import { describe, expect, it } from 'vitest';
import { DOWNLOADS, LATEST_RELEASE_URL, PAGE_COPY } from '../src/lib/site';

describe('site data', () => {
  it('supplies latest-style release fallback download data', () => {
    expect(DOWNLOADS.en.map((item) => item.fileName)).toEqual([
      'volward-latest-macos-arm64.zip',
      'volward-latest-macos-x64.zip',
      'VolwardSetup-latest-windows-x64.exe',
      'Volward-latest-linux-x86_64.AppImage',
    ]);
    expect(DOWNLOADS.en.map((item) => item.href)).toEqual(Array(4).fill(LATEST_RELEASE_URL));
  });

  it('keeps the EN and ZH copy keys aligned', () => {
    expect(Object.keys(PAGE_COPY.en)).toEqual(Object.keys(PAGE_COPY.zh));
  });
});
