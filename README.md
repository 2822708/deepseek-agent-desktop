# DeepSeek Agent 桌面版

> 🚀 **最新版本 v1.1.0**：支持 **x64 + x86 双架构**，提供 **安装版 + 便携版** 两种分发方式。
> 📦 [下载 Release](https://github.com/2822708/deepseek-agent-desktop/releases/latest) · 📋 [项目报告](PROJECT_REPORT.md)

把 DeepSeek Harness 的 Web 界面（`http://127.0.0.1:3080`）包装成原生 Windows 桌面应用。

- 内核：系统 WebView2 (EdgeChromium)，无需内置浏览器
- 后端在线 → 直接加载完整 agent 界面（会话、工具、目标管理全都有）
- 后端离线 → 显示本地提示页，可一键「重试连接」或「启动后端」（自动执行 `dsh web`）

## 系统要求

| 要求 | 说明 |
| --- | --- |
| 操作系统 | Windows 10 1803+ / Windows 11（x64 或 x86） |
| WebView2 Runtime | 渲染内核，Win11 和较新 Win10 已预装；旧系统需手动安装 |
| .NET Framework | pythonnet 直接使用系统内置的 .NET Framework（Win10/11 自带 4.8），**一般无需额外安装** |

> **安装版（Setup）** 会在安装时自动检测 WebView2 Runtime 和 .NET Framework，
> 若缺失则从微软官方服务器下载并静默安装（仅极少数精简系统会触发）。安装过程需要联网。
> 若自动安装失败（如无网络），会弹窗提示手动安装链接。
>
> **便携版（Portable ZIP）** 不包含运行时自动安装逻辑，请确保目标电脑已安装 WebView2 Runtime。

### 手动安装运行时（便携版用户或自动安装失败时）

| 组件 | 下载地址 |
| --- | --- |
| WebView2 Runtime | <https://developer.microsoft.com/microsoft-edge/webview2/> |

安装方法：下载后双击运行，按提示完成安装即可。

## 下载与安装

### 安装版（推荐）

从 [Releases](https://github.com/2822708/deepseek-agent-desktop/releases) 下载对应架构的安装包：

| 文件 | 架构 | 适用系统 |
| --- | --- | --- |
| `DeepSeekAgentDesktop-Setup-x64.exe` | 64 位 | Win10/11 64 位 |
| `DeepSeekAgentDesktop-Setup-x86.exe` | 32 位 | Win10/11 32 位或 64 位 |

安装过程：

1. 双击 `Setup-xxx.exe` 运行安装程序
2. 选择安装目录（默认 `C:\Program Files\DeepSeek Agent`）
3. 安装程序自动检测并安装 WebView2 Runtime（如缺失）
4. 可选：勾选「开机自启」
5. 安装完成后可立即启动

安装后可在「开始菜单 → DeepSeek Agent」或桌面快捷方式启动。

### 便携版

| 文件 | 架构 |
| --- | --- |
| `DeepSeekAgentDesktop-1.1.0-Portable-x64.zip` | 64 位 |
| `DeepSeekAgentDesktop-1.1.0-Portable-x86.zip` | 32 位 |

解压后双击 `DeepSeekAgentDesktop.exe` 即可运行，无需安装。
但需确保系统已安装 WebView2 Runtime（见上文）。

## 构建

### 一键构建（多架构 + 安装包）

```powershell
# 构建全部（x64+x86，便携版+安装版）
.\build-all.ps1

# 仅构建 x64
.\build-all.ps1 -Arch x64

# 仅便携版（跳过 NSIS 安装包）
.\build-all.ps1 -SkipInstaller

# 若网络下载超时（构建需下载 NSIS / Python x86），可显式指定代理
.\build-all.ps1 -Proxy "http://127.0.0.1:7890"
```

构建脚本会自动下载所需工具（NSIS、Python 3.11 x86 embeddable）到 `_tools/` 目录。

产物：

| 文件 | 类型 | 说明 |
| --- | --- | --- |
| `dist\DeepSeekAgentDesktop-Setup-x64.exe` | 安装版 | 64 位 NSIS 安装包 |
| `dist\DeepSeekAgentDesktop-Setup-x86.exe` | 安装版 | 32 位 NSIS 安装包 |
| `dist\DeepSeekAgentDesktop-1.1.0-Portable-x64.zip` | 便携版 | 64 位免安装 |
| `dist\DeepSeekAgentDesktop-1.1.0-Portable-x86.zip` | 便携版 | 32 位免安装 |

### 简单构建（仅 x64 单文件）

```powershell
.\build.ps1
```

产物：`dist\DeepSeekAgentDesktop.exe`（单文件，免安装，双击即用）。

> 注：构建脚本已内置清华 PyPI 镜像（`PIP_INDEX_URL`）。若你机器上 pip 因缓存损坏导致
> 「from versions: none」或反复超时，先清缓存：`pip cache purge`。

## 功能特性

- **自动健康检查**：后台线程定期探测后端状态，断连时自动切换到提示页
- **系统托盘集成**：最小化到托盘，红/绿图标显示后端连接状态
- **运行时切换 URL**：在提示页输入框中实时修改后端地址，无需重启
- **自动轮询重连**：提示页每 3 秒自动探测后端，就绪后自动跳转
- **状态可视化**：提示页显示探测次数、延迟、上次检测时间
- **旋转日志**：`RotatingFileHandler`（2MB x 5 份），Debug 模式同时输出到控制台

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

## 项目结构

```
dsh-desktop/
├── app.py                  # 主应用（窗口创建、API、托盘、健康检查）
├── config.py               # 集中配置（版本号、窗口尺寸、超时等）
├── fallback.html           # 离线提示页（自动轮询、状态可视化、URL 切换）
├── requirements.txt        # Python 依赖
├── build.ps1               # 简单构建脚本（仅 x64 单文件）
├── build-all.ps1           # 多架构构建脚本（x64+x86，便携+安装）
├── installer.nsi           # NSIS 安装包脚本（含运行时自动安装）
├── app.ico                 # 应用图标（DeepSeek 鲸鱼）
├── DeepSeekAgentDesktop.spec  # PyInstaller 配置
└── dist/                   # 构建产物
```
