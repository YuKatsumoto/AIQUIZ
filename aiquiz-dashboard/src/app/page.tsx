"use client";

import { useEffect, useState } from 'react';
import { db } from '../lib/firebase';
import { ref, get } from 'firebase/database';
import Link from 'next/link';

interface RatingEntry {
  good: boolean;
  subject?: string;
  grade?: number;
  difficulty?: string;
  ts?: number;
  q?: string;
  src?: string;
}

type HealthState = 'ok' | 'warn' | 'error' | 'pending';

function healthClass(state: HealthState) {
  return `health-item health-item--${state === 'ok' ? 'ok' : state === 'warn' ? 'warn' : state === 'error' ? 'error' : 'pending'}`;
}

function HealthCard({ label, value, state, icon }: { label: string; value: string; state: HealthState; icon: string }) {
  const iconClass = `health-icon health-icon--${state === 'ok' ? 'ok' : state === 'warn' ? 'warn' : state === 'error' ? 'error' : 'pending'}`;
  const valueClass = `health-value${state !== 'pending' ? ` health-value--${state === 'ok' ? 'ok' : state === 'warn' ? 'warn' : 'error'}` : ''}`;
  return (
    <div className={healthClass(state)}>
      <div className={iconClass}>{icon}</div>
      <div>
        <div className="health-label">{label}</div>
        <div className={valueClass}>{value}</div>
      </div>
    </div>
  );
}

export default function Home() {
  const [offlineCount, setOfflineCount] = useState(0);
  const [ratingCount, setRatingCount] = useState(0);
  const [subjectStats, setSubjectStats] = useState<Record<string, number>>({});
  const [goodRatings, setGoodRatings] = useState(0);
  const [gradeStats, setGradeStats] = useState<Record<string, number>>({});
  const [difficultyStats, setDifficultyStats] = useState<Record<string, { good: number; bad: number }>>({});
  const [recentItems, setRecentItems] = useState<RatingEntry[]>([]);
  const [firebaseOk, setFirebaseOk] = useState<boolean | null>(null);
  const [envStatus, setEnvStatus] = useState<Record<string, string> | null>(null);
  const [loading, setLoading] = useState(true);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);

  useEffect(() => {
    fetch('/api/offline-bank')
      .then(res => res.json())
      .then(data => {
        if (!data.error) {
          let count = 0;
          const stats: Record<string, number> = {};
          const gStats: Record<string, number> = {};
          for (const subject in data) {
            stats[subject] = 0;
            for (const grade in data[subject]) {
              const num = data[subject][grade].length;
              count += num;
              stats[subject] += num;
              const gKey = `${grade}年生`;
              gStats[gKey] = (gStats[gKey] || 0) + num;
            }
          }
          setOfflineCount(count);
          setSubjectStats(stats);
          setGradeStats(gStats);
        }
      });

    fetch('/api/env')
      .then(res => res.json())
      .then(data => {
        if (!data.error) setEnvStatus(data);
      })
      .catch(() => setEnvStatus(null));

    const ratingsRef = ref(db, 'quiz_ratings/shared');
    get(ratingsRef).then((snapshot) => {
      if (snapshot.exists()) {
        const data = snapshot.val();
        const arr = Object.values<RatingEntry>(data);
        setRatingCount(arr.length);
        setGoodRatings(arr.filter(r => r.good).length);
        setFirebaseOk(true);

        const diffDist: Record<string, { good: number; bad: number }> = {};
        arr.forEach(r => {
          const diff = r.difficulty || '不明';
          if (!diffDist[diff]) diffDist[diff] = { good: 0, bad: 0 };
          if (r.good) diffDist[diff].good++;
          else diffDist[diff].bad++;
        });
        setDifficultyStats(diffDist);

        const sorted = [...arr]
          .filter(r => r.ts)
          .sort((a, b) => (b.ts || 0) - (a.ts || 0))
          .slice(0, 5);
        setRecentItems(sorted);
      } else {
        setFirebaseOk(true);
      }
      setLoading(false);
      setLastUpdated(new Date());
    }).catch(() => {
      setFirebaseOk(false);
      setLoading(false);
      setLastUpdated(new Date());
    });
  }, []);

  const goodRatio = ratingCount > 0 ? Math.round((goodRatings / ratingCount) * 100) : 0;
  const badRatings = ratingCount - goodRatings;
  const maxSubjectCount = Math.max(...Object.values(subjectStats), 1);

  const hasProxyUrl = envStatus && Object.keys(envStatus).some(k => k === 'PROXY_URL');
  const hasFirebaseUrl = envStatus && Object.keys(envStatus).some(k => k === 'FIREBASE_DB_URL');

  const firebaseState: HealthState = firebaseOk === null ? 'pending' : firebaseOk ? 'ok' : 'error';
  const proxyState: HealthState = hasProxyUrl ? 'ok' : 'warn';
  const dbUrlState: HealthState = hasFirebaseUrl ? 'ok' : 'warn';
  const offlineState: HealthState = offlineCount > 0 ? 'ok' : 'error';

  const formattedTime = lastUpdated
    ? lastUpdated.toLocaleString('ja-JP', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
    : null;

  return (
    <div className={`dashboard animate-fade${loading ? ' dashboard-loading' : ''}`}>
      <header className="dashboard-hero">
        <div className="dashboard-hero-text">
          <h2 className="heading">AIQUIZ ダッシュボード</h2>
          <p className="subheading" style={{ marginBottom: 0 }}>
            システム稼働状況とデータリポジトリをひと目で把握できます。
          </p>
        </div>
        <div className="dashboard-hero-meta">
          {!loading && firebaseOk && (
            <span className="dashboard-badge dashboard-badge--live">システム稼働中</span>
          )}
          {formattedTime && (
            <span className="dashboard-timestamp">最終更新 {formattedTime}</span>
          )}
        </div>
      </header>

      <section className="health-grid" aria-label="システムヘルス">
        {loading ? (
          <>
            {[1, 2, 3, 4].map(i => (
              <div key={i} className="skeleton skeleton-stat" style={{ height: '72px' }} />
            ))}
          </>
        ) : (
          <>
            <HealthCard
              label="Firebase"
              value={firebaseOk === null ? 'チェック中' : firebaseOk ? '接続 OK' : '接続失敗'}
              state={firebaseState}
              icon={firebaseOk ? '✓' : firebaseOk === false ? '✕' : '…'}
            />
            <HealthCard
              label="Proxy Server"
              value={hasProxyUrl ? '設定済' : '未設定'}
              state={proxyState}
              icon="⚡"
            />
            <HealthCard
              label="Firebase DB URL"
              value={hasFirebaseUrl ? '設定済' : '未設定'}
              state={dbUrlState}
              icon="🔗"
            />
            <HealthCard
              label="オフライン問題庫"
              value={offlineCount > 0 ? `${offlineCount.toLocaleString()} 問` : '空'}
              state={offlineState}
              icon="📦"
            />
          </>
        )}
      </section>

      <section className="grid-4" style={{ marginBottom: '1.5rem' }} aria-label="主要指標">
        {loading ? (
          [1, 2, 3, 4].map(i => <div key={i} className="skeleton skeleton-stat" />)
        ) : (
          <>
            <div className="stat-card stat-card--primary">
              <div className="stat-card-header">
                <div className="stat-icon" style={{ color: 'var(--primary-light)' }}>🧠</div>
                {ratingCount > 0 && <span className="stat-trend stat-trend--up">蓄積中</span>}
              </div>
              <div className="stat-value">{ratingCount.toLocaleString()}</div>
              <div className="stat-label">AI評価データ</div>
              {ratingCount > 0 && (
                <div className="rating-summary">
                  <span className="rating-summary-item">GOOD<strong>{goodRatings}</strong></span>
                  <span className="rating-summary-item">BAD<strong>{badRatings}</strong></span>
                </div>
              )}
            </div>

            <div className="stat-card stat-card--success">
              <div className="stat-card-header">
                <div className="stat-icon" style={{ color: 'var(--success)' }}>✅</div>
                <span className={`stat-trend${goodRatio >= 50 ? ' stat-trend--up' : ' stat-trend--down'}`}>
                  {goodRatio >= 50 ? '良好' : '要改善'}
                </span>
              </div>
              <div className="stat-value">{goodRatio}%</div>
              <div className="stat-label">GOOD評価率</div>
              <div className="progress-bar" style={{ marginTop: '0.75rem' }}>
                <div
                  className="progress-fill"
                  style={{
                    width: `${goodRatio}%`,
                    background: goodRatio >= 50
                      ? 'linear-gradient(90deg, var(--success), #4ade80)'
                      : 'linear-gradient(90deg, var(--danger), #f87171)',
                  }}
                />
              </div>
            </div>

            <div className="stat-card stat-card--cyan">
              <div className="stat-card-header">
                <div className="stat-icon" style={{ color: 'var(--secondary)' }}>📦</div>
              </div>
              <div className="stat-value">{offlineCount.toLocaleString()}</div>
              <div className="stat-label">オフライン問題</div>
              <div className="stat-sub">{Object.keys(gradeStats).length} 学年分登録</div>
            </div>

            <div className="stat-card stat-card--amber">
              <div className="stat-card-header">
                <div className="stat-icon" style={{ color: 'var(--warning)' }}>📊</div>
              </div>
              <div className="stat-value">{Object.keys(subjectStats).length}</div>
              <div className="stat-label">登録教科数</div>
              <div className="stat-sub">
                {Object.keys(subjectStats).slice(0, 3).join(' · ') || '—'}
              </div>
            </div>
          </>
        )}
      </section>

      <div className="grid-2" style={{ marginBottom: '1.5rem' }}>
        <div className="panel">
          <h3 className="panel-title">
            <span className="panel-title-icon">⚡</span>
            難易度別 評価分布
          </h3>
          {loading ? (
            <div className="skeleton" style={{ height: '120px' }} />
          ) : Object.keys(difficultyStats).length === 0 ? (
            <p className="panel-empty">評価データがありません</p>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
              {Object.entries(difficultyStats).map(([diff, stats]) => {
                const total = stats.good + stats.bad;
                const goodPct = total > 0 ? (stats.good / total) * 100 : 0;
                const badPct = total > 0 ? (stats.bad / total) * 100 : 0;
                return (
                  <div key={diff} className="diff-row">
                    <div className="diff-row-header">
                      <span className="diff-row-label">{diff}</span>
                      <span className="diff-row-stats">
                        {stats.good}G / {stats.bad}B · {goodPct.toFixed(0)}%
                      </span>
                    </div>
                    <div className="diff-stacked-bar">
                      <div className="diff-stacked-good" style={{ width: `${goodPct}%` }} />
                      <div className="diff-stacked-bad" style={{ width: `${badPct}%` }} />
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        <div className="panel">
          <h3 className="panel-title">
            <span className="panel-title-icon">📚</span>
            教科・学年別 問題数
          </h3>
          {loading ? (
            <div className="skeleton" style={{ height: '160px' }} />
          ) : Object.keys(subjectStats).length === 0 ? (
            <p className="panel-empty">オフライン問題がありません</p>
          ) : (
            <>
              <div className="dist-section-label">教科別</div>
              <div className="subject-bars">
                {Object.entries(subjectStats)
                  .sort(([, a], [, b]) => b - a)
                  .map(([sub, count]) => {
                    const pct = (count / maxSubjectCount) * 100;
                    const share = offlineCount > 0 ? ((count / offlineCount) * 100).toFixed(0) : '0';
                    return (
                      <div key={sub} className="subject-bar-row">
                        <span className="subject-bar-name">{sub}</span>
                        <div className="subject-bar-track">
                          <div className="subject-bar-fill" style={{ width: `${pct}%` }} />
                        </div>
                        <span className="subject-bar-count" title={`全体の ${share}%`}>
                          {count}
                        </span>
                      </div>
                    );
                  })}
              </div>

              <div className="dist-section-label">学年別</div>
              <div className="grade-chips">
                {Object.entries(gradeStats).sort().map(([grade, count]) => (
                  <div key={grade} className="grade-chip">
                    <strong>{grade}</strong>
                    <span>{count} 問</span>
                  </div>
                ))}
              </div>
            </>
          )}
        </div>
      </div>

      {!loading && recentItems.length > 0 && (
        <section style={{ marginBottom: '1.5rem' }}>
          <h3 className="section-title">
            <span>🕐</span>
            直近のAI評価アクティビティ
          </h3>
          <div className="panel activity-feed">
            {recentItems.map((r, i) => (
              <div key={i} className="activity-item">
                <div className="activity-meta">
                  <span className={`badge ${r.good ? 'good' : 'bad'}`}>
                    {r.good ? 'GOOD' : 'BAD'}
                  </span>
                  <span className="badge" style={{ backgroundColor: 'var(--surface)', fontSize: '0.7rem' }}>
                    {r.subject || '?'} {r.grade ?? '?'}年
                  </span>
                </div>
                <span className="activity-time">
                  {r.ts
                    ? new Date(r.ts * 1000).toLocaleString('ja-JP', {
                        month: 'short',
                        day: 'numeric',
                        hour: '2-digit',
                        minute: '2-digit',
                      })
                    : '—'}
                </span>
                <span className="activity-question">{r.q || '(問題文なし)'}</span>
              </div>
            ))}
          </div>
        </section>
      )}

      <section>
        <h3 className="section-title">クイックアクセス</h3>
        <div className="quick-grid">
          <Link href="/ratings">
            <div className="quick-card quick-card--ratings">
              <div className="quick-card-icon">⭐</div>
              <h4>評価データ</h4>
              <p>AI生成問題の品質評価を管理・フィルタリング</p>
            </div>
          </Link>
          <Link href="/offline-bank">
            <div className="quick-card quick-card--bank">
              <div className="quick-card-icon">📚</div>
              <h4>問題庫編集</h4>
              <p>オフラインプリセット問題の追加・削除</p>
            </div>
          </Link>
          <Link href="/statistics">
            <div className="quick-card quick-card--stats">
              <div className="quick-card-icon">📈</div>
              <h4>統計分析</h4>
              <p>教科・難易度ごとの品質トレンドを分析</p>
            </div>
          </Link>
          <Link href="/settings">
            <div className="quick-card quick-card--settings">
              <div className="quick-card-icon">⚙️</div>
              <h4>設定</h4>
              <p>環境変数・API接続状況の確認</p>
            </div>
          </Link>
        </div>
      </section>
    </div>
  );
}
