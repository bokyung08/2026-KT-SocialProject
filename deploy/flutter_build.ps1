# ---------------------------------------------------------------------------
# Flutter 웹 빌드를 Kotlin 서버 static 리소스 경로에 반영한다.
#
#   pwsh deploy/flutter_build.ps1
#
# Flutter SDK가 PATH에 없으면 FLUTTER_HOME 환경변수로 설치 경로를 지정할 것.
#   $env:FLUTTER_HOME = "C:\Users\BREW\AppData\Local\flutter"
# ---------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

$AppDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$FlutterDir = Join-Path $AppDir "frontend\pm_safeline_flutter"
$StaticDir = Join-Path $AppDir "src\main\resources\static"

if ($env:FLUTTER_HOME) {
    $env:Path = "$env:FLUTTER_HOME\bin;" + $env:Path
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "flutter 명령을 찾을 수 없습니다. PATH에 추가하거나 FLUTTER_HOME을 설정하세요."
}

Set-Location $FlutterDir

Write-Output "[flutter_build] 의존성 설치..."
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get 실패 (exit $LASTEXITCODE)" }

Write-Output "[flutter_build] 웹 빌드..."
flutter build web --release
if ($LASTEXITCODE -ne 0) { throw "flutter build web 실패 (exit $LASTEXITCODE)" }

Write-Output "[flutter_build] static 경로 교체: $StaticDir"
if (Test-Path $StaticDir) { Remove-Item $StaticDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $StaticDir | Out-Null
Copy-Item -Path (Join-Path $FlutterDir "build\web\*") -Destination $StaticDir -Recurse -Force

Write-Output "[flutter_build] 완료 -> $StaticDir"
