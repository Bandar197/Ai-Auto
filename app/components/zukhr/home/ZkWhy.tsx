import { useId } from 'react';
import type { ReactNode } from 'react';
import { useTranslation } from '@salla.sa/twilight-theme-engine/i18n';
import { localized, scalar } from '../../../lib/zkFields';

const GLYPHS: Record<string, ReactNode> = {
  select: <path d="M12 3l2.6 5.4 5.9.8-4.3 4.1 1 5.8L12 16.4 6.8 19.1l1-5.8L3.5 9.2l5.9-.8L12 3Z" />,
  quality: <path d="M12 3l7 3v5c0 4.5-3 8.3-7 10-4-1.7-7-5.5-7-10V6l7-3ZM9 12l2 2 4-4" />,
  value: <path d="M12 3v18M16.5 7.5C16 6 14.3 5 12 5 9.2 5 7.5 6.4 7.5 8.3 7.5 12.8 16.5 10.7 16.5 15.4c0 2-1.9 3.6-4.5 3.6-2.5 0-4.2-1.1-4.6-2.7" />,
  secure: <path d="M6 11h12v10H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3M12 15v2" />,
  shipping: <path d="M3 6h11v10H3zM14 9h4l3 3v4h-7M7.5 19a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3ZM17.5 19a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z" />,
  support: <path d="M4 13v-1a8 8 0 0 1 16 0v1M4 13h3v6H5a1 1 0 0 1-1-1v-5ZM20 13h-3v6h2a1 1 0 0 0 1-1v-5ZM17 19c0 1.1-2.2 2-5 2" />,
};

interface ZkWhyItem {
  'items.icon'?: unknown;
  'items.title'?: unknown;
  'items.text'?: unknown;
  icon?: unknown;
  title?: unknown;
  text?: unknown;
}

export interface ZkWhyData {
  title?: unknown;
  subtitle?: unknown;
  items?: ZkWhyItem[];
  [key: string]: unknown;
}

const field = (item: ZkWhyItem, key: 'icon' | 'title' | 'text') => item[`items.${key}`] ?? item[key];

/** `zk-why` home block — "ليش زخر؟": the brand's promise in 3–4 short points. */
export function ZkWhy({ data }: { data: ZkWhyData }) {
  const { t, locale } = useTranslation();
  const headingId = useId();
  const items = (Array.isArray(data.items) ? data.items : [])
    .slice(0, 4)
    .map((item) => ({
      icon: scalar(field(item, 'icon')),
      title: localized(field(item, 'title'), locale),
      text: localized(field(item, 'text'), locale),
    }))
    .filter((item) => item.title);
  if (!items.length) return null;

  const title = localized(data.title, locale, t('zukhr.home.why', 'Why ZUKHR'));
  const subtitle = localized(data.subtitle, locale);

  return (
    <section className="zk-section zk-why" aria-labelledby={headingId}>
      <div className="zk-container">
        <div className="zk-section__head zk-why__head">
          <div>
            <h2 className="zk-title" id={headingId}>
              {title}
            </h2>
            {subtitle && <p className="zk-lead mt-2">{subtitle}</p>}
          </div>
        </div>
        <ul className="zk-why__grid">
          {items.map((item, index) => (
            <li key={`${item.title}-${index}`} className="zk-why__item">
              <span className="zk-why__icon">
                <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  {GLYPHS[item.icon] ?? GLYPHS.select}
                </svg>
              </span>
              <h3 className="zk-why__title">{item.title}</h3>
              {item.text && <p className="zk-why__text">{item.text}</p>}
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
