import Link from "next/link";
import type { Locale } from "@/lib/site";
import { site } from "@/lib/site";
import type { Dictionary } from "@/i18n/dictionaries";
import { WaveMark } from "@/components/wave-mark";

export function Hero({ dict }: { locale: Locale; dict: Dictionary }) {
  const h = dict.hero;
  return (
    <section className="relative overflow-hidden">
      {/* aurora wash anchored to the hero */}
      <div
        aria-hidden
        className="pointer-events-none absolute left-1/2 top-[-12rem] -z-0 size-[42rem] -translate-x-1/2 rounded-full opacity-60 blur-[120px]"
        style={{
          background:
            "radial-gradient(closest-side, rgba(110,86,248,0.5), transparent)",
        }}
      />

      <div className="shell relative pt-24 pb-12 text-center sm:pt-32">
        <span
          className="rede-rise chip mx-auto uppercase tracking-[0.14em] text-cloud/70"
          style={{ animationDelay: "0ms" }}
        >
          <span className="size-1.5 rounded-full bg-lime" />
          {h.eyebrow}
        </span>

        <h1
          className="rede-rise t-display mx-auto mt-7 max-w-4xl"
          style={{ animationDelay: "80ms" }}
        >
          <span className="text-electric">{h.titleLead}</span>
          <br />
          <span className="text-cloud/85">{h.titleAccent}</span>
        </h1>

        <p
          className="rede-rise t-lead mx-auto mt-7 max-w-xl"
          style={{ animationDelay: "160ms" }}
        >
          {h.sub}
        </p>

        <div
          className="rede-rise mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row"
          style={{ animationDelay: "240ms" }}
        >
          <Link
            href={site.download}
            className="group inline-flex items-center gap-2 rounded-full bg-lime px-6 py-3 text-base font-semibold text-ink shadow-lg shadow-lime/10 transition-transform hover:scale-[1.03] active:scale-100"
          >
            <DownloadGlyph />
            {h.ctaPrimary}
          </Link>
          <Link
            href={site.github}
            className="inline-flex items-center gap-2 rounded-full glass-strong px-6 py-3 text-base font-semibold text-cloud transition-colors hover:border-[var(--hairline-strong)]"
          >
            {h.ctaSecondary}
          </Link>
        </div>

        <p
          className="rede-rise t-small mx-auto mt-6 max-w-md"
          style={{ animationDelay: "320ms" }}
        >
          {h.smallprint}
        </p>
      </div>

      {/* floating recording pill — the brand's signature live object */}
      <div className="shell relative pb-20">
        <div
          className="rede-rise mx-auto flex w-fit items-center gap-4 rounded-full glass-strong px-6 py-4 shadow-2xl shadow-violet/25"
          style={{ animationDelay: "420ms" }}
        >
          <span
            className="size-3 rounded-full bg-violet"
            style={{ animation: "rede-glow 1.6s ease-in-out infinite" }}
          />
          <WaveMark className="h-6" />
          <span className="text-sm font-medium text-cloud/70">
            {h.badgeLive}
          </span>
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
