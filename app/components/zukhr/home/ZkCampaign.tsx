import { useId } from 'react';
import { useTranslation } from '@salla.sa/twilight-theme-engine/i18n';
import { Link } from '@salla.sa/twilight-theme-engine/common';
import { linkHref, localized, scalar } from '../../../lib/zkFields';
import { useEditorPreview } from '../../../hooks/useEditorPreview';

export interface ZkCampaignData {
  theme?: unknown;
  eyebrow?: unknown;
  title?: unknown;
  text?: unknown;
  cta_text?: unknown;
  cta_url?: unknown;
  image?: unknown;
  image_mobile?: unknown;
  [key: string]: unknown;
}

/**
 * `zk-campaign` home block — one featured brand or product campaign: a
 * campaign image beside a short message and CTA. Navy by default (one of
 * the few dark bands that break the page rhythm). Hidden on the live store
 * until it has a title or an image.
 */
export function ZkCampaign({ data }: { data: ZkCampaignData }) {
  const { t, locale } = useTranslation();
  const isEditor = useEditorPreview();
  const headingId = useId();
  const isLight = scalar(data.theme) === 'light';

  const eyebrow = localized(data.eyebrow, locale);
  const title = localized(data.title, locale);
  const text = localized(data.text, locale);
  const ctaText = localized(data.cta_text, locale);
  const ctaHref = linkHref(data.cta_url);
  const image = typeof data.image === 'string' ? data.image : '';
  const imageMobile = typeof data.image_mobile === 'string' && data.image_mobile ? data.image_mobile : image;

  if (!title && !image && !isEditor) return null;

  return (
    <section
      className={`zk-section zk-campaign ${isLight ? 'zk-section--frost' : 'zk-section--dark'}`}
      aria-labelledby={title ? headingId : undefined}
    >
      <div className="zk-container zk-campaign__inner">
        <div className="zk-campaign__copy">
          {eyebrow && <span className="zk-eyebrow">{eyebrow}</span>}
          {title && (
            <h2 className="zk-title" id={headingId}>
              {title}
            </h2>
          )}
          {text && <p className="zk-lead mt-3">{text}</p>}
          {ctaText && ctaHref && (
            <Link to={ctaHref} className={`zk-btn ${isLight ? 'zk-btn--primary' : 'zk-btn--light'} mt-6`}>
              {ctaText}
            </Link>
          )}
          {!title && isEditor && (
            <p className="zk-editor-hint mt-4">{t('zukhr.editor.campaign', 'Add the campaign title, image and link in the theme editor.')}</p>
          )}
        </div>
        <div className="zk-campaign__media">
          {image ? (
            <picture>
              <source media="(max-width: 767px)" srcSet={imageMobile} />
              <img src={image} alt={title} width={1600} height={1200} loading="lazy" decoding="async" />
            </picture>
          ) : (
            <div className="zk-campaign__media-empty" aria-hidden="true" />
          )}
        </div>
      </div>
    </section>
  );
}
