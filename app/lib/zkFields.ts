/**
 * Readers for the values the theme editor sends for ZUKHR settings and home
 * blocks. The backend is loose about shapes (a dropdown can arrive as a
 * scalar, `{ value }`, or an array of either; a translatable text as a string
 * or `{ ar, en }`), so every block reads its fields through these.
 */

/** A dropdown / picker value as its plain string: `'x'`, `{ value: 'x' }`, `['x']` → `'x'`. */
export function scalar(value: unknown): string {
  if (Array.isArray(value)) return scalar(value[0]);
  if (value && typeof value === 'object') {
    const o = value as { value?: unknown; key?: unknown; id?: unknown };
    return scalar(o.value ?? o.key ?? o.id);
  }
  return value === null || value === undefined ? '' : String(value);
}

/** Positive numeric ids from a product / category picker, in the merchant's order. */
export function toIds(value: unknown): number[] {
  if (value && typeof value === 'object' && !Array.isArray(value) && 'source_value' in value) {
    return toIds((value as { source_value?: unknown }).source_value);
  }
  const list = Array.isArray(value) ? value : value === null || value === undefined || value === '' ? [] : [value];
  return list
    .map((item) => Number(scalar(item)))
    .filter((id) => Number.isInteger(id) && id > 0);
}

/** A translatable text field for the current locale; `fallback` when empty. */
export function localized(value: unknown, locale: string, fallback = ''): string {
  if (typeof value === 'string') return value.trim() || fallback;
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    const map = value as Record<string, unknown>;
    const hit = map[locale] ?? map.ar ?? map.en;
    return typeof hit === 'string' && hit.trim() ? hit.trim() : fallback;
  }
  return fallback;
}

/**
 * A link field (`variable-list`) as an href, or `undefined` when unset.
 * Arrives as a URL string or an object carrying `url` / `value`.
 */
export function linkHref(value: unknown): string | undefined {
  const raw =
    typeof value === 'string'
      ? value
      : Array.isArray(value)
        ? linkHref(value[0])
        : value && typeof value === 'object'
          ? ((value as { url?: unknown; value?: unknown }).url ?? (value as { value?: unknown }).value)
          : undefined;
  if (typeof raw !== 'string') return undefined;
  const href = raw.trim();
  return href && href !== '#' ? href : undefined;
}

/** A boolean switch; `fallback` when the setting was never saved. */
export function flag(value: unknown, fallback: boolean): boolean {
  if (typeof value === 'boolean') return value;
  if (value === 'true' || value === 1 || value === '1') return true;
  if (value === 'false' || value === 0 || value === '0') return false;
  return fallback;
}
