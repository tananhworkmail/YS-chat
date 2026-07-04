param(
    [Parameter(Mandatory = $true)]
    [string] $ApiUrl,

    [switch] $DebugBuild
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$mobileRoot = Resolve-Path (Join-Path $scriptRoot "..")
$repoRoot = Resolve-Path (Join-Path $mobileRoot "..")
$webDownloadsDir = Join-Path $repoRoot "ys-web\public\downloads"
$targetApk = Join-Path $webDownloadsDir "YSChat.apk"
$flutterExecutable = Get-Command flutter -ErrorAction SilentlyContinue
$flutterCommand = $null
if ($flutterExecutable) {
    $flutterCommand = $flutterExecutable.Source
}
if (-not $flutterCommand -and (Test-Path -LiteralPath "D:\Flutter\flutter\bin\flutter.bat")) {
    $flutterCommand = "D:\Flutter\flutter\bin\flutter.bat"
}
if (-not $flutterCommand) {
    throw "Flutter was not found in PATH. Install Flutter or add flutter\bin to PATH."
}

Push-Location $mobileRoot
try {
    if ($DebugBuild) {
        & $flutterCommand build apk --debug --target-platform android-arm64 --dart-define="YS_API_URL=$ApiUrl"
        $sourceApk = Join-Path $mobileRoot "build\app\outputs\flutter-apk\app-debug.apk"
    } else {
        & $flutterCommand build apk --release --target-platform android-arm64 --dart-define="YS_API_URL=$ApiUrl"
        $sourceApk = Join-Path $mobileRoot "build\app\outputs\flutter-apk\app-release.apk"
    }

    if (-not (Test-Path -LiteralPath $sourceApk)) {
        throw "APK was not created: $sourceApk"
    }

    New-Item -ItemType Directory -Force -Path $webDownloadsDir | Out-Null
    Copy-Item -LiteralPath $sourceApk -Destination $targetApk -Force

    $apk = Get-Item -LiteralPath $targetApk
    Write-Host "Copied APK to $targetApk"
    Write-Host ("Size: {0:N2} MB" -f ($apk.Length / 1MB))
    Write-Host "Web download URL: /downloads/YSChat.apk"
} finally {
    Pop-Location
}
