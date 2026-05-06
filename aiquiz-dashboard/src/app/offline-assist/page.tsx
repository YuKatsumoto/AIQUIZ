"use client";

import { useEffect, useState, useCallback } from 'react';
import Link from 'next/link';
import { useToast } from '../../components/ToastProvider';

interface QuizItem {
  q: string;
  c: string[];
  a: number;
  exp?: string;
  e?: string;
  difficulty?: string;
}

interface Suggestion {
  type: 'missing' | 'duplicate' | 'low_quality';
  subject?: string;
  grade?: string;
  message: string;
  severity: 'high' | 'medium' | 'low';
}

const TARGET_COUNT = 30; // 理想的な問題数/単元

interface CellStats {
  total: number;
  easy: number;
  normal: number;
  hard: number;
  none: number;
}

export default function OfflineAssistPage() {
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState<Record<string, Record<string, CellStats>>>({});
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [totalCount, setTotalCount] = useState(0);
  const [generating, setGenerating] = useState<{subj: string, grade: string} | null>(null);
  
  // Manual generation state
  const [manualSubject, setManualSubject] = useState('算数');
  const [manualGrade, setManualGrade] = useState('1');
  const [manualCount, setManualCount] = useState(10);
  const [manualDifficulty, setManualDifficulty] = useState('すべて');
  
  const { addToast } = useToast();

  const fetchBank = useCallback(() => {
    setLoading(true);
    fetch('/api/offline-bank')
      .then(res => res.json())
      .then(data => {
        if (data.error) {
          setLoading(false);
          return;
        }

        let total = 0;
        const s: Record<string, Record<string, CellStats>> = {};
        const sugs: Suggestion[] = [];
        const subjects = ['算数', '国語', '理科', '社会'];
        const grades = ['1', '2', '3', '4', '5', '6'];

        const allQuestions: Record<string, {subj: string, grade: string}[]> = {};

        subjects.forEach(subj => {
          s[subj] = {};
          grades.forEach(grade => {
            const qs: QuizItem[] = data[subj]?.[grade] || [];
            
            let easy = 0, normal = 0, hard = 0, none = 0;
            qs.forEach(q => {
              if (q.difficulty === '簡単') easy++;
              else if (q.difficulty === '普通') normal++;
              else if (q.difficulty === '難しい') hard++;
              else none++;
            });

            const count = qs.length;
            s[subj][grade] = { total: count, easy, normal, hard, none };
            total += count;

            if (count === 0) {
              sugs.push({ type: 'missing', subject: subj, grade, message: `${grade}年生 ${subj} の問題が全くありません。`, severity: 'high' });
            } else if (count < TARGET_COUNT) {
              sugs.push({ type: 'missing', subject: subj, grade, message: `${grade}年生 ${subj} の問題が不足しています（現在 ${count}問 / 目標 ${TARGET_COUNT}問）。`, severity: 'medium' });
            }

            qs.forEach(q => {
              const text = q.q.trim();
              if (!allQuestions[text]) allQuestions[text] = [];
              allQuestions[text].push({ subj, grade });

              if (!q.c || q.c.length < 2) {
                sugs.push({ type: 'low_quality', subject: subj, grade, message: `選択肢が少なすぎる問題があります: "${text.substring(0, 20)}..."`, severity: 'medium' });
              }
              if (!q.a && q.a !== 0) {
                sugs.push({ type: 'low_quality', subject: subj, grade, message: `正解(a)が設定されていない問題があります: "${text.substring(0, 20)}..."`, severity: 'high' });
              }
            });
          });
        });

        Object.entries(allQuestions).forEach(([text, locs]) => {
          if (locs.length > 1) {
            sugs.push({
              type: 'duplicate',
              message: `重複問題があります(${locs.length}件): "${text.substring(0, 20)}..."`,
              severity: 'low'
            });
          }
        });

        setStats(s);
        setTotalCount(total);
        setSuggestions(sugs.sort((a, b) => {
          const sev = { high: 3, medium: 2, low: 1 };
          return sev[b.severity] - sev[a.severity];
        }));
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, []);

  useEffect(() => {
    fetchBank();
  }, [fetchBank]);

  const handleGenerate = async (subject: string, grade: string, count: number = 10, difficulty: string = 'すべて') => {
    setGenerating({ subj: subject, grade });
    try {
      const res = await fetch('/api/generate-offline', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ subject, grade, count, difficulty })
      });
      const data = await res.json();
      
      if (!res.ok) {
        throw new Error(data.error || '生成に失敗しました');
      }
      
      if (data.added > 0) {
        addToast(`${grade}年生 ${subject} に ${data.added}問の新しい問題を追加しました！`, 'success');
        fetchBank();
      } else {
        addToast(`生成完了しましたが、既存問題との重複などで追加されませんでした。`, 'info');
      }
    } catch (err: any) {
      console.error(err);
      addToast(err.message, 'error');
    } finally {
      setGenerating(null);
    }
  };

  const getSeverityBadge = (severity: string) => {
    switch (severity) {
      case 'high': return <span className="badge bad">🚨 緊急</span>;
      case 'medium': return <span className="badge warning" style={{ backgroundColor: 'rgba(245, 158, 11, 0.2)', color: 'var(--warning)', border: '1px solid rgba(245, 158, 11, 0.4)' }}>⚠️ 警告</span>;
      case 'low': return <span className="badge info" style={{ backgroundColor: 'rgba(6, 182, 212, 0.2)', color: 'var(--secondary)', border: '1px solid rgba(6, 182, 212, 0.4)' }}>ℹ️ 情報</span>;
      default: return null;
    }
  };

  const getSubjectColor = (subj: string) => {
    switch (subj) {
      case '算数': return '#3b82f6';
      case '国語': return '#ef4444';
      case '理科': return '#22c55e';
      case '社会': return '#f59e0b';
      default: return 'var(--text-muted)';
    }
  };

  return (
    <div className="animate-fade">
      <h2 className="heading">🤖 問題庫アシスト</h2>
      <p className="subheading" style={{ marginBottom: '2rem' }}>
        オフライン問題庫（offline_bank.json）の品質と網羅性を自動分析し、改善を提案します。
      </p>

      {loading && !generating ? (
        <div className="loading-spinner">分析中...</div>
      ) : (
        <div className="grid-2">
          {/* Analysis Report */}
          <div className="card glass-panel" style={{ display: 'flex', flexDirection: 'column', gap: '1rem', height: '100%', maxHeight: '800px' }}>
            <h3 style={{ fontSize: '1.1rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <span>🔍</span> 分析レポート ({suggestions.length}件の提案)
            </h3>
            
            <div style={{ flex: 1, overflowY: 'auto', paddingRight: '0.5rem' }}>
              {suggestions.length === 0 ? (
                <div style={{ textAlign: 'center', padding: '3rem 1rem', color: 'var(--success)' }}>
                  <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>🎉</div>
                  <p style={{ fontWeight: 600 }}>問題庫は完璧な状態です！</p>
                  <p style={{ fontSize: '0.9rem', color: 'var(--text-muted)' }}>全教科・学年に十分な問題があり、重複もありません。</p>
                </div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                  {suggestions.map((s, i) => {
                    const isGeneratingThis = generating?.subj === s.subject && generating?.grade === s.grade;
                    
                    return (
                      <div key={i} style={{ 
                        padding: '1rem', borderRadius: '8px', 
                        background: 'var(--surface)', border: '1px solid var(--border)',
                        display: 'flex', flexDirection: 'column', gap: '0.5rem'
                      }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                          {getSeverityBadge(s.severity)}
                          {s.subject && s.grade && (
                            <span className="badge" style={{ backgroundColor: 'var(--background)', color: getSubjectColor(s.subject) }}>
                              {s.subject} {s.grade}年生
                            </span>
                          )}
                        </div>
                        <div style={{ fontSize: '0.9rem', lineHeight: '1.5' }}>{s.message}</div>
                        
                        {s.type === 'missing' && s.subject && s.grade && (
                          <div style={{ marginTop: '0.5rem', display: 'flex', gap: '0.5rem' }}>
                            <button 
                              className="btn btn-sm" 
                              style={{ background: 'var(--primary)', color: '#fff' }}
                              onClick={() => handleGenerate(s.subject!, s.grade!, 10, 'すべて')}
                              disabled={!!generating}
                            >
                              {isGeneratingThis ? '⏳ 生成中...' : '✨ 不足分を自動生成'}
                            </button>
                            <Link href={`/ai-tuning?subj=${s.subject}&grade=${s.grade}`}>
                              <button className="btn btn-sm btn-outline">
                                生成シミュレーター
                              </button>
                            </Link>
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          </div>

          {/* Right Column: Manual Generator & Heatmap */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
            
            {/* Manual Generator */}
            <div className="card glass-panel" style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
              <h3 style={{ fontSize: '1.1rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <span>✨</span> 高品質自動生成
              </h3>
              <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>
                指定した学年と教科の問題をGeminiで生成し、オフライン問題庫に追加します。
              </p>
              
              <div style={{ display: 'flex', gap: '1rem', flexWrap: 'wrap', alignItems: 'flex-end' }}>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', flex: 1, minWidth: '80px' }}>
                  <label style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--text-dim)' }}>教科</label>
                  <select 
                    className="input-field" 
                    value={manualSubject} 
                    onChange={e => setManualSubject(e.target.value)}
                    disabled={!!generating}
                  >
                    {['算数', '国語', '理科', '社会'].map(s => <option key={s} value={s}>{s}</option>)}
                  </select>
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', flex: 1, minWidth: '80px' }}>
                  <label style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--text-dim)' }}>学年</label>
                  <select 
                    className="input-field" 
                    value={manualGrade} 
                    onChange={e => setManualGrade(e.target.value)}
                    disabled={!!generating}
                  >
                    {['1', '2', '3', '4', '5', '6'].map(g => <option key={g} value={g}>{g}年生</option>)}
                  </select>
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', flex: 1, minWidth: '90px' }}>
                  <label style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--text-dim)' }}>難易度</label>
                  <select 
                    className="input-field" 
                    value={manualDifficulty} 
                    onChange={e => setManualDifficulty(e.target.value)}
                    disabled={!!generating}
                  >
                    {['すべて', '簡単', '普通', '難しい'].map(d => <option key={d} value={d}>{d}</option>)}
                  </select>
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', width: '80px' }}>
                  <label style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--text-dim)' }}>問題数</label>
                  <select 
                    className="input-field" 
                    value={manualCount} 
                    onChange={e => setManualCount(Number(e.target.value))}
                    disabled={!!generating}
                  >
                    <option value={5}>5問</option>
                    <option value={10}>10問</option>
                    <option value={20}>20問</option>
                    <option value={30}>30問</option>
                  </select>
                </div>
                
                <button 
                  className="btn" 
                  style={{ background: 'var(--primary)', color: '#fff', height: '42px', padding: '0 1rem' }}
                  onClick={() => handleGenerate(manualSubject, manualGrade, manualCount, manualDifficulty)}
                  disabled={!!generating}
                >
                  {generating ? '⏳ 生成中...' : '🚀 生成開始'}
                </button>
              </div>
            </div>

            {/* Heatmap / Coverage */}
            <div className="card glass-panel" style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem', flex: 1 }}>
              <h3 style={{ fontSize: '1.1rem', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <span>🗺️</span> 網羅性ヒートマップ
              </h3>
              
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: '0.5rem' }}>
                <span style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>総問題数: <strong>{totalCount}</strong> 問</span>
                <span style={{ fontSize: '0.75rem', color: 'var(--text-dim)' }}>目標: {TARGET_COUNT}問/セル</span>
              </div>

              <table style={{ width: '100%', borderCollapse: 'separate', borderSpacing: '4px' }}>
                <thead>
                  <tr>
                    <th></th>
                    {['1', '2', '3', '4', '5', '6'].map(g => (
                      <th key={g} style={{ padding: '0.5rem', fontSize: '0.8rem', color: 'var(--text-muted)', fontWeight: 600 }}>{g}年</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {Object.keys(stats).map(subj => (
                    <tr key={subj}>
                      <td style={{ padding: '0.5rem', fontSize: '0.85rem', fontWeight: 600, color: getSubjectColor(subj), textAlign: 'right' }}>{subj}</td>
                      {['1', '2', '3', '4', '5', '6'].map(g => {
                        const cellStats = stats[subj][g] || { total: 0, easy: 0, normal: 0, hard: 0, none: 0 };
                        const count = cellStats.total;
                        const ratio = Math.min(count / TARGET_COUNT, 1);
                        let bg = 'var(--surface)';
                        let border = 'var(--border)';
                        if (count > 0) {
                          bg = `rgba(34, 197, 94, ${ratio * 0.4})`;
                          border = `rgba(34, 197, 94, ${Math.max(ratio, 0.2)})`;
                        } else {
                          bg = 'rgba(239, 68, 68, 0.15)';
                          border = 'rgba(239, 68, 68, 0.4)';
                        }
                        
                        return (
                          <td key={g} style={{ 
                            padding: '0.5rem 0.25rem', textAlign: 'center', borderRadius: '6px',
                            background: bg, border: `1px solid ${border}`,
                            color: count === 0 ? 'var(--danger)' : 'var(--text-main)'
                          }}>
                            <div style={{ fontSize: '0.9rem', fontWeight: 700 }}>{count}</div>
                            {count > 0 && (
                              <div style={{ fontSize: '0.65rem', color: 'var(--text-dim)', display: 'flex', justifyContent: 'center', gap: '2px', marginTop: '2px' }}>
                                <span title="簡単" style={{ color: cellStats.easy > 0 ? '#4ade80' : 'inherit' }}>簡{cellStats.easy}</span>
                                <span>/</span>
                                <span title="普通" style={{ color: cellStats.normal > 0 ? '#fbbf24' : 'inherit' }}>普{cellStats.normal}</span>
                                <span>/</span>
                                <span title="難しい" style={{ color: cellStats.hard > 0 ? '#f87171' : 'inherit' }}>難{cellStats.hard}</span>
                                {cellStats.none > 0 && (
                                  <>
                                    <span>/</span>
                                    <span title="未分類(旧バージョンで生成された問題)" style={{ color: 'inherit' }}>他{cellStats.none}</span>
                                  </>
                                )}
                              </div>
                            )}
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
              
              <div style={{ marginTop: 'auto', padding: '1rem', background: 'rgba(6, 182, 212, 0.1)', borderRadius: '8px', border: '1px dashed var(--secondary-glow)' }}>
                <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', lineHeight: '1.6' }}>
                  生成された問題は自動的に重複チェックが行われ、新しい問題のみが追加されます。<br/>
                  難易度の内訳は <strong>簡(簡単) / 普(普通) / 難(難しい)</strong> で表示されます。
                </p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
