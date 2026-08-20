# Volward Website

Astro 静态官网，负责产品介绍、双语内容和 GitHub Releases 下载导流。

## 开发

```bash
cd apps/website
pnpm install
pnpm dev
```

`pnpm dev` 会默认使用 `SITE_URL=http://localhost:4321` 和 `APTABASE_HOST=https://analytics.volwardapp.com`，并尝试从 `~/.zshrc` 读取 `APTABASE_WEB_KEY`。也可以像生产构建一样显式传入这些环境变量。

## 构建

```bash
cd apps/website
SITE_URL=https://volward.example pnpm build
```

产物输出到 `dist/`。

构建时会访问 GitHub latest release API 来解析真实下载链接。可选环境变量：

- `GITHUB_TOKEN` 或 `GH_TOKEN`：只在构建阶段使用，用于避免 GitHub 匿名 API rate limit。
- `SITE_URL`：生产构建必填，用于 sitemap、canonical URL 和 Open Graph URL。
- `APTABASE_WEB_KEY`：网站端 Aptabase app key；未配置时前端统计保持 noop。
- `APTABASE_HOST`：Aptabase 上报地址，默认 `https://analytics.volwardapp.com`。

网站统计使用官方 `@aptabase/web` SDK。自托管 App Key（`A-SH-...`）构建时必须同时提供 `APTABASE_HOST`。

生成后的静态文件不会包含 GitHub token，服务器也不需要配置 GitHub token。

## 预览

```bash
cd apps/website
pnpm preview
```

或者：

```bash
python3 -m http.server 8080 --directory dist
```

## 部署

首次同时发布桌面端 GitHub Release 与官网时，按 [`../../docs/first-release-guide.md`](../../docs/first-release-guide.md) 执行。

本地构建后部署：

```bash
cd apps/website
SITE_URL=https://volward.example pnpm build
rsync -av --delete dist/ user@host:/var/www/volward-web/
```

GitHub Actions 构建后部署：

1. 在 Actions 中 checkout 仓库。
2. 安装 Node 和 pnpm。
3. 在 `apps/website` 安装依赖、执行测试和 `pnpm build`。
4. 构建时传入 `SITE_URL`、workflow 自带的 `GITHUB_TOKEN`，以及 `secrets.APTABASE_WEB_KEY` / `secrets.APTABASE_HOST`。
5. 将 `apps/website/dist/` 作为 artifact 保存，或通过 SSH/rsync/scp 发布到服务器。

服务器只需要接收静态文件。若使用 SSH 部署，Actions secrets 建议命名为：

- `DEPLOY_HOST`
- `DEPLOY_USER`
- `DEPLOY_KEY`
- `DEPLOY_PATH`

Nginx root 指向部署目录，例如 `/var/www/volward-web`。
