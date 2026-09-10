import { resolveFeaturesScrollTop } from './hero-scroll';
import { fitTourMockup } from './product-tour';

export type PreviewRect = {
  top: number;
  left: number;
  width: number;
  height: number;
};

export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

export function lerpRect(from: PreviewRect, to: PreviewRect, t: number): PreviewRect {
  return {
    top: lerp(from.top, to.top, t),
    left: lerp(from.left, to.left, t),
    width: lerp(from.width, to.width, t),
    height: lerp(from.height, to.height, t),
  };
}

export function readSlotRect(el: HTMLElement): PreviewRect {
  const rect = el.getBoundingClientRect();
  return {
    top: rect.top,
    left: rect.left,
    width: rect.width,
    height: rect.height,
  };
}

export function resolvePreviewMorphProgress(
  hero: HTMLElement,
  features: HTMLElement,
  scrollY: number,
): number {
  const transitionStart = hero.offsetTop + hero.offsetHeight * 0.36;
  const transitionEnd = resolveFeaturesScrollTop(features);

  if (transitionEnd <= transitionStart) {
    return scrollY >= transitionEnd ? 1 : 0;
  }

  const raw = (scrollY - transitionStart) / (transitionEnd - transitionStart);
  return Math.min(1, Math.max(0, raw));
}

export function applyPreviewRect(layer: HTMLElement, rect: PreviewRect): void {
  layer.style.position = 'fixed';
  layer.style.top = `${rect.top}px`;
  layer.style.left = `${rect.left}px`;
  layer.style.width = `${rect.width}px`;
  layer.style.height = `${rect.height}px`;
  layer.style.transform = 'none';
}

export type PreviewOrchestratorOptions = {
  hero: HTMLElement;
  features: HTMLElement;
  layer: HTMLElement;
  tourRoot: HTMLElement;
  reducedMotion?: boolean;
};

export function initPreviewOrchestrator({
  hero,
  features,
  layer,
  tourRoot,
  reducedMotion = false,
}: PreviewOrchestratorOptions): () => void {
  const heroSlot = hero.querySelector<HTMLElement>('[data-preview-slot="hero"]');
  const featureSlot =
    features.querySelector<HTMLElement>('.product-showcase-stage') ??
    features.querySelector<HTMLElement>('[data-preview-slot="feature"]');
  if (!heroSlot || !featureSlot) {
    return () => {};
  }

  let ticking = false;

  const sync = () => {
    ticking = false;
    const progress = reducedMotion
      ? window.scrollY >= resolveFeaturesScrollTop(features)
        ? 1
        : 0
      : resolvePreviewMorphProgress(hero, features, window.scrollY);

    document.documentElement.style.setProperty('--preview-morph-progress', progress.toFixed(4));

    const heroRect = readSlotRect(heroSlot);
    const featureRect = readSlotRect(featureSlot);
    const rect = reducedMotion
      ? progress >= 1
        ? featureRect
        : heroRect
      : lerpRect(heroRect, featureRect, progress);

    applyPreviewRect(layer, rect);
    layer.classList.toggle('is-docked', progress >= 0.999);
    layer.style.pointerEvents = progress >= 0.999 ? 'auto' : 'none';

    fitTourMockup(layer);
  };

  const requestSync = () => {
    if (ticking) {
      return;
    }
    ticking = true;
    requestAnimationFrame(sync);
  };

  const resizeObserver =
    typeof ResizeObserver !== 'undefined' ? new ResizeObserver(requestSync) : null;
  resizeObserver?.observe(heroSlot);
  resizeObserver?.observe(featureSlot);

  window.addEventListener('scroll', requestSync, { passive: true });
  window.addEventListener('resize', requestSync, { passive: true });
  requestSync();

  return () => {
    resizeObserver?.disconnect();
    window.removeEventListener('scroll', requestSync);
    window.removeEventListener('resize', requestSync);
    document.documentElement.style.removeProperty('--preview-morph-progress');
  };
}
