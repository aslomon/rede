"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { Locale } from "@/lib/site";
import type { Dictionary } from "@/i18n/dictionaries";
import { clsx } from "@/lib/cn";

export function DocsSidebar({
  locale,
  dict,
}: {
  locale: Locale;
  dict: Dictionary;
}) {
  const pathname = usePathname() ?? "";
  const base = `/${locale}/docs`;
  const items = [
    { href: base, label: dict.docs.nav.index },
    { href: `${base}/setup`, label: dict.docs.nav.setup },
    { href: `${base}/hotkeys`, label: dict.docs.nav.hotkeys },
    { href: `${base}/openai`, label: dict.docs.nav.openai },
    { href: `${base}/local`, label: dict.docs.nav.local },
  ];

  return (
    <nav className="lg:sticky lg:top-24">
      <p className="t-eyebrow flex items-center gap-2 px-3">
        <span className="h-px w-4 bg-lime" />
        {dict.docs.tocLabel}
      </p>
      <ul className="mt-5 space-y-1.5">
        {items.map((item) => {
          const active = pathname === item.href || pathname === `${item.href}/`;
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={clsx(
                  "group relative flex items-center rounded-lg py-2.5 pl-5 pr-3 text-sm transition-colors",
                  active
                    ? "bg-violet/15 font-semibold text-cloud"
                    : "text-cloud/50 hover:bg-cloud/5 hover:text-cloud/80",
                )}
              >
                <span
                  aria-hidden
                  className={clsx(
                    "absolute left-2 top-1/2 w-0.5 -translate-y-1/2 rounded-full bg-lime transition-all duration-200",
                    active
                      ? "h-4 opacity-100"
                      : "h-2 opacity-0 group-hover:opacity-40",
                  )}
                />
                {item.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
