import { notFound } from "next/navigation";
import { isLocale } from "@/lib/site";
import { getDictionary } from "@/i18n/dictionaries";
import { DocArticle } from "@/components/doc-article";

export default async function DocHotkeys(props: PageProps<"/[locale]">) {
  const { locale } = await props.params;
  if (!isLocale(locale)) notFound();
  const page = getDictionary(locale).docs.pages.hotkeys;
  return <DocArticle title={page.title} blocks={page.blocks} />;
}
