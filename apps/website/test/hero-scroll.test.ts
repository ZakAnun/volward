import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  animateScrollTo,
  easeInOutCubic,
  easeOutCubic,
  resolveFeaturesScrollTop,
} from '../src/lib/hero-scroll';

describe('easeInOutCubic', () => {
  it('starts at 0 and ends at 1', () => {
    expect(easeInOutCubic(0)).toBe(0);
    expect(easeInOutCubic(1)).toBe(1);
  });

  it('eases through the midpoint', () => {
    expect(easeInOutCubic(0.5)).toBe(0.5);
  });
});

describe('easeOutCubic', () => {
  it('starts at 0 and ends at 1', () => {
    expect(easeOutCubic(0)).toBe(0);
    expect(easeOutCubic(1)).toBe(1);
  });

  it('moves faster at the start than ease-in-out', () => {
    expect(easeOutCubic(0.2)).toBeGreaterThan(easeInOutCubic(0.2));
  });
});

describe('animateScrollTo', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('jumps immediately when reduced motion is enabled', async () => {
    const scrollTo = vi.fn();
    vi.stubGlobal('window', {
      scrollY: 0,
      innerHeight: 800,
      scrollTo,
    });
    vi.stubGlobal('document', {
      documentElement: { scrollHeight: 3000, style: {} },
    });

    await animateScrollTo(640, { reducedMotion: true });

    expect(scrollTo).toHaveBeenCalledWith({ top: 640, left: 0, behavior: 'instant' });
  });
});

describe('resolveFeaturesScrollTop', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('subtracts scroll margin from the element document top', () => {
    const el = {
      getBoundingClientRect: () => ({ top: 900 }),
    } as unknown as HTMLElement;

    vi.stubGlobal('window', { scrollY: 100 });
    vi.stubGlobal('getComputedStyle', () => ({ scrollMarginTop: '72px' }));

    expect(resolveFeaturesScrollTop(el)).toBe(928);
  });
});
