# -*- coding: utf-8 -*-
"""集中配置与常量。"""
import os
import sys

APP_TITLE = "DeepSeek Agent"
APP_VERSION = "1.1.0"
APP_ID = "com.deepseek.agent.desktop"

DEFAULT_BACKEND_URL = os.environ.get("DSH_WEB_URL", "http://127.0.0.1:3080")

WINDOW_WIDTH = 1280
WINDOW_HEIGHT = 840
WINDOW_MIN_SIZE = (960, 600)
WINDOW_BG_COLOR = "#0d1117"

HEALTH_CHECK_INTERVAL = 3.0
HEALTH_CHECK_TIMEOUT = 1.5
FALLBACK_AUTO_RETRY_INTERVAL = 3.0

LOG_FILE = os.path.join(os.path.expanduser("~"), ".dsh-desktop.log")
LOG_MAX_BYTES = 2 * 1024 * 1024
LOG_BACKUP_COUNT = 5


def resource_path(relative_path: str) -> str:
    """获取资源文件的绝对路径（兼容 PyInstaller 打包）。"""
    if getattr(sys, "frozen", False):
        base_path = sys._MEIPASS
    else:
        base_path = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(base_path, relative_path)


def is_debug() -> bool:
    return os.environ.get("DSH_DESKTOP_DEBUG") == "1"