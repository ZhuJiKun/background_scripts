#!/bin/bash

set -Eeuo pipefail

if [ "$#" -ne 2 ]; then
  printf '用法: %s /绝对/图片路径 透明度(0-100)\n' "$0" >&2
  printf '透明度 0 = 图片完全不透明；100 = 完全隐藏图片。必要时脚本会重启 ChatGPT。\n' >&2
  exit 2
fi

IMAGE_PATH="$1"
TRANSPARENCY="$2"
[ -f "$IMAGE_PATH" ] || { printf '图片不存在: %s\n' "$IMAGE_PATH" >&2; exit 1; }
case "$TRANSPARENCY" in
  ''|*[!0-9]*) printf '透明度必须是 0-100 的整数。\n' >&2; exit 2 ;;
esac
[ "$TRANSPARENCY" -le 100 ] || { printf '透明度必须是 0-100 的整数。\n' >&2; exit 2; }

APP=""
for candidate in /Applications/ChatGPT.app "$HOME/Applications/ChatGPT.app"; do
  if [ -x "$candidate/Contents/MacOS/ChatGPT" ]; then APP="$candidate"; break; fi
done
[ -n "$APP" ] || { printf '未找到官方 ChatGPT.app。\n' >&2; exit 1; }
NODE="$APP/Contents/Resources/cua_node/bin/node"
[ -x "$NODE" ] || { printf '未找到 ChatGPT 自带的 Node.js。\n' >&2; exit 1; }

PORT=9341
STATE_DIR="$HOME/.chatgpt-background"
PID_FILE="$STATE_DIR/watcher.pid"
LOG_FILE="$STATE_DIR/watcher.log"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

stop_watcher() {
  [ -f "$PID_FILE" ] || return 0
  local old_pid old_token command
  read -r old_pid old_token < "$PID_FILE" || true
  if [ -n "${old_pid:-}" ] && [ -n "${old_token:-}" ]; then
    command="$(ps -p "$old_pid" -o command= 2>/dev/null || true)"
    case "$command" in
      *"$NODE --input-type=module - $PORT $old_token"*)
        kill -TERM "$old_pid" 2>/dev/null || true
        for _ in $(seq 1 50); do
          kill -0 "$old_pid" 2>/dev/null || break
          sleep 0.1
        done
        if kill -0 "$old_pid" 2>/dev/null; then
          printf '旧注入进程未能退出，已取消本次操作。\n' >&2
          return 1
        fi
        ;;
    esac
  fi
  rm -f "$PID_FILE"
}

cdp_ready() {
  local listener_pid command
  listener_pid="$(/usr/sbin/lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -n 1)"
  [ -n "$listener_pid" ] || return 1
  command="$(ps -p "$listener_pid" -o command= 2>/dev/null || true)"
  case "$command" in
    "$APP/Contents/MacOS/ChatGPT"*) ;;
    *) return 1 ;;
  esac
  curl --noproxy '*' -fsS --max-time 1 "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1
}

if ! cdp_ready; then
  if pgrep -f "$APP/Contents/MacOS/ChatGPT" >/dev/null 2>&1; then
    if ! osascript <<'APPLESCRIPT' >/dev/null 2>&1
display dialog "需要重启 ChatGPT 才能应用背景。请先保存未发送的聊天内容，再点击“重启并应用”。" buttons {"取消", "重启并应用"} default button "重启并应用" cancel button "取消" with title "ChatGPT Background"
APPLESCRIPT
    then
      printf '已取消，ChatGPT 未重启。\n'
      exit 20
    fi
    osascript -e 'tell application id "com.openai.codex" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 60); do
      pgrep -f "$APP/Contents/MacOS/ChatGPT" >/dev/null 2>&1 || break
      sleep 0.25
    done
    if pgrep -f "$APP/Contents/MacOS/ChatGPT" >/dev/null 2>&1; then
      printf 'ChatGPT 未退出，已停止操作。请手动按 Cmd+Q 后重试。\n' >&2
      exit 1
    fi
  fi
  open -na "$APP" --args \
    --remote-debugging-address=127.0.0.1 \
    --remote-debugging-port="$PORT"
fi
stop_watcher

for _ in $(seq 1 90); do
  cdp_ready && break
  sleep 0.5
done
if ! cdp_ready; then
  printf 'ChatGPT 未能打开调试端口 %s。\n' "$PORT" >&2
  exit 1
fi

rm -f "$STATE_DIR"/applied-*.json
TOKEN="$(uuidgen)"
APPLIED_FILE="$STATE_DIR/applied-$TOKEN.json"
: > "$LOG_FILE"

nohup env \
  IMAGE_PATH="$IMAGE_PATH" \
  TRANSPARENCY="$TRANSPARENCY" \
  STATE_DIR="$STATE_DIR" \
  APPLIED_FILE="$APPLIED_FILE" \
  "$NODE" --input-type=module - "$PORT" "$TOKEN" >>"$LOG_FILE" 2>&1 <<'NODE' &
import fs from "node:fs/promises";
import path from "node:path";

const port = Number(process.argv[2]);
const token = process.argv[3];
const imagePath = process.env.IMAGE_PATH;
const transparency = Number(process.env.TRANSPARENCY);
const stateDir = process.env.STATE_DIR;
const appliedFile = process.env.APPLIED_FILE;
const image = await fs.readFile(imagePath);
if (image.length === 0 || image.length > 20 * 1024 * 1024) {
  throw new Error("图片不能为空，且不能超过 20 MB");
}
const mimeByExtension = {
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".png": "image/png",
  ".webp": "image/webp",
  ".gif": "image/gif",
  ".avif": "image/avif",
};
const mime = mimeByExtension[path.extname(imagePath).toLowerCase()];
if (!mime) throw new Error("仅支持 JPG、PNG、WebP、GIF、AVIF 图片");
const dataUrl = `data:${mime};base64,${image.toString("base64")}`;
const shade = (transparency / 100).toFixed(2);
const css = `
html[data-local-chatgpt-background] {
  background: transparent !important;
  --local-chatgpt-overlay: 255 255 255;
}
html[data-local-chatgpt-background]:is(.electron-dark, [data-theme="dark"]) {
  --local-chatgpt-overlay: 17 17 17;
}
html[data-local-chatgpt-background] body {
  background-color: rgb(var(--local-chatgpt-overlay)) !important;
  background-image:
    linear-gradient(
      rgb(var(--local-chatgpt-overlay) / ${shade}),
      rgb(var(--local-chatgpt-overlay) / ${shade})
    ),
    url(${JSON.stringify(dataUrl)}) !important;
  background-repeat: no-repeat !important;
  background-position: center center !important;
  background-size: cover !important;
  background-attachment: fixed !important;
}
html[data-local-chatgpt-background] .macos-window-backdrop,
html[data-local-chatgpt-background] #root,
html[data-local-chatgpt-background] #root > div,
html[data-local-chatgpt-background] [data-app-shell-page-surface="true"], [data-app-shell-surface-backing="true"], [data-app-shell-tabs="true"] > div, [data-new-tab-scroll-root="true"], [class*="app-shell-content-fade-height"],
html[data-local-chatgpt-background] .sidebar-navigation,
html[data-local-chatgpt-background] main,
html[data-local-chatgpt-background] [role="main"],
html[data-local-chatgpt-background] aside.app-shell-left-panel,
html[data-local-chatgpt-background] header:is(.app-header-tint, [data-app-shell-header-edge-scroll], [data-app-shell-titlebar="true"], [class*="_Header_"]) {
  background-color: transparent !important;
  background-image: none !important;
  backdrop-filter: none !important;
}
`;
const installSource = `(() => {
  const excluded = new URLSearchParams(location.search).get("initialRoute") === "/avatar-overlay";
  if (excluded) return;
  document.documentElement.setAttribute("data-local-chatgpt-background", "active");
  const install = () => {
    let style = document.getElementById("local-chatgpt-background-style");
    if (!style) {
      style = document.createElement("style");
      style.id = "local-chatgpt-background-style";
    }
    const content = ${JSON.stringify(css)};
    if (style.textContent !== content) style.textContent = content;
    const parent = document.head || document.documentElement;
    if (style.parentNode !== parent) parent.appendChild(style);
    if (document.body) {
      const bodyStyle = document.body.style;
      bodyStyle.setProperty("background-color", "rgb(var(--local-chatgpt-overlay))", "important");
      bodyStyle.setProperty("background-image", ${JSON.stringify(`linear-gradient(rgb(var(--local-chatgpt-overlay) / ${shade}), rgb(var(--local-chatgpt-overlay) / ${shade})), url(${JSON.stringify(dataUrl)})`)}, "important");
      bodyStyle.setProperty("background-repeat", "no-repeat", "important");
      bodyStyle.setProperty("background-position", "center center", "important");
      bodyStyle.setProperty("background-size", "cover", "important");
      bodyStyle.setProperty("background-attachment", "fixed", "important");
    }
    const surfaces = document.querySelectorAll('.macos-window-backdrop, #root, #root > div, [data-app-shell-page-surface="true"], [data-app-shell-surface-backing="true"], [data-app-shell-tabs="true"] > div, [data-new-tab-scroll-root="true"], [class*="app-shell-content-fade-height"], .sidebar-navigation, main, [role="main"], aside.app-shell-left-panel, header:is(.app-header-tint, [data-app-shell-header-edge-scroll], [data-app-shell-titlebar="true"], [class*="_Header_"])');
    for (const node of surfaces) {
      node.style.setProperty("background-color", "transparent", "important");
      node.style.setProperty("background-image", "none", "important");
      node.style.setProperty("backdrop-filter", "none", "important");
    }
    for (const node of document.querySelectorAll('header[data-app-shell-titlebar="true"]')) {
      node.style.setProperty("background-color", "rgb(var(--local-chatgpt-overlay) / 0.08)", "important");
      node.style.setProperty("backdrop-filter", "blur(18px) saturate(120%)", "important");
      node.style.setProperty("text-shadow", "0 1px 4px rgb(0 0 0 / 0.45)", "important");
    }
  };
  install();
  window.__localChatGPTBackgroundObserver?.disconnect();
  let scheduled = false;
  const scheduleInstall = () => {
    if (scheduled) return;
    scheduled = true;
    setTimeout(() => {
      scheduled = false;
      install();
    }, 16);
  };
  const observer = new MutationObserver(scheduleInstall);
  window.__localChatGPTBackgroundObserver = observer;
  observer.observe(document.documentElement, { childList: true, subtree: true });
})()`;

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

class Session {
  constructor(target) {
    this.target = target;
    this.ws = new WebSocket(target.webSocketDebuggerUrl);
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = new Map();
    this.earlyScriptId = null;
    this.closed = false;
  }

  async open() {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => { this.ws.close(); reject(new Error("WebSocket 连接超时")); }, 5000);
      this.ws.addEventListener("open", () => { clearTimeout(timeout); resolve(); }, { once: true });
      this.ws.addEventListener("error", () => { clearTimeout(timeout); reject(new Error("WebSocket 连接失败")); }, { once: true });
    });
    this.ws.addEventListener("message", event => {
      const message = JSON.parse(String(event.data));
      if (!message.id) {
        for (const listener of this.listeners.get(message.method) || []) listener(message.params || {});
        return;
      }
      const waiter = this.pending.get(message.id);
      if (!waiter) return;
      this.pending.delete(message.id);
      clearTimeout(waiter.timeout);
      if (message.error) waiter.reject(new Error(message.error.message));
      else waiter.resolve(message.result);
    });
    this.ws.addEventListener("close", () => {
      this.closed = true;
      for (const waiter of this.pending.values()) {
        clearTimeout(waiter.timeout);
        waiter.reject(new Error("CDP 会话已关闭"));
      }
      this.pending.clear();
    });
    await this.send("Runtime.enable");
    await this.send("Page.enable");
    return this;
  }

  send(method, params = {}) {
    if (this.closed) return Promise.reject(new Error("CDP 会话已关闭"));
    return new Promise((resolve, reject) => {
      const id = this.nextId++;
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`CDP 命令超时: ${method}`));
      }, 10000);
      this.pending.set(id, { resolve, reject, timeout });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  on(method, listener) {
    const listeners = this.listeners.get(method) || [];
    listeners.push(listener);
    this.listeners.set(method, listeners);
  }

  async evaluate(expression) {
    const result = await this.send("Runtime.evaluate", {
      expression,
      returnByValue: true,
      awaitPromise: true,
    });
    if (result.exceptionDetails) throw new Error(result.exceptionDetails.text || "页面执行失败");
    return result.result?.value;
  }

  async removeEarlyScript() {
    const identifier = this.earlyScriptId;
    this.earlyScriptId = null;
    if (!identifier || this.closed) return;
    try {
      await this.send("Page.removeScriptToEvaluateOnNewDocument", { identifier });
    } catch {}
  }

  close() {
    this.closed = true;
    try { this.ws.close(); } catch {}
  }
}

async function targets() {
  const response = await fetch(`http://127.0.0.1:${port}/json/list`, {
    signal: AbortSignal.timeout(2000),
  });
  if (!response.ok) throw new Error(`CDP HTTP ${response.status}`);
  const items = await response.json();
  return items.filter(item =>
    item.type === "page" &&
    typeof item.url === "string" &&
    item.url.startsWith("app://") &&
    !item.url.includes("initialRoute=%2Favatar-overlay") &&
    typeof item.webSocketDebuggerUrl === "string" &&
    item.webSocketDebuggerUrl.startsWith(`ws://127.0.0.1:${port}/devtools/page/`)
  );
}

const sessions = new Map();
let applied = false;
let failures = 0;

async function cleanup() {
  await Promise.all([...sessions.values()].map(async session => {
    await session.removeEarlyScript();
    session.close();
  }));
  sessions.clear();
}
process.on("SIGTERM", async () => { await cleanup(); process.exit(0); });
process.on("SIGINT", async () => { await cleanup(); process.exit(0); });

while (true) {
  let current;
  try {
    current = await targets();
    failures = 0;
  } catch (error) {
    failures += 1;
    if (failures === 1 || failures % 10 === 0) console.error(error.message);
    if (failures >= 20) {
      await cleanup();
      process.exit(0);
    }
    await sleep(750);
    continue;
  }

  const activeIds = new Set(current.map(target => target.id));
  for (const [id, session] of sessions) {
    if (!activeIds.has(id) || session.closed) {
      await session.removeEarlyScript();
      session.close();
      sessions.delete(id);
    }
  }

  for (const target of current) {
    if (sessions.has(target.id)) continue;
    let session;
    try {
      session = await new Session(target).open();
      session.on("Page.loadEventFired", () => {
        session.evaluate(installSource).catch(error => console.error(`${target.id}: ${error.message}`));
      });
      const decoded = await session.evaluate(`(async () => {
        try {
          const image = new Image();
          image.src = ${JSON.stringify(dataUrl)};
          await image.decode();
          return image.naturalWidth > 0 && image.naturalHeight > 0;
        } catch {
          return false;
        }
      })()`);
      if (!decoded) {
        const error = new Error("图片无法解码，请使用有效的 JPG、PNG、WebP、GIF 或 AVIF 文件");
        error.code = "INVALID_IMAGE";
        throw error;
      }
      const early = await session.send("Page.addScriptToEvaluateOnNewDocument", { source: installSource });
      session.earlyScriptId = early.identifier ?? null;
      await session.evaluate(installSource);
      const verified = await session.evaluate(`(() => {
        const style = document.getElementById("local-chatgpt-background-style");
        return Boolean(style && getComputedStyle(document.body).backgroundImage.includes("data:${mime}"));
      })()`);
      if (!verified) throw new Error("背景样式未通过页面校验");
      sessions.set(target.id, session);
      if (!applied) {
        applied = true;
        await fs.writeFile(appliedFile, JSON.stringify({
          imagePath,
          transparency,
          targetId: target.id,
          appliedAt: new Date().toISOString(),
        }, null, 2) + "\n", { mode: 0o600 });
        console.log(`背景已应用: ${imagePath}; 透明度=${transparency}`);
      }
    } catch (error) {
      if (session) {
        await session.removeEarlyScript();
        session.close();
      }
      console.error(`${target.id}: ${error.message}`);
      if (error.code === "INVALID_IMAGE") {
        await cleanup();
        process.exit(1);
      }
    }
  }
  await sleep(1000);
}
NODE
WATCHER_PID=$!
printf '%s %s\n' "$WATCHER_PID" "$TOKEN" > "$PID_FILE"
chmod 600 "$PID_FILE"

for _ in $(seq 1 90); do
  [ -f "$APPLIED_FILE" ] && break
  if ! kill -0 "$WATCHER_PID" 2>/dev/null; then
    printf '注入进程已退出：\n' >&2
    cat "$LOG_FILE" >&2
    rm -f "$PID_FILE"
    exit 1
  fi
  sleep 0.5
done

if [ ! -f "$APPLIED_FILE" ]; then
  kill -TERM "$WATCHER_PID" 2>/dev/null || true
  rm -f "$PID_FILE"
  printf '背景应用超时：\n' >&2
  cat "$LOG_FILE" >&2
  exit 1
fi

printf '背景已应用：%s\n透明度：%s（0 最不透明，100 完全透明）\n' "$IMAGE_PATH" "$TRANSPARENCY"
printf '日志：%s\n' "$LOG_FILE"
