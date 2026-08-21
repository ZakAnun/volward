# Volward Website

Astro 静态官网，负责产品介绍、双语内容和 GitHub Releases 下载导流。

## 开发

```bash
cd apps/website
pnpm install
pnpm dev
```

`pnpm dev` 会默认使用 `SITE_URL=http://localhost:4321` 和 `APTABASE_HOST=https://analytics.volwardapp.com`，并优先读取环境变量；如果走环境变量，`APTABASE_WEB_KEY` 和 `APTABASE_HOST` 需要成对设置。也可以在 `apps/website/aptabase.json` 里放本地配置，格式见 `aptabase.json.example`。

## 构建

```bash
cd apps/website
SITE_URL=https://volward.example pnpm build
```

产物输出到 `dist/`。

构建时会访问 GitHub latest release API 来解析真实下载链接。可选环境变量：

- `GITHUB_TOKEN` 或 `GH_TOKEN`：只在构建阶段使用，用于避免 GitHub 匿名 API rate limit。
- `SITE_URL`：生产构建必填，用于 sitemap、canonical URL 和 Open Graph URL。
- `APTABASE_WEB_KEY`：网站端 Aptabase app key；会优先读环境变量，其次读 `apps/website/aptabase.json`。
- `APTABASE_HOST`：Aptabase 上报地址；如果走环境变量，需要和 `APTABASE_WEB_KEY` 一起提供，默认值仍是 `https://analytics.volwardapp.com`。

网站统计使用官方 `@aptabase/web` SDK。自托管 App Key（`A-SH-...`）构建时必须同时提供 `APTABASE_HOST`。

如果想把构建结果直接推到服务器，可以用仓库根目录的 [`scripts/website_release.sh`](/Users/liminglin/Funny/volward/scripts/website_release.sh)：

```bash
SITE_URL=https://volward.example \
APTABASE_WEB_KEY=... \
APTABASE_HOST=https://analytics.volwardapp.com \
DEPLOY_HOST=example.com \
DEPLOY_USER=deploy \
DEPLOY_PATH=/var/www/volward-web \
DEPLOY_KEY='-----BEGIN OPENSSH PRIVATE KEY----- ...' \
bash scripts/website_release.sh
```

部署时会先构建 `apps/website/dist/`，再用 `rsync` 推到服务器；`DEPLOY_KEY` 可选，如果你已经在本机或 CI 里配置了 SSH agent，也可以不传。

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

本地构建后部署：

```bash
cd apps/website
SITE_URL=https://volward.example pnpm build
rsync -av --delete dist/ user@host:/var/www/volward-web/
```

GitHub Actions 构建后部署：

1. 在 Actions 中 checkout 仓库。
2. 安装 Node 和 pnpm。
3. 在 `apps/website` 安装依赖，然后执行 `bash scripts/website_release.sh`。
4. 构建时传入 `SITE_URL`、workflow 自带的 `GITHUB_TOKEN`，以及 `secrets.APTABASE_WEB_KEY` / `secrets.APTABASE_HOST`。
5. 如要自动部署，再补 `DEPLOY_HOST`、`DEPLOY_USER`、`DEPLOY_PATH`，以及可选的 `DEPLOY_KEY` / `DEPLOY_PORT`。

服务器只需要接收静态文件。若使用 SSH 部署，Actions secrets 建议命名为：

- `DEPLOY_HOST`
- `DEPLOY_USER`
- `DEPLOY_KEY`
- `DEPLOY_PATH`
- `DEPLOY_PORT`（可选，默认 `22`）

Nginx root 指向部署目录，例如 `/var/www/volward-web`，直接指向 `dist/` 的内容即可。

### 服务器配置

1. 创建一个部署用户，例如 `deploy`。
2. 在服务器上准备发布目录，例如 `/var/www/volward-web`。
3. 把 `deploy` 用户的 SSH 公钥写入 `~deploy/.ssh/authorized_keys`。
4. 确保 `deploy` 用户对发布目录有写权限。
5. 如果用 Nginx，站点根目录指向 `/var/www/volward-web`。
6. 如果 SSH 不是 22 端口，把 `sshd_config` 里的端口和防火墙一起放行，再把 `DEPLOY_PORT` 写到 GitHub Secrets。

一个常见的服务器侧命令顺序是：

```bash
sudo useradd -m -s /bin/bash deploy
sudo mkdir -p /var/www/volward-web
sudo chown -R deploy:deploy /var/www/volward-web
sudo install -d -m 700 /home/deploy/.ssh
sudo nano /home/deploy/.ssh/authorized_keys
sudo chmod 600 /home/deploy/.ssh/authorized_keys
sudo chown -R deploy:deploy /home/deploy/.ssh
```

### GitHub Actions 自动部署示例

如果想让 tag release 后自动上服务器，deploy job 可以这样组织：

```yaml
- name: Deploy website
  env:
    DEPLOY_HOST: ${{ secrets.DEPLOY_HOST }}
    DEPLOY_USER: ${{ secrets.DEPLOY_USER }}
    DEPLOY_KEY: ${{ secrets.DEPLOY_KEY }}
    DEPLOY_PATH: ${{ secrets.DEPLOY_PATH }}
  run: |
    install -m 600 /dev/null /tmp/volward-deploy-key
    printf '%s\n' "$DEPLOY_KEY" > /tmp/volward-deploy-key
    rsync -az --delete -e "ssh -i /tmp/volward-deploy-key -o StrictHostKeyChecking=no" \
      apps/website/dist/ \
      "${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}/"
```

部署前确保：

- 服务器上的 `DEPLOY_PATH` 已存在且可写
- 站点根目录指向这个路径
- 如果是 Nginx，静态目录权限允许 Web 进程读取

### GitHub Secrets 对应关系

- `SITE_URL`：Repository Variables，不建议放 Secret
- `APTABASE_WEB_KEY`：Secret
- `APTABASE_HOST`：Secret
- `DEPLOY_HOST`：Secret
- `DEPLOY_USER`：Secret
- `DEPLOY_PATH`：Secret
- `DEPLOY_KEY`：Secret，填 SSH 私钥全文
- `DEPLOY_PORT`：Secret 或 Variable 都可以，默认 `22`
