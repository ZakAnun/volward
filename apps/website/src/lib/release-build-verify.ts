import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { DOWNLOAD_ENTRIES } from './site';

const BUILT_PAGES = ['index.html', 'zh/index.html'] as const;

export type VerifyBuiltReleasePagesOptions = {
  distDir: string;
  expectedTag?: string;
};

export function verifyBuiltReleasePages(options: VerifyBuiltReleasePagesOptions): void {
  const expectedTag = options.expectedTag?.trim();

  if (!expectedTag) {
    return;
  }

  for (const relativePath of BUILT_PAGES) {
    const pagePath = join(options.distDir, relativePath);
    let html: string;

    try {
      html = readFileSync(pagePath, 'utf8');
    } catch {
      throw new Error(`Built page missing: ${relativePath}`);
    }

    if (!html.includes(expectedTag)) {
      throw new Error(`Expected release tag ${expectedTag} not found in ${relativePath}`);
    }

    const downloadPrefix = `releases/download/${expectedTag}/`;
    if (!html.includes(downloadPrefix)) {
      throw new Error(`Expected versioned download links for ${expectedTag} not found in ${relativePath}`);
    }

    for (const entry of DOWNLOAD_ENTRIES) {
      const marker = `${downloadPrefix}${entry.fileName}`;
      if (!html.includes(marker)) {
        throw new Error(`Missing download link for ${entry.id} (${entry.fileName}) in ${relativePath}`);
      }
    }
  }
}
