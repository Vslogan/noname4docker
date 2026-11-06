#!/usr/bin/env bash
#
# 安装 noname 命令到 PATH
#
#   sudo ./install.sh            安装到 /usr/local/bin（推荐）
#   ./install.sh ~/.local/bin    安装到指定目录
#
# 安装完成后即可在任意目录执行：
#   noname start / kill / reboot / info / update

set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$ROOT/bin/noname"

[ -f "$SOURCE" ] || {
	echo "错误：找不到 $SOURCE" >&2
	exit 1
}

chmod +x "$SOURCE"

if [ "$#" -ge 1 ] && [ -n "$1" ]; then
	target_dir="$1"
elif [ "$(id -u)" -eq 0 ] || [ -w /usr/local/bin ]; then
	target_dir="/usr/local/bin"
else
	target_dir="$HOME/.local/bin"
fi

mkdir -p "$target_dir"
ln -sfn "$SOURCE" "$target_dir/noname"

echo "已安装：$target_dir/noname -> $SOURCE"

case ":$PATH:" in
*":$target_dir:"*) ;;
*)
	echo
	echo "提示：$target_dir 不在 PATH 中，请将其加入 PATH，例如："
	echo "  echo 'export PATH=\"$target_dir:\$PATH\"' >> ~/.bashrc && . ~/.bashrc"
	;;
esac

echo
if command -v docker >/dev/null 2>&1; then
	echo "接下来执行：noname start"
else
	echo "未检测到 docker，请先安装 Docker Engine 与 Compose v2 插件。"
fi
