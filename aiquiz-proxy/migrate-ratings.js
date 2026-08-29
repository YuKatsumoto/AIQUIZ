const fs = require('fs');
const path = require('path');
const { applicationDefault, deleteApp, initializeApp } = require('firebase-admin/app');
const { getDatabase } = require('firebase-admin/database');
const {
    canonicalizeQuiz,
    mergeCandidate,
    normalizeQuestion,
    reusableRecord,
} = require('./quiz-bank-service');

const APPLY = process.argv.includes('--apply');
const databaseURL = process.env.FIREBASE_DB_URL || '';
const projectId = process.env.FIREBASE_PROJECT_ID || 'aiquiz-a12f6';
const offlinePath = process.env.OFFLINE_BANK_PATH
    || path.resolve(__dirname, '..', 'AIQUIZ-Godot', 'offline_bank.json');

if (!databaseURL) {
    console.error('FIREBASE_DB_URL is required. Dry-run and apply both read the live ratings path.');
    process.exit(2);
}

const firebaseApp = initializeApp({ credential: applicationDefault(), databaseURL, projectId });
const db = getDatabase(firebaseApp);

function collectOfflineQuestions(bank) {
    const result = new Set();
    for (const grades of Object.values(bank || {})) {
        if (!grades || typeof grades !== 'object') continue;
        for (const items of Object.values(grades)) {
            if (!Array.isArray(items)) continue;
            for (const item of items) {
                if (item && item.q) result.add(normalizeQuestion(item.q));
            }
        }
    }
    return result;
}

function buildMigration(ratingObject, offlineQuestions, existingArchive = {}) {
    const grouped = new Map();
    let invalid = 0;
    let offlineSource = 0;

    for (const raw of Object.values(ratingObject || {})) {
        const source = String(raw && raw.src || '').toUpperCase();
        if (source.startsWith('OFFLINE')) {
            offlineSource += 1;
            continue;
        }
        try {
            const quiz = canonicalizeQuiz(raw);
            const current = grouped.get(quiz.id) || {
                quiz,
                first_seen: Number(raw.ts || 0),
                last_seen: Number(raw.ts || 0),
                seen_count: 0,
                bad_ever: false,
                last_reason: '',
            };
            current.seen_count += 1;
            current.first_seen = Math.min(current.first_seen || Number(raw.ts || 0), Number(raw.ts || 0));
            if (Number(raw.ts || 0) >= current.last_seen) {
                current.last_seen = Number(raw.ts || 0);
                current.quiz = quiz;
                current.last_reason = String(raw.reason || raw.comment || '');
            }
            if (raw.good !== true) current.bad_ever = true;
            grouped.set(quiz.id, current);
        } catch (_error) {
            invalid += 1;
        }
    }

    const archive = new Map();
    const reusable = new Map();
    let good = 0;
    let bad = 0;
    let builtInOverlap = 0;

    for (const [id, entry] of grouped) {
        const prior = existingArchive[id] || null;
        let record = mergeCandidate(prior, entry.quiz, entry.last_seen || Math.floor(Date.now() / 1000));
        record.first_seen = prior && prior.first_seen
            ? prior.first_seen
            : entry.first_seen;
        record.seen_count = Math.max(Number(prior && prior.seen_count || 0), entry.seen_count);
        record.bad_ever = Boolean(prior && prior.bad_ever) || entry.bad_ever;
        record.status = record.bad_ever ? 'bad' : 'good';
        record.last_evaluated = entry.last_seen;
        record.evaluation_reason = entry.last_reason.slice(0, 500);
        archive.set(id, record);

        if (record.status === 'bad') {
            bad += 1;
            continue;
        }
        good += 1;
        if (offlineQuestions.has(normalizeQuestion(record.q))) {
            builtInOverlap += 1;
            continue;
        }
        reusable.set(id, reusableRecord(record));
    }

    return { archive, reusable, stats: {
        source_rows: Object.keys(ratingObject || {}).length,
        unique_online: grouped.size,
        good,
        bad,
        invalid,
        offline_source: offlineSource,
        built_in_overlap: builtInOverlap,
        reusable: reusable.size,
    } };
}

async function applyMigration(migration) {
    const updates = {};
    for (const [id, record] of migration.archive) {
        updates[`quiz_archive/v1/items/${id}`] = record;
        updates[`quiz_bank/v1/items/${id}`] = migration.reusable.get(id) || null;
    }

    const entries = Object.entries(updates);
    for (let offset = 0; offset < entries.length; offset += 400) {
        await db.ref().update(Object.fromEntries(entries.slice(offset, offset + 400)));
        console.log(`Applied ${Math.min(offset + 400, entries.length)}/${entries.length} paths`);
    }
    await db.ref('quiz_bank/v1/meta/revision').transaction(current => Number(current || 0) + 1);
}

async function main() {
    const bank = JSON.parse(fs.readFileSync(offlinePath, 'utf8'));
    const [ratings, existingArchive] = await Promise.all([
        db.ref('quiz_ratings/shared').once('value'),
        db.ref('quiz_archive/v1/items').once('value'),
    ]);
    const migration = buildMigration(
        ratings.val() || {},
        collectOfflineQuestions(bank),
        existingArchive.val() || {},
    );
    console.log(JSON.stringify({ mode: APPLY ? 'apply' : 'dry-run', ...migration.stats }, null, 2));
    if (APPLY) {
        await applyMigration(migration);
        console.log('Migration complete. No LLM APIs were called.');
    } else {
        console.log('Dry-run only. Re-run with --apply after the proxy deployment is verified.');
    }
}

main()
    .catch(error => {
        console.error(error.message);
        process.exitCode = 1;
    })
    .finally(async () => {
        await deleteApp(firebaseApp).catch(() => {});
    });
