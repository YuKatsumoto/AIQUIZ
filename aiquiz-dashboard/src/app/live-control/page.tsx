"use client";

import { useEffect, useState } from 'react';
import { db } from '../../lib/firebase';
import { ref, get, set, serverTimestamp } from 'firebase/database';
import { useToast } from '../../components/ToastProvider';

interface LiveConfig {
  announcement: string;
  event_theme: string;
  is_active: boolean;
  updated_at?: number;
}

export default function LiveControlPage() {
  const [config, setConfig] = useState<LiveConfig>({
    announcement: '',
    event_theme: '',
    is_active: true,
  });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const { addToast } = useToast();

  useEffect(() => {
    const configRef = ref(db, 'live_config');
    get(configRef).then((snapshot) => {
      if (snapshot.exists()) {
        setConfig(c => ({
          ...c,
          ...snapshot.val()
        }));
      }
      setLoading(false);
    }).catch((err) => {
      console.error(err);
      addToast('設定の取得に失敗しました', 'error');
      setLoading(false);
    });
  }, [addToast]);

  const handleSave = async () => {
    setSaving(true);
    try {
      const configRef = ref(db, 'live_config');
      await set(configRef, {
        ...config,
        updated_at: serverTimestamp()
      });
      addToast('ライブ設定を保存しました', 'success');
    } catch (err) {
      console.error(err);
      addToast('保存に失敗しました', 'error');
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return <div className="loading-spinner"></div>;
  }

  return (
    <div className="animate-fade">
      <h2 className="heading">📡 ライブコントロール</h2>
      <p className="subheading" style={{ marginBottom: '2rem' }}>
        ゲーム内のロビーや生成エンジンに対して、リアルタイムに指示を送ります。
      </p>

      <div className="grid-2">
        <div className="card glass-panel" style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
          <h3 style={{ fontSize: '1.1rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <span>📢</span> ゲーム内アナウンス
          </h3>
          <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>
            プレイヤーがメインメニューを開いた際に表示されるお知らせテキストです。
          </p>

          <div className="input-group">
            <label>アナウンス・メッセージ</label>
            <textarea 
              className="input-field" 
              placeholder="例：本日は「宇宙特集」イベント開催中！宇宙に関するクイズが出やすくなっています。"
              value={config.announcement}
              onChange={(e) => setConfig({ ...config, announcement: e.target.value })}
              rows={4}
            />
          </div>

          <div className="input-group" style={{ flexDirection: 'row', alignItems: 'center', gap: '1rem' }}>
            <label style={{ margin: 0 }}>アナウンスを有効にする</label>
            <label className="switch" style={{ display: 'flex', alignItems: 'center', cursor: 'pointer', gap: '0.5rem' }}>
              <input 
                type="checkbox" 
                checked={config.is_active}
                onChange={(e) => setConfig({ ...config, is_active: e.target.checked })}
                style={{ width: '1.2rem', height: '1.2rem', accentColor: 'var(--primary)' }}
              />
              <span style={{ fontSize: '0.9rem', color: config.is_active ? 'var(--success)' : 'var(--text-dim)' }}>
                {config.is_active ? '配信中' : '非表示'}
              </span>
            </label>
          </div>
        </div>

        <div className="card glass-panel" style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
          <h3 style={{ fontSize: '1.1rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <span>🎯</span> イベントテーマ（プロンプト上書き）
          </h3>
          <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>
            オンライン問題生成時に、AIに対して追加で与えるテーマや制約です。
          </p>

          <div className="input-group">
            <label>テーマ・コンテキスト</label>
            <input 
              type="text" 
              className="input-field" 
              placeholder="例：宇宙、歴史、ファンタジー"
              value={config.event_theme}
              onChange={(e) => setConfig({ ...config, event_theme: e.target.value })}
            />
          </div>
          
          <div style={{ padding: '1rem', background: 'rgba(99, 102, 241, 0.1)', borderRadius: '8px', border: '1px dashed var(--primary-subtle)' }}>
            <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', lineHeight: '1.5' }}>
              <strong>💡 Hint:</strong><br/>
              テーマを設定すると、Godot側でAIにプロンプトを送る際に「このクイズは[{config.event_theme || '未設定'}]に関連する要素を少し含めてください」といった文脈が動的に追加されます。
            </p>
          </div>
        </div>
      </div>

      <div style={{ marginTop: '2rem', display: 'flex', justifyContent: 'flex-end' }}>
        <button 
          className="btn btn-primary btn-lg" 
          onClick={handleSave}
          disabled={saving}
          style={{ minWidth: '200px', justifyContent: 'center' }}
        >
          {saving ? '保存中...' : '設定を反映する'}
        </button>
      </div>
    </div>
  );
}
