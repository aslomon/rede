"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { locales, type Locale } from "@/lib/site";
import { clsx } from "@/lib/cn";

/** DE/EN toggle that preserves the current path. */
export function LocaleSwitch({ current }: { current: Locale }) {
  const pathname = usePathname() ?? `/${current}`;

  function swapTo(locale: Locale): string {
    const parts = pathname.split("/");
    parts[1] = locale; // first segment after the leading slash is the locale
    return parts.join("/") || `/${locale}`;
  }

  return (
    <div className="flex items-center gap-0.5 rounded-full glass px-0.5 py-0.5 text-xs font-semibold">
      {locales.map((locale) => {
        const active = locale === current;
        return (
          <Link
            key={locale}
            href={swapTo(locale)}
            aria-current={active ? "true" : undefined}
            className={clsx(
              "rounded-full px-2.5 py-1 uppercase tracking-wide transition-colors",
              active
                ? "bg-violet text-white"
                : "text-cloud/55 hover:text-cloud",
            )}
          >
            {locale}
          </Link>
        );
      })}
    </div>
  );
}
