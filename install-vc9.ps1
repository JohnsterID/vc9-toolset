<#
.SYNOPSIS
    Install VC9 SP1 (VS2008 SP1) toolchain for Visual Studio 2010-2022

.DESCRIPTION
    Downloads and installs:
    1. VC9 SP1 compiler from Windows SDK 7.0
    2. MSBuild v90 toolset (bundled in this repository)

    After installation, set PlatformToolset=v90 in your project.

.PARAMETER IncludeMFC
    Also install MFC Feature Pack from VS2008 SP1 (optional)

.EXAMPLE
    .\install-vc9.ps1

.EXAMPLE
    .\install-vc9.ps1 -IncludeMFC
#>

param(
    [switch]$IncludeMFC
)

$ErrorActionPreference = "Stop"

# Require admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires Administrator privileges. Right-click and 'Run as Administrator'."
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempDir = "$env:TEMP\vc9-install"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

Write-Host "=== VC9 SP1 Installer ===" -ForegroundColor Cyan
Write-Host ""

# File names, URLs, and sizes
$SDK70_NAME = "GRMSDK_EN_DVD.iso"
# NOTE: archive.org/grmsdkx-en-dvd is SDK 7.1 (VC10) — do NOT use that.
# The correct SDK 7.0 ISO is ~1.48 GB (contains VC9 SP1 15.0.30729.1).
$SDK70_URL = "https://web.archive.org/web/20161230154527/http://download.microsoft.com/download/2/E/9/2E911956-F90F-4BFB-8231-E292A7B6F287/GRMSDK_EN_DVD.iso"
$SDK70_SIZE = 1552508928  # ~1.48 GB

function Get-OrDownload {
    param($FileName, $Url, $ExpectedSize)
    
    # Check if file exists next to script
    $localPath = Join-Path $ScriptDir $FileName
    if (Test-Path $localPath) {
        $size = (Get-Item $localPath).Length
        if ($size -eq $ExpectedSize) {
            Write-Host "  Using local: $FileName" -ForegroundColor Green
            return $localPath
        }
        Write-Host "  Local $FileName wrong size, will download..." -ForegroundColor Yellow
    }
    
    # Check temp directory
    $tempPath = Join-Path $TempDir $FileName
    if (Test-Path $tempPath) {
        $size = (Get-Item $tempPath).Length
        if ($size -eq $ExpectedSize) {
            Write-Host "  Using cached: $tempPath" -ForegroundColor Gray
            return $tempPath
        }
        Write-Host "  Cached file incomplete, re-downloading..." -ForegroundColor Yellow
        Remove-Item $tempPath
    }
    
    # Download
    Write-Host "  Downloading: $Url"
    Write-Host "  (This may take a while...)" -ForegroundColor Gray
    try {
        Start-BitsTransfer -Source $Url -Destination $tempPath -DisplayName "Downloading $FileName"
    } catch {
        Write-Host "  BITS failed, using WebRequest..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $Url -OutFile $tempPath -UseBasicParsing
    }
    return $tempPath
}

function Mount-IsoAndGetPath {
    param($IsoPath)
    $mount = Mount-DiskImage -ImagePath $IsoPath -PassThru
    $drive = ($mount | Get-Volume).DriveLetter
    return "${drive}:"
}

# ============================================
# Step 1: Download and install VC9 from SDK 7.0
# ============================================
Write-Host "[1/3] Installing VC9 SP1 from Windows SDK 7.0..." -ForegroundColor Green

$SDK70_Path = Get-OrDownload -FileName $SDK70_NAME -Url $SDK70_URL -ExpectedSize $SDK70_SIZE

Write-Host "  Mounting SDK 7.0 ISO..."
$sdkDrive = Mount-IsoAndGetPath $SDK70_Path

try {
    Write-Host "  Installing vc_stdx86.msi (VC9 x86 compiler)..."
    Start-Process msiexec -ArgumentList "/i `"$sdkDrive\Setup\vc_stdx86\vc_stdx86.msi`" /qb" -Wait
    
    Write-Host "  Installing vc_stdamd64.msi (VC9 x64 cross-compiler)..."
    Start-Process msiexec -ArgumentList "/i `"$sdkDrive\Setup\vc_stdamd64\vc_stdamd64.msi`" /qb" -Wait
} finally {
    Dismount-DiskImage -ImagePath $SDK70_Path | Out-Null
}

# Verify installation
$VCInstallDir = "${env:ProgramFiles(x86)}\Microsoft Visual Studio 9.0\VC\"
$VSInstallDir = "${env:ProgramFiles(x86)}\Microsoft Visual Studio 9.0\"
$clPath = "${VCInstallDir}bin\cl.exe"
if (-not (Test-Path $clPath)) {
    Write-Error "VC9 installation failed - cl.exe not found"
    exit 1
}
Write-Host "  VC9 installed: $clPath" -ForegroundColor Gray

# Set registry keys for MSBuild to find VC9
# The props file reads these to set VCInstallDir and VSInstallDir
Write-Host "  Setting registry keys for MSBuild..."
$regPath = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\9.0\Setup\VC"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
Set-ItemProperty -Path $regPath -Name "ProductDir" -Value $VCInstallDir

$regPathVS = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\9.0\Setup\VS"
if (-not (Test-Path $regPathVS)) {
    New-Item -Path $regPathVS -Force | Out-Null
}
Set-ItemProperty -Path $regPathVS -Name "ProductDir" -Value $VSInstallDir

# Create Common7\Tools\vsvars32.bat for build scripts that use VS90COMNTOOLS
$commonTools = "${VSInstallDir}Common7\Tools\"
New-Item -ItemType Directory -Force -Path $commonTools | Out-Null

$vsvars32Content = @'
@echo off
:: vsvars32.bat - Set up VC9 SP1 environment (created by vc9-msbuild-toolset)

set "VSINSTALLDIR=%~dp0..\.."
set "VCINSTALLDIR=%VSINSTALLDIR%VC\"

:: Get Windows SDK path from registry
for /f "tokens=2*" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Microsoft SDKs\Windows" /v CurrentInstallFolder 2^>nul') do set "WindowsSdkDir=%%b"
if "%WindowsSdkDir%"=="" for /f "tokens=2*" %%a in ('reg query "HKLM\SOFTWARE\Wow6432Node\Microsoft\Microsoft SDKs\Windows" /v CurrentInstallFolder 2^>nul') do set "WindowsSdkDir=%%b"

:: Get .NET Framework path
for /f "tokens=2*" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\.NETFramework" /v InstallRoot 2^>nul') do set "FrameworkDir=%%b"
if "%FrameworkDir%"=="" for /f "tokens=2*" %%a in ('reg query "HKLM\SOFTWARE\Wow6432Node\Microsoft\.NETFramework" /v InstallRoot 2^>nul') do set "FrameworkDir=%%b"
set "FrameworkVersion=v2.0.50727"
set "Framework35Version=v3.5"

@echo Setting environment for using Microsoft Visual Studio 2008 x86 tools.

set "PATH=%VCINSTALLDIR%bin;%WindowsSdkDir%bin;%FrameworkDir%%Framework35Version%;%FrameworkDir%%FrameworkVersion%;%PATH%"
set "INCLUDE=%VCINSTALLDIR%include;%WindowsSdkDir%include;%INCLUDE%"
set "LIB=%VCINSTALLDIR%lib;%WindowsSdkDir%lib;%LIB%"
set "LIBPATH=%FrameworkDir%%Framework35Version%;%FrameworkDir%%FrameworkVersion%;%VCINSTALLDIR%lib;%LIBPATH%"
'@

$vsvars32Content | Out-File -FilePath "${commonTools}vsvars32.bat" -Encoding ASCII
Write-Host "  Created: ${commonTools}vsvars32.bat" -ForegroundColor Gray

# Set VS90COMNTOOLS environment variable
[Environment]::SetEnvironmentVariable("VS90COMNTOOLS", $commonTools, "Machine")
Write-Host "  VS90COMNTOOLS = $commonTools" -ForegroundColor Gray

# ============================================
# Step 2: Install MSBuild v90 toolset (from repo)
# ============================================
Write-Host "[2/3] Installing MSBuild v90 toolset..." -ForegroundColor Green

$msbuildSrc = Join-Path $ScriptDir "MSBuild\v90"
if (-not (Test-Path "$msbuildSrc\Microsoft.Cpp.Win32.v90.props")) {
    Write-Error "MSBuild v90 files not found at $msbuildSrc. Repository may be incomplete."
    exit 1
}

# Install to all MSBuild platform toolset locations
# The legacy path (v4.0\Platforms) is checked by all VS versions including VS2022
$toolsetDirs = @(
    # Legacy path - works for VS2010-VS2022 (primary location)
    "${env:ProgramFiles(x86)}\MSBuild\Microsoft.Cpp\v4.0\Platforms\Win32\PlatformToolsets\v90"
    # VS2012-specific
    "${env:ProgramFiles(x86)}\MSBuild\Microsoft.Cpp\v4.0\V110\Platforms\Win32\PlatformToolsets\v90"
    # VS2013-specific
    "${env:ProgramFiles(x86)}\MSBuild\Microsoft.Cpp\v4.0\V120\Platforms\Win32\PlatformToolsets\v90"
    # VS2015-specific
    "${env:ProgramFiles(x86)}\MSBuild\Microsoft.Cpp\v4.0\V140\Platforms\Win32\PlatformToolsets\v90"
)

foreach ($dir in $toolsetDirs) {
    $parentDir = Split-Path $dir -Parent
    if (Test-Path $parentDir) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Copy-Item "$msbuildSrc\Microsoft.Cpp.Win32.v90.props" "$dir\Microsoft.Cpp.Win32.v90.props" -Force
        Copy-Item "$msbuildSrc\Microsoft.Cpp.Win32.v90.targets" "$dir\Microsoft.Cpp.Win32.v90.targets" -Force
        Write-Host "  Installed to: $dir" -ForegroundColor Gray
    }
}

# ============================================
# Step 3 (Optional): Install MFC Feature Pack
# ============================================
if ($IncludeMFC) {
    Write-Host "[3/3] MFC Feature Pack..." -ForegroundColor Green
    Write-Host "  MFC Feature Pack extraction is not yet automated." -ForegroundColor Yellow
    Write-Host "  For pre-extracted MFC SP1 files, see:" -ForegroundColor Yellow
    Write-Host "    https://github.com/archaic-msvc/msvc900 (msvc900_sp1 branch)" -ForegroundColor Cyan
} else {
    Write-Host "[3/3] Skipping MFC Feature Pack (use -IncludeMFC to install)" -ForegroundColor Gray
}

# ============================================
# Done
# ============================================
Write-Host ""
Write-Host "=== Installation Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "VC9 SP1 (15.0.30729.1) installed to:"
Write-Host "  ${env:ProgramFiles(x86)}\Microsoft Visual Studio 9.0\VC\"
Write-Host ""
Write-Host "MSBuild v90 toolset installed to legacy path (works with VS2010-2022)"
Write-Host ""
Write-Host "Usage:"
Write-Host "  Project Properties -> General -> Platform Toolset -> Visual Studio 2008 (v90)"
Write-Host "  Or in .vcxproj: <PlatformToolset>v90</PlatformToolset>"
Write-Host ""

# Cleanup option
$cleanup = Read-Host "Delete downloaded ISO (~1.5GB)? [y/N]"
if ($cleanup -eq 'y' -or $cleanup -eq 'Y') {
    Remove-Item -Recurse -Force $TempDir
    Write-Host "Cleaned up temp files."
}
