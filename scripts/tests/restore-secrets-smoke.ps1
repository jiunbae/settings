<#
.SYNOPSIS
  bin/windows/Restore-Secrets.ps1 에 대한 회귀 테스트.

.DESCRIPTION
  scripts/tests/secrets-scope-smoke.sh 의 Windows 쪽 짝입니다. bash 판은
  Windows 에서 아예 돌지 않으므로(lib/platform.sh 가 MSYS 를 거부합니다) 복원
  엔진의 Windows 절반은 여기서만 검증됩니다.

  bw 는 stub 이고 HOME 은 임시 디렉터리입니다. 진짜 vault 도, 진짜 비밀도, 이
  사용자의 ~/.ssh 도 건드리지 않습니다.

      pwsh -NoProfile -File scripts/tests/restore-secrets-smoke.ps1
#>
#Requires -Version 7
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Target   = Join-Path $RepoRoot "bin\windows\Restore-Secrets.ps1"
$TestRoot = Join-Path $env:TEMP ("restore-secrets-smoke-" + [guid]::NewGuid().ToString("N").Substring(0, 8))

$script:Failures = 0

function Pass([string]$m) { Write-Host "  $([char]0x2713) $m" -ForegroundColor Green }
function Fail([string]$m) { Write-Host "  $([char]0x2717) $m" -ForegroundColor Red; $script:Failures++ }

function Check([string]$What, $Expected, $Actual) {
  if ("$Expected" -eq "$Actual") { Pass $What }
  else { Fail $What; Write-Host "      expected: $Expected"; Write-Host "      actual:   $Actual" }
}
function Contains([string]$What, [string]$Needle, [string]$Hay) {
  if ($Hay -and $Hay.Contains($Needle)) { Pass $What } else { Fail "$What (missing: $Needle)" }
}
function Lacks([string]$What, [string]$Needle, [string]$Hay) {
  if ($Hay -and $Hay.Contains($Needle)) { Fail "$What (unexpected: $Needle)" } else { Pass $What }
}

# ==============================================================================
# 가짜 vault
# ==============================================================================

# 실제 키여야 하는 것은 하나뿐입니다. 복원된 개인키가 ssh-keygen 을 통과하는지가
# 이 포팅이 존재하는 이유(개행과 ACL)를 직접 확인하는 유일한 방법입니다.
function New-Fixture {
  param([string]$HomeDir)

  New-Item -ItemType Directory -Path $HomeDir -Force | Out-Null
  $bin   = Join-Path $HomeDir "bin"
  $state = Join-Path $HomeDir "state"
  New-Item -ItemType Directory -Path $bin, $state -Force | Out-Null

  # 진짜 ed25519 키 한 쌍. HOME 밖에서 만들어 vault 항목에만 담습니다.
  $keyPath = Join-Path $state "seed_ed25519"
  # -N '' 이어야 암호 없는 키가 나옵니다. -N '""' 는 따옴표 두 개를 암호로 가진
  # 키를 만들고, 그러면 아래의 ssh-keygen -y 가 암호를 물으며 멈춥니다.
  & ssh-keygen -q -t ed25519 -N '' -C "fixture@test" -f $keyPath 2>&1 | Out-Null
  if (-not (Test-Path -LiteralPath $keyPath)) { throw "ssh-keygen 실패: 테스트를 돌릴 수 없습니다" }
  # vault 는 노트를 끝 개행 없이 들고 있습니다 - secrets-push.sh 가 "$(cat …)" 로
  # 담기 때문입니다. 웹 vault 를 Windows 브라우저로 편집하면 CRLF 도 섞입니다.
  # 복원이 둘 다 되돌려놓는지가 여기서 검증됩니다.
  $priv = ([System.IO.File]::ReadAllText($keyPath)).TrimEnd("`n") -replace "`n", "`r`n"
  $pub  = ([System.IO.File]::ReadAllText("$keyPath.pub")).Trim()

  $binaryPayload = [byte[]](0, 1, 2, 3, 250, 251, 252, 253)
  [System.IO.File]::WriteAllBytes((Join-Path $state "att-fixture.bin"), $binaryPayload)

  $listKeys = @(
    "# scope: personal",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa one@host-a",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb two@host-b"
  ) -join "`n"

  # exec 가 payload 를 바이트 그대로 stdin 으로 받는지 보는 탐침. Windows 에
  # 기본으로 있는 것 중 stdin 을 받아 파일로 쓰면서 셸 문법이 필요 없는 명령이
  # 마땅치 않아(sort /O 는 입력을 코드페이지로 뭉갭니다) 하나 만들어 씁니다.
  $execOut = (Join-Path $state "exec-probe.bin")
  [System.IO.File]::WriteAllText((Join-Path $bin "exec-probe.ps1"), @'
param([string]$Out)
$in = [Console]::OpenStandardInput()
$buf = New-Object System.IO.MemoryStream
$in.CopyTo($buf)
[System.IO.File]::WriteAllBytes($Out, $buf.ToArray())
'@, (New-Object System.Text.UTF8Encoding($false)))
  $probeCmd = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $bin 'exec-probe.ps1')`" `"$execOut`""

  # manifest. secrets-push.sh 가 쓰는 것과 같은 모양이고, ssh:authorized_keys 의
  # exec 는 그 스크립트의 AUTHORIZED_KEYS_MERGE 를 글자 그대로 옮긴 것입니다.
  $manifest = [ordered]@{
    version = 2
    entries = @(
      [ordered]@{ item = "ssh:id_ed25519"; source = "notes";        dest = "~/.ssh/id_ed25519";     mode = "600"; scope = "personal" },
      [ordered]@{ item = "ssh:id_ed25519"; source = "field:public"; dest = "~/.ssh/id_ed25519.pub"; mode = "644"; scope = "personal" },
      [ordered]@{ item = "env:work";       source = "notes";        dest = "~/.envs/work.env";      mode = "600"; scope = "work" },
      [ordered]@{ item = "env:shared";     source = "notes";        dest = "~/.envs/shared.env";    mode = "600"; scope = "shared" },
      [ordered]@{ item = "file:fixture";   source = "attachment:fixture.bin"; dest = "~/fixture.bin"; mode = "600"; scope = "personal" },
      [ordered]@{ item = "ssh:authorized_keys"; source = "notes"; scope = "personal"
                  exec = 'umask 077; mkdir -p "$HOME/.ssh"; while IFS= read -r l; do grep -qF "$l" "$HOME/.ssh/authorized_keys" || printf "%s\n" "$l" >> "$HOME/.ssh/authorized_keys"; done' },
      [ordered]@{ item = "app:barshelf"; source = "notes"; exec = "tar -xzf -"; scope = "personal"; platform = @("macos") },
      [ordered]@{ item = "probe:plain"; source = "notes"; exec = $probeCmd; scope = "personal" },
      [ordered]@{ item = "legacy:noscope"; source = "notes"; dest = "~/legacy.txt"; mode = "600" }
    )
  }

  $items = @(
    [ordered]@{ id = "item-1"; name = "bootstrap"; notes = ($manifest | ConvertTo-Json -Depth 10) },
    [ordered]@{ id = "item-2"; name = "ssh:id_ed25519"; notes = $priv
                fields = @([ordered]@{ name = "public"; value = $pub }) },
    [ordered]@{ id = "item-3"; name = "env:work";   notes = "WORK_TOKEN=w" },
    [ordered]@{ id = "item-4"; name = "env:shared"; notes = "SHARED_TOKEN=s" },
    [ordered]@{ id = "item-5"; name = "ssh:authorized_keys"; notes = $listKeys },
    [ordered]@{ id = "item-6"; name = "app:barshelf"; notes = "never read here" },
    [ordered]@{ id = "item-7"; name = "probe:plain";  notes = "b`na" },
    [ordered]@{ id = "item-8"; name = "legacy:noscope"; notes = "from before scopes" },
    [ordered]@{ id = "item-9"; name = "file:fixture"
                attachments = @([ordered]@{ id = "att-fixture"; fileName = "fixture.bin" }) }
  )
  [System.IO.File]::WriteAllText((Join-Path $state "items.json"),
    ($items | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))

  # bw stub. 상태는 파일에 있으므로 호출 간에 id 가 흔들리지 않습니다.
  $stub = @'
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$BwArgs)
$state = $env:BW_STUB_STATE
switch ($BwArgs[0]) {
  "--version" { "2026.8.0"; exit 0 }
  "status"    { '{"status":"unlocked","serverUrl":"https://vault.test","lastSync":"2026-09-20T00:00:00.000Z"}'; exit 0 }
  "sync"      { exit 0 }
  "lock"      { exit 0 }
  "logout"    { exit 0 }
  "config"    { "https://vault.test"; exit 0 }
  "list"      { if ($BwArgs[1] -eq "items") { Get-Content -LiteralPath (Join-Path $state "items.json") -Raw; exit 0 }; exit 1 }
  "get"       {
    if ($BwArgs[1] -eq "attachment") {
      $id = $BwArgs[2]
      $out = $null
      for ($i = 3; $i -lt $BwArgs.Count; $i++) { if ($BwArgs[$i] -eq "--output") { $out = $BwArgs[$i + 1] } }
      $src = Join-Path $state "att-$($id -replace '^att-', '').bin"
      if (-not (Test-Path -LiteralPath $src) -or -not $out) { exit 1 }
      $dir = Split-Path -Parent $out
      if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
      Copy-Item -LiteralPath $src -Destination $out -Force
      exit 0
    }
    exit 1
  }
}
exit 1
'@
  [System.IO.File]::WriteAllText((Join-Path $bin "bw-stub.ps1"), $stub, (New-Object System.Text.UTF8Encoding($false)))

  # bw 자체는 .cmd 입니다. 읽기 호출은 여기서 바로 답하고, 첨부를 내려받는
  # 것만 위의 PowerShell stub 으로 넘깁니다 - 한 번의 복원이 bw 를 예닐곱 번
  # 부르는데, 매번 pwsh 를 띄우면 테스트가 분 단위로 길어집니다.
  $cmd = @(
    "@echo off",
    'if "%~1"=="--version" (echo 2026.8.0& exit /b 0)',
    'if "%~1"=="status" (echo {"status":"unlocked","serverUrl":"https://vault.test","lastSync":"2026-09-20T00:00:00.000Z"}& exit /b 0)',
    'if "%~1"=="sync" exit /b 0',
    'if "%~1"=="lock" exit /b 0',
    'if "%~1"=="logout" exit /b 0',
    'if "%~1"=="config" (echo https://vault.test& exit /b 0)',
    'if "%~1"=="list" (type "%BW_STUB_STATE%\items.json"& exit /b 0)',
    'pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0bw-stub.ps1" %*',
    "exit /b %ERRORLEVEL%"
  ) -join "`r`n"
  [System.IO.File]::WriteAllText((Join-Path $bin "bw.cmd"), $cmd + "`r`n",
    (New-Object System.Text.ASCIIEncoding))

  return [pscustomobject]@{
    HomeDir = $HomeDir; Bin = $bin; State = $state
    PublicKey = $pub; ExecProbe = $execOut
    ListKeys = @("one@host-a", "two@host-b")
  }
}

# 자식 pwsh 로 실제 스크립트를 돌립니다. $HOME 은 USERPROFILE 에서 오므로
# 가짜 홈은 환경변수 하나로 끝납니다.
function Invoke-Restore {
  param([object]$Fixture, [string[]]$ScriptArgs = @(), [hashtable]$Env = @{})

  $saved = @{}
  $vars = @{
    USERPROFILE              = $Fixture.HomeDir
    HOME                     = $Fixture.HomeDir
    PATH                     = "$($Fixture.Bin);$env:PATH"
    BW_STUB_STATE            = $Fixture.State
    BW_SESSION               = "stub-session"
    SETTINGS_VAULT_SERVER    = "https://vault.test"
    SETTINGS_SECRETS_SCOPE   = ""
  }
  foreach ($k in $Env.Keys) { $vars[$k] = $Env[$k] }

  foreach ($k in $vars.Keys) {
    $saved[$k] = [Environment]::GetEnvironmentVariable($k)
    [Environment]::SetEnvironmentVariable($k, $vars[$k])
  }
  try {
    $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $Target @ScriptArgs 2>&1
    return ($out | Out-String)
  } finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
  }
}

# ssh-keygen 이 복원된 개인키를 읽어내는가. stdin 을 닫고 부릅니다: 키가
# 망가졌으면 ssh-keygen 은 암호를 물으려 들고, 그대로 두면 실패가 아니라
# 영원한 정지로 나타납니다.
function Test-SshKeyReadable([string]$Path) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = (Get-Command ssh-keygen -CommandType Application | Select-Object -First 1).Source
  foreach ($a in @("-y", "-f", $Path)) { [void]$psi.ArgumentList.Add($a) }
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.StandardInput.Close()
  if (-not $p.WaitForExit(15000)) { try { $p.Kill() } catch { }; return $false }
  return ($p.ExitCode -eq 0)
}

# 이 파일의 ACL 이 상속을 끊고 이 사용자만 남겼는가 - 즉 chmod 600 에 해당하는가.
function Test-PrivateAcl([string]$Path) {
  $acl = Get-Acl -LiteralPath $Path
  if (-not $acl.AreAccessRulesProtected) { return $false }
  $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $others = @($acl.Access | Where-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -ne $me })
  return ($others.Count -eq 0)
}

# ==============================================================================
New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
try {

Write-Host ""
Write-Host "Restore-Secrets: dry run and scopes"

$fx = New-Fixture (Join-Path $TestRoot "dry")
$dry = Invoke-Restore $fx @("-DryRun")

Contains "the scope in force is named before anything is read" "scope 'personal'" $dry
Contains "a personal entry is listed"      "[DRY-RUN] ssh:id_ed25519 [personal]" $dry
Lacks    "a work entry is not"             "env:work" $dry
Lacks    "a shared entry is not"           "env:shared" $dry
Contains "an entry with no scope is mixed" "legacy:noscope [mixed]" $dry
Contains "and says the manifest predates scopes" "scope 가 없습니다" $dry
Contains "a macOS-only entry is skipped"   "app:barshelf (platform: macos)" $dry
Contains "the skipped count is reported"   "밖이라 건너뛴 항목 2 개" $dry
Contains "the merge is named, not its shell one-liner" "authorized_keys 에 병합" $dry
Lacks    "nothing was written"             "복원:" $dry
Check    "and the home is still empty" $false (Test-Path -LiteralPath (Join-Path $fx.HomeDir ".ssh"))

$all = Invoke-Restore $fx @("-DryRun", "-Scope", "all")
Contains "-Scope all takes the work entry"   "env:work" $all
Contains "-Scope all takes the shared entry" "env:shared" $all
Lacks    "but not a foreign platform"        "[DRY-RUN] app:barshelf" $all

$work = Invoke-Restore $fx @("-DryRun", "-Scope", "personal,work")
Contains "a comma list takes both"  "env:work" $work
Lacks    "and nothing more"         "env:shared" $work

$envScope = Invoke-Restore $fx @("-DryRun") -Env @{ SETTINGS_SECRETS_SCOPE = "shared" }
Contains "the environment sets the scope" "env:shared" $envScope
Lacks    "and replaces the default"       "ssh:id_ed25519" $envScope

$scopeFile = Join-Path $fx.HomeDir ".config\settings\secrets.scope"
New-Item -ItemType Directory -Path (Split-Path -Parent $scopeFile) -Force | Out-Null
Set-Content -LiteralPath $scopeFile -Value "work" -NoNewline
$fromFile = Invoke-Restore $fx @("-DryRun")
Contains "the machine's own file sets the default" "env:work" $fromFile
$override = Invoke-Restore $fx @("-DryRun", "-Scope", "personal")
Contains "-Scope still wins over the file" "ssh:id_ed25519" $override
Lacks    "and the file is not consulted"   "env:work" $override
Remove-Item -LiteralPath $scopeFile -Force

# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "Restore-Secrets: a real restore"

$fx = New-Fixture (Join-Path $TestRoot "run")
# 이 목록이 본 적 없는 키. 복원이 이것을 지우면 그 기기는 조용히 잠깁니다.
$sshDir = Join-Path $fx.HomeDir ".ssh"
New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
$ciKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIccccccccccccccccccccccccccccccccccccccccccc ci@runner"
[System.IO.File]::WriteAllText((Join-Path $sshDir "authorized_keys"), "$ciKey`n")

$run = Invoke-Restore $fx
$key = Join-Path $sshDir "id_ed25519"
$pub = Join-Path $sshDir "id_ed25519.pub"

Check "the private key is written" $true (Test-Path -LiteralPath $key)
$bytes = [System.IO.File]::ReadAllBytes($key)
Check "with no CR left in it"        $false ($bytes -contains 13)
Check "and a final newline"          10 $bytes[-1]
# 개행 하나가 없으면 ssh-keygen 은 여기서 error in libcrypto 로 떨어집니다.
Check "so ssh-keygen accepts the restored key" $true (Test-SshKeyReadable $key)

Check "the key's ACL is private"        $true  (Test-PrivateAcl $key)
Check "the public key keeps inheritance" $false (Test-PrivateAcl $pub)
Check "the .ssh directory is left alone" $false ((Get-Acl -LiteralPath $sshDir).AreAccessRulesProtected)

$authorized = [System.IO.File]::ReadAllText((Join-Path $sshDir "authorized_keys"))
Contains "a key the list never saw survives" "ci@runner" $authorized
Contains "the list's keys arrive"            "one@host-a" $authorized
Contains "all of them"                       "two@host-b" $authorized
Lacks    "the scope header is not copied in" "# scope:"  $authorized
Contains "the merge is reported as a merge"  "2 개 추가, 삭제 없음" $run
Check    "and the file is private"  $true (Test-PrivateAcl (Join-Path $sshDir "authorized_keys"))

$binary = [System.IO.File]::ReadAllBytes((Join-Path $fx.HomeDir "fixture.bin"))
Check "a binary attachment lands byte for byte" "0 1 2 3 250 251 252 253" ($binary -join " ")

Check "a plain exec gets the payload on stdin" $true (Test-Path -LiteralPath $fx.ExecProbe)
# 텍스트로 파이프하면 인코딩이 섞입니다. vault 에 담긴 노트가 바이트 단위로
# 그대로 도착해야 gpg --import 같은 것이 armor 를 읽을 수 있습니다.
Check "byte for byte, LF and a final newline" "98 10 97 10" `
  (([System.IO.File]::ReadAllBytes($fx.ExecProbe)) -join " ")

Lacks "a work secret never touched this machine" "work.env" $run
Check "nor landed"  $false (Test-Path -LiteralPath (Join-Path $fx.HomeDir ".envs\work.env"))
Check "nor did the macOS app entry" $false (Test-Path -LiteralPath (Join-Path $fx.HomeDir "Library"))

# 두 번째 실행은 아무것도 바꾸지 않습니다.
$again = Invoke-Restore $fx
Contains "re-running reports the key unchanged" "(변경 없음)" $again
Contains "and adds no keys"                     "이미 다 있음" $again
$authorized2 = [System.IO.File]::ReadAllText((Join-Path $sshDir "authorized_keys"))
Check "authorized_keys is byte-identical" $authorized $authorized2
Check "and no backup was made" 0 @(Get-ChildItem -LiteralPath $sshDir -Filter "*.backup.*").Count

# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "Restore-Secrets: things it must refuse"

# 셸 문법이 있는 exec 는 실행하지 않고, 그 항목만 건너뜁니다.
$fx = New-Fixture (Join-Path $TestRoot "refuse")
$itemsPath = Join-Path $fx.State "items.json"
$items = Get-Content -LiteralPath $itemsPath -Raw | ConvertFrom-Json
$manifest = ($items | Where-Object { $_.name -eq "bootstrap" }).notes | ConvertFrom-Json
# app:barshelf 의 platform 태그를 떼면, 남는 것은 여기서 돌 수 없는 sh 명령입니다.
$entry = $manifest.entries | Where-Object { $_.item -eq "app:barshelf" }
$entry.PSObject.Properties.Remove("platform")
$entry.exec = 'tar -xzf - -C "$HOME" && open -a BarShelf'
($items | Where-Object { $_.name -eq "bootstrap" }).notes = ($manifest | ConvertTo-Json -Depth 10)
[System.IO.File]::WriteAllText($itemsPath, ($items | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))

$refused = Invoke-Restore $fx
Contains "a shell exec is refused, not half-run" "셸 문법이 있는 exec" $refused
Contains "and says how to mark it macOS-only"    'platform": ["macos"]' $refused
Contains "the rest of the manifest still runs"   "복원:" $refused
Check    "including the key after it" $true (Test-Path -LiteralPath (Join-Path $fx.HomeDir ".ssh\id_ed25519"))

# 목록에 키가 하나도 없고(주석뿐) 이 기기에 authorized_keys 도 아직 없는 경우.
# 만들 것도 퍼미션을 맞출 것도 없는데, 없는 경로에 ACL 을 걸어 이 항목만
# 실패로 보고되던 자리입니다.
$fx = New-Fixture (Join-Path $TestRoot "emptykeys")
$itemsPath = Join-Path $fx.State "items.json"
$items = Get-Content -LiteralPath $itemsPath -Raw | ConvertFrom-Json
($items | Where-Object { $_.name -eq "ssh:authorized_keys" }).notes = "# scope: personal`n# (no keys)"
[System.IO.File]::WriteAllText($itemsPath, ($items | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))

$empty = Invoke-Restore $fx
Contains "a list of nothing creates no file" "만들지 않았습니다" $empty
Lacks    "and is not reported as a failure"  "ssh:authorized_keys 실패" $empty
Check    "the file really is absent" $false `
  (Test-Path -LiteralPath (Join-Path $fx.HomeDir ".ssh\authorized_keys"))
Check    "while the rest of the manifest landed" $true `
  (Test-Path -LiteralPath (Join-Path $fx.HomeDir ".ssh\id_ed25519"))

# manifest 항목이 없는 경우: 이 자리에서 제일 흔한 원인은 낡은 캐시입니다.
$fx = New-Fixture (Join-Path $TestRoot "nomanifest")
$itemsPath = Join-Path $fx.State "items.json"
$items = @(Get-Content -LiteralPath $itemsPath -Raw | ConvertFrom-Json | Where-Object { $_.name -ne "bootstrap" })
[System.IO.File]::WriteAllText($itemsPath, ($items | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
$missing = Invoke-Restore $fx
Contains "a missing manifest says how many items this machine holds" "항목 8개 중에는 없습니다" $missing
Contains "and when it last synced" "마지막 동기화: " $missing
Contains "and what to do about it" "bw sync" $missing

Write-Host ""
if ($script:Failures -gt 0) {
  Write-Host "$($script:Failures) test(s) failed" -ForegroundColor Red
  exit 1
}
Write-Host "all Restore-Secrets checks passed" -ForegroundColor Green

} finally {
  Remove-Item -Recurse -Force -LiteralPath $TestRoot -ErrorAction SilentlyContinue
}
