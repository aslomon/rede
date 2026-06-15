import { notFound } from "next/navigation";
import { isLocale } from "@/lib/site";
import { getDictionary } from "@/i18n/dictionaries";
import { Hero } from "@/components/hero";
import { Modes } from "@/components/modes";
import { HowItWorks } from "@/components/how-it-works";
import { Privacy } from "@/components/privacy";
import { Screenshots } from "@/components/screenshots";
import { DownloadCTA } from "@/components/download-cta";

export default async function HomePage(props: PageProps<"/[locale]">) {
  const { locale } = await props.params;
  if (!isLocale(locale)) notFound();
  const dict = getDictionary(locale);

  return (
    <>
      <Hero locale={locale} dict={dict} />
      <Modes dict={dict} />
      <HowItWorks dict={dict} />
      <Privacy dict={dict} />
      <Screenshots dict={dict} />
      <DownloadCTA dict={dict} />
    </>
  );
}
