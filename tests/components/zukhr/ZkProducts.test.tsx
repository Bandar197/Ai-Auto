import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ZkProducts } from '../../../app/components/zukhr/home/ZkProducts';

const listMock = vi.fn();
const editor = { value: false };

vi.mock('../../../app/hooks/useEditorPreview', () => ({ useEditorPreview: () => editor.value }));
vi.mock('../../../app/components/common', () => ({
  ScrollCarousel: ({ children }: { children: React.ReactNode }) => <div data-testid="rail">{children}</div>,
}));
vi.mock('@salla.sa/twilight-theme-engine/i18n', () => ({
  useTranslation: () => ({ t: (_k: string, fb?: string) => fb ?? _k, locale: 'ar' }),
}));
vi.mock('@salla.sa/twilight-theme-engine/api/product', () => ({
  product: {
    queries: {
      list: (params: Record<string, unknown>) => ({
        queryKey: ['products', 'list', params],
        queryFn: () => listMock(params),
      }),
    },
  },
}));
vi.mock('@salla.sa/twilight-theme-engine/common', () => ({
  Link: ({ to, children, ...rest }: { to: string; children?: React.ReactNode }) => (
    <a href={to} {...rest}>
      {children}
    </a>
  ),
}));
vi.mock('../../../app/components/product', () => ({
  ProductCard: ({ product }: { product: { name: string } }) => <div data-testid="card">{product.name}</div>,
}));

function renderBlock(data: Record<string, unknown>) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } });
  return render(
    <QueryClientProvider client={client}>
      <ZkProducts data={data} />
    </QueryClientProvider>
  );
}

beforeEach(() => {
  listMock.mockReset();
  editor.value = false;
});

describe('ZkProducts', () => {
  it("loads Salla's most-sold list for a best-sellers section, with a view-all link", async () => {
    listMock.mockResolvedValue({ items: [{ id: 1, name: 'Anker' }, { id: 2, name: 'Apple 20W' }] });
    const { findAllByTestId, getByRole } = renderBlock({ title: 'الأكثر طلباً', source: 'sales' });
    expect(await findAllByTestId('card')).toHaveLength(2);
    expect(listMock).toHaveBeenCalledWith(expect.objectContaining({ source: 'sales', perPage: 8 }));
    expect(getByRole('heading', { name: 'الأكثر طلباً' })).toBeTruthy();
    expect(getByRole('link', { name: 'View all' }).getAttribute('href')).toBe('/products?source=sales');
  });

  it('loads exactly the picked products for a selected section', async () => {
    listMock.mockResolvedValue({ items: [{ id: 7, name: 'Pick' }] });
    renderBlock({ source: 'selected', products: [{ id: 7 }, { id: 9 }] });
    await waitFor(() =>
      expect(listMock).toHaveBeenCalledWith(expect.objectContaining({ source: 'selected', sourceValue: [7, 9] }))
    );
  });

  it('renders nothing on the live store when no products were picked, and never fetches', () => {
    const { container } = renderBlock({ title: 'هدايا تستاهل', source: 'selected' });
    expect(container.innerHTML).toBe('');
    expect(listMock).not.toHaveBeenCalled();
  });

  it('shows a hint in the editor when no products were picked', () => {
    editor.value = true;
    const { getByText } = renderBlock({ title: 'هدايا تستاهل', source: 'selected' });
    expect(getByText('Pick the products for this section in the theme editor.')).toBeTruthy();
  });

  it('renders nothing on the live store when the source has no products', async () => {
    listMock.mockResolvedValue({ items: [] });
    const { container } = renderBlock({ title: 'العروض', source: 'offers' });
    await waitFor(() => expect(listMock).toHaveBeenCalled());
    await waitFor(() => expect(container.innerHTML).toBe(''));
  });
});
