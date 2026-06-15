import { notFound } from "next/navigation";
import { isLocale } from "@/lib/site";
import { getDictionary } from "@/i18n/dictionaries";
import { DocsSidebar } from "@/components/docs-sidebar";

export default async function DocsLayout(props: LayoutProps<"/[locale]">) {
  const { locale } = await props.params;
  if (!isLocale(locale)) notFound();
  const dict = getDictionary(locale);

  return (
    <div className="mx-auto max-w-6xl px-5 py-14">
      <header className="mb-10">
        <h1 className="text-4xl font-bold tracking-tight">{dict.docs.title}</h1>
        <p className="mt-2 max-w-xl text-lg text-cloud/55">{dict.docs.sub}</p>
      </header>
      <div className="grid gap-10 lg:grid-cols-[15rem_1fr]">
        <aside>
          <DocsSidebar locale={locale} dict={dict} />
        </aside>
        <div className="min-w-0">{props.children}</div>
      </div>
    </div>
  );
}
