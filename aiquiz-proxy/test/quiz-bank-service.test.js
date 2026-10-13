const test = require('node:test');
const assert = require('node:assert/strict');

const {
    canonicalizeQuiz,
    mergeCandidate,
    mergeEvaluation,
    normalizeQuestion,
    questionId,
    reusableRecord,
} = require('../quiz-bank-service');

function quiz(overrides = {}) {
    return {
        q: '  3 ＋ 4 は？ ',
        c: ['5', '7', '8', '9'],
        a: 1,
        e: '3と4を足します。',
        subject: '算数',
        grade: 1,
        difficulty: '普通',
        src: 'GEMINI_STREAM',
        genre: 'たし算',
        estimated_seconds: 3.2,
        ...overrides,
    };
}

test('question identity ignores Japanese/full-width spacing differences', () => {
    assert.equal(normalizeQuestion(' ３　＋ ４ は？ '), normalizeQuestion('3+4は?'));
    assert.equal(
        questionId('算数', 1, ' ３　＋ ４ は？ '),
        questionId('算数', 1, '3+4は?'),
    );
});

test('canonicalize validates the offline-bank contract', () => {
    const item = canonicalizeQuiz(quiz());
    assert.equal(item.q, '3 ＋ 4 は？');
    assert.equal(item.grade, 1);
    assert.equal(item.original_src, 'GEMINI_STREAM');
    assert.equal(item.c.length, 4);

    assert.throws(() => canonicalizeQuiz(quiz({ c: ['7', '7'], a: 0 })), /Duplicate choices/);
    assert.throws(() => canonicalizeQuiz(quiz({ a: 9 })), /answer index/);
    assert.throws(() => canonicalizeQuiz(quiz({ src: 'OFFLINE' })), /online source/);
    assert.throws(() => canonicalizeQuiz(quiz({ q: 'あ'.repeat(61) })), /Invalid q/);
});

test('candidate upserts are idempotent by id and retain terminal status', () => {
    const item = canonicalizeQuiz(quiz());
    const first = mergeCandidate(null, item, 100);
    const second = mergeCandidate(first, item, 120);
    assert.equal(second.first_seen, 100);
    assert.equal(second.last_seen, 120);
    assert.equal(second.seen_count, 2);
    assert.equal(second.status, 'pending');
});

test('bad always wins and later good evaluations cannot reactivate it', () => {
    const item = canonicalizeQuiz(quiz());
    const good = mergeEvaluation(null, item, true, 'ok', 100);
    assert.equal(good.status, 'good');
    assert.equal(good.seen_count, 1);
    assert.equal(reusableRecord(good).src, 'OFFLINE_FIREBASE');

    const bad = mergeEvaluation(good, item, false, 'ambiguous', 110);
    assert.equal(bad.status, 'bad');
    assert.equal(bad.bad_ever, true);
    assert.equal(bad.seen_count, 1);

    const laterGood = mergeEvaluation(bad, item, true, 'retry', 120);
    assert.equal(laterGood.status, 'bad');
    assert.equal(laterGood.bad_ever, true);
});

test('English and reused pool questions can enter the shared archive', () => {
    const english = canonicalizeQuiz(quiz({
        q: 'What color is the sky?', c: ['blue', 'red'], a: 0, subject: '英語', grade: 3,
    }));
    assert.equal(english.subject, '英語');
    assert.equal(canonicalizeQuiz(quiz({ src: 'GEMINI_POOL' })).original_src, 'GEMINI_POOL');
});

test('with review required, client good votes are counted but do not promote', () => {
    const item = canonicalizeQuiz(quiz());
    const voted = mergeEvaluation(null, item, true, 'ok', 100, { requireReview: true });
    assert.equal(voted.status, 'pending');
    assert.equal(voted.good_votes, 1);

    const again = mergeEvaluation(voted, item, true, 'ok', 110, { requireReview: true });
    assert.equal(again.status, 'pending');
    assert.equal(again.good_votes, 2);

    const rejected = mergeEvaluation(again, item, false, 'wrong', 120, { requireReview: true });
    assert.equal(rejected.status, 'bad');
    assert.equal(rejected.bad_ever, true);

    // 既に good の問題（確認合格・従来の昇格分）は good のまま
    const reviewedGood = { ...voted, status: 'good' };
    assert.equal(mergeEvaluation(reviewedGood, item, true, 'ok', 130, { requireReview: true }).status, 'good');
});

test('client uploads cannot change the content of a question sent for review', () => {
    const item = canonicalizeQuiz(quiz());
    const reviewed = { ...mergeCandidate(null, item, 100), review: { state: 'done', verdict: 'pass' } };
    const tampered = canonicalizeQuiz(quiz({ a: 2, e: '別の解説' }));
    const merged = mergeCandidate(reviewed, tampered, 110);
    assert.equal(merged.a, 1);
    assert.equal(merged.e, '3と4を足します。');
    assert.equal(merged.seen_count, 2);
});
