import { describe, expect, it } from 'vitest';
import {
  aptabaseInitOptions,
  completeTrackedNavigation,
  sanitizeAnalyticsProps,
} from '../src/lib/website-analytics';

describe('aptabaseInitOptions', () => {
  it('passes self-hosted Aptabase settings to the official web SDK', () => {
    expect(aptabaseInitOptions('https://analytics.volwardapp.com/', '0.0.3')).toEqual({
      appVersion: '0.0.3',
      host: 'https://analytics.volwardapp.com',
    });
  });
});

describe('sanitizeAnalyticsProps', () => {
  it('keeps only Aptabase-compatible property values', () => {
    expect(
      sanitizeAnalyticsProps({
        text: 'value',
        count: 1,
        enabled: true,
        disabled: false,
        missing: undefined,
        empty: null,
      }),
    ).toEqual({
      text: 'value',
      count: 1,
      enabled: 1,
      disabled: 0,
    });
  });
});

describe('completeTrackedNavigation', () => {
  it('waits for analytics before continuing navigation', async () => {
    const calls: string[] = [];
    let finishTracking: () => void = () => undefined;
    const tracking = new Promise<void>((resolve) => {
      finishTracking = resolve;
    });

    const completion = completeTrackedNavigation(
      () => {
        calls.push('track');
        return tracking;
      },
      () => calls.push('navigate'),
      1_000,
    );

    await Promise.resolve();
    expect(calls).toEqual(['track']);

    finishTracking();
    await completion;
    expect(calls).toEqual(['track', 'navigate']);
  });
});
