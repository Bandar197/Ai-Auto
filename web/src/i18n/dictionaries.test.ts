import { describe, expect, it } from "vitest";
import ar from "./ar";
import en from "./en";
import { interpolate, switchLocalePath } from "./config";
import { KNOWN_ERROR_CODES } from "@/lib/errors";

type Tree = { [k: string]: string | Tree };

function flatten(tree: Tree, prefix = ""): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(tree)) {
    const path = prefix ? `${prefix}.${key}` : key;
    if (typeof value === "string") out[path] = value;
    else Object.assign(out, flatten(value, path));
  }
  return out;
}

const flatAr = flatten(ar as unknown as Tree);
const flatEn = flatten(en as unknown as Tree);
const placeholders = (s: string) => [...s.matchAll(/\{(\w[\w-]*)\}/g)].map((m) => m[1]).sort();

describe("i18n dictionaries", () => {
  it("ar and en have exactly the same keys", () => {
    const arKeys = Object.keys(flatAr).sort();
    const enKeys = Object.keys(flatEn).sort();
    expect(arKeys.filter((k) => !(k in flatEn))).toEqual([]);
    expect(enKeys.filter((k) => !(k in flatAr))).toEqual([]);
    expect(arKeys.length).toBeGreaterThan(100);
  });

  it("has no empty strings", () => {
    for (const [key, value] of [...Object.entries(flatAr), ...Object.entries(flatEn)]) {
      expect(value.trim(), key).not.toBe("");
    }
  });

  it("uses the same placeholders in both languages", () => {
    for (const key of Object.keys(flatAr)) {
      expect(placeholders(flatEn[key]), key).toEqual(placeholders(flatAr[key]));
    }
  });

  it("translates every known API error code", () => {
    for (const code of KNOWN_ERROR_CODES) {
      expect(flatAr[`apiErrors.${code}`], code).toBeTruthy();
      expect(flatEn[`apiErrors.${code}`], code).toBeTruthy();
    }
  });

  it("Arabic strings actually contain Arabic script", () => {
    expect(flatAr["nav.overview"]).toMatch(/[؀-ۿ]/);
    expect(flatAr["auth.signIn"]).toMatch(/[؀-ۿ]/);
  });
});

describe("i18n helpers", () => {
  it("interpolates placeholders", () => {
    expect(interpolate("{from}–{to} of {total}", { from: 1, to: 20, total: 45 })).toBe("1–20 of 45");
    expect(interpolate("{missing}", {})).toBe("{missing}");
  });

  it("switches the locale segment of a path", () => {
    expect(switchLocalePath("/ar/users", "en")).toBe("/en/users");
    expect(switchLocalePath("/en", "ar")).toBe("/ar");
    expect(switchLocalePath("/arabic", "en")).toBe("/en/arabic");
  });
});
