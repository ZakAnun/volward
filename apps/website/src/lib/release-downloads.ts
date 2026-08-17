import type { DownloadAsset, Locale } from './site';
import { DOWNLOAD_ENTRIES, DOWNLOADS, GITHUB_REPO, LATEST_RELEASE_URL } from './site';

export const LATEST_RELEASE_FALLBACK_FILE_NAME = 'GitHub Releases';

const GITHUB_LATEST_RELEASE_API = `https://api.github.com/repos/${GITHUB_REPO}/releases/latest`;

type ReleaseAsset = {
  name: string;
  browser_download_url: string;
};

type GitHubRelease = {
  tag_name: string;
  assets: ReleaseAsset[];
};

type Logger = Pick<Console, 'warn'>;

type FetchLatestReleaseOptions = {
  fetchFn?: typeof fetch;
  env?: Record<string, string | undefined>;
};

type ResolveDownloadsOptions = FetchLatestReleaseOptions & {
  logger?: Logger;
};

type ResolveDownloadAssetsOptions = {
  logger?: Logger;
};

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

function assertPlatformMatchersCoverSiteData() {
  const matcherIds = PLATFORM_MATCHERS.map((platform) => platform.id);
  const entryIds = DOWNLOAD_ENTRIES.map((entry) => entry.id);

  if (matcherIds.join('|') !== entryIds.join('|')) {
    throw new Error('Release download platform matchers do not align with site download entries');
  }
}

export function resolveDownloadAssets(
  locale: Locale,
  release: GitHubRelease,
  options: ResolveDownloadAssetsOptions = {},
): DownloadAsset[] {
  assertPlatformMatchersCoverSiteData();
  const assets = release.assets.filter((asset) => !asset.name.endsWith('.sha256'));
  const copyById = new Map(DOWNLOADS[locale].map((item) => [item.id, item]));
  const latestFileNameById = new Map(DOWNLOAD_ENTRIES.map((entry) => [entry.id, entry.fileName]));

  return PLATFORM_MATCHERS.map((platform) => {
    const latestFileName = latestFileNameById.get(platform.id);
    const exactLatest = assets.find((asset) => asset.name === latestFileName);
    const exactVersioned = assets.find((asset) => asset.name === platform.versionedFileName(release.tag_name));
    const fallback = assets.find((asset) => platform.matchesFallback(asset.name));
    const asset = exactLatest ?? exactVersioned ?? fallback;
    const copy = copyById.get(platform.id);

    if (!copy) {
      throw new Error(`Missing localized download copy for ${platform.id}`);
    }

    if (!asset) {
      options.logger?.warn(`[website] Falling back to GitHub Releases for ${platform.id}: matching asset not found`);

      return {
        id: platform.id,
        fileName: LATEST_RELEASE_FALLBACK_FILE_NAME,
        href: LATEST_RELEASE_URL,
        label: copy.label,
        hint: copy.hint,
      };
    }

    return {
      id: platform.id,
      fileName: asset.name,
      href: asset.browser_download_url,
      label: copy.label,
      hint: copy.hint,
    };
  });
}

export async function fetchLatestRelease(options: FetchLatestReleaseOptions = {}): Promise<GitHubRelease> {
  const fetchFn = options.fetchFn ?? fetch;
  const env = options.env ?? process.env;
  const token = env.GITHUB_TOKEN ?? env.GH_TOKEN;
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'volward-website-build',
  };

  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  const response = await fetchFn(GITHUB_LATEST_RELEASE_API, { headers });

  if (!response.ok) {
    throw new Error(`GitHub latest release request failed: HTTP ${response.status}`);
  }

  const payload = (await response.json()) as Partial<GitHubRelease>;

  if (typeof payload.tag_name !== 'string' || !Array.isArray(payload.assets)) {
    throw new Error('GitHub latest release response did not include tag_name and assets');
  }

  return {
    tag_name: payload.tag_name,
    assets: payload.assets
      .filter(
        (asset): asset is ReleaseAsset =>
          typeof asset?.name === 'string' && typeof asset?.browser_download_url === 'string',
      )
      .map((asset) => ({
        name: asset.name,
        browser_download_url: asset.browser_download_url,
      })),
  };
}

export async function resolveDownloads(
  locale: Locale,
  options: ResolveDownloadsOptions = {},
): Promise<DownloadAsset[]> {
  try {
    const release = await fetchLatestRelease(options);
    return resolveDownloadAssets(locale, release, { logger: options.logger });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    options.logger?.warn(`[website] Falling back to GitHub Releases download links: ${message}`);

    return DOWNLOADS[locale].map((item) => ({
      id: item.id,
      fileName: LATEST_RELEASE_FALLBACK_FILE_NAME,
      href: LATEST_RELEASE_URL,
      label: item.label,
      hint: item.hint,
    }));
  }
}
