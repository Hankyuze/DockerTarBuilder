#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-Hankyuze/DockerTarBuilder}"
TAG="${TAG:-DockerTarBuilder-AMD64}"
PROXY="${PROXY:-http://127.0.0.1:10808}"
FILTER="${1:-}"
OUT_DIR="${2:-./downloads}"

if ! command -v aria2c >/dev/null 2>&1; then
  echo "[ERROR] 未安装 aria2"
  echo "Ubuntu/WSL 执行: sudo apt update && sudo apt install -y aria2"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[ERROR] 未安装 python3"
  exit 1
fi

mkdir -p "$OUT_DIR"
TMP_HTML="$(mktemp)"
TMP_LIST="$(mktemp)"
trap 'rm -f "$TMP_HTML" "$TMP_LIST"' EXIT

ASSET_PAGE="https://github.com/${REPO}/releases/expanded_assets/${TAG}"

echo "=========================================="
echo "GitHub Release 高速下载"
echo "仓库: $REPO"
echo "Tag : $TAG"
echo "筛选: ${FILTER:-全部文件}"
echo "目录: $OUT_DIR"
echo "代理: $PROXY"
echo "=========================================="

USE_PROXY=0

# 先尝试通过本地代理访问 github.com。
# 不再依赖 api.github.com，避免部分代理对 GitHub API TLS 握手失败。
if [[ -n "$PROXY" && "$PROXY" != "none" ]]; then
  echo "[0/4] 检测 GitHub 代理连通性..."
  if curl -fsSL \
      --connect-timeout 10 \
      --max-time 30 \
      --retry 2 \
      --proxy "$PROXY" \
      "$ASSET_PAGE" \
      -o "$TMP_HTML"; then
    USE_PROXY=1
    echo "代理访问 GitHub：OK"
  else
    echo "[WARN] 代理访问 GitHub 失败，自动尝试直连..."
    rm -f "$TMP_HTML"
    if ! curl -fsSL \
        --connect-timeout 10 \
        --max-time 30 \
        --retry 2 \
        "$ASSET_PAGE" \
        -o "$TMP_HTML"; then
      echo "[ERROR] GitHub 代理和直连都失败。"
      echo "先执行下面两条检查："
      echo "  curl -I https://github.com"
      echo "  curl -I -x $PROXY https://github.com"
      exit 1
    fi
    echo "GitHub 直连：OK"
  fi
else
  echo "[0/4] 使用 GitHub 直连..."
  curl -fsSL \
    --connect-timeout 10 \
    --max-time 30 \
    --retry 2 \
    "$ASSET_PAGE" \
    -o "$TMP_HTML"
fi

# 从 Release 的 expanded_assets 页面提取真实下载链接。
python3 - "$TMP_HTML" "$TMP_LIST" "$FILTER" "$REPO" "$TAG" <<'PY'
import html
import re
import sys
from urllib.parse import unquote

src, dst, flt, repo, tag = sys.argv[1:]
text = open(src, 'r', encoding='utf-8', errors='ignore').read()

pattern = re.compile(r'href="([^"]*/releases/download/[^"]+)"')
seen = set()
selected = []

for href in pattern.findall(text):
    href = html.unescape(href)
    if href.startswith('/'):
        url = 'https://github.com' + href
    elif href.startswith('http://') or href.startswith('https://'):
        url = href
    else:
        continue

    name = unquote(url.rsplit('/', 1)[-1])
    if flt and flt.lower() not in name.lower():
        continue
    if url in seen:
        continue
    seen.add(url)
    selected.append((name, url))

if not selected:
    print('[ERROR] Release 页面中没有找到匹配文件。', file=sys.stderr)
    print('筛选关键字:', flt or '(空)', file=sys.stderr)
    sys.exit(2)

with open(dst, 'w', encoding='utf-8') as f:
    for name, url in selected:
        f.write(url + '\n')
        f.write('  out=' + name + '\n')

print('将下载以下文件:')
for name, _ in selected:
    print(' -', name)
PY

aria2_args=(
  --continue=true
  --max-connection-per-server=16
  --split=16
  --min-split-size=1M
  --max-concurrent-downloads=3
  --file-allocation=none
  --connect-timeout=15
  --timeout=60
  --max-tries=0
  --retry-wait=2
  --summary-interval=2
  --console-log-level=warn
  --download-result=full
  --auto-file-renaming=false
  --allow-overwrite=true
  --dir="$OUT_DIR"
  --input-file="$TMP_LIST"
)

if [[ "$USE_PROXY" -eq 1 ]]; then
  aria2_args+=(--all-proxy="$PROXY")
  echo ""
  echo "下载模式：代理 + aria2 16连接"
else
  echo ""
  echo "下载模式：直连 + aria2 16连接"
fi

echo "[1/4] aria2 多线程下载开始..."
aria2c "${aria2_args[@]}"

echo ""
echo "[2/4] 检查分卷..."
shopt -s nullglob

for sha_path in "$OUT_DIR"/*.sha256; do
  sha_name="$(basename "$sha_path")"
  base_name="${sha_name%.sha256}"
  base_path="$OUT_DIR/$base_name"

  if [[ ! -f "$base_path" ]]; then
    parts=("$OUT_DIR/$base_name".part-*)
    if (( ${#parts[@]} > 0 )); then
      echo "合并: $base_name"
      cat "${parts[@]}" > "$base_path"
    fi
  fi
done

echo ""
echo "[3/4] SHA256 校验..."
SHA_COUNT=0
for sha_path in "$OUT_DIR"/*.sha256; do
  SHA_COUNT=$((SHA_COUNT + 1))
  (
    cd "$OUT_DIR"
    sha256sum -c "$(basename "$sha_path")"
  )
done

if [[ "$SHA_COUNT" -eq 0 ]]; then
  echo "[WARN] 没有找到 .sha256 文件，跳过校验"
fi

echo ""
echo "[4/4] 完成"
echo "=========================================="
echo "下载目录: $OUT_DIR"
echo "=========================================="
