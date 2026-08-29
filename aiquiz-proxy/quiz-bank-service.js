const crypto = require('crypto');
const express = require('express');
const { applicationDefault, getApps, initializeApp } = require('firebase-admin/app');
const { getDatabase } = require('firebase-admin/database');

const SUBJECTS = new Set(['国語', '算数', '理科', '社会']);
const DIFFICULTIES = new Set(['簡単', '普通', '難しい']);
const ONLINE_SOURCES = new Set(['GEMINI', 'GEMINI_STREAM', 'OPENAI']);
const MAX_BATCH = 50;
const MAX_PAGE = 500;

function normalizeQuestion(text) {
    return String(text || '')
        .normalize('NFKC')
        .trim()
        .toLocaleLowerCase('ja-JP')
        .replace(/[\s\u3000]+/g, '');
}

function questionId(subject, grade, question) {
    const identity = `${subject}\u0000${grade}\u0000${normalizeQuestion(question)}`;
    return crypto.createHash('sha256').update(identity, 'utf8').digest('hex');
}

function cleanText(value, maxLength, fieldName, allowEmpty = false) {
    const text = String(value ?? '').trim();
    if ((!allowEmpty && !text) || text.length > maxLength || text.includes('\uFFFD')) {
        throw new Error(`Invalid ${fieldName}`);
    }
    return text;
}

function canonicalizeQuiz(raw, { allowOffline = false } = {}) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
        throw new Error('Quiz must be an object');
    }

    const subject = cleanText(raw.subject, 10, 'subject');
    const grade = Number(raw.grade);
    const difficulty = cleanText(raw.difficulty, 10, 'difficulty');
    const q = cleanText(raw.q, 60, 'q');
    const e = cleanText(raw.e ?? '', 600, 'e', true);
    const src = cleanText(raw.src || 'GEMINI', 32, 'src').toUpperCase();

    if (!SUBJECTS.has(subject)) throw new Error('Invalid subject');
    if (!Number.isInteger(grade) || grade < 1 || grade > 6) throw new Error('Invalid grade');
    if (!DIFFICULTIES.has(difficulty)) throw new Error('Invalid difficulty');
    if (!allowOffline && !ONLINE_SOURCES.has(src)) throw new Error('Invalid online source');
    if (!Array.isArray(raw.c) || (raw.c.length !== 2 && raw.c.length !== 4)) {
        throw new Error('Choices must contain 2 or 4 items');
    }

    const c = raw.c.map((choice, index) => cleanText(choice, 20, `c[${index}]`));
    const normalizedChoices = c.map(normalizeQuestion);
    if (new Set(normalizedChoices).size !== c.length) throw new Error('Duplicate choices');

    const a = Number(raw.a);
    if (!Number.isInteger(a) || a < 0 || a >= c.length) throw new Error('Invalid answer index');

    const estimated = Number(raw.estimated_seconds ?? raw.t ?? 4.0);
    const estimatedSeconds = Number.isFinite(estimated)
        ? Math.min(10.0, Math.max(1.5, estimated))
        : 4.0;
    const genre = cleanText(raw.genre ?? raw.g ?? '', 80, 'genre', true);
    const id = questionId(subject, grade, q);

    return {
        id,
        q,
        c,
        a,
        e,
        subject,
        grade,
        difficulty,
        original_src: src,
        genre,
        estimated_seconds: estimatedSeconds,
    };
}

function mergeCandidate(existing, quiz, nowSeconds) {
    const prior = existing && typeof existing === 'object' ? existing : {};
    const status = prior.bad_ever ? 'bad' : (prior.status || 'pending');
    return {
        ...prior,
        ...quiz,
        status,
        bad_ever: Boolean(prior.bad_ever),
        first_seen: Number(prior.first_seen || nowSeconds),
        last_seen: nowSeconds,
        seen_count: Number(prior.seen_count || 0) + 1,
    };
}

function mergeEvaluation(existing, quiz, good, reason, nowSeconds) {
    const candidate = mergeCandidate(existing, quiz, nowSeconds);
    // Evaluations are not new generation sightings. Preserve the generation
    // count when the candidate was already archived.
    if (existing && typeof existing === 'object') {
        candidate.seen_count = Number(existing.seen_count || 0);
    }
    const badEver = Boolean(candidate.bad_ever) || !good;
    return {
        ...candidate,
        status: badEver ? 'bad' : 'good',
        bad_ever: badEver,
        last_evaluated: nowSeconds,
        evaluation_reason: String(reason || '').slice(0, 500),
    };
}

function reusableRecord(archive) {
    return {
        q: archive.q,
        c: archive.c,
        a: archive.a,
        e: archive.e || '',
        subject: archive.subject,
        grade: archive.grade,
        difficulty: archive.difficulty,
        src: 'OFFLINE_FIREBASE',
        genre: archive.genre || '',
        estimated_seconds: archive.estimated_seconds || 4.0,
        updated_at: archive.last_evaluated || archive.last_seen || 0,
    };
}

function parseBatch(body, name) {
    let parsed;
    try {
        parsed = typeof body === 'string' ? JSON.parse(body) : body;
    } catch (_error) {
        throw new Error('Invalid JSON');
    }
    const items = parsed && parsed[name];
    if (!Array.isArray(items) || items.length < 1 || items.length > MAX_BATCH) {
        throw new Error(`${name} must contain 1-${MAX_BATCH} items`);
    }
    return items;
}

function createFirebaseDatabase() {
    const databaseURL = process.env.FIREBASE_DB_URL || '';
    const projectId = process.env.FIREBASE_PROJECT_ID || '';
    if (!databaseURL) throw new Error('FIREBASE_DB_URL is not configured');
    if (!projectId) throw new Error('FIREBASE_PROJECT_ID is not configured');
    if (!getApps().length) {
        // Cloud Run and Firebase live in separate Google Cloud projects. Pin the
        // Firebase target explicitly while using the Cloud Run service account's
        // ADC credentials (granted access on the Firebase project).
        initializeApp({ credential: applicationDefault(), databaseURL, projectId });
    }
    return getDatabase();
}

class FirebaseQuizBankService {
    constructor(databaseFactory = createFirebaseDatabase) {
        this.databaseFactory = databaseFactory;
    }

    _db() {
        return this.databaseFactory();
    }

    async _bumpRevision(db) {
        const result = await db.ref('quiz_bank/v1/meta/revision').transaction(
            current => Number(current || 0) + 1,
        );
        return Number(result.snapshot.val() || 0);
    }

    async archiveCandidates(rawItems) {
        const now = Math.floor(Date.now() / 1000);
        const quizzes = rawItems.map(raw => canonicalizeQuiz(raw));
        const db = this._db();
        await Promise.all(quizzes.map(quiz =>
            db.ref(`quiz_archive/v1/items/${quiz.id}`).transaction(
                current => mergeCandidate(current, quiz, now),
            ),
        ));
        return { accepted: quizzes.length, ids: quizzes.map(quiz => quiz.id) };
    }

    async recordEvaluations(rawEvaluations) {
        const now = Math.floor(Date.now() / 1000);
        const db = this._db();
        let bankChanged = false;
        const results = [];

        for (const raw of rawEvaluations) {
            if (typeof raw.good !== 'boolean') throw new Error('Evaluation good must be boolean');
            const source = String(raw.src || '').trim().toUpperCase();
            const isOnline = ONLINE_SOURCES.has(source);
            const isCachedBankItem = source === 'OFFLINE_FIREBASE';
            const isManagedBankItem = isOnline || isCachedBankItem;
            const quiz = canonicalizeQuiz(raw, { allowOffline: !isOnline });
            const reason = String(raw.reason || '').slice(0, 500);
            let status = 'rating_only';
            if (isManagedBankItem) {
                const archiveRef = db.ref(`quiz_archive/v1/items/${quiz.id}`);
                if (isCachedBankItem && !(await archiveRef.once('value')).exists()) {
                    throw new Error('Unknown OFFLINE_FIREBASE quiz');
                }
                const transaction = await archiveRef.transaction(
                    current => mergeEvaluation(current, quiz, raw.good, reason, now),
                );
                const archive = transaction.snapshot.val();
                const bankRef = db.ref(`quiz_bank/v1/items/${quiz.id}`);
                if (archive.status === 'good') {
                    await bankRef.set(reusableRecord(archive));
                } else {
                    await bankRef.remove();
                }
                status = archive.status;
                bankChanged = true;
            }

            const eventId = /^[A-Za-z0-9_-]{16,160}$/.test(String(raw.event_id || ''))
                ? String(raw.event_id)
                : crypto.createHash('sha256')
                    .update(`${quiz.id}\u0000${raw.good}\u0000${now}\u0000${reason}`)
                    .digest('hex');
            await db.ref(`quiz_ratings/shared/${eventId}`).set({
                q: quiz.q,
                c: quiz.c,
                a: quiz.a,
                e: quiz.e,
                good: raw.good,
                subject: quiz.subject,
                grade: quiz.grade,
                difficulty: quiz.difficulty,
                src: quiz.original_src,
                reason,
                ts: now,
            });
            results.push({ id: quiz.id, status });
        }

        const revision = bankChanged ? await this._bumpRevision(db) : 0;
        return { accepted: results.length, revision, results };
    }

    async snapshot({ cursor = '', limit = 200, expectedRevision = 0 } = {}) {
        const db = this._db();
        const metaRef = db.ref('quiz_bank/v1/meta/revision');
        const before = Number((await metaRef.once('value')).val() || 0);
        if (expectedRevision && expectedRevision !== before) {
            const error = new Error('revision_changed');
            error.statusCode = 409;
            throw error;
        }

        const pageSize = Math.min(MAX_PAGE, Math.max(1, Number(limit) || 200));
        let query = db.ref('quiz_bank/v1/items').orderByKey();
        if (cursor) query = query.startAt(cursor);
        query = query.limitToFirst(pageSize + (cursor ? 2 : 1));
        const value = (await query.once('value')).val() || {};
        let entries = Object.entries(value).sort(([a], [b]) => a.localeCompare(b));
        if (cursor && entries.length && entries[0][0] === cursor) entries = entries.slice(1);
        const hasMore = entries.length > pageSize;
        entries = entries.slice(0, pageSize);

        const after = Number((await metaRef.once('value')).val() || 0);
        if (after !== before) {
            const error = new Error('revision_changed');
            error.statusCode = 409;
            throw error;
        }

        return {
            version: 1,
            revision: before,
            items: entries.map(([id, item]) => ({ id, ...item })),
            next_cursor: hasMore && entries.length ? entries[entries.length - 1][0] : '',
        };
    }
}

function createQuizBankRouter(service = new FirebaseQuizBankService()) {
    const router = express.Router();

    router.post('/candidates', async (req, res) => {
        try {
            const result = await service.archiveCandidates(parseBatch(req.body, 'items'));
            res.status(200).json(result);
        } catch (error) {
            res.status(400).json({ error: error.message });
        }
    });

    router.post('/evaluations', async (req, res) => {
        try {
            const result = await service.recordEvaluations(parseBatch(req.body, 'evaluations'));
            res.status(200).json(result);
        } catch (error) {
            res.status(400).json({ error: error.message });
        }
    });

    router.get('/snapshot', async (req, res) => {
        try {
            const result = await service.snapshot({
                cursor: String(req.query.cursor || ''),
                limit: Number(req.query.limit || 200),
                expectedRevision: Number(req.query.revision || 0),
            });
            res.setHeader('ETag', `\"${result.revision}\"`);
            res.status(200).json(result);
        } catch (error) {
            res.status(error.statusCode || 500).json({ error: error.message });
        }
    });

    return router;
}

module.exports = {
    FirebaseQuizBankService,
    canonicalizeQuiz,
    createQuizBankRouter,
    mergeCandidate,
    mergeEvaluation,
    normalizeQuestion,
    questionId,
    reusableRecord,
};
