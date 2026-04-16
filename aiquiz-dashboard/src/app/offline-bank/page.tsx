"use client";

import { useEffect, useState } from 'react';
import { useToast } from '../../components/ToastProvider';

export default function OfflineBankPage() {
  const [bankData, setBankData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const { addToast } = useToast();

  const [subject, setSubject] = useState<string>('');
  const [grade, setGrade] = useState<string>('');
  const [search, setSearch] = useState('');

  // New Question Modal State
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [newQ, setNewQ] = useState('');
  const [newC, setNewC] = useState(['', '', '', '']);
  const [newA, setNewA] = useState(0);
  const [newE, setNewE] = useState('');

  useEffect(() => {
    fetch('/api/offline-bank')
      .then(res => res.json())
      .then(data => {
        if (!data.error) {
          setBankData(data);
          const firstSubj = Object.keys(data)[0];
          if (firstSubj) {
            setSubject(firstSubj);
            const firstGrade = Object.keys(data[firstSubj])[0];
            if (firstGrade) setGrade(firstGrade);
          }
        }
        setLoading(false);
      });
  }, []);

  const handleSave = async () => {
    setSaving(true);
    addToast('ディスクに保存しています...', 'info');
    try {
      await fetch('/api/offline-bank', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(bankData)
      });
      addToast('正常に保存されました！', 'success');
    } catch (e) {
      addToast('データの保存中にエラーが発生しました', 'error');
    }
    setSaving(false);
  };

  const deleteQuiz = (originalIndex: number) => {
    if (!confirm('この問題を問題集から削除しますか？')) return;
    const newData = { ...bankData };
    newData[subject][grade].splice(originalIndex, 1);
    setBankData(newData);
    addToast('問題をプレビューから削除しました。変更を確定するには「ディスクに保存」を押してください。', 'info');
  };

  const handleAddQuestion = () => {
    if (!newQ) {
      addToast('問題文を入力してください', 'error');
      return;
    }
    const newData = { ...bankData };
    if (!newData[subject]) newData[subject] = {};
    if (!newData[subject][grade]) newData[subject][grade] = [];

    newData[subject][grade].push({
      q: newQ,
      c: newC,
      a: newA,
      exp: newE || '解説なし'
    });
    
    setBankData(newData);
    setIsModalOpen(false);
    addToast('新規問題を追加しました。保存ボタンで確定してください。', 'success');
    
    // Reset Form
    setNewQ('');
    setNewC(['', '', '', '']);
    setNewA(0);
    setNewE('');
  };

  if (loading) return <div className="loading-spinner">ローカルディスクからオフライン問題集を読み出し中...</div>;
  if (!bankData) return <div className="empty-state">オフライン問題集の読み込みに失敗しました。</div>;

  const subjects = Object.keys(bankData);
  const grades = subject && bankData[subject] ? Object.keys(bankData[subject]) : [];
  let currentQuizzes = subject && grade && bankData[subject][grade] ? bankData[subject][grade] : [];

  // Add original index tracking for deletion when filtered
  const filteredQuizzes = currentQuizzes.map((q: any, originalIndex: number) => ({ q, originalIndex }))
    .filter((item: any) => {
      if (!search) return true;
      return item.q.q.includes(search) || item.q.exp?.includes(search) || item.q.e?.includes(search);
    });

  return (
    <div className="animate-fade">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '2rem' }}>
        <div>
          <h2 className="heading" style={{ marginBottom: 0 }}>オフライン問題庫</h2>
          <p className="subheading">オフライン時用のプリセット問題ファイルを直接編集します。</p>
        </div>
        <div style={{ display: 'flex', gap: '1rem' }}>
          <button className="btn btn-outline" onClick={() => setIsModalOpen(true)}>
            + 問題を追加
          </button>
          <button className="btn btn-primary" onClick={handleSave} disabled={saving} style={{ padding: '0.75rem 2rem' }}>
            {saving ? '保存中...' : 'ディスクに変更を保存'}
          </button>
        </div>
      </div>

      <div className="card glass-panel" style={{ marginBottom: '2rem', display: 'flex', gap: '1.5rem', flexWrap: 'wrap' }}>
        <div style={{ flex: 1, minWidth: '200px' }}>
          <div className="input-group">
            <label>教科</label>
            <select 
              className="input-field" 
              value={subject} 
              onChange={e => {
                setSubject(e.target.value);
                setGrade(Object.keys(bankData[e.target.value])[0] || '');
              }}
            >
              {subjects.map(s => <option key={s} value={s}>{s}</option>)}
            </select>
          </div>
        </div>
        <div style={{ flex: 1, minWidth: '200px' }}>
          <div className="input-group">
            <label>学年</label>
            <select 
              className="input-field" 
              value={grade} 
              onChange={e => setGrade(e.target.value)}
            >
              {grades.map(g => <option key={g} value={g}>{g} 年生</option>)}
            </select>
          </div>
        </div>
        <div style={{ flex: 2, minWidth: '300px' }}>
          <div className="input-group">
            <label>検索 (絞り込み)</label>
            <div className="search-bar" style={{ marginBottom: 0 }}>
              <span className="search-icon">🔍</span>
              <input 
                type="text" 
                placeholder="問題文から検索..." 
                value={search}
                onChange={e => setSearch(e.target.value)}
              />
            </div>
          </div>
        </div>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
        <h3 style={{ fontSize: '1.25rem', marginBottom: '0.5rem', fontWeight: 600 }}>
          {subject} ({grade}年生) の問題数: {filteredQuizzes.length}問 {search && '(検索結果)'}
        </h3>

        {filteredQuizzes.map(({ q, originalIndex }: any) => (
          <div key={originalIndex} className="card glass-panel animate-slide">
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
              <div style={{ flex: 1, paddingRight: '2rem' }}>
                <h4 style={{ fontSize: '1.15rem', marginBottom: '1rem', fontWeight: 600 }}>{q.q}</h4>
                
                <div className="grid-2" style={{ marginBottom: '1rem' }}>
                  {q.c?.map((choice: string, cIdx: number) => (
                    <div 
                      key={cIdx} 
                      style={{ 
                        padding: '0.5rem 0.75rem', 
                        borderRadius: '8px', 
                        fontSize: '0.85rem',
                        border: cIdx === q.a ? '1px solid var(--primary)' : '1px solid var(--border)',
                        color: cIdx === q.a ? 'var(--text-main)' : 'var(--text-muted)',
                        backgroundColor: cIdx === q.a ? 'var(--primary-subtle)' : 'var(--background)',
                        display: 'flex',
                        alignItems: 'center',
                        gap: '0.5rem'
                      }}
                    >
                      <span style={{ color: cIdx === q.a ? 'var(--primary)' : 'var(--border-light)' }}>
                        {cIdx === q.a ? '✓' : '○'}
                      </span>
                      {choice}
                    </div>
                  ))}
                </div>
                
                <div style={{ backgroundColor: 'var(--background)', padding: '0.75rem 1rem', borderRadius: '8px', borderLeft: '3px solid var(--border-light)' }}>
                  <span style={{ color: 'var(--text-muted)', fontSize: '0.75rem', fontWeight: 700, textTransform: 'uppercase' }}>解説</span>
                  <p style={{ color: 'var(--text-main)', fontSize: '0.9rem', marginTop: '0.25rem' }}>
                    {q.e || q.exp || '解説なし。'}
                  </p>
                </div>
              </div>
              
              <button className="btn btn-danger btn-sm" onClick={() => deleteQuiz(originalIndex)}>
                🗑️ 削除
              </button>
            </div>
          </div>
        ))}
        
        {filteredQuizzes.length === 0 && (
          <div className="empty-state">
            <div className="empty-icon">📭</div>
            <p>このカテゴリに問題はありません。</p>
          </div>
        )}
      </div>

      {/* New Question Modal */}
      {isModalOpen && (
        <div className="modal-overlay">
          <div className="modal-content">
            <div className="modal-header">
              <h3>新しい問題を追加</h3>
              <button className="modal-close" onClick={() => setIsModalOpen(false)}>×</button>
            </div>
            
            <div className="input-group">
              <label>問題文</label>
              <textarea 
                className="input-field" 
                value={newQ} 
                onChange={e => setNewQ(e.target.value)} 
                placeholder="例: 日本で一番高い山は何ですか？" 
              />
            </div>

            <div className="input-group" style={{ marginTop: '1rem' }}>
              <label>選択肢 (4つ)</label>
              {newC.map((c, i) => (
                <div key={i} style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.5rem' }}>
                  <input 
                    type="radio" 
                    name="correct-answer" 
                    checked={newA === i}
                    onChange={() => setNewA(i)}
                    style={{ cursor: 'pointer' }}
                  />
                  <input 
                    type="text" 
                    className="input-field" 
                    style={{ marginBottom: 0 }}
                    value={c} 
                    onChange={e => {
                      const cArr = [...newC];
                      cArr[i] = e.target.value;
                      setNewC(cArr);
                    }} 
                    placeholder={`選択肢 ${i + 1}`}
                  />
                </div>
              ))}
              <span style={{ fontSize: '0.8rem', color: 'var(--text-dim)' }}>ラジオボタンで正解を選択してください。</span>
            </div>

            <div className="input-group" style={{ marginTop: '1rem' }}>
              <label>解説 (任意)</label>
              <textarea 
                className="input-field" 
                value={newE} 
                onChange={e => setNewE(e.target.value)} 
                placeholder="解説を入力..."
                style={{ minHeight: '60px' }}
              />
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '1rem', marginTop: '2rem' }}>
              <button className="btn" onClick={() => setIsModalOpen(false)}>キャンセル</button>
              <button className="btn btn-primary" onClick={handleAddQuestion}>追加する</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
