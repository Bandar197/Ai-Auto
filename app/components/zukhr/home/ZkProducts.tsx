import { useId } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from '@salla.sa/twilight-theme-engine/i18n';
import { product, type ProductsListSource } from '@salla.sa/twilight-theme-engine/api/product';
import { ScrollCarousel } from '../../common';
import { ProductCard } from '../../product';
import { blockLimit } from '../../../lib/blockLimit';
import { linkHref, localized, scalar, toIds } from '../../../lib/zkFields';
import { useEditorPreview } from '../../../hooks/useEditorPreview';
import { ZkSectionHead } from './ZkSectionHead';

/** Sources a merchant can pick for a ZUKHR product section. */
const SOURCES = ['selected', 'sales', 'offers', 'latest', 'top-rated', 'categories'] as const;
type ZkSource = (typeof SOURCES)[number];

/** Where "view all" goes when the merchant leaves the link empty. */
const DEFAULT_MORE: Partial<Record<ZkSource, string>> = {
  sales: '/products?source=sales',
  offers: '/products?source=offers',
  latest: '/products',
};

export interface ZkProductsData {
  eyebrow?: unknown;
  title?: unknown;
  subtitle?: unknown;
  source?: unknown;
  products?: unknown;
  category?: unknown;
  limit?: unknown;
  surface?: unknown;
  display_all_url?: unknown;
  [key: string]: unknown;
}

const DEFAULT_LIMIT = 8;

/**
 * `zk-products` home block — one product rail used for ZUKHR Picks, Best
 * Sellers, Offers and Gifts. Products always come from the store: a merchant
 * pick (`selected`), Salla's most-sold list (`sales`), current offers,
 * latest, top rated, or a category. Nothing is invented: a section with no
 * products renders nothing on the live store, and an editor hint in preview.
 *
 * Stage 1 renders the theme's current ProductCard; the ZUKHR card lands in
 * Stage 5.
 */
export function ZkProducts({ data }: { data: ZkProductsData }) {
  const { t, locale } = useTranslation();
  const isEditor = useEditorPreview();
  const headingId = useId();

  const pickedSource = scalar(data.source) as ZkSource;
  const source: ZkSource = (SOURCES as readonly string[]).includes(pickedSource) ? pickedSource : 'selected';
  const ids = source === 'selected' ? toIds(data.products) : source === 'categories' ? toIds(data.category) : [];
  const needsIds = source === 'selected' || source === 'categories';
  const ready = !needsIds || ids.length > 0;
  const limit = blockLimit(data.limit) ?? DEFAULT_LIMIT;

  const { data: result, isSuccess, isError } = useQuery({
    ...product.queries.list({
      source: source as ProductsListSource,
      sourceValue: needsIds ? ids : undefined,
      perPage: limit,
    }),
    enabled: ready,
  });
  const items = result?.items?.slice(0, limit) ?? [];

  const title = localized(data.title, locale);
  const eyebrow = localized(data.eyebrow, locale);
  const subtitle = localized(data.subtitle, locale);
  const moreHref = linkHref(data.display_all_url) ?? DEFAULT_MORE[source];
  const surface = scalar(data.surface) === 'frost' ? ' zk-section--frost' : '';

  const empty = !ready || isError || (isSuccess && items.length === 0);
  if (empty && !isEditor) return null;

  return (
    <section className={`zk-section zk-products${surface}`} aria-labelledby={title ? headingId : undefined}>
      <div className="zk-container">
        <ZkSectionHead
          id={headingId}
          eyebrow={eyebrow}
          title={title}
          subtitle={subtitle}
          moreHref={empty ? undefined : moreHref}
          moreLabel={t('blocks.home.display_all', 'View all')}
        />

        {empty ? (
          <p className="zk-editor-hint">
            {needsIds && !ready
              ? t('zukhr.editor.pick_products', 'Pick the products for this section in the theme editor.')
              : t('zukhr.editor.no_products', 'No products from this source in the store yet.')}
          </p>
        ) : !isSuccess ? (
          <div className="zk-rail zk-rail--skeleton" aria-hidden="true">
            {Array.from({ length: 4 }, (_, i) => (
              <div key={i} className="zk-rail__slide">
                <div className="zk-skeleton aspect-square" />
                <div className="zk-skeleton mt-4 h-4 w-3/4" />
                <div className="zk-skeleton mt-2 h-4 w-1/3" />
              </div>
            ))}
          </div>
        ) : (
          <ScrollCarousel
            className="zk-rail"
            prevLabel={t('blocks.home.reviews_prev', 'Previous')}
            nextLabel={t('blocks.home.reviews_next', 'Next')}
          >
            {items.map((item) => (
              <div key={item.id} className="zk-rail__slide">
                <ProductCard product={item} />
              </div>
            ))}
          </ScrollCarousel>
        )}
      </div>
    </section>
  );
}
