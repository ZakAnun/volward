import { describe, expect, it } from 'vitest';
import { DOWNLOADS, GITHUB_RELEASES_URL, PAGE_COPY } from '../src/lib/site';

describe('site data', () => {
  it('supplies all-releases fallback download data', () => {
    expect(DOWNLOADS.en.map((item) => item.fileName)).toEqual([
      'volward-latest-macos-arm64.zip',
      'volward-latest-macos-x64.zip',
      'VolwardSetup-latest-windows-x64.exe',
      'Volward-latest-linux-x86_64.AppImage',
    ]);
    expect(DOWNLOADS.en.map((item) => item.href)).toEqual(Array(4).fill(GITHUB_RELEASES_URL));
  });

  it('keeps the EN and ZH copy keys aligned', () => {
    expect(Object.keys(PAGE_COPY.en)).toEqual(Object.keys(PAGE_COPY.zh));
  });

  it('supplies a localized Chinese platform accessible name', () => {
    expect(PAGE_COPY.zh.downloadPlatformAriaLabel).toBe('适用于 {platform} 的 Volward');
  });
});

const WORKFLOW_STEP_IDS = ['scan', 'browse', 'filter', 'clean'] as const;

describe('product tour copy', () => {
  it('defines four workflow steps in order for EN and ZH', () => {
    for (const locale of ['en', 'zh'] as const) {
      const steps = PAGE_COPY[locale].productTour.steps;
      expect(steps.map((s) => s.id)).toEqual(WORKFLOW_STEP_IDS);
    }
  });

  it('keeps productTour keys aligned between locales', () => {
    expect(Object.keys(PAGE_COPY.en.productTour)).toEqual(Object.keys(PAGE_COPY.zh.productTour));
  });

  it('includes mockupLabels required by filter and clean states', () => {
    for (const locale of ['en', 'zh'] as const) {
      const labels = PAGE_COPY[locale].productTour.mockupLabels;
      expect(labels.filterAll).toBeTruthy();
      expect(labels.stickyBrowseResults).toBeTruthy();
      expect(labels.scanActionRescan).toBeTruthy();
      expect(labels.moveToTrash).toBeTruthy();
      expect(labels.scanning).toBeTruthy();
      expect(labels.navSubtitle).toBeTruthy();
      expect(labels.resultsSummary).toBeTruthy();
      expect(labels.stickySelected).toBeTruthy();
      expect(labels.trashActionEmpty).toBeTruthy();
    }
  });

  it('includes shortName and hook for each workflow step', () => {
    for (const locale of ['en', 'zh'] as const) {
      for (const step of PAGE_COPY[locale].productTour.steps) {
        expect(step.shortName).toBeTruthy();
        expect(step.title || step.hook).toBeTruthy();
        if (step.hook) {
          expect(step.hook.length).toBeLessThan(80);
        }
        if (step.title) {
          expect(step.title.length).toBeLessThan(80);
        }
      }
    }
  });
});
