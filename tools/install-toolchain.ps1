#requires -Version 5.1
# Installs the Flutter + JDK 17 + Android SDK toolchain for elevar-game on Windows.
# Idempotent: re-running skips whatever is already in place.
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$dev = if ($env:ELEVAR_DEV_ROOT) { $env:ELEVAR_DEV_ROOT } else { Join-Path $HOME 'dev' }
$dl  = Join-Path $dev '_downloads'
New-Item -ItemType Directory -Force -Path $dl | Out-Null

function Log($m) { "$([DateTime]::Now.ToString('HH:mm:ss'))  $m" | Tee-Object -FilePath "$dev\install.log" -Append }

function Fetch($url, $out) {
    if ((Test-Path $out) -and (Get-Item $out).Length -gt 20MB) { Log "skip download (have it): $(Split-Path $out -Leaf)"; return }
    Log "downloading $(Split-Path $out -Leaf)"
    # BITS-free, resumable-enough: straight WebClient is far faster than Invoke-WebRequest for big files.
    (New-Object System.Net.WebClient).DownloadFile($url, $out)
    Log "  done: $([math]::Round((Get-Item $out).Length/1MB,1)) MB"
}

function Expand($zip, $dest, $sentinel) {
    if (Test-Path $sentinel) { Log "skip extract (have it): $(Split-Path $dest -Leaf)"; return }
    Log "extracting $(Split-Path $zip -Leaf) -> $dest"
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $dest)
    Log "  extracted"
}

# --- 1. Flutter -------------------------------------------------------------
Fetch 'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.1-stable.zip' "$dl\flutter.zip"
Expand "$dl\flutter.zip" $dev "$dev\flutter\bin\flutter.bat"

# --- 2. JDK 17 (Temurin) ----------------------------------------------------
$jdkUrl = 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.20%2B8/OpenJDK17U-jdk_x64_windows_hotspot_17.0.20_8.zip'
Fetch $jdkUrl "$dl\jdk17.zip"
Expand "$dl\jdk17.zip" $dev "$dev\jdk-17.0.20+8\bin\java.exe"

# --- 3. Android command-line tools -----------------------------------------
# sdkmanager insists on living at <sdk>\cmdline-tools\latest\, not the bare
# cmdline-tools\ the archive unpacks to. Getting this wrong is the single most
# common cause of "sdkmanager is not recognized".
$sdk = "$dev\android-sdk"
Fetch 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' "$dl\cmdline-tools.zip"
if (-not (Test-Path "$sdk\cmdline-tools\latest\bin\sdkmanager.bat")) {
    Log "installing cmdline-tools"
    New-Item -ItemType Directory -Force -Path "$sdk\cmdline-tools" | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tmp = "$dl\_cmdline"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$dl\cmdline-tools.zip", $tmp)
    Move-Item "$tmp\cmdline-tools" "$sdk\cmdline-tools\latest"
    Remove-Item $tmp -Recurse -Force
    Log "  cmdline-tools at $sdk\cmdline-tools\latest"
} else { Log "skip cmdline-tools (have it)" }

# --- 4. Environment ---------------------------------------------------------
$javaHome = "$dev\jdk-17.0.20+8"
[Environment]::SetEnvironmentVariable('JAVA_HOME', $javaHome, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $sdk, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $sdk, 'User')
$paths = @("$dev\flutter\bin", "$javaHome\bin", "$sdk\cmdline-tools\latest\bin", "$sdk\platform-tools")
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
foreach ($p in $paths) { if ($userPath -notlike "*$p*") { $userPath = "$p;$userPath" } }
[Environment]::SetEnvironmentVariable('Path', $userPath.TrimEnd(';'), 'User')
Log "environment set (JAVA_HOME, ANDROID_HOME, PATH)"

# Make them live in *this* process too, so the SDK steps below can run now.
$env:JAVA_HOME = $javaHome
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:Path = ($paths -join ';') + ';' + $env:Path

# --- 5. Android SDK licences ------------------------------------------------
# Written directly rather than piped into `sdkmanager --licenses`. That command
# reads from the console, and when stdin is not a terminal it accepts nothing,
# installs nothing, and still exits 0 — which looks exactly like success. These
# are the published hashes; writing them is precisely what typing "y" does.
$lic = Join-Path $sdk 'licenses'
New-Item -ItemType Directory -Force -Path $lic | Out-Null
$licenses = @{
  'android-sdk-license'           = @('8933bad161af4178b1185d1a37fbf41ea5269c55','d56f5187479451eabf01fb78af6dfcb131a6481e','24333f8a63b6825ea9c5514f83c2829b004d1fee')
  'android-sdk-preview-license'   = @('84831b9409646a918e30573bab4c9c91346d8abd')
  'android-sdk-arm-dbt-license'   = @('859f317696f67ef3d7f30a50a5560e7834b43903')
  'android-googletv-license'      = @('601085b94cd77f0b54ff86406957099ebe79c4d6')
  'google-gdk-license'            = @('33b6a2b64607f11b759f320ef9dff4ae5c47d97a')
  'mips-android-sysimage-license' = @('e9acab5b5fbb560a72cfaecce8946896ff6aab9d')
}
foreach ($name in $licenses.Keys) {
  [System.IO.File]::WriteAllText((Join-Path $lic $name), "`n" + ($licenses[$name] -join "`n") + "`n")
}
Log "SDK licences accepted"

# --- 6. Android SDK packages ------------------------------------------------
# Platform 36 / build-tools 36.0.0 are what the app's Gradle config expects.
if (-not (Test-Path "$sdk\platforms\android-36")) {
    Log "installing SDK packages (this is the slow one)"
    cmd /c "`"$sdk\cmdline-tools\latest\bin\sdkmanager.bat`" --install `"platform-tools`" `"platforms;android-36`" `"build-tools;36.0.0`" 2>&1" | Select-Object -Last 3 | ForEach-Object { Log "  sdk: $_" }
} else { Log "skip SDK packages (have android-36)" }

# --- 7. Wire Flutter up -----------------------------------------------------
Log "flutter config"
& "$dev\flutter\bin\flutter.bat" config --android-sdk $sdk --no-analytics 2>&1 | Select-Object -Last 3 | ForEach-Object { Log "  $_" }
& "$dev\flutter\bin\flutter.bat" --version 2>&1 | Select-Object -First 3 | ForEach-Object { Log "  $_" }

Log "DONE"
