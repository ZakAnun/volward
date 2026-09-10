const HEADER_OFFSET = 72;
const FEATURES_SCROLL_DURATION_MS = 760;

export function easeInOutCubic(t: number): number {
  return t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2;
}

export function easeOutCubic(t: number): number {
  return 1 - (1 - t) ** 3;
}

function scrollInstant(top: number): void {
  window.scrollTo({ top, left: 0, behavior: 'instant' });
}

export function resolveFeaturesScrollTop(featuresEl: HTMLElement): number {
  const top = featuresEl.getBoundingClientRect().top + window.scrollY;
  const margin = Number.parseFloat(getComputedStyle(featuresEl).scrollMarginTop) || HEADER_OFFSET;
  return Math.max(0, top - margin);
}

export type AnimateScrollOptions = {
  duration?: number;
  reducedMotion?: boolean;
  easing?: 'easeOut' | 'easeInOut';
};

export function animateScrollTo(
  targetTop: number,
  {
    duration = FEATURES_SCROLL_DURATION_MS,
    reducedMotion = false,
    easing = 'easeOut',
  }: AnimateScrollOptions = {},
): Promise<void> {
  if (typeof window === 'undefined') {
    return Promise.resolve();
  }

  const maxTop = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
  const clampedTarget = Math.min(Math.max(0, targetTop), maxTop);
  const startTop = window.scrollY;
  const distance = clampedTarget - startTop;

  if (reducedMotion || Math.abs(distance) < 2) {
    scrollInstant(clampedTarget);
    return Promise.resolve();
  }

  const ease = easing === 'easeInOut' ? easeInOutCubic : easeOutCubic;
  const root = document.documentElement;
  const previousScrollBehavior = root.style.scrollBehavior;
  root.style.scrollBehavior = 'auto';

  const startTime = performance.now();

  return new Promise((resolve) => {
    const finish = () => {
      scrollInstant(clampedTarget);
      root.style.scrollBehavior = previousScrollBehavior;
      resolve();
    };

    const tick = (now: number) => {
      const progress = Math.min((now - startTime) / duration, 1);
      scrollInstant(startTop + distance * ease(progress));
      if (progress < 1) {
        requestAnimationFrame(tick);
      } else {
        finish();
      }
    };

    tick(startTime);
  });
}

export type HeroScrollBridgeOptions = {
  hero: HTMLElement;
  features: HTMLElement;
  reducedMotion?: boolean;
};

export function syncPastHeroState(hero: HTMLElement, headerOffset = HEADER_OFFSET): void {
  const heroRect = hero.getBoundingClientRect();
  document.body.classList.toggle('is-past-hero', heroRect.bottom <= headerOffset + 2);
}

export function initHeroScrollBridge({
  hero,
  features,
  reducedMotion = false,
}: HeroScrollBridgeOptions): () => void {
  let locked = true;
  let bridging = false;

  const unlockIfAtTop = () => {
    syncPastHeroState(hero);
    if (window.scrollY <= 8) {
      locked = true;
      bridging = false;
    }
  };

  const bridgeToFeatures = () => {
    if (bridging) {
      return;
    }
    bridging = true;
    locked = false;
    void animateScrollTo(resolveFeaturesScrollTop(features), { reducedMotion }).finally(() => {
      bridging = false;
    });
  };

  const onWheel = (event: WheelEvent) => {
    if (!locked || bridging || event.deltaY <= 0) {
      return;
    }

    const heroRect = hero.getBoundingClientRect();
    if (heroRect.bottom <= HEADER_OFFSET + 4) {
      locked = false;
      return;
    }

    event.preventDefault();
    bridgeToFeatures();
  };

  const onKeyDown = (event: KeyboardEvent) => {
    if (!locked || bridging) {
      return;
    }

    if (!['ArrowDown', 'PageDown', ' '].includes(event.key)) {
      return;
    }

    const heroRect = hero.getBoundingClientRect();
    if (heroRect.bottom <= HEADER_OFFSET + 4) {
      locked = false;
      return;
    }

    event.preventDefault();
    bridgeToFeatures();
  };

  let touchStartY = 0;

  const onTouchStart = (event: TouchEvent) => {
    touchStartY = event.touches[0]?.clientY ?? 0;
  };

  const onTouchMove = (event: TouchEvent) => {
    if (!locked || bridging) {
      return;
    }

    const touchY = event.touches[0]?.clientY ?? touchStartY;
    const delta = touchStartY - touchY;
    if (delta <= 12) {
      return;
    }

    const heroRect = hero.getBoundingClientRect();
    if (heroRect.bottom <= HEADER_OFFSET + 4) {
      locked = false;
      return;
    }

    event.preventDefault();
    bridgeToFeatures();
  };

  const onResize = () => syncPastHeroState(hero);

  syncPastHeroState(hero);

  window.addEventListener('wheel', onWheel, { passive: false });
  window.addEventListener('keydown', onKeyDown);
  window.addEventListener('scroll', unlockIfAtTop, { passive: true });
  window.addEventListener('resize', onResize, { passive: true });
  hero.addEventListener('touchstart', onTouchStart, { passive: true });
  hero.addEventListener('touchmove', onTouchMove, { passive: false });

  return () => {
    window.removeEventListener('wheel', onWheel);
    window.removeEventListener('keydown', onKeyDown);
    window.removeEventListener('scroll', unlockIfAtTop);
    window.removeEventListener('resize', onResize);
    hero.removeEventListener('touchstart', onTouchStart);
    hero.removeEventListener('touchmove', onTouchMove);
    document.body.classList.remove('is-past-hero');
  };
}
