import { clsx } from "@/lib/cn";

export function SectionHeading({
  eyebrow,
  title,
  sub,
  className,
}: {
  eyebrow?: string;
  title: string;
  sub?: string;
  className?: string;
}) {
  return (
    <div className={clsx("max-w-2xl", className)}>
      {eyebrow && (
        <span className="t-eyebrow inline-flex items-center gap-2">
          <span className="h-px w-5 bg-lime" />
          {eyebrow}
        </span>
      )}
      <h2 className="t-h2 mt-3">{title}</h2>
      {sub && <p className="t-lead mt-3">{sub}</p>}
    </div>
  );
}
