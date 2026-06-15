import Link from "next/link";
import { notFound } from "next/navigation";
import { isLocale } from "@/lib/site";
import { getDictionary } from "@/i18n/dictionaries";

export default async function DocsIndex(props: PageProps<"/[locale]">) {
  const { locale } = await props.params;
  if (!isLocale(locale)) notFound();
  const dict = getDictionary(locale);
  const page = dict.docs.pages.index;
  const base = `/${locale}/docs`;

  return (
    <div>
      <h2 className="text-2xl font-bold tracking-tight text-cloud">
        {page.title}
      </h2>
      <p className="mt-4 max-w-2xl text-lg leading-relaxed text-cloud/60">
        {page.intro}
      </p>

      <div className="mt-10 grid gap-4 sm:grid-cols-2">
        {page.cards.map((card) => (
          <Link
            key={card.to}
            href={`${base}/${card.to}`}
            className="group rounded-xl glass p-5 transition-colors hover:border-[var(--hairline-strong)]"
          >
            <div className="flex items-center justify-between">
              <h3 className="font-semibold text-cloud">{card.title}</h3>
              <span className="text-violet-soft transition-transform group-hover:translate-x-0.5">
                →
              </span>
            </div>
            <p className="mt-1.5 text-sm leading-relaxed text-cloud/55">
              {card.desc}
            </p>
          </Link>
        ))}
      </div>
    </div>
  );
}
