<#
.SYNOPSIS
  로그아웃해도 살아남는 rmux 서버(세션 0)를 준비하고 세션을 보장합니다.

.EXAMPLE
  start-rmux-session                      # 기본 라벨 / 세션 main 보장 후 상태 출력
  start-rmux-session -Attach              # 준비되면 바로 붙기
  start-rmux-session -Label dev -Session api -WorkDir C:\Users\jiun\workspace
  start-rmux-session -Status              # 현재 상태만
  start-rmux-session -Stop                # 서버 종료 (작업 등록은 유지)
  start-rmux-session -Remove              # 서버 종료 + 예약 작업 삭제

.NOTES
  Windows는 로그오프할 때 그 로그온 세션(콘솔/RDP)의 프로세스를 전부 종료합니다.
  터미널에서 그냥 띄운 rmux 데몬도 같이 죽습니다. 살아남게 하려면 데몬이
  세션 0(비대화형)에 있어야 하고, 그 방법이 작업 스케줄러의 S4U 실행
  ("사용자의 로그온 여부에 관계없이 실행")입니다. 작업 액션 프로세스가 끝나도
  rmux-daemon.exe 는 세션 0에 남습니다.

  rmux 의 파이프 이름은 rmux-<SID>-il-<무결성수준>-<라벨> 이라서, 클라이언트가
  서버를 찾으려면 계정 SID / 무결성 수준 / 라벨이 모두 같아야 합니다.
    - SYSTEM 으로 돌리면 SID 가 달라 붙지 못합니다. 반드시 본인 계정(S4U).
    - S4U 작업은 -RunLevel 과 무관하게 il-high 로 뜹니다. 그래서 이 스크립트도,
      평소 attach 하는 터미널도 관리자 권한이어야 합니다. 일반 권한 창은
      il-medium 을 찾다가 "No such file or directory" 로 실패합니다.
#>
[CmdletBinding()]
param(
  # rmux -L 라벨. 서버(데몬) 하나를 식별합니다.
  # 기본값 default 는 라벨 없는 bare `rmux` 와 같은 파이프를 씁니다. 다른 값으로
  # 띄우면 `rmux ls` 에는 안 보이고 `rmux -L <라벨> ls` 로 봐야 합니다.
  [string]$Label = 'default',

  # 보장할 세션 이름
  [string]$Session = 'main',

  # 세션의 시작 디렉터리 (세션 0의 기본 cwd 는 system32 라 명시가 필요)
  [string]$WorkDir = $env:USERPROFILE,

  # 예약 작업 이름 (기본: rmux-<라벨>)
  [string]$TaskName,

  # 준비된 뒤 바로 attach
  [switch]$Attach,

  # 예약 작업을 다시 등록
  [switch]$Force,

  # 상태만 출력하고 종료
  [switch]$Status,

  # 서버 종료 (예약 작업은 남김)
  [switch]$Stop,

  # 서버 종료 + 예약 작업 삭제
  [switch]$Remove,

  # 작업 스케줄러가 세션 0에서 호출하는 내부 진입점. 직접 쓰지 마세요
  [switch]$Ensure,

  # -Ensure 가 빈 서버를 띄울 때 muxa 스냅샷 복원을 건너뜀
  [switch]$NoRestore
)

$ErrorActionPreference = "Stop"
function Die($m) { Write-Host "start-rmux-session: $m" -ForegroundColor Red; exit 1 }
function Note($m) { Write-Host $m -ForegroundColor DarkGray }

if (-not $TaskName) { $TaskName = "rmux-$Label" }

$rmux = (Get-Command rmux.exe -ErrorAction SilentlyContinue).Source
if (-not $rmux) { $rmux = Join-Path $env:USERPROFILE ".cargo\bin\rmux.exe" }
if (-not (Test-Path $rmux)) { Die "rmux.exe 를 찾을 수 없습니다." }

# 세션 존재 확인. has-session 은 없으면 0 이 아닌 코드로 끝나고 stderr 에
# 연결 실패를 적으므로, 출력은 버리고 종료 코드만 봅니다.
function Test-RmuxSession {
  & $rmux -L $Label has-session -t $Session *>$null
  return ($LASTEXITCODE -eq 0)
}

# 복원하는 동안 서버를 살려두는 임시 세션. 스냅샷 세션과 겹치지 않을 이름
$BootPlaceholder = '__rmux_boot'

# muxa 최신 스냅샷을 빈 서버에 복원합니다. 스냅샷이 이 라벨의 서버(같은 SID /
# 무결성 수준 / 라벨 해시)에서 찍힌 것일 때만 합니다 — 파이프 끝의 랜덤 부분은
# 서버를 띄울 때마다 바뀌고, muxa 가 새 파이프를 알아서 따라갑니다.
function Invoke-BootRestore {
  $muxa = (Get-Command muxa.exe -ErrorAction SilentlyContinue).Source
  if (-not $muxa) { $muxa = Join-Path $env:USERPROFILE ".cargo\bin\muxa.exe" }
  if (-not (Test-Path $muxa)) { Log "muxa.exe 가 없어 복원하지 않음"; return }

  $plan = (& $muxa restore --json 2>$null) -join "`n"
  if ($LASTEXITCODE -ne 0 -or -not $plan) { Log "복원할 스냅샷이 없음"; return }
  $plan = $plan | ConvertFrom-Json

  $line = (& $rmux -L $Label diagnose --human 2>$null | Select-String 'socket_path' | Select-Object -First 1)
  if (-not ("$line" -match 'socket_path:\s*(\S*-g-[0-9a-f]+)-[0-9a-f]+')) { Log "rmux diagnose 를 읽지 못함"; return }
  $prefix = $Matches[1]
  if (-not "$($plan.socket)".StartsWith("$prefix-")) {
    Log "최신 스냅샷 $($plan.id) 은 다른 서버의 것이라 복원하지 않음 ($($plan.socket))"
    return
  }

  # muxa 는 살아 있는 서버의 파이프를 찾아 복원하므로 먼저 서버를 띄워 둡니다
  & $rmux -L $Label new-session -d -s $BootPlaceholder -c $WorkDir
  Start-Sleep -Milliseconds 500
  Log "스냅샷 $($plan.id) 복원 시작: $($plan.summary.sessions) 세션, $($plan.summary.panes) pane, 에이전트 $($plan.summary.agents)"
  & $muxa restore $plan.dir --run *>&1 | ForEach-Object { Log "  $_" }
  Log "복원 종료 (코드 $LASTEXITCODE)"
}

# ---- 세션 0에서 호출되는 경로 -----------------------------------------
# rmux 에는 "있으면 두고 없으면 만들기"가 없습니다. new-session -A 는 -d 와 같이
# 써도 attach 를 시도해 "open terminal failed: not a terminal" 로 끝나므로,
# has-session 으로 갈라줍니다.
#
# 서버가 아예 없을 때(= 부팅 직후)는 muxa 의 최신 스냅샷으로 먼저 복원합니다.
# muxad 가 15분마다 자동 스냅샷을 남기므로, 재부팅 전 세션/창/pane 과 그 안의
# Claude·Codex 대화가 그대로 돌아옵니다. 이미 세션이 있는 서버는 건드리지 않습니다.
# 세션 0 이라 화면이 없으니 결과는 $env:TEMP\rmux-boot-<라벨>.log 에 남깁니다.
if ($Ensure) {
  $log = Join-Path $env:TEMP "rmux-boot-$Label.log"
  function Log($m) { "$(Get-Date -Format s) $m" | Add-Content -LiteralPath $log -Encoding utf8 }

  & $rmux -L $Label ls *>$null
  $serverUp = ($LASTEXITCODE -eq 0)
  if (-not $serverUp -and -not $NoRestore) {
    try { Invoke-BootRestore } catch { Log "복원 실패: $_" }
  }
  if (-not (Test-RmuxSession)) {
    & $rmux -L $Label new-session -d -s $Session -c $WorkDir
  }
  $code = $LASTEXITCODE
  # 복원용으로 띄운 자리표시 세션은 $Session 이 생긴 뒤에 치워야 서버가 안 꺼집니다
  & $rmux -L $Label has-session -t $BootPlaceholder *>$null
  if ($LASTEXITCODE -eq 0) { & $rmux -L $Label kill-session -t $BootPlaceholder *>$null }
  exit $code
}

# ---- 헬퍼 -------------------------------------------------------------
# diagnose 가 찍는 socket_path 는 "...-il-<수준>-g-<라벨해시>-<호출마다 랜덤>"
# 형태입니다. 뒤쪽 랜덤을 뺀 앞부분이 이 라벨의 서버를 가리키는 고정 키라,
# 무결성 수준 확인과 데몬 프로세스 매칭에 그대로 씁니다.
function Get-RmuxKey {
  $line = (& $rmux -L $Label diagnose --human 2>$null | Select-String 'socket_path' | Select-Object -First 1)
  if (-not $line -or "$line" -notmatch 'socket_path:\s*(\S+)') { Die "rmux diagnose 를 읽지 못했습니다." }
  $pipe = $Matches[1]
  if ($pipe -notmatch '^(.*-il-([a-z]+)-g-[0-9a-f]+)-[0-9a-f]+$') { Die "socket_path 형식을 해석하지 못했습니다: $pipe" }
  return [pscustomobject]@{ Prefix = $Matches[1]; Integrity = $Matches[2] }
}

function Get-RmuxDaemon($prefix) {
  return Get-CimInstance Win32_Process -Filter "Name='rmux-daemon.exe'" |
         Where-Object { $_.CommandLine -like "*$prefix*" }
}

function Show-Status($key) {
  $d = Get-RmuxDaemon $key.Prefix
  if (-not $d) {
    Write-Host "서버: 없음 (라벨 $Label, $($key.Integrity))"
    return
  }
  foreach ($p in $d) {
    $where = if ($p.SessionId -eq 0) { "세션 0 - 로그아웃해도 유지" }
             else { "세션 $($p.SessionId) - 로그아웃하면 함께 종료됨" }
    Write-Host "서버: pid $($p.ProcessId), $where"
  }
  & $rmux -L $Label ls
  $sel = if ($Label -eq 'default') { '' } else { "-L $Label " }   # 기본 라벨이면 -L 없이 그대로 보인다
  Write-Host "붙기: rmux ${sel}attach -t $Session" -ForegroundColor Cyan
}

# ---- 정리 동작 --------------------------------------------------------
if ($Stop -or $Remove) {
  & $rmux -L $Label kill-server *>$null
  Write-Host "서버 종료: 라벨 $Label"
  if ($Remove) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "예약 작업 삭제: $TaskName"
  }
  exit 0
}

$key = Get-RmuxKey
if ($Status) { Show-Status $key; exit 0 }

# S4U 작업은 il-high 로 뜨므로, 여기서 medium 이면 만들어도 못 붙습니다.
if ($key.Integrity -ne 'high') {
  Die @"
지금 터미널의 무결성 수준이 '$($key.Integrity)' 입니다.
세션 0 서버는 il-high 로 뜨기 때문에 이 창에서는 붙을 수 없습니다.
관리자 권한 pwsh 에서 다시 실행하세요.
"@
}

# ---- 예약 작업 등록 ---------------------------------------------------
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($Force -and $task) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  $task = $null
}
if (-not $task) {
  $pwsh = (Get-Process -Id $PID).Path    # 이 스크립트를 돌리는 pwsh 그대로
  $taskArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Ensure -Label "{1}" -Session "{2}" -WorkDir "{3}"' `
              -f $PSCommandPath, $Label, $Session, $WorkDir
  $action = New-ScheduledTaskAction -Execute $pwsh -Argument $taskArgs -WorkingDirectory $WorkDir
  # S4U 는 비밀번호를 저장하지 않습니다. 네트워크 드라이브나 자격 증명 관리자가
  # 필요하면 -LogonType Password 로 바꾸고 비밀번호를 등록하세요.
  $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                 -LogonType S4U -RunLevel Highest
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger (New-ScheduledTaskTrigger -AtStartup) `
    -Principal $principal -Settings $settings -Force | Out-Null
  Write-Host "예약 작업 등록: $TaskName (부팅 시 자동 시작)"
}

# ---- 서버 기동 --------------------------------------------------------
if (-not (Test-RmuxSession)) {
  # 세션 2에 남은 데몬이 라벨을 잡고 있으면 세션 0 데몬이 못 뜹니다
  # ("an older RMUX daemon still owns this label").
  $stale = Get-RmuxDaemon $key.Prefix | Where-Object { $_.SessionId -ne 0 }
  if ($stale) {
    & $rmux -L $Label kill-server *>$null
    Note "로그인 세션에 있던 기존 데몬을 정리했습니다 (pid $($stale.ProcessId -join ', '))."
    Start-Sleep -Milliseconds 500
  }

  Start-ScheduledTask -TaskName $TaskName
  $deadline = (Get-Date).AddSeconds(20)
  while (-not (Test-RmuxSession) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
  if (-not (Test-RmuxSession)) {
    $code = (Get-ScheduledTaskInfo -TaskName $TaskName).LastTaskResult
    Die "세션을 만들지 못했습니다 (작업 결과 코드 $code). 이벤트 뷰어 > 작업 스케줄러 로그를 확인하세요."
  }
  Write-Host "세션 생성: $Session (라벨 $Label)" -ForegroundColor Green
}

Show-Status $key

if ($Attach) { & $rmux -L $Label attach -t $Session }
