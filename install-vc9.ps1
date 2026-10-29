<#
.SYNOPSIS
    Install VC9 SP1 (VS2008 SP1) toolchain for Visual Studio 2010 and later

.DESCRIPTION
    Downloads and installs:
    1. VC9 SP1 compiler, and the headers, libs, rc.exe and mt.exe of Windows SDK 7.0
    2. MSBuild v90 toolset (bundled in this repository)

    Optional add-ons from VS2008 SP1 (~832 MB download):
    3. Debug CRT libs/DLLs (-IncludeDebugCRT)

    After installation, set PlatformToolset=v90 in your project.

.PARAMETER IsoPath
    Path to an already-downloaded SDK 7.0 ISO. Skips download if provided.

.PARAMETER SP1IsoPath
    Path to an already-downloaded VS2008 SP1 ISO. Skips download if provided.

.PARAMETER SetupDir
    Folder made by fetch-vc9.sh (sdk70\Setup\..., sp1\*.msp). Installs from it instead of the ISOs;
    used by the GitHub Action, which caches that folder.

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
    [string]$SetupDir,
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

# File names, sizes, SHA-256 and URLs: downloads.txt (shared with fetch-vc9.sh)
function Read-Download {
    param([string]$Id)
    $entry = @{ Name = $null; Size = 0; Sha256 = $null; Urls = @() }
    foreach ($line in Get-Content (Join-Path $ScriptDir "downloads.txt")) {
        $fields = -split $line
        if ($fields.Count -lt 3 -or $fields[0].StartsWith("#") -or $fields[1] -ne $Id) { continue }
        if ($fields[0] -eq "file") { $entry.Name = $fields[2]; $entry.Size = [long]$fields[3]; $entry.Sha256 = $fields[4] }
        elseif ($fields[0] -eq "url") { $entry.Urls += $fields[2] }
    }
    if (-not $entry.Name -or $entry.Urls.Count -eq 0) { Write-Error "No entry for '$Id' in downloads.txt"; exit 1 }
    return $entry
}
$sdk70 = Read-Download "sdk70"
$SDK70_NAME = $sdk70.Name; $SDK70_SIZE = $sdk70.Size; $SDK70_SHA256 = $sdk70.Sha256; $SDK70_URLS = $sdk70.Urls
$sp1 = Read-Download "sp1"
$SP1_NAME = $sp1.Name; $SP1_SIZE = $sp1.Size; $SP1_SHA256 = $sp1.Sha256; $SP1_URLS = $sp1.Urls
$SP1_MSP = "vs90sp1\VC90sp1-KB947888-x86-enu.msp"

function Test-Iso {
    param($Path, $ExpectedSize, $ExpectedHash)
    if (-not (Test-Path $Path) -or (Get-Item $Path).Length -ne $ExpectedSize) { return $false }
    return (Get-FileHash $Path -Algorithm SHA256).Hash -eq $ExpectedHash
}

function Get-OrDownload {
    param($FileName, $Urls, $ExpectedSize, $ExpectedHash)

    # Next to the script, then a previous download in the temp directory
    foreach ($candidate in @((Join-Path $ScriptDir $FileName), (Join-Path $TempDir $FileName))) {
        if (Test-Iso $candidate $ExpectedSize $ExpectedHash) {
            Write-Host "  Using: $candidate" -ForegroundColor Green
            return $candidate
        }
    }

    $tempPath = Join-Path $TempDir $FileName
    foreach ($url in $Urls) {
        Write-Host "  Downloading: $url"
        Write-Host "  (This may take a while...)" -ForegroundColor Gray
        # curl.exe ships with Windows 10+. It has no read timeout: --speed-limit/--speed-time abort a stalled
        # transfer. --fail only catches HTTP errors, so the size and hash are checked too.
        & curl.exe -L --fail --retry 2 --retry-all-errors --connect-timeout 60 --speed-limit 1024 --speed-time 120 --no-progress-meter -o $tempPath $url
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Download failed (curl exit $LASTEXITCODE): $url"
            continue
        }
        if (Test-Iso $tempPath $ExpectedSize $ExpectedHash) { return $tempPath }
        Write-Warning "Wrong size or SHA-256 from $url"
    }
    Write-Error "Could not download $FileName with the expected size and SHA-256"
    exit 1
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

if ($SetupDir) {
    # msiexec cannot open a package path with mixed separators (exit 1619), e.g. D:\a\_temp/vc9-setup from bash
    $SetupDir = [System.IO.Path]::GetFullPath($SetupDir)
    if (-not (Test-Path "$SetupDir\sdk70\.complete")) {
        Write-Error "$SetupDir has no complete sdk70 folder. Run fetch-vc9.sh `"$SetupDir`" first."
        exit 1
    }
    Write-Host "  Using setup files: $SetupDir\sdk70" -ForegroundColor Green
    $sdkRoot = "$SetupDir\sdk70"
    $is7zExtract = $true
} elseif ($IsoPath -and (Test-Path $IsoPath)) {
    Write-Host "  Using provided ISO: $IsoPath" -ForegroundColor Green
    $SDK70_Path = $IsoPath
} else {
    $SDK70_Path = Get-OrDownload -FileName $SDK70_NAME -Urls $SDK70_URLS -ExpectedSize $SDK70_SIZE -ExpectedHash $SDK70_SHA256
}

if (-not $SetupDir) {
    $sdkRoot = Expand-IsoToPath $SDK70_Path
    $is7zExtract = Test-Path "$sdkRoot\Setup"  # 7z gives a dir; mount gives a drive letter
}

foreach ($msi in @(
    @{ Path = "$sdkRoot\Setup\vc_stdx86\vc_stdx86.msi";         Desc = "VC9 x86 compiler" }
    @{ Path = "$sdkRoot\Setup\vc_stdamd64\vc_stdamd64.msi";     Desc = "VC9 x64 cross-compiler" }
    @{ Path = "$sdkRoot\Setup\WinSDKBuild\WinSDKBuild_x86.msi"; Desc = "Windows SDK headers + libs" }
    @{ Path = "$sdkRoot\Setup\WinSDKWin32Tools\WinSDKWin32Tools_x86.msi"; Desc = "Windows SDK rc.exe + mt.exe" }
)) {
    if (-not (Test-Path $msi.Path)) {
        Write-Error "MSI not found: $($msi.Path)"
        exit 1
    }
    Write-Host "  Installing $($msi.Desc)..."
    $log = Join-Path $TempDir ((Split-Path $msi.Path -Leaf) + ".log")
    $p = Start-Process msiexec -ArgumentList "/i `"$($msi.Path)`" /qn /norestart /l*v `"$log`"" -Wait -PassThru
    # 0 = success, 3010 = success, restart required
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        Get-Content $log -Tail 40 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" }
        Write-Error "msiexec exit $($p.ExitCode) for $($msi.Desc) (log: $log)"
        exit 1
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

# VS2017+ (every MSBuild\Microsoft\VC\v* folder, v150 to v180): uses Toolset.props/Toolset.targets naming
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsInstalls = & $vswhere -all -products '*' -property installationPath 2>$null
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
            # - TrackFileAccess=false: VC9's cl.exe cannot run under v170's file tracker
            # - IncludePath/LibraryPath/ExecutablePath: the stock props only set these when empty, and
            #   v170 has already filled them with the current toolset's paths, so set VC9 + SDK 7.0 here
            #   (absolute: VCInstallDir is not defined yet); /p:UseEnv=true still takes them from the environment
            # - WindowsSdkDir: the stock props read CurrentInstallFolder, which another SDK may own and which
            #   needs a trailing backslash; set it last to the SDK 7.0 this script installed
            $binDir = "${VCInstallDir}bin"
            $sdkDir = "${env:ProgramFiles(x86)}\Microsoft SDKs\Windows\v7.0\"
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
    <TrackFileAccess>false</TrackFileAccess>
    <LegacyManifestEmbedding>true</LegacyManifestEmbedding>
    <IncludePath Condition="'`$(UseEnv)' != 'true'">${VCInstallDir}include;${VCInstallDir}atlmfc\include;${sdkDir}Include</IncludePath>
    <LibraryPath Condition="'`$(UseEnv)' != 'true'">${VCInstallDir}lib;${VCInstallDir}atlmfc\lib;${sdkDir}Lib</LibraryPath>
    <ExecutablePath Condition="'`$(UseEnv)' != 'true'">$binDir;${sdkDir}Bin;${VSInstallDir}Common7\IDE;`$(PATH)</ExecutablePath>
"@
            # - LegacyManifestEmbedding: v170 embeds manifests with link /MANIFEST:EMBED, which VC9's link.exe
            #   doesn't have; this restores the VS2010 way (mt.exe and a second link)
            # - Microsoft.Cpp.Common.props: the ClCompile/Link/Lib item defaults (ProgramDataBaseFileName,
            #   ObjectFileName, Link OutputFile, ...); v143 gets it through Microsoft.Cpp.MSVC.Toolset.Common.props.
            #   The item defaults set before it are the VS2010 ones where v170 differs: the Win32 platform defaults
            #   from VS2010's Microsoft.Cpp.Win32.props (Platform.Common.props would also add /SAFESEH), no /FC
            #   (it puts full paths into __FILE__), and no /DEBUG unless the project asks for it
            $propsContent = $propsContent -replace '\s*(</PropertyGroup>)', @"

    <WindowsSdkDir Condition="'`$(UseEnv)' != 'true'">$sdkDir</WindowsSdkDir>
  `$1

  <ItemDefinitionGroup>
    <ClCompile>
      <EnablePREfast Condition="'%(ClCompile.EnablePREfast)' == ''">false</EnablePREfast>
      <OmitFramePointers Condition="'%(ClCompile.OmitFramePointers)' == ''">false</OmitFramePointers>
      <DebugInformationFormat Condition="'%(ClCompile.DebugInformationFormat)' == '' and '`$(UseDebugLibraries)' == 'true'">EditAndContinue</DebugInformationFormat>
      <UseFullPaths Condition="'%(ClCompile.UseFullPaths)' == ''">false</UseFullPaths>
    </ClCompile>
    <Link>
      <TargetMachine Condition="'%(Link.TargetMachine)' == ''">MachineX86</TargetMachine>
      <GenerateDebugInformation Condition="'%(Link.GenerateDebugInformation)' == ''">false</GenerateDebugInformation>
    </Link>
    <Lib>
      <TargetMachine Condition="'%(Lib.TargetMachine)' == ''">MachineX86</TargetMachine>
    </Lib>
    <ImpLib>
      <TargetMachine Condition="'%(ImpLib.TargetMachine)' == ''">MachineX86</TargetMachine>
    </ImpLib>
  </ItemDefinitionGroup>

  <Import Project="`$(VCTargetsPath)\Microsoft.Cpp.Common.props" />
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
            # The ItemDefinitionGroup turns off the switches newer than VC9's cl.exe and link.exe that v170/v180
            # turn on by default (/JMC, /Zc:inline, /diagnostics:column, /external:W3, /DEBUG:FULL, /ILK,
            # /LTCG:incremental) or that projects made with newer VS often set (/sdl, /permissive-, /std, ...),
            # like Microsoft.Cpp.ClangCl.Exclusion.props does for clang-cl; being in the targets, it also applies
            # when the project sets them.
            $targetsContent = $targetsContent -replace '</Project>', @"

  <ItemDefinitionGroup>
    <ClCompile>
      <SupportJustMyCode>false</SupportJustMyCode>
      <RemoveUnreferencedCodeData>false</RemoveUnreferencedCodeData>
      <DiagnosticsFormat />
      <ExternalWarningLevel />
      <ExternalTemplatesDiagnostics />
      <TreatAngleIncludeAsExternal />
      <SDLCheck />
      <ConformanceMode />
      <LanguageStandard />
      <LanguageStandard_C />
      <UseStandardPreprocessor />
      <ControlFlowGuard />
      <GuardEHContMetadata />
      <SpectreMitigation />
      <EnableASAN />
      <IntelJCCErratum />
      <EnableParallelCodeGeneration />
    </ClCompile>
    <Link>
      <GenerateDebugInformation Condition="'%(Link.GenerateDebugInformation)' == 'DebugFull' or '%(Link.GenerateDebugInformation)' == 'DebugFastLink'">true</GenerateDebugInformation>
      <LinkTimeCodeGeneration Condition="'%(Link.LinkTimeCodeGeneration)' == 'UseFastLinkTimeCodeGeneration'">UseLinkTimeCodeGeneration</LinkTimeCodeGeneration>
      <IncrementalLinkDatabaseFile />
      <LinkTimeCodeGenerationObjectFile />
      <CETCompat />
      <LinkControlFlowGuard />
    </Link>
  </ItemDefinitionGroup>

  <Import Project="`$(VCTargetsPath)\Microsoft.CppCommon.targets" />
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

    $sevenZip = Get-Command 7z -ErrorAction SilentlyContinue
    if (-not $sevenZip) {
        Write-Error "7z required for SP1 extraction. Install 7-Zip and ensure 7z is in PATH."
        exit 1
    }
    $mspDir = "$TempDir\sp1msp"
    $setupMsp = if ($SetupDir) { Join-Path $SetupDir ("sp1\" + (Split-Path $SP1_MSP -Leaf)) }

    if ($setupMsp) {
        if (-not (Test-Path "$SetupDir\sp1\.complete")) {
            Write-Error "$SetupDir has no complete sp1 folder. Run fetch-vc9.sh --include-debug-crt `"$SetupDir`" first."
            exit 1
        }
        Write-Host "  Extracting VC90 SP1 MSP from $setupMsp..."
        & 7z x $setupMsp -y -o"$mspDir" | Out-Null
    } else {
        # Download/locate SP1 ISO
        if ($SP1IsoPath -and (Test-Path $SP1IsoPath)) {
            Write-Host "  Using provided SP1 ISO: $SP1IsoPath" -ForegroundColor Green
            $sp1Path = $SP1IsoPath
        } else {
            $sp1Path = Get-OrDownload -FileName $SP1_NAME -Urls $SP1_URLS -ExpectedSize $SP1_SIZE -ExpectedHash $SP1_SHA256
        }

        # Extract SP1 ISO -> get the VC90 SP1 MSP
        $sp1ExtractDir = "$TempDir\sp1iso"
        Write-Host "  Extracting SP1 ISO..."
        & 7z x $sp1Path -y -o"$sp1ExtractDir" $SP1_MSP | Out-Null
        if (-not (Test-Path "$sp1ExtractDir\$SP1_MSP")) {
            Write-Error "SP1 MSP not found after extraction: $sp1ExtractDir\$SP1_MSP"
            exit 1
        }

        # Extract MSP -> flat files with FL_ naming convention
        Write-Host "  Extracting VC90 SP1 MSP..."
        & 7z x "$sp1ExtractDir\$SP1_MSP" -y -o"$mspDir" | Out-Null
        Remove-Item -Recurse -Force $sp1ExtractDir
    }

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
