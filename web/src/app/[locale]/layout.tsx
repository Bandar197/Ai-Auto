import type { Metadata, Viewport } from "next";
import { IBM_Plex_Sans_Arabic } from "next/font/google";
import { notFound } from "next/navigation";
import { AuthProvider } from "@/components/auth/AuthProvider";
import { I18nProvider } from "@/i18n/I18nProvider";
import { dictionaries, dirOf, isLocale, locales } from "@/i18n/config";
import "../globals.css";

// Downloaded at build time and served from this origin — no runtime CDN calls.
const plexArabic = IBM_Plex_Sans_Arabic({
  weight: ["400", "500", "600", "700"],
  subsets: ["arabic", "latin"],
  display: "swap",
  variable: "--font-plex-arabic",
});

export function generateStaticParams() {
  return locales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: LayoutProps<"/[locale]">): Promise<Metadata> {
  const { locale } = await params;
  const dict = dictionaries[isLocale(locale) ? locale : "ar"];
  return {
    title: { default: dict.meta.title, template: `%s · ${dict.nav.brand}` },
    description: dict.meta.description,
    robots: { index: false, follow: false },
  };
}

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  colorScheme: "light dark",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f6f7f9" },
    { media: "(prefers-color-scheme: dark)", color: "#111214" },
  ],
};

export default async function LocaleLayout({ children, params }: LayoutProps<"/[locale]">) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();

  return (
    <html lang={locale} dir={dirOf(locale)} className={`${plexArabic.variable} h-full`}>
      <body className="min-h-full bg-bg text-fg antialiased">
        <I18nProvider locale={locale}>
          <AuthProvider>{children}</AuthProvider>
        </I18nProvider>
      </body>
    </html>
  );
}
