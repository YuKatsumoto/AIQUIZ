// 段階2: 管理ソフトからの操作（本番を書き換える）。
//   端末・回線のブロックと解除 … device_blocklist/v1/{iid または ipKey}（プロキシが 1 分ごとに読み直す）
//   問題を共有バンクから外す・戻す … quiz_bank/v1/items と removed（差分同期で各端末からも消える）
//   夜のジョブを今すぐ動かす … Cloud Run Jobs の :run
// どの操作も ops_log/v1 に「いつ・誰が・何を」を残す。
const os = require('os');
const { BLOCKLIST_PATH, putBankItem, removeBankItem } = require('./proxy-shared');

const OPS_LOG_PATH = 'ops_log/v1';
const BANK_ITEMS_PATH = 'quiz_bank/v1/items';
const ARCHIVE_ITEMS_PATH = 'quiz_archive/v1/items';
const REVISION_PATH = 'quiz_bank/v1/meta/revision';

const DEVICE_ID = /^[0-9a-f]{32}$/;
const IP_KEY = /^[A-Za-z0-9_-]{8,64}$/;
const QUESTION_ID = /^[A-Za-z0-9_-]{1,128}$/;

class ActionError extends Error {
    constructor(message, status = 400) {
        super(message);
        this.status = status;
    }
}

function reasonOf(value) {
    return String(value || '').trim().slice(0, 200);
}

function blockKind(key) {
    if (DEVICE_ID.test(key)) return 'device';
    if (IP_KEY.test(key)) return 'ip';
    return null;
}

class OpsActions {
    constructor({ db, gcpRequest, jobs, runUrl, now = () => new Date(), actor = defaultActor(), onBankChange = () => {} }) {
        this.db = db;
        this.gcpRequest = gcpRequest;
        this.jobs = jobs;
        this.runUrl = runUrl;
        this.now = now;
        this.actor = actor;
        this.onBankChange = onBankChange;
    }

    _nowSec() {
        return Math.floor(this.now().getTime() / 1000);
    }

    async _log(action, target, detail = {}) {
        await this.db.ref(OPS_LOG_PATH).push({ at: this._nowSec(), by: this.actor, action, target, ...detail });
    }

    // ---- ブロック ----

    async block({ kind, key, reason } = {}) {
        key = String(key || '').trim();
        if (!['device', 'ip'].includes(kind)) throw new ActionError('kind は device か ip です');
        if (blockKind(key) !== kind) {
            throw new ActionError(kind === 'device' ? '端末の ID（32 桁の英数字）ではありません' : '回線の値ではありません');
        }
        const ref = this.db.ref(`${BLOCKLIST_PATH}/${key}`);
        if ((await ref.once('value')).val()) throw new ActionError('すでにブロックしています', 409);
        const entry = { kind, reason: reasonOf(reason), at: this._nowSec(), by: this.actor };
        await ref.set(entry);
        await this._log('block', key, { kind, reason: entry.reason });
        return entry;
    }

    async unblock({ key } = {}) {
        key = String(key || '').trim();
        if (!blockKind(key)) throw new ActionError('ID の形が正しくありません');
        const ref = this.db.ref(`${BLOCKLIST_PATH}/${key}`);
        const current = (await ref.once('value')).val();
        if (!current) throw new ActionError('ブロックしていません', 404);
        await ref.remove();
        await this._log('unblock', key, { kind: (current && current.kind) || blockKind(key) });
        return { key };
    }

    // ---- 問題 ----

    async removeQuestion({ id, reason } = {}) {
        id = String(id || '').trim();
        if (!QUESTION_ID.test(id)) throw new ActionError('問題の ID の形が正しくありません');
        const bankItem = (await this.db.ref(`${BANK_ITEMS_PATH}/${id}`).once('value')).val();
        if (!bankItem) throw new ActionError('共有バンクにない問題です', 404);
        const nowSec = this._nowSec();
        const why = reasonOf(reason);
        // アーカイブ側も「不合格」にして、判定や投票でバンクに戻らないようにする。戻すときのために前の状態を残す
        await this.db.ref(`${ARCHIVE_ITEMS_PATH}/${id}`).transaction(item => {
            if (!item) return item;
            return {
                ...item,
                status: 'bad',
                bad_ever: true,
                last_evaluated: nowSec,
                evaluation_reason: `ops: ${why || '管理ソフトで外した'}`,
                ops_removed: {
                    at: nowSec,
                    by: this.actor,
                    reason: why,
                    prev_status: item.status || null,
                    prev_bad_ever: Boolean(item.bad_ever),
                    prev_reason: item.evaluation_reason || null,
                },
            };
        });
        await removeBankItem(this.db, id, this.now().getTime());
        await this.db.ref(REVISION_PATH).transaction(current => Number(current || 0) + 1);
        await this._log('remove_question', id, { reason: why, q: String(bankItem.q || '').slice(0, 120) });
        this.onBankChange({ type: 'removed', id });
        return { id, q: bankItem.q };
    }

    async restoreQuestion({ id } = {}) {
        id = String(id || '').trim();
        if (!QUESTION_ID.test(id)) throw new ActionError('問題の ID の形が正しくありません');
        const archiveRef = this.db.ref(`${ARCHIVE_ITEMS_PATH}/${id}`);
        const current = (await archiveRef.once('value')).val();
        if (!current || !current.ops_removed) throw new ActionError('管理ソフトで外した問題だけ戻せます', 404);
        const nowSec = this._nowSec();
        const result = await archiveRef.transaction(item => {
            if (!item || !item.ops_removed) return item;
            const prev = item.ops_removed;
            const next = {
                ...item,
                status: 'good',
                bad_ever: Boolean(prev.prev_bad_ever),
                last_evaluated: nowSec,
                evaluation_reason: prev.prev_reason || 'ops: 管理ソフトで戻した',
            };
            delete next.ops_removed;
            return next;
        });
        const restored = result.snapshot.val();
        await putBankItem(this.db, id, restored, this.now().getTime());
        await this.db.ref(REVISION_PATH).transaction(value => Number(value || 0) + 1);
        await this._log('restore_question', id, { q: String(restored.q || '').slice(0, 120) });
        this.onBankChange({ type: 'restored', id, archive: restored });
        return { id, q: restored.q };
    }

    // ---- 夜のジョブ ----

    async runJob({ name } = {}) {
        const job = this.jobs.find(j => j.name === name);
        if (!job) throw new ActionError('知らないジョブです');
        const operation = await this.gcpRequest(this.runUrl(`jobs/${job.name}:run`), { method: 'POST', data: {} });
        const execution = String(((operation && operation.metadata) || {}).name || (operation && operation.name) || '')
            .split('/').pop();
        await this._log('run_job', job.name, { execution });
        return { name: job.name, execution };
    }

    // ---- 記録 ----

    async recentLog(limit = 50) {
        const value = (await this.db.ref(OPS_LOG_PATH).orderByKey().limitToLast(limit).once('value')).val() || {};
        return Object.entries(value).map(([key, entry]) => ({ key, ...entry })).reverse();
    }
}

function defaultActor() {
    try {
        return `${os.userInfo().username}@${os.hostname()}`;
    } catch (_e) {
        return os.hostname();
    }
}

module.exports = { ActionError, OPS_LOG_PATH, OpsActions, blockKind };
