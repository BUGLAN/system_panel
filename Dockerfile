# 宿主养成系统 · 一个容器同时跑 API 和前端静态文件
# 构建：docker compose build    运行：docker compose up -d    数据：/data（SQLite + 证据照片 + 快照）

# ── 1. 构建前后端 ─────────────────────────────────────────────
FROM node:22-slim AS build
WORKDIR /app
# 原生依赖（better-sqlite3）没有预编译包时要现场编译
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json ./
COPY packages/core/package.json packages/core/
COPY apps/web/package.json apps/web/
COPY apps/server/package.json apps/server/
RUN npm ci
COPY . .
RUN npm run build && node scripts/check-dist.mjs

# ── 2. 只装服务端的生产依赖 ───────────────────────────────────
FROM node:22-slim AS deps
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json ./
COPY packages/core/package.json packages/core/
COPY apps/web/package.json apps/web/
COPY apps/server/package.json apps/server/
RUN npm ci --omit=dev --workspace=@host/server --include-workspace-root=false

# ── 3. 运行 ───────────────────────────────────────────────────
FROM node:22-slim
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=8787 \
    DATA_DIR=/data \
    BACKUP_DIR=/backups \
    WEB_DIST=/app/apps/web/dist
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/apps/server/dist ./apps/server/dist
COPY --from=build /app/apps/web/dist ./apps/web/dist
RUN mkdir -p /data /backups && chown -R node:node /data /backups
USER node
VOLUME ["/data", "/backups"]
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8787/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "apps/server/dist/main.mjs"]
