# background_scripts

用于自定义本地应用背景图的脚本集合。目前包含 Kimi Code Web 和 ChatGPT macOS 桌面应用背景设置脚本。

## 目录结构

```text
background_scripts/
├── README.md
├── chatgpt/
│   ├── README.md
│   └── chatgpt-background.sh
└── kimi/
    └── kimi-bg.sh
```

## Kimi Code Web 深色模式背景设置

`kimi/kimi-bg.sh` 可以为**本机 Kimi Code Web 页面**设置自定义背景图，并通过黑色蒙层调整背景深浅。它不会生成或设计图片，也不会修改 kimi.com 官方网页。

### 适用场景

- 当前适用于 Kimi Code Web 的**深色模式（`dark`）**，脚本会将页面及面板背景改为透明或半透明，使背景图可见。
- **亮色模式（`light`）暂未适配**：默认的不透明白色背景会遮住背景图，因此脚本执行后也可能看不到效果。
- **跟随系统（`system`）**会套用深色样式，建议仅在系统使用深色外观时启用，避免系统亮色外观下面板颜色不协调。

### 功能

- 自定义本地 Kimi Code Web 的背景图。
- 调整背景蒙层深度，避免背景影响文字阅读。
- 将背景图保存到 `~/.kimi-web-bg.<扩展名>`，便于升级后重新应用。
- 支持 `jpg`、`jpeg`、`png`、`webp`、`gif` 和 `avif` 格式。

### 使用前提

- macOS，且 Kimi Code Web 资源目录符合脚本中的 `darwin-arm64` 路径。
- 已安装 Python 3，并可通过 `python3` 命令调用。
- 至少打开过一次 Kimi Code Web，使本地缓存中生成 `dist-web` 资源目录。
- 首次运行且未指定图片时，需要存在默认图片：
  `~/Library/Application Support/CodexDreamSkinStudio/theme/background.jpg`。

### 使用方法

在仓库根目录执行：

```bash
# 只调整蒙层深度，取值 0~100，越大越暗
./kimi/kimi-bg.sh 60

# 只更换背景图，蒙层深度默认为 50
./kimi/kimi-bg.sh ~/Desktop/新图.jpg

# 同时更换背景图并调整深度，两个参数的顺序可以互换
./kimi/kimi-bg.sh 60 ~/Desktop/新图.jpg
```

执行完成后，在浏览器中按 `Cmd + Shift + R` 强制刷新页面。

### 实现原理

1. 将指定图片保存到用户主目录下的 `.kimi-web-bg.<扩展名>`。
2. 查找 Kimi Code 缓存中最新的 `dist-web` 目录，并将图片复制为该目录下的 `bg.<扩展名>`。
3. 修改 `dist-web/index.html`，通过 `body::before` 注入固定背景、黑色蒙层及半透明界面样式。
4. 如果已存在背景补丁，则更新蒙层透明度和图片地址；否则重新插入样式。

Kimi Code 升级可能覆盖缓存中的修改，届时重新运行脚本即可恢复背景。

### 注意事项

- 脚本会替换 `dist-web` 目录中已有的同名 `bg` 图片，并修改缓存中的 `index.html`。
- 指定新图片时，脚本会清理主目录下旧的 `.kimi-web-bg.*` 文件。
- 脚本仅操作本机文件，不包含上传图片、收集数据或访问外部服务的逻辑。
- 脚本不包含 API 密钥、访问令牌、密码或硬编码的个人用户名。

## ChatGPT macOS 背景设置

`chatgpt/chatgpt-background.sh` 可以为官方 ChatGPT macOS 桌面应用设置本地背景图和透明度，无需安装 Dream Skin 或其他换肤软件。

```bash
./chatgpt/chatgpt-background.sh "$HOME/Pictures/background.jpg" 35
```

脚本通过仅绑定本机回环地址的 CDP 注入临时样式，不修改 `ChatGPT.app`、聊天数据或 Codex 配置。已开启调试端口时支持热更新；需要重启时会先请求确认。

完整的使用前提、参数说明、实现原理、恢复方法和注意事项见 [chatgpt/README.md](chatgpt/README.md)。

## 文件说明

| 文件 | 用途 |
| --- | --- |
| `chatgpt/chatgpt-background.sh` | 设置 ChatGPT macOS 桌面应用的本地背景图和透明度 |
| `chatgpt/README.md` | ChatGPT 背景脚本的完整使用文档 |
| `kimi/kimi-bg.sh` | 设置本地 Kimi Code Web 的背景图和蒙层深度 |
