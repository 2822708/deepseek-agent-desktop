# -*- coding: utf-8 -*-
"""
DeepSeek Agent 桌面版
=====================
DSH (DeepSeek Harness) Web GUI 的桌面壳：
用系统 WebView2 (EdgeChromium) 把后端 Web 界面包装成原生桌面窗口。

特性：
- 后端在线  -> 直接加载 Web GUI
- 后端离线  -> 显示本地 fallback 页，自动轮询 + 一键启动后端
- 运行时健康检查 + 系统托盘状态指示
- 支持运行时切换后端 URL

打包: pyinstaller --onefile --windowed app.py (见 build.ps1)
"""

import json
import logging
import os
import shutil
import subprocess
import sys
import threading
import time
import urllib.request
from logging.handlers import RotatingFileHandler
from string import Template

import webview

from config import (
    APP_ID,
    APP_TITLE,
    APP_VERSION,
    DEFAULT_BACKEND_URL,
    HEALTH_CHECK_INTERVAL,
    HEALTH_CHECK_TIMEOUT,
    LOG_BACKUP_COUNT,
    LOG_FILE,
    LOG_MAX_BYTES,
    WINDOW_BG_COLOR,
    WINDOW_HEIGHT,
    WINDOW_MIN_SIZE,
    WINDOW_WIDTH,
    is_debug,
    resource_path,
)

log = logging.getLogger("dsh-desktop")


class BackendState:
    """后端状态管理器（线程安全）。"""

    def __init__(self, url: str) -> None:
        self._url = url
        self._up = False
        self._lock = threading.Lock()
        self._last_check = 0.0
        self._latency_ms = 0
        self._retry_count = 0

    @property
    def url(self) -> str:
        return self._url

    def set_url(self, url: str) -> None:
        with self._lock:
            self._url = url
            self._retry_count = 0

    @property
    def is_up(self) -> bool:
        with self._lock:
            return self._up

    @property
    def last_check(self) -> float:
        with self._lock:
            return self._last_check

    @property
    def latency_ms(self) -> int:
        with self._lock:
            return self._latency_ms

    @property
    def retry_count(self) -> int:
        with self._lock:
            return self._retry_count

    def check(self) -> bool:
        """探测后端是否在线，返回状态。"""
        with self._lock:
            self._retry_count += 1
            self._last_check = time.time()
        try:
            start = time.time()
            with urllib.request.urlopen(self._url, timeout=HEALTH_CHECK_TIMEOUT) as resp:
                ok = resp.status < 500
            latency = round((time.time() - start) * 1000)
        except Exception:
            ok = False
            latency = 0

        with self._lock:
            self._up = ok
            self._latency_ms = latency
        return ok


def load_fallback_html(backend_url: str) -> str:
    """加载 fallback.html 并替换后端 URL。"""
    html_path = resource_path("fallback.html")
    try:
        with open(html_path, encoding="utf-8") as f:
            template = Template(f.read())
    except FileNotFoundError:
        logging.error("fallback.html not found at %s", html_path)
        return f"<html><body><p>资源文件缺失: fallback.html ({html_path})</p></body></html>"
    return template.safe_substitute(backend_url=backend_url)


def find_dsh() -> str | None:
    """定位 dsh 可执行文件。"""
    for name in ("dsh.cmd", "dsh.exe", "dsh.bat", "dsh"):
        path = shutil.which(name)
        if path:
            return path
    return None


def launch_backend_cmd() -> list[str] | None:
    """返回用于启动后端的命令参数列表（无 shell=True）。"""
    dsh = find_dsh()
    if not dsh:
        return None
    return [dsh, "web"]


class Api:
    """暴露给 fallback 页面调用的 JS API。"""

    def __init__(self, state: BackendState) -> None:
        self._state = state
        self._window = None

    def attach(self, window) -> None:
        self._window = window

    def backend_up(self) -> bool:
        return self._state.check()

    def launch_backend(self) -> str:
        """尝试启动 dsh web。"""
        cmd = launch_backend_cmd()
        if not cmd:
            return "no-dsh"
        try:
            subprocess.Popen(
                cmd,
                shell=False,
                cwd=os.path.expanduser("~"),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                creationflags=subprocess.CREATE_NO_WINDOW | subprocess.DETACHED_PROCESS,
            )
            log.info("launched backend: %s", cmd)
            return "launched"
        except Exception as exc:
            log.exception("launch backend failed")
            return f"error: {exc}"

    def get_status(self) -> str:
        """返回后端状态 JSON。"""
        with self._state._lock:
            return json.dumps({
                "up": self._state._up,
                "url": self._state._url,
                "last_check": self._state._last_check,
                "latency_ms": self._state._latency_ms,
                "retry_count": self._state._retry_count,
            })

    def set_backend_url(self, url: str) -> bool:
        """运行时切换后端地址。"""
        if not url or not isinstance(url, str):
            return False
        url = url.strip()
        if not url.startswith(("http://", "https://")):
            return False
        self._state.set_url(url)
        log.info("backend URL changed to: %s", url)
        return True


def health_check_loop(state: BackendState, window: webview.Window) -> None:
    """后台健康检查循环（pywebview 的 set_html/evaluate_js 线程安全）。"""
    was_up = False
    while True:
        try:
            is_up = state.check()
            if is_up != was_up:
                was_up = is_up
                log.info("backend state changed: up=%s url=%s", is_up, state.url)
                if not is_up:
                    # 后端宕机 → 切换到 fallback（set_html 线程安全）
                    try:
                        html = load_fallback_html(state.url)
                        window.set_html(html)
                    except Exception:
                        log.exception("failed to set fallback html")
                # 后端恢复在线 → fallback 页面的 JS 自动轮询会自行跳转
            # 更新托盘图标
            try:
                update_tray_icon(is_up)
            except Exception:
                pass
        except Exception:
            log.exception("health check loop error")
        time.sleep(HEALTH_CHECK_INTERVAL)


# --- Tray integration (optional, falls back gracefully) ---
_tray_icon = None
_tray_thread = None


def _create_tray_image(online: bool) -> "PIL.Image.Image | None":
    """创建托盘图标（纯色圆点）。"""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        return None
    size = 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    color = (63, 185, 80, 255) if online else (248, 81, 73, 255)
    draw.ellipse((8, 8, size - 8, size - 8), fill=color)
    return img


def update_tray_icon(online: bool) -> None:
    """更新托盘图标状态。"""
    global _tray_icon
    if _tray_icon is None:
        return
    img = _create_tray_image(online)
    if img:
        try:
            _tray_icon.icon = img
        except Exception:
            pass
    _tray_icon.update_menu()


def setup_tray(state: BackendState, window: webview.Window) -> None:
    """初始化系统托盘（如果 pystray 可用）。"""
    global _tray_icon, _tray_thread
    try:
        import pystray
    except ImportError:
        log.warning("pystray not installed, tray integration disabled")
        return

    menu = pystray.Menu(
        pystray.MenuItem("显示窗口", lambda icon, item: _show_window(window), default=True),
        pystray.MenuItem("启动后端", lambda icon, item: _launch_backend_from_tray(state)),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("退出", lambda icon, item: _exit_app(window)),
    )

    _tray_icon = pystray.Icon(APP_ID, _create_tray_image(False), APP_TITLE, menu)

    def run_tray() -> None:
        try:
            _tray_icon.run()
        except Exception:
            log.exception("tray icon error")

    _tray_thread = threading.Thread(target=run_tray, daemon=True)
    _tray_thread.start()
    log.info("tray icon started")


def _show_window(window: webview.Window) -> None:
    try:
        if window:
            window.show()
            window.restore()
        # Bring to front on Windows
        if sys.platform == "win32":
            import ctypes
            user32 = ctypes.windll.user32
            user32.ShowWindow(window.hwnd, 9)  # SW_RESTORE
            user32.SetForegroundWindow(window.hwnd)
    except Exception:
        log.exception("show window error")


def _launch_backend_from_tray(state: BackendState) -> None:
    cmd = launch_backend_cmd()
    if not cmd:
        log.warning("no dsh found for tray launch")
        return
    try:
        subprocess.Popen(
            cmd,
            shell=False,
            cwd=os.path.expanduser("~"),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=subprocess.CREATE_NO_WINDOW | subprocess.DETACHED_PROCESS,
        )
        log.info("launched backend from tray: %s", cmd)
    except Exception:
        log.exception("tray launch backend failed")


def _exit_app(window: webview.Window) -> None:
    """退出应用：先停止托盘图标并等待其线程清理，再销毁窗口。"""
    global _tray_icon, _tray_thread
    if _tray_icon is not None:
        try:
            _tray_icon.stop()
        except Exception:
            log.exception("tray icon stop error")
        # 等待托盘线程结束，确保图标已从通知区域移除，避免残影
        # （若退出由托盘菜单触发，则回调本身就在该线程内，无需 join）
        if _tray_thread is not None and _tray_thread is not threading.current_thread():
            try:
                _tray_thread.join(timeout=3.0)
            except Exception:
                pass
        _tray_icon = None
    try:
        if window:
            window.destroy()
    except Exception:
        pass
    sys.exit(0)


# --- Logging setup ---
def setup_logging() -> None:
    """配置滚动日志。"""
    log_dir = os.path.dirname(LOG_FILE)
    if log_dir and not os.path.exists(log_dir):
        os.makedirs(log_dir, exist_ok=True)

    handlers: list[logging.Handler] = [
        RotatingFileHandler(
            LOG_FILE,
            maxBytes=LOG_MAX_BYTES,
            backupCount=LOG_BACKUP_COUNT,
            encoding="utf-8",
        ),
    ]
    if is_debug():
        handlers.append(logging.StreamHandler(sys.stderr))

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        handlers=handlers,
    )


# --- Main ---
def main() -> None:
    setup_logging()

    log.info("starting %s v%s", APP_TITLE, APP_VERSION)

    debug = is_debug()
    backend_state = BackendState(DEFAULT_BACKEND_URL)

    api = Api(backend_state)
    backend_up = backend_state.check()

    if backend_up:
        start_url = backend_state.url
        log.info("backend online, loading %s", start_url)
    else:
        start_url = load_fallback_html(backend_state.url)
        log.info("backend offline, showing fallback")

    window = webview.create_window(
        APP_TITLE,
        start_url,
        width=WINDOW_WIDTH,
        height=WINDOW_HEIGHT,
        min_size=WINDOW_MIN_SIZE,
        js_api=api,
        background_color=WINDOW_BG_COLOR,
        text_select=False,
    )
    api.attach(window)

    # Setup system tray
    setup_tray(backend_state, window)

    # Start background health check thread
    health_thread = threading.Thread(
        target=health_check_loop,
        args=(backend_state, window),
        daemon=True,
    )
    health_thread.start()

    # Handle window close → minimize to tray (use 'closing' to prevent destruction)
    def on_window_closing() -> bool:
        log.info("window closing, minimizing to tray")
        if _tray_icon:
            try:
                window.hide()
                return False  # Prevent actual close
            except Exception:
                pass
        _exit_app(window)
        return True

    window.events.closing += on_window_closing

    webview.start(debug=debug, private_mode=False)


if __name__ == "__main__":
    main()