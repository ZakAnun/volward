export const APP_VERSION = '0.0.3';
export const GITHUB_REPO = 'ZakAnun/volward';
export const RELEASE_BASE_URL = `https://github.com/${GITHUB_REPO}/releases/download/v${APP_VERSION}`;
export const VERSION_RELEASE_URL = `https://github.com/${GITHUB_REPO}/releases/tag/v${APP_VERSION}`;

export type Locale = 'en' | 'zh';

export type DownloadAsset = {
  id: string;
  fileName: string;
  label: string;
  hint: string;
  href: string;
};

export type FeatureCopy = {
  title: string;
  body: string;
};

export type PageCopy = {
  title: string;
  description: string;
  navFeatures: string;
  navDownload: string;
  localeToggle: string;
  downloadAllReleases: string;
  heroEyebrow: string;
  heroTitle: string;
  heroLead: string;
  ctaDownload: string;
  ctaLearn: string;
  featureSectionTitle: string;
  featureSectionLead: string;
  downloadTitle: string;
  downloadLead: string;
  footerCopy: string;
  footerVersion: string;
  footerUnsigned: string;
  features: FeatureCopy[];
};

export const PAGE_COPY: Record<Locale, PageCopy> = {
  en: {
    title: 'Volward',
    description:
      'Volward is a desktop storage steward: scan progressively, browse like Finder, then move reclaimable files to Trash.',
    navFeatures: 'Features',
    navDownload: 'Download',
    localeToggle: '中文',
    downloadAllReleases: 'See all releases on GitHub',
    heroEyebrow: 'Desktop storage steward',
    heroTitle: 'See what is taking space.',
    heroLead:
      'Scan progressively, browse in Finder-style columns, and move reclaimable files to Trash with a calm, explicit flow.',
    ctaDownload: 'Download',
    ctaLearn: 'Learn more',
    featureSectionTitle: 'A quieter way to clean up.',
    featureSectionLead: 'Every step stays visible, reversible, and easy to revisit.',
    downloadTitle: 'Download Volward',
    downloadLead: 'Choose the build that matches your desktop.',
    footerCopy: '© Volward',
    footerVersion: 'Version {version}',
    footerUnsigned:
      'Unsigned builds: macOS right-click Open; Windows SmartScreen More info → Run anyway.',
    features: [
      {
        title: 'Progressive scan',
        body: 'Preview Home quickly, keep scanning in the background, and cancel anytime.',
      },
      {
        title: 'Finder-style browsing',
        body: 'Browse in columns, filter by category or deletable state, and sort by size or name.',
      },
      {
        title: 'Safer deletion',
        body: 'Cache and Temp are low risk, Media and System are flagged before anything is trashed.',
      },
      {
        title: 'Settings and updates',
        body: 'Theme, language, in-app update, and macOS FDA guidance stay inside the app.',
      },
    ],
  },
  zh: {
    title: 'Volward',
    description:
      'Volward 是一个桌面存储管家，帮你更快找出占空间的文件，先预览、再浏览、最后安全删除。',
    navFeatures: '功能',
    navDownload: '下载',
    localeToggle: 'EN',
    downloadAllReleases: '前往 GitHub 查看全部版本',
    heroEyebrow: '桌面存储管家',
    heroTitle: '先看清谁在占空间。',
    heroLead:
      '渐进式扫描、Finder 式浏览，再把可回收文件安全移到废纸篓，整个流程尽量安静而明确。',
    ctaDownload: '下载',
    ctaLearn: '了解功能',
    featureSectionTitle: '更安静地清理空间。',
    featureSectionLead: '每一步都保持可见、可回退，也更容易重新检查。',
    downloadTitle: '下载 Volward',
    downloadLead: '选择与你的桌面平台匹配的安装包。',
    footerCopy: '© Volward',
    footerVersion: '版本 {version}',
    footerUnsigned:
      '未签名构建：macOS 右键打开；Windows SmartScreen 点“更多信息”→“仍要运行”。',
    features: [
      {
        title: '渐进式扫描',
        body: '先看到 Home 的快速预览，扫描继续在后台进行，随时可以取消。',
      },
      {
        title: 'Finder 式浏览',
        body: '按列浏览，支持分类和可删状态筛选，也能按大小或名称排序。',
      },
      {
        title: '更安全的删除',
        body: 'Cache / Temp 默认低风险，Media / System 会先提示再入废纸篓。',
      },
      {
        title: '设置和更新',
        body: '主题、语言、应用内更新、macOS FDA 提示都在应用内完成。',
      },
    ],
  },
};

export const DOWNLOADS: Record<Locale, DownloadAsset[]> = {
  en: [
    {
      id: 'macos-arm64',
      fileName: 'volward-v0.0.3-macos-arm64.zip',
      label: 'macOS (Apple Silicon)',
      hint: 'Unzip and drag into /Applications. First launch: right-click → Open.',
      href: `${RELEASE_BASE_URL}/volward-v0.0.3-macos-arm64.zip`,
    },
    {
      id: 'macos-x64',
      fileName: 'volward-v0.0.3-macos-x64.zip',
      label: 'macOS (Intel)',
      hint: 'Same install flow as Apple Silicon.',
      href: `${RELEASE_BASE_URL}/volward-v0.0.3-macos-x64.zip`,
    },
    {
      id: 'windows-x64',
      fileName: 'VolwardSetup-v0.0.3-windows-x64.exe',
      label: 'Windows (x64)',
      hint: 'If SmartScreen appears, open More info then Run anyway.',
      href: `${RELEASE_BASE_URL}/VolwardSetup-v0.0.3-windows-x64.exe`,
    },
    {
      id: 'linux-appimage',
      fileName: 'Volward-v0.0.3-linux-x86_64.AppImage',
      label: 'Linux AppImage',
      hint: 'Run chmod +x first, then launch.',
      href: `${RELEASE_BASE_URL}/Volward-v0.0.3-linux-x86_64.AppImage`,
    },
  ],
  zh: [
    {
      id: 'macos-arm64',
      fileName: 'volward-v0.0.3-macos-arm64.zip',
      label: 'macOS（Apple Silicon）',
      hint: '解压后拖入 /Applications。首次打开：右键 → 打开。',
      href: `${RELEASE_BASE_URL}/volward-v0.0.3-macos-arm64.zip`,
    },
    {
      id: 'macos-x64',
      fileName: 'volward-v0.0.3-macos-x64.zip',
      label: 'macOS（Intel）',
      hint: '安装方式同 Apple Silicon。',
      href: `${RELEASE_BASE_URL}/volward-v0.0.3-macos-x64.zip`,
    },
    {
      id: 'windows-x64',
      fileName: 'VolwardSetup-v0.0.3-windows-x64.exe',
      label: 'Windows（x64）',
      hint: '若出现 SmartScreen：更多信息 → 仍要运行。',
      href: `${RELEASE_BASE_URL}/VolwardSetup-v0.0.3-windows-x64.exe`,
    },
    {
      id: 'linux-appimage',
      fileName: 'Volward-v0.0.3-linux-x86_64.AppImage',
      label: 'Linux AppImage',
      hint: 'chmod +x 后运行。',
      href: `${RELEASE_BASE_URL}/Volward-v0.0.3-linux-x86_64.AppImage`,
    },
  ],
};
