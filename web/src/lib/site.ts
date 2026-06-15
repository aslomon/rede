/**
 * Central site configuration for the rede marketing site.
 * Download points at the notarized .dmg published via GitHub Releases.
 */

export const site = {
  name: "rede",
  /** public URL once deployed (used for metadata / OG). */
  url: "https://rede.app",
  /** GitHub repository (source + releases). */
  github: "https://github.com/aslomon/rede",
  /** Latest release page — the download button links here until a fixed asset URL exists. */
  releases: "https://github.com/aslomon/rede/releases/latest",
  /** Direct .dmg asset (fill in once a release asset name is fixed). */
  download: "https://github.com/aslomon/rede/releases/latest",
  /** Sparkle auto-update feed (mirrors Info.plist SUFeedURL). */
  appcast: "https://aslomon.github.io/rede/appcast.xml",
  /** Minimum supported macOS version shown in the UI. */
  minMacOS: "macOS 14",
  license: "MIT",
} as const;

export const locales = ["de", "en"] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = "de";

export function isLocale(value: string): value is Locale {
  return (locales as readonly string[]).includes(value);
}
