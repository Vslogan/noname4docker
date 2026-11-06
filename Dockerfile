# 无名杀（noname）容器镜像
#
# 最终镜像只包含：
#   1. 构建好的静态资源（dist）
#   2. 网页服务（packages/fs）及其生产依赖
#   3. 联机服务（packages/server）及其生产依赖
# 构建期的 node_modules、pnpm store、源码仓库都不会进入最终镜像。
#
# 常用构建参数：
#   NONAME_VERSION       写入镜像标签与 /app/VERSION 的版本号（默认 dev）
#   NONAME_BUILD_COMMIT  构建对应的 git commit（显示在游戏内「构建信息」中）
#   NONAME_BUILD_TIME    构建时间（nightly 渠道使用）
#   NODE_VERSION         Node.js 大版本，需满足仓库要求（^20.19.0 || >=22.12.0）
#   PNPM_VERSION         pnpm 版本，需与仓库 CI 保持一致（10）

ARG NODE_VERSION=24

# ---------------------------------------------------------------------------
# 构建阶段：安装完整依赖并产出 dist / 服务端产物
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-alpine AS builder

ARG PNPM_VERSION=10
ARG NONAME_BUILD_COMMIT=local
ARG NONAME_BUILD_TIME=unknown

# 构建阶段不需要 electron 等二进制，跳过下载以加快构建
ENV PNPM_HOME=/pnpm \
    PATH=/pnpm:$PATH \
    ELECTRON_SKIP_BINARY_DOWNLOAD=1 \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    NONAME_BUILD_CHANNEL=release \
    NONAME_BUILD_COMMIT=${NONAME_BUILD_COMMIT} \
    NONAME_BUILD_TIME=${NONAME_BUILD_TIME}

RUN npm install --global pnpm@${PNPM_VERSION}

WORKDIR /src

COPY . .

# 安装依赖。
# 注意：这里不使用 BuildKit 的 `RUN --mount=type=cache` 语法——该语法要求启用 BuildKit，
# 在未启用 BuildKit 的旧版 docker build、NAS 容器管理面板中会直接构建失败。
# 依赖层本身仍会被 Docker 层缓存复用：只要源码没有变化，重复构建不会重新安装。
RUN pnpm install --frozen-lockfile

# 1. 构建前端静态资源，输出到 /src/dist
# 2. 单独构建网页服务与联机服务（不参与 pnpm build 的依赖图）
RUN pnpm build \
 && pnpm --filter @noname/fs build \
 && pnpm --filter @noname/server build

# 只保留生产依赖，避免 webpack/vite/electron 等开发依赖进入最终镜像
RUN pnpm --filter @noname/fs deploy --prod /out/web \
 && pnpm --filter @noname/server deploy --prod /out/online

# ---------------------------------------------------------------------------
# 运行阶段：Node.js 运行时 + 静态资源 + 两个服务的生产依赖
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-alpine AS runtime

ARG NONAME_VERSION=dev

LABEL org.opencontainers.image.title="无名杀 noname" \
      org.opencontainers.image.description="无名杀网页版容器化部署：静态资源服务 + 联机服务" \
      org.opencontainers.image.url="https://github.com/libnoname/noname" \
      org.opencontainers.image.source="https://github.com/libnoname/noname" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.opencontainers.image.version="${NONAME_VERSION}"

ENV NODE_ENV=production \
    NONAME_VERSION=${NONAME_VERSION} \
    NONAME_BIND_HOST=0.0.0.0 \
    NONAME_WEB_PORT=8089 \
    NONAME_ONLINE_PORT=8082 \
    NONAME_ROOT=/app/dist

# 运行期用不到 npm / corepack，删除以减小体积
RUN rm -rf /usr/local/lib/node_modules/npm \
           /usr/local/lib/node_modules/corepack \
           /usr/local/bin/npm \
           /usr/local/bin/npx \
           /usr/local/bin/corepack \
           /opt/yarn* \
 && mkdir -p /app/dist

WORKDIR /app

COPY --from=builder --chown=node:node /out/web /app/web
COPY --from=builder --chown=node:node /out/online /app/online
COPY --from=builder --chown=node:node /src/dist /app/dist

COPY --chown=node:node docker/entrypoint.sh /usr/local/bin/noname-entrypoint
COPY --chown=node:node docker/healthcheck.mjs /app/healthcheck.mjs

RUN chmod +x /usr/local/bin/noname-entrypoint \
 && printf '%s\n' "${NONAME_VERSION}" > /app/VERSION \
 && mkdir -p /app/dist/extension \
 && chown -R node:node /app

# 扩展目录作为匿名卷声明，直接 `docker run` 时也能持久化已导入的扩展
VOLUME ["/app/dist/extension"]

USER node

EXPOSE 8089 8082

# 默认按网页服务检查健康状态；联机服务的健康检查由 docker-compose.yml 覆盖
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD ["node", "/app/healthcheck.mjs", "web"]

ENTRYPOINT ["/usr/local/bin/noname-entrypoint"]
CMD ["web"]
