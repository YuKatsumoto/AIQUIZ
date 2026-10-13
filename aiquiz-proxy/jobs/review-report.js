// 確認結果の一覧を出す: `node jobs/review-report.js <batch_id>`
// batch_id を省くと、いちばん新しい回収済みの Batch を出す。1行1問の JSON をログに書く。
const { createFirebaseDatabase } = require('../quiz-bank-service');

async function main() {
    const db = createFirebaseDatabase();
    let batchId = process.argv[2] || '';
    const batches = (await db.ref('quiz_review/v1/batches').once('value')).val() || {};
    if (!batchId) {
        const collected = Object.entries(batches)
            .filter(([, b]) => b && b.state === 'collected')
            .sort(([, a], [, b]) => Number(b.collected_at || 0) - Number(a.collected_at || 0));
        if (!collected.length) throw new Error('no collected batch');
        batchId = collected[0][0];
    }
    const record = batches[batchId];
    if (!record) throw new Error(`unknown batch ${batchId}`);
    const rows = [];
    for (const id of Object.keys(record.ids || {})) {
        const item = (await db.ref(`quiz_archive/v1/items/${id}`).once('value')).val() || {};
        const review = item.review || {};
        rows.push({
            type: 'claude_review_item',
            batch_id: batchId,
            id,
            verdict: review.verdict || review.state || 'unknown',
            status: item.status,
            subject: item.subject,
            grade: item.grade,
            difficulty: item.difficulty,
            q: item.q,
            c: item.c,
            a: item.a,
            claude_answer: review.answer,
            issues: review.issues || [],
            confidence: review.confidence,
            note: review.note || review.error || '',
            good_votes: item.good_votes || 0,
        });
    }
    for (const row of rows) console.log(JSON.stringify(row));
    console.log(JSON.stringify({
        type: 'claude_review_report', batch_id: batchId, count: rows.length, usd: record.usd,
    }));
}

main().then(() => process.exit(0), error => {
    console.error(JSON.stringify({ type: 'claude_review_error', error: error.message }));
    process.exit(1);
});
