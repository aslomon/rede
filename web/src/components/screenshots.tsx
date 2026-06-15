import Image from "next/image";
import type { Dictionary } from "@/i18n/dictionaries";
import { SectionHeading } from "@/components/section-heading";
import { clsx } from "@/lib/cn";

const DIMS: Record<string, { w: number; h: number }> = {
  "/screenshots/menubar.png": { w: 842, h: 716 },
  "/screenshots/modes.png": { w: 836, h: 1220 },
  "/screenshots/local-models.png": { w: 1128, h: 1340 },
};

export function Screenshots({ dict }: { dict: Dictionary }) {
  const s = dict.shots;
  const [feature, ...rest] = s.items;
  const featureDim = feature
    ? (DIMS[feature.src] ?? { w: 900, h: 1000 })
    : null;

  return (
    <section className="section">
      <div className="shell">
        <SectionHeading title={s.heading} sub={s.sub} eyebrow="screenshots" />

        {/* offset gallery: one large featured shot + two smaller, offset beside/below */}
        <div className="mt-12 grid items-start gap-5 lg:grid-cols-12">
          {/* featured showcase — wider, device-ish glass mat */}
          {feature && featureDim && (
            <figure className="group relative lg:col-span-7">
              <div
                aria-hidden
                className="pointer-events-none absolute -inset-6 -z-10 rounded-[2rem] bg-violet/10 opacity-0 blur-3xl transition-opacity duration-500 group-hover:opacity-100"
              />
              <div className="overflow-hidden rounded-[1.75rem] glass-strong p-3 transition-colors duration-300 hover:border-[var(--hairline-strong)]">
                {/* device-ish title bar */}
                <div className="flex items-center gap-1.5 px-2 pb-2.5 pt-1">
                  <span className="size-2.5 rounded-full bg-cloud/15" />
                  <span className="size-2.5 rounded-full bg-cloud/15" />
                  <span className="size-2.5 rounded-full bg-lime/60" />
                </div>
                <div className="overflow-hidden rounded-2xl bg-ink-2/70">
                  <Image
                    src={feature.src}
                    alt={feature.caption}
                    width={featureDim.w}
                    height={featureDim.h}
                    sizes="(max-width: 1024px) 100vw, 58vw"
                    priority
                    className="h-full w-full object-cover object-top transition-transform duration-500 ease-out group-hover:scale-[1.02]"
                  />
                </div>
              </div>
              <figcaption className="mt-4 flex items-center gap-2.5 px-1">
                <span className="size-1.5 shrink-0 rounded-full bg-lime" />
                <span className="t-small text-cloud/70">{feature.caption}</span>
              </figcaption>
            </figure>
          )}

          {/* the two smaller shots, offset in a stacked column */}
          <div className="flex flex-col gap-5 lg:col-span-5 lg:pt-10">
            {rest.map((shot, i) => {
              const dim = DIMS[shot.src] ?? { w: 900, h: 1000 };
              return (
                <figure
                  key={shot.src}
                  className={clsx(
                    "group overflow-hidden rounded-2xl glass p-2.5 transition-colors duration-300 hover:border-[var(--hairline-strong)]",
                    i === 1 && "lg:ml-8",
                  )}
                >
                  <div className="overflow-hidden rounded-xl bg-ink-2/60">
                    <Image
                      src={shot.src}
                      alt={shot.caption}
                      width={dim.w}
                      height={dim.h}
                      sizes="(max-width: 1024px) 100vw, 38vw"
                      className="h-52 w-full object-cover object-top transition-transform duration-500 ease-out group-hover:scale-[1.03] sm:h-64"
                    />
                  </div>
                  <figcaption className="flex items-center gap-2.5 px-2 py-3">
                    <span className="size-1.5 shrink-0 rounded-full bg-cloud/30" />
                    <span className="t-small text-cloud/60">
                      {shot.caption}
                    </span>
                  </figcaption>
                </figure>
              );
            })}
          </div>
        </div>
      </div>
    </section>
  );
}
