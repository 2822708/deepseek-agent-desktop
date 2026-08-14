# DeepSeek Agent Desktop - Multi-arch Build Script
# Produces: portable ZIP + NSIS installer for x64 and x86
#
# Usage:
#   .\build-all.ps1                 # Build everything
#   .\build-all.ps1 -Arch x64       # Build x64 only
#   .\build-all.ps1 -Arch x86       # Build x86 only
#   .\build-all.ps1 -SkipInstaller  # Portable only, skip NSIS
#   .\build-all.ps1 -Proxy "http://127.0.0.1:7890"   # Optional: specify a proxy

param(
    [ValidateSet("all","x64","x86")]
    [string]$Arch = "all",
    [switch]$SkipInstaller,
    [string]$Proxy = ""
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root
$toolsDir = Join-Path $root "_tools"
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

# --- Version ---
$versionLine = Get-Content (Join-Path $root 'config.py') | Select-String 'APP_VERSION' | Select-Object -First 1
if ($versionLine -match '"([^"]+)"') { $Version = $matches[1] } else { $Version = '0.0.0' }
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  DeepSeek Agent Desktop v$Version" -ForegroundColor Cyan
Write-Host "  Multi-arch Build Script" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# --- Download helper ---
function Download-File {
    param([string]$Url, [string]$OutPath, [string]$ProxyAddr = "")
    $params = @{ Uri = $Url; OutFile = $OutPath; UseBasicParsing = $true; TimeoutSec = 300 }
    if ($ProxyAddr) { $params.Proxy = $ProxyAddr }
    $retry = 0
    while ($retry -lt 3) {
        try {
            Invoke-WebRequest @params
            return $true
        } catch {
            $retry++
            Write-Host "  Download attempt $retry failed: $($_.Exception.Message)"
            if ($retry -lt 3) { Start-Sleep -Seconds 3 }
        }
    }
    return $false
}

# --- Ensure NSIS ---
function Ensure-NSIS {
    $nsisExe = Join-Path $toolsDir "nsis\makensis.exe"
    if (Test-Path $nsisExe) {
        Write-Host "[OK] NSIS found: $nsisExe" -ForegroundColor Green
        return $nsisExe
    }

    Write-Host "[..] Downloading NSIS 3.10..." -ForegroundColor Yellow
    $nsisZip = Join-Path $toolsDir "nsis-3.10.zip"
    $urls = @(
        "https://master.dl.sourceforge.net/project/nsis/NSIS%203/3.10/nsis-3.10.zip",
        "https://cfhcable.dl.sourceforge.net/project/nsis/NSIS%203/3.10/nsis-3.10.zip"
    )
    $downloaded = $false
    foreach ($url in $urls) {
        # Use curl for proper redirect following
        $proxyArg = if ($Proxy) { "-x $Proxy" } else { "" }
        & curl.exe -L $proxyArg -o $nsisZip --connect-timeout 15 --max-time 120 -s $url 2>&1
        if (Test-Path $nsisZip) {
            $bytes = [System.IO.File]::ReadAllBytes($nsisZip)[0..1]
            if ($bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B) {
                $downloaded = $true
                break
            }
            Remove-Item $nsisZip -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $downloaded) {
        Write-Host "[FAIL] Cannot download NSIS. Install manually from https://nsis.sourceforge.io" -ForegroundColor Red
        return $null
    }

    Write-Host "[..] Extracting NSIS..." -ForegroundColor Yellow
    Expand-Archive -Path $nsisZip -DestinationPath (Join-Path $toolsDir "nsis-tmp") -Force
    # NSIS zip extracts to nsis-3.10/ folder
    $extracted = Get-ChildItem (Join-Path $toolsDir "nsis-tmp") -Directory | Select-Object -First 1
    if ($extracted) {
        Move-Item $extracted.FullName (Join-Path $toolsDir "nsis") -Force
    }
    Remove-Item (Join-Path $toolsDir "nsis-tmp") -Recurse -Force -ErrorAction SilentlyContinue

    if (Test-Path $nsisExe) {
        Write-Host "[OK] NSIS installed: $nsisExe" -ForegroundColor Green
        return $nsisExe
    }
    Write-Host "[FAIL] NSIS extraction failed" -ForegroundColor Red
    return $null
}

# --- Ensure Python x86 (embeddable + pip bootstrap) ---
function Ensure-PythonX86 {
    $py86Dir = Join-Path $toolsDir "python311-x86"
    $py86Exe = Join-Path $py86Dir "python.exe"
    if (Test-Path $py86Exe) {
        # Verify pip is available
        & $py86Exe -m pip --version 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Python x86 found: $py86Exe" -ForegroundColor Green
            return $py86Exe
        }
    }

    Write-Host "[..] Downloading Python 3.11.9 embeddable (win32)..." -ForegroundColor Yellow
    $embZip = Join-Path $toolsDir "python-3.11.9-embed-win32.zip"
    $url = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-win32.zip"
    $proxyArg = if ($Proxy) { "-x $Proxy" } else { "" }
    & curl.exe -L $proxyArg -o $embZip --connect-timeout 15 --max-time 120 -s $url 2>&1
    if (-not (Test-Path $embZip)) {
        Write-Host "[FAIL] Cannot download Python x86 embeddable" -ForegroundColor Red
        return $null
    }

    Write-Host "[..] Extracting Python 3.11.9 (32-bit) to $py86Dir..." -ForegroundColor Yellow
    if (Test-Path $py86Dir) { Remove-Item $py86Dir -Recurse -Force }
    Expand-Archive -Path $embZip -DestinationPath $py86Dir -Force

    if (-not (Test-Path $py86Exe)) {
        Write-Host "[FAIL] Python x86 extraction failed" -ForegroundColor Red
        return $null
    }

    # Enable site-packages in _pth
    $pthFile = Join-Path $py86Dir "python311._pth"
    if (Test-Path $pthFile) {
        $content = Get-Content $pthFile -Raw
        $content = $content -replace '#import site', 'import site'
        Set-Content $pthFile $content -NoNewline
    }

    # Bootstrap pip
    Write-Host "[..] Bootstrapping pip for x86..." -ForegroundColor Yellow
    $getPip = Join-Path $py86Dir "get-pip.py"
    & curl.exe -L $proxyArg -o $getPip --connect-timeout 15 --max-time 60 -s "https://bootstrap.pypa.io/get-pip.py" 2>&1
    & $py86Exe $getPip --quiet 2>&1

    & $py86Exe -m pip --version 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Python x86 ready: $py86Exe" -ForegroundColor Green
        return $py86Exe
    }
    Write-Host "[FAIL] pip bootstrap failed for x86" -ForegroundColor Red
    return $null
}

# --- Build function ---
function Build-Arch {
    param(
        [string]$ArchLabel,   # "x64" or "x86"
        [string]$PythonExe,
        [string]$VenvName,
        [bool]$MakeInstaller,
        [string]$NsisExe
    )

    Write-Host "`n--- Building $ArchLabel ---`n" -ForegroundColor Cyan

    $venvDir = Join-Path $root $VenvName

    # 1. Create venv
    if (-not (Test-Path $venvDir)) {
        Write-Host "  Creating venv ($ArchLabel)..."
        & $PythonExe -m venv $venvDir
    }
    $py = Join-Path $venvDir "Scripts\python.exe"

    # 2. Install dependencies
    Write-Host "  Installing dependencies ($ArchLabel)..."
    & $py -m pip install --disable-pip-version-check -q --no-cache-dir --upgrade pip
    & $py -m pip install --disable-pip-version-check -q --no-cache-dir -r requirements.txt pyinstaller

    # 3. Build with PyInstaller
    Write-Host "  Building PyInstaller ($ArchLabel)..."
    $exeName = "DeepSeekAgentDesktop-$ArchLabel"
    & $py -m PyInstaller --noconfirm --clean --onefile --windowed `
        --name $exeName `
        --icon app.ico `
        --collect-all pystray `
        --collect-all clr_loader `
        --collect-all pythonnet `
        --collect-all webview `
        --hidden-import webview.platforms.edgechromium `
        --add-data "fallback.html;." `
        app.py

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [FAIL] PyInstaller build failed for $ArchLabel" -ForegroundColor Red
        return $false
    }

    $builtExe = Join-Path $root "dist\$exeName.exe"
    if (-not (Test-Path $builtExe)) {
        Write-Host "  [FAIL] Output not found: $builtExe" -ForegroundColor Red
        return $false
    }

    $sizeMB = [math]::Round((Get-Item $builtExe).Length / 1MB, 1)
    Write-Host "  [OK] Built: $exeName.exe ($sizeMB MB)" -ForegroundColor Green

    # 4. Create portable ZIP
    Write-Host "  Creating portable ZIP ($ArchLabel)..."
    $zipName = "DeepSeekAgentDesktop-$Version-Portable-$ArchLabel.zip"
    $zipPath = Join-Path $root "dist\$zipName"
    $stagingDir = Join-Path $root "dist\staging-$ArchLabel"
    New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

    Copy-Item $builtExe (Join-Path $stagingDir "DeepSeekAgentDesktop.exe") -Force
    Copy-Item (Join-Path $root "README.md") $stagingDir -Force
    Copy-Item (Join-Path $root "app.ico") $stagingDir -Force

    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $zipPath
    Remove-Item $stagingDir -Recurse -Force
    Write-Host "  [OK] Portable ZIP: $zipName" -ForegroundColor Green

    # 5. Create NSIS installer
    if ($MakeInstaller -and $NsisExe) {
        Write-Host "  Creating NSIS installer ($ArchLabel)..."
        & $NsisExe /DARCH=$ArchLabel /V2 installer.nsi
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [WARN] NSIS build failed for $ArchLabel" -ForegroundColor Yellow
        } else {
            $installerExe = Join-Path $root "dist\DeepSeekAgentDesktop-Setup-$ArchLabel.exe"
            if (Test-Path $installerExe) {
                $instSize = [math]::Round((Get-Item $installerExe).Length / 1MB, 1)
                Write-Host "  [OK] Installer: DeepSeekAgentDesktop-Setup-$ArchLabel.exe ($instSize MB)" -ForegroundColor Green
            }
        }
    }

    return $true
}

# --- Main ---
$buildX64 = ($Arch -eq "all" -or $Arch -eq "x64")
$buildX86 = ($Arch -eq "all" -or $Arch -eq "x86")

# Ensure NSIS for installer
$nsisExe = $null
if (-not $SkipInstaller) {
    $nsisExe = Ensure-NSIS
    if (-not $nsisExe) {
        Write-Host "`n[WARN] NSIS not available, will skip installer creation" -ForegroundColor Yellow
    }
}

# System Python (x64)
$py64 = Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path $py64)) {
    $py64 = "python"  # fallback to system python
}

$results = @{}

# Build x64
if ($buildX64) {
    $ok = Build-Arch -ArchLabel "x64" -PythonExe $py64 -VenvName ".venv" -MakeInstaller (-not $SkipInstaller) -NsisExe $nsisExe
    $results["x64"] = $ok
}

# Build x86
if ($buildX86) {
    $py86 = Ensure-PythonX86
    if ($py86) {
        $ok = Build-Arch -ArchLabel "x86" -PythonExe $py86 -VenvName ".venv-x86" -MakeInstaller (-not $SkipInstaller) -NsisExe $nsisExe
        $results["x86"] = $ok
    } else {
        Write-Host "`n[WARN] Skipping x86 build - Python x86 not available" -ForegroundColor Yellow
        Write-Host "  To enable x86 builds, install Python 3.11 32-bit and re-run." -ForegroundColor Yellow
        $results["x86"] = $false
    }
}

# --- Summary ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Build Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$distDir = Join-Path $root "dist"
if (Test-Path $distDir) {
    Get-ChildItem $distDir -File | Where-Object { $_.Extension -in ".exe",".zip" } | ForEach-Object {
        $sizeMB = [math]::Round($_.Length / 1MB, 1)
        $type = if ($_.Name -match "Setup") { "Installer" } elseif ($_.Name -match "Portable") { "Portable" } else { "Exe" }
        Write-Host ("  {0,-50} {1,8} MB  ({2})" -f $_.Name, $sizeMB, $type) -ForegroundColor Green
    }
} else {
    Write-Host "  No output files found" -ForegroundColor Red
}
Write-Host "========================================`n" -ForegroundColor Cyan