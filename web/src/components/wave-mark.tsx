import { clsx } from "@/lib/cn";

/**
 * Animated voice waveform — the rede brand motif as live equalizer bars.
 * Crisp lime bars that grow from the baseline via the `rede-wave` scaleY
 * keyframe. The root takes its height from the caller's className (e.g.
 * "h-6"/"h-8") — do NOT add h-full here, percentage bar heights need a
 * definite parent height to resolve. Respects prefers-reduced-motion
 * (global CSS freezes the animation into a legible static waveform).
 */
export function WaveMark({
  className,
  animate = true,
}: {
  className?: string;
  animate?: boolean;
}) {
  // base heights form a soft asymmetric crest; durations/delays add life.
  const bars = [
    { h: 38, dur: 1.1, delay: 0 },
    { h: 64, dur: 0.9, delay: 0.16 },
    { h: 88, dur: 1.25, delay: 0.07 },
    { h: 100, dur: 0.8, delay: 0.22 },
    { h: 72, dur: 1.15, delay: 0.1 },
    { h: 94, dur: 0.95, delay: 0.28 },
    { h: 54, dur: 1.2, delay: 0.14 },
    { h: 80, dur: 0.85, delay: 0.04 },
    { h: 46, dur: 1.05, delay: 0.2 },
    { h: 68, dur: 0.92, delay: 0.12 },
    { h: 34, dur: 1.18, delay: 0.24 },
  ];

  return (
    <span
      className={clsx("inline-flex items-end gap-[2px]", className)}
      aria-hidden
    >
      {bars.map((bar, i) => (
        <span
          key={i}
          className="w-[3px] shrink-0 rounded-full bg-lime"
          style={{
            height: `${bar.h}%`,
            transformOrigin: "bottom",
            willChange: animate ? "transform" : undefined,
            animation: animate
              ? `rede-wave ${bar.dur}s var(--ease-out-soft) ${bar.delay}s infinite alternate`
              : undefined,
          }}
        />
      ))}
    </span>
  );
}
