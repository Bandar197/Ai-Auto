import { useTwilight } from '@salla.sa/twilight-theme-engine/providers';
import { useTranslation } from '@salla.sa/twilight-theme-engine/i18n';
import { flag, linkHref, localized } from '../../lib/zkFields';

export const ANNOUNCEMENT_DEFAULT_TEXT = '✦ زخر | اختيارات تستاهل ✦';

/**
 * Thin navy strip above the header (theme settings: `announcement_enabled`,
 * `announcement_text`, `announcement_link`). Used for the brand line by
 * default, and for shipping / launch / offer messages when the merchant edits it.
 */
export function AnnouncementBar() {
  const { theme } = useTwilight();
  const { locale } = useTranslation();
  const settings = (theme?.settings ?? {}) as Record<string, unknown>;

  if (!flag(settings.announcement_enabled, true)) return null;

  const text = localized(settings.announcement_text, locale, ANNOUNCEMENT_DEFAULT_TEXT);
  const href = linkHref(settings.announcement_link);
  if (!text) return null;

  return (
    <div className="zk-announcement">
      <div className="zk-container zk-announcement__inner">
        {href ? (
          <a className="zk-announcement__text" href={href}>
            {text}
          </a>
        ) : (
          <p className="zk-announcement__text">{text}</p>
        )}
      </div>
    </div>
  );
}
