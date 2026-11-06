# 无名杀 Docker 部署指南

本文档介绍如何用 Docker Compose 一键部署《无名杀》网页版，并使用配套的 `noname` 命令完成日常运维。

- 源码仓库：<https://github.com/libnoname/noname>
- 容器化文件：`Dockerfile`、`docker-compose.yml`、`docker/`、`bin/noname`

## 一、部署了什么

| 服务     | 说明                                                       | 默认端口 |
| -------- | ---------------------------------------------------------- | -------- |
| `web`    | 静态资源服务 + 文件读写接口（浏览器端存档、扩展导入依赖它） | `8089`   |
| `online` | 联机服务（游戏内「联机」大厅使用的 WebSocket 服务）        | `8082`   |

两者使用**同一个镜像**，通过容器启动参数区分角色，因此只占用一份磁盘空间。

镜像内容只包含：

1. `pnpm build` 产出的静态资源（`dist/`）
2. 网页服务与联机服务的代码及其**生产依赖**（约 18 MB）

构建阶段安装的 `node_modules`、pnpm store、源码仓库都**不会**进入最终镜像；运行镜像还额外删除了 `npm`/`corepack`，并用 Alpine 作为基础镜像。最终镜像体积约 1.4 GB，其中 99% 是游戏本身的音频与图像素材（`audio` 640 MB、`image` 541 MB），这部分无法裁剪，否则会缺素材。

## 二、环境要求

- Docker Engine 20.10+（推荐 24+）
- Docker Compose v2（`docker compose` 子命令，或独立的 `docker-compose`）
- 不要求启用 BuildKit：Dockerfile 同时兼容新旧构建器（NAS 的容器管理面板通常使用旧版构建器）
- 磁盘：至少 8 GB 可用（构建期依赖 + 最终镜像）
- 内存：构建时建议 4 GB 以上
- 网络：首次构建需要访问 npm 源；`noname update` 还需要访问 GitHub

## 三、一键部署

```bash
git clone https://github.com/libnoname/noname.git noname   # 或使用你 fork 的仓库
cd noname

sudo ./install.sh      # 把 noname 命令安装到 /usr/local/bin
noname start           # 首次会构建镜像（5~20 分钟），然后启动服务
```

`noname start` 结束后会打印网页与联机地址，例如：

```
访问地址
  网页： http://localhost:8089/
        http://192.168.1.10:8089/
  联机： ws://192.168.1.10:8082（游戏内「联机」模式地址栏填写 192.168.1.10:8082）
```

不想安装命令，也可以直接用 Compose：

```bash
docker compose up -d --build
```

## 四、命令说明

```bash
noname start            # 构建（镜像不存在时）并启动全部服务
noname kill             # 停止并移除容器（保留镜像与扩展数据卷）
noname kill --purge     # 连同数据卷、部署状态一起删除（危险）
noname reboot           # 重启服务
noname reboot --recreate  # 强制重新创建容器（配置变更后使用）
noname info             # 查看运行状态、端口映射、资源占用、磁盘占用
noname update           # 检查 GitHub Release 最新版本，不一致则重新构建并重启
noname update --check   # 只检查，有新版本时退出码为 10
noname build            # 用当前目录源码重新构建镜像并重建容器
noname logs -f web      # 查看日志（web / online 可指定服务）
noname version          # 当前命令行与部署版本
```

### noname info 示例

```
无名杀部署状态
  项目目录 : /srv/noname
  镜像     : noname:v1.11.7
  应用版本 : v1.11.7  （部署于 2026-11-06T08:30:12Z）
  部署来源 : release
  项目名   : noname

[web]
  容器 : noname-web-1
  状态 : running / 健康 healthy / 重启 0 次
  启动 : 2026-11-06 16:30:15
  端口 : 0.0.0.0:8089 -> 8089/tcp
  镜像 : noname:v1.11.7（4f2a1c9d8b7e）
  资源 : CPU 0.03% / 内存 92.4MiB / 1.9GiB
...
```

## 五、配置

复制示例配置后按需修改，Compose 会自动读取项目根目录的 `.env`：

```bash
cp .env.example .env
```

常用配置项：

| 变量                      | 默认值               | 说明                                              |
| ------------------------- | -------------------- | ------------------------------------------------- |
| `NONAME_WEB_PORT`         | `8089`               | 网页服务端口                                      |
| `NONAME_ONLINE_PORT`      | `8082`               | 联机服务端口                                      |
| `NONAME_BIND_ADDRESS`     | `0.0.0.0`            | 宿主机监听地址，配合反向代理可改为 `127.0.0.1`    |
| `NONAME_EXTENSION_VOLUME` | `noname-extensions`  | 扩展数据卷名称                                    |
| `NONAME_IMAGE`            | `noname`             | 镜像名                                            |
| `NONAME_UPSTREAM`         | 上游 GitHub 地址     | `noname update` 拉取源码的仓库，可换成镜像地址    |
| `GITHUB_TOKEN`            | 空                   | 可选，避免查询 Release 时触发 API 限流            |
| `NONAME_KEEP_IMAGES`      | `2`                 | `update --prune` 时保留的版本数量（含当前版本）   |

修改端口后需要重建容器：`noname reboot --recreate`。

## 六、数据持久化

- **扩展目录**：容器内 `/app/dist/extension` 挂载到数据卷 `noname-extensions`，`noname update` 或重建容器都不会丢失已导入的扩展。
- **游戏存档**：网页模式下存档保存在**浏览器 localStorage** 中，与容器无关；换浏览器/清理缓存会丢失，重要存档请用游戏内导出功能备份。
- 备份扩展目录：

  ```bash
  docker run --rm -v noname-extensions:/data -v "$PWD":/backup alpine \
    tar czf /backup/extensions-$(date +%F).tar.gz -C /data .
  ```

- 使用 bind mount 时（自行修改 compose 文件），宿主机目录属主需要是镜像内的 `node` 用户（uid/gid `1000`）：

  ```bash
  sudo mkdir -p /srv/noname/extensions && sudo chown -R 1000:1000 /srv/noname/extensions
  ```

## 七、更新机制（noname update）

`noname update` 的完整流程：

1. 通过 GitHub API `repos/libnoname/noname/releases/latest` 获取最新 Release 标签；
   API 不可用时回退到 `git ls-remote --tags`，取版本号最大的标签。
2. 与当前部署版本比较（记录在 `.noname/state.env`，也写入镜像 OCI 标签与 `/app/VERSION`）。
3. 版本一致 → 直接结束；`--force` 可强制重建。
4. 版本不一致 → `git clone --depth 1 --branch <tag>` 拉取该 Release 源码到 `.noname/src/<tag>`，
   把本仓库的 `Dockerfile` / `.dockerignore` / `docker/` 复制进去后重新构建镜像。
5. 新镜像同时标记为 `noname:<tag>` 与 `noname:latest`。
6. 用新镜像重建并重启容器，健康检查通过后写入新的部署状态。
7. 构建成功会删除 `.noname/src/<tag>`（约 1.5 GB）以节省磁盘；构建失败则保留便于排查。
8. `--prune` 会清理旧版本镜像，默认保留当前版本 + 1 个历史版本用于回滚。

常用用法：

```bash
noname update --check                 # 只检查是否有新版本
noname update                         # 更新到最新 Release
noname update --tag v1.11.7           # 部署指定版本
noname update --force --prune         # 强制重建并清理旧镜像
noname update --no-restart            # 只构建，不重启服务
```

回滚到保留的历史版本（镜像已存在时无需重新构建，秒级切换）：

```bash
docker images noname                 # 查看本地保留的历史版本
noname update --tag v1.11.6          # 直接切换到旧版本并重启
noname update --tag v1.11.6 --force  # 需要按该标签重新构建时使用
```

> 注意：版本比较使用 `sort -V`，需要 GNU coreutils（Linux 默认满足）。

## 八、反向代理与 HTTPS（推荐）

网页模式的即时编译（TS 扩展）依赖 Service Worker，而 Service Worker 只在**安全上下文**（HTTPS 或 `localhost`）可用。通过局域网 IP 用 `http://` 访问时游戏可以正常游玩，但无法使用 TS 扩展的即时编译。

需要完整功能时，建议用 Nginx/Caddy 提供 HTTPS，并把 `NONAME_BIND_ADDRESS` 改为 `127.0.0.1`。

Nginx 示例（联机服务需要 WebSocket 升级）：

```nginx
server {
    listen 443 ssl;
    server_name noname.example.com;

    ssl_certificate     /etc/letsencrypt/live/noname.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/noname.example.com/privkey.pem;

    client_max_body_size 512m;   # 导入扩展/存档包时放开体积限制

    location / {
        proxy_pass http://127.0.0.1:8089;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /online/ {
        proxy_pass http://127.0.0.1:8082/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

> 安全提醒：网页服务内置的文件接口可以在容器内 `/app/dist` 目录读写文件（用于存档与扩展导入）。**不要**把 8089 直接暴露到公网，请通过反向代理加认证，或只在内网使用。

## 九、常见问题

**构建报错 `the --mount option requires BuildKit`**
旧版 Dockerfile 使用过 BuildKit 专属的缓存挂载语法，现已移除，重新 `git pull` 后可直接构建。
如果希望显式启用 BuildKit 获得更快的构建，可设置环境变量后重试：`DOCKER_BUILDKIT=1 noname build`。

**构建很慢 / 卡在 pnpm install**
首次构建需要下载依赖并执行 vite 构建，属正常现象；源码未变化时重复构建会直接复用 Docker 层缓存。
国内网络可配置 npm 镜像，或使用 `NONAME_BUILD_EXTRA_ARGS` 追加构建参数。

**`noname update` 拉取源码失败**
GitHub 访问受限时，可设置镜像地址：

```bash
NONAME_UPSTREAM=https://gitclone.com/github.com/libnoname/noname.git noname update
```

GitHub API 限流时设置 `GITHUB_TOKEN`。

**端口被占用**
修改 `.env` 中的 `NONAME_WEB_PORT` / `NONAME_ONLINE_PORT`，然后 `noname reboot --recreate`。

**扩展导入失败 / 提示目录不可写**
确认数据卷属主正确，容器内以 `node`（1000:1000）运行：
`docker exec <容器> id`，bind mount 场景请 `chown -R 1000:1000`。

**如何查看日志**
`noname logs -f`（全部服务）或 `noname logs -f web`。容器日志已限制为单个文件 10 MB、最多 3 个。

**想彻底重来**

```bash
noname kill --purge    # 删除容器、数据卷与状态
noname start
```
