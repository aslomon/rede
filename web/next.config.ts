import type { NextConfig } from "next";

/**
 * Static export for GitHub Pages project site at aslomon.github.io/rede.
 * - `output: "export"` → fully static `out/` (no Node server, no middleware).
 * - `basePath`/`assetPrefix` → everything is served under /rede.
 * - images unoptimized → next/image works without the Vercel optimizer.
 * - trailingSlash → folder-style URLs (/de/ → /de/index.html) that Pages serves cleanly.
 *
 * Locale routing: the Node `proxy.ts` Accept-Language redirect cannot run on a
 * static host, so it was removed; the site defaults to German via a root redirect
 * (public/index.html → de/). Language can still be switched in the header.
 */
const REPO = "rede";

const nextConfig: NextConfig = {
  output: "export",
  basePath: `/${REPO}`,
  assetPrefix: `/${REPO}/`,
  trailingSlash: true,
  images: { unoptimized: true },
};

export default nextConfig;
