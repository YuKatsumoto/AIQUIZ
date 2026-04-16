"use client";

import { useEffect, useState } from 'react';
import { db } from '../../lib/firebase';
import { ref, get } from 'firebase/database';

export default function StatisticsPage() {
  const [loading, setLoading] = useState(true);
  const [totalRatings, setTotalRatings] = useState(0);
  const [goodRatings, setGoodRatings] = useState(0);
  const [subjectDist, setSubjectDist] = useState<Record<string, { good: number, bad: number }>>({});
  const [recentActivity, setRecentActivity] = useState<any[]>([]);

  useEffect(() => {
    const ratingsRef = ref(db, 'quiz_ratings/shared');
    get(ratingsRef).then((snapshot) => {
      if (snapshot.exists()) {
        const data = snapshot.val();
        const arr = Object.values<any>(data).sort((a, b) => (b.ts || 0) - (a.ts || 0));
        
        setTotalRatings(arr.length);
        
        let good = 0;
        const dist: Record<string, { good: number, bad: number }> = {};
        
        arr.forEach(r => {
          if (r.good) good++;
          
          if (!dist[r.subject]) {
            dist[r.subject] = { good: 0, bad: 0 };
          }
          if (r.good) dist[r.subject].good++;
          else dist[r.subject].bad++;
        });

        setGoodRatings(good);
        setSubjectDist(dist);
        setRecentActivity(arr.slice(0, 10)); // Top 10 recent actions
      }
      setLoading(false);
    });
  }, []);

  const overallRatio = totalRatings > 0 ? (goodRatings / totalRatings) * 100 : 0;

  return (
    <div className="animate-fade">
      <h2 className="heading">統計・分析</h2>
      <p className="subheading" style={{ marginBottom: '2rem' }}>
        Firebaseに保存された評価データを基に、AIの生成品質や教科別の傾向を可視化します。
      </p>

      {loading ? (
        <div className="loading-spinner">データを集計中...</div>
      ) : (
        <>
          <div className="grid-2" style={{ marginBottom: '2rem' }}>
            <div className="card glass-panel">
              <h3 style={{ fontSize: '1.25rem', marginBottom: '1.5rem', fontWeight: 600 }}>全体品質スコア</h3>
              
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '1rem' }}>
                <span style={{ fontSize: '3rem', fontWeight: 800, color: overallRatio > 70 ? 'var(--success)' : 'var(--warning)' }}>
                  {overallRatio.toFixed(1)}%
                </span>
                <div style={{ textAlign: 'right' }}>
                  <div style={{ color: 'var(--text-muted)' }}>総評価数</div>
                  <div style={{ fontSize: '1.5rem', fontWeight: 700 }}>{totalRatings} 件</div>
                </div>
              </div>
              
              <div className="progress-bar" style={{ height: '12px' }}>
                <div className="progress-fill" style={{ width: `${overallRatio}%`, background: overallRatio > 70 ? 'var(--success)' : 'var(--warning)' }}></div>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', marginTop: '0.5rem', color: 'var(--text-muted)' }}>
                <span>{goodRatings} GOOD</span>
                <span>{totalRatings - goodRatings} BAD</span>
              </div>
            </div>

            <div className="card glass-panel" style={{ display: 'flex', flexDirection: 'column' }}>
              <h3 style={{ fontSize: '1.25rem', marginBottom: '1rem', fontWeight: 600 }}>教科別 品質比率</h3>
              
              <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem', flex: 1, overflowY: 'auto' }}>
                {Object.entries(subjectDist).map(([subject, stats]) => {
                  const total = stats.good + stats.bad;
                  const ratio = total > 0 ? (stats.good / total) * 100 : 0;
                  return (
                    <div key={subject}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.85rem', marginBottom: '0.25rem' }}>
                        <span style={{ fontWeight: 600 }}>{subject}</span>
                        <span style={{ color: 'var(--text-muted)' }}>{stats.good} / {total} ({ratio.toFixed(0)}%)</span>
                      </div>
                      <div className="progress-bar" style={{ height: '6px', backgroundColor: 'var(--danger-glow)' }}>
                        <div className="progress-fill" style={{ width: `${ratio}%`, background: 'var(--success)' }}></div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>

          <h3 style={{ fontSize: '1.25rem', marginBottom: '1rem', fontWeight: 600 }}>直近の評価アクティビティ</h3>
          <div className="card glass-panel">
            <table className="data-table">
              <thead>
                <tr>
                  <th>日時</th>
                  <th>教科/学年</th>
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
                      <span className={`badge ${r.good ? 'good' : 'bad'}`}>{r.good ? 'GOOD' : 'BAD'}</span>
                    </td>
                    <td style={{ maxWidth: '300px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                      {r.q}
                    </td>
                  </tr>
                ))}
                {recentActivity.length === 0 && (
                  <tr>
                    <td colSpan={4} style={{ textAlign: 'center', padding: '2rem' }}>アクティビティが存在しません。</td>
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
