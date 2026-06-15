import { clsx } from "@/lib/cn";

/**
 * The rede wordmark — always lowercase, with the lime accent dot.
 * The dot is the brand's voice cue (lime on dark only, per DESIGN.md).
 */
export function Wordmark({
  className,
  dotClassName,
}: {
  className?: string;
  dotClassName?: string;
}) {
  return (
    <span className={clsx("font-sans font-bold tracking-tight", className)}>
      rede<span className={clsx("brand-dot", dotClassName)}>.</span>
    </span>
  );
}
