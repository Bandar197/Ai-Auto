import React from 'react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, fireEvent, act } from '@testing-library/react';
import { Header } from '../../../app/components/layout/Header';
import { HOME_ROUTE_ID } from '../../../app/lib/routeIds';

const state = {
  store: {
    url: '/',
    name: 'Acme',
    logo: 'logo.png',
    description: '<p>Handmade goods</p>',
    social: { twitter: 'https://x.com/acme' },
  } as Record<string, unknown>,
  theme: { settings: {} } as Record<string, unknown>,
  isHome: true,
  routeIds: [] as string[],
};

type RouterStateStub = {
  matches: { routeId: string }[];
};

vi.mock('@tanstack/react-router', () => ({
  useRouterState: ({ select }: { select: (s: RouterStateStub) => unknown }) =>
    select({
      matches: state.routeIds.map((routeId) => ({ routeId })),
    }),
}));

vi.mock('@salla.sa/twilight-theme-engine/providers', () => ({
  useTwilight: () => ({ store: state.store, theme: state.theme }),
  useIsHome: () => state.isHome,
}));

vi.mock('@salla.sa/twilight-theme-engine/i18n', () => ({
  useTranslation: () => ({ t: (_k: string, fb?: string) => fb ?? _k }),
}));

vi.mock('@salla.sa/twilight-theme-engine/hooks', () => ({
  HookSlot: ({ name }: { name: string }) => <div data-hook-slot={name} />,
}));

vi.mock('@salla.sa/twilight-theme-engine/common', () => ({
  Image: (props: Record<string, unknown>) => (
    <img alt={String(props.alt ?? '')} src={String(props.src ?? '')} />
  ),
  Link: ({ to, children, ...rest }: { to: string; children?: React.ReactNode }) => (
    <a href={to} {...rest}>
      {children}
    </a>
  ),
}));

vi.mock('../../../app/components/layout/HeaderMainMenu', () => ({
  HeaderMainMenu: () => <div data-testid="header-main-menu" />,
}));
vi.mock('../../../app/components/layout/HeaderNav', () => ({
  HeaderNav: ({ open }: { open: boolean }) => <nav data-testid="header-nav" data-open={open} />,
}));

vi.mock('@salla.sa/twilight-theme-engine/layout', () => ({
  PageAdvertisements: () => <div data-testid="advertisement-bar-render" />,
}));
vi.mock('@salla.sa/twilight-components-react/search', () => ({
  SallaSearch: () => <salla-search />,
}));
vi.mock('@salla.sa/twilight-components-react/user-menu', () => ({
  SallaUserMenu: () => <salla-user-menu />,
}));
vi.mock('@salla.sa/twilight-components-react/cart-summary', () => ({
  SallaCartSummary: ({ children }: { children?: React.ReactNode }) => (
    <salla-cart-summary>{children}</salla-cart-summary>
  ),
}));

beforeEach(() => {
  state.store = {
    url: '/',
    name: 'Acme',
    logo: 'logo.png',
    description: '<p>Handmade goods</p>',
    social: { twitter: 'https://x.com/acme' },
  };
  state.theme = { settings: {} };
  state.isHome = true;
  state.routeIds = [];
});

// The pin observer: records its options, and lets a test push an intersection.
let pinCallback: ((entries: { isIntersecting: boolean }[]) => void) | null = null;
const observerMargins: string[] = [];
class FakeIntersectionObserver {
  constructor(cb: (entries: { isIntersecting: boolean }[]) => void, options: { rootMargin?: string }) {
    pinCallback = cb;
    observerMargins.push(options?.rootMargin ?? '');
  }
  observe() {}
  unobserve() {}
  disconnect() {}
}

beforeEach(() => {
  pinCallback = null;
  observerMargins.length = 0;
  vi.stubGlobal('IntersectionObserver', FakeIntersectionObserver);
});

const scrollTo = (y: number) => {
  Object.defineProperty(window, 'scrollY', { value: y, configurable: true });
  fireEvent.scroll(window);
};

afterEach(() => {
  document.documentElement.style.removeProperty('--app-safe-area-top');
  vi.unstubAllGlobals();
});

describe('Header', () => {
  it('renders the shell: logo, actions, search modal, cart, wishlist and the hook slots', () => {
    const { container, getAllByLabelText, getByLabelText } = render(<Header />);
    expect(container.querySelector('header.site-header.site-header--zk')).toBeTruthy();
    expect(container.querySelector('.site-header__brand img')?.getAttribute('alt')).toBe('Acme');
    expect(container.querySelector('salla-user-menu')).toBeTruthy();
    expect(container.querySelector('salla-cart-summary')).toBeTruthy();
    expect(container.querySelector('salla-search')).toBeTruthy();
    expect(getAllByLabelText('Search')).toHaveLength(1);
    expect(getByLabelText('Wishlist').getAttribute('href')).toBe('/account/wishlist');
    expect(container.querySelector('[data-hook-slot="header:start"]')).toBeTruthy();
    expect(container.querySelector('[data-hook-slot="header:end"]')).toBeTruthy();
  });

  it('renders the category menu in a labelled nav', () => {
    const { getByTestId } = render(<Header />);
    expect(getByTestId('header-main-menu').closest('nav')?.getAttribute('aria-label')).toBe('Categories');
  });

  it('shows the search hint text inside the search button', () => {
    const { getByLabelText } = render(<Header />);
    expect(getByLabelText('Search').textContent).toContain('Search products, brands, categories');
  });

  it('hides the wishlist icon when header_show_wishlist is off', () => {
    state.theme = { settings: { header_show_wishlist: false } };
    const { queryByLabelText } = render(<Header />);
    expect(queryByLabelText('Wishlist')).toBeNull();
  });

  it('renders the top bar only when header_show_topnav is on', () => {
    const { container, rerender } = render(<Header />);
    expect(container.querySelector('.site-header__bullet--desktop')).toBeTruthy();
    state.theme = { settings: { header_show_topnav: true } };
    rerender(<Header />);
    expect(container.querySelector('.site-header__bullet--desktop')).toBeNull();
  });

  it('opens the nav drawer when the menu button is clicked', () => {
    const { getByLabelText, getByTestId } = render(<Header />);
    const button = getByLabelText('Menu');
    expect(button.getAttribute('aria-expanded')).toBe('false');
    fireEvent.click(button);
    expect(button.getAttribute('aria-expanded')).toBe('true');
    expect(getByTestId('header-nav').getAttribute('data-open')).toBe('true');
  });

  it('dispatches the search event when the search button is clicked', () => {
    const dispatch = vi.fn();
    (window as unknown as { salla: unknown }).salla = { event: { dispatch } };
    const { getByLabelText } = render(<Header />);
    fireEvent.click(getByLabelText('Search'));
    expect(dispatch).toHaveBeenCalledWith('search::open');
  });

  it('pins the bar once its resting place leaves the viewport', () => {
    const { container } = render(<Header />);
    expect(container.querySelector('.site-header__bar.is-scrolled')).toBeNull();
    act(() => pinCallback?.([{ isIntersecting: false }]));
    expect(container.querySelector('.site-header__bar.is-scrolled')).toBeTruthy();
  });

  it("pins at the Salla app's status bar line, and follows the inset", async () => {
    const pinMargins = () => observerMargins.filter((m) => m.startsWith('-'));
    document.documentElement.style.setProperty('--app-safe-area-top', '62px');
    render(<Header />);
    expect(pinMargins().at(-1)).toBe('-62px 0px 0px 0px');
    await act(async () => {
      document.documentElement.style.setProperty('--app-safe-area-top', '47px');
    });
    expect(pinMargins().at(-1)).toBe('-47px 0px 0px 0px');
  });

  it('hides the pinned bar while scrolling down far, and brings it back on scroll up', async () => {
    const { container } = render(<Header />);
    act(() => pinCallback?.([{ isIntersecting: false }]));
    const raf = vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => {
      cb(0);
      return 0;
    });
    act(() => scrollTo(0));
    act(() => scrollTo(600));
    expect(container.querySelector('.site-header__bar.is-hidden')).toBeTruthy();
    act(() => scrollTo(500));
    expect(container.querySelector('.site-header__bar.is-hidden')).toBeNull();
    raf.mockRestore();
  });

  it('never pins the bar when header_is_sticky is disabled', () => {
    state.theme = { settings: { header_is_sticky: false } };
    const { container } = render(<Header />);
    act(() => pinCallback?.([{ isIntersecting: false }]));
    expect(container.querySelector('.site-header__bar.is-scrolled')).toBeNull();
  });

  it('adds the product-page modifier from route match state, not the body class', () => {
    state.routeIds = ['/{-$locale}/$slug/p{$id}'];
    const { container } = render(<Header />);
    expect(container.querySelector('header.site-header--product')).toBeTruthy();
  });

  it('omits the product-page modifier on other routes', () => {
    state.routeIds = ['/{-$locale}/cart'];
    const { container } = render(<Header />);
    expect(container.querySelector('header.site-header--product')).toBeNull();
  });

  it('adds the home modifier from route match state, so it is in the SSR markup', () => {
    state.routeIds = [HOME_ROUTE_ID];
    const { container } = render(<Header />);
    expect(container.querySelector('header.site-header--home')).toBeTruthy();
  });

  it('omits the home modifier on other routes', () => {
    state.routeIds = ['/{-$locale}/cart'];
    const { container } = render(<Header />);
    expect(container.querySelector('header.site-header--home')).toBeNull();
  });

  it("renders the engine's ad bar in the header's ad slot", () => {
    const { getByTestId } = render(<Header />);
    expect(getByTestId('advertisement-bar-render').closest('.site-header__ad')).not.toBeNull();
  });
});
