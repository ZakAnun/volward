import type { DownloadAsset, Locale } from './site';
import { DOWNLOAD_ENTRIES, DOWNLOADS, GITHUB_RELEASES_URL, GITHUB_REPO } from './site';
import { isStrictReleaseBuild, type ReleaseBuildOptions } from './release-build-options';
import {
  assertPlatformMatchersCoverSiteData,
  findReleaseDownloadOption,
  type GitHubReleaseAssets,
  type ReleaseAsset,
} from './release-assets';

export const RELEASES_FALLBACK_FILE_NAME = 'GitHub Releases';

const GITHUB_LATEST_RELEASE_API = `https://api.github.com/repos/${GITHUB_REPO}/releases/latest`;

function createGitHubReleaseHeaders(env: Record<string, string | undefined>): Record<string, string> {
  const token = env.GITHUB_TOKEN || env.GH_TOKEN;
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'volward-website-build',
  };

  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  return headers;
}

function parseGitHubReleasePayload(payload: Partial<GitHubRelease>, source: string): GitHubRelease {
  if (typeof payload.tag_name !== 'string' || !Array.isArray(payload.assets)) {
    throw new Error(`GitHub ${source} response did not include tag_name and assets`);
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

type GitHubRelease = GitHubReleaseAssets;

type Logger = Pick<Console, 'warn'>;

type FetchLatestReleaseOptions = {
  fetchFn?: typeof fetch;
  env?: Record<string, string | undefined>;
};

type ResolveDownloadsOptions = FetchLatestReleaseOptions &
  ReleaseBuildOptions & {
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
  const response = await fetchFn(GITHUB_LATEST_RELEASE_API, { headers: createGitHubReleaseHeaders(env) });

  if (!response.ok) {
    throw new Error(`GitHub latest release request failed: HTTP ${response.status}`);
  }

  return parseGitHubReleasePayload((await response.json()) as Partial<GitHubRelease>, 'latest release');
}

export async function fetchReleaseByTag(
  tag: string,
  options: FetchLatestReleaseOptions = {},
): Promise<GitHubRelease> {
  const fetchFn = options.fetchFn ?? fetch;
  const env = options.env ?? process.env;
  const normalizedTag = tag.trim();
  const response = await fetchFn(
    `https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${encodeURIComponent(normalizedTag)}`,
    { headers: createGitHubReleaseHeaders(env) },
  );

  if (!response.ok) {
    throw new Error(`GitHub release request failed for ${normalizedTag}: HTTP ${response.status}`);
  }

  return parseGitHubReleasePayload((await response.json()) as Partial<GitHubRelease>, `release ${normalizedTag}`);
}

async function fetchReleaseForBuild(options: FetchLatestReleaseOptions = {}): Promise<GitHubRelease> {
  const env = options.env ?? process.env;
  const expectedTag = env.EXPECTED_RELEASE_TAG?.trim();

  if (expectedTag) {
    return fetchReleaseByTag(expectedTag, options);
  }

  return fetchLatestRelease(options);
}

export async function resolveDownloads(
  locale: Locale,
  options: ResolveDownloadsOptions = {},
): Promise<DownloadAsset[]> {
  const env = options.env ?? process.env;
  const strict = isStrictReleaseBuild(env, options);

  try {
    const release = await fetchReleaseForBuild(options);
    const downloads = resolveDownloadAssets(locale, release, { logger: options.logger });

    if (strict) {
      const missing = downloads.filter((item) => item.href === GITHUB_RELEASES_URL);
      if (missing.length > 0) {
        throw new Error(
          `Latest release ${release.tag_name} is missing download assets for: ${missing.map((item) => item.id).join(', ')}`,
        );
      }
    }

    return downloads;
  } catch (error) {
    if (strict) {
      throw error;
    }

    const message = error instanceof Error ? error.message : String(error);
    options.logger?.warn(`[website] Falling back to GitHub Releases download links: ${message}`);

    return DOWNLOADS[locale];
  }
}
