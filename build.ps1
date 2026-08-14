# DeepSeek Agent Desktop - one-shot build (Windows)
# Output: dist\DeepSeekAgentDesktop.exe (single file, no install)
#
# Usage:
#   .\build.ps1                          # default build
#   .\build.ps1 -Mirror ''               # skip Tsinghua mirror
#   .\build.ps1 -Debug                   # debug build (console + devtools)

param(
    [string]$Mirror = 'https://pypi.tuna.tsinghua.edu.cn/simple',
    [switch]$Debug
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

if ($Mirror) {
    $env:PIP_INDEX_URL = $Mirror
    Write-Host "Using PyPI mirror: $Mirror"
}

# Read version from config.py
$versionLine = Get-Content config.py | Select-String 'APP_VERSION' | Select-Object -First 1
if ($versionLine -match '"([^"]+)"') {
    $Version = $matches[1]
} else {
    $Version = '0.0.0'
}
Write-Host "Building version: $Version"

Write-Host "==> 1/4 create venv .venv (skip if exists)"
if (-not (Test-Path '.venv')) { python -m venv .venv }

$py = Join-Path $root '.venv\Scripts\python.exe'

Write-Host "==> 2/4 install dependencies"
& $py -m pip install --disable-pip-version-check -q --no-cache-dir --upgrade pip
& $py -m pip install --disable-pip-version-check -q --no-cache-dir -r requirements.txt pyinstaller

Write-Host "==> 3/4 package (PyInstaller onefile)"
if ($Debug) {
    Write-Host "    Debug mode: console enabled, devtools available"
    & $py -m PyInstaller --noconfirm --clean --onefile `
        --name DeepSeekAgentDesktop `
        --icon app.ico `
        --collect-all pystray `
        --collect-all clr_loader `
        --collect-all pythonnet `
        --collect-all webview `
        --add-data "fallback.html;." `
        app.py
} else {
    & $py -m PyInstaller --noconfirm --clean --onefile --windowed `
        --name DeepSeekAgentDesktop `
        --icon app.ico `
        --collect-all pystray `
        --collect-all clr_loader `
        --collect-all pythonnet `
        --collect-all webview `
        --add-data "fallback.html;." `
        app.py
}

Write-Host "==> 4/4 done"
$exe = Join-Path $root 'dist\DeepSeekAgentDesktop.exe'
if (Test-Path $exe) {
    $size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
    Write-Host "Output: $exe ($size MB, v$Version)"
} else {
    Write-Error 'build failed: output not found'
    exit 1
}