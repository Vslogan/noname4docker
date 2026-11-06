#!/bin/sh
# 无名杀容器入口脚本
#
# 用法：
#   noname-entrypoint web      启动网页服务（静态资源 + 文件接口）
#   noname-entrypoint online   启动联机服务（WebSocket 大厅）
#   noname-entrypoint shell    进入调试 shell
#
# 可配置环境变量：
#   NONAME_WEB_PORT     网页服务端口（默认 8089）
#   NONAME_ONLINE_PORT  联机服务端口（默认 8082）
#   NONAME_BIND_HOST    监听地址（默认 0.0.0.0）
#   NONAME_ROOT         静态资源目录（默认 /app/dist）
#   NONAME_DEBUG        设为 1 时输出访问日志
set -eu

role="${1:-web}"
if [ "$#" -gt 0 ]; then
	shift
fi

log() {
	printf '[noname] %s\n' "$*"
}

case "$role" in
web)
	port="${NONAME_WEB_PORT:-8089}"
	host="${NONAME_BIND_HOST:-0.0.0.0}"
	root="${NONAME_ROOT:-/app/dist}"

	if [ ! -f "$root/index.html" ]; then
		log "错误：$root/index.html 不存在，静态资源没有正确打包进镜像" >&2
		exit 1
	fi

	# 扩展目录经常被挂载为数据卷，这里仅给出可读的提示，不阻断启动
	if [ ! -d "$root/extension" ]; then
		if ! mkdir -p "$root/extension" 2>/dev/null; then
			log "警告：无法创建 $root/extension，导入扩展会失败" >&2
		fi
	fi

	if [ -d "$root/extension" ] && [ ! -w "$root/extension" ]; then
		log "警告：$root/extension 不可写（当前用户 $(id -u):$(id -g)）。" >&2
		log "      若使用 bind mount，请先执行：sudo chown -R 1000:1000 <宿主机目录>" >&2
	fi

	set -- node /app/web/dist/entry.cjs \
		--server \
		"--host=$host" \
		"--port=$port" \
		"--dirname=$root"
	[ "${NONAME_DEBUG:-0}" = "1" ] && set -- "$@" --debug

	log "启动网页服务：http://$host:$port/ （静态资源：$root）"
	exec "$@"
	;;

online)
	port="${NONAME_ONLINE_PORT:-8082}"
	log "启动联机服务：ws://0.0.0.0:$port"
	exec node /app/online/dist/cli.cjs --port "$port"
	;;

shell | sh | bash)
	exec /bin/sh
	;;

*)
	log "未知的运行角色：$role" >&2
	log "可用角色：web | online | shell" >&2
	exit 1
	;;
esac
