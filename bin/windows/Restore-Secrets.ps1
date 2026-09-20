<#
.SYNOPSIS
  Vault(Vaultwarden / Bitwarden)에서 SSH 키·설정 등 비공개 자료를 이 PC로 복원합니다.
  modules/secrets.sh 의 restore 절반을 PowerShell로 옮긴 것입니다.

.DESCRIPTION
  install.sh 는 Windows에서 돌지 않습니다 (lib/platform.sh 의 detect_platform 이
  Linux/Darwin 만 통과시킴). 그래서 docs/windows.md 의 다른 항목들과 같은 방식으로,
  이 스크립트를 직접 실행합니다.

  무엇을 복원할지는 이 파일이 아니라 vault 안의 manifest(기본 항목명 bootstrap)가
  정합니다. 레포에는 엔진만 있고 목록은 마스터 비밀번호 뒤에 있으므로, 이 파일은
  공개 레포에 그대로 둘 수 있습니다.

  어디까지 복원할지는 scope 가 정합니다. 한 vault 가 여러 삶을 담으므로
  (personal / work / shared / mixed), 기본값은 personal 하나뿐입니다. bash 판과
  같은 규칙이고 같은 파일(~/.config/settings/secrets.scope)을 읽습니다.

  push(= vault 에 올리는 쪽, scripts/secrets-push.sh)는 포팅하지 않았습니다.
  Windows 에만 있는 비밀은 없고, manifest 를 쓰는 주체가 둘이면 갈리기 때문입니다.

  main 의 secrets 엔진은 kitbag 으로 넘어갔지만(docs/kitbag.md) kitbag 은 아직
  macOS·Linux 바이너리만 냅니다. 그래서 Windows 에서는 manifest 엔진이 유일한
  경로이고, 이 스크립트가 그 엔진입니다. bash 쪽에서 같은 것을 부르는 이름은
  SETTINGS_SECRETS_ENGINE=bash 입니다.

.PARAMETER Scope
  복원할 scope. 쉼표로 여러 개, 또는 all. 지정하지 않으면
  $env:SETTINGS_SECRETS_SCOPE, 그다음 ~/.config/settings/secrets.scope,
  그래도 없으면 personal.

.PARAMETER Skip
  이 기기에서만 건너뛸 항목 이름. 쉼표로 여러 개. 지정하지 않으면
  $env:SETTINGS_SECRETS_SKIP, 그다음 ~/.config/settings/secrets.skip.

  scope 도 platform 도 이 질문에 답하지 못하는 경우가 있습니다. vault 의
  ssh:id_ed25519 는 어느 기기의 키이고 scope 는 personal 인데, 이미 자기 키를
  가진 기기는 그것을 받으면 안 됩니다 - 두 기기가 같은 키를 쓰면 한쪽만
  폐기할 수도, 로그에서 구분할 수도 없습니다. manifest 가 아니라 기기 쪽에
  두는 이유도 그것입니다: vault 의 사실이 아니라 이 기기의 사정입니다.

.PARAMETER DryRun
  아무것도 쓰지 않고 무엇이 복원될지만 출력합니다. 비밀번호를 묻지 않습니다.
  이미 세션이 있으면($env:BW_SESSION) 실제 manifest 를 열거합니다.

.EXAMPLE
  .\Restore-Secrets.ps1 -DryRun
  .\Restore-Secrets.ps1
  .\Restore-Secrets.ps1 -Scope all
  .\Restore-Secrets.ps1 -Skip ssh:id_ed25519
  .\Restore-Secrets.ps1 -VaultServer https://vault.example.com -Manifest my-bootstrap

.NOTES
  bash 판과 다른 점은 넷뿐입니다.

  1. 퍼미션. Windows OpenSSH 는 POSIX 모드를 무시하고 ACL 을 봅니다. chmod 600 을
     그대로 옮기면 상속된 ACE 가 남아 ssh 가 UNPROTECTED PRIVATE KEY FILE 로 키를
     거부합니다. 그래서 mode 의 group/other 자리가 0 인 항목은 상속을 끊고 현재
     사용자만 남깁니다.
  2. platform 필드. manifest 항목에 "platform": ["macos"] 가 있으면 건너뜁니다.
     app:aas / app:barshelf / app:otpeek 은 ~/Library 와 open -a 를 쓰므로
     Windows 에서 실행되면 안 됩니다.
  3. exec 항목. bash 판은 bash -c 로 실행하지만 여기엔 sh 가 없습니다. 파이프나
     리다이렉션이 섞인 명령은 실행하지 않고 왜 못 하는지를 말합니다.
     gpg --import 처럼 단순한 것만 stdin 으로 바이트 그대로 흘려보냅니다.
  4. ssh:authorized_keys. 그 exec 는 sh 로 쓰인 "합쳐라, 지우지 마라" 한 줄인데,
     3번 때문에 여기서는 돌지 않습니다. 명령을 흉내내는 대신 같은 규칙을
     PowerShell 로 구현합니다. 새 기기가 기존 기기들에서 닿을 수 있게 되는
     경로라서, 건너뛰면 그 기기만 조용히 고립됩니다.

  jq 는 필요 없습니다. ConvertFrom-Json 이 대신합니다.
#>
[CmdletBinding()]
param(
  # Vault 주소
  [string]$VaultServer = $(if ($env:SETTINGS_VAULT_SERVER) { $env:SETTINGS_VAULT_SERVER } else { "https://vault.jiun.dev" }),

  # manifest 를 담고 있는 항목 이름
  [string]$Manifest = $(if ($env:SETTINGS_VAULT_MANIFEST) { $env:SETTINGS_VAULT_MANIFEST } else { "bootstrap" }),

  # 0=인증 앱, 1=이메일, 3=YubiKey
  [string]$TwoFactorMethod = $(if ($env:SETTINGS_VAULT_2FA_METHOD) { $env:SETTINGS_VAULT_2FA_METHOD } else { "0" }),

  # Vaultwarden 에 대해 검증된 bw 버전. 다르면 경고만 합니다.
  [string]$BwVersion = $(if ($env:SETTINGS_BW_CLI_VERSION) { $env:SETTINGS_BW_CLI_VERSION } else { "2026.8.0" }),

  # 복원할 scope. 빈 값이면 환경변수 -> 파일 -> personal 순으로 정해집니다.
  [string]$Scope = $(if ($env:SETTINGS_SECRETS_SCOPE) { $env:SETTINGS_SECRETS_SCOPE } else { "" }),

  # scope 를 이 기기의 기본값으로 적어두는 파일. bash 판과 같은 경로입니다.
  [string]$ScopeFile = $(if ($env:SETTINGS_SECRETS_SCOPE_FILE) { $env:SETTINGS_SECRETS_SCOPE_FILE } else { Join-Path $HOME ".config\settings\secrets.scope" }),

  # 이 기기에서만 건너뛸 항목 이름. 쉼표로 여러 개.
  [string]$Skip = $(if ($env:SETTINGS_SECRETS_SKIP) { $env:SETTINGS_SECRETS_SKIP } else { "" }),

  # -Skip 을 이 기기의 기본값으로 적어두는 파일.
  [string]$SkipFile = $(if ($env:SETTINGS_SECRETS_SKIP_FILE) { $env:SETTINGS_SECRETS_SKIP_FILE } else { Join-Path $HOME ".config\settings\secrets.skip" }),

  # 쓰지 않고 계획만 출력
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# 이 스크립트가 도는 플랫폼. manifest 의 platform 필드와 맞춥니다.
$script:Platform = "windows"

function Info([string]$m) { Write-Host "  $m" -ForegroundColor DarkGray }
function Ok([string]$m)   { Write-Host "  + $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Die([string]$m)  { Write-Host "Restore-Secrets: $m" -ForegroundColor Red; exit 1 }
function Section([string]$m) {
  Write-Host ""
  Write-Host "== $m" -ForegroundColor Cyan
}

# ==============================================================================
# bw 호출
# ==============================================================================

# bw 를 실행하고 stdout 을 문자열로 돌려줍니다. 실패하면 $null.
# stderr 은 버리되 예외로 만들지 않습니다. bw 는 정상 동작 중에도 경고를 씁니다.
function Invoke-Bw {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$BwArgs)
  $out = & bw @BwArgs 2>$null
  if ($LASTEXITCODE -ne 0) { return $null }
  if ($null -eq $out) { return "" }
  return ($out -join "`n")
}

function Assert-VaultCli {
  if (-not (Get-Command bw -ErrorAction SilentlyContinue)) {
    Die "bw(Bitwarden CLI)가 없습니다. winget install Bitwarden.CLI 또는 npm install -g @bitwarden/cli@$BwVersion"
  }
  $have = & bw --version 2>$null | Select-Object -Last 1
  if ($have -and $have.Trim() -ne $BwVersion) {
    Warn "bw $($have.Trim()) 은 검증된 $BwVersion 이 아닙니다. Vaultwarden 에서 로그인이 깨질 수 있습니다."
    Info "실패하면: bw logout 후 npm install -g @bitwarden/cli@$BwVersion"
  }
}

# ==============================================================================
# 세션
# ==============================================================================

# SecureString -> 평문. BW_PASSWORD 환경변수로만 넘기고 즉시 지웁니다.
function ConvertFrom-SecureStringPlain([System.Security.SecureString]$s) {
  return [System.Net.NetworkCredential]::new("", $s).Password
}

function Invoke-VaultLogin {
  Info "Vault 로그인 - 마스터 비밀번호와 인증 코드가 필요합니다"
  $email  = Read-Host "  Email"
  $secure = Read-Host "  Master password" -AsSecureString
  $code   = Read-Host "  Verification code (TOTP, 없으면 빈 줄)"

  $env:BW_PASSWORD = ConvertFrom-SecureStringPlain $secure
  try {
    if ([string]::IsNullOrWhiteSpace($code)) {
      $session = Invoke-Bw login $email --passwordenv BW_PASSWORD --raw
    } else {
      $session = Invoke-Bw login $email --passwordenv BW_PASSWORD --method $TwoFactorMethod --code $code.Trim() --raw
    }
  } finally {
    $env:BW_PASSWORD = $null
  }
  return $session
}

function Unlock-Vault {
  $statusJson = Invoke-Bw status
  $status = "unauthenticated"
  $serverUrl = $null
  if ($statusJson) {
    try {
      $parsed = $statusJson | ConvertFrom-Json
      $status = $parsed.status
      $serverUrl = $parsed.serverUrl
    } catch {
      $status = "unauthenticated"
    }
  }

  # 서버는 로그아웃 상태에서만 바꿀 수 있습니다.
  if ($status -eq "unauthenticated") {
    $current = Invoke-Bw config server
    if (-not $current -or $current.Trim() -ne $VaultServer) {
      Info "Vault server: $VaultServer"
      [void](Invoke-Bw config server $VaultServer)
    }
  } elseif ($serverUrl -and $serverUrl -ne $VaultServer) {
    Warn "$serverUrl 에 로그인되어 있는데 요청한 서버는 $VaultServer 입니다."
    Die "다른 vault 로 바꾸려면 먼저 bw logout"
  }

  $session = $null
  switch ($status) {
    "unauthenticated" {
      $session = Invoke-VaultLogin
    }
    "locked" {
      Info "Vault 가 잠겨 있습니다"
      $secure = Read-Host "  Master password" -AsSecureString
      $env:BW_PASSWORD = ConvertFrom-SecureStringPlain $secure
      try { $session = Invoke-Bw unlock --passwordenv BW_PASSWORD --raw } finally { $env:BW_PASSWORD = $null }
      if (-not $session) {
        # 저장된 로그인을 서버가 더 이상 받지 않는 경우(만료·폐기된 refresh token)와
        # 비밀번호 오타가 똑같이 여기로 떨어집니다. 어느 쪽이든 재로그인이 출구입니다.
        Warn "해제 실패 - 저장된 로그인이 거부되었거나 비밀번호가 틀립니다. 다시 로그인합니다."
        [void](Invoke-Bw logout)
        [void](Invoke-Bw config server $VaultServer)
        $session = Invoke-VaultLogin
      }
    }
    "unlocked" {
      if ($env:BW_SESSION) {
        $session = $env:BW_SESSION
      } else {
        Info "Vault 는 해제 상태인데 BW_SESSION 이 없습니다"
        $secure = Read-Host "  Master password" -AsSecureString
        $env:BW_PASSWORD = ConvertFrom-SecureStringPlain $secure
        try { $session = Invoke-Bw unlock --passwordenv BW_PASSWORD --raw } finally { $env:BW_PASSWORD = $null }
      }
    }
  }

  if (-not $session) { Die "vault 세션을 얻지 못했습니다" }
  $env:BW_SESSION = $session.Trim()

  Info "Vault 동기화 중..."
  if ($null -eq (Invoke-Bw sync)) { Warn "bw sync 실패 - 캐시된 내용으로 진행합니다" }
  Ok "Vault 해제됨"
}

# ==============================================================================
# 항목 조회
# ==============================================================================

# bw get item <name> 은 검색입니다. 이름이 겹치는 두 번째 항목이 있으면
# (env:foo 옆의 env:foo-staging) "More than one result" 로 실패하므로,
# 목록을 한 번만 받아 정확한 이름으로 직접 맞춥니다.
$script:ItemsCache = $null

function Get-VaultItem([string]$Name) {
  if ($null -eq $script:ItemsCache) {
    $json = Invoke-Bw list items
    if (-not $json) { Die "bw list items 실패 - vault 가 잠겨 있지 않은지 확인하세요" }
    $script:ItemsCache = @($json | ConvertFrom-Json)
  }
  $hit = @($script:ItemsCache | Where-Object { $_.name -eq $Name })
  if ($hit.Count -eq 0) { return $null }
  return $hit[0]
}

# bw 가 마지막으로 받아온 항목 수. "없다" 는 말에 근거를 달기 위한 것입니다.
function Get-VaultItemCount {
  if ($null -eq $script:ItemsCache) { return -1 }
  return @($script:ItemsCache).Count
}

# 마지막 동기화 시각. 캐시가 낡았는지를 가르는 단 하나의 사실이고, vault 가
# 잠긴 상태에서도 읽힙니다. "10일 전" 한 줄이면 원인을 찾을 필요가 없습니다.
function Get-LastSyncText {
  $json = Invoke-Bw status
  if (-not $json) { return $null }
  try { $last = ($json | ConvertFrom-Json).lastSync } catch { return $null }
  if (-not $last) { return "한 번도 없음" }
  $dt = [datetime]$last
  $days = [int]([datetime]::UtcNow - $dt.ToUniversalTime()).TotalDays
  return "{0:yyyy-MM-dd HH:mm} ({1}일 전)" -f $dt.ToLocalTime(), $days
}

function Get-Prop($Object, [string]$Name) {
  if ($null -eq $Object) { return $null }
  if (-not $Object.PSObject.Properties[$Name]) { return $null }
  return $Object.$Name
}

# 항목에서 payload 를 꺼내 파일로 씁니다. 성공하면 $true.
function Get-Payload {
  param([string]$ItemName, [string]$Source, [string]$OutFile)

  $item = Get-VaultItem $ItemName
  if (-not $item) { Warn "vault 에 없는 항목: $ItemName"; return $false }

  $text = $null

  if ($Source -eq "notes") {
    $text = Get-Prop $item "notes"
  } elseif ($Source -eq "sshkey") {
    $text = Get-Prop (Get-Prop $item "sshKey") "privateKey"
  } elseif ($Source -eq "password") {
    $text = Get-Prop (Get-Prop $item "login") "password"
  } elseif ($Source.StartsWith("field:")) {
    $fname = $Source.Substring(6)
    $fields = @(Get-Prop $item "fields")
    $hit = @($fields | Where-Object { $_ -and $_.name -eq $fname })
    if ($hit.Count -gt 0) { $text = $hit[0].value }
  } elseif ($Source.StartsWith("attachment:")) {
    $fname = $Source.Substring(11)
    $atts = @(Get-Prop $item "attachments")
    # 이름이 아니라 id 로 받습니다. 예전 push 가 같은 이름의 첨부를 남겨두면
    # bw get attachment <name> 이 "More than one result" 로 실패합니다.
    # 목록의 마지막이 가장 최근에 올라간 것입니다.
    $cands = @($atts | Where-Object { $_ -and $_.fileName -eq $fname })
    if ($cands.Count -eq 0) { Warn "$ItemName 에 '$fname' 첨부가 없습니다"; return $false }
    [void](Invoke-Bw get attachment $cands[-1].id --itemid $item.id --output $OutFile)
    if (-not (Test-Path -LiteralPath $OutFile) -or (Get-Item -LiteralPath $OutFile).Length -eq 0) {
      Warn "첨부 내려받기 실패: $ItemName/$fname"
      return $false
    }
    return $true
  } else {
    Warn "알 수 없는 source: $Source"
    return $false
  }

  if ([string]::IsNullOrEmpty($text)) { Warn "빈 payload: $ItemName ($Source)"; return $false }

  # 개행은 LF 로 고정합니다. OpenSSH 와 gpg 는 CRLF 가 섞인 키를 읽지 못합니다.
  $text = $text -replace "`r`n", "`n"
  # 마지막 개행도 반드시 붙입니다. secrets-push.sh 는 노트를 "$(cat …)" 로 담는데
  # 명령 치환이 끝의 개행을 먹으므로, vault 에 있는 키는 개행 없이 저장돼 있습니다.
  # bash 판은 jq -r 이 개행을 다시 붙여줘 티가 나지 않지만 ConvertFrom-Json 에는
  # 그런 동작이 없고, 개행 하나가 없는 개인키는 ssh-keygen 이 곧바로
  # "error in libcrypto" 로 거부합니다.
  if (-not $text.EndsWith("`n")) { $text += "`n" }
  [System.IO.File]::WriteAllText($OutFile, $text, (New-Object System.Text.UTF8Encoding($false)))
  return $true
}

# ==============================================================================
# 배치
# ==============================================================================

# 상속을 끊고 현재 사용자만 남깁니다. chmod 600 에 해당하는 Windows 쪽 동작이고,
# OpenSSH 가 개인키에 대해 실제로 검사하는 것이기도 합니다.
function Protect-Path([string]$Path) {
  $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
  $isDir = Test-Path -LiteralPath $Path -PathType Container
  $inherit = if ($isDir) { "ContainerInherit,ObjectInherit" } else { "None" }

  $acl = Get-Acl -LiteralPath $Path
  $acl.SetAccessRuleProtection($true, $false)
  foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRule($rule) }
  $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
    $me, "FullControl", $inherit, "None", "Allow")))
  Set-Acl -LiteralPath $Path -AclObject $acl
}

# 상속을 되돌립니다. payload 는 잠긴 작업 디렉터리 안에서 만들어지고, 같은 볼륨
# 안에서의 Move-Item 은 DACL 을 그대로 들고 갑니다. 그래서 그냥 두면 공개키(644)
# 조차 목적지의 상속 ACL 이 아니라 TEMP 에서 온 단일 ACE 를 달고 도착합니다 -
# SYSTEM 과 Administrators 가 빠진 채로. 빈 FileSecurity 를 보호 해제 상태로
# 씌우면 명시 ACE 가 사라지고 목적지 폴더의 상속 ACL 만 남습니다.
function Reset-InheritedAcl([string]$Path) {
  $fresh = New-Object System.Security.AccessControl.FileSecurity
  $fresh.SetAccessRuleProtection($false, $false)
  Set-Acl -LiteralPath $Path -AclObject $fresh
}

# mode 의 group/other 자리가 0 이면 비공개 파일로 봅니다 (600, 700, 400, 0600...).
function Test-PrivateMode([string]$Mode) {
  if ([string]::IsNullOrWhiteSpace($Mode)) { return $true }
  return ($Mode -match '^[0-7]?[0-7]00$')
}

function Expand-DestPath([string]$Dest) {
  $p = $Dest
  if ($p -eq "~") {
    $p = $HOME
  } elseif ($p.StartsWith("~/") -or $p.StartsWith("~\")) {
    $p = Join-Path $HOME $p.Substring(2)
  }
  return [System.IO.Path]::GetFullPath(($p -replace '/', '\'))
}

function Test-SameContent([string]$A, [string]$B) {
  if ((Get-Item -LiteralPath $A).Length -ne (Get-Item -LiteralPath $B).Length) { return $false }
  return (Get-FileHash -LiteralPath $A -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $B -Algorithm SHA256).Hash
}

function Copy-Into {
  param([string]$Tmp, [string]$Dest, [string]$Mode)

  if (Test-Path -LiteralPath $Dest -PathType Leaf) {
    if (Test-SameContent $Tmp $Dest) {
      # 내용이 같아도 ACL 은 다시 맞춥니다. 이 포팅이 존재하는 이유가 퍼미션이라,
      # 손으로 복사해 왔거나 Move-Item 직후에 죽은 실행이 남긴 "내용은 맞는데
      # ACL 이 틀린" 키를 그냥 두면 재실행으로도 영영 고쳐지지 않고 ssh 는 계속
      # UNPROTECTED PRIVATE KEY FILE 로 거부합니다. 멱등이라 비용도 없습니다.
      if (Test-PrivateMode $Mode) { Protect-Path $Dest } else { Reset-InheritedAcl $Dest }
      Remove-Item -LiteralPath $Tmp -Force -ErrorAction SilentlyContinue
      Ok "$Dest (변경 없음)"
      return
    }
    $backup = "$Dest.backup." + (Get-Date -Format "yyyyMMddHHmmss")
    Move-Item -LiteralPath $Dest -Destination $backup
    Info "백업: $Dest -> $backup"
  }

  $dir = Split-Path -Parent $Dest
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  # 디렉터리 ACL 은 건드리지 않습니다. 프로필에서 상속된 ACL 이 이미 사용자 +
  # SYSTEM + Administrators 뿐이고, Windows OpenSSH 는 키 파일을 검사하지
  # 디렉터리를 검사하지 않습니다. 여기서 상속을 끊으면 ~/.ssh 전체가 영향을 받습니다.

  Move-Item -LiteralPath $Tmp -Destination $Dest -Force
  if (Test-PrivateMode $Mode) { Protect-Path $Dest } else { Reset-InheritedAcl $Dest }
  Ok "복원: $Dest"
}

# ==============================================================================
# exec 항목
# ==============================================================================

# 따옴표를 존중하는 최소 토크나이저. sh 가 아니므로 치환은 하지 않습니다.
function Split-Command([string]$Cmd) {
  $tokens = @()
  $cur = ""
  $quote = $null
  $quoted = $false
  foreach ($ch in $Cmd.ToCharArray()) {
    if ($quote) {
      if ($ch -eq $quote) { $quote = $null } else { $cur += $ch }
    } elseif ($ch -eq "'" -or $ch -eq '"') {
      $quote = $ch
      $quoted = $true
    } elseif ($ch -eq ' ' -or $ch -eq "`t") {
      if ($quoted -or $cur.Length -gt 0) { $tokens += $cur; $cur = ""; $quoted = $false }
    } else {
      $cur += $ch
    }
  }
  if ($quoted -or $cur.Length -gt 0) { $tokens += $cur }
  return $tokens
}

# ------------------------------------------------------------------------------
# 뜻만 같게 다시 구현한 exec
# ------------------------------------------------------------------------------
# manifest 의 exec 는 sh 한 줄입니다. 대부분은 그 항목이 macOS 전용이라 여기서
# 돌 필요가 없지만, 하나는 다릅니다: ssh:authorized_keys 는 새 기기가 기존
# 기기들에서 닿을 수 있게 만드는 경로라 Windows 에서도 반드시 적용돼야 합니다.
# 명령 문자열을 흉내내는 대신, 그 명령이 말하는 계약("합쳐라, 아무것도 지우지
# 마라")을 PowerShell 로 구현합니다. push 가 항목 이름을 바꾸면 여기서 못 찾고
# 아래의 거부 메시지로 떨어집니다 - 조용히 건너뛰는 것보다 낫습니다.
function Get-NativeExec([string]$ItemName) {
  if ($ItemName -eq "ssh:authorized_keys") {
    return [pscustomobject]@{
      Describe = "~/.ssh/authorized_keys 에 병합 (추가만, 삭제 없음)"
      Action   = "Merge-AuthorizedKeys"
    }
  }
  return $null
}

# authorized_keys 는 덮어쓰면 안 되는 단 하나의 파일입니다. 이 기기에는 목록이
# 본 적 없는 키(CI 러너, 에이전트, 휴대폰)가 있을 수 있고, 통째로 바꾸면 그것들이
# 말없이 잠깁니다. 그래서 없는 줄만 더하고 아무것도 지우지 않습니다 - bash 쪽
# AUTHORIZED_KEYS_MERGE 와 같은 규칙이고, 같은 판정(타입 + base64 부분 일치)입니다.
function Merge-AuthorizedKeys {
  param([string]$ItemName, [string]$PayloadFile)

  $sshDir = Join-Path $HOME ".ssh"
  if (-not (Test-Path -LiteralPath $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
  }
  $dest = Join-Path $sshDir "authorized_keys"

  $lines = @()
  if (Test-Path -LiteralPath $dest -PathType Leaf) {
    $lines = @([System.IO.File]::ReadAllLines($dest))
  }
  # 비교는 파일 전체에 대한 부분 일치입니다. 같은 키가 다른 코멘트나 다른 옵션을
  # 달고 있어도 두 번 들어가지 않습니다.
  $haystack = ($lines -join "`n")

  $added = 0
  foreach ($raw in [System.IO.File]::ReadAllLines($PayloadFile)) {
    $line = $raw.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith("#")) { continue }
    $parts = @($line -split '\s+')
    if ($parts.Count -lt 2) { continue }
    $material = $parts[0] + " " + $parts[1]
    if ($haystack.Contains($material)) { continue }
    $lines += $line
    $haystack = $haystack + "`n" + $line
    $added++
  }

  if ($added -eq 0) {
    # 파일이 없는데 더할 줄도 없는 경우(payload 가 주석과 빈 줄뿐)가 있습니다.
    # 그때는 만들 것도, 퍼미션을 맞출 것도 없습니다. 아래 Protect-Path 가
    # 없는 경로에 Get-Acl 을 걸어 이 항목만 실패로 보고되던 자리입니다.
    if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) {
      Ok "$ItemName (목록에 키가 없어 $dest 를 만들지 않았습니다)"
      return
    }
    Ok "$ItemName (이미 다 있음, $dest 그대로)"
  } else {
    [System.IO.File]::WriteAllText($dest, (($lines -join "`n") + "`n"),
      (New-Object System.Text.UTF8Encoding($false)))
    Ok "$ItemName -> $dest ($added 개 추가, 삭제 없음)"
    # 이 계정이 관리자면 sshd 는 이 파일이 아니라 ProgramData 쪽을 봅니다.
    # 키를 넣었는데 여전히 로그인이 안 되는 경우의 답이 거의 항상 이것입니다.
    Info "이 계정이 Administrators 면 Windows sshd 는 C:\ProgramData\ssh\administrators_authorized_keys 를 읽습니다"
  }
  # 내용이 그대로여도 ACL 은 다시 맞춥니다. sshd 는 상속된 ACE 가 남은
  # authorized_keys 를 거부합니다.
  Protect-Path $dest
}

function Invoke-ExecEntry {
  param([string]$ItemName, [string]$Cmd, [string]$PayloadFile)

  # sh 가 없으므로 셸 문법이 섞이면 실행하지 않습니다. 조용히 반쯤 실행되는
  # 것보다, 무엇을 못 했는지 말하는 편이 낫습니다.
  if ($Cmd -match '[|;&<>`]' -or $Cmd.Contains('$(')) {
    Warn "$ItemName 건너뜀 - 셸 문법이 있는 exec 는 Windows 에서 실행할 수 없습니다:"
    Info "  $Cmd"
    Info '  해당 항목이 macOS 전용이면 manifest 에 "platform": ["macos"] 를 넣으세요.'
    Info "  Windows 에도 필요한 것이면 Get-NativeExec 에 구현을 추가해야 합니다."
    return
  }

  $tokens = @(Split-Command $Cmd)
  if ($tokens.Count -eq 0) { Warn "$ItemName 의 exec 가 비어 있습니다"; return }

  $exe = Get-Command $tokens[0] -CommandType Application -ErrorAction SilentlyContinue
  if (-not $exe) { Warn "$ItemName 건너뜀 - '$($tokens[0])' 를 찾을 수 없습니다"; return }

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = @($exe)[0].Source
  for ($i = 1; $i -lt $tokens.Count; $i++) { [void]$psi.ArgumentList.Add($tokens[$i]) }
  $psi.RedirectStandardInput = $true
  $psi.UseShellExecute = $false

  $proc = [System.Diagnostics.Process]::Start($psi)
  try {
    # 바이트 그대로 흘려보냅니다. 텍스트로 파이프하면 인코딩이 섞입니다.
    $fs = [System.IO.File]::OpenRead($PayloadFile)
    try { $fs.CopyTo($proc.StandardInput.BaseStream) } finally { $fs.Dispose() }
    $proc.StandardInput.Close()
  } catch {
    # 자식이 stdin 을 다 읽기 전에 끝나면(망가진 armor 를 gpg 가 즉시 거절하는
    # 경우) 파이프가 끊기면서 CopyTo 가 IOException 을 던집니다. 바로 아래의 두
    # 실패 경로와 마찬가지로, 그 항목만 경고로 끝나야 합니다.
    Warn "$ItemName 실패 - stdin 으로 넘기는 중 끊겼습니다: $($_.Exception.Message)"
    try { $proc.StandardInput.Close() } catch { }
    try { if (-not $proc.HasExited) { $proc.Kill() } } catch { }
    $proc.WaitForExit()
    return
  }
  $proc.WaitForExit()

  if ($proc.ExitCode -eq 0) { Ok "$ItemName -> $Cmd" }
  else { Warn "$ItemName 실패 (exit $($proc.ExitCode)): $Cmd" }
}

# ==============================================================================
# scope
# ==============================================================================

# 이 기기가 복원할 scope. -Scope, 그다음 환경변수(파라미터 기본값에서 이미
# 읽었습니다), 그다음 기기가 스스로 적어둔 파일, 마지막이 안전한 기본값
# personal. 순서도 파일 경로도 bash 판(secrets_scope)과 같습니다 - 같은 기기에서
# WSL 과 PowerShell 이 서로 다른 것을 복원하면 그 자체가 버그입니다.
function Resolve-Scope {
  if (-not [string]::IsNullOrWhiteSpace($Scope)) { return ($Scope -replace '\s', '') }
  if (Test-Path -LiteralPath $ScopeFile) {
    $fromFile = (Get-Content -LiteralPath $ScopeFile -Raw -ErrorAction SilentlyContinue) -replace '\s', ''
    if (-not [string]::IsNullOrWhiteSpace($fromFile)) { return $fromFile }
  }
  return "personal"
}

# 이 기기가 이름으로 거절하는 항목들. scope 도 platform 도 "이 기기가 아니다"
# 라고 말하지 못하는 경우가 있습니다 - vault 의 ssh:id_ed25519 는 누군가의
# 기기 키이고, 이미 자기 키를 가진 기기는 그것을 받아선 안 됩니다. 덮어쓰면 두
# 기기가 같은 키를 쓰게 되어 한쪽만 폐기할 수도, 로그에서 구분할 수도 없습니다.
#
# manifest 가 아니라 기기 쪽에 두는 이유: 이것은 vault 의 사실이 아니라 이
# 기기의 사정입니다. 같은 항목을 다른 기기는 받아야 합니다.
function Resolve-SkipList {
  $raw = $Skip
  if ([string]::IsNullOrWhiteSpace($raw) -and (Test-Path -LiteralPath $SkipFile)) {
    $raw = ((Get-Content -LiteralPath $SkipFile -ErrorAction SilentlyContinue) |
      Where-Object { $_ -and -not $_.TrimStart().StartsWith("#") }) -join ","
  }
  if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
  return @($raw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# 항목의 scope 가 요청한 scope 에 드는가.
# 여러 삶이 한 덩어리에 섞인 항목(mixed)은 밖에서 쪼갤 수 없으므로 어느 scope 로도
# 복원합니다. scope 가 아예 없는 항목은 scope 가 생기기 전에 쓰인 manifest 이고,
# bash 판과 같이 mixed 로 봅니다.
function Test-ScopeWanted([string]$EntryScope, [string]$Want) {
  if ($Want -eq "all") { return $true }
  if ([string]::IsNullOrWhiteSpace($EntryScope) -or $EntryScope -eq "mixed") { return $true }
  return (@($Want -split ',') -contains $EntryScope)
}

# ==============================================================================
# manifest
# ==============================================================================

# "match" | "skip" | "invalid".
#
# platform 이 없으면 어디서나 복원합니다. 문자열 하나도 배열처럼 받습니다. 이름을
# 하나도 담지 않은 값("" 이나 [])은 "제약을 말하지 않은 것"으로 봅니다 - bash 판의
# [[ -n "$platforms" ]] 과 같은 판정이라야 같은 manifest 가 두 엔진에서 다르게
# 동작하지 않습니다. 숫자나 객체처럼 이름이 될 수 없는 값은 manifest 오류이므로
# 어느 쪽으로도 추측하지 않고 그 항목만 버립니다. 조용히 "어디서나"로 읽으면
# 오타 하나가 macOS 전용 항목을 Windows 에 풀어놓게 됩니다.
function Get-PlatformVerdict($Platform) {
  if ($null -eq $Platform) { return "match" }
  $list = @($Platform)
  if ($list.Count -eq 0) { return "match" }
  foreach ($p in $list) { if ($p -isnot [string]) { return "invalid" } }
  $named = @($list | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($named.Count -eq 0) { return "match" }
  if ($named -contains $script:Platform) { return "match" }
  return "skip"
}

function Invoke-Manifest([string]$TmpDir) {
  Section "Restoring Secrets"

  $manifestItem = Get-VaultItem $Manifest
  if (-not $manifestItem) {
    # 이 자리에서 제일 흔한 원인은 "vault 에 없다" 가 아니라 "이 기기가 아직
    # 못 받았다" 입니다. bw 는 로컬 캐시를 읽고 unlock 은 그걸 복호화만 하므로,
    # 다른 기기에서 push 한 직후의 manifest 는 sync 전까지 보이지 않습니다.
    Warn "manifest 항목 '$Manifest' 을 찾을 수 없습니다 (이 기기가 받아온 항목 $(Get-VaultItemCount)개 중에는 없습니다)"
    $sync = Get-LastSyncText
    if ($sync) { Info "마지막 동기화: $sync" }
    Info "그 뒤에 다른 기기에서 push 했다면 캐시가 낡은 것입니다: bw sync"
    Info "이름이 다르다면: -Manifest <항목명> 또는 SETTINGS_VAULT_MANIFEST"
    Die "manifest 를 읽지 못했습니다"
  }
  $notes = Get-Prop $manifestItem "notes"
  if ([string]::IsNullOrWhiteSpace($notes)) { Die "manifest '$Manifest' 의 notes 가 비어 있습니다" }

  try { $parsed = $notes | ConvertFrom-Json }
  catch { Die "manifest '$Manifest' 이 올바른 JSON 이 아닙니다: $_" }

  # entries 만은 Get-Prop 을 거치면 안 됩니다. 함수의 반환값은 파이프라인을
  # 지나며 언롤링돼서, 원소가 하나인 배열은 PSCustomObject 로, 빈 배열은 $null 로
  # 바뀝니다 - 키 하나짜리 manifest 로 시작한 부트스트랩이 "배열이 아니다" 로
  # 거절당하는 게 그 결과입니다. 직접 대입은 세 경우 모두 Object[] 를 보존합니다.
  # 존재 여부는 따로 봐야 합니다. @($null) 이 원소 하나짜리 배열이라 Count 로는
  # "entries 없음" 과 "entries 가 하나" 를 구분할 수 없기 때문입니다.
  if (-not $parsed.PSObject.Properties['entries']) { Die "manifest '$Manifest' 에 entries 가 없습니다" }
  $entriesRaw = $parsed.entries
  if ($entriesRaw -isnot [System.Array]) { Die "manifest '$Manifest' 의 entries 가 배열이 아닙니다" }
  $entries = @($entriesRaw)

  $want = Resolve-Scope
  $skipList = Resolve-SkipList
  Info "manifest '$Manifest': $($entries.Count) entries, scope '$want'"
  if ($skipList.Count -gt 0) { Info "이 기기가 건너뛰도록 지정된 항목: $($skipList -join ', ')" }

  $legacy = @($entries | Where-Object { -not $_.PSObject.Properties['scope'] }).Count
  if ($legacy -gt 0) {
    Warn "$legacy 개 항목에 scope 가 없습니다 (scope 이전에 쓰인 manifest) - mixed 로 복원합니다"
  }

  $skipped = 0
  foreach ($e in $entries) {
    $item = Get-Prop $e "item"

    # 한 항목의 실패가 나머지를 데려가지 않도록 감쌉니다. $ErrorActionPreference
    # 가 Stop 이라 잠긴 파일에 대한 Move-Item 하나(편집기나 살아있는 ssh 가
    # ~/.ssh/config 를 잡고 있으면 실제로 IOException 입니다)가 Invoke-Manifest
    # 밖으로 튀어나가면, 뒤에 남은 항목은 아무 말 없이 전부 복원되지 않습니다.
    # bash 판의 apply_manifest 는 항목마다 로그를 남기고 continue 합니다.
    # try 안의 continue 는 switch 와 달리 바깥 foreach 를 정상적으로 넘깁니다.
    try {
      $src  = Get-Prop $e "source"; if (-not $src) { $src = "notes" }
      $dest = Get-Prop $e "dest"
      $mode = Get-Prop $e "mode";   if (-not $mode) { $mode = "600" }
      $exec = Get-Prop $e "exec"
      $plat = Get-Prop $e "platform"
      $escope = Get-Prop $e "scope"

      # 이름으로 거절한 것이 제일 먼저입니다. 사용자가 직접 지목한 것이라,
      # 다른 어떤 판정보다 먼저 그리고 눈에 띄게 말해야 합니다.
      if ($skipList -contains $item) {
        Info "건너뜀 $item (이 기기에서 제외)"
        continue
      }

      # scope 가 먼저입니다. 이 기기가 아예 원하지 않는 삶의 비밀은 dest 가
      # 멀쩡한지조차 따질 필요가 없습니다.
      if (-not (Test-ScopeWanted $escope $want)) {
        $skipped++
        continue
      }

      if (($dest -and $exec) -or (-not $dest -and -not $exec)) {
        Warn "$item 항목에는 dest 와 exec 중 정확히 하나가 필요합니다"
        continue
      }

      # dry run 보다 먼저 봅니다. 그래야 dry run 에도 건너뛴 항목이 보입니다.
      # switch 안의 continue 는 switch 만 빠져나가므로 여기서는 쓰지 않습니다.
      $verdict = Get-PlatformVerdict $plat
      if ($verdict -eq "skip") {
        Info "건너뜀 $item (platform: $(@($plat) -join ' '))"
        continue
      }
      if ($verdict -eq "invalid") {
        Warn "$item 건너뜀 - platform 은 문자열이거나 문자열 배열이어야 합니다"
        continue
      }

      $native = if ($exec) { Get-NativeExec $item } else { $null }

      if ($DryRun) {
        $sink = if ($dest) { $dest } elseif ($native) { $native.Describe } else { $exec }
        $label = if ($escope) { $escope } else { "mixed" }
        Info "[DRY-RUN] $item [$label] ($src) -> $sink"
        continue
      }

      $payload = Join-Path $TmpDir "payload"
      if (Test-Path -LiteralPath $payload) { Remove-Item -LiteralPath $payload -Force }
      if (-not (Get-Payload -ItemName $item -Source $src -OutFile $payload)) { continue }

      if ($dest) {
        Copy-Into -Tmp $payload -Dest (Expand-DestPath $dest) -Mode $mode
      } elseif ($native) {
        & $native.Action -ItemName $item -PayloadFile $payload
        Remove-Item -LiteralPath $payload -Force -ErrorAction SilentlyContinue
      } else {
        Invoke-ExecEntry -ItemName $item -Cmd $exec -PayloadFile $payload
        Remove-Item -LiteralPath $payload -Force -ErrorAction SilentlyContinue
      }
    } catch {
      Warn "$item 실패: $($_.Exception.Message)"
    }
  }

  if ($skipped -gt 0) {
    Info "scope '$want' 밖이라 건너뛴 항목 $skipped 개 (-Scope all 이면 전부)"
  }
}

function New-ScratchDir {
  $p = Join-Path $env:TEMP ("settings-secrets-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
  New-Item -ItemType Directory -Path $p | Out-Null
  return $p
}

# ==============================================================================
# main
# ==============================================================================

Section "Secrets ($VaultServer)"

if ($DryRun) {
  # dry run 은 bw 가 없어도 계획을 말할 수 있어야 합니다. docs/windows.md 의
  # 설치 순서를 그대로 따라오는 새 PC 는 아직 bw 가 없는 상태로 여기에 닿는데,
  # 계획을 보여주라는 실행이 그걸 이유로 아무 말도 못 하면 곤란합니다.
  # bash 판의 ensure_vault_cli 도 DRY_RUN 이면 "설치할 것" 만 알리고 통과합니다.
  if (Get-Command bw -ErrorAction SilentlyContinue) {
    Assert-VaultCli
  } else {
    Info "[DRY-RUN] 설치 필요: @bitwarden/cli@$BwVersion"
  }
  # scope 는 vault 가 잠겨 있어도 말할 수 있고, 잠겨 있을 때 제일 알고 싶은
  # 값이기도 합니다. 기본값이 personal 하나라는 것을 모르고 "일부만 복원됐다"로
  # 읽는 것이 이 스크립트의 가장 흔한 오해입니다.
  Info "[DRY-RUN] $VaultServer 를 열고 manifest '$Manifest' 을 scope '$(Resolve-Scope)' 로 적용합니다"
  if ($env:BW_SESSION) {
    # 여기서만 bash 판과 다르게 굽니다. bw 는 로컬 캐시를 읽고 unlock 은 그걸
    # 복호화만 하므로, 동기화 없이 열거하면 다른 기기에서 방금 push 한 내용을
    # 못 본 채로 "이게 복원될 것" 이라고 말하게 됩니다. 그건 계획을 보여주는
    # 명령이 할 수 있는 최악의 거짓말입니다. sync 는 읽기 전용이라 비용도 없습니다.
    Info "Vault 동기화 중..."
    if ($null -eq (Invoke-Bw sync)) { Warn "bw sync 실패 - 캐시된 내용으로 열거합니다" }
    $tmp = New-ScratchDir
    try { Invoke-Manifest $tmp } finally { Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue }
  } else {
    Info "[DRY-RUN] vault 가 잠겨 있습니다 - 항목을 보려면 먼저 bw unlock"
  }
  exit 0
}

Assert-VaultCli
Unlock-Vault

# 비밀 자료가 잠깐이라도 다른 사용자에게 읽히지 않도록, 작업 디렉터리부터 잠급니다.
$tmpDir = New-ScratchDir
Protect-Path $tmpDir

try {
  Invoke-Manifest $tmpDir
} finally {
  Remove-Item -Recurse -Force -LiteralPath $tmpDir -ErrorAction SilentlyContinue
}

Write-Host ""
Info "이 셸에서 vault 는 열린 채로 남습니다. 끝나면 bw lock."
Ok "복원 완료"
