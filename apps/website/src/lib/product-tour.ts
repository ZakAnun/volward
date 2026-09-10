import type { WorkflowStepId } from './site';

/** Default Volward desktop window (see windows/runner/main.cpp, linux/my_application.cc). */
export const APP_WINDOW_WIDTH = 1280;
export const APP_WINDOW_HEIGHT = 720;
export const APP_WINDOW_ASPECT = APP_WINDOW_WIDTH / APP_WINDOW_HEIGHT;

export function resolveTourMockupScale(
  stageWidth: number,
  stageHeight: number,
  windowWidth = APP_WINDOW_WIDTH,
  windowHeight = APP_WINDOW_HEIGHT,
): number {
  if (stageWidth <= 0 || stageHeight <= 0 || windowWidth <= 0 || windowHeight <= 0) {
    return 1;
  }

  return Math.min(stageWidth / windowWidth, stageHeight / windowHeight);
}

export const MIN_TOUR_MOCKUP_MEASURE_PX = 120;

export function resolveTourMockupRoot(root: HTMLElement): HTMLElement {
  return (
    document.querySelector<HTMLElement>('[data-app-preview-layer]') ??
    root.querySelector<HTMLElement>('[data-tour-mockup]') ??
    root
  );
}

export function fitTourMockup(root: HTMLElement): void {
  const mockupRoot = resolveTourMockupRoot(root);
  const viewport = mockupRoot.querySelector<HTMLElement>('[data-tour-mockup-viewport]');
  if (!viewport) {
    return;
  }

  const measureTarget = mockupRoot.matches('[data-app-preview-layer]')
    ? mockupRoot
    : (mockupRoot.querySelector<HTMLElement>('[data-app-preview-layer]') ?? mockupRoot);

  const width = measureTarget.clientWidth || measureTarget.getBoundingClientRect().width;
  const height = measureTarget.clientHeight || measureTarget.getBoundingClientRect().height;
  if (width < MIN_TOUR_MOCKUP_MEASURE_PX || height < MIN_TOUR_MOCKUP_MEASURE_PX) {
    return;
  }

  const scale = resolveTourMockupScale(width, height);
  const displayWidth = APP_WINDOW_WIDTH * scale;
  const displayHeight = APP_WINDOW_HEIGHT * scale;

  mockupRoot.style.setProperty('--tour-mockup-scale', scale.toFixed(4));
  viewport.style.width = `${displayWidth}px`;
  viewport.style.height = `${displayHeight}px`;
}

export const WORKFLOW_STEP_IDS: readonly WorkflowStepId[] = ['scan', 'browse', 'filter', 'clean'];

const STEP_ORDER: Record<WorkflowStepId, number> = {
  scan: 0,
  browse: 1,
  filter: 2,
  clean: 3,
};

export type StepPanelBounds = {
  id: WorkflowStepId;
  top: number;
  bottom: number;
};

export function resolveActiveStep(
  entries: Array<{ id: WorkflowStepId; ratio: number }>,
): WorkflowStepId {
  if (entries.length === 0) {
    return 'scan';
  }

  const sorted = [...entries].sort((a, b) => {
    if (b.ratio !== a.ratio) {
      return b.ratio - a.ratio;
    }
    return STEP_ORDER[a.id] - STEP_ORDER[b.id];
  });

  return sorted[0]?.ratio > 0 ? sorted[0].id : 'scan';
}

export function resolveActiveStepByCenter(
  panels: StepPanelBounds[],
  activationY: number,
): WorkflowStepId {
  if (panels.length === 0) {
    return 'scan';
  }

  const sorted = [...panels].sort((a, b) => STEP_ORDER[a.id] - STEP_ORDER[b.id]);
  const first = sorted[0];
  const last = sorted[sorted.length - 1];

  if (!first || !last) {
    return 'scan';
  }

  if (activationY <= first.top) {
    return first.id;
  }

  if (activationY >= last.bottom) {
    return last.id;
  }

  const containing = sorted.find(
    (panel) => activationY >= panel.top && activationY < panel.bottom,
  );
  if (containing) {
    return containing.id;
  }

  let best: WorkflowStepId = first.id;
  let bestDistance = Infinity;

  for (const panel of sorted) {
    const center = (panel.top + panel.bottom) / 2;
    const distance = Math.abs(activationY - center);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = panel.id;
    } else if (distance === bestDistance && STEP_ORDER[panel.id] < STEP_ORDER[best]) {
      best = panel.id;
    }
  }

  return best;
}

export function measureTourPanelBounds(
  showcase: HTMLElement,
  scrollY = typeof window !== 'undefined' ? window.scrollY : 0,
): StepPanelBounds[] {
  return Array.from(showcase.querySelectorAll<HTMLElement>('[data-tour-panel]')).map(
    (panel) => {
      const rect = panel.getBoundingClientRect();
      return {
        id: panel.dataset.tourPanel as WorkflowStepId,
        top: rect.top + scrollY,
        bottom: rect.bottom + scrollY,
      };
    },
  );
}

export function resolveActiveStepFromScroll(
  panels: StepPanelBounds[],
  scrollY: number,
  viewportHeight: number,
): WorkflowStepId {
  return resolveActiveStepByCenter(panels, scrollY + viewportHeight * 0.5);
}

export function prefersReducedMotion(): boolean {
  return (
    typeof window !== 'undefined' &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches
  );
}

export function readPreviewMorphProgress(): number {
  const raw = getComputedStyle(document.documentElement)
    .getPropertyValue('--preview-morph-progress')
    .trim();
  const parsed = Number.parseFloat(raw);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function readTourCssVar(root: HTMLElement, name: string, fallback: number): number {
  const raw = getComputedStyle(root).getPropertyValue(name).trim();
  const parsed = Number.parseFloat(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

/** Scroll so the step panel center aligns with the viewport center. */
export function computeScrollTopForStep(_root: HTMLElement, step: WorkflowStepId): number {
  const panel = document.getElementById(`tour-${step}`);
  if (!panel) {
    return 0;
  }

  const rect = panel.getBoundingClientRect();
  const panelCenter = rect.top + window.scrollY + rect.height / 2;
  return panelCenter - window.innerHeight / 2;
}

export function applyActiveStep(
  root: HTMLElement,
  step: WorkflowStepId,
  reducedMotion: boolean,
): void {
  root.dataset.activeStep = step;

  const mockup =
    root.querySelector<HTMLElement>('[data-tour-mockup]') ??
    document.querySelector<HTMLElement>('[data-tour-mockup]');
  if (mockup) {
    mockup.dataset.activeStep = step;
    if (!reducedMotion) {
      mockup.classList.add('is-transitioning');
      window.setTimeout(() => mockup.classList.remove('is-transitioning'), 280);
    }
  }

  root.querySelectorAll<HTMLElement>('[data-tour-progress]').forEach((item) => {
    const isActive = item.dataset.tourProgress === step;
    item.classList.toggle('is-active', isActive);
    item.setAttribute('aria-current', isActive ? 'step' : 'false');
  });

  root.querySelectorAll<HTMLElement>('[data-tour-mobile-caption]').forEach((panel) => {
    const isActive = panel.dataset.tourMobileCaption === step;
    panel.classList.toggle('is-active', isActive);
    panel.dataset.active = isActive ? 'true' : 'false';
  });
}

export type ProductTourOptions = {
  root: HTMLElement;
  onStepView?: (step: WorkflowStepId) => void;
};

/** Legacy IO margin — kept for tests; scroll sync is primary in initProductTour. */
export const TOUR_STEP_ROOT_MARGIN = '-38% 0px -38% 0px';

export function scrollToTourStep(
  root: HTMLElement,
  step: WorkflowStepId,
  reducedMotion: boolean,
): void {
  const top = computeScrollTopForStep(root, step);
  window.scrollTo({
    top,
    behavior: reducedMotion ? 'auto' : 'smooth',
  });
}

export function initProductTour({ root, onStepView }: ProductTourOptions): () => void {
  const reducedMotion = prefersReducedMotion();
  const viewed = new Set<WorkflowStepId>();
  const showcase = root.querySelector<HTMLElement>('[data-tour-showcase]');
  let lastStep: WorkflowStepId | null = null;
  let ticking = false;

  const sync = () => {
    ticking = false;
    if (!showcase) {
      return;
    }

    const showcaseRect = showcase.getBoundingClientRect();
    if (showcaseRect.bottom <= 0 || showcaseRect.top >= window.innerHeight) {
      return;
    }

    const morphProgress = readPreviewMorphProgress();
    const step =
      morphProgress < 0.999
        ? 'scan'
        : resolveActiveStepFromScroll(
            measureTourPanelBounds(showcase),
            window.scrollY,
            window.innerHeight,
          );

    if (step === lastStep) {
      return;
    }

    lastStep = step;
    applyActiveStep(root, step, reducedMotion);

    if (!viewed.has(step)) {
      viewed.add(step);
      onStepView?.(step);
    }
  };

  const requestSync = () => {
    if (ticking) {
      return;
    }
    ticking = true;
    window.requestAnimationFrame(sync);
  };

  const requestFit = () => {
    fitTourMockup(root);
  };

  const fitTarget =
    document.querySelector<HTMLElement>('[data-app-preview-layer]') ??
    root.querySelector<HTMLElement>('.product-showcase-stage');
  const resizeObserver =
    typeof ResizeObserver !== 'undefined' && fitTarget
      ? new ResizeObserver(requestFit)
      : null;
  resizeObserver?.observe(fitTarget);

  const onWindowResize = () => {
    requestFit();
    requestSync();
  };

  window.addEventListener('scroll', requestSync, { passive: true });
  window.addEventListener('resize', onWindowResize, { passive: true });
  requestFit();
  requestSync();

  const onNavClick = (event: Event) => {
    const target = (event.target as Element).closest<HTMLAnchorElement>('[data-tour-progress-link]');
    if (!target || !root.contains(target)) {
      return;
    }

    event.preventDefault();
    const step = target.dataset.tourProgressLink as WorkflowStepId | undefined;
    if (!step) {
      return;
    }

    scrollToTourStep(root, step, reducedMotion);
    lastStep = null;
    requestSync();
    if (!viewed.has(step)) {
      viewed.add(step);
      onStepView?.(step);
    }
  };

  root.addEventListener('click', onNavClick);

  return () => {
    resizeObserver?.disconnect();
    window.removeEventListener('scroll', requestSync);
    window.removeEventListener('resize', onWindowResize);
    root.removeEventListener('click', onNavClick);
  };
}
