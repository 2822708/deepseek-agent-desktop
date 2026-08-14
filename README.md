# DeepSeek Agent 桌面版

把 DeepSeek Harness 的 Web 界面（`http://127.0.0.1:3080`）包装成原生 Windows 桌面应用。

- 内核：系统 WebView2 (EdgeChromium)，无需内置浏览器
- 后端在线 → 直接加载完整 agent 界面（会话、工具、目标管理全都有）
- 后端离线 → 显示本地提示页，可一键「重试连接」或「启动后端」（自动执行 `dsh web`）

## 构建

```powershell
.\build.ps1
```

产物：`dist\DeepSeekAgentDesktop.exe`（单文件，免安装，双击即用）。

依赖：Python 3.10+、Windows 10/11（自带 WebView2 Runtime）。

> 注：构建脚本已内置清华 PyPI 镜像（`PIP_INDEX_URL`）。若你机器上 pip 因缓存损坏导致
> 「from versions: none」或反复超时，先清缓存：`pip cache purge`。

## 已构建产物

当前仓库里已经打包好一版可直接运行的：

```
dist\DeepSeekAgentDesktop.exe   (约 13.5 MB, 单文件)
```

双击启动后：后端在线（`dsh web` 已跑）则直接进入对话界面；后端离线则显示提示页，
可点「启动后端」自动执行 `dsh web`。

## 开发运行

```powershell
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
.\.venv\Scripts\python app.py
```

环境变量：

| 变量 | 作用 |
| --- | --- |
| `DSH_WEB_URL` | 后端地址，默认 `http://127.0.0.1:3080` |
| `DSH_DESKTOP_DEBUG=1` | 调试模式（打开 DevTools、保留控制台） |

日志：`%USERPROFILE%\.dsh-desktop.log`
