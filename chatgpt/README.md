# ChatGPT macOS 背景设置脚本

`chatgpt-background.sh` 用于给官方 ChatGPT macOS 桌面应用设置本地背景图。脚本通过本机 Chrome DevTools Protocol（CDP）注入页面样式，不修改 `ChatGPT.app`，也不依赖 Dream Skin 或其他第三方换肤软件。

## 功能

- 使用本地 JPG、JPEG、PNG、WebP、GIF 或 AVIF 图片作为背景。
- 通过 `0–100` 的透明度参数控制背景蒙层深度。
- 左侧栏、中间聊天区和右侧标签页面板共用同一张窗口级背景图。
- 清除顶部黑色渐隐遮罩，并使用轻微磨砂标题栏保持文字可读性。
- 已开启调试端口时直接热更新，无需重启 ChatGPT。
- 页面刷新后自动恢复背景，重复执行可更换图片或透明度。
- 注入前验证图片能否实际解码，无效图片不会被误报为成功。
- 不修改应用安装包、聊天数据或 Codex 配置文件。

## 使用前提

- macOS。
- 官方 ChatGPT 桌面应用位于 `/Applications/ChatGPT.app` 或 `~/Applications/ChatGPT.app`。
- 当前 ChatGPT 包含 `Contents/Resources/cua_node/bin/node`，并支持 CDP 启动参数。
- 图片大小不超过 20 MB。

脚本使用 ChatGPT 自带的 Node.js，不需要单独安装 Node.js、Python 或 npm 依赖。

## 使用方法

在仓库根目录执行：

```bash
chmod +x ./chatgpt/chatgpt-background.sh
./chatgpt/chatgpt-background.sh "$HOME/Pictures/background.jpg" 35
```

也可以先进入本目录：

```bash
cd chatgpt
./chatgpt-background.sh "/完整/图片路径.png" 35
```

两个参数分别为：

1. 本地图片路径。路径包含空格或中文时，请使用双引号。
2. 背景透明度，取值为 `0–100` 的整数：
   - `0`：不添加蒙层，图片最清晰。
   - `35`：添加 35% 蒙层，兼顾图片和文字可读性。
   - `100`：完全遮住图片。

例如，将背景调得更清晰：

```bash
./chatgpt/chatgpt-background.sh "$HOME/Pictures/background.jpg" 15
```

将背景调得更暗、更容易阅读文字：

```bash
./chatgpt/chatgpt-background.sh "$HOME/Pictures/background.jpg" 60
```

## 重启行为

- 如果 ChatGPT 已开启脚本所需的调试端口，脚本会直接热更新背景，不会重启应用。
- 如果需要重启才能开启调试端口，脚本会先显示确认框。请先保存未发送的聊天内容，再点击“重启并应用”。
- 完全退出 ChatGPT 并以普通方式重新打开后，需要再次运行脚本才能恢复背景。

## 实现原理

1. 将本地图片读取为 Base64 Data URL，图片不会上传到网络。
2. 确认 `127.0.0.1:9341` 的监听进程属于当前官方 ChatGPT 应用。
3. 必要时经用户确认后，使用仅监听本机回环地址的 CDP 参数启动 ChatGPT。
4. 向 ChatGPT 主渲染页面注入背景及透明容器样式。
5. 保留轻量 watcher，在页面刷新或样式被移除后重新应用；更换配置时清理旧的提前注入脚本。

调试端口仅绑定 `127.0.0.1`，脚本没有上传图片、读取密钥或访问外部服务的逻辑。

## 运行文件

脚本运行时会创建 `~/.chatgpt-background/`，其中只保存注入进程信息、应用结果和日志：

```text
~/.chatgpt-background/
├── watcher.pid
├── watcher.log
└── applied-*.json
```

这些文件不包含图片内容；日志和应用结果可能包含你本次提供的本地图片路径。

## 恢复 ChatGPT 原生外观

完全退出 ChatGPT，然后不使用脚本、以普通方式重新打开即可。watcher 会在应用退出后停止，页面中的临时样式和提前注入脚本会随渲染进程一起清理。

如不再需要运行日志和状态文件，可以删除：

```bash
rm -rf "$HOME/.chatgpt-background"
```

这不会删除 ChatGPT、聊天记录或原始图片。

## 注意事项

- 这是基于 ChatGPT 当前页面结构和 CDP 能力的非官方脚本。ChatGPT 更新内部页面结构、自带 Node.js 路径或调试能力后，可能需要同步调整。
- 脚本只处理 ChatGPT 主界面的背景。右侧区域打开第三方网页后，网页自身的背景和样式不在修改范围内。
- 不建议同时运行其他会向 ChatGPT 注入样式的工具，以免背景规则互相覆盖。
- 透明度过低可能降低文字可读性；如果背景较复杂，建议从 `35–60` 开始调整。
