import { useQuery } from '@tanstack/react-query';
import { useTranslation } from '@salla.sa/twilight-theme-engine/i18n';
import { useTwilight } from '@salla.sa/twilight-theme-engine/providers';
import { product } from '@salla.sa/twilight-theme-engine/api/product';
import { Image, Link } from '@salla.sa/twilight-theme-engine/common';
import { linkHref, localized, scalar, toIds } from '../../../lib/zkFields';
import { useEditorPreview } from '../../../hooks/useEditorPreview';

export const HERO_DEFAULTS = {
  tagline: 'اختيارات تستاهل',
  title: 'منتجات مختارة بعناية للشيء اللي فعلا يستاهل',
  cta: 'تسوق الآن',
};

/** At most this many products on the hero stage (brief: 4–5). */
const MAX_STAGE_PRODUCTS = 5;

export interface ZkHeroData {
  theme?: unknown;
  logo?: unknown;
  tagline?: unknown;
  title?: unknown;
  cta_text?: unknown;
  cta_url?: unknown;
  image_desktop?: unknown;
  image_mobile?: unknown;
  products?: unknown;
  /** Set by the engine's home renderer for the first blocks on the page. */
  priority?: boolean;
  [key: string]: unknown;
}

/**
 * `zk-hero` home block. Brand side (start edge — the right in Arabic): logo,
 * tagline, headline, CTA. Stage side: up to five products the merchant picks
 * from the real catalog, shown with their real store images.
 *
 * Dark (navy) by default; `theme: light` gives a Frost version. The logo field
 * takes the master logo file as-is (a light version for the dark hero); when
 * it is empty the light hero falls back to the store logo.
 *
 * Stage 1 skeleton: layout, copy and product sourcing. The stage composition
 * (platforms, lighting) is Stage 4.
 */
export function ZkHero({ data }: { data: ZkHeroData }) {
  const priority = data.priority === true;
  const { locale, t } = useTranslation();
  const { store } = useTwilight();
  const isEditor = useEditorPreview();
  const isLight = scalar(data.theme) === 'light';

  const tagline = localized(data.tagline, locale, HERO_DEFAULTS.tagline);
  const title = localized(data.title, locale, HERO_DEFAULTS.title);
  const ctaText = localized(data.cta_text, locale, HERO_DEFAULTS.cta);
  const ctaHref = linkHref(data.cta_url) ?? '/products';
  const uploadedLogo = typeof data.logo === 'string' && data.logo ? data.logo : undefined;
  const logo = uploadedLogo ?? (isLight ? store?.logo : undefined);
  const bgDesktop = typeof data.image_desktop === 'string' ? data.image_desktop : '';
  const bgMobile = typeof data.image_mobile === 'string' && data.image_mobile ? data.image_mobile : bgDesktop;

  const ids = toIds(data.products).slice(0, MAX_STAGE_PRODUCTS);
  const { data: result, isSuccess } = useQuery({
    ...product.queries.list({ source: 'selected', sourceValue: ids, perPage: ids.length || 1 }),
    enabled: ids.length > 0,
  });
  const stage = (result?.items ?? []).slice(0, MAX_STAGE_PRODUCTS);

  return (
    <section className={`zk-hero ${isLight ? 'zk-hero--light' : 'zk-hero--dark'}`}>
      {bgDesktop && (
        <picture className="zk-hero__bg" aria-hidden="true">
          <source media="(max-width: 767px)" srcSet={bgMobile} />
          <img src={bgDesktop} alt="" width={2400} height={1200} fetchPriority={priority ? 'high' : 'auto'} decoding="async" />
        </picture>
      )}

      <div className="zk-container zk-hero__inner">
        <div className="zk-hero__brand">
          {logo ? (
            <Image className="zk-hero__logo" src={logo} alt={store?.name || 'ZUKHR'} priority={priority} width={220} height={96} />
          ) : (
            isEditor && <p className="zk-editor-hint zk-hero__logo-hint">{t('zukhr.editor.hero_logo', 'Upload the light master logo in the hero settings.')}</p>
          )}
          <p className="zk-hero__tagline">{tagline}</p>
          <h1 className="zk-hero__title">{title}</h1>
          <Link to={ctaHref} className={`zk-btn ${isLight ? 'zk-btn--primary' : 'zk-btn--light'} zk-hero__cta`}>
            {ctaText}
          </Link>
        </div>

        <div className="zk-hero__stage">
          {stage.length > 0 ? (
            <ul className={`zk-hero__products zk-hero__products--${stage.length}`}>
              {stage.map((item, index) => (
                <li key={item.id} className="zk-hero__product">
                  <Link to={item.url} className="zk-hero__product-link" aria-label={item.name}>
                    <Image
                      src={item.image?.url}
                      alt={item.image?.alt || item.name}
                      width={320}
                      height={320}
                      priority={priority && index < 2}
                    />
                  </Link>
                </li>
              ))}
            </ul>
          ) : ids.length > 0 && !isSuccess ? (
            <div className="zk-hero__stage-skeleton zk-skeleton" aria-hidden="true" />
          ) : (
            isEditor && <p className="zk-editor-hint">{t('zukhr.editor.hero_products', 'Pick 4–5 in-stock products for the hero.')}</p>
          )}
        </div>
      </div>
    </section>
  );
}
