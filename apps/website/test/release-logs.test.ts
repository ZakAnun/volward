import { afterEach, describe, expect, it, vi } from 'vitest';
import { fetchReleaseLogs, resolveReleaseLogItems, resolveReleaseLogs, summarizeReleaseBody } from '../src/lib/release-logs';

afterEach(() => {
  vi.restoreAllMocks();
});

describe('summarizeReleaseBody', () => {
  it('cleans markdown and keeps the first three displayable lines', () => {
    expect(
      summarizeReleaseBody([
        '## What changed',
        '- Added `macOS` downloads',
        '- [Fixed release links](https://example.invalid)',
        '1. Improved Windows installer',
        '- Hidden fourth line',
      ].join('\n')),
    ).toEqual(['What changed', 'Added macOS downloads', 'Fixed release links']);
  });
});

describe('resolveReleaseLogItems', () => {
  it('returns the latest three release logs with localized dates', () => {
    const logs = resolveReleaseLogItems('en', [
      {
        tag_name: 'v0.0.4',
        name: 'Volward 0.0.4',
        html_url: 'https://github.com/ZakAnun/volward/releases/tag/v0.0.4',
        published_at: '2026-08-17T12:00:00Z',
        body: '- Download page polish',
      },
      {
        tag_name: 'v0.0.3',
        name: '',
        html_url: 'https://github.com/ZakAnun/volward/releases/tag/v0.0.3',
        published_at: '2026-08-16T12:00:00Z',
        body: '- Latest-style assets',
      },
      {
        tag_name: 'v0.0.2',
        html_url: 'https://github.com/ZakAnun/volward/releases/tag/v0.0.2',
        published_at: '2026-08-15T12:00:00Z',
        body: '- Website release',
      },
      {
        tag_name: 'v0.0.1',
        html_url: 'https://github.com/ZakAnun/volward/releases/tag/v0.0.1',
        published_at: '2026-08-14T12:00:00Z',
        body: '- Initial release',
      },
    ]);

    expect(logs).toHaveLength(3);
    expect(logs.map((log) => log.title)).toEqual(['Volward 0.0.4', 'v0.0.3', 'v0.0.2']);
    expect(logs[0]).toMatchObject({
      displayDate: 'Aug 17, 2026',
      summary: ['Download page polish'],
    });
  });

  it('skips drafts and releases without body content', () => {
    const logs = resolveReleaseLogItems('zh', [
      {
        tag_name: 'v0.0.4',
        html_url: 'https://github.com/ZakAnun/volward/releases/tag/v0.0.4',
        published_at: '2026-08-17T12:00:00Z',
        body: '- Hidden draft',
        draft: true,
      },
      {
        tag_name: 'v0.0.3',
        html_url: 'https://github.com/ZakAnun/volward/releases/tag/v0.0.3',
        published_at: '2026-08-16T12:00:00Z',
        body: '',
      },
      {
        tag_name: 'v0.0.2',
        html_url: 'https://github.com/ZakAnun/volward/releases/tag/v0.0.2',
        published_at: '2026-08-15T12:00:00Z',
        body: '- 可展示更新',
      },
    ]);

    expect(logs).toHaveLength(1);
    expect(logs[0]).toMatchObject({
      title: 'v0.0.2',
      displayDate: '2026年8月15日',
      summary: ['可展示更新'],
    });
  });
});

describe('fetchReleaseLogs', () => {
  it('requests enough release candidates with a GitHub token when available', async () => {
    const fetchFn = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => [],
    });

    await fetchReleaseLogs({
      fetchFn,
      env: { GH_TOKEN: 'ghp_build_token' },
    });

    expect(fetchFn).toHaveBeenCalledWith(
      'https://api.github.com/repos/ZakAnun/volward/releases?per_page=10',
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: 'Bearer ghp_build_token',
          Accept: 'application/vnd.github+json',
        }),
      }),
    );
  });
});

describe('resolveReleaseLogs', () => {
  it('returns three displayable logs when newer releases cannot be displayed', async () => {
    const releases = [
      {
        tag_name: 'v0.0.5',
        html_url: 'https://github.com/ZakAnun/volward/releases/tag/v0.0.5',
        published_at: '2026-08-18T12:00:00Z',
        body: '',
      },
      {
        tag_name: 'v0.0.4',
        html_url: 'https://github.com/ZakAnun/volward/releases/tag/v0.0.4',
        published_at: '2026-08-17T12:00:00Z',
        body: '- Download page polish',
      },
      {
        tag_name: 'v0.0.3',
        html_url: 'https://github.com/ZakAnun/volward/releases/tag/v0.0.3',
        published_at: '2026-08-16T12:00:00Z',
        body: '- Latest-style assets',
      },
      {
        tag_name: 'v0.0.2',
        html_url: 'https://github.com/ZakAnun/volward/releases/tag/v0.0.2',
        published_at: '2026-08-15T12:00:00Z',
        body: '- Website release',
      },
    ];

    const logs = await resolveReleaseLogs('en', {
      fetchFn: vi.fn().mockResolvedValue({
        ok: true,
        json: async () => releases,
      }),
      env: {},
    });

    expect(logs.map((log) => log.title)).toEqual(['v0.0.4', 'v0.0.3', 'v0.0.2']);
  });

  it('returns an empty list when the GitHub request fails', async () => {
    const warn = vi.fn();

    await expect(
      resolveReleaseLogs('en', {
        fetchFn: vi.fn().mockRejectedValue(new Error('offline')),
        logger: { warn },
        env: {},
      }),
    ).resolves.toEqual([]);
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('offline'));
  });
});
