import type { DownloadAsset, Locale } from './site';
import { DOWNLOAD_ENTRIES, DOWNLOADS, GITHUB_RELEASES_URL, GITHUB_REPO } from './site';
import {
  assertPlatformMatchersCoverSiteData,
  findReleaseDownloadOption,
  type GitHubReleaseAssets,
  type ReleaseAsset,
} from './release-assets';

export const RELEASES_FALLBACK_FILE_NAME = 'GitHub Releases';

const GITHUB_LATEST_RELEASE_API = `https://api.github.com/repos/${GITHUB_REPO}/releases/latest`;

type GitHubRelease = GitHubReleaseAssets;

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

export function resolveDownloadAssets(
  locale: Locale,
  release: GitHubRelease,
  options: ResolveDownloadAssetsOptions = {},
): DownloadAsset[] {
  assertPlatformMatchersCoverSiteData();
  const copyById = new Map(DOWNLOADS[locale].map((item) => [item.id, item]));

  return DOWNLOAD_ENTRIES.map((entry) => {
    const asset = findReleaseDownloadOption(release, entry.id);
    const copy = copyById.get(entry.id);

    if (!copy) {
      throw new Error(`Missing localized download copy for ${entry.id}`);
    }

    if (!asset) {
      options.logger?.warn(`[website] Falling back to GitHub Releases for ${entry.id}: matching asset not found`);

      return {
        id: entry.id,
        fileName: RELEASES_FALLBACK_FILE_NAME,
        href: GITHUB_RELEASES_URL,
        label: copy.label,
        hint: copy.hint,
      };
    }

    return {
      id: entry.id,
      fileName: asset.fileName,
      href: asset.href,
      label: copy.label,
      hint: copy.hint,
    };
  });
}

export async function fetchLatestRelease(options: FetchLatestReleaseOptions = {}): Promise<GitHubRelease> {
  const fetchFn = options.fetchFn ?? fetch;
  const env = options.env ?? process.env;
  const token = env.GITHUB_TOKEN || env.GH_TOKEN;
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

    return DOWNLOADS[locale];
  }
}
