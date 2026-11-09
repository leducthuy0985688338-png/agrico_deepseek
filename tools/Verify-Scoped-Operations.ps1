[CmdletBinding()]
param([switch]$Full,[switch]$Build)
$ErrorActionPreference = 'Stop'
if ($Build -and -not $Full) { throw '-Build requires -Full.' }
$repoPath = Split-Path $PSScriptRoot -Parent
Push-Location $repoPath
try {
    $branch = (& git branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or $branch -ne 'feature/scoped-operations-private-personnel-20261026') { throw 'Wrong working branch.' }
    & git merge-base --is-ancestor ea0d642860560e716cca3dc32466521043b1e49e HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Required baseline is not an ancestor.' }
    if (@(& git diff --cached --name-only).Count -gt 0) { throw 'Unexpected staged changes.' }
    $allowed = @('analysis_options.yaml','linux/flutter/generated_plugin_registrant.cc','linux/flutter/generated_plugin_registrant.h','linux/flutter/generated_plugins.cmake','macos/Flutter/GeneratedPluginRegistrant.swift','windows/flutter/generated_plugin_registrant.cc','windows/flutter/generated_plugin_registrant.h','windows/flutter/generated_plugins.cmake')
    $state = & git status --porcelain --untracked-files=all
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect git status.' }
    foreach ($line in $state) {
        if ($line.Length -gt 3 -and $allowed -notcontains $line.Substring(3).Trim('"').Replace('\','/')) { throw "Unexpected local change: $line" }
    }
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
    & flutter analyze --no-fatal-infos --no-fatal-warnings
    if ($LASTEXITCODE -ne 0) { throw 'Analyzer failed.' }
    $targets = @('test/core/permissions','test/core/backup','test/core/migrations','test/app_v2/v2_resource_module_routes_test.dart','test/features/finance','test/features/inventory','test/features/personnel','test/features/machines','test/features/trade','test/features/integration','test/core/auth','test/theme/app_bar_tab_visibility_test.dart')
    & flutter test @targets
    if ($LASTEXITCODE -ne 0) { throw 'Focused tests failed. Build not started.' }
    if ($Full) {
        & flutter test
        if ($LASTEXITCODE -ne 0) { throw 'Full test suite failed. Build not started.' }
    }
    & git -c 'core.whitespace=trailing-space,space-before-tab,cr-at-eol' diff --check
    if ($LASTEXITCODE -ne 0) { throw 'Whitespace check failed.' }
    if ($Build) {
        if (-not (Test-Path -LiteralPath 'android/app/google-services.json')) { throw 'android/app/google-services.json is missing.' }
        & flutter build apk --debug
        if ($LASTEXITCODE -ne 0) { throw 'APK build failed.' }
        $apkPath = Join-Path $env:USERPROFILE ('Downloads\AGRICO-scoped-operations-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.apk')
        Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-debug.apk' -Destination $apkPath
        Write-Host "APK saved: $apkPath"
    }
    & git status --short
    Write-Host 'No automatic commit, push, merge, phone install or app-data reset.'
} finally { Pop-Location }
