import { NextResponse, type NextRequest } from "next/server";
import { defaultLocale, locales } from "@/lib/site";

/**
 * Next.js 16 proxy (formerly middleware): redirect locale-less paths to the
 * best-matching locale based on the Accept-Language header.
 */
function pickLocale(request: NextRequest): string {
  const header = request.headers.get("accept-language") ?? "";
  const wanted = header
    .split(",")
    .map((part) => part.split(";")[0].trim().slice(0, 2).toLowerCase());
  for (const candidate of wanted) {
    if ((locales as readonly string[]).includes(candidate)) return candidate;
  }
  return defaultLocale;
}

export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  const hasLocale = locales.some(
    (locale) => pathname === `/${locale}` || pathname.startsWith(`/${locale}/`),
  );
  if (hasLocale) return;

  const locale = pickLocale(request);
  request.nextUrl.pathname = `/${locale}${pathname === "/" ? "" : pathname}`;
  return NextResponse.redirect(request.nextUrl);
}

export const config = {
  matcher: ["/((?!_next|icon|.*\\..*).*)"],
};
