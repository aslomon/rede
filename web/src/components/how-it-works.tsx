import type { Dictionary } from "@/i18n/dictionaries";
import { SectionHeading } from "@/components/section-heading";

export function HowItWorks({ dict }: { dict: Dictionary }) {
  const h = dict.how;
  return (
    <section id="how" className="panel section scroll-mt-24 hairline-t">
      <div className="shell">
        <SectionHeading eyebrow="workflow" title={h.heading} sub={h.sub} />

        {/* left-anchored timeline: a waveform connects the three steps */}
        <ol className="mt-14 max-w-3xl">
          {h.steps.map((step, i) => {
            const last = i === h.steps.length - 1;
            return (
              <li
                key={step.n}
                className="group relative grid grid-cols-[auto_1fr] gap-6 pb-10 last:pb-0 sm:gap-8"
              >
                {/* numeral rail + connecting wave line */}
                <div className="relative flex flex-col items-center">
                  <span className="t-mono relative z-10 inline-flex size-12 shrink-0 items-center justify-center rounded-xl glass text-base font-semibold text-cloud transition-colors group-hover:border-[var(--hairline-strong)] sm:size-14">
                    {step.n}
                  </span>
                  {!last && <WaveConnector />}
                </div>

                {/* step content */}
                <div className="pt-1.5 sm:pt-2.5">
                  <h3 className="t-h3 text-cloud">{step.title}</h3>
                  <p className="t-body mt-2 max-w-xl">{step.desc}</p>
                </div>
              </li>
            );
          })}
        </ol>
      </div>
    </section>
  );
}

/* a thin vertical waveform that links one step to the next */
function WaveConnector() {
  return (
    <span aria-hidden className="relative mt-2 flex flex-1 w-px justify-center">
      <span
        className="absolute inset-y-0 w-px"
        style={{
          background:
            "linear-gradient(to bottom, var(--color-lime) 0%, color-mix(in srgb, var(--color-violet) 60%, transparent) 60%, transparent 100%)",
          opacity: 0.55,
        }}
      />
      <span className="absolute inset-y-1 flex flex-col items-center justify-around">
        {[0, 1, 2, 3].map((d) => (
          <span
            key={d}
            className="block size-1 rounded-full bg-lime"
            style={{
              animation: "rede-glow 1.8s ease-in-out infinite",
              animationDelay: `${d * 240}ms`,
            }}
          />
        ))}
      </span>
    </span>
  );
}
