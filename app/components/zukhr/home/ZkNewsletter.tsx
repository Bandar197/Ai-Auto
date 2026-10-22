import { useId } from 'react';
import { SallaSocial } from '@salla.sa/twilight-components-react/social';
import { useTranslation } from '@salla.sa/twilight-theme-engine/i18n';
import { localized } from '../../../lib/zkFields';

export interface ZkNewsletterData {
  title?: unknown;
  text?: unknown;
  [key: string]: unknown;
}

/**
 * `zk-newsletter` home block — "stay close" band before the footer.
 *
 * Salla's storefront SDK has no newsletter sign-up endpoint, so this block
 * does not fake an email form: it points visitors to the store's real social
 * accounts (`<salla-social>`, from the store settings). An email form can be
 * added once a newsletter app is installed on the store.
 */
export function ZkNewsletter({ data }: { data: ZkNewsletterData }) {
  const { t, locale } = useTranslation();
  const headingId = useId();
  const title = localized(data.title, locale, t('zukhr.home.newsletter_title', 'Stay close to ZUKHR picks'));
  const text = localized(
    data.text,
    locale,
    t('zukhr.home.newsletter_text', 'Follow us to hear first about new picks and selected offers.')
  );

  return (
    <section className="zk-section zk-newsletter" aria-labelledby={headingId}>
      <div className="zk-container">
        <div className="zk-newsletter__card">
          <div>
            <h2 className="zk-title" id={headingId}>
              {title}
            </h2>
            <p className="zk-lead mt-2">{text}</p>
          </div>
          <SallaSocial className="zk-newsletter__social" />
        </div>
      </div>
    </section>
  );
}
