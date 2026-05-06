"use client";

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const navItems = [
  { label: 'メイン', section: true },
  { href: '/', icon: '📊', label: 'ダッシュボード' },
  { href: '/live-control', icon: '📡', label: 'ライブコントロール' },
  { href: '/ratings', icon: '⭐', label: '評価済みクイズ' },
  { href: '/offline-bank', icon: '📚', label: 'オフライン問題庫' },
  { label: 'ツール', section: true },
  { href: '/offline-assist', icon: '🤖', label: '問題庫アシスト' },
  { href: '/ai-tuning', icon: '🧪', label: 'AIチューニング' },
  { href: '/statistics', icon: '📈', label: '統計・分析' },
  { href: '/settings', icon: '⚙️', label: '設定・環境情報' },
];

export default function Sidebar() {
  const pathname = usePathname();

  return (
    <nav className="sidebar">
      <div className="sidebar-logo">
        AIQUIZ<span> Admin</span>
      </div>

      {navItems.map((item, i) => {
        if (item.section) {
          return <div key={i} className="sidebar-section">{item.label}</div>;
        }
        return (
          <Link
            key={item.href}
            href={item.href!}
            className={`sidebar-link ${pathname === item.href ? 'active' : ''}`}
          >
            <span>{item.icon}</span>
            {item.label}
          </Link>
        );
      })}

      <div className="sidebar-footer">
        AIQUIZ Dashboard v1.0<br />
        © 2026 AIQUIZ Project
      </div>
    </nav>
  );
}
