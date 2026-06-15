import type { Dictionary } from "@/i18n/dictionaries";
import { SectionHeading } from "@/components/section-heading";

export function Privacy({ dict }: { dict: Dictionary }) {
  const p = dict.privacy;
  return (
    <section id="privacy" className="section scroll-mt-24">
      <div className="shell">
        <SectionHeading eyebrow="datenschutz" title={p.heading} sub={p.sub} />

        {/* hard two-tone split: local (lime) vs online (violet) */}
        <div className="mt-12 grid gap-px overflow-hidden rounded-3xl border border-[var(--hairline)] bg-[var(--hairline)] lg:grid-cols-2">
          {p.columns.map((col) => {
            const isLime = col.tone === "lime";
            const accent = isLime ? "var(--color-lime)" : "var(--color-violet)";
            return (
              <div
                key={col.key}
                className="relative overflow-hidden bg-ink p-7 sm:p-9"
              >
                {/* tinted field for the column */}
                <div
                  aria-hidden
                  className="pointer-events-none absolute -top-24 size-72 rounded-full blur-3xl"
                  style={{
                    background: accent,
                    opacity: isLime ? 0.07 : 0.16,
                    left: isLime ? "-3rem" : "auto",
                    right: isLime ? "auto" : "-3rem",
                  }}
                />
                <div className="relative">
                  <div className="flex items-center gap-3">
                    <span
                      className="rounded-full px-3 py-1 text-xs font-bold uppercase tracking-wide text-ink"
                      style={{ background: accent }}
                    >
                      {col.label}
                    </span>
                    <h3 className="t-h3 text-cloud">{col.title}</h3>
                  </div>
                  <ul className="mt-6 space-y-3.5">
                    {col.points.map((point, i) => (
                      <li key={i} className="flex gap-3 text-cloud/65">
                        <span
                          className="mt-2 size-1.5 shrink-0 rounded-full"
                          style={{ background: accent }}
                        />
                        <span className="leading-relaxed">{point}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
