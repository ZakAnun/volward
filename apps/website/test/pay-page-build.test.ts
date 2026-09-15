import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const requireDist = process.env.WEBSITE_REQUIRE_RELEASE === '1';

describe('pay page build output', () => {
  it('includes pay route HTML when dist exists', () => {
    const payHtml = join(process.cwd(), 'dist/pay/index.html');
    if (!existsSync(payHtml)) {
      expect(requireDist, 'dist/pay/index.html missing after build').toBe(false);
      return;
    }
    const html = readFileSync(payHtml, 'utf8');
    expect(html).toContain('data-paddle-shell');
    expect(html).toContain('paddle.js');
  });
});
