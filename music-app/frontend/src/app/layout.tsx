import type { Metadata } from "next";
import { Geist, Manrope } from "next/font/google";
import type { ReactNode } from "react";
import "./globals.css";

const geist = Geist({ variable: "--font-geist", subsets: ["latin"] });
const manrope = Manrope({ variable: "--font-manrope", subsets: ["latin"] });

export const metadata: Metadata = {
  title: "InnerWave — Dynamic Music",
  description: "A dynamic music experience powered by InnerTube.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className={`${geist.variable} ${manrope.variable}`} suppressHydrationWarning>
      <body suppressHydrationWarning>{children}</body>
    </html>
  );
}
