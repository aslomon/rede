import Link from "next/link";
import { site } from "@/lib/site";
import type { Dictionary } from "@/i18n/dictionaries";
import { WaveMark } from "@/components/wave-mark";

export function DownloadCTA({ dict }: { dict: Dictionary }) {
  const d = dict.download;
  return (
    <section id="download" className="section scroll-mt-24">
      <div className="shell">
        <div className="relative overflow-hidden rounded-[2.5rem] glass-strong px-6 py-20 text-center sm:px-12 sm:py-24">
          {/* layered aurora blooms — the most confident moment on the page */}
          <div
            aria-hidden
            className="pointer-events-none absolute left-1/2 top-[-10rem] size-[34rem] -translate-x-1/2 rounded-full blur-[120px]"
            style={{
              background:
                "radial-gradient(closest-side, rgba(110,86,248,0.55), transparent)",
            }}
          />
          <div
            aria-hidden
            className="pointer-events-none absolute -bottom-32 -left-24 size-80 rounded-full blur-[110px]"
            style={{
              background:
                "radial-gradient(closest-side, rgba(204,255,26,0.16), transparent)",
            }}
          />
          <div
            aria-hidden
            className="pointer-events-none absolute -right-24 top-1/3 size-72 rounded-full blur-[110px]"
            style={{
              background:
                "radial-gradient(closest-side, rgba(142,123,255,0.28), transparent)",
            }}
          />

          <div className="relative mx-auto max-w-2xl">
            {/* hero wave-mark accent */}
            <span
              className="mx-auto flex size-16 items-center justify-center rounded-2xl glass"
              style={{ boxShadow: "0 0 60px rgba(204,255,26,0.12)" }}
            >
              <WaveMark className="h-7" />
            </span>

            <h2 className="t-h1 mt-8">
              <span className="text-electric">{d.heading}</span>
            </h2>

            <p className="t-lead mx-auto mt-5 max-w-md">{d.sub}</p>

            <div className="mt-10 flex flex-col items-center justify-center gap-3 sm:flex-row">
              <Link
                href={site.download}
                className="group inline-flex items-center gap-2 rounded-full bg-lime px-8 py-4 text-base font-semibold text-ink shadow-lg shadow-lime/15 transition-transform hover:scale-[1.03] active:scale-100"
              >
                <DownloadGlyph />
                {d.cta}
              </Link>
              <Link
                href={site.github}
                className="inline-flex items-center gap-2 rounded-full glass px-8 py-4 text-base font-semibold text-cloud transition-colors hover:border-[var(--hairline-strong)] active:opacity-80"
              >
                {d.secondary}
              </Link>
            </div>

            <p className="t-mono mx-auto mt-9 max-w-md uppercase tracking-[0.12em] text-cloud/45">
              {d.requirement}
            </p>
            <p className="t-small mx-auto mt-4 max-w-sm">{d.note}</p>
          </div>
        </div>
      </div>
    </section>
  );
}

function DownloadGlyph() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 16 16"
      fill="none"
      aria-hidden
      className="transition-transform group-hover:translate-y-0.5"
    >
      <path
        d="M8 1.5v9M8 10.5 4.5 7M8 10.5 11.5 7M2.5 13.5h11"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
