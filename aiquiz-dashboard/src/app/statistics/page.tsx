"use client";

import { useEffect, useState } from 'react';
import { db } from '../../lib/firebase';
import { ref, get } from 'firebase/database';

interface RatingEntry {
  good: boolean;
  subject?: string;
  grade?: number;
  difficulty?: string;
  ts?: number;
  q?: string;
  src?: string;
  c?: string[];
  a?: number;
  e?: string;
}

export default function StatisticsPage() {
  const [loading, setLoading] = useState(true);
  const [totalRatings, setTotalRatings] = useState(0);
  const [goodRatings, setGoodRatings] = useState(0);
  const [subjectDist, setSubjectDist] = useState<Record<string, { good: number, bad: number }>>({});
  const [gradeDist, setGradeDist] = useState<Record<string, { good: number, bad: number }>>({});
  const [difficultyDist, setDifficultyDist] = useState<Record<string, { good: number, bad: number }>>({});
  const [srcDist, setSrcDist] = useState<Record<string, { good: number, bad: number }>>({});
  const [recentActivity, setRecentActivity] = useState<RatingEntry[]>([]);
  const [dailyCounts, setDailyCounts] = useState<Record<string, { good: number, bad: number }>>({});
  const [worstQuestions, setWorstQuestions] = useState<RatingEntry[]>([]);

  useEffect(() => {
    const ratingsRef = ref(db, 'quiz_ratings/shared');
    get(ratingsRef).then((snapshot) => {
      if (snapshot.exists()) {
        const data = snapshot.val();
        const arr: RatingEntry[] = Object.values(data);
        const sorted = [...arr].sort((a, b) => (b.ts || 0) - (a.ts || 0));
        
        setTotalRatings(arr.length);
        
        let good = 0;
        const subj: Record<string, { good: number, bad: number }> = {};
        const grade: Record<string, { good: number, bad: number }> = {};
        const diff: Record<string, { good: number, bad: number }> = {};
        const src: Record<string, { good: number, bad: number }> = {};
        const daily: Record<string, { good: number, bad: number }> = {};
        
        arr.forEach(r => {
          if (r.good) good++;
          
          // Subject
          const s = r.subject || '不明';
          if (!subj[s]) subj[s] = { good: 0, bad: 0 };
          if (r.good) subj[s].good++; else subj[s].bad++;
          
          // Grade
          const g = r.grade ? `${r.grade}年生` : '不明';
          if (!grade[g]) grade[g] = { good: 0, bad: 0 };
          if (r.good) grade[g].good++; else grade[g].bad++;
          
          // Difficulty
          const d = r.difficulty || '不明';
          if (!diff[d]) diff[d] = { good: 0, bad: 0 };
          if (r.good) diff[d].good++; else diff[d].bad++;
          
          // Source
          const srcKey = r.src || 'AI生成';
          if (!src[srcKey]) src[srcKey] = { good: 0, bad: 0 };
          if (r.good) src[srcKey].good++; else src[srcKey].bad++;
          
          // Daily counts (last 14 days)
          if (r.ts) {
            const dateStr = new Date(r.ts * 1000).toLocaleDateString('ja-JP', { month: 'short', day: 'numeric' });
            if (!daily[dateStr]) daily[dateStr] = { good: 0, bad: 0 };
            if (r.good) daily[dateStr].good++; else daily[dateStr].bad++;
          }
        });

        setGoodRatings(good);
        setSubjectDist(subj);
        setGradeDist(grade);
        setDifficultyDist(diff);
        setSrcDist(src);
        setRecentActivity(sorted.slice(0, 15));
        setDailyCounts(daily);
        
        // Worst questions (BAD rated, most recent)
        setWorstQuestions(sorted.filter(r => !r.good).slice(0, 5));
      }
      setLoading(false);
    });
  }, []);

  const overallRatio = totalRatings > 0 ? (goodRatings / totalRatings) * 100 : 0;

  const renderDistBar = (label: string, stats: { good: number; bad: number }) => {
    const total = stats.good + stats.bad;
    const ratio = total > 0 ? (stats.good / total) * 100 : 0;
    const color = ratio > 70 ? 'var(--success)' : ratio > 40 ? 'var(--warning)' : 'var(--danger)';
    return (
      <div key={label} style={{ marginBottom: '0.6rem' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.85rem', marginBottom: '0.25rem' }}>
          <span style={{ fontWeight: 600 }}>{label}</span>
          <span style={{ color: 'var(--text-muted)' }}>{stats.good}G / {stats.bad}B ({ratio.toFixed(0)}%)</span>
        </div>
        <div style={{ display: 'flex', height: '8px', borderRadius: '4px', overflow: 'hidden', background: 'var(--border)' }}>
          <div style={{ width: `${ratio}%`, background: color, borderRadius: '4px', transition: 'width 0.6s ease' }}></div>
        </div>
      </div>
    );
  };

  return (
    <div className="animate-fade">
      <h2 className="heading">統計・分析</h2>
      <p className="subheading" style={{ marginBottom: '2rem' }}>
        Firebaseに蓄積された評価データを多角的に可視化し、AIの生成品質を分析します。
      </p>

      {loading ? (
        <div className="loading-spinner">データを集計中...</div>
      ) : (
        <>
          {/* Top KPI Cards */}
          <div className="grid-4" style={{ marginBottom: '2rem' }}>
            <div className="stat-card">
              <div className="stat-icon" style={{ color: 'var(--primary)' }}>📊</div>
              <div className="stat-value">{totalRatings}</div>
              <div className="stat-label">総評価数</div>
            </div>
            <div className="stat-card">
              <div className="stat-icon" style={{ color: 'var(--success)' }}>✅</div>
              <div className="stat-value" style={{ color: overallRatio > 70 ? 'var(--success)' : 'var(--warning)' }}>
                {overallRatio.toFixed(1)}%
              </div>
              <div className="stat-label">GOOD評価率</div>
            </div>
            <div className="stat-card">
              <div className="stat-icon" style={{ color: 'var(--success)' }}>👍</div>
              <div className="stat-value">{goodRatings}</div>
              <div className="stat-label">GOOD</div>
            </div>
            <div className="stat-card">
              <div className="stat-icon" style={{ color: 'var(--danger)' }}>👎</div>
              <div className="stat-value">{totalRatings - goodRatings}</div>
              <div className="stat-label">BAD</div>
            </div>
          </div>

          {/* Overall Progress */}
          <div className="card glass-panel" style={{ marginBottom: '2rem' }}>
            <h3 style={{ fontSize: '1.1rem', marginBottom: '1rem', fontWeight: 600 }}>全体品質スコア</h3>
            <div className="progress-bar" style={{ height: '16px', marginBottom: '0.5rem' }}>
              <div className="progress-fill" style={{ 
                width: `${overallRatio}%`, 
                background: overallRatio > 70
                  ? 'linear-gradient(90deg, var(--success), #4ade80)'
                  : overallRatio > 40
                  ? 'linear-gradient(90deg, var(--warning), #fbbf24)'
                  : 'linear-gradient(90deg, var(--danger), #f87171)'
              }}></div>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', color: 'var(--text-muted)' }}>
              <span>{goodRatings} GOOD</span>
              <span style={{ fontWeight: 700, fontSize: '1rem', color: overallRatio > 70 ? 'var(--success)' : 'var(--warning)' }}>
                {overallRatio.toFixed(1)}%
              </span>
              <span>{totalRatings - goodRatings} BAD</span>
            </div>
          </div>

          {/* Analysis Grid - 2 columns */}
          <div className="grid-2" style={{ marginBottom: '2rem' }}>
            {/* Subject Distribution */}
            <div className="card glass-panel">
              <h3 style={{ fontSize: '1.1rem', marginBottom: '1.25rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <span>📖</span>教科別 品質
              </h3>
              {Object.entries(subjectDist).map(([label, stats]) => renderDistBar(label, stats))}
              {Object.keys(subjectDist).length === 0 && (
                <p style={{ color: 'var(--text-dim)', fontSize: '0.9rem' }}>データがありません。</p>
              )}
            </div>

            {/* Difficulty Distribution */}
            <div className="card glass-panel">
              <h3 style={{ fontSize: '1.1rem', marginBottom: '1.25rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <span>⚡</span>難易度別 品質
              </h3>
              {Object.entries(difficultyDist).map(([label, stats]) => renderDistBar(label, stats))}
              {Object.keys(difficultyDist).length === 0 && (
                <p style={{ color: 'var(--text-dim)', fontSize: '0.9rem' }}>データがありません。</p>
              )}
            </div>

            {/* Grade Distribution */}
            <div className="card glass-panel">
              <h3 style={{ fontSize: '1.1rem', marginBottom: '1.25rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <span>🎓</span>学年別 品質
              </h3>
              {Object.entries(gradeDist).sort().map(([label, stats]) => renderDistBar(label, stats))}
              {Object.keys(gradeDist).length === 0 && (
                <p style={{ color: 'var(--text-dim)', fontSize: '0.9rem' }}>データがありません。</p>
              )}
            </div>

            {/* Source Distribution */}
            <div className="card glass-panel">
              <h3 style={{ fontSize: '1.1rem', marginBottom: '1.25rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <span>🔧</span>生成ソース別 品質
              </h3>
              {Object.entries(srcDist).map(([label, stats]) => renderDistBar(label, stats))}
              {Object.keys(srcDist).length === 0 && (
                <p style={{ color: 'var(--text-dim)', fontSize: '0.9rem' }}>データがありません。</p>
              )}
            </div>
          </div>

          {/* Daily Activity Chart (CSS bar chart) */}
          {Object.keys(dailyCounts).length > 0 && (
            <div style={{ marginBottom: '2rem' }}>
              <h3 style={{ fontSize: '1.1rem', marginBottom: '1rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <span>📅</span>日別アクティビティ
              </h3>
              <div className="card glass-panel">
                <div style={{ display: 'flex', alignItems: 'flex-end', gap: '4px', height: '120px', padding: '0.5rem 0' }}>
                  {Object.entries(dailyCounts).slice(-14).map(([date, stats]) => {
                    const total = stats.good + stats.bad;
                    const maxTotal = Math.max(...Object.values(dailyCounts).map(s => s.good + s.bad));
                    const heightPct = maxTotal > 0 ? (total / maxTotal) * 100 : 0;
                    const goodPct = total > 0 ? (stats.good / total) * 100 : 0;
                    return (
                      <div key={date} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', height: '100%', justifyContent: 'flex-end' }} title={`${date}: ${stats.good}G / ${stats.bad}B`}>
                        <div style={{ 
                          width: '100%', maxWidth: '32px',
                          height: `${Math.max(heightPct, 4)}%`, 
                          borderRadius: '4px 4px 2px 2px',
                          background: `linear-gradient(to top, var(--danger) 0%, var(--danger) ${100 - goodPct}%, var(--success) ${100 - goodPct}%, var(--success) 100%)`,
                          transition: 'height 0.5s ease',
                          position: 'relative',
                          minHeight: '4px'
                        }}>
                          <span style={{ 
                            position: 'absolute', top: '-18px', left: '50%', transform: 'translateX(-50%)',
                            fontSize: '0.65rem', color: 'var(--text-muted)', whiteSpace: 'nowrap'
                          }}>{total}</span>
                        </div>
                        <span style={{ fontSize: '0.6rem', color: 'var(--text-dim)', marginTop: '4px', whiteSpace: 'nowrap' }}>{date}</span>
                      </div>
                    );
                  })}
                </div>
                <div style={{ display: 'flex', justifyContent: 'center', gap: '2rem', marginTop: '0.75rem', fontSize: '0.75rem', color: 'var(--text-muted)' }}>
                  <span><span style={{ display: 'inline-block', width: '10px', height: '10px', background: 'var(--success)', borderRadius: '2px', marginRight: '4px' }}></span>GOOD</span>
                  <span><span style={{ display: 'inline-block', width: '10px', height: '10px', background: 'var(--danger)', borderRadius: '2px', marginRight: '4px' }}></span>BAD</span>
                </div>
              </div>
            </div>
          )}

          {/* Worst Questions */}
          {worstQuestions.length > 0 && (
            <div style={{ marginBottom: '2rem' }}>
              <h3 style={{ fontSize: '1.1rem', marginBottom: '1rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <span>⚠️</span>直近のBAD評価問題
              </h3>
              <div className="card glass-panel" style={{ padding: 0, overflow: 'hidden' }}>
                {worstQuestions.map((r, i) => (
                  <div key={i} style={{
                    padding: '0.85rem 1.25rem',
                    borderBottom: i < worstQuestions.length - 1 ? '1px solid var(--border)' : 'none',
                    display: 'flex', alignItems: 'center', gap: '1rem',
                  }}>
                    <span className="badge bad" style={{ minWidth: '40px', textAlign: 'center' }}>BAD</span>
                    <span style={{ fontSize: '0.8rem', color: 'var(--text-dim)', minWidth: '85px' }}>
                      {r.ts ? new Date(r.ts * 1000).toLocaleString('ja-JP', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '-'}
                    </span>
                    <span className="badge" style={{ backgroundColor: 'var(--surface)', fontSize: '0.7rem' }}>
                      {r.subject || '?'} {r.grade || '?'}年 {r.difficulty || ''}
                    </span>
                    <span style={{ flex: 1, fontSize: '0.85rem', color: 'var(--text-muted)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                      {r.q || '(問題文なし)'}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Recent Activity Table */}
          <h3 style={{ fontSize: '1.1rem', marginBottom: '1rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <span>🕐</span>直近の評価アクティビティ
          </h3>
          <div className="card glass-panel">
            <table className="data-table">
              <thead>
                <tr>
                  <th>日時</th>
                  <th>教科/学年</th>
                  <th>難易度</th>
                  <th>評価</th>
                  <th>問題プレビュー</th>
                </tr>
              </thead>
              <tbody>
                {recentActivity.map((r, i) => (
                  <tr key={i}>
                    <td style={{ whiteSpace: 'nowrap' }}>
                      {r.ts ? new Date(r.ts * 1000).toLocaleString('ja-JP', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '-'}
                    </td>
                    <td>
                      <span className="badge" style={{ backgroundColor: 'var(--surface)' }}>{r.subject} {r.grade}年</span>
                    </td>
                    <td>
                      <span style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>{r.difficulty || '-'}</span>
                    </td>
                    <td>
                      <span className={`badge ${r.good ? 'good' : 'bad'}`}>{r.good ? 'GOOD' : 'BAD'}</span>
                    </td>
                    <td style={{ maxWidth: '300px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                      {r.q}
                    </td>
                  </tr>
                ))}
                {recentActivity.length === 0 && (
                  <tr>
                    <td colSpan={5} style={{ textAlign: 'center', padding: '2rem' }}>アクティビティが存在しません。</td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  );
}
