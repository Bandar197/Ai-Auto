import { useId } from 'react';
import type { ReactNode } from 'react';
import { useTranslation } from '@salla.sa/twilight-theme-engine/i18n';
import { Image, Link } from '@salla.sa/twilight-theme-engine/common';
import { linkHref, localized, scalar } from '../../../lib/zkFields';
import { useEditorPreview } from '../../../hooks/useEditorPreview';
import { ZkSectionHead } from './ZkSectionHead';

/** Simple line glyphs for the default categories (24px, 1.5 stroke, like icons.tsx). */
const GLYPHS: Record<string, ReactNode> = {
  charger: <path d="M9 2v4M15 2v4M6 6h12v4a6 6 0 0 1-12 0V6ZM12 16v6" />,
  cable: <path d="M7 3v5M11 3v5M5 8h8v3a4 4 0 0 1-8 0V8ZM9 15v2a4 4 0 0 0 4 4h2a4 4 0 0 0 4-4V5" />,
  audio: <path d="M4 15v-3a8 8 0 0 1 16 0v3M4 15a2 2 0 0 1 2-2h1v7H6a2 2 0 0 1-2-2v-3ZM20 15a2 2 0 0 0-2-2h-1v7h1a2 2 0 0 0 2-2v-3Z" />,
  care: <path d="M12 3c3 4 6 7 6 11a6 6 0 0 1-12 0c0-4 3-7 6-11ZM9.5 14.5a2.5 2.5 0 0 0 2.5 2.5" />,
  gift: <path d="M4 11h16v10H4zM3 7h18v4H3zM12 7v14M12 7S10.5 3 8 3a2 2 0 0 0 0 4h4ZM12 7s1.5-4 4-4a2 2 0 0 1 0 4h-4Z" />,
  offers: <path d="M3 12V4h8l10 10-8 8L3 12ZM7.5 7.5h.01" />,
  grid: <path d="M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z" />,
};

function CategoryGlyph({ name }: { name: string }) {
  return (
    <svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {GLYPHS[name] ?? GLYPHS.grid}
    </svg>
  );
}

interface ZkCategoryItem {
  'items.title'?: unknown;
  'items.icon'?: unknown;
  'items.image'?: unknown;
  'items.url'?: unknown;
  title?: unknown;
  icon?: unknown;
  image?: unknown;
  url?: unknown;
}

export interface ZkCategoriesData {
  title?: unknown;
  items?: ZkCategoryItem[];
  [key: string]: unknown;
}

/** Collection rows arrive with `items.`-prefixed keys or plain ones; read either. */
const field = (item: ZkCategoryItem, key: 'title' | 'icon' | 'image' | 'url') =>
  item[`items.${key}`] ?? item[key];

/**
 * `zk-categories` home block — "تسوق حسب الفئة": 4–6 main categories, each a
 * tile with a simple icon (or a merchant image) linking to a real category.
 * A tile without a link is hidden on the live store.
 */
export function ZkCategories({ data }: { data: ZkCategoriesData }) {
  const { t, locale } = useTranslation();
  const isEditor = useEditorPreview();
  const headingId = useId();

  const tiles = (Array.isArray(data.items) ? data.items : [])
    .slice(0, 6)
    .map((item) => ({
      title: localized(field(item, 'title'), locale),
      icon: scalar(field(item, 'icon')),
      image: typeof field(item, 'image') === 'string' ? (field(item, 'image') as string) : '',
      href: linkHref(field(item, 'url')),
    }))
    .filter((tile) => tile.title && (tile.href || isEditor));

  if (!tiles.length) return null;
  const title = localized(data.title, locale, t('zukhr.home.shop_by_category', 'Shop by category'));

  return (
    <section className="zk-section zk-categories" aria-labelledby={headingId}>
      <div className="zk-container">
        <ZkSectionHead id={headingId} title={title} />
        <ul className="zk-categories__grid">
          {tiles.map((tile, index) => {
            const body = (
              <>
                <span className="zk-categories__media">
                  {tile.image ? (
                    <Image src={tile.image} alt="" width={96} height={96} />
                  ) : (
                    <CategoryGlyph name={tile.icon} />
                  )}
                </span>
                <span className="zk-categories__label">{tile.title}</span>
              </>
            );
            return (
              <li key={`${tile.title}-${index}`}>
                {tile.href ? (
                  <Link to={tile.href} className="zk-categories__tile">
                    {body}
                  </Link>
                ) : (
                  <div className="zk-categories__tile is-unlinked" title={t('zukhr.editor.link_category', 'Link this tile to a category in the theme editor.')}>
                    {body}
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      </div>
    </section>
  );
}
