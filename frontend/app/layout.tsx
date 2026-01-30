import './globals.css';
import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import { Analytics } from '@vercel/analytics/react';
import { SpeedInsights } from '@vercel/speed-insights/next';
import { Providers } from './providers';

const inter = Inter({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: 'Smart Contract Frontend',
  description: 'Built by Ember 🐉',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className={inter.className}>
        <Providers>
          {children}
        </Providers>
        {/* Vercel Analytics - tracks page views, visitors, etc. */}
        <Analytics />
        {/* Vercel Speed Insights - tracks Core Web Vitals */}
        <SpeedInsights />
      </body>
    </html>
  );
}
