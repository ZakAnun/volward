#!/usr/bin/env node

// Keep DOWNLOAD_FILE_NAMES in sync with DOWNLOAD_ENTRIES in src/lib/site.ts.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const BUILT_PAGES = ['index.html', 'zh/index.html'];
const DOWNLOAD_FILE_NAMES = [
  'volward-latest-macos-arm64.zip',
  'volward-latest-macos-x64.zip',
  'VolwardSetup-latest-windows-x64.exe',
  'Volward-latest-linux-x86_64.AppImage',
];

function verifyBuiltReleasePages({ distDir, expectedTag }) {
  const tag = expectedTag?.trim();

  if (!tag) {
    return;
  }

  for (const relativePath of BUILT_PAGES) {
    const pagePath = join(distDir, relativePath);
    let html;

    try {
      html = readFileSync(pagePath, 'utf8');
    } catch {
      throw new Error(`Built page missing: ${relativePath}`);
    }

    if (!html.includes(tag)) {
      throw new Error(`Expected release tag ${tag} not found in ${relativePath}`);
    }

    const downloadPrefix = `releases/download/${tag}/`;
    if (!html.includes(downloadPrefix)) {
      throw new Error(`Expected versioned download links for ${tag} not found in ${relativePath}`);
    }

    for (const fileName of DOWNLOAD_FILE_NAMES) {
      const marker = `${downloadPrefix}${fileName}`;
      if (!html.includes(marker)) {
        throw new Error(`Missing download link for ${fileName} in ${relativePath}`);
      }
    }
  }
}

const distDir = process.argv[2];
const expectedTag = process.argv[3]?.trim() || process.env.EXPECTED_RELEASE_TAG?.trim();

if (!distDir) {
  console.error('Usage: node scripts/verify_release_build.mjs <dist-dir> [expected-tag]');
  process.exit(1);
}

try {
  verifyBuiltReleasePages({ distDir, expectedTag });
  if (expectedTag) {
    console.log(`✅ Verified release ${expectedTag} in built pages`);
  }
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`❌ Release build verification failed: ${message}`);
  process.exit(1);
}
