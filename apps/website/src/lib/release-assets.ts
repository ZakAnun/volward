import type { DownloadAsset } from './site';
import { DOWNLOAD_ENTRIES } from './site';

export type ReleaseAsset = {
  name: string;
  browser_download_url: string;
};

export type GitHubReleaseAssets = {
  tag_name: string;
  assets: ReleaseAsset[];
};

export type ReleaseDownloadOption = Pick<DownloadAsset, 'id' | 'href' | 'fileName'>;

type PlatformMatcher = {
  id: DownloadAsset['id'];
  versionedFileName: (tagName: string) => string;
  matchesFallback: (fileName: string) => boolean;
};

const PLATFORM_MATCHERS: PlatformMatcher[] = [
  {
    id: 'macos-arm64',
    versionedFileName: (tagName) => `volward-${tagName}-macos-arm64.zip`,
    matchesFallback: (fileName) => fileName.includes('macos-arm64') && fileName.endsWith('.zip'),
  },
  {
    id: 'macos-x64',
    versionedFileName: (tagName) => `volward-${tagName}-macos-x64.zip`,
    matchesFallback: (fileName) => fileName.includes('macos-x64') && fileName.endsWith('.zip'),
  },
  {
    id: 'windows-x64',
    versionedFileName: (tagName) => `VolwardSetup-${tagName}-windows-x64.exe`,
    matchesFallback: (fileName) => fileName.includes('windows-x64') && fileName.endsWith('.exe'),
  },
  {
    id: 'linux-appimage',
    versionedFileName: (tagName) => `Volward-${tagName}-linux-x86_64.AppImage`,
    matchesFallback: (fileName) => fileName.includes('linux-x86_64') && fileName.endsWith('.AppImage'),
  },
];

export function assertPlatformMatchersCoverSiteData(): void {
  const matcherIds = PLATFORM_MATCHERS.map((platform) => platform.id);
  const entryIds = DOWNLOAD_ENTRIES.map((entry) => entry.id);

  if (matcherIds.join('|') !== entryIds.join('|')) {
    throw new Error('Release download platform matchers do not align with site download entries');
  }
}

export function findReleaseDownloadOption(
  release: GitHubReleaseAssets,
  id: DownloadAsset['id'],
): ReleaseDownloadOption | undefined {
  assertPlatformMatchersCoverSiteData();

  const matcher = PLATFORM_MATCHERS.find((platform) => platform.id === id);
  const entry = DOWNLOAD_ENTRIES.find((item) => item.id === id);

  if (!matcher || !entry) {
    return undefined;
  }

  const assets = release.assets.filter((asset) => !asset.name.endsWith('.sha256'));
  const exactLatest = assets.find((asset) => asset.name === entry.fileName);
  const exactVersioned = assets.find((asset) => asset.name === matcher.versionedFileName(release.tag_name));
  const fallback = assets.find((asset) => matcher.matchesFallback(asset.name));
  const asset = exactLatest ?? exactVersioned ?? fallback;

  if (!asset) {
    return undefined;
  }

  return {
    id,
    fileName: asset.name,
    href: asset.browser_download_url,
  };
}

export function resolveReleaseDownloadOptions(release: GitHubReleaseAssets): ReleaseDownloadOption[] {
  assertPlatformMatchersCoverSiteData();

  return DOWNLOAD_ENTRIES.map((entry) => findReleaseDownloadOption(release, entry.id)).filter(
    (option): option is ReleaseDownloadOption => Boolean(option),
  );
}
