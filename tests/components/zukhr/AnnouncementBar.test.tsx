import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render } from '@testing-library/react';
import { AnnouncementBar } from '../../../app/components/zukhr/AnnouncementBar';

const state = { settings: {} as Record<string, unknown> };

vi.mock('@salla.sa/twilight-theme-engine/providers', () => ({
  useTwilight: () => ({ theme: { settings: state.settings } }),
}));
vi.mock('@salla.sa/twilight-theme-engine/i18n', () => ({
  useTranslation: () => ({ locale: 'ar' }),
}));

beforeEach(() => {
  state.settings = {};
});

describe('AnnouncementBar', () => {
  it('shows the brand line by default', () => {
    const { container } = render(<AnnouncementBar />);
    expect(container.querySelector('.zk-announcement')?.textContent).toBe('✦ زخر | اختيارات تستاهل ✦');
  });

  it('shows the merchant text as a link when a link is set', () => {
    state.settings = { announcement_text: 'شحن مجاني', announcement_link: 'https://zukhr.sa/offers' };
    const { getByRole } = render(<AnnouncementBar />);
    expect(getByRole('link', { name: 'شحن مجاني' }).getAttribute('href')).toBe('https://zukhr.sa/offers');
  });

  it('renders nothing when turned off', () => {
    state.settings = { announcement_enabled: false };
    const { container } = render(<AnnouncementBar />);
    expect(container.innerHTML).toBe('');
  });
});
