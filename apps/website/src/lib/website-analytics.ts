import { init, trackEvent, type AptabaseOptions } from '@aptabase/web';

type AnalyticsProps = Record<string, string | number | boolean | null | undefined>;

type AnalyticsNavigator = {
  language?: string;
};

const SOURCE = 'website';
const TRACKED_NAVIGATION_TIMEOUT_MS = 300;

let analyticsEnabled = false;

function logDevAnalyticsStatus(message: string, detail: Record<string, string | number | boolean> = {}): void {
  if (import.meta.env.DEV) {
    console.info(`[website analytics] ${message}`, detail);
  }
}

function warnDevAnalyticsStatus(message: string): void {
  if (import.meta.env.DEV) {
    console.warn(`[website analytics] ${message}`);
  }
}

function trimTrailingSlash(value: string): string {
  return value.replace(/\/+$/, '');
}

function currentPath(): string {
  return `${window.location.pathname}${window.location.search}`;
}

function referrerHost(): string {
  if (!document.referrer) {
    return '';
  }

  try {
    return new URL(document.referrer).hostname;
  } catch {
    return '';
  }
}

export function sanitizeAnalyticsProps(props: AnalyticsProps): Record<string, string | number> {
  return Object.fromEntries(
    Object.entries(props)
      .map(([key, value]) => {
        if (typeof value === 'string' || typeof value === 'number') {
          return [key, value] as const;
        }

        if (typeof value === 'boolean') {
          return [key, value ? 1 : 0] as const;
        }

        return undefined;
      })
      .filter((entry): entry is readonly [string, string | number] => Boolean(entry)),
  );
}

export function aptabaseInitOptions(host: string, appVersion: string): AptabaseOptions {
  return {
    appVersion,
    host: trimTrailingSlash(host),
  };
}

export function websiteEventProps(props: AnalyticsProps = {}): Record<string, string | number> {
  return sanitizeAnalyticsProps({
    source: SOURCE,
    locale: document.documentElement.lang || (navigator as AnalyticsNavigator).language || 'unknown',
    path: currentPath(),
    ...props,
  });
}

export async function trackWebsiteEvent(eventName: string, props: AnalyticsProps = {}): Promise<void> {
  if (!analyticsEnabled) {
    return;
  }

  await trackEvent(eventName, websiteEventProps(props));
}

export async function completeTrackedNavigation(
  track: () => Promise<void>,
  navigate: () => void,
  timeoutMs = TRACKED_NAVIGATION_TIMEOUT_MS,
): Promise<void> {
  let timeoutId: ReturnType<typeof setTimeout> | undefined;

  try {
    await Promise.race([
      track().catch(() => undefined),
      new Promise<void>((resolve) => {
        timeoutId = setTimeout(resolve, timeoutMs);
      }),
    ]);
  } finally {
    if (timeoutId !== undefined) {
      clearTimeout(timeoutId);
    }

    navigate();
  }
}

function shouldDelayTrackedNavigation(event: MouseEvent, target: HTMLAnchorElement): boolean {
  return (
    event.button === 0 &&
    !event.metaKey &&
    !event.ctrlKey &&
    !event.shiftKey &&
    !event.altKey &&
    target.target !== '_blank'
  );
}

function trackNavigationClick(
  event: MouseEvent,
  target: HTMLAnchorElement,
  eventName: string,
  props: AnalyticsProps,
): void {
  const track = () => trackWebsiteEvent(eventName, props);

  if (!shouldDelayTrackedNavigation(event, target)) {
    void track();
    return;
  }

  event.preventDefault();
  void completeTrackedNavigation(track, () => window.location.assign(target.href));
}

function initAptabase(appKey: string, host: string, appVersion: string): void {
  init(appKey, aptabaseInitOptions(host, appVersion));
}

function trackPageView(): void {
  void trackWebsiteEvent('website_page_view', {
    referrer: referrerHost(),
  });
}

export function initWebsiteAnalytics(): void {
  const appKey = __APTABASE_WEB_KEY__.trim();

  if (!appKey) {
    warnDevAnalyticsStatus('APTABASE_WEB_KEY is empty; tracking is disabled. Restart the dev server after exporting it.');
    return;
  }

  const host = __APTABASE_HOST__ || 'https://analytics.volwardapp.com';
  const appVersion = __VOLWARD_WEBSITE_VERSION__ || '0.0.0';

  initAptabase(
    appKey,
    host,
    appVersion,
  );
  analyticsEnabled = true;
  logDevAnalyticsStatus('Aptabase SDK initialized', {
    appKeyPrefix: appKey.split('-').slice(0, 2).join('-'),
    host,
    appVersion,
  });

  trackPageView();
  bindClickTracking();
}

function bindClickTracking(): void {
  document.addEventListener('click', (event) => {
    const target = event.target instanceof Element ? event.target.closest<HTMLAnchorElement>('a') : null;

    if (!target) {
      return;
    }

    if (target.dataset.downloadRow !== undefined) {
      trackNavigationClick(event, target, 'website_download_click', {
        platform: target.dataset.downloadPlatform,
        href: target.href,
      });
      return;
    }

    if (target.dataset.releaseLogLink !== undefined) {
      trackNavigationClick(event, target, 'website_release_click', {
        release: target.dataset.releaseTitle,
        href: target.href,
      });
      return;
    }

    if (target.dataset.localeSwitch !== undefined) {
      trackNavigationClick(event, target, 'website_language_switch', {
        href: target.href,
      });
      return;
    }

    const href = target.getAttribute('href') ?? '';

    if (href === '#features' || href === '#download') {
      void trackWebsiteEvent('website_nav_click', {
        target: href.slice(1),
      });
    }
  });
}
