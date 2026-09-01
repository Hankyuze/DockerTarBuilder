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
TMP_JSON="$(mktemp)"
TMP_LIST="$(mktemp)"
trap 'rm -f "$TMP_JSON" "$TMP_LIST"' EXIT

API="https://api.github.com/repos/${REPO}/releases/tags/${TAG}"

echo "=========================================="
echo "GitHub Release 高速下载"
echo "仓库: $REPO"
echo "Tag : $TAG"
echo "筛选: ${FILTER:-全部文件}"
echo "目录: $OUT_DIR"
echo "代理: $PROXY"
echo "=========================================="

curl_opts=(-fL --connect-timeout 15 --retry 5 --retry-delay 2)
if [[ -n "$PROXY" && "$PROXY" != "none" ]]; then
  curl_opts+=(--proxy "$PROXY")
fi

curl "${curl_opts[@]}" "$API" -o "$TMP_JSON"

python3 - "$TMP_JSON" "$TMP_LIST" "$FILTER" <<'PY'
import json, sys
src, dst, flt = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src, 'r', encoding='utf-8') as f:
    data = json.load(f)
assets = data.get('assets', [])
selected = []
for a in assets:
    name = a.get('name', '')
    url = a.get('browser_download_url', '')
    if not url:
        continue
    if flt and flt.lower() not in name.lower():
        continue
    selected.append((name, url))
if not selected:
    print('[ERROR] Release 中没有匹配文件', file=sys.stderr)
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
  --dir="$OUT_DIR"
  --input-file="$TMP_LIST"
)

if [[ -n "$PROXY" && "$PROXY" != "none" ]]; then
  aria2_args+=(--all-proxy="$PROXY")
fi

echo ""
echo "[1/3] aria2 多线程下载开始..."
aria2c "${aria2_args[@]}"

echo ""
echo "[2/3] 检查分卷并自动合并..."
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
echo "[3/3] SHA256 校验..."
for sha_path in "$OUT_DIR"/*.sha256; do
  (
    cd "$OUT_DIR"
    sha256sum -c "$(basename "$sha_path")"
  )
done

echo ""
echo "=========================================="
echo "完成"
echo "下载目录: $OUT_DIR"
echo "=========================================="
