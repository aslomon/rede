import { notFound } from "next/navigation";
import { isLocale } from "@/lib/site";
import { getDictionary } from "@/i18n/dictionaries";

export default async function PrivacyPage(props: PageProps<"/[locale]">) {
  const { locale } = await props.params;
  if (!isLocale(locale)) notFound();
  const p = getDictionary(locale).legal.privacy;

  return (
    <article className="mx-auto max-w-3xl px-5 py-20">
      <h1 className="text-4xl font-bold tracking-tight">{p.title}</h1>
      <p className="mt-2 font-mono text-xs uppercase tracking-wider text-cloud/40">
        {p.updated}
      </p>
      <p className="mt-6 text-lg leading-relaxed text-cloud/65">{p.intro}</p>

      <div className="mt-10 space-y-8">
        {p.sections.map((s) => (
          <section key={s.h}>
            <h2 className="text-xl font-semibold text-cloud">{s.h}</h2>
            <p className="mt-2 leading-relaxed text-cloud/60">{s.p}</p>
          </section>
        ))}
      </div>
    </article>
  );
}
