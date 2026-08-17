import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  LATEST_RELEASE_FALLBACK_FILE_NAME,
  fetchLatestRelease,
  resolveDownloadAssets,
  resolveDownloads,
} from '../src/lib/release-downloads';
import { LATEST_RELEASE_URL } from '../src/lib/site';

const versionedRelease = {
  tag_name: 'v0.0.3',
  assets: [
    {
      name: 'volward-v0.0.3-linux-x64.tar.gz',
      browser_download_url:
        'https://github.com/ZakAnun/volward/releases/download/v0.0.3/volward-v0.0.3-linux-x64.tar.gz',
    },
    {
      name: 'volward-v0.0.3-linux-x64.tar.gz.sha256',
      browser_download_url:
        'https://github.com/ZakAnun/volward/releases/download/v0.0.3/volward-v0.0.3-linux-x64.tar.gz.sha256',
    },
    {
      name: 'Volward-v0.0.3-linux-x86_64.AppImage',
      browser_download_url:
        'https://github.com/ZakAnun/volward/releases/download/v0.0.3/Volward-v0.0.3-linux-x86_64.AppImage',
    },
    {
      name: 'Volward-v0.0.3-linux-x86_64.AppImage.sha256',
      browser_download_url:
        'https://github.com/ZakAnun/volward/releases/download/v0.0.3/Volward-v0.0.3-linux-x86_64.AppImage.sha256',
    },
    {
      name: 'volward-v0.0.3-macos-arm64.zip',
      browser_download_url:
        'https://github.com/ZakAnun/volward/releases/download/v0.0.3/volward-v0.0.3-macos-arm64.zip',
    },
    {
      name: 'volward-v0.0.3-macos-arm64.zip.sha256',
      browser_download_url:
        'https://github.com/ZakAnun/volward/releases/download/v0.0.3/volward-v0.0.3-macos-arm64.zip.sha256',
    },
    {
      name: 'volward-v0.0.3-macos-x64.zip',
      browser_download_url:
        'https://github.com/ZakAnun/volward/releases/download/v0.0.3/volward-v0.0.3-macos-x64.zip',
    },
    {
      name: 'VolwardSetup-v0.0.3-windows-x64.exe',
      browser_download_url:
        'https://github.com/ZakAnun/volward/releases/download/v0.0.3/VolwardSetup-v0.0.3-windows-x64.exe',
    },
  ],
};

const latestRelease = {
  tag_name: 'v0.0.4',
  assets: [
    {
      name: 'volward-v0.0.4-macos-arm64.zip',
      browser_download_url:
        'https://github.com/ZakAnun/volward/releases/download/v0.0.4/volward-v0.0.4-macos-arm64.zip',
    },
    {
      name: 'volward-latest-macos-arm64.zip',
      browser_download_url:
        'https://github.com/ZakAnun/volward/releases/download/v0.0.4/volward-latest-macos-arm64.zip',
    },
    {
      name: 'volward-latest-macos-x64.zip',
      browser_download_url:
        'https://github.com/ZakAnun/volward/releases/download/v0.0.4/volward-latest-macos-x64.zip',
    },
    {
      name: 'VolwardSetup-latest-windows-x64.exe',
      browser_download_url:
        'https://github.com/ZakAnun/volward/releases/download/v0.0.4/VolwardSetup-latest-windows-x64.exe',
    },
    {
      name: 'Volward-latest-linux-x86_64.AppImage',
      browser_download_url:
        'https://github.com/ZakAnun/volward/releases/download/v0.0.4/Volward-latest-linux-x86_64.AppImage',
    },
  ],
};

afterEach(() => {
  vi.restoreAllMocks();
});

describe('resolveDownloadAssets', () => {
  it('selects versioned v0.0.3 assets when latest-style assets are absent', () => {
    const downloads = resolveDownloadAssets('en', versionedRelease);

    expect(downloads.map((item) => item.fileName)).toEqual([
      'volward-v0.0.3-macos-arm64.zip',
      'volward-v0.0.3-macos-x64.zip',
      'VolwardSetup-v0.0.3-windows-x64.exe',
      'Volward-v0.0.3-linux-x86_64.AppImage',
    ]);
    expect(downloads.map((item) => item.href)).toEqual([
      'https://github.com/ZakAnun/volward/releases/download/v0.0.3/volward-v0.0.3-macos-arm64.zip',
      'https://github.com/ZakAnun/volward/releases/download/v0.0.3/volward-v0.0.3-macos-x64.zip',
      'https://github.com/ZakAnun/volward/releases/download/v0.0.3/VolwardSetup-v0.0.3-windows-x64.exe',
      'https://github.com/ZakAnun/volward/releases/download/v0.0.3/Volward-v0.0.3-linux-x86_64.AppImage',
    ]);
  });

  it('prefers latest-style assets when both latest and versioned assets exist', () => {
    const downloads = resolveDownloadAssets('en', latestRelease);

    expect(downloads.map((item) => item.fileName)).toEqual([
      'volward-latest-macos-arm64.zip',
      'volward-latest-macos-x64.zip',
      'VolwardSetup-latest-windows-x64.exe',
      'Volward-latest-linux-x86_64.AppImage',
    ]);
  });

  it('does not select checksum files or Linux tar archives for primary download cards', () => {
    const downloads = resolveDownloadAssets('en', {
      tag_name: 'v0.0.3',
      assets: [
        {
          name: 'Volward-v0.0.3-linux-x86_64.AppImage.sha256',
          browser_download_url: 'https://example.invalid/appimage.sha256',
        },
        {
          name: 'volward-v0.0.3-linux-x64.tar.gz',
          browser_download_url: 'https://example.invalid/linux.tar.gz',
        },
      ],
    });

    const linux = downloads.find((item) => item.id === 'linux-appimage');
    expect(linux).toMatchObject({
      fileName: LATEST_RELEASE_FALLBACK_FILE_NAME,
      href: LATEST_RELEASE_URL,
    });
  });

  it('falls back only for platforms whose assets are missing', () => {
    const warn = vi.fn();
    const downloads = resolveDownloadAssets('en', {
      tag_name: 'v0.0.3',
      assets: [
        {
          name: 'volward-v0.0.3-macos-arm64.zip',
          browser_download_url:
            'https://github.com/ZakAnun/volward/releases/download/v0.0.3/volward-v0.0.3-macos-arm64.zip',
        },
      ],
    }, { logger: { warn } });

    expect(downloads.find((item) => item.id === 'macos-arm64')).toMatchObject({
      fileName: 'volward-v0.0.3-macos-arm64.zip',
    });
    expect(downloads.find((item) => item.id === 'windows-x64')).toMatchObject({
      fileName: LATEST_RELEASE_FALLBACK_FILE_NAME,
      href: LATEST_RELEASE_URL,
    });
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('windows-x64'));
  });

  it('keeps localized download ids aligned and uses shared site data copy', () => {
    const en = resolveDownloadAssets('en', versionedRelease);
    const zh = resolveDownloadAssets('zh', versionedRelease);

    expect(en.map((item) => item.id)).toEqual(zh.map((item) => item.id));
    expect(en.map((item) => item.label)).toEqual([
      'macOS (Apple Silicon)',
      'macOS (Intel)',
      'Windows (x64)',
      'Linux AppImage',
    ]);
    expect(zh.map((item) => item.label)).toEqual([
      'macOS（Apple Silicon）',
      'macOS（Intel）',
      'Windows（x64）',
      'Linux AppImage',
    ]);
  });
});

describe('fetchLatestRelease', () => {
  it('uses GITHUB_TOKEN when it is available', async () => {
    const fetchFn = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => versionedRelease,
    });

    await fetchLatestRelease({
      fetchFn,
      env: { GITHUB_TOKEN: 'ghs_build_token', GH_TOKEN: 'ignored' },
    });

    expect(fetchFn).toHaveBeenCalledWith(
      'https://api.github.com/repos/ZakAnun/volward/releases/latest',
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: 'Bearer ghs_build_token',
          Accept: 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'volward-website-build',
        }),
      }),
    );
  });

  it('uses GH_TOKEN when GITHUB_TOKEN is unavailable', async () => {
    const fetchFn = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => versionedRelease,
    });

    await fetchLatestRelease({
      fetchFn,
      env: { GH_TOKEN: 'ghp_build_token' },
    });

    expect(fetchFn).toHaveBeenCalledWith(
      'https://api.github.com/repos/ZakAnun/volward/releases/latest',
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: 'Bearer ghp_build_token',
        }),
      }),
    );
  });
});

describe('resolveDownloads', () => {
  it('falls back to the latest release page for every platform when the API request fails', async () => {
    const warn = vi.fn();

    const downloads = await resolveDownloads('en', {
      fetchFn: vi.fn().mockRejectedValue(new Error('rate limited')),
      logger: { warn },
      env: {},
    });

    expect(downloads).toHaveLength(4);
    expect(downloads.every((item) => item.href === LATEST_RELEASE_URL)).toBe(true);
    expect(downloads.every((item) => item.fileName === LATEST_RELEASE_FALLBACK_FILE_NAME)).toBe(true);
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('rate limited'));
  });
});
