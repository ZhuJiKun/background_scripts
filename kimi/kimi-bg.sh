#!/bin/bash
# Kimi Code Web 背景设置脚本
#
# 用法:
#   ~/kimi-bg.sh 60                        只调深度（0~100，越大越暗）
#   ~/kimi-bg.sh ~/Desktop/新图.jpg         只换背景图（深度默认 50）
#   ~/kimi-bg.sh 60 ~/Desktop/新图.jpg      换图 + 调深度（顺序随意）
#
# 背景图会被保存到 ~/.kimi-web-bg.<扩展名>，以后即使 kimi-code 升级
# 把补丁冲掉，重跑一次本命令即可自动恢复。

set -e

DEPTH=""
NEWIMG=""

# 解析参数：数字是深度，存在的文件是图片
for arg in "$@"; do
  if [[ "$arg" =~ ^[0-9]+$ ]]; then
    DEPTH="$arg"
  elif [ -f "$arg" ]; then
    NEWIMG="$arg"
  else
    echo "无法识别的参数: $arg（既不是 0~100 的数字，也不是存在的文件）"
    exit 1
  fi
done

DEPTH="${DEPTH:-50}"
if [ "$DEPTH" -gt 100 ]; then
  echo "深度范围是 0~100"
  exit 1
fi
# 转成 0~1 小数，如 50 -> .5、65 -> .65、5 -> .05
if [ "$DEPTH" -eq 100 ]; then A="1"; elif [ "$DEPTH" -lt 10 ]; then A=".0$DEPTH"; else A=".$DEPTH"; fi

# 如果给了新图，保存到固定位置（保留原扩展名）
if [ -n "$NEWIMG" ]; then
  EXT="${NEWIMG##*.}"
  EXT=$(echo "$EXT" | tr 'A-Z' 'a-z')
  case "$EXT" in
    jpg|jpeg) EXT="jpg" ;;
    png|webp|gif|avif) ;;
    *) echo "不支持的图片格式: .$EXT（支持 jpg/png/webp/gif/avif）"; exit 1 ;;
  esac
  rm -f "$HOME"/.kimi-web-bg.*
  cp "$NEWIMG" "$HOME/.kimi-web-bg.$EXT"
  echo "已保存新背景图: $NEWIMG"
fi

# 确定当前使用的背景图；第一次运行时用默认图
STORE=$(ls "$HOME"/.kimi-web-bg.* 2>/dev/null | head -1)
if [ -z "$STORE" ]; then
  cp "$HOME/Library/Application Support/CodexDreamSkinStudio/theme/background.jpg" "$HOME/.kimi-web-bg.jpg"
  STORE="$HOME/.kimi-web-bg.jpg"
fi
EXT="${STORE##*.}"

# 找到最新版本正在使用的 dist-web 目录
D=$(ls -dt "$HOME/Library/Caches/kimi-code/web/"*/darwin-arm64/*/dist-web 2>/dev/null | head -1)
[ -d "$D" ] || { echo "没找到 kimi web 资源目录，请先打开一次 http://127.0.0.1:58627/"; exit 1; }

# 把当前背景图部署到 dist-web（清掉旧的，避免扩展名变了还残留）
rm -f "$D"/bg.jpg "$D"/bg.png "$D"/bg.webp "$D"/bg.gif "$D"/bg.avif
cp "$STORE" "$D/bg.$EXT"

python3 - "$D/index.html" "$A" "$EXT" <<'PYEOF'
import re, sys
path, a, ext = sys.argv[1], sys.argv[2], sys.argv[3]

tooltip = (
    '      /* custom tooltip colors */\n'
    '      html[data-color-scheme=dark] .ui-tip__bubble,html[data-color-scheme=system] .ui-tip__bubble{background:rgba(31,31,31,.96);color:#f5f5f5}\n'
)
block = (
    '    <style>\n'
    '      /* custom background image */\n'
    f'      body::before{{content:"";position:fixed;inset:0;z-index:-1;background:linear-gradient(rgba(0,0,0,{a}),rgba(0,0,0,{a})),url("/bg.{ext}") center/cover no-repeat}}\n'
    '      html[data-color-scheme=dark],html[data-color-scheme=system]{--bg:transparent;--panel:rgba(31,31,31,.7);--panel2:rgba(18,18,18,.7);--canvas:transparent;--bluebg:rgba(41,41,41,.72);--color-bg:transparent;--color-surface:rgba(31,31,31,.7);--color-surface-raised:rgba(41,41,41,.78);--color-surface-sunken:rgba(18,18,18,.55);--color-well:rgba(31,31,31,.7);--color-surface-deep:rgba(13,13,13,.7);--color-sidebar-bg:rgba(13,13,13,.65);--color-user-bubble-bg:rgba(41,41,41,.88)}\n'
    + tooltip
    + '    </style>\n'
    '  </head>'
)

s = open(path).read()
if "custom background" in s:
    # 已有补丁：更新蒙层深度和图片地址
    s = re.sub(r'rgba\(0,0,0,\.\d+\),rgba\(0,0,0,\.\d+\)',
               f'rgba(0,0,0,{a}),rgba(0,0,0,{a})', s, count=1)
    s = re.sub(r'/bg\.\w+', f'/bg.{ext}', s)
    if "custom tooltip colors" not in s:
        s = s.replace("    </style>", tooltip + "    </style>", 1)
else:
    # 补丁被冲掉了：重新插入
    s = s.replace("  </head>", block, 1)
open(path, "w").write(s)
PYEOF

echo "完成！背景深度: $DEPTH，图片: $STORE"
echo "到浏览器按 Cmd+Shift+R 强制刷新即可看到效果。"
