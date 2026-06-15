import Link from "next/link";
import { Wordmark } from "@/components/wordmark";

export default function NotFound() {
  return (
    <section className="mx-auto flex max-w-xl flex-col items-center px-5 py-32 text-center">
      <Wordmark className="text-3xl" />
      <h1 className="mt-8 text-5xl font-bold tracking-tight">404</h1>
      <p className="mt-3 text-lg text-cloud/55">
        diese seite gibt es nicht. / this page doesn’t exist.
      </p>
      <Link
        href="/"
        className="mt-8 rounded-full bg-lime px-6 py-3 font-semibold text-ink transition-transform hover:scale-[1.03]"
      >
        → home
      </Link>
    </section>
  );
}
