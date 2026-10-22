import { useTwilight } from '@salla.sa/twilight-theme-engine/providers';

/**
 * True in local dev and inside the Salla theme editor preview: the places a
 * merchant is setting the theme up. Blocks that still need input (no products
 * picked yet) show a hint there and render nothing on the live store.
 */
export function useEditorPreview(): boolean {
  const { theme } = useTwilight();
  return import.meta.env.DEV || theme?.mode === 'preview';
}
