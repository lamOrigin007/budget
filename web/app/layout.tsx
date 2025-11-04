import './globals.css';
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Family Budget',
  description: 'Базовая система семейного бюджета'
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ru">
      <body>{children}</body>
    </html>
  );
}
