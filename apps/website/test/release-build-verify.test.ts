import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

import { isStrictReleaseBuild } from '../src/lib/release-build-options';
import { verifyBuiltReleasePages } from '../src/lib/release-build-verify';
import { DOWNLOAD_ENTRIES } from '../src/lib/site';

describe('isStrictReleaseBuild', () => {
  it('enables strict mode from WEBSITE_REQUIRE_RELEASE', () => {
    expect(isStrictReleaseBuild({ WEBSITE_REQUIRE_RELEASE: '1' })).toBe(true);
    expect(isStrictReleaseBuild({ WEBSITE_REQUIRE_RELEASE: 'true' })).toBe(true);
    expect(isStrictReleaseBuild({})).toBe(false);
  });

  it('prefers explicit strict option over env', () => {
    expect(isStrictReleaseBuild({ WEBSITE_REQUIRE_RELEASE: '1' }, { strict: false })).toBe(false);
    expect(isStrictReleaseBuild({}, { strict: true })).toBe(true);
  });
});

describe('verifyBuiltReleasePages', () => {
  it('passes when both locales include versioned download links', () => {
    const distDir = mkdtempSync(join(tmpdir(), 'volward-website-'));
    const tag = 'v0.0.6';
    const prefix = `https://github.com/ZakAnun/volward/releases/download/${tag}/`;
    const html = `
      <a href="${prefix}volward-latest-macos-arm64.zip">macOS arm64</a>
      <a href="${prefix}volward-latest-macos-x64.zip">macOS x64</a>
      <a href="${prefix}VolwardSetup-latest-windows-x64.exe">Windows</a>
      <a href="${prefix}Volward-latest-linux-x86_64.AppImage">Linux</a>
      <h3>${tag}</h3>
    `;

    mkdirSync(join(distDir, 'zh'), { recursive: true });
    writeFileSync(join(distDir, 'index.html'), html);
    writeFileSync(join(distDir, 'zh/index.html'), html);

    expect(() =>
      verifyBuiltReleasePages({
        distDir,
        expectedTag: tag,
      }),
    ).not.toThrow();
  });

  it('fails when a built page is missing the expected tag', () => {
    const distDir = mkdtempSync(join(tmpdir(), 'volward-website-'));
    mkdirSync(join(distDir, 'zh'), { recursive: true });
    writeFileSync(join(distDir, 'index.html'), '<html>v0.0.5</html>');
    writeFileSync(join(distDir, 'zh/index.html'), '<html>v0.0.5</html>');

    expect(() =>
      verifyBuiltReleasePages({
        distDir,
        expectedTag: 'v0.0.6',
      }),
    ).toThrow(/Expected release tag v0\.0\.6 not found/);
  });

  it('skips verification when no expected tag is provided', () => {
    const distDir = mkdtempSync(join(tmpdir(), 'volward-website-'));

    expect(() =>
      verifyBuiltReleasePages({
        distDir,
      }),
    ).not.toThrow();
  });

  it('fails when a platform download marker is missing', () => {
    const distDir = mkdtempSync(join(tmpdir(), 'volward-website-'));
    const tag = 'v0.0.6';
    const prefix = `https://github.com/ZakAnun/volward/releases/download/${tag}/`;
    const html = `
      <a href="${prefix}volward-latest-macos-arm64.zip">macOS arm64</a>
      <h3>${tag}</h3>
    `;

    mkdirSync(join(distDir, 'zh'), { recursive: true });
    writeFileSync(join(distDir, 'index.html'), html);
    writeFileSync(join(distDir, 'zh/index.html'), html);

    expect(() =>
      verifyBuiltReleasePages({
        distDir,
        expectedTag: tag,
      }),
    ).toThrow(/Missing download link for macos-x64/);
  });

  it('keeps verify_release_build.mjs download file names aligned with site data', () => {
    const script = readFileSync(join(process.cwd(), 'scripts/verify_release_build.mjs'), 'utf8');

    for (const entry of DOWNLOAD_ENTRIES) {
      expect(script).toContain(entry.fileName);
    }
  });
});
