"use client";

import { useEffect, useState } from 'react';
import { db } from '../../lib/firebase';
import { ref, get } from 'firebase/database';

interface HealthCheck {
  label: string;
  icon: string | React.ReactNode;
  status: 'ok' | 'warn' | 'error' | 'checking';
  detail: string;
}

export default function SettingsPage() {
  const [config, setConfig] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [healthChecks, setHealthChecks] = useState<HealthCheck[]>([]);
  const [firebaseStats, setFirebaseStats] = useState<{ total: number; lastTs: number | null }>({ total: 0, lastTs: null });

  function runHealthChecks(envData: Record<string, string>) {
    const checks: HealthCheck[] = [];

    // .env file
    checks.push({
      label: '.env ファイル',
      icon: <img src="https://cdn.simpleicons.org/dotenv/C8C8C8" width="24" height="24" alt="dotenv" />,
      status: Object.keys(envData).length > 0 ? 'ok' : 'error',
      detail: Object.keys(envData).length > 0 
        ? `${Object.keys(envData).length}個の環境変数を検出`
        : '.envファイルが見つかりません。'
    });

    // Proxy Server
    const hasProxyUrl = Object.keys(envData).some(k => k === 'PROXY_URL');
    checks.push({
      label: 'Proxy Server',
      icon: <span style={{ fontSize: '1.5rem', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>🌐</span>,
      status: hasProxyUrl ? 'ok' : 'warn',
      detail: hasProxyUrl ? `URL: ${envData['PROXY_URL']}` : 'PROXY_URLが未設定。外部のAI Gatewayを経由せずに直接APIを叩きます。'
    });

    // OpenAI API Key
    const hasOpenAI = Object.keys(envData).some(k => k === 'OPENAI_API_KEY');
    checks.push({
      label: 'OpenAI API Key',
      icon: <img src="https://cdn.jsdelivr.net/npm/simple-icons/icons/openai.svg" style={{ filter: 'invert(1)' }} width="24" height="24" alt="OpenAI" />,
      status: hasOpenAI ? 'ok' : 'warn',
      detail: hasOpenAI ? 'API Keyが設定されています。' : 'OPENAI_API_KEYが未設定。OpenAIモデルは使用できません。'
    });

    // Firebase URL
    const hasFirebase = Object.keys(envData).some(k => k === 'FIREBASE_DB_URL');
    checks.push({
      label: 'Firebase Realtime DB',
      icon: <img src="https://cdn.simpleicons.org/firebase/FFCA28" width="24" height="24" alt="Firebase" />,
      status: hasFirebase ? 'ok' : 'warn',
      detail: hasFirebase ? `URL: ${envData['FIREBASE_DB_URL']}` : 'FIREBASE_DB_URLが未設定。評価データの送信ができません。'
    });

    // Firebase Ratings Path
    const hasPath = Object.keys(envData).some(k => k === 'FIREBASE_RATINGS_PATH');
    checks.push({
      label: 'Firebase Ratings Path',
      icon: <img src="https://cdn.simpleicons.org/firebase/FFCA28" width="24" height="24" alt="Firebase" />,
      status: 'ok',
      detail: hasPath ? `パス: ${envData['FIREBASE_RATINGS_PATH']}` : 'デフォルト: quiz_ratings/shared'
    });

    // Offline bank
    checks.push({
      label: 'オフライン問題庫',
      icon: <img src="https://cdn.simpleicons.org/godotengine/478CBF" width="24" height="24" alt="Godot" />,
      status: 'checking',
      detail: '確認中...'
    });

    setHealthChecks(checks);

    // Check offline bank async
    fetch('/api/offline-bank')
      .then(res => res.json())
      .then(data => {
        let count = 0;
        if (!data.error) {
          for (const subject in data) {
            for (const grade in data[subject]) {
              count += data[subject][grade].length;
            }
          }
        }
        setHealthChecks(prev => prev.map(c =>
          c.label === 'オフライン問題庫'
            ? { ...c, status: count > 0 ? 'ok' : 'error', detail: count > 0 ? `${count}問のプリセット問題を検出。` : 'offline_bank.json が空または見つかりません。' }
            : c
        ));
      });
  }

  useEffect(() => {
    // Load env config
    fetch('/api/env')
      .then(res => res.json())
      .then(data => {
        if (!data.error) {
          setConfig(data);
          runHealthChecks(data);
        } else {
          setHealthChecks([{
            label: '.env ファイル',
            icon: <img src="https://cdn.simpleicons.org/dotenv/C8C8C8" width="24" height="24" alt="dotenv" />,
            status: 'error',
            detail: '.env ファイルの読み込みに失敗しました。'
          }]);
        }
        setLoading(false);
      })
      .catch(() => {
        setLoading(false);
      });

    // Firebase stats
    const ratingsRef = ref(db, 'quiz_ratings/shared');
    get(ratingsRef).then(snapshot => {
      if (snapshot.exists()) {
        const data = snapshot.val();
        const arr = Object.values(data as Record<string, { ts?: number }>);
        const lastTs = arr.reduce((max, r) => Math.max(max, r.ts || 0), 0);
        setFirebaseStats({ total: arr.length, lastTs: lastTs || null });
      }
    }).catch(() => {});
  }, []);

  const statusColor = (s: string) => {
    switch (s) {
      case 'ok': return 'var(--success)';
      case 'warn': return 'var(--warning)';
      case 'error': return 'var(--danger)';
      default: return 'var(--text-dim)';
    }
  };

  const statusIcon = (s: string) => {
    switch (s) {
      case 'ok': return '🟢';
      case 'warn': return '🟡';
      case 'error': return '🔴';
      default: return '⏳';
    }
  };

  const categorizeEnvVars = (config: Record<string, string>) => {
    const categories: Record<string, [string, string][]> = {
      'API設定': [],
      'Firebase設定': [],
      'モデル設定': [],
      'その他': [],
    };
    Object.entries(config).forEach(([key, value]) => {
      if (key.includes('API_KEY') || key.includes('SECRET')) {
        categories['API設定'].push([key, value]);
      } else if (key.includes('FIREBASE')) {
        categories['Firebase設定'].push([key, value]);
      } else if (key.includes('MODEL')) {
        categories['モデル設定'].push([key, value]);
      } else {
        categories['その他'].push([key, value]);
      }
    });
    return categories;
  };

  return (
    <div className="animate-fade">
      <h2 className="heading">設定・環境情報</h2>
      <p className="subheading" style={{ marginBottom: '2rem' }}>
        システム構成とAPI接続状況を確認・診断します。
      </p>

      {loading ? (
        <div className="loading-spinner">設定を読み込み中...</div>
      ) : (
        <>
          {/* System Health */}
          <h3 style={{ fontSize: '1.1rem', marginBottom: '1rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <span>🏥</span>システムヘルスチェック
          </h3>
          <div className="grid-2" style={{ marginBottom: '2rem' }}>
            {healthChecks.map((check, i) => (
              <div key={i} className="card glass-panel" style={{ 
                display: 'flex', alignItems: 'center', gap: '1rem', padding: '1rem 1.25rem',
                borderLeft: `3px solid ${statusColor(check.status)}`
              }}>
                <span style={{ fontSize: '1.5rem' }}>{check.icon}</span>
                <div style={{ flex: 1 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.25rem' }}>
                    <span style={{ fontWeight: 600, fontSize: '0.95rem' }}>{check.label}</span>
                    <span style={{ fontSize: '0.85rem' }}>{statusIcon(check.status)}</span>
                  </div>
                  <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>{check.detail}</span>
                </div>
              </div>
            ))}
          </div>

          {/* Firebase Connection Info */}
          <h3 style={{ fontSize: '1.1rem', marginBottom: '1rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <span>🔥</span>Firebase 接続情報
          </h3>
          <div className="card glass-panel" style={{ marginBottom: '2rem' }}>
            <div style={{ display: 'flex', gap: '3rem', flexWrap: 'wrap' }}>
              <div>
                <div style={{ fontSize: '0.75rem', color: 'var(--text-dim)', textTransform: 'uppercase', fontWeight: 600, marginBottom: '0.25rem' }}>ダッシュボード接続先</div>
                <code style={{ fontSize: '0.85rem', color: 'var(--secondary)' }}>
                  aiquiz-a12f6-default-rtdb.asia-southeast1
                </code>
              </div>
              <div>
                <div style={{ fontSize: '0.75rem', color: 'var(--text-dim)', textTransform: 'uppercase', fontWeight: 600, marginBottom: '0.25rem' }}>蓄積レコード数</div>
                <span style={{ fontSize: '1.25rem', fontWeight: 700 }}>{firebaseStats.total.toLocaleString()}</span>
                <span style={{ fontSize: '0.85rem', color: 'var(--text-muted)', marginLeft: '0.5rem' }}>件</span>
              </div>
              <div>
                <div style={{ fontSize: '0.75rem', color: 'var(--text-dim)', textTransform: 'uppercase', fontWeight: 600, marginBottom: '0.25rem' }}>最終更新</div>
                <span style={{ fontSize: '0.9rem', color: 'var(--text-muted)' }}>
                  {firebaseStats.lastTs
                    ? new Date(firebaseStats.lastTs * 1000).toLocaleString('ja-JP')
                    : 'データなし'}
                </span>
              </div>
            </div>
          </div>

          {/* Environment Variables - Categorized */}
          <h3 style={{ fontSize: '1.1rem', marginBottom: '1rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <span>📄</span>環境変数一覧
          </h3>
          {Object.entries(categorizeEnvVars(config))
            .filter(([, vars]) => vars.length > 0)
            .map(([category, vars]) => (
              <div key={category} className="card glass-panel" style={{ marginBottom: '1rem' }}>
                <h4 style={{ fontSize: '0.85rem', color: 'var(--text-dim)', textTransform: 'uppercase', fontWeight: 600, marginBottom: '0.75rem', letterSpacing: '0.05em' }}>
                  {category}
                </h4>
                <table className="data-table">
                  <thead>
                    <tr>
                      <th style={{ width: '35%' }}>キー</th>
                      <th>値</th>
                    </tr>
                  </thead>
                  <tbody>
                    {vars.map(([key, value]) => (
                      <tr key={key}>
                        <td style={{ fontWeight: 600, color: 'var(--primary-light)' }}>{key}</td>
                        <td>
                          <code style={{ background: 'var(--background)', padding: '0.2rem 0.5rem', borderRadius: '4px', border: '1px solid var(--border)', wordBreak: 'break-all' }}>
                            {value}
                          </code>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ))}

          {/* System Info */}
          <div className="card glass-panel" style={{ marginTop: '1rem' }}>
            <h4 style={{ fontSize: '0.85rem', color: 'var(--text-dim)', textTransform: 'uppercase', fontWeight: 600, marginBottom: '0.75rem', letterSpacing: '0.05em' }}>
              システム情報
            </h4>
            <div style={{ display: 'flex', gap: '2rem', flexWrap: 'wrap', fontSize: '0.85rem' }}>
              <div>
                <span style={{ color: 'var(--text-dim)' }}>ダッシュボード: </span>
                <span style={{ color: 'var(--text-muted)', fontWeight: 600 }}>v1.0 (Next.js)</span>
              </div>
              <div>
                <span style={{ color: 'var(--text-dim)' }}>ゲームエンジン: </span>
                <span style={{ color: 'var(--text-muted)', fontWeight: 600 }}>Godot 4.3</span>
              </div>
              <div>
                <span style={{ color: 'var(--text-dim)' }}>データベース: </span>
                <span style={{ color: 'var(--text-muted)', fontWeight: 600 }}>Firebase Realtime DB</span>
              </div>
              <div>
                <span style={{ color: 'var(--text-dim)' }}>AI生成: </span>
                <span style={{ color: 'var(--text-muted)', fontWeight: 600 }}>Gemini / OpenAI</span>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
