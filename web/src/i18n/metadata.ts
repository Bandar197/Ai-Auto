import type { Metadata } from "next";
import { dictionaries, isLocale } from "./config";

type NavKey = "overview" | "users" | "diagnostics" | "ecu" | "plans" | "errors" | "audit";

export async function navMetadata(params: Promise<{ locale: string }>, key: NavKey | "login"): Promise<Metadata> {
  const { locale } = await params;
  const dict = dictionaries[isLocale(locale) ? locale : "ar"];
  return { title: key === "login" ? dict.auth.title : dict.nav[key] };
}
