import { Link } from '@salla.sa/twilight-theme-engine/common';

interface ZkSectionHeadProps {
  eyebrow?: string;
  title?: string;
  subtitle?: string;
  moreHref?: string;
  moreLabel?: string;
  /** Heading id, for `aria-labelledby` on the section. */
  id?: string;
}

/** Shared heading row for ZUKHR home sections: eyebrow, title, lead, "view all". */
export function ZkSectionHead({ eyebrow, title, subtitle, moreHref, moreLabel, id }: ZkSectionHeadProps) {
  if (!title && !eyebrow && !moreHref) return null;
  return (
    <div className="zk-section__head">
      <div>
        {eyebrow && <span className="zk-eyebrow">{eyebrow}</span>}
        {title && (
          <h2 className="zk-title" id={id}>
            {title}
          </h2>
        )}
        {subtitle && <p className="zk-lead mt-2">{subtitle}</p>}
      </div>
      {moreHref && moreLabel && (
        <Link to={moreHref} className="zk-link-more">
          {moreLabel}
        </Link>
      )}
    </div>
  );
}
