import Link from "next/link";
import type { Locale } from "@/lib/site";
import { site } from "@/lib/site";
import type { Dictionary } from "@/i18n/dictionaries";
import { Wordmark } from "@/components/wordmark";

export function SiteFooter({
  locale,
  dict,
}: {
  locale: Locale;
  dict: Dictionary;
}) {
  const base = `/${locale}`;
  const f = dict.footer;
  const year = new Date().getFullYear();

  const columns = [
    {
      title: f.cols.product,
      links: [
        { href: `${base}#features`, label: f.links.features },
        { href: site.download, label: f.links.download },
      ],
    },
    {
      title: f.cols.resources,
      links: [
        { href: `${base}/docs`, label: f.links.docs },
        { href: site.github, label: f.links.github },
      ],
    },
    {
      title: f.cols.legal,
      links: [
        { href: `${base}/datenschutz`, label: f.links.privacy },
        { href: `${base}/impressum`, label: f.links.imprint },
      ],
    },
  ];

  return (
    <footer className="hairline-t relative mt-24">
      {/* thin lime waveform divider riding the top hairline */}
      <span
        aria-hidden
        className="pointer-events-none absolute -top-px left-0 flex h-px w-full items-center"
      >
        <span className="flex h-3 -translate-y-1/2 items-end gap-[3px] pl-[1.25rem] opacity-70">
          {[0.4, 0.75, 0.55, 1, 0.65, 0.35, 0.85, 0.5].map((h, i) => (
            <span
              key={i}
              className="signal w-[2px] rounded-full bg-current"
              style={{ height: `${h * 100}%` }}
            />
          ))}
        </span>
      </span>

      <div className="shell grid gap-12 py-16 sm:grid-cols-2 lg:grid-cols-[1.5fr_1fr_1fr_1fr]">
        {/* wordmark block + tagline */}
        <div className="max-w-xs">
          <Link
            href={base}
            className="inline-block text-3xl transition-opacity hover:opacity-80"
          >
            <Wordmark />
          </Link>
          <p className="t-small mt-5 text-cloud/60">{f.tagline}</p>
          <p className="t-small mt-2 text-cloud/40">{f.builtWith}</p>
        </div>

        {/* link columns */}
        {columns.map((col) => (
          <nav key={col.title} aria-label={col.title}>
            <h3 className="t-eyebrow">{col.title}</h3>
            <ul className="mt-5 flex flex-col gap-3">
              {col.links.map((link) => (
                <li key={link.href}>
                  <Link
                    href={link.href}
                    className="group t-small inline-flex items-center gap-2 text-cloud/65 transition-colors hover:text-cloud"
                  >
                    <span
                      aria-hidden
                      className="signal h-[3px] w-0 rounded-full bg-current opacity-0 transition-all duration-200 group-hover:w-2 group-hover:opacity-100"
                    />
                    {link.label}
                  </Link>
                </li>
              ))}
            </ul>
          </nav>
        ))}
      </div>

      {/* muted bottom row */}
      <div className="hairline-t">
        <div className="shell flex flex-col gap-1 py-6 sm:flex-row sm:items-center sm:gap-3">
          <p className="t-small text-cloud/35">
            © {year} <span className="text-cloud/55">rede</span>
            <span className="brand-dot">.</span>
          </p>
          <span aria-hidden className="hidden text-cloud/20 sm:inline">
            ·
          </span>
          <p className="t-small text-cloud/35">{site.license}</p>
          <span aria-hidden className="hidden text-cloud/20 sm:inline">
            ·
          </span>
          <p className="t-small text-cloud/35">{f.rights}</p>
        </div>
      </div>
    </footer>
  );
}
