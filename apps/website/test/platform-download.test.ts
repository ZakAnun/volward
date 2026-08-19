import { describe, expect, it } from 'vitest';
import {
  detectDownloadTargetId,
  initializeDownloadTargets,
  resolveDownloadHref,
} from '../src/lib/platform-download';

describe('detectDownloadTargetId', () => {
  it('selects Apple Silicon macOS when architecture is available', () => {
    expect(detectDownloadTargetId({ userAgentDataPlatform: 'macOS', architecture: 'arm' })).toBe('macos-arm64');
  });

  it('selects Intel macOS when architecture is available', () => {
    expect(detectDownloadTargetId({ platform: 'MacIntel', architecture: 'x86' })).toBe('macos-x64');
  });

  it('falls back for macOS when the architecture is unknown', () => {
    expect(detectDownloadTargetId({ platform: 'MacIntel' })).toBeUndefined();
  });

  it('selects Windows x64 from browser platform signals', () => {
    expect(detectDownloadTargetId({ userAgentDataPlatform: 'Windows' })).toBe('windows-x64');
  });

  it('falls back when Windows reports an unsupported architecture', () => {
    expect(detectDownloadTargetId({ userAgentDataPlatform: 'Windows', architecture: 'arm64' })).toBeUndefined();
  });

  it('selects Linux AppImage from user agent signals', () => {
    expect(detectDownloadTargetId({ userAgent: 'Mozilla/5.0 (X11; Linux x86_64)' })).toBe('linux-appimage');
  });

  it('falls back when the OS cannot be detected', () => {
    expect(detectDownloadTargetId({ userAgentDataPlatform: 'Chrome OS' })).toBeUndefined();
  });
});

describe('resolveDownloadHref', () => {
  it('keeps the releases fallback when no compatible target exists', () => {
    expect(
      resolveDownloadHref(
        [{ id: 'windows-x64', href: 'https://example.com/windows-x64.exe' }],
        undefined,
        'https://example.com/releases',
      ),
    ).toBe('https://example.com/releases');
  });
});

describe('initializeDownloadTargets', () => {
  it('applies the detected target before refreshed assets finish loading', async () => {
    const calls: string[] = [];
    let resolveRefresh: (options: Array<{ id: string; href: string }>) => void = () => undefined;
    const refreshPromise = new Promise<Array<{ id: string; href: string }>>((resolve) => {
      resolveRefresh = resolve;
    });

    const completion = initializeDownloadTargets({
      detectTarget: async () => 'macos-arm64',
      refreshOptions: () => refreshPromise,
      updateOptions: () => calls.push('update'),
      applyTarget: (targetId) => calls.push(`apply:${targetId}`),
    });

    await Promise.resolve();
    await Promise.resolve();
    expect(calls).toEqual(['apply:macos-arm64']);

    resolveRefresh([{ id: 'macos-arm64', href: 'https://example.com/macos-arm64.zip' }]);
    await completion;
    expect(calls).toEqual(['apply:macos-arm64', 'update', 'apply:macos-arm64']);
  });
});
