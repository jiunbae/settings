<#
  Nextcloud 업로드 환경 설정 (cloud-upload CLI + rclone + 네트워크 드라이브)
  실행:  pwsh -ExecutionPolicy Bypass -File .\Setup-Nextcloud.ps1
  관리자 권한으로 실행하면 네트워크 드라이브 50MB 제한 해제까지 처리합니다.
#>
param(
  # 기본값 없음(이 레포는 public). 생략하면 기존 설정에서 읽거나 물어봅니다.
  [string]$Server      = "",
  [string]$RemoteDir   = "Uploads",
  [string]$DriveLetter = "Z",
  # /Uploads 를 캐시로 쓰기 위해 .nomedia 를 넣어 Photos/Memories/previewgenerator 에서 제외
  [bool]$NoMedia       = $true
)

$ErrorActionPreference = "Stop"
function Info($m) { Write-Host "  $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  OK   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  SKIP $m" -ForegroundColor Yellow }

# 서버 주소 확정: 인자 > 기존 .cloud-upload.json > 직접 입력
if (-not $Server) {
  $prev = Join-Path $env:USERPROFILE ".cloud-upload.json"
  if (Test-Path $prev) { $Server = (Get-Content $prev -Raw | ConvertFrom-Json).server }
}
if (-not $Server) { $Server = Read-Host "Nextcloud 서버 주소 (예: https://cloud.example.com)" }
$Server = $Server.TrimEnd('/')

$hostName = ([uri]$Server).Host
Write-Host "`n=== Nextcloud 업로드 설정 ($hostName) ===`n" -ForegroundColor White

# -- 1. 자격 증명 입력 --------------------------------------------------
$user = Read-Host "Nextcloud 사용자 ID"
$sec  = Read-Host "앱 비밀번호 (입력이 화면에 안 보입니다)" -AsSecureString
$pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
          [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))

$dav = "$Server/remote.php/dav/files/$user/"

# -- 2. 인증 확인 -------------------------------------------------------
Info "인증 확인 중..."
$code = & curl.exe -s -o NUL -w "%{http_code}" -u "${user}:${pass}" `
          -X PROPFIND -H "Depth: 0" $dav
if ($code -ne "207") {
  Write-Host "  FAIL 인증 실패 (HTTP $code). 사용자 ID / 앱 비밀번호를 확인하세요." -ForegroundColor Red
  Write-Host "       앱 비밀번호 발급: $Server/settings/user/security" -ForegroundColor Red
  exit 1
}
Ok "인증 성공 -> $dav"

# -- 3. curl 용 _netrc (비밀번호를 명령어/기록에 안 남기기 위함) ---------
$netrc = Join-Path $env:USERPROFILE "_netrc"
$line  = "machine $hostName login $user password $pass"
if (Test-Path $netrc) {
  $kept = Get-Content $netrc | Where-Object { $_ -notmatch "^machine\s+$([regex]::Escape($hostName))\s" }
  Set-Content $netrc (@($kept) + $line) -Encoding ascii
} else {
  Set-Content $netrc $line -Encoding ascii
}
Ok "_netrc 작성 -> $netrc"

# -- 4. cloud-upload 설정 파일 (ID를 매번 안 치기 위함) -------------------
$cfg = Join-Path $env:USERPROFILE ".cloud-upload.json"
[pscustomobject]@{ server = $Server; user = $user; remoteDir = $RemoteDir } |
  ConvertTo-Json | Set-Content $cfg -Encoding utf8
Ok "설정 저장 -> $cfg"

# -- 5. 원격 폴더 + .nomedia -------------------------------------------
& curl.exe -s -o NUL -u "${user}:${pass}" -X MKCOL "$dav$RemoteDir"
Ok "원격 폴더 준비 -> /$RemoteDir"

if ($NoMedia) {
  $tmp = New-TemporaryFile
  & curl.exe -s -o NUL -u "${user}:${pass}" -T $tmp.FullName "$dav$RemoteDir/.nomedia"
  Remove-Item $tmp -Force
  Ok ".nomedia 업로드 -> /$RemoteDir (Photos/Memories/previewgenerator 제외)"
}

# -- 6. cloud-upload 설치 (%USERPROFILE%\bin, PATH 등록) ----------------
$bin = Join-Path $env:USERPROFILE "bin"
New-Item -ItemType Directory -Force $bin | Out-Null

# settings 레포의 사본을 그대로 쓴다. 복사하면 두 벌이 갈라지므로
# $PROFILE 과 같은 방식으로 "가리키기"만 한다 (Windows 심볼릭 링크는 권한 필요).
$src = Join-Path $PSScriptRoot "cloud-upload.ps1"
if (Test-Path $src) {
  Remove-Item (Join-Path $bin "cloud-upload.ps1") -Force -ErrorAction SilentlyContinue
  @"
@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "$src" %*
"@ | Set-Content (Join-Path $bin "cloud-upload.cmd") -Encoding oem

  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($userPath -notlike "*$bin*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$bin", "User")
  }
  $env:PATH += ";$bin"
  Ok "cloud-upload 설치 -> $bin\cloud-upload.cmd  ->  $src"
} else {
  Warn "cloud-upload.ps1 을 찾을 수 없음 ($src)"
}

# -- 7. rclone 설치 + 원격 등록 -----------------------------------------
$env:PATH += ";$env:LOCALAPPDATA\Microsoft\WinGet\Links"
if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
  Info "rclone 설치 중 (winget)..."
  winget install -e --id Rclone.Rclone --accept-package-agreements --accept-source-agreements | Out-Null
  $env:PATH += ";$env:LOCALAPPDATA\Microsoft\WinGet\Links"
}
if (Get-Command rclone -ErrorAction SilentlyContinue) {
  rclone config delete nc 2>$null | Out-Null
  rclone config create nc webdav url=$dav vendor=nextcloud user=$user pass=$pass --obscure | Out-Null
  Ok "rclone 원격 'nc' 등록   (rclone sync C:\upload nc:$RemoteDir -P)"
} else {
  Warn "rclone 설치 실패 - 수동 설치 필요"
}

# -- 8. WebClient 서비스 + 파일 크기 제한 해제 ---------------------------
$admin = ([Security.Principal.WindowsPrincipal] `
          [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($admin) {
  Set-Service WebClient -StartupType Automatic
  $reg = "HKLM:\SYSTEM\CurrentControlSet\Services\WebClient\Parameters"
  Set-ItemProperty $reg FileSizeLimitInBytes 0xFFFFFFFF -Type DWord
  Set-ItemProperty $reg BasicAuthLevel       2          -Type DWord
  Restart-Service WebClient -Force
  Ok "WebClient 자동시작 + 파일 크기 제한 해제 (50MB -> 4GB)"
} else {
  Warn "관리자 아님 - 50MB 제한이 남습니다. 관리자 PowerShell에서 재실행하세요."
  if ((Get-Service WebClient).Status -ne "Running") { Start-Service WebClient }
}

# -- 9. 네트워크 드라이브 매핑 ------------------------------------------
& net use "${DriveLetter}:" /delete /y 2>$null | Out-Null
& net use "${DriveLetter}:" $dav /user:$user $pass /persistent:yes | Out-Null
if (Test-Path "${DriveLetter}:\") {
  Ok "네트워크 드라이브 매핑 -> ${DriveLetter}:  (탐색기에서 드래그앤드롭)"
} else {
  Warn "드라이브 매핑 실패 - WebClient 서비스 상태를 확인하세요."
}

# -- 10. 우클릭 '보내기' 메뉴 -------------------------------------------
$sendTo = Join-Path $env:APPDATA "Microsoft\Windows\SendTo\Nextcloud 업로드.cmd"
@"
@echo off
chcp 65001 >nul
pwsh -NoProfile -ExecutionPolicy Bypass -File "$src" %*
echo.
pause
"@ | Set-Content $sendTo -Encoding oem
Ok "우클릭 -> 보내기 -> 'Nextcloud 업로드' 등록"

Write-Host "`n=== 완료 ===`n" -ForegroundColor White
Write-Host "  cloud-upload `"C:\경로\파일.zip`""
Write-Host "  cloud-upload C:\logs\*.log -To logs"
Write-Host "  cloud-upload C:\build\dist -Share -Expire 7"
Write-Host "  탐색기: ${DriveLetter}: 드라이브 / 우클릭 -> 보내기`n"
Write-Host "  (PATH가 갱신되었으니 새 터미널을 여세요)`n" -ForegroundColor Yellow
