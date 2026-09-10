import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  applyPreviewRect,
  lerp,
  lerpRect,
  resolvePreviewMorphProgress,
} from '../src/lib/preview-orchestrator';

describe('lerp', () => {
  it('interpolates between two numbers', () => {
    expect(lerp(0, 100, 0)).toBe(0);
    expect(lerp(0, 100, 0.5)).toBe(50);
    expect(lerp(0, 100, 1)).toBe(100);
  });
});

describe('lerpRect', () => {
  it('interpolates all rect fields', () => {
    const from = { top: 0, left: 0, width: 200, height: 100 };
    const to = { top: 100, left: 50, width: 400, height: 300 };
    expect(lerpRect(from, to, 0.5)).toEqual({
      top: 50,
      left: 25,
      width: 300,
      height: 200,
    });
  });
});

describe('resolvePreviewMorphProgress', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('returns 0 before the transition window', () => {
    const hero = { offsetTop: 0, offsetHeight: 1000 } as HTMLElement;
    const features = { getBoundingClientRect: () => ({ top: 900 }) } as HTMLElement;
    vi.stubGlobal('window', { scrollY: 100 });
    vi.stubGlobal('getComputedStyle', () => ({ scrollMarginTop: '72px' }));
    expect(resolvePreviewMorphProgress(hero, features, 100)).toBe(0);
  });

  it('returns 1 once features entry is reached', () => {
    const hero = { offsetTop: 0, offsetHeight: 1000 } as HTMLElement;
    const features = { getBoundingClientRect: () => ({ top: -72 }) } as HTMLElement;
    vi.stubGlobal('window', { scrollY: 1000 });
    vi.stubGlobal('getComputedStyle', () => ({ scrollMarginTop: '72px' }));
    expect(resolvePreviewMorphProgress(hero, features, 1000)).toBe(1);
  });
});

describe('applyPreviewRect', () => {
  it('sets fixed positioning from rect', () => {
    const layer = { style: {} as CSSStyleDeclaration } as HTMLElement;
    applyPreviewRect(layer, { top: 10, left: 20, width: 300, height: 200 });
    expect(layer.style.position).toBe('fixed');
    expect(layer.style.top).toBe('10px');
    expect(layer.style.left).toBe('20px');
    expect(layer.style.width).toBe('300px');
    expect(layer.style.height).toBe('200px');
  });
});
