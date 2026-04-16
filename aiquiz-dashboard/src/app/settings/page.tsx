"use client";

import { useEffect, useState } from 'react';

export default function SettingsPage() {
  const [config, setConfig] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch('/api/env')
      .then(res => res.json())
      .then(data => {
        if (!data.error) setConfig(data);
        setLoading(false);
      });
  }, []);

  return (
    <div className="animate-fade">
      <h2 className="heading">設定・環境情報</h2>
      <p className="subheading" style={{ marginBottom: '2rem' }}>
        Godotプロジェクト側の <code>.env</code> ファイルに設定されている現在の動作環境パラメータです。
      </p>

      {loading ? (
        <div className="loading-spinner">設定を読み込み中...</div>
      ) : (
        <div className="card glass-panel">
          <table className="data-table">
            <thead>
              <tr>
                <th>環境変数名</th>
                <th>設定値</th>
              </tr>
            </thead>
            <tbody>
              {Object.entries(config).map(([key, value]) => (
                <tr key={key}>
                  <td style={{ fontWeight: 600, color: 'var(--primary-light)' }}>{key}</td>
                  <td>
                    <code style={{ background: 'var(--background)', padding: '0.2rem 0.5rem', borderRadius: '4px', border: '1px solid var(--border)' }}>
                      {value}
                    </code>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
