import { notFound } from "next/navigation";
import { isLocale } from "@/lib/site";
import { getDictionary } from "@/i18n/dictionaries";

export default async function ImprintPage(props: PageProps<"/[locale]">) {
  const { locale } = await props.params;
  if (!isLocale(locale)) notFound();
  const im = getDictionary(locale).legal.imprint;

  return (
    <article className="mx-auto max-w-3xl px-5 py-20">
      <h1 className="text-4xl font-bold tracking-tight">{im.title}</h1>
      <p className="mt-6 text-lg leading-relaxed text-cloud/65">{im.intro}</p>

      <div className="mt-6 rounded-xl glass px-4 py-3 text-sm text-mode-dampf">
        {im.placeholder}
      </div>

      <div className="mt-10 space-y-8">
        {im.sections.map((s) => (
          <section key={s.h}>
            <h2 className="text-xl font-semibold text-cloud">{s.h}</h2>
            <p className="mt-2 whitespace-pre-line leading-relaxed text-cloud/60">
              {s.p}
            </p>
          </section>
        ))}
      </div>
    </article>
  );
}
