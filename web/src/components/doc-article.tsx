export function DocArticle({
  title,
  blocks,
}: {
  title: string;
  blocks: ReadonlyArray<{ h: string; p: string }>;
}) {
  return (
    <article>
      <h2 className="t-h2 text-cloud">{title}</h2>

      <div className="mt-10 flex flex-col gap-px">
        {blocks.map((block, i) => (
          <section
            key={block.h}
            className="group relative grid grid-cols-[auto_1fr] gap-x-5 py-7 hairline-t first:border-t-0 first:pt-0 sm:gap-x-7"
          >
            {/* lime index tick + accent rule */}
            <div className="flex flex-col items-center pt-1.5">
              <span className="t-mono text-lime/90">
                {String(i + 1).padStart(2, "0")}
              </span>
              <span className="mt-3 w-px flex-1 bg-[var(--hairline)] transition-colors group-hover:bg-lime/40" />
            </div>

            <div className="min-w-0 max-w-[65ch]">
              <h3 className="t-h3 text-cloud">{block.h}</h3>
              <p className="t-body mt-2">{block.p}</p>
            </div>
          </section>
        ))}
      </div>
    </article>
  );
}
