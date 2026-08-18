import type { DownloadAsset } from './site';

export type DownloadTargetId = DownloadAsset['id'];

export type DownloadLinkOption = Pick<DownloadAsset, 'id' | 'href'>;

type InitializeDownloadTargetsOptions<T> = {
  detectTarget: () => Promise<DownloadTargetId | undefined>;
  refreshOptions: () => Promise<T[]>;
  updateOptions: (options: T[]) => void;
  applyTarget: (targetId: DownloadTargetId | undefined) => void;
};

export type BrowserDownloadPlatformInfo = {
  userAgentDataPlatform?: string;
  platform?: string;
  userAgent?: string;
  architecture?: string;
};

const X64_ARCHITECTURES = new Set(['x64', 'x86', 'x86_64', 'amd64', 'ia32', 'intel']);
const ARM64_ARCHITECTURES = new Set(['arm', 'arm64', 'aarch64']);

function normalize(value: string | undefined): string {
  return value?.trim().toLowerCase() ?? '';
}

function normalizeArchitecture(value: string | undefined): string {
  return normalize(value).replace(/[\s-]/g, '_');
}

function hasAnyPlatformSignal(info: BrowserDownloadPlatformInfo, values: string[]): boolean {
  const signals = [info.userAgentDataPlatform, info.platform, info.userAgent].map(normalize);
  return signals.some((signal) => values.some((value) => signal.includes(value)));
}

function isX64Architecture(architecture: string): boolean {
  return X64_ARCHITECTURES.has(architecture);
}

function isArm64Architecture(architecture: string): boolean {
  return ARM64_ARCHITECTURES.has(architecture);
}

export function detectDownloadTargetId(info: BrowserDownloadPlatformInfo): DownloadTargetId | undefined {
  const architecture = normalizeArchitecture(info.architecture);

  if (hasAnyPlatformSignal(info, ['macos', 'mac os', 'macintel', 'macintosh'])) {
    if (isArm64Architecture(architecture)) {
      return 'macos-arm64';
    }

    if (isX64Architecture(architecture)) {
      return 'macos-x64';
    }

    return undefined;
  }

  if (hasAnyPlatformSignal(info, ['windows', 'win32', 'win64', 'wow64'])) {
    return architecture && !isX64Architecture(architecture) ? undefined : 'windows-x64';
  }

  if (hasAnyPlatformSignal(info, ['linux', 'x11'])) {
    return architecture && !isX64Architecture(architecture) ? undefined : 'linux-appimage';
  }

  return undefined;
}

export function resolveDownloadHref(
  options: DownloadLinkOption[],
  targetId: DownloadTargetId | undefined,
  fallbackHref: string,
): string {
  if (!targetId) {
    return fallbackHref;
  }

  return options.find((option) => option.id === targetId)?.href ?? fallbackHref;
}

export async function initializeDownloadTargets<T>(options: InitializeDownloadTargetsOptions<T>): Promise<void> {
  const targetIdPromise = options.detectTarget().catch(() => undefined);
  const refreshedOptionsPromise = options.refreshOptions().catch(() => []);
  const initialApplyPromise = targetIdPromise.then(options.applyTarget);
  const refreshedOptions = await refreshedOptionsPromise;

  await initialApplyPromise;
  options.updateOptions(refreshedOptions);
  options.applyTarget(await targetIdPromise);
}
