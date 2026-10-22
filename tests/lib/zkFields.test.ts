import { describe, it, expect } from 'vitest';
import { flag, linkHref, localized, scalar, toIds } from '../../app/lib/zkFields';

describe('zkFields', () => {
  it('reads a dropdown value in any of its shapes', () => {
    expect(scalar('sales')).toBe('sales');
    expect(scalar({ value: 'sales' })).toBe('sales');
    expect(scalar([{ key: 'sales' }])).toBe('sales');
    expect(scalar(null)).toBe('');
  });

  it('reads picker ids, dropping anything that is not a positive id', () => {
    expect(toIds([{ id: 12 }, '34', { value: 'x' }, -1])).toEqual([12, 34]);
    expect(toIds({ source_value: [5, 6] })).toEqual([5, 6]);
    expect(toIds('')).toEqual([]);
    expect(toIds(undefined)).toEqual([]);
  });

  it('reads a translatable text for the locale, with a fallback', () => {
    expect(localized('  زخر ', 'ar')).toBe('زخر');
    expect(localized({ ar: 'زخر', en: 'ZUKHR' }, 'en')).toBe('ZUKHR');
    expect(localized({ ar: 'زخر' }, 'en')).toBe('زخر');
    expect(localized('', 'ar', 'fallback')).toBe('fallback');
    expect(localized(null, 'ar', 'fallback')).toBe('fallback');
  });

  it('reads a link as an href, treating empty and "#" as unset', () => {
    expect(linkHref('https://zukhr.sa/x')).toBe('https://zukhr.sa/x');
    expect(linkHref({ url: '/offers' })).toBe('/offers');
    expect(linkHref('#')).toBeUndefined();
    expect(linkHref('')).toBeUndefined();
    expect(linkHref(null)).toBeUndefined();
  });

  it('reads a switch, with a fallback for unsaved settings', () => {
    expect(flag(false, true)).toBe(false);
    expect(flag('true', false)).toBe(true);
    expect(flag(undefined, true)).toBe(true);
  });
});
