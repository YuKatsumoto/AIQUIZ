"use client";

import { useState } from 'react';
import { useToast } from '../../components/ToastProvider';

export default function AiTuningPage() {
  const [subject, setSubject] = useState('算数');
  const [grade, setGrade] = useState('3');
  const [difficulty, setDifficulty] = useState('普通');
  const [count, setCount] = useState(3);
  
  const [systemInstruction, setSystemInstruction] = useState(
`あなたは日本の小学生向け教育エキスパートです。
以下のJSONスキーマに従い、指定された教科・学年・難易度のクイズを【絶対にJSONのリスト(配列)形式のみ】で出力してください。
マークダウン(\`\`\`json)は付けないでください。[ {...} ] のみを出力してください。
{"q": "問題文", "c": ["選択肢1", "選択肢2", "選択肢3", "選択肢4"], "a": 正解インデックス(0-3), "e": "解説(20文字以内)"}`
  );

  const [prompt, setPrompt] = useState('小学3年生の算数の難易度「普通」の高品質なクイズを3問作成せよ。');

  const [loading, setLoading] = useState(false);
  const [results, setResults] = useState<Record<string, unknown>[]>([]);
  const [rawText, setRawText] = useState('');
  const { addToast } = useToast();

  const handleSimulate = async () => {
    setLoading(true);
    setResults([]);
    setRawText('');
    try {
      const res = await fetch('/api/simulate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          subject, grade: parseInt(grade), difficulty, count,
          systemInstruction, prompt
        })
      });
      const data = await res.json();
      
      if (!res.ok) {
        addToast(data.error || 'シミュレーション失敗', 'error');
        setRawText(JSON.stringify(data, null, 2));
      } else {
        addToast('生成完了', 'success');
        setResults(data.result);
        setRawText(data.raw);
      }
    } catch {
      addToast('通信エラーが発生しました', 'error');
    } finally {
      setLoading(false);
    }
  };

  const updatePrompt = (s: string, g: string, d: string, c: number) => {
    setPrompt(`小学${g}年生の${s}の難易度「${d}」の高品質なクイズを${c}問作成せよ。`);
  };

  return (
    <div className="animate-fade">
      <h2 className="heading">🧪 AIチューニング（シミュレーター）</h2>
      <p className="subheading" style={{ marginBottom: '2rem' }}>
        Godotゲーム本体を起動せずに、ダッシュボード上で直接AIプロンプトのテストと生成品質の検証を行います。
      </p>

      <div className="grid-2">
        {/* Settings Panel */}
        <div className="card glass-panel" style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
          <h3 style={{ fontSize: '1.1rem', fontWeight: 600 }}>1. 生成条件</h3>
          
          <div className="grid-4" style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '1rem' }}>
            <div className="input-group">
              <label>教科</label>
              <select className="input-field" value={subject} onChange={e => { setSubject(e.target.value); updatePrompt(e.target.value, grade, difficulty, count); }}>
                <option value="算数">算数</option>
                <option value="国語">国語</option>
                <option value="理科">理科</option>
                <option value="社会">社会</option>
              </select>
            </div>
            <div className="input-group">
              <label>学年</label>
              <select className="input-field" value={grade} onChange={e => { setGrade(e.target.value); updatePrompt(subject, e.target.value, difficulty, count); }}>
                {[1,2,3,4,5,6].map(g => <option key={g} value={g}>{g}年生</option>)}
              </select>
            </div>
            <div className="input-group">
              <label>難易度</label>
              <select className="input-field" value={difficulty} onChange={e => { setDifficulty(e.target.value); updatePrompt(subject, grade, e.target.value, count); }}>
                <option value="簡単">簡単</option>
                <option value="普通">普通</option>
                <option value="難しい">難しい</option>
                <option value="激ムズ">激ムズ</option>
              </select>
            </div>
            <div className="input-group">
              <label>生成数</label>
              <select className="input-field" value={count} onChange={e => { setCount(parseInt(e.target.value)); updatePrompt(subject, grade, difficulty, parseInt(e.target.value)); }}>
                <option value={1}>1問</option>
                <option value={3}>3問</option>
                <option value={5}>5問</option>
                <option value={10}>10問</option>
              </select>
            </div>
          </div>

          <div className="input-group" style={{ marginTop: '0.5rem' }}>
            <label>システム・インストラクション (System Prompt)</label>
            <textarea 
              className="input-field" 
              rows={6}
              value={systemInstruction}
              onChange={e => setSystemInstruction(e.target.value)}
              style={{ fontFamily: 'monospace', fontSize: '0.8rem' }}
            />
          </div>

          <div className="input-group">
            <label>ユーザー・プロンプト (User Prompt)</label>
            <input 
              type="text" 
              className="input-field" 
              value={prompt}
              onChange={e => setPrompt(e.target.value)}
            />
          </div>

          <button 
            className="btn btn-primary" 
            onClick={handleSimulate}
            disabled={loading}
            style={{ marginTop: '1rem', justifyContent: 'center' }}
          >
            {loading ? '生成中...' : 'Geminiで生成シミュレーションを実行'}
          </button>
        </div>

        {/* Results Panel */}
        <div className="card glass-panel" style={{ display: 'flex', flexDirection: 'column', gap: '1rem', height: '100%', maxHeight: '800px' }}>
          <h3 style={{ fontSize: '1.1rem', fontWeight: 600 }}>2. 出力プレビュー</h3>
          
          <div style={{ flex: 1, overflowY: 'auto', background: 'var(--background)', borderRadius: '8px', padding: '1rem', border: '1px solid var(--border)' }}>
            {loading ? (
              <div className="loading-spinner"></div>
            ) : results.length > 0 ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                {results.map((r, i) => (
                  <div key={i} style={{ background: 'var(--surface)', padding: '1rem', borderRadius: '8px', border: '1px solid var(--border-light)' }}>
                    <div style={{ fontWeight: 600, marginBottom: '0.5rem' }}>Q{i+1}: {r.q}</div>
                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem', marginBottom: '0.5rem' }}>
                      {r.c?.map((choice: string, idx: number) => (
                        <div key={idx} style={{ 
                          padding: '0.4rem', borderRadius: '4px', fontSize: '0.85rem',
                          background: idx === r.a ? 'rgba(34,197,94,0.2)' : 'var(--background)',
                          border: `1px solid ${idx === r.a ? 'var(--success)' : 'var(--border)'}`,
                          color: idx === r.a ? 'var(--success)' : 'inherit'
                        }}>
                          {idx}. {choice}
                        </div>
                      ))}
                    </div>
                    <div style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                      💡 解説: {r.e || r.exp || '(なし)'}
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <div style={{ color: 'var(--text-dim)', fontSize: '0.9rem', whiteSpace: 'pre-wrap', fontFamily: 'monospace' }}>
                {rawText ? `[Raw Output]\n${rawText}` : 'ここに生成結果が表示されます。'}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
