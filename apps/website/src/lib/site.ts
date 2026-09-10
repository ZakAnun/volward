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

export type WorkflowStepId = 'scan' | 'browse' | 'filter' | 'clean';

export type WorkflowStepCopy = {
  id: WorkflowStepId;
  index: string;
  shortName: string;
  title: string;
  hook: string;
};

export type ProductTourMockupLabels = {
  scanning: string;
  filterAll: string;
  moveToTrash: string;
  sortSizeDesc: string;
  navSubtitle: string;
  resultsSummary: string;
  scanTargetHome: string;
  scanActionFolder: string;
  scanActionHome: string;
  scanActionRescan: string;
  stickyBrowseResults: string;
  stickySelected: string;
  trashActionEmpty: string;
};

export type ProductTourCopy = {
  sectionLabel: string;
  sectionTitle: string;
  steps: WorkflowStepCopy[];
  mockupLabels: ProductTourMockupLabels;
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
  heroScrollHint: string;
  heroDashboard: HeroDashboardCopy;
  productTour: ProductTourCopy;
  downloadTitle: string;
  downloadLead: string;
  footerCopy: string;
  footerVersion: string;
  footerUnsigned: string;
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
    heroTitle: 'See what is taking space',
    heroLead: 'Scan, browse in Finder columns, move reclaimable files to Trash',
    ctaDownload: 'Download',
    ctaLearn: 'Learn more',
    heroScrollHint: 'Scroll to features',
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
    productTour: {
      sectionLabel: 'Features',
      sectionTitle: 'See how Volward works',
      steps: [
        {
          id: 'scan',
          index: '01',
          shortName: 'Scan',
          title: 'Pick sidebar target, then Start Scan',
          hook: '',
        },
        {
          id: 'browse',
          index: '02',
          shortName: 'Browse',
          title: 'Browse scan results',
          hook: 'Browse mode opens with summary, filter bar, and Finder-style columns',
        },
        {
          id: 'filter',
          index: '03',
          shortName: 'Filter',
          title: 'Filter by category',
          hook: 'Same browse view — switch Cache, Temp, Media, or System in the filter bar',
        },
        {
          id: 'clean',
          index: '04',
          shortName: 'Clean',
          title: 'Move to Trash',
          hook: 'Select items in the column view, then confirm in the sticky bar',
        },
      ],
      mockupLabels: {
        scanning: 'Scanning…',
        filterAll: 'All',
        moveToTrash: 'Move to Trash',
        sortSizeDesc: 'Size ↓',
        navSubtitle: 'Storage steward',
        resultsSummary: 'Macintosh HD · 386 GB · 1,247 items · 128 GB reclaimable',
        scanTargetHome: 'Home',
        scanActionFolder: 'Folder…',
        scanActionHome: 'Home',
        scanActionRescan: 'Refresh',
        stickyBrowseResults: 'Select items to move to Trash',
        stickySelected: 'Selected: 3 · 12.2 GB',
        trashActionEmpty: 'Empty Trash',
      },
    },
    downloadTitle: 'Download Volward',
    downloadLead: 'Choose the build that matches your desktop.',
    footerCopy: '© Volward',
    footerVersion: 'Version {version}',
    footerUnsigned:
      'Unsigned builds: macOS right-click Open; Windows SmartScreen More info → Run anyway.',
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
    heroTitle: '先看清谁在占用空间',
    heroLead: '渐进扫描、列式浏览，安全将可回收文件移到废纸篓',
    ctaDownload: '下载',
    ctaLearn: '了解功能',
    heroScrollHint: '向下滚动查看功能',
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
    productTour: {
      sectionLabel: '功能',
      sectionTitle: '了解 Volward 怎么用',
      steps: [
        {
          id: 'scan',
          index: '01',
          shortName: '扫描',
          title: '侧栏选目标，点开始扫描',
          hook: '',
        },
        {
          id: 'browse',
          index: '02',
          shortName: '浏览',
          title: '浏览扫描结果',
          hook: '进入 Browse 模式：摘要、筛选栏与 Finder 式列视图',
        },
        {
          id: 'filter',
          index: '03',
          shortName: '筛选',
          title: '按分类筛选',
          hook: '同一 Browse 视图，在筛选栏切换 Cache / Temp / Media / System',
        },
        {
          id: 'clean',
          index: '04',
          shortName: '清理',
          title: '移到废纸篓',
          hook: '在列视图中勾选项目，底部 StickyBar 确认后移到废纸篓',
        },
      ],
      mockupLabels: {
        scanning: '正在扫描…',
        filterAll: '全部',
        moveToTrash: '移到废纸篓',
        sortSizeDesc: '大小 ↓',
        navSubtitle: '存储管家',
        resultsSummary: 'Macintosh HD · 386 GB · 1,247 项 · 可回收 128 GB',
        scanTargetHome: 'Home',
        scanActionFolder: '选择文件夹…',
        scanActionHome: 'Home',
        scanActionRescan: '刷新',
        stickyBrowseResults: '选择要移到废纸篓的项目',
        stickySelected: '已选择：3 · 12.2 GB',
        trashActionEmpty: '清空废纸篓',
      },
    },
    downloadTitle: '下载 Volward',
    downloadLead: '选择与你的桌面平台匹配的安装包。',
    footerCopy: '© Volward',
    footerVersion: '版本 {version}',
    footerUnsigned:
      '未签名构建：macOS 右键打开；Windows SmartScreen 点“更多信息”→“仍要运行”。',
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
