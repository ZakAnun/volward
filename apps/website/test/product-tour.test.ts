import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  APP_WINDOW_ASPECT,
  APP_WINDOW_HEIGHT,
  APP_WINDOW_WIDTH,
  fitTourMockup,
  MIN_TOUR_MOCKUP_MEASURE_PX,
  prefersReducedMotion,
  resolveActiveStep,
  resolveActiveStepByCenter,
  resolveActiveStepFromScroll,
  resolveTourMockupScale,
  TOUR_STEP_ROOT_MARGIN,
} from '../src/lib/product-tour';

describe('APP_WINDOW dimensions', () => {
  it('matches the desktop default window size', () => {
    expect(APP_WINDOW_WIDTH).toBe(1280);
    expect(APP_WINDOW_HEIGHT).toBe(720);
    expect(APP_WINDOW_ASPECT).toBeCloseTo(16 / 9, 5);
  });
});

describe('resolveTourMockupScale', () => {
  it('fits the desktop window into the available stage', () => {
    expect(resolveTourMockupScale(1280, 720)).toBe(1);
    expect(resolveTourMockupScale(640, 720)).toBe(0.5);
    expect(resolveTourMockupScale(1280, 360)).toBe(0.5);
  });

  it('falls back to 1 for invalid stage sizes', () => {
    expect(resolveTourMockupScale(0, 720)).toBe(1);
  });
});

describe('resolveActiveStep', () => {
  it('picks the highest intersection ratio', () => {
    expect(
      resolveActiveStep([
        { id: 'scan', ratio: 0.2 },
        { id: 'browse', ratio: 0.65 },
      ]),
    ).toBe('browse');
  });

  it('falls back to scan when empty', () => {
    expect(resolveActiveStep([])).toBe('scan');
  });

  it('breaks ties by workflow order', () => {
    expect(
      resolveActiveStep([
        { id: 'filter', ratio: 0.5 },
        { id: 'browse', ratio: 0.5 },
      ]),
    ).toBe('browse');
  });
});

describe('resolveActiveStepByCenter', () => {
  it('picks the panel containing the activation line', () => {
    expect(
      resolveActiveStepByCenter(
        [
          { id: 'scan', top: 100, bottom: 400 },
          { id: 'browse', top: 401, bottom: 700 },
        ],
        450,
      ),
    ).toBe('browse');
  });

  it('falls back to the nearest panel center', () => {
    expect(
      resolveActiveStepByCenter(
        [
          { id: 'scan', top: 100, bottom: 300 },
          { id: 'browse', top: 500, bottom: 700 },
        ],
        420,
      ),
    ).toBe('browse');
  });

  it('falls back to scan when no panels exist', () => {
    expect(resolveActiveStepByCenter([], 500)).toBe('scan');
  });

  it('clamps to the first step before the showcase track starts', () => {
    expect(
      resolveActiveStepByCenter(
        [
          { id: 'scan', top: 1000, bottom: 1900 },
          { id: 'browse', top: 1900, bottom: 2800 },
        ],
        900,
      ),
    ).toBe('scan');
  });

  it('clamps to the last step after the showcase track ends', () => {
    expect(
      resolveActiveStepByCenter(
        [
          { id: 'scan', top: 1000, bottom: 1900 },
          { id: 'clean', top: 2800, bottom: 3700 },
        ],
        4000,
      ),
    ).toBe('clean');
  });
});

describe('resolveActiveStepFromScroll', () => {
  it('uses the viewport center as the activation line', () => {
    expect(
      resolveActiveStepFromScroll(
        [
          { id: 'scan', top: 100, bottom: 900 },
          { id: 'browse', top: 900, bottom: 1700 },
        ],
        500,
        1000,
      ),
    ).toBe('browse');
  });
});

describe('TOUR_STEP_ROOT_MARGIN', () => {
  it('targets the middle viewport band for step detection', () => {
    expect(TOUR_STEP_ROOT_MARGIN).toBe('-38% 0px -38% 0px');
  });
});

describe('fitTourMockup', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('skips scale update when layer is too small', () => {
    const viewport = { style: { width: '', height: '' } };
    const root = {
      clientWidth: MIN_TOUR_MOCKUP_MEASURE_PX - 1,
      clientHeight: 400,
      matches: (selector: string) => selector.includes('data-app-preview-layer'),
      getBoundingClientRect: () => ({
        width: MIN_TOUR_MOCKUP_MEASURE_PX - 1,
        height: 400,
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        x: 0,
        y: 0,
        toJSON: () => ({}),
      }),
      style: {
        props: { '--tour-mockup-scale': '0.75' },
        getPropertyValue(name: string) {
          return this.props[name] ?? '';
        },
        setProperty(name: string, value: string) {
          this.props[name] = value;
        },
      },
      querySelector(selector: string) {
        if (selector.includes('tour-mockup-viewport')) {
          return viewport;
        }
        return null;
      },
    } as unknown as HTMLElement;

    vi.stubGlobal('document', { querySelector: () => root });

    fitTourMockup(root);
    expect(root.style.getPropertyValue('--tour-mockup-scale')).toBe('0.75');
    expect(viewport.style.width).toBe('');
  });
});

describe('prefersReducedMotion', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('returns true when matchMedia reports reduce', () => {
    vi.stubGlobal('window', {
      matchMedia: vi.fn().mockReturnValue({ matches: true }),
    });
    expect(prefersReducedMotion()).toBe(true);
  });
});
