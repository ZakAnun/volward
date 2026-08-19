export const GITHUB_REPO = 'ZakAnun/volward';
export const GITHUB_RELEASES_URL = `https://github.com/${GITHUB_REPO}/releases`;

export type Locale = 'en' | 'zh';

export type DownloadAsset = {
  id: string;
  fileName: string;
  href: string;
  label: string;
  hint: string;
};

export type FeatureCopy = {
  title: string;
  body: string;
};

export type HeroDashboardCopy = {
  volumeName: string;
  chooseFolder: string;
  targets: {
    home: string;
    applications: string;
    desktop: string;
    downloads: string;
    documents: string;
  };
  capacityPath: string;
  usedBytes: string;
  usedLabel: string;
  totalBytes: string;
  totalLabel: string;
  availableBytes: string;
  availableLabel: string;
  largestTitle: string;
  scannedLabel: string;
  largestItems: [
    { name: string; size: string; barWidth: string; kind: 'folder' | 'file' },
    { name: string; size: string; barWidth: string; kind: 'folder' | 'file' },
    { name: string; size: string; barWidth: string; kind: 'folder' | 'file' },
  ];
  categories: {
    cache: string;
    temp: string;
    media: string;
    system: string;
  };
  status: string;
  lastScan: string;
  reclaimable: string;
  browseFiles: string;
  startScan: string;
};

export type PageCopy = {
  title: string;
  description: string;
  navFeatures: string;
  navDownload: string;
  localeToggle: string;
  downloadAllReleases: string;
  downloadPlatformAriaLabel: string;
  releaseLogTitle: string;
  heroEyebrow: string;
  heroTitle: string;
  heroLead: string;
  ctaDownload: string;
  ctaLearn: string;
  heroDashboard: HeroDashboardCopy;
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
    downloadPlatformAriaLabel: 'Volward for {platform}',
    releaseLogTitle: 'Latest release logs',
    heroEyebrow: 'Desktop storage steward',
    heroTitle: 'See what is taking space.',
    heroLead:
      'Scan progressively, browse in Finder-style columns, and move reclaimable files to Trash with a calm, explicit flow.',
    ctaDownload: 'Download',
    ctaLearn: 'Learn more',
    heroDashboard: {
      volumeName: 'Macintosh HD',
      chooseFolder: 'Choose Folder',
      targets: {
        home: 'Home',
        applications: 'Applications',
        desktop: 'Desktop',
        downloads: 'Downloads',
        documents: 'Documents',
      },
      capacityPath: '/Users/volward',
      usedBytes: '386 GB',
      usedLabel: 'Used',
      totalBytes: '1 TB',
      totalLabel: 'Total capacity',
      availableBytes: '638 GB',
      availableLabel: 'Available',
      largestTitle: 'Largest items',
      scannedLabel: '386 GB scanned',
      largestItems: [
        { name: 'Library', size: '132 GB', barWidth: '100%', kind: 'folder' },
        { name: 'Movies', size: '84 GB', barWidth: '64%', kind: 'folder' },
        { name: 'Xcode.app', size: '31 GB', barWidth: '24%', kind: 'file' },
      ],
      categories: {
        cache: 'Cache',
        temp: 'Temp',
        media: 'Media',
        system: 'System',
      },
      status: 'Live disk data',
      lastScan: 'Last scan today',
      reclaimable: '128 GB reclaimable',
      browseFiles: 'Browse Files',
      startScan: 'Start Scan',
    },
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
    downloadPlatformAriaLabel: '适用于 {platform} 的 Volward',
    releaseLogTitle: '最新更新日志',
    heroEyebrow: '桌面存储管家',
    heroTitle: '先看清谁在占空间。',
    heroLead:
      '渐进式扫描、Finder 式浏览，再把可回收文件安全移到废纸篓，整个流程尽量安静而明确。',
    ctaDownload: '下载',
    ctaLearn: '了解功能',
    heroDashboard: {
      volumeName: 'Macintosh HD',
      chooseFolder: '选择文件夹',
      targets: {
        home: '个人目录',
        applications: '应用程序',
        desktop: '桌面',
        downloads: '下载',
        documents: '文稿',
      },
      capacityPath: '/Users/volward',
      usedBytes: '386 GB',
      usedLabel: '已使用',
      totalBytes: '1 TB',
      totalLabel: '总容量',
      availableBytes: '638 GB',
      availableLabel: '可用',
      largestTitle: '最大项目',
      scannedLabel: '已扫描 386 GB',
      largestItems: [
        { name: '资源库', size: '132 GB', barWidth: '100%', kind: 'folder' },
        { name: '影片', size: '84 GB', barWidth: '64%', kind: 'folder' },
        { name: 'Xcode.app', size: '31 GB', barWidth: '24%', kind: 'file' },
      ],
      categories: {
        cache: '缓存',
        temp: '临时',
        media: '媒体',
        system: '系统',
      },
      status: '实时磁盘数据',
      lastScan: '上次扫描：今天',
      reclaimable: '可回收 128 GB',
      browseFiles: '浏览文件',
      startScan: '开始扫描',
    },
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

export type DownloadEntry = {
  id: DownloadAsset['id'];
  fileName: string;
  en: { label: string; hint: string };
  zh: { label: string; hint: string };
};

export const DOWNLOAD_ENTRIES: DownloadEntry[] = [
  {
    id: 'macos-arm64',
    fileName: 'volward-latest-macos-arm64.zip',
    en: { label: 'macOS (Apple Silicon)', hint: 'Unzip and drag into /Applications. First launch: right-click -> Open.' },
    zh: { label: 'macOS（Apple Silicon）', hint: '解压后拖入 /Applications。首次打开：右键 -> 打开。' },
  },
  {
    id: 'macos-x64',
    fileName: 'volward-latest-macos-x64.zip',
    en: { label: 'macOS (Intel)', hint: 'Same install flow as Apple Silicon.' },
    zh: { label: 'macOS（Intel）', hint: '安装方式同 Apple Silicon。' },
  },
  {
    id: 'windows-x64',
    fileName: 'VolwardSetup-latest-windows-x64.exe',
    en: { label: 'Windows (x64)', hint: 'If SmartScreen appears, open More info then Run anyway.' },
    zh: { label: 'Windows（x64）', hint: '若出现 SmartScreen：更多信息 -> 仍要运行。' },
  },
  {
    id: 'linux-appimage',
    fileName: 'Volward-latest-linux-x86_64.AppImage',
    en: { label: 'Linux AppImage', hint: 'Run chmod +x first, then launch.' },
    zh: { label: 'Linux AppImage', hint: 'chmod +x 后运行。' },
  },
];

export const DOWNLOADS: Record<Locale, DownloadAsset[]> = {
  en: DOWNLOAD_ENTRIES.map(({ id, fileName, en }) => ({ id, fileName, href: GITHUB_RELEASES_URL, ...en })),
  zh: DOWNLOAD_ENTRIES.map(({ id, fileName, zh }) => ({ id, fileName, href: GITHUB_RELEASES_URL, ...zh })),
};
