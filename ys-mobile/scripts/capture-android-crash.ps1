param(
    [string] $PackageName = "com.tythac.ys_mobile",
    [string] $Output = "android-crash-log.txt"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$adb = Join-Path $repoRoot ".tools\android-sdk\platform-tools\adb.exe"
if (-not (Test-Path -LiteralPath $adb)) {
    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $adbCommand) {
        throw "adb was not found. Connect Android SDK platform-tools or add adb to PATH."
    }
    $adb = $adbCommand.Source
}

$devices = & $adb devices -l
$connected = $devices | Select-String -Pattern "\bdevice\b"
if (-not $connected) {
    Write-Host "No Android phone is connected."
    Write-Host "Enable Developer options, enable USB debugging, plug the phone in, and accept the RSA prompt."
    & $adb devices -l
    exit 1
}

Write-Host "Connected devices:"
& $adb devices -l

try {
    & $adb logcat -c 2>$null
} catch {
    Write-Host "Could not clear logcat. Continuing with recent logs."
}

Write-Host "Launching $PackageName ..."
& $adb shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Host
Start-Sleep -Seconds 8

$outputPath = Join-Path (Get-Location) $Output
& $adb logcat -d -t 2000 > $outputPath

Write-Host "Saved crash log to $outputPath"
Write-Host "Useful crash lines:"
Select-String -Path $outputPath -Pattern "FATAL EXCEPTION|AndroidRuntime|UnsatisfiedLinkError|$PackageName|flutter|Exception|Error" -Context 3,8
