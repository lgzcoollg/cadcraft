#!/usr/bin/env bash
# 用本机的 Docker 起一个"图纸查看站点"：把 <图纸目录> 里的 DXF/DWG 和 CADCraft 的 web 版
# 拼成一个站点，跑在容器里，浏览器打开就能看、能缩放、能量尺寸。
#
# 用法:
#   packaging/drawings-viewer/serve.sh [图纸目录] [--port N] [--image IMG] [--refresh]
#
#   serve.sh                          # 看当前目录下的图纸
#   serve.sh ~/work/drawings          # 看某个目录（比如 git clone 下来的仓库）
#   serve.sh ~/work/drawings --port 9000
#   serve.sh ~/work/drawings --refresh   # 重新从镜像里取站点（换镜像版本后用）
#
# 重复运行 = 刷新图纸并重启容器；站点内容和图纸都不写进仓库，放在缓存目录里。
# 第一次运行会把 CADCraft 站点（约 36 MB）从镜像里取出来，之后复用。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${CADCRAFT_IMAGE:-lgzcoollg/cadcraft:0.5.1}"
NAME="${CADCRAFT_DRAWINGS_NAME:-cadcraft-drawings}"
SITE="${CADCRAFT_DRAWINGS_SITE:-${HOME}/.cache/cadcraft-drawings-site}"
DRAWINGS="."
PORT=""
REFRESH=""

say() { printf '%s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --port)     PORT="${2:?--port needs a number}"; shift 2 ;;
        --image)    IMAGE="${2:?--image needs a reference}"; shift 2 ;;
        --site)     SITE="${2:?--site needs a path}"; shift 2 ;;
        --name)     NAME="${2:?--name needs a name}"; shift 2 ;;
        --refresh)  REFRESH=1; shift ;;
        -h|--help)  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)         die "unknown option $1 (try --help)" ;;
        *)          DRAWINGS="$1"; shift ;;
    esac
done

command -v docker >/dev/null || die "docker not found"
[ -d "$DRAWINGS" ] || die "$DRAWINGS is not a directory"
DRAWINGS="$(cd "$DRAWINGS" && pwd)"

# --- 站点目录：父页面 + viewer/（镜像里的 web 版）+ drawings/（图纸副本）---
mkdir -p "$SITE/viewer" "$SITE/drawings"
if [ -n "$REFRESH" ] || [ ! -f "$SITE/viewer/index.html" ]; then
    say "正在从镜像 $IMAGE 取出 CADCraft 站点（约 36 MB，只有第一次慢）…"
    cid="$(docker create "$IMAGE")"
    trap 'docker rm "$cid" >/dev/null 2>&1 || true' EXIT
    docker cp "$cid:/usr/share/nginx/html/." "$SITE/viewer/"
    docker rm "$cid" >/dev/null
    trap - EXIT
    rm -f "$SITE/viewer/50x.html"          # nginx 自带的默认页，用不上
fi
cp -f "$HERE/index.html" "$SITE/index.html"

# --- 图纸：复制一份并生成清单（父页面按 index.txt 列表）---
say "正在收集 $DRAWINGS 下的 .dxf/.dwg …"
rm -rf "$SITE/drawings"
mkdir -p "$SITE/drawings"
count=0
while IFS= read -r -d '' f; do
    rel="${f#"$DRAWINGS"/}"
    mkdir -p "$SITE/drawings/$(dirname "$rel")"
    cp -f "$f" "$SITE/drawings/$rel"
    printf '%s\n' "$rel"
    count=$((count + 1))
done < <(find "$DRAWINGS" -type f \( -iname '*.dxf' -o -iname '*.dwg' \) -print0) > "$SITE/drawings/index.txt"
LC_ALL=C sort -o "$SITE/drawings/index.txt" "$SITE/drawings/index.txt" 2>/dev/null || true
say "收集到 $count 张图纸"

# --- 端口：默认 8772，被占了就往后找 ---
free_port() {
    local p="$1"
    if command -v lsof >/dev/null; then
        ! lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1
    else
        ! (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null
    fi
}
if [ -z "$PORT" ]; then
    PORT=8772
    i=0
    while ! free_port "$PORT" && [ "$i" -lt 20 ]; do PORT=$((PORT + 1)); i=$((i + 1)); done
fi

# --- 容器：同名就换掉，端口映射到站点目录（只读）---
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --restart unless-stopped \
    -p "${PORT}:80" \
    -v "$SITE:/usr/share/nginx/html:ro" \
    "$IMAGE" web >/dev/null

# --- 报告地址 ---
ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
say ""
say "图纸站点已启动（容器 ${NAME}，镜像 ${IMAGE}，站点目录 ${SITE}）"
say "  本机：      http://localhost:$PORT/"
[ -n "${ip:-}" ] && say "  局域网：    http://${ip}:${PORT}/    （同事用这个；一台机器上跑多个 crafting app 时记得换端口）"
say "  停止：      docker rm -f ${NAME}"
say "  换图纸：    再跑一次本脚本（会自动刷新目录并重启容器）"
