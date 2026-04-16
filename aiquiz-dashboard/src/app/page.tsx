"use client";

import { useEffect, useState } from 'react';
import { db } from '../lib/firebase';
import { ref, get } from 'firebase/database';
import Link from 'next/link';

export default function Home() {
  const [offlineCount, setOfflineCount] = useState(0);
  const [ratingCount, setRatingCount] = useState(0);
  const [subjectStats, setSubjectStats] = useState<Record<string, number>>({});
  const [goodRatings, setGoodRatings] = useState(0);

  useEffect(() => {
    fetch('/api/offline-bank')
      .then(res => res.json())
      .then(data => {
        if (!data.error) {
          let count = 0;
          const stats: Record<string, number> = {};
          for (const subject in data) {
            stats[subject] = 0;
            for (const grade in data[subject]) {
              const num = data[subject][grade].length;
              count += num;
              stats[subject] += num;
            }
          }
          setOfflineCount(count);
          setSubjectStats(stats);
        }
      });

    const ratingsRef = ref(db, 'quiz_ratings/shared');
    get(ratingsRef).then((snapshot) => {
      if (snapshot.exists()) {
        const data = snapshot.val();
        const arr = Object.values<{good: boolean}>(data);
        setRatingCount(arr.length);
        setGoodRatings(arr.filter(r => r.good).length);
      }
    });

  }, []);

  const goodRatio = ratingCount > 0 ? Math.round((goodRatings / ratingCount) * 100) : 0;

  return (
    <div className="animate-fade">
      <h2 className="heading">AIQUIZ ダッシュボード</h2>
      <p className="subheading" style={{ marginBottom: '2.5rem' }}>AIQUIZシステム全体の稼働状況とデータリポジトリを管理します。</p>

      <div className="grid-2" style={{ marginBottom: '2rem' }}>
        <div className="stat-card">
          <div className="stat-icon" style={{ color: 'var(--primary)' }}>🧠</div>
          <div className="stat-value">{ratingCount.toLocaleString()}</div>
          <div className="stat-label">AIクイズ自動評価データ 総件数</div>
          
          <div style={{ marginTop: '1.5rem' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', marginBottom: '0.5rem', color: 'var(--text-muted)' }}>
              <span>GOOD評価率</span>
              <span style={{ color: goodRatio > 50 ? 'var(--success)' : 'var(--danger)', fontWeight: 'bold' }}>{goodRatio}%</span>
            </div>
            <div className="progress-bar">
              <div className="progress-fill" style={{ width: `${goodRatio}%` }}></div>
            </div>
          </div>
        </div>

        <div className="stat-card">
          <div className="stat-icon" style={{ color: 'var(--success)' }}>📦</div>
          <div className="stat-value">{offlineCount.toLocaleString()}</div>
          <div className="stat-label">オフライン問題庫 プリセット問題総数</div>

          <div style={{ marginTop: '1.5rem', display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
            {Object.entries(subjectStats).map(([sub, count]) => (
              <span key={sub} className="badge" style={{ backgroundColor: 'var(--surface-hover)', border: '1px solid var(--border)' }}>
                {sub}: {count}
              </span>
            ))}
          </div>
        </div>
      </div>

      <h3 style={{ fontSize: '1.25rem', marginBottom: '1rem', fontWeight: 600 }}>クイックアクセス</h3>
      <div className="grid-2">
        <Link href="/ratings">
          <div className="card glass-panel" style={{ cursor: 'pointer', height: '100%' }}>
            <h4 style={{ color: 'var(--primary)', marginBottom: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <span>⭐</span>評価済みデータの確認
            </h4>
            <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem' }}>
              ゲームプレイ中にGemini AIが自己採点した問題のクオリティをチェックし、AIのプロンプト学習状況を監視します。
            </p>
          </div>
        </Link>
        <Link href="/offline-bank">
          <div className="card glass-panel" style={{ cursor: 'pointer', height: '100%' }}>
            <h4 style={{ color: 'var(--success)', marginBottom: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <span>📚</span>オフライン問題データの編集
            </h4>
            <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem' }}>
              APIキーが利用できない環境用のフォールバック問題（JSONファイル）から、不適切な問題を削除して安全なゲーム進行を担保します。
            </p>
          </div>
        </Link>
      </div>
    </div>
  );
}
