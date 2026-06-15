import type { Dictionary } from "@/i18n/dictionaries";
import { SectionHeading } from "@/components/section-heading";
import { clsx } from "@/lib/cn";

/** column spans per mode — an asymmetric bento, not a uniform row of cards. */
const SPAN: Record<string, string> = {
  diktat: "sm:col-span-2 lg:col-span-3",
  lokal: "sm:col-span-2 lg:col-span-3",
  email: "lg:col-span-2",
  prompt: "lg:col-span-2",
  social: "lg:col-span-2",
};

export function Modes({ dict }: { dict: Dictionary }) {
  const m = dict.modes;
  return (
    <section id="features" className="section scroll-mt-24">
      <div className="shell">
        <SectionHeading eyebrow="modi" title={m.heading} sub={m.sub} />

        <div className="mt-12 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-6">
          {m.items.map((mode) => {
            const feature = mode.key === "diktat" || mode.key === "lokal";
            return (
              <article
                key={mode.key}
                className={clsx(
                  "group relative overflow-hidden rounded-2xl p-6 transition-all duration-300 hover:-translate-y-0.5 sm:p-7",
                  SPAN[mode.key],
                )}
                style={{
                  background: `color-mix(in srgb, ${mode.accent} 7%, var(--surface))`,
                  border: `0.5px solid color-mix(in srgb, ${mode.accent} 24%, var(--hairline))`,
                }}
              >
                {/* accent bloom that warms on hover */}
                <div
                  aria-hidden
                  className="pointer-events-none absolute -right-12 -top-12 size-36 rounded-full opacity-20 blur-3xl transition-opacity duration-300 group-hover:opacity-45"
                  style={{ background: mode.accent }}
                />

                <div className="relative flex h-full flex-col">
                  <div className="flex items-center gap-3">
                    <span
                      className={clsx(
                        "inline-flex shrink-0 items-center justify-center rounded-xl text-ink",
                        feature ? "size-12" : "size-10",
                      )}
                      style={{ background: mode.accent }}
                    >
                      <ModeIcon kind={mode.key} size={feature ? 22 : 19} />
                    </span>
                    <div className="min-w-0">
                      <h3 className="t-h3 text-cloud">{mode.name}</h3>
                      <span
                        className="text-sm font-medium"
                        style={{ color: mode.accent }}
                      >
                        {mode.tagline}
                      </span>
                    </div>
                  </div>

                  <p className="t-body mt-4 max-w-md">{mode.desc}</p>

                  {feature && (
                    <span className="t-mono mt-5 inline-flex w-fit items-center gap-1.5 rounded-md bg-white/[0.05] px-2 py-1 text-cloud/55">
                      <span className="size-1.5 rounded-full bg-lime" />
                      eigener hotkey
                    </span>
                  )}
                </div>
              </article>
            );
          })}
        </div>
      </div>
    </section>
  );
}

/* one SVG per mode concept, mirroring the app's SF-symbol language */
function ModeIcon({ kind, size }: { kind: string; size: number }) {
  const common = {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 1.8,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
  };
  switch (kind) {
    case "diktat":
      return (
        <svg {...common}>
          <rect x="9" y="2.5" width="6" height="11" rx="3" />
          <path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21M8.5 21h7" />
        </svg>
      );
    case "lokal":
      return (
        <svg {...common}>
          <path d="M12 2.5 4.5 5.5v5c0 4.5 3 8.3 7.5 10 4.5-1.7 7.5-5.5 7.5-10v-5L12 2.5Z" />
          <path d="M9.2 11.8l2 2 3.6-3.8" />
        </svg>
      );
    case "email":
      return (
        <svg {...common}>
          <rect x="3" y="5" width="18" height="14" rx="2.5" />
          <path d="M3.5 7.5 12 13l8.5-5.5" />
        </svg>
      );
    case "prompt":
      return (
        <svg {...common}>
          <rect x="2.5" y="4" width="19" height="16" rx="2.5" />
          <path d="M7 10l2.5 2L7 14M12.5 14.5h4" />
        </svg>
      );
    case "social":
      return (
        <svg {...common}>
          <path d="M4 5.5h13a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2H9l-4 3.5V14.5a2 2 0 0 1-2-2v-5a2 2 0 0 1 1-1.7" />
          <path d="M8.5 9.5h6M8.5 12h4" />
        </svg>
      );
    default:
      return null;
  }
}
