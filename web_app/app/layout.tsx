import type { Metadata } from "next";
import { headers } from "next/headers";
import "./globals.css";
import { Providers } from "./providers";

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
      <body className="antialiased">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
