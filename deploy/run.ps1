# ---------------------------------------------------------------------------
# 현재 계정에서 서버를 실행하고, main 변경을 감지하면 자동으로 새로고침한다.
# (권한/유닛/전용 사용자 불필요 — 그냥 실행해두면 됨)
#
#   pwsh deploy/run.ps1
#
# 로그아웃해도 계속 돌리려면 백그라운드 작업(Start-Process)이나
# Windows 작업 스케줄러에 등록해서 실행할 것.
#
# 매 주기 `git pull`만 시도한다. 실패하면(충돌, 네트워크 등) 그냥 무시하고
# 다음 주기에 재시도한다 — 어떤 경우에도 이미 떠 있는 서버는 건드리지 않는다.
#
# 환경변수:
#   PM_BRANCH        추적 브랜치        (기본 main)
#   PM_POLL_SECONDS  변경 확인 주기(초) (기본 60)
#   PM_PORT          서버 포트          (기본 21000)
# 서버 자체 설정(PM_OSM_FILE 등)은 프로젝트 루트 .env 에서 자동 로드된다.
# ---------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

$Branch = if ($env:PM_BRANCH) { $env:PM_BRANCH } else { "main" }
$Interval = if ($env:PM_POLL_SECONDS) { [int]$env:PM_POLL_SECONDS } else { 60 }
$Port = if ($env:PM_PORT) { $env:PM_PORT } else { "21000" }
$AppDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not $env:JAVA_HOME -or -not (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe"))) {
    throw "JAVA_HOME이 설정되어 있지 않거나 유효하지 않습니다. 예: `$env:JAVA_HOME = 'C:\Users\BREW\.jdks\jbr-21.0.11'"
}

# build.gradle.kts: 프로젝트 경로에 비-ASCII(한글)가 있으면 classpath 인코딩 문제를 피하려고
# 빌드 출력을 %TEMP%\gradle-build-<rootProject.name>으로 리다이렉트한다 (safety = rootProject.name).
$BuildDir = if ($AppDir -match '[^\x00-\x7F]') {
    Join-Path $env:TEMP "gradle-build-safety"
} else {
    Join-Path $AppDir "build"
}
$InstallDir = Join-Path $BuildDir "install\safety"

Set-Location $AppDir

$script:ServerProcess = $null

function Build-App {
    Write-Output "[run] 빌드 중..."
    & "$AppDir\gradlew.bat" --no-daemon -q installDist
    if ($LASTEXITCODE -ne 0) { throw "gradle installDist 실패 (exit $LASTEXITCODE)" }
}

function Start-Server {
    # installDist가 만든 safety.bat은 classpath를 cmd.exe 명령줄에 그대로 펼치는데,
    # 이 프로젝트는 의존성(GraphHopper 등)이 많아 cmd.exe 명령줄 길이 제한(8191자)을
    # 넘겨 "입력 줄이 너무 깁니다" 오류가 난다. cmd(.bat)를 거치지 않고 java.exe를
    # 직접 실행하면 CreateProcess 제한(32767자)이 적용되어 문제없이 뜬다.
    $javaExe = Join-Path $env:JAVA_HOME "bin\java.exe"
    $classpath = (Get-ChildItem (Join-Path $InstallDir "lib") -Filter "*.jar" |
        ForEach-Object { $_.FullName }) -join ";"
    $script:ServerProcess = Start-Process -FilePath $javaExe `
        -ArgumentList @("-classpath", "`"$classpath`"", "kt.dinjae.pm_safeline.MainKt", "-port=$Port") `
        -PassThru -NoNewWindow
    Write-Output "[run] 서버 시작 (pid $($script:ServerProcess.Id)) -> http://localhost:$Port"
}

function Stop-Server {
    if ($script:ServerProcess -and -not $script:ServerProcess.HasExited) {
        Write-Output "[run] 서버 중지 (pid $($script:ServerProcess.Id))"
        Stop-Process -Id $script:ServerProcess.Id -Force -ErrorAction SilentlyContinue
        $script:ServerProcess.WaitForExit()
    }
    $script:ServerProcess = $null
}

try {
    Build-App
    Start-Server

    Write-Output "[run] '$Branch' 변경 감시 중 (${Interval}s 간격). 종료: Ctrl+C"
    while ($true) {
        Start-Sleep -Seconds $Interval

        # 서버가 죽었으면 되살림
        if ($script:ServerProcess -and $script:ServerProcess.HasExited) {
            Write-Output "[run] 서버가 종료되어 있음 -> 재시작"
            Start-Server
        }

        $before = (& git rev-parse HEAD 2>$null)
        & git pull --quiet 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Output "[run] git pull 실패 (exit $LASTEXITCODE), 다음 주기 재시도"
            continue
        }
        $after = (& git rev-parse HEAD 2>$null)
        if ($before -eq $after) { continue }

        Write-Output "[run] 새 커밋 감지 -> 새로고침"
        try {
            Stop-Server
            Build-App
            Start-Server
        } catch {
            Write-Output "[run] 새로고침 실패, 다음 주기 재시도: $_"
        }
    }
}
finally {
    Stop-Server
}
