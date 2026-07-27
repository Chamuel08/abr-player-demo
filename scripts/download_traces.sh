#!/usr/bin/env bash
#
# download_traces.sh —— 拉取公开真实网络吞吐 trace 到 data/traces/
#
# 数据来源：confiwent/Real-world-bandwidth-traces（MIT License）
# 该仓库把学界 ABR 常用的四组公开 trace 统一预处理成 [时间戳(秒), 吞吐(Mbit/s)] 两列格式：
#   - cooked_3gp/        Norway 3G/HSDPA 车载移动网络（弱网抖动剧烈）
#   - fcc_ori/           FCC Measuring Broadband America（宽带，长时段平稳）
#   - fcc_and_hsdpa/     FCC + HSDPA 混合，自带 train/test 划分
#   - traces_oboe/       Oboe 论文数据集（带宽较高）
#   - puffer_211017/     Puffer 平台真实用户会话（2021-10-17）
#   - puffer_220218/     Puffer 平台真实用户会话（2022-02-18）
#
# clone 约 169MB，删掉 .git 后落盘约 125MB。不入 git（见 .gitignore），
# 只保留本脚本保证可复现。
#
set -euo pipefail

REPO_URL="https://github.com/confiwent/Real-world-bandwidth-traces.git"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="$ROOT_DIR/data/traces"

if [ -d "$DEST_DIR" ] && [ -n "$(ls -A "$DEST_DIR" 2>/dev/null)" ]; then
    echo "[skip] trace 已存在：$DEST_DIR"
    echo "       如需重新下载，先删除该目录。"
    exit 0
fi

command -v git >/dev/null 2>&1 || { echo "[error] 需要 git" >&2; exit 1; }

echo "[1/2] clone $REPO_URL ..."
mkdir -p "$(dirname "$DEST_DIR")"
git clone --depth 1 "$REPO_URL" "$DEST_DIR"

# .git 占了大部分体积，trace 本身是纯文本，删掉以省空间
rm -rf "$DEST_DIR/.git"

echo "[2/2] 校验 ..."
for d in cooked_3gp fcc_ori traces_oboe fcc_and_hsdpa; do
    if [ -d "$DEST_DIR/$d" ]; then
        printf '  %-16s %5d files\n' "$d" "$(find "$DEST_DIR/$d" -type f | wc -l | tr -d ' ')"
    else
        echo "  [warn] 缺少 $d"
    fi
done

echo
echo "完成。trace 位于 $DEST_DIR"
echo "下一步："
echo "  python3 scripts/simulate_abr.py --dataset norway_3g --strategy both"
echo "  python3 scripts/grid_search.py"
