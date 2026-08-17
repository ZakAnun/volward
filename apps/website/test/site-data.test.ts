import { describe, expect, it } from 'vitest';
import { DOWNLOADS, LATEST_RELEASE_URL, PAGE_COPY } from '../src/lib/site';

describe('site data', () => {
  it('keeps fallback downloads safe when the resolver is not used', () => {
    expect(DOWNLOADS.en).toHaveLength(4);
    expect(DOWNLOADS.zh).toHaveLength(4);
    expect(DOWNLOADS.en.every((item) => item.href === LATEST_RELEASE_URL)).toBe(true);
    expect(DOWNLOADS.zh.every((item) => item.href === LATEST_RELEASE_URL)).toBe(true);
    expect(DOWNLOADS.en.map((item) => item.id)).toEqual([
      'macos-arm64',
      'macos-x64',
      'windows-x64',
      'linux-appimage',
    ]);
  });

  it('keeps the EN and ZH copy keys aligned', () => {
    expect(Object.keys(PAGE_COPY.en)).toEqual(Object.keys(PAGE_COPY.zh));
  });
});
