import "./globals.css";
import Sidebar from '../components/Sidebar';
import { ToastProvider } from '../components/ToastProvider';

export const metadata = {
  title: "AIQUIZ Dashboard",
  description: "AIQUIZのバックエンド、モデル、JSONバンクを管理",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ja">
      <body>
        <ToastProvider>
          <div className="container">
            <Sidebar />
            <main className="main-content">
              {children}
            </main>
          </div>
        </ToastProvider>
      </body>
    </html>
  );
}
