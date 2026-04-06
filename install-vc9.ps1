<#
.SYNOPSIS
    Install VC9 SP1 (VS2008 SP1) toolchain for Visual Studio 2010-2022

.DESCRIPTION
    Downloads and installs:
    1. VC9 SP1 compiler from Windows SDK 7.0
    2. MSBuild v90 toolset (bundled in this repository)

    Optional add-ons from VS2008 SP1 (~832 MB download):
    3. Debug CRT libs/DLLs (-IncludeDebugCRT)

    After installation, set PlatformToolset=v90 in your project.

.PARAMETER IsoPath
    Path to an already-downloaded SDK 7.0 ISO. Skips download if provided.

.PARAMETER SP1IsoPath
    Path to an already-downloaded VS2008 SP1 ISO. Skips download if provided.

.PARAMETER IncludeDebugCRT
    Install debug CRT libs (msvcrtd.lib, libcmtd.lib, etc.) and debug DLLs
    (msvcr90d.dll, msvcp90d.dll) from VS2008 SP1. Required for /MDd and /MTd.

.PARAMETER NoPrompt
    Skip the interactive cleanup prompt (for CI/automation)

.EXAMPLE
    .\install-vc9.ps1

.EXAMPLE
    .\install-vc9.ps1 -IsoPath .\GRMSDK_EN_DVD.iso -NoPrompt

.EXAMPLE
    .\install-vc9.ps1 -IncludeDebugCRT
#>

param(
    [string]$IsoPath,
    [string]$SP1IsoPath,
    [switch]$IncludeDebugCRT,
    [switch]$NoPrompt
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

# VS2008 SP1 ISO — contains debug CRT add-ons
$SP1_NAME = "VS2008SP1ENUX1512962.iso"
$SP1_URL = "https://download.microsoft.com/download/a/3/7/a371b6d1-fc5e-44f7-914c-cb452b4043a9/VS2008SP1ENUX1512962.iso"
$SP1_SIZE = 871700480     # ~832 MB
$SP1_MSP = "vs90sp1\VC90sp1-KB947888-x86-enu.msp"

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

function Expand-IsoToPath {
    param($IsoPath)
    $extractDir = "$TempDir\sdk70-iso"

    # Use 7z if available (works on GitHub Actions and headless servers),
    # fall back to Mount-DiskImage for local desktop use.
    $sevenZip = Get-Command 7z -ErrorAction SilentlyContinue
    if ($sevenZip) {
        Write-Host "  Extracting ISO with 7z..."
        & 7z x $IsoPath -y -o"$extractDir" | Out-Null
        return $extractDir
    }

    Write-Host "  Mounting ISO with Mount-DiskImage..."
    try {
        $mount = Mount-DiskImage -ImagePath $IsoPath -PassThru
        $drive = ($mount | Get-Volume).DriveLetter
        return "${drive}:"
    } catch {
        Write-Error "Cannot extract ISO: 7z not found and Mount-DiskImage failed. Install 7-Zip or run on a desktop OS."
        exit 1
    }
}

# ============================================
# Step 1: Download and extract SDK 7.0, install VC9
# ============================================
Write-Host "[1/4] Installing VC9 SP1 from Windows SDK 7.0..." -ForegroundColor Green

if ($IsoPath -and (Test-Path $IsoPath)) {
    Write-Host "  Using provided ISO: $IsoPath" -ForegroundColor Green
    $SDK70_Path = $IsoPath
} else {
    $SDK70_Path = Get-OrDownload -FileName $SDK70_NAME -Url $SDK70_URL -ExpectedSize $SDK70_SIZE
}

$sdkRoot = Expand-IsoToPath $SDK70_Path
$is7zExtract = Test-Path "$sdkRoot\Setup"  # 7z gives a dir; mount gives a drive letter

foreach ($msi in @(
    @{ Path = "$sdkRoot\Setup\vc_stdx86\vc_stdx86.msi";         Desc = "VC9 x86 compiler" }
    @{ Path = "$sdkRoot\Setup\vc_stdamd64\vc_stdamd64.msi";     Desc = "VC9 x64 cross-compiler" }
    @{ Path = "$sdkRoot\Setup\WinSDKBuild\WinSDKBuild_x86.msi"; Desc = "Windows SDK headers + libs" }
)) {
    if (Test-Path $msi.Path) {
        Write-Host "  Installing $($msi.Desc)..."
        $p = Start-Process msiexec -ArgumentList "/i `"$($msi.Path)`" /qn" -Wait -PassThru
        if ($p.ExitCode -ne 0) { Write-Warning "msiexec exit $($p.ExitCode) for $($msi.Desc)" }
    } else {
        Write-Warning "MSI not found: $($msi.Path)"
    }
}

# Dismount only if we used Mount-DiskImage (not 7z extraction)
if (-not $is7zExtract) {
    try { Dismount-DiskImage -ImagePath $SDK70_Path -ErrorAction SilentlyContinue | Out-Null } catch {}
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

# ============================================
# Step 2: Fix cl.exe DLL dependencies
# ============================================
Write-Host "[2/4] Fixing cl.exe runtime dependencies..." -ForegroundColor Green

# cl.exe depends on mspdb80.dll, mspdbcore.dll, msobj80.dll, mspdbsrv.exe
# which MSI installs to Common7\IDE, not VC\bin. Without them in PATH or
# VC\bin, cl.exe silently crashes with STATUS_DLL_NOT_FOUND (0xC0000135).
# Ref: github.com/LoneGazebo/Community-Patch-DLL .github/workflows/build_vp.yml
$ideDir = "${VSInstallDir}Common7\IDE"
$binDir = "${VCInstallDir}bin"
foreach ($dll in @("msobj80.dll", "mspdb80.dll", "mspdbcore.dll", "mspdbsrv.exe")) {
    $src = "$ideDir\$dll"
    if (Test-Path $src) {
        Copy-Item $src $binDir -Force
        Write-Host "  Copied $dll -> VC\bin" -ForegroundColor Gray
    }
}

# ============================================
# Step 3: Set registry keys + environment
# ============================================
Write-Host "[3/4] Setting registry keys and environment..." -ForegroundColor Green

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
:: vsvars32.bat - Set up VC9 SP1 environment (created by vc9-toolset)

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
# Step 4: Install MSBuild v90 toolset (from repo)
# ============================================
Write-Host "[4/4] Installing MSBuild v90 toolset..." -ForegroundColor Green

$msbuildSrc = Join-Path $ScriptDir "MSBuild\v90"
if (-not (Test-Path "$msbuildSrc\Microsoft.Cpp.Win32.v90.props")) {
    Write-Error "MSBuild v90 files not found at $msbuildSrc. Repository may be incomplete."
    exit 1
}

# Legacy paths (v4.0) — used by VS2010-VS2015 and older MSBuild
$legacyDirs = @(
    "${env:ProgramFiles(x86)}\MSBuild\Microsoft.Cpp\v4.0\Platforms\Win32\PlatformToolsets\v90"
    "${env:ProgramFiles(x86)}\MSBuild\Microsoft.Cpp\v4.0\V110\Platforms\Win32\PlatformToolsets\v90"
    "${env:ProgramFiles(x86)}\MSBuild\Microsoft.Cpp\v4.0\V120\Platforms\Win32\PlatformToolsets\v90"
    "${env:ProgramFiles(x86)}\MSBuild\Microsoft.Cpp\v4.0\V140\Platforms\Win32\PlatformToolsets\v90"
)

foreach ($dir in $legacyDirs) {
    $parentDir = Split-Path $dir -Parent
    if (Test-Path $parentDir) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Copy-Item "$msbuildSrc\*" $dir -Force
        Write-Host "  Installed to: $dir" -ForegroundColor Gray
    }
}

# VS2017+ (v150/v160/v170) — uses Toolset.props/Toolset.targets naming
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsInstalls = & $vswhere -all -property installationPath 2>$null
    foreach ($vsPath in $vsInstalls) {
        $vcVersionDirs = Get-ChildItem "$vsPath\MSBuild\Microsoft\VC\v*" -Directory -ErrorAction SilentlyContinue
        foreach ($vcDir in $vcVersionDirs) {
            $toolsetDir = "$($vcDir.FullName)\Platforms\Win32\PlatformToolsets\v90"
            New-Item -ItemType Directory -Force -Path $toolsetDir | Out-Null

            # v150+ expects Toolset.props with _PlatformToolsetFound=true
            $propsContent = Get-Content "$msbuildSrc\Microsoft.Cpp.Win32.v90.props" -Raw
            # v170 MSBuild requires these properties for toolset discovery and build:
            # - _PlatformToolsetFound: suppresses MSB8020 "platform toolset not found"
            # - VCToolsInstallDir/VCToolsVersion: gates Microsoft.CppBuild.targets import
            # - CLToolPath/LinkToolPath/LibToolPath: tool locations (VC9 has flat bin\
            #   layout vs v170's bin\Hostx86\x86\ layout)
            # - LinkCompiled: v170 CL task tracker normally sets this; VC9's cl.exe
            #   doesn't use the tracker, so we set it statically
            $binDir = "${VCInstallDir}bin"
            $propsContent = $propsContent -replace '(<PropertyGroup>)', @"
`$1
    <_PlatformToolsetFound>true</_PlatformToolsetFound>
    <VCToolsInstallDir>$VCInstallDir</VCToolsInstallDir>
    <VCToolsVersion>9.0</VCToolsVersion>
    <CLToolPath>$binDir</CLToolPath>
    <CLToolExe>cl.exe</CLToolExe>
    <LinkToolPath>$binDir</LinkToolPath>
    <LinkToolExe>link.exe</LinkToolExe>
    <LibToolPath>$binDir</LibToolPath>
    <LibToolExe>lib.exe</LibToolExe>
    <LinkCompiled>true</LinkCompiled>
"@
            $propsContent | Out-File "$toolsetDir\Toolset.props" -Encoding UTF8

            # v170 Toolset.targets: must import Microsoft.CppCommon.targets (which
            # imports Microsoft.CppBuild.targets → defines the Build target).
            # Without this, MSBuild finds the toolset but has no Build target.
            # Also strip the VCMessage v4.0 UsingTask (v170 has its own).
            $targetsContent = Get-Content "$msbuildSrc\Microsoft.Cpp.Win32.v90.targets" -Raw
            $targetsContent = $targetsContent -replace '(?s)\s*<UsingTask\s+TaskName="VCMessage"[^/]*/>', ''
            $targetsContent = $targetsContent -replace 'ToolsVersion="4\.0"', ''
            # Insert CppCommon.targets import (same as v110–v143 toolsets).
            # CppCommon imports CppBuild.targets which defines Build/ClCompile/Link.
            # Override DoLinkOutputFilesMatch: the v170 VCMessage for MSB8012 crashes
            # with a FormatException when Link.OutputFile metadata is empty (v170 bug).
            $targetsContent = $targetsContent -replace '</Project>', @"

  <Import Project="`$(VCTargetsPath)\Microsoft.CppCommon.targets" />

  <!-- Override v170's DoLinkOutputFilesMatch: its VCMessage MSB8012 crashes with
       FormatException when Link.OutputFile is empty (no OutputFile metadata on v90) -->
  <Target Name="DoLinkOutputFilesMatch" />
</Project>
"@
            $targetsContent | Out-File "$toolsetDir\Toolset.targets" -Encoding UTF8

            Write-Host "  Installed to: $toolsetDir" -ForegroundColor Gray
        }
    }
}

# ============================================
# Optional: Debug CRT from VS2008 SP1
# ============================================
if ($IncludeDebugCRT) {
    Write-Host ""
    Write-Host "[SP1] Installing Debug CRT from VS2008 SP1..." -ForegroundColor Green

    # Download/locate SP1 ISO
    if ($SP1IsoPath -and (Test-Path $SP1IsoPath)) {
        Write-Host "  Using provided SP1 ISO: $SP1IsoPath" -ForegroundColor Green
        $sp1Path = $SP1IsoPath
    } else {
        $sp1Path = Get-OrDownload -FileName $SP1_NAME -Url $SP1_URL -ExpectedSize $SP1_SIZE
    }

    # Extract SP1 ISO → get the VC90 SP1 MSP
    $sp1ExtractDir = "$TempDir\sp1iso"
    $sevenZip = Get-Command 7z -ErrorAction SilentlyContinue
    if (-not $sevenZip) {
        Write-Error "7z required for SP1 extraction. Install 7-Zip and ensure 7z is in PATH."
        exit 1
    }
    Write-Host "  Extracting SP1 ISO..."
    & 7z x $sp1Path -y -o"$sp1ExtractDir" $SP1_MSP | Out-Null
    if (-not (Test-Path "$sp1ExtractDir\$SP1_MSP")) {
        Write-Error "SP1 MSP not found after extraction: $sp1ExtractDir\$SP1_MSP"
        exit 1
    }

    # Extract MSP → flat files with FL_ naming convention
    $mspDir = "$TempDir\sp1msp"
    Write-Host "  Extracting VC90 SP1 MSP..."
    & 7z x "$sp1ExtractDir\$SP1_MSP" -y -o"$mspDir" | Out-Null
    Remove-Item -Recurse -Force $sp1ExtractDir

    # Helper: copy FL_ named file to target
    function Copy-MspFile {
        param($Pattern, $TargetPath)
        $src = Get-ChildItem $mspDir -Filter "${Pattern}*" -File | Select-Object -First 1
        if ($src) {
            Copy-Item $src.FullName $TargetPath -Force
            return $true
        }
        return $false
    }

    # --- Debug CRT ---
    Write-Host "  Installing debug CRT libs..." -ForegroundColor Gray
    $dbgCount = 0

    # Debug CRT libs → VC\lib\
    $libDir = "${VCInstallDir}lib"
    $libMap = @{
        "FL_msvcrtd_lib_"  = "msvcrtd.lib"
        "FL_msvcprtd_lib_" = "msvcprtd.lib"
        "FL_libcmtd_lib_"  = "libcmtd.lib"
        "FL_libcpmtd_lib_" = "libcpmtd.lib"
        "FL_libcmtd_pdb_"  = "libcmtd.pdb"
        "FL_libcpmtd_pdb_" = "libcpmtd.pdb"
    }
    foreach ($entry in $libMap.GetEnumerator()) {
        if (Copy-MspFile -Pattern $entry.Key -TargetPath "$libDir\$($entry.Value)") {
            $dbgCount++
        } else {
            Write-Warning "$($entry.Value) not found in SP1 MSP"
        }
    }

    # Debug CRT DLLs → VC\redist\Debug_NonRedist\x86\Microsoft.VC90.DebugCRT\
    $dbgDllDir = "${VCInstallDir}redist\Debug_NonRedist\x86\Microsoft.VC90.DebugCRT"
    New-Item -ItemType Directory -Force -Path $dbgDllDir | Out-Null
    $dllMap = @{
        "FL_msvcr90_d_dll_"  = "msvcr90d.dll"
        "FL_msvcp90_d_dll_"  = "msvcp90d.dll"
        "FL_msvcm90_d_dll_"  = "msvcm90d.dll"
        "FL_Microsoft_VC90_DebugCRT_manifest_" = "Microsoft.VC90.DebugCRT.manifest"
    }
    foreach ($entry in $dllMap.GetEnumerator()) {
        if (Copy-MspFile -Pattern $entry.Key -TargetPath "$dbgDllDir\$($entry.Value)") {
            $dbgCount++
        }
    }
    Write-Host "  Installed $dbgCount debug CRT files" -ForegroundColor Gray

    Remove-Item -Recurse -Force $mspDir -ErrorAction SilentlyContinue
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
Write-Host "Usage:"
Write-Host "  Project Properties -> General -> Platform Toolset -> Visual Studio 2008 (v90)"
Write-Host "  Or in .vcxproj: <PlatformToolset>v90</PlatformToolset>"
Write-Host ""

# Cleanup option
if (-not $NoPrompt) {
    $cleanup = Read-Host "Delete downloaded ISO (~1.5GB)? [y/N]"
    if ($cleanup -eq 'y' -or $cleanup -eq 'Y') {
        Remove-Item -Recurse -Force $TempDir
        Write-Host "Cleaned up temp files."
    }
}
