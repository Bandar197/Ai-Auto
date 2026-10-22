import { useEffect, useRef, useState } from 'react';
import { useRouterState } from '@tanstack/react-router';
import { SallaSearch } from '@salla.sa/twilight-components-react/search';
import { SallaUserMenu } from '@salla.sa/twilight-components-react/user-menu';
import { SallaCartSummary } from '@salla.sa/twilight-components-react/cart-summary';
import { useTwilight } from '@salla.sa/twilight-theme-engine/providers';
import { useTranslation } from '@salla.sa/twilight-theme-engine/i18n';
import { HookSlot } from '@salla.sa/twilight-theme-engine/hooks';
import { Image, Link } from '@salla.sa/twilight-theme-engine/common';
import { PageAdvertisements } from '@salla.sa/twilight-theme-engine/layout';
import { HeartIcon, MapPinIcon, SearchIcon, ShoppingBagIcon } from '../icons';
import { useAppSafeAreaTop } from '../../hooks/useAppSafeAreaTop';
import { useScrollDirection } from '../../hooks/useScrollDirection';
import { HOME_ROUTE_ID, PRODUCT_ROUTE_ID } from '../../lib/routeIds';
import { flag } from '../../lib/zkFields';
import { HeaderMainMenu } from './HeaderMainMenu';
import { HeaderNav } from './HeaderNav';
import { HeaderTopnav } from './HeaderTopnav';

/** Opens the Salla search modal (the `<SallaSearch />` at the end of the header). */
const openSearch = () => window.salla?.event?.dispatch('search::open');

const openScopes = () => window.salla?.event?.dispatch('scopes::open');

/** How far down the page the bar may hide while scrolling down (smart sticky). */
const HIDE_AFTER_PX = 320;

/**
 * Search trigger. On desktop it reads as a search field (icon + hint text);
 * on phones the text is hidden and it is an icon button. It opens the Salla
 * search modal through the `search::open` event.
 */
function SearchButton({ label, hint }: { label: string; hint: string }) {
  return (
    <button
      type="button"
      className="header-action site-header__search"
      aria-label={label}
      onClick={openSearch}
    >
      <SearchIcon aria-hidden="true" />
      <span className="site-header__search-hint" aria-hidden="true">
        {hint}
      </span>
    </button>
  );
}

/** Branch / scope trigger — opens `<SallaScopes>` (mounted in `ThemeLayout`). */
function ScopeButton({ label }: { label: string }) {
  return (
    <button
      type="button"
      data-testid="store-header-scope-btn"
      className="header-action site-header__scope"
      aria-label={label}
      aria-haspopup="dialog"
      title={label}
      onClick={openScopes}
    >
      <MapPinIcon aria-hidden="true" />
    </button>
  );
}

interface HeaderProps {
  navOpen?: boolean;
  onNavOpenChange?: (open: boolean) => void;
}

/**
 * ZUKHR header — swapped in via `<TwilightProvider layout={ThemeLayout}>`.
 *
 * Desktop: logo · category menu (store menu, mega-menu aware) · search field ·
 * account · wishlist · cart, on one compact row.
 * Phones/tablets: menu button · logo · search · cart; the bottom bar
 * (`MobileBottomBar`) carries the rest. On phones the bar shows on the home
 * page only, as in Raed; other pages use `MobilePageTitleBar`.
 *
 * Sticky is "smart": the bar pins once it reaches the top, hides while the
 * visitor scrolls down past {@link HIDE_AFTER_PX}, and comes back on any scroll
 * up. `header_is_sticky: false` turns pinning off. The optional top bar
 * (language / currency / branches) is `header_show_topnav`.
 *
 * The menu drawer state can be lifted (`navOpen` + `onNavOpenChange`) so the
 * bottom bar's Categories tab drives the same drawer. The `header:start` /
 * `header:end` hook slots are kept for installed apps.
 */
export function Header({ navOpen: navOpenProp, onNavOpenChange }: HeaderProps = {}) {
  const { store, theme } = useTwilight();
  const { t } = useTranslation();
  const settings = (theme?.settings ?? {}) as Record<string, unknown>;
  const stickyEnabled = flag(settings.header_is_sticky, true);
  const showTopnav = flag(settings.header_show_topnav, false);
  const showWishlist = flag(settings.header_show_wishlist, true);
  const [navOpenState, setNavOpenState] = useState(false);
  const navOpen = navOpenProp ?? navOpenState;
  const setNavOpen = (open: boolean) => {
    if (navOpenProp === undefined) setNavOpenState(open);
    onNavOpenChange?.(open);
  };
  const [scrolled, setScrolled] = useState(false);
  const [pastHideLine, setPastHideLine] = useState(false);
  const direction = useScrollDirection();
  // Route match rather than the body class, so the modifiers are in the SSR
  // markup and correct from the first tick of a client navigation.
  const isProductPage = useRouterState({
    select: (state) => state.matches.some((match) => match.routeId === PRODUCT_ROUTE_ID),
  });
  const isHomePage = useRouterState({
    select: (state) => state.matches.some((match) => match.routeId === HOME_ROUTE_ID),
  });
  // Zero-height marker where the bar rests; the bar pins once it leaves the
  // viewport top (below the status bar inside the Salla app).
  const stickySentinelRef = useRef<HTMLDivElement>(null);
  const safeTop = useAppSafeAreaTop();

  useEffect(() => {
    if (!stickyEnabled) {
      setScrolled(false);
      return;
    }
    const sentinel = stickySentinelRef.current;
    if (!sentinel || typeof IntersectionObserver === 'undefined') return;
    const observer = new IntersectionObserver(([entry]) => setScrolled(!entry.isIntersecting), {
      threshold: 0,
      rootMargin: `-${safeTop}px 0px 0px 0px`,
    });
    observer.observe(sentinel);
    return () => observer.disconnect();
  }, [stickyEnabled, safeTop]);

  useEffect(() => {
    if (!stickyEnabled) return;
    const onScroll = () => setPastHideLine(window.scrollY > HIDE_AFTER_PX);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, [stickyEnabled]);

  const hidden = scrolled && pastHideLine && direction === 'down' && !navOpen;
  const searchLabel = t('blocks.header.search', 'Search');
  const storeName = store?.name || 'ZUKHR';

  return (
    <header
      className={`site-header site-header--default site-header--zk${
        isProductPage ? ' site-header--product' : ''
      }${isHomePage ? ' site-header--home' : ''}`}
      suppressHydrationWarning
    >
      <HookSlot name="header:start" />

      <div className="site-header__ad">
        <PageAdvertisements />
      </div>

      {/* "Delivering to …" tag (bullet delivery); renders nothing when the
          store has none. Phones above the bar, desktop in its own slim row. */}
      <div className="site-header__bullet lg:hidden">
        <salla-bullet-delivery-tag data-testid="store-header-bullet-delivery-mobile" />
      </div>
      {showTopnav ? (
        <HeaderTopnav />
      ) : (
        <div className="site-header__bullet site-header__bullet--desktop hidden lg:block">
          <div className="container">
            <salla-bullet-delivery-tag data-testid="store-header-bullet-delivery-desktop" />
          </div>
        </div>
      )}

      <div ref={stickySentinelRef} className="site-header__sticky-sentinel" aria-hidden="true" />

      <div className="site-header__bar-outer">
        <div
          className={`site-header__bar${scrolled ? ' is-scrolled' : ''}${hidden ? ' is-hidden' : ''}`}
        >
          <div className="container site-header__bar-inner">
            <div className="site-header__nav-toggle">
              <button
                type="button"
                className="header-action"
                aria-label={t('blocks.header.main_menu', 'Menu')}
                aria-expanded={navOpen}
                onClick={() => setNavOpen(true)}
              >
                <span className="site-header__burger" aria-hidden="true">
                  <span />
                  <span />
                  <span />
                </span>
              </button>
            </div>

            <a className="site-header__brand" href={store?.url || '/'}>
              {/* The merchant's master logo, as uploaded to the store. */}
              <Image src={store?.logo} alt={storeName} priority width={140} height={48} />
            </a>

            <nav
              className="site-header__mainmenu"
              aria-label={t('common.titles.categories', 'Categories')}
            >
              <HeaderMainMenu />
            </nav>

            <div className="site-header__actions">
              <SearchButton
                label={searchLabel}
                hint={t('blocks.header.search_hint', 'Search products, brands, categories')}
              />
              {store?.scope && (
                <ScopeButton label={store.scope.name || t('blocks.header.branches', 'Branches')} />
              )}
              <SallaUserMenu avatarOnly showHeader relativeDropdown className="header-action" />
              {showWishlist && (
                <Link
                  to="/account/wishlist"
                  className="header-action site-header__wishlist"
                  aria-label={t('blocks.header.wishlist', 'Wishlist')}
                >
                  <HeartIcon aria-hidden="true" />
                </Link>
              )}
              <SallaCartSummary className="header-action">
                <ShoppingBagIcon slot="icon" aria-hidden="true" />
              </SallaCartSummary>
            </div>
          </div>
        </div>
      </div>

      <HeaderNav open={navOpen} onClose={() => setNavOpen(false)} />

      <SallaSearch suppressHydrationWarning />

      <HookSlot name="header:end" />
    </header>
  );
}
