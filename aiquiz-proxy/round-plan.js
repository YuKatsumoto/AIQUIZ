// ラウンドごとの「新作の数」（フェーズ C1）。
//
// Gemini の請求を月の上限（GEMINI_MONTHLY_BUDGET_USD）に収めるため、全体の使用ペースと
// その端末の今日の何試合目かから、10 問のうち何問を Gemini で新しく作るかを決める。
// 残りはゲームが共有バンク・端末内の問題プール・同梱の問題で埋める。
// 各端末のその日の最初の PRIORITY_ROUNDS 試合は、予算が苦しくても新作を多めにする。

const PRIORITY_ROUNDS = 2;

// ペース → [その日の最初の試合, それ以降] の新作の数（10 問中）
const NEW_COUNT_TABLE = {
    green: [10, 10],
    yellow: [10, 3],
    orange: [6, 0],
    red: [3, 0],
    stop: [0, 0],
};

function newCountFor(level, roundIndex) {
    const row = NEW_COUNT_TABLE[level] || NEW_COUNT_TABLE.stop;
    return roundIndex <= PRIORITY_ROUNDS ? row[0] : row[1];
}

module.exports = { NEW_COUNT_TABLE, PRIORITY_ROUNDS, newCountFor };
