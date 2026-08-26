# Build the web app and push it to the DigitalOcean droplet.
#
#   .\deploy\deploy-web.ps1 -DropletHost root@203.0.113.10
#   .\deploy\deploy-web.ps1 -DropletHost root@203.0.113.10 -IncludeApk
#
# Needs ssh and scp on PATH — both ship with Windows 10/11 (OpenSSH client).
# Nothing here is DigitalOcean-specific; it is a droplet with nginx on it.

[CmdletBinding()]
param(
    # user@host of the droplet.
    [Parameter(Mandatory = $true)]
    [string] $DropletHost,

    # Where nginx's `root` points. Must match deploy/nginx/elevar-play.conf.
    [string] $RemoteRoot = '/var/www/elevar-play',

    # Set this if the app is served from a subpath rather than a subdomain,
    # e.g. -BaseHref '/play/'. Getting it wrong gives a blank page and no error
    # in the console, which is a miserable half hour.
    [string] $BaseHref = '/',

    # Also upload the release APK next to the web build, so one link can offer
    # both "play now" and "install it properly".
    [switch] $IncludeApk,

    # Skip the Flutter build and ship whatever is already in build/web.
    [switch] $NoBuild
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'app'
$web = Join-Path $app 'build\web'

function Step($message) {
    Write-Host ''
    Write-Host "==> $message" -ForegroundColor Cyan
}

if (-not $NoBuild) {
    Step 'Building the web release'
    Push-Location $app
    try {
        & flutter build web --release --base-href $BaseHref
        if ($LASTEXITCODE -ne 0) { throw "flutter build web failed ($LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path (Join-Path $web 'index.html'))) {
    throw "No build at $web. Run without -NoBuild."
}

# The two files the ledger needs in the browser. A deploy that loses them
# looks fine until the first match ends and the points never bank.
foreach ($required in 'sqflite_sw.js', 'sqlite3.wasm') {
    if (-not (Test-Path (Join-Path $web $required))) {
        throw "$required is missing from the build. Run: cd app; dart run sqflite_common_ffi_web:setup"
    }
}

Step 'Trimming debug symbols'
# ~4.5MB each and never fetched at runtime. Deleting them from the *copy*
# would be cleaner, but the build directory is disposable.
Get-ChildItem -Path $web -Filter '*.symbols' -Recurse | ForEach-Object {
    Write-Host "    removing $($_.Name)"
    Remove-Item $_.FullName -Force
}

$size = (Get-ChildItem $web -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ("    payload: {0:N1} MB" -f ($size / 1MB))

Step "Preparing $RemoteRoot on $DropletHost"
& ssh $DropletHost "mkdir -p '$RemoteRoot' && rm -rf '$RemoteRoot'/*"
if ($LASTEXITCODE -ne 0) { throw "ssh failed ($LASTEXITCODE)" }

Step 'Uploading'
# scp -r on the directory *contents*, so the remote root holds index.html
# rather than a nested web/ directory.
& scp -r "$web\*" "${DropletHost}:$RemoteRoot/"
if ($LASTEXITCODE -ne 0) { throw "scp failed ($LASTEXITCODE)" }

if ($IncludeApk) {
    $apk = Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk'
    if (Test-Path $apk) {
        Step 'Uploading the APK'
        & scp $apk "${DropletHost}:$RemoteRoot/elevar-play.apk"
        if ($LASTEXITCODE -ne 0) { throw "scp of the APK failed ($LASTEXITCODE)" }
    } else {
        Write-Warning "No APK at $apk — run: cd app; flutter build apk --release"
    }
}

Step 'Fixing ownership and reloading nginx'
& ssh $DropletHost "chown -R www-data:www-data '$RemoteRoot' && nginx -t && systemctl reload nginx"
if ($LASTEXITCODE -ne 0) { throw "remote nginx reload failed ($LASTEXITCODE)" }

Write-Host ''
Write-Host 'Deployed.' -ForegroundColor Green
Write-Host 'Hard-refresh once (Ctrl+Shift+R): the old service worker will otherwise serve the previous build.'
