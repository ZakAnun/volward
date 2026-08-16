import { describe, expect, it } from 'vitest';
import { APP_VERSION, DOWNLOADS, PAGE_COPY } from '../src/lib/site';

describe('site data', () => {
  it('pins all release assets to v0.0.3', () => {
    expect(APP_VERSION).toBe('0.0.3');
    expect(DOWNLOADS.en.map((item) => item.fileName)).toEqual([
      'volward-v0.0.3-macos-arm64.zip',
      'volward-v0.0.3-macos-x64.zip',
      'VolwardSetup-v0.0.3-windows-x64.exe',
      'Volward-v0.0.3-linux-x86_64.AppImage',
    ]);
    expect(DOWNLOADS.en.map((item) => item.href)).toEqual([
      'https://github.com/ZakAnun/volward/releases/download/v0.0.3/volward-v0.0.3-macos-arm64.zip',
      'https://github.com/ZakAnun/volward/releases/download/v0.0.3/volward-v0.0.3-macos-x64.zip',
      'https://github.com/ZakAnun/volward/releases/download/v0.0.3/VolwardSetup-v0.0.3-windows-x64.exe',
      'https://github.com/ZakAnun/volward/releases/download/v0.0.3/Volward-v0.0.3-linux-x86_64.AppImage',
    ]);
  });

  it('keeps the EN and ZH copy keys aligned', () => {
    expect(Object.keys(PAGE_COPY.en)).toEqual(Object.keys(PAGE_COPY.zh));
  });
});
