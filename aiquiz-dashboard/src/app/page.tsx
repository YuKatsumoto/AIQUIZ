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

  useEffect(() => {
    // Offline bank stats
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

    // Env status
    fetch('/api/env')
      .then(res => res.json())
      .then(data => {
        if (!data.error) setEnvStatus(data);
      })
      .catch(() => setEnvStatus(null));

    // Firebase ratings
    const ratingsRef = ref(db, 'quiz_ratings/shared');
    get(ratingsRef).then((snapshot) => {
      if (snapshot.exists()) {
        const data = snapshot.val();
        const arr = Object.values<RatingEntry>(data);
        setRatingCount(arr.length);
        setGoodRatings(arr.filter(r => r.good).length);
        setFirebaseOk(true);

        // Difficulty breakdown
        const diffDist: Record<string, { good: number; bad: number }> = {};
        arr.forEach(r => {
          const diff = r.difficulty || '不明';
          if (!diffDist[diff]) diffDist[diff] = { good: 0, bad: 0 };
          if (r.good) diffDist[diff].good++;
          else diffDist[diff].bad++;
        });
        setDifficultyStats(diffDist);

        // Recent items (sorted by timestamp, top 5)
        const sorted = [...arr]
          .filter(r => r.ts)
          .sort((a, b) => (b.ts || 0) - (a.ts || 0))
          .slice(0, 5);
        setRecentItems(sorted);
      } else {
        setFirebaseOk(true);
      }
      setLoading(false);
    }).catch(() => {
      setFirebaseOk(false);
      setLoading(false);
    });
  }, []);

  const goodRatio = ratingCount > 0 ? Math.round((goodRatings / ratingCount) * 100) : 0;
  const badRatings = ratingCount - goodRatings;

  // Determine system health
  const hasProxyUrl = envStatus && Object.keys(envStatus).some(k => k === 'PROXY_URL');
  const hasFirebaseUrl = envStatus && Object.keys(envStatus).some(k => k === 'FIREBASE_DB_URL');

  return (
    <div className="animate-fade">
      <h2 className="heading">AIQUIZ ダッシュボード</h2>
      <p className="subheading" style={{ marginBottom: '2rem' }}>AIQUIZシステム全体の稼働状況とデータリポジトリを管理します。</p>

      {/* System Health Banner */}
      <div className="card glass-panel" style={{ 
        marginBottom: '2rem', padding: '1rem 1.5rem',
        display: 'flex', gap: '2rem', alignItems: 'center', flexWrap: 'wrap',
        borderLeft: `4px solid ${firebaseOk === false ? 'var(--danger)' : 'var(--success)'}`
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          <span style={{ fontSize: '1.2rem' }}>{firebaseOk === null ? '⏳' : firebaseOk ? '🟢' : '🔴'}</span>
          <span style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>Firebase</span>
          <span style={{ fontSize: '0.85rem', fontWeight: 600, color: firebaseOk ? 'var(--success)' : 'var(--danger)' }}>
            {firebaseOk === null ? 'チェック中' : firebaseOk ? '接続OK' : '接続失敗'}
          </span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          <span style={{ fontSize: '1.2rem' }}>{hasProxyUrl ? '🟢' : '🟡'}</span>
          <span style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>Proxy Server</span>
          <span style={{ fontSize: '0.85rem', fontWeight: 600, color: hasProxyUrl ? 'var(--success)' : 'var(--warning)' }}>
            {hasProxyUrl ? '設定済' : '未設定'}
          </span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          <span style={{ fontSize: '1.2rem' }}>{hasFirebaseUrl ? '🟢' : '🟡'}</span>
          <span style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>Firebase DB URL</span>
          <span style={{ fontSize: '0.85rem', fontWeight: 600, color: hasFirebaseUrl ? 'var(--success)' : 'var(--warning)' }}>
            {hasFirebaseUrl ? '設定済' : '未設定'}
          </span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          <span style={{ fontSize: '1.2rem' }}>{offlineCount > 0 ? '🟢' : '🔴'}</span>
          <span style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>オフライン問題庫</span>
          <span style={{ fontSize: '0.85rem', fontWeight: 600, color: offlineCount > 0 ? 'var(--success)' : 'var(--danger)' }}>
            {offlineCount > 0 ? `${offlineCount}問` : '空'}
          </span>
        </div>
      </div>

      {/* Main Stat Cards - 4 columns */}
      <div className="grid-4" style={{ marginBottom: '2rem' }}>
        <div className="stat-card">
          <div className="stat-icon" style={{ color: 'var(--primary)' }}>🧠</div>
          <div className="stat-value">{ratingCount.toLocaleString()}</div>
          <div className="stat-label">AI評価データ</div>
        </div>

        <div className="stat-card">
          <div className="stat-icon" style={{ color: 'var(--success)' }}>✅</div>
          <div className="stat-value">{goodRatio}%</div>
          <div className="stat-label">GOOD評価率</div>
          <div className="progress-bar" style={{ marginTop: '0.75rem' }}>
            <div className="progress-fill" style={{ width: `${goodRatio}%`, background: goodRatio > 50 ? 'var(--success)' : 'var(--danger)' }}></div>
          </div>
        </div>

        <div className="stat-card">
          <div className="stat-icon" style={{ color: 'var(--secondary)' }}>📦</div>
          <div className="stat-value">{offlineCount.toLocaleString()}</div>
          <div className="stat-label">オフライン問題</div>
        </div>

        <div className="stat-card">
          <div className="stat-icon" style={{ color: 'var(--warning)' }}>📊</div>
          <div className="stat-value">{Object.keys(subjectStats).length}</div>
          <div className="stat-label">登録教科数</div>
        </div>
      </div>

      {/* Two-column detail section */}
      <div className="grid-2" style={{ marginBottom: '2rem' }}>
        {/* Difficulty Breakdown */}
        <div className="card glass-panel">
          <h3 style={{ fontSize: '1.1rem', marginBottom: '1.25rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <span>⚡</span>難易度別 評価分布
          </h3>
          {Object.keys(difficultyStats).length === 0 ? (
            <p style={{ color: 'var(--text-dim)', fontSize: '0.9rem' }}>評価データがありません。</p>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
              {Object.entries(difficultyStats).map(([diff, stats]) => {
                const total = stats.good + stats.bad;
                const ratio = total > 0 ? (stats.good / total) * 100 : 0;
                return (
                  <div key={diff}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.85rem', marginBottom: '0.3rem' }}>
                      <span style={{ fontWeight: 600 }}>{diff}</span>
                      <span style={{ color: 'var(--text-muted)' }}>
                        {stats.good}G / {stats.bad}B ({ratio.toFixed(0)}%)
                      </span>
                    </div>
                    <div className="progress-bar" style={{ height: '6px' }}>
                      <div className="progress-fill" style={{ width: `${ratio}%`, background: ratio > 70 ? 'var(--success)' : ratio > 40 ? 'var(--warning)' : 'var(--danger)' }}></div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Subject / Grade Distribution */}
        <div className="card glass-panel">
          <h3 style={{ fontSize: '1.1rem', marginBottom: '1.25rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <span>📚</span>教科・学年別 問題数
          </h3>
          
          <div style={{ marginBottom: '1.25rem' }}>
            <div style={{ fontSize: '0.75rem', color: 'var(--text-dim)', textTransform: 'uppercase', fontWeight: 600, marginBottom: '0.5rem' }}>教科別</div>
            <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
              {Object.entries(subjectStats).map(([sub, count]) => {
                const pct = offlineCount > 0 ? (count / offlineCount) * 100 : 0;
                return (
                  <div key={sub} style={{
                    padding: '0.5rem 0.75rem', borderRadius: '10px',
                    background: 'var(--surface)', border: '1px solid var(--border)',
                    display: 'flex', flexDirection: 'column', alignItems: 'center', minWidth: '80px'
                  }}>
                    <span style={{ fontWeight: 700, fontSize: '1.1rem' }}>{count}</span>
                    <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>{sub}</span>
                    <span style={{ fontSize: '0.65rem', color: 'var(--text-dim)' }}>{pct.toFixed(0)}%</span>
                  </div>
                );
              })}
            </div>
          </div>
          
          <div>
            <div style={{ fontSize: '0.75rem', color: 'var(--text-dim)', textTransform: 'uppercase', fontWeight: 600, marginBottom: '0.5rem' }}>学年別</div>
            <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
              {Object.entries(gradeStats).sort().map(([grade, count]) => (
                <div key={grade} style={{
                  padding: '0.4rem 0.75rem', borderRadius: '8px',
                  background: 'var(--surface)', border: '1px solid var(--border)',
                  fontSize: '0.8rem'
                }}>
                  <span style={{ fontWeight: 600 }}>{grade}</span>
                  <span style={{ color: 'var(--text-muted)', marginLeft: '0.5rem' }}>{count}問</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Recent Activity Feed */}
      {recentItems.length > 0 && (
        <div style={{ marginBottom: '2rem' }}>
          <h3 style={{ fontSize: '1.1rem', marginBottom: '1rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <span>🕐</span>直近のAI評価アクティビティ
          </h3>
          <div className="card glass-panel" style={{ padding: 0, overflow: 'hidden' }}>
            {recentItems.map((r, i) => (
              <div key={i} style={{
                padding: '0.85rem 1.25rem',
                borderBottom: i < recentItems.length - 1 ? '1px solid var(--border)' : 'none',
                display: 'flex', alignItems: 'center', gap: '1rem',
                transition: 'background 0.2s'
              }}
                onMouseOver={e => e.currentTarget.style.background = 'var(--surface-hover)'}
                onMouseOut={e => e.currentTarget.style.background = 'transparent'}
              >
                <span className={`badge ${r.good ? 'good' : 'bad'}`} style={{ minWidth: '50px', textAlign: 'center' }}>
                  {r.good ? 'GOOD' : 'BAD'}
                </span>
                <span style={{ fontSize: '0.8rem', color: 'var(--text-dim)', minWidth: '90px' }}>
                  {r.ts ? new Date(r.ts * 1000).toLocaleString('ja-JP', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '-'}
                </span>
                <span className="badge" style={{ backgroundColor: 'var(--surface)', fontSize: '0.7rem' }}>
                  {r.subject || '?'} {r.grade || '?'}年
                </span>
                <span style={{ flex: 1, fontSize: '0.85rem', color: 'var(--text-muted)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {r.q || '(問題文なし)'}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Quick Access */}
      <h3 style={{ fontSize: '1.1rem', marginBottom: '1rem', fontWeight: 600 }}>クイックアクセス</h3>
      <div className="grid-4">
        <Link href="/ratings">
          <div className="card glass-panel" style={{ cursor: 'pointer', height: '100%' }}>
            <h4 style={{ color: 'var(--primary)', marginBottom: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <span>⭐</span>評価データ
            </h4>
            <p style={{ color: 'var(--text-muted)', fontSize: '0.8rem' }}>
              AI生成問題の品質評価を管理・フィルタリング
            </p>
          </div>
        </Link>
        <Link href="/offline-bank">
          <div className="card glass-panel" style={{ cursor: 'pointer', height: '100%' }}>
            <h4 style={{ color: 'var(--success)', marginBottom: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <span>📚</span>問題庫編集
            </h4>
            <p style={{ color: 'var(--text-muted)', fontSize: '0.8rem' }}>
              オフラインプリセット問題の追加・削除
            </p>
          </div>
        </Link>
        <Link href="/statistics">
          <div className="card glass-panel" style={{ cursor: 'pointer', height: '100%' }}>
            <h4 style={{ color: 'var(--warning)', marginBottom: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <span>📈</span>統計分析
            </h4>
            <p style={{ color: 'var(--text-muted)', fontSize: '0.8rem' }}>
              教科・難易度ごとの品質トレンドを分析
            </p>
          </div>
        </Link>
        <Link href="/settings">
          <div className="card glass-panel" style={{ cursor: 'pointer', height: '100%' }}>
            <h4 style={{ color: 'var(--secondary)', marginBottom: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <span>⚙️</span>設定
            </h4>
            <p style={{ color: 'var(--text-muted)', fontSize: '0.8rem' }}>
              環境変数・API接続状況の確認
            </p>
          </div>
        </Link>
      </div>
    </div>
  );
}
