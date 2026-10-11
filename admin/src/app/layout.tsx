import type { Metadata } from "next";
import localFont from "next/font/local";
import "./globals.css";
const prompt = localFont({
  src: [
    { path: "../fonts/Prompt-Regular.ttf", weight: "400" },
    { path: "../fonts/Prompt-Medium.ttf", weight: "500" },
    { path: "../fonts/Prompt-SemiBold.ttf", weight: "600" },
    { path: "../fonts/Prompt-Bold.ttf", weight: "700" },
  ],
  variable: "--font-prompt",
  display: "swap",
});
export const metadata: Metadata = {
  title: "ยืมหน่อย · Dashboard",
  description: "ศูนย์จัดการแอปยืมหน่อย",
  robots: { index: false, follow: false },
};
export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="th" suppressHydrationWarning>
      <body className={prompt.variable}>{children}</body>
    </html>
  );
}
