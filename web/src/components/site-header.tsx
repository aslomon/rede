import Link from "next/link";
import type { Locale } from "@/lib/site";
import { site } from "@/lib/site";
import type { Dictionary } from "@/i18n/dictionaries";
import { Wordmark } from "@/components/wordmark";
import { LocaleSwitch } from "@/components/locale-switch";

export function SiteHeader({
  locale,
  dict,
}: {
  locale: Locale;
  dict: Dictionary;
}) {
  const base = `/${locale}`;
  const nav = [
    { href: `${base}#features`, label: dict.nav.features },
    { href: `${base}#how`, label: dict.nav.how },
    { href: `${base}#privacy`, label: dict.nav.privacy },
    { href: `${base}/docs`, label: dict.nav.docs },
  ];

  return (
    <header className="sticky top-0 z-50 px-3 pt-3">
      <div className="shell !px-0">
        <div className="flex items-center gap-4 rounded-full glass-strong px-3 py-2 shadow-xl shadow-ink/40 sm:px-4 sm:py-2.5">
          {/* wordmark — left */}
          <Link
            href={base}
            className="shrink-0 rounded-full px-1.5 text-xl leading-none transition-opacity hover:opacity-80"
          >
            <Wordmark />
          </Link>

          {/* nav — centered, desktop only */}
          <nav className="hidden flex-1 items-center justify-center gap-1 md:flex">
            {nav.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className="group relative rounded-full px-3.5 py-1.5 text-sm font-medium text-cloud/65 transition-colors hover:text-cloud focus-visible:text-cloud"
              >
                <span className="relative z-10">{item.label}</span>
                {/* hover/active wash */}
                <span className="absolute inset-0 -z-0 rounded-full bg-white/0 transition-colors group-hover:bg-white/[0.06] group-active:bg-white/[0.1]" />
                {/* lime active tick */}
                <span className="absolute inset-x-3.5 -bottom-px h-px origin-center scale-x-0 bg-lime transition-transform duration-300 group-hover:scale-x-100" />
              </Link>
            ))}
          </nav>

          {/* right — locale + lime download pill */}
          <div className="ml-auto flex shrink-0 items-center gap-2 md:ml-0">
            <LocaleSwitch current={locale} />
            <Link
              href={site.download}
              className="hidden rounded-full bg-lime px-4 py-1.5 text-sm font-semibold text-ink shadow-md shadow-lime/15 transition-transform duration-200 ease-[var(--ease-out-soft)] hover:scale-[1.04] active:scale-100 sm:inline-flex sm:items-center sm:gap-1.5"
            >
              <DownloadGlyph />
              {dict.nav.download}
            </Link>
          </div>
        </div>
      </div>
    </header>
  );
}

function DownloadGlyph() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 16 16"
      fill="none"
      aria-hidden
      className="-ml-0.5"
    >
      <path
        d="M8 1.5v9M8 10.5 4.5 7M8 10.5 11.5 7M2.5 13.5h11"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
