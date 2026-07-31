import type { Metadata } from "next";
import { headers } from "next/headers";
import { Space_Grotesk, Instrument_Sans, JetBrains_Mono } from "next/font/google";
import "./globals.css";
import { Providers } from "./providers";

const display = Space_Grotesk({
  subsets: ["latin"],
  weight: ["500", "600", "700"],
  variable: "--font-space",
  display: "swap",
});

const sans = Instrument_Sans({
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  variable: "--font-instrument",
  display: "swap",
});

const mono = JetBrains_Mono({
  subsets: ["latin"],
  weight: ["400", "500", "700"],
  variable: "--font-jetbrains",
  display: "swap",
});

const title = "NoteClaw Memory — Durable MCP Memory for AI Agents";
const description =
  "Give AI agents durable namespaced memory, automatic compaction, and live WebSocket presence through focused MCP tools.";

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host =
    requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host");
  const protocol =
    requestHeaders.get("x-forwarded-proto") ??
    (host?.includes("localhost") ? "http" : "https");
  const origin = host
    ? `${protocol}://${host}`
    : process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";
  const socialImage = new URL("/og.png", origin).toString();

  return {
    metadataBase: new URL(origin),
    title,
    description,
    alternates: {
      canonical: "/",
    },
    icons: {
      icon: "/icon.png",
      apple: "/icon.png",
    },
    openGraph: {
      type: "website",
      url: "/",
      siteName: "NoteClaw Memory",
      title,
      description,
      images: [
        {
          url: socialImage,
          width: 1728,
          height: 907,
          alt: "NoteClaw Memory — Memory that survives the session.",
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [socialImage],
    },
  };
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={`${display.variable} ${sans.variable} ${mono.variable} antialiased`}>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
