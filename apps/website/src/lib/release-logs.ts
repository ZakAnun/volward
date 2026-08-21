import { GITHUB_REPO, type Locale } from './site';

const GITHUB_RELEASES_API = `https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=10`;
const MAX_RELEASE_LOGS = 3;
const MAX_SUMMARY_LINES = 3;

type Logger = Pick<Console, 'warn'>;

type FetchReleaseLogsOptions = {
  fetchFn?: typeof fetch;
  env?: Record<string, string | undefined>;
};

type ResolveReleaseLogsOptions = FetchReleaseLogsOptions & {
  logger?: Logger;
};

type GitHubReleaseLogPayload = {
  tag_name?: unknown;
  name?: unknown;
  body?: unknown;
  html_url?: unknown;
  published_at?: unknown;
  created_at?: unknown;
  draft?: unknown;
};

export type ReleaseLog = {
  title: string;
  href: string;
  publishedAt: string;
  displayDate: string;
  summary: string[];
};

function createGitHubHeaders(env: Record<string, string | undefined>): Record<string, string> {
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

function cleanReleaseLine(line: string): string {
  return line
    .trim()
    .replace(/^---+$/, '')
    .replace(/^[-*+]\s+\[[ xX]\]\s+/, '')
    .replace(/^#{1,6}\s+/, '')
    .replace(/^[-*+]\s+/, '')
    .replace(/^\d+\.\s+/, '')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/__([^_]+)__/g, '$1')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/<[^>]+>/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

export function summarizeReleaseBody(body: string): string[] {
  return body
    .split(/\r?\n/)
    .map(cleanReleaseLine)
    .filter(Boolean)
    .slice(0, MAX_SUMMARY_LINES);
}

function formatReleaseDate(locale: Locale, publishedAt: string): string {
  const date = new Date(publishedAt);

  if (Number.isNaN(date.getTime())) {
    return publishedAt.slice(0, 10);
  }

  return new Intl.DateTimeFormat(locale === 'zh' ? 'zh-CN' : 'en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  }).format(date);
}

export function resolveReleaseLogItems(locale: Locale, releases: GitHubReleaseLogPayload[]): ReleaseLog[] {
  return releases
    .filter((release) => release.draft !== true)
    .map((release) => {
      const tagName = typeof release.tag_name === 'string' ? release.tag_name.trim() : '';
      const name = typeof release.name === 'string' ? release.name.trim() : '';
      const href = typeof release.html_url === 'string' ? release.html_url : '';
      const publishedAt =
        typeof release.published_at === 'string'
          ? release.published_at
          : typeof release.created_at === 'string'
            ? release.created_at
            : '';
      const body = typeof release.body === 'string' ? release.body : '';

      return {
        title: name || tagName,
        href,
        publishedAt,
        displayDate: formatReleaseDate(locale, publishedAt),
        summary: summarizeReleaseBody(body),
      };
    })
    .filter((release) => release.title && release.href && release.publishedAt && release.summary.length > 0)
    .slice(0, MAX_RELEASE_LOGS);
}

export async function fetchReleaseLogs(options: FetchReleaseLogsOptions = {}): Promise<GitHubReleaseLogPayload[]> {
  const fetchFn = options.fetchFn ?? fetch;
  const env = options.env ?? process.env;
  const response = await fetchFn(GITHUB_RELEASES_API, { headers: createGitHubHeaders(env) });

  if (!response.ok) {
    throw new Error(`GitHub releases request failed: HTTP ${response.status}`);
  }

  const payload = await response.json();

  if (!Array.isArray(payload)) {
    throw new Error('GitHub releases response was not an array');
  }

  return payload as GitHubReleaseLogPayload[];
}

export async function resolveReleaseLogs(
  locale: Locale,
  options: ResolveReleaseLogsOptions = {},
): Promise<ReleaseLog[]> {
  try {
    const releases = await fetchReleaseLogs(options);
    return resolveReleaseLogItems(locale, releases);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    options.logger?.warn(`[website] Skipping GitHub release logs: ${message}`);

    return [];
  }
}
