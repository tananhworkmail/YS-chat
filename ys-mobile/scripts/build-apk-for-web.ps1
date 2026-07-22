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
$googleServicesConfig = Join-Path $mobileRoot "android\app\google-services.json"

if (-not (Test-Path -LiteralPath $googleServicesConfig)) {
    Write-Warning @"
Firebase Android config is missing: $googleServicesConfig
The APK can be built, but background messages and incoming calls will not work
until google-services.json for applicationId com.tythac.ys_mobile is added.
"@
}

function Remove-StaleFlutterDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string] $RelativePath
    )

    $target = Join-Path $mobileRoot $RelativePath
    if (-not (Test-Path -LiteralPath $target)) {
        return
    }

    $resolvedTarget = Resolve-Path -LiteralPath $target
    if (-not $resolvedTarget.Path.StartsWith($mobileRoot.Path, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete outside mobile project: $($resolvedTarget.Path)"
    }

    Get-ChildItem -LiteralPath $resolvedTarget.Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
    }
    $item = Get-Item -LiteralPath $resolvedTarget.Path -Force
    $item.Attributes = $item.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Remove-Item -LiteralPath $resolvedTarget.Path -Recurse -Force
            return
        } catch {
            if ($attempt -eq 5) {
                throw
            }
            Start-Sleep -Milliseconds 500
        }
    }
}

function Clear-FlutterBuildReadOnlyAttributes {
    $buildRoot = Join-Path $mobileRoot "build"
    if (-not (Test-Path -LiteralPath $buildRoot)) {
        return
    }

    $resolvedBuildRoot = Resolve-Path -LiteralPath $buildRoot
    if (-not $resolvedBuildRoot.Path.StartsWith($mobileRoot.Path, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify attributes outside mobile project: $($resolvedBuildRoot.Path)"
    }

    Write-Host "Preparing existing Flutter build cache..."
    Get-ChildItem -LiteralPath $resolvedBuildRoot.Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if (($_.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
            $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
        }
    }

    $rootItem = Get-Item -LiteralPath $resolvedBuildRoot.Path -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
        $rootItem.Attributes = $rootItem.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
    }
}

function Stop-GradleDaemon {
    $gradleWrapper = Join-Path $mobileRoot "android\gradlew.bat"
    if (-not (Test-Path -LiteralPath $gradleWrapper)) {
        return
    }

    & $gradleWrapper --stop *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Gradle daemon stop returned exit code $LASTEXITCODE. Continuing cleanup."
    }
}

function Stop-BuildJavaDaemons {
    $buildDaemons = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "java.exe" -and (
            $_.CommandLine -like "*org.gradle.launcher.daemon.bootstrap.GradleDaemon*" -or
            $_.CommandLine -like "*org.jetbrains.kotlin.daemon.KotlinCompileDaemon*" -or
            $_.CommandLine -like "*com.github.badsyntax.gradle.GradleServer*"
        )
    }

    foreach ($process in $buildDaemons) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }

    if ($buildDaemons) {
        Start-Sleep -Milliseconds 800
    }
}

function Stop-FlutterBuildDaemons {
    $flutterDaemons = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -in @("dart.exe", "dartvm.exe") -and
        $_.CommandLine -like "*flutter_tools.snapshot*" -and
        $_.CommandLine -like "* daemon*"
    }

    foreach ($process in $flutterDaemons) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }

    if ($flutterDaemons) {
        Start-Sleep -Milliseconds 800
    }
}

function Invoke-FlutterBuild {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    & $flutterCommand @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter build failed with exit code $LASTEXITCODE."
    }
}

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
    Stop-GradleDaemon
    Stop-BuildJavaDaemons
    Stop-FlutterBuildDaemons
    Clear-FlutterBuildReadOnlyAttributes
    Remove-StaleFlutterDirectory "ios\Flutter\ephemeral\Packages\.packages"
    Remove-StaleFlutterDirectory "build\unit_test_assets"
    Remove-StaleFlutterDirectory "build\app"

    if ($DebugBuild) {
        Invoke-FlutterBuild -Arguments @("build", "apk", "--debug", "--no-android-gradle-daemon", "--target-platform", "android-arm64,android-x64", "--dart-define=YS_API_URL=$ApiUrl")
        $sourceApk = Join-Path $mobileRoot "build\app\outputs\flutter-apk\app-debug.apk"
    } else {
        Invoke-FlutterBuild -Arguments @("build", "apk", "--release", "--no-android-gradle-daemon", "--target-platform", "android-arm64,android-x64", "--dart-define=YS_API_URL=$ApiUrl")
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
    Stop-GradleDaemon
    Stop-BuildJavaDaemons
    Stop-FlutterBuildDaemons
    Pop-Location
}
