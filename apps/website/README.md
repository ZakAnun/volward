# Volward Website

Astro 静态官网，负责产品介绍、双语内容和 GitHub Releases 下载导流。

## 开发

```bash
cd apps/website
pnpm install
pnpm dev
```

## 构建

```bash
cd apps/website
pnpm build
```

产物输出到 `dist/`。

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

```bash
pnpm build
rsync -av --delete dist/ user@host:/var/www/volward-web/
```

Nginx root 指向 `/var/www/volward-web`。
