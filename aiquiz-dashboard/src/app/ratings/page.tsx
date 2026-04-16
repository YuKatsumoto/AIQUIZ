"use client";

import { useEffect, useState } from 'react';
import { db } from '../../lib/firebase';
import { ref, onValue, remove, update } from 'firebase/database';
import { useToast } from '../../components/ToastProvider';

const QUICK_TAGS = ['🟢とても良い', '🟡簡単すぎる', '🔴難しすぎる', '⚠️不適切/バグ'];

function RatingCard({ r, onDelete, onUpdate }: { r: any, onDelete: (id: string) => void, onUpdate: (id: string, payload: any) => Promise<void> }) {
  const [comment, setComment] = useState(r.comment || '');
  const [isSaving, setIsSaving] = useState(false);

  // Sync state if external update happens
  useEffect(() => {
    setComment(r.comment || '');
  }, [r.comment]);

  const handleToggleGood = async () => {
    setIsSaving(true);
    await onUpdate(r.id, { good: !r.good });
    setIsSaving(false);
  };

  const handleSaveComment = async () => {
    setIsSaving(true);
    await onUpdate(r.id, { comment });
    setIsSaving(false);
  };

  const handleQuickTag = async (tag: string) => {
    const newComment = comment ? `${comment} ${tag}` : tag;
    setComment(newComment);
    setIsSaving(true);
    await onUpdate(r.id, { comment: newComment });
    setIsSaving(false);
  };

  return (
    <div className="card glass-panel animate-slide">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div style={{ flex: 1, paddingRight: '2rem' }}>
          <div style={{ display: 'flex', gap: '0.5rem', marginBottom: '0.75rem', alignItems: 'center' }}>
            <button 
              onClick={handleToggleGood}
              disabled={isSaving}
              className={`badge ${r.good ? 'good' : 'bad'}`}
              style={{ cursor: 'pointer', border: 'none', transition: 'all 0.2s', opacity: isSaving ? 0.7 : 1 }}
              title="クリックで GOOD / BAD を反転"
            >
              {r.good ? 'GOOD' : 'BAD'}
            </button>
            <span className="badge" style={{ backgroundColor: 'var(--surface)' }}>{r.subject} {r.grade}年生 ({r.difficulty})</span>
            <span className="badge" style={{ backgroundColor: 'var(--surface)' }}>{r.src || 'AI'}</span>
            <span style={{ color: 'var(--text-dim)', fontSize: '0.8rem', marginLeft: 'auto' }}>
              {r.ts ? new Date(r.ts * 1000).toLocaleString() : '時刻不明'}
            </span>
          </div>
          
          <h3 style={{ fontSize: '1.15rem', marginBottom: '1rem', fontWeight: 600 }}>{r.q}</h3>
          
          <div className="grid-2" style={{ marginBottom: '1rem' }}>
            {r.c?.map((choice: string, idx: number) => (
              <div 
                key={idx} 
                style={{ 
                  padding: '0.5rem 0.75rem', 
                  borderRadius: '8px', 
                  fontSize: '0.85rem',
                  border: idx === r.a ? '1px solid var(--primary)' : '1px solid var(--border)',
                  color: idx === r.a ? 'var(--text-main)' : 'var(--text-muted)',
                  backgroundColor: idx === r.a ? 'var(--primary-subtle)' : 'var(--background)',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '0.5rem'
                }}
              >
                <span style={{ color: idx === r.a ? 'var(--primary-light)' : 'var(--border-light)' }}>
                  {idx === r.a ? '✓' : '○'}
                </span>
                {choice}
              </div>
            ))}
          </div>
          
          <div style={{ backgroundColor: 'var(--background)', padding: '0.75rem 1rem', borderRadius: '8px', borderLeft: '3px solid var(--primary)', marginBottom: '1rem' }}>
            <span style={{ color: 'var(--primary-light)', fontSize: '0.8rem', fontWeight: 700, textTransform: 'uppercase' }}>解説</span>
            <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem', marginTop: '0.25rem' }}>
              {r.e || '解説がありません。'}
            </p>
          </div>

          <div style={{ backgroundColor: 'var(--surface)', padding: '0.75rem 1rem', borderRadius: '8px', border: '1px solid var(--border)' }}>
            <span style={{ color: 'var(--text-main)', fontSize: '0.85rem', fontWeight: 600, display: 'block', marginBottom: '0.5rem' }}>💬 フィードバック・コメント</span>
            <div style={{ display: 'flex', gap: '0.5rem', marginBottom: '0.75rem', flexWrap: 'wrap' }}>
              {QUICK_TAGS.map(tag => (
                <button 
                  key={tag}
                  onClick={() => handleQuickTag(tag)}
                  disabled={isSaving}
                  style={{
                    padding: '0.25rem 0.6rem',
                    borderRadius: '16px',
                    fontSize: '0.75rem',
                    backgroundColor: 'var(--background)',
                    color: 'var(--text-muted)',
                    border: '1px solid var(--border)',
                    cursor: 'pointer',
                    transition: 'all 0.2s',
                  }}
                  onMouseOver={(e) => {
                    e.currentTarget.style.borderColor = 'var(--primary)';
                    e.currentTarget.style.color = 'var(--primary-light)';
                  }}
                  onMouseOut={(e) => {
                    e.currentTarget.style.borderColor = 'var(--border)';
                    e.currentTarget.style.color = 'var(--text-muted)';
                  }}
                >
                  {tag}
                </button>
              ))}
            </div>
            <div style={{ display: 'flex', gap: '0.5rem' }}>
              <input
                type="text"
                placeholder="独自のコメントを追加..."
                value={comment}
                onChange={e => setComment(e.target.value)}
                style={{ flex: 1, padding: '0.5rem 0.75rem', borderRadius: '6px', border: '1px solid var(--border)', backgroundColor: 'var(--background)', color: 'var(--text-main)', fontSize: '0.85rem' }}
                disabled={isSaving}
              />
              <button 
                className="btn btn-primary btn-sm"
                onClick={handleSaveComment}
                disabled={isSaving || comment === (r.comment || '')}
              >
                {isSaving ? '保存中...' : '保存'}
              </button>
            </div>
          </div>
        </div>
        
        <button className="btn btn-danger btn-sm" onClick={() => onDelete(r.id)}>
          🗑️ 削除
        </button>
      </div>
    </div>
  );
}

export default function RatingsPage() {
  const [ratings, setRatings] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [filterMode, setFilterMode] = useState<'all' | 'good' | 'bad' | 'commented'>('all');
  const [search, setSearch] = useState('');
  const { addToast } = useToast();

  useEffect(() => {
    const ratingsRef = ref(db, 'quiz_ratings/shared');
    const unsubscribe = onValue(ratingsRef, (snapshot) => {
      if (snapshot.exists()) {
        const data = snapshot.val();
        const parsed = Object.keys(data).map(key => ({
          id: key,
          ...data[key]
        })).sort((a, b) => (b.ts || 0) - (a.ts || 0));
        setRatings(parsed);
      } else {
        setRatings([]);
      }
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  const handleDelete = async (id: string) => {
    if (confirm("この評価データを削除してもよろしいですか？")) {
      const itemRef = ref(db, `quiz_ratings/shared/${id}`);
      await remove(itemRef);
      addToast('評価データを削除しました', 'success');
    }
  };

  const handleUpdate = async (id: string, payload: any) => {
    try {
      const itemRef = ref(db, `quiz_ratings/shared/${id}`);
      await update(itemRef, payload);
      // Removed noisy toast for simple good/bad toggles unless explicitly requested
      if (payload.comment !== undefined) {
        addToast('コメントを保存しました', 'success');
      }
    } catch (e: any) {
      addToast('保存に失敗しました: ' + e.message, 'error');
    }
  };

  const filteredRatings = ratings.filter(r => {
    if (filterMode === 'good' && !r.good) return false;
    if (filterMode === 'bad' && r.good) return false;
    if (filterMode === 'commented' && !r.comment) return false;
    
    if (search) {
      const term = search.toLowerCase();
      if (
        !r.q?.toLowerCase().includes(term) && 
        !r.e?.toLowerCase().includes(term) &&
        !r.comment?.toLowerCase().includes(term)
      ) return false;
    }
    return true;
  });

  return (
    <div className="animate-fade">
      <h2 className="heading">AI クイズ評価履歴</h2>
      <p className="subheading" style={{ marginBottom: '1.5rem' }}>
        AIの生成品質を向上させるため、プレイ後に手動・自動で評価・蓄積された問題データです。
      </p>

      {loading ? (
        <div className="loading-spinner">Firebase からデータを同期中...</div>
      ) : (
        <>
          <div className="card glass-panel" style={{ padding: '1rem 1.5rem', marginBottom: '1.5rem', display: 'flex', gap: '1.5rem', alignItems: 'center', flexWrap: 'wrap' }}>
            <div style={{ flex: 1, minWidth: '250px' }}>
              <div className="search-bar" style={{ marginBottom: 0 }}>
                <span className="search-icon">🔍</span>
                <input 
                  type="text" 
                  placeholder="問題文・解説・コメントから検索..." 
                  value={search}
                  onChange={e => setSearch(e.target.value)}
                />
              </div>
            </div>
            <div className="filter-chips" style={{ marginBottom: 0 }}>
              <button 
                className={`chip ${filterMode === 'all' ? 'active' : ''}`}
                onClick={() => setFilterMode('all')}
              >
                すべて ({ratings.length})
              </button>
              <button 
                className={`chip ${filterMode === 'good' ? 'active-success' : ''}`}
                onClick={() => setFilterMode('good')}
              >
                GOOD ({ratings.filter(r => r.good).length})
              </button>
              <button 
                className={`chip ${filterMode === 'bad' ? 'active-danger' : ''}`}
                onClick={() => setFilterMode('bad')}
              >
                BAD ({ratings.filter(r => !r.good).length})
              </button>
              <button 
                className={`chip ${filterMode === 'commented' ? 'active' : ''}`}
                onClick={() => setFilterMode('commented')}
              >
                💬 コメントあり ({ratings.filter(r => !!r.comment).length})
              </button>
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
            {filteredRatings.length === 0 ? (
              <div className="empty-state">
                <div className="empty-icon">📭</div>
                <p>条件に一致する評価データがありません。</p>
              </div>
            ) : filteredRatings.map(r => (
              <RatingCard 
                key={r.id} 
                r={r} 
                onDelete={handleDelete} 
                onUpdate={handleUpdate} 
              />
            ))}
          </div>
        </>
      )}
    </div>
  );
}
