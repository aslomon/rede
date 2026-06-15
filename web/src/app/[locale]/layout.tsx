import type { Metadata } from "next";
import { notFound } from "next/navigation";
import "../globals.css";
import { isLocale, locales, site } from "@/lib/site";
import { getDictionary } from "@/i18n/dictionaries";
import { SiteHeader } from "@/components/site-header";
import { SiteFooter } from "@/components/site-footer";

// Only de/en are valid; anything else 404s with a proper boundary.
export const dynamicParams = false;

export function generateStaticParams() {
  return locales.map((locale) => ({ locale }));
}

export async function generateMetadata(
  props: PageProps<"/[locale]">,
): Promise<Metadata> {
  const { locale } = await props.params;
  if (!isLocale(locale)) return {};
  const dict = getDictionary(locale);
  return {
    metadataBase: new URL(site.url),
    title: dict.meta.title,
    description: dict.meta.description,
    icons: { icon: "/icon.png" },
    openGraph: {
      title: dict.meta.title,
      description: dict.meta.description,
      type: "website",
      images: ["/icon-1024.png"],
    },
    alternates: {
      languages: { de: "/de", en: "/en" },
    },
  };
}

export default async function LocaleLayout(props: LayoutProps<"/[locale]">) {
  const { locale } = await props.params;
  if (!isLocale(locale)) notFound();
  const dict = getDictionary(locale);

  return (
    <html lang={locale}>
      <body className="relative min-h-screen antialiased">
        <div className="relative z-10 flex min-h-screen flex-col">
          <SiteHeader locale={locale} dict={dict} />
          <main className="flex-1">{props.children}</main>
          <SiteFooter locale={locale} dict={dict} />
        </div>
      </body>
    </html>
  );
}
