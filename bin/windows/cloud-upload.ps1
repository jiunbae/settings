<#
.SYNOPSIS
  Nextcloud로 파일/폴더를 업로드합니다. 이미 올라간 파일은 건너뜁니다.

.EXAMPLE
  cloud-upload report.pdf
  cloud-upload C:\logs\*.zip
  cloud-upload C:\build\dist -To builds        # 폴더 재귀 업로드 (변경분만)
  cloud-upload C:\build\dist -DryRun           # 무엇이 올라갈지만 확인
  cloud-upload C:\build\dist -Force            # 스킵 없이 전부 재업로드
  cloud-upload big.iso -Share -Expire 7        # 공개 링크를 클립보드로
  cloud-upload C:\proj -Exclude *.tmp,__pycache__,.git     # 제외 패턴 (여러 개)
  cloud-upload C:\proj -Exclude 'dist/*'       # '/' 가 있으면 상대경로 전체와 매칭

  자격 증명은 %USERPROFILE%\_netrc, 대상 정보는
  %USERPROFILE%\.cloud-upload.json 에서 읽습니다 (Setup-Nextcloud.ps1이 생성).

.NOTES
  중복 업로드 회피 (2026-09 실측, Nextcloud 32.0.3)
    - PROPFIND Depth:infinity 1회로 원격 트리 전체를 받아온다 (200개/62KB = 0.16s).
      Nextcloud가 거부하면(403) 디렉터리별 Depth:1 재귀로 자동 폴백.
    - 비교는 "크기 + mtime". 해시 비교는 불가능하다:
        · d:getetag 는 내용 해시가 아니라 서버 내부 값 (재현 불가)
        · oc:checksum 은 OC-Checksum 헤더를 보내도 저장되지 않음 (검증 완료)
        · 진짜 해시를 얻으려면 원격 파일을 내려받아야 하는데, 그건 재업로드보다 느리다
    - 업로드 시 X-OC-Mtime 헤더로 로컬 mtime을 그대로 심는다. 덕분에 다음 실행에서
      mtime이 정확히 일치하고 스킵 판정이 확실해진다.
    - 기존에 올라간(= mtime이 업로드 시각인) 파일은 "크기 같음 + 원격이 더 최신"이면
      스킵한다. 업로드 전용 워크플로에서는 안전한 규칙. 엄격히 하려면 -Strict.

  전송 방식
    - 기본(curl)  : 50MB 단일 80 MB/s   <- 가장 빠름
    - -Sync(rclone): 50MB 단일 24 MB/s
    이제 기본 경로도 변경분만 올리므로 -Sync 는 거의 필요 없다.
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
  [string[]]$Path,

  # 원격 하위 폴더 (기본: 설정의 remoteDir)
  [string]$To,

  # 변경된 파일만 전송 (rclone). 하위 호환용
  [switch]$Sync,

  # 업로드 후 공개 공유 링크 생성 + 클립보드 복사
  [switch]$Share,

  # 링크 만료일 (예: -Expire 7). -Share 와 함께 사용
  [int]$Expire = 0,

  # 병렬 전송 수
  [int]$Transfers = 8,

  # 스킵 판정 없이 전부 업로드
  [switch]$Force,

  # mtime 이 정확히 일치할 때만 스킵 (기본: 원격이 더 최신이어도 스킵)
  [switch]$Strict,

  # 실제로 올리지 않고 계획만 출력
  [switch]$DryRun,

  # 제외 패턴 (여러 개 가능): -Exclude *.tmp,__pycache__,'build/*'
  [string[]]$Exclude
)

$ErrorActionPreference = "Stop"
function Die($m) { Write-Host "cloud-upload: $m" -ForegroundColor Red; exit 1 }

# -Exclude a,b arrives as two values from a PowerShell prompt but as the single
# string "a,b" through bin\cloud-upload.cmd, because `pwsh -File` takes arguments
# literally and never applies PowerShell's array syntax. The Explorer "Send to"
# entry goes the same way. Splitting here makes one spelling work from both.
# A pattern that genuinely contains a comma is not expressible — no glob needs one.
$Exclude = @($Exclude | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } |
             Where-Object { $_ -ne '' })

# ---- 설정 로드 --------------------------------------------------------
$cfgPath = Join-Path $env:USERPROFILE ".cloud-upload.json"
if (-not (Test-Path $cfgPath)) { Die "설정 없음 ($cfgPath). Setup-Nextcloud.ps1 를 먼저 실행하세요." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json

$server = $cfg.server.TrimEnd('/')
$user   = $cfg.user
# -To takes a nested path ("builds/nightly"). Backslashes are accepted because
# that is what a Windows shell completes, and normalised here: left alone they
# survive into a URL segment as %5C and the result depends on the server undoing
# it, which also leaves the printed path mixing both separators.
$root   = (($(if ($To) { $To } else { $cfg.remoteDir })) -replace '\\', '/').Trim('/')
$dav    = "$server/remote.php/dav/files/$user"
$davPath = ([uri]$dav).AbsolutePath.TrimEnd('/')    # /remote.php/dav/files/<user>

# Schannel 빌드(System32)가 HTTP/1.1 이지만 실측상 가장 빠름. HTTP/2 빌드는 오히려 느림.
$curl = "$env:WINDIR\System32\curl.exe"
if (-not (Test-Path $curl)) { $curl = (Get-Command curl.exe -ErrorAction Stop).Source }

if (-not $Path -or $Path.Count -eq 0) {
  Write-Host "사용법: cloud-upload <파일|폴더|와일드카드> [-To 경로] [-Exclude 패턴,...] [-Force] [-Strict] [-DryRun] [-Share] [-Expire 일수] [-Transfers N] [-Sync]"
  Write-Host "대상  : $server/  ->  /$root   (사용자: $user)"
  Write-Host "curl  : $curl"
  exit 0
}

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Remote-Url([string]$relative) {
  $parts = @($relative.Trim('/') -split '/' | Where-Object { $_ -ne '' })
  return "$dav/" + (($parts | ForEach-Object { Enc $_ }) -join '/')
}

# -Exclude, matched the way rclone's --exclude reads: a pattern with no "/" is
# tested against every path segment, so `__pycache__` drops the directory wherever
# it sits; a pattern with a "/" is tested against the whole path relative to the
# input root. `*` spans separators (PowerShell -like is plain string matching), so
# `build/*` covers `build/x/y` and there is no separate `**`. Matching is
# case-insensitive, which is what the filesystem underneath already is.
function Test-Excluded([string]$rel, [string[]]$patterns) {
  if (-not $patterns) { return $false }
  $segments = $null
  foreach ($pat in $patterns) {
    $p = ($pat -replace '\\', '/').Trim('/')
    if ($p -eq '') { continue }
    if ($p.Contains('/')) {
      if ($rel -like $p) { return $true }
    } else {
      if ($null -eq $segments) { $segments = $rel -split '/' }
      foreach ($s in $segments) { if ($s -like $p) { return $true } }
    }
  }
  return $false
}

# Resolve-Path -Path reads [ ] as a wildcard character class, so a real file whose
# name contains brackets ("[Full video] x.mp4") resolves to nothing. Keep wildcard
# support (*.zip) and fall back to a literal lookup only when the pattern matched
# nothing — a name that is both a valid pattern and a real file keeps the pattern.
function Resolve-Targets([string]$p) {
  $r = @(Resolve-Path -Path $p -ErrorAction SilentlyContinue)
  if ($r.Count -eq 0) { $r = @(Resolve-Path -LiteralPath $p -ErrorAction SilentlyContinue) }
  return $r
}

# Resolve once, before any transfer. A public link must name one explicit input,
# never a common parent that may contain unrelated uploads.
$inputs = @(
  foreach ($p in $Path) {
    $items = Resolve-Targets $p
    if ($items.Count -eq 0) { Die "경로를 찾을 수 없음: $p" }
    foreach ($it in $items) { Get-Item -LiteralPath $it.Path }
  }
)
if ($Share -and $inputs.Count -ne 1) {
  Die "-Share 는 파일 또는 폴더 하나만 지정하세요. 여러 경로는 각각 실행하세요."
}
$shareTarget = if ($Share) { "/$root/$($inputs[0].Name)" }

$uploaded = [Collections.Generic.List[string]]::new()
$skipped  = [Collections.Generic.List[string]]::new()
$failed   = [Collections.Generic.List[string]]::new()
$sw       = [Diagnostics.Stopwatch]::StartNew()
$totalSize = 0

# ---- 원격 인덱스 ------------------------------------------------------
# 반환: @{ Files = @{rel -> @{Size; Mtime(UTC)}}; Dirs = HashSet<rel>; Ok = bool }
$PROPFIND_BODY = '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:getcontentlength/><d:getlastmodified/><d:resourcetype/></d:prop></d:propfind>'

function Parse-Multistatus($xmlText, $files, $dirs) {
  $xml = [xml]$xmlText
  $ns = [System.Xml.XmlNamespaceManager]::new($xml.NameTable)
  $ns.AddNamespace('d', 'DAV:')
  foreach ($resp in $xml.SelectNodes('//d:response', $ns)) {
    $href = $resp.SelectSingleNode('d:href', $ns).InnerText
    # href 는 절대경로 또는 절대 URL. 퍼센트 인코딩되어 있다.
    if ($href -match '^https?://') { $href = ([uri]$href).AbsolutePath }
    $href = [uri]::UnescapeDataString($href)
    if (-not $href.StartsWith($davPath, [StringComparison]::OrdinalIgnoreCase)) { continue }
    $rel = $href.Substring($davPath.Length).Trim('/')
    if ($rel -eq '') { continue }

    $ok = $resp.SelectSingleNode("d:propstat[starts-with(d:status,'HTTP/1.1 200')]/d:prop", $ns)
    if (-not $ok) { continue }
    if ($ok.SelectSingleNode('d:resourcetype/d:collection', $ns)) {
      [void]$dirs.Add($rel)
      continue
    }
    $lenNode = $ok.SelectSingleNode('d:getcontentlength', $ns)
    $modNode = $ok.SelectSingleNode('d:getlastmodified', $ns)
    if (-not $lenNode) { continue }
    $mt = [DateTime]::MinValue
    if ($modNode -and $modNode.InnerText) {
      try {
        $mt = [DateTime]::Parse($modNode.InnerText, [Globalization.CultureInfo]::InvariantCulture,
              [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
      } catch { }
    }
    $files[$rel] = @{ Size = [int64]$lenNode.InnerText; Mtime = $mt }
  }
}

function Get-RemoteIndex([string]$rootRel) {
  $files = @{}
  $dirs  = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $body  = New-TemporaryFile
  Set-Content $body.FullName $PROPFIND_BODY -Encoding utf8 -NoNewline

  try {
    $out = & $curl -s -n -X PROPFIND -H "Depth: infinity" -H "Content-Type: application/xml" `
                   --data-binary "@$($body.FullName)" -w "`n%{http_code}" (Remote-Url $rootRel) 2>$null
    $text = ($out | Out-String)
    $code = ($text.TrimEnd() -split "`n")[-1].Trim()
    $xmlText = $text.Substring(0, [Math]::Max(0, $text.TrimEnd().Length - $code.Length))

    if ($code -eq '207') {
      Parse-Multistatus $xmlText $files $dirs
      return @{ Files = $files; Dirs = $dirs; Ok = $true }
    }
    if ($code -eq '404') {
      # 대상 폴더가 아직 없음 -> 전부 신규
      return @{ Files = $files; Dirs = $dirs; Ok = $true }
    }

    # Depth:infinity 거부(보통 403) -> 디렉터리별 Depth:1 BFS 폴백
    Write-Host "  (Depth:infinity 거부됨 [$code], 디렉터리별 조회로 폴백)" -ForegroundColor DarkYellow
    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($rootRel)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    while ($queue.Count -gt 0) {
      $cur = $queue.Dequeue()
      if (-not $seen.Add($cur)) { continue }
      $before = [Collections.Generic.HashSet[string]]::new($dirs, [StringComparer]::Ordinal)
      $o = & $curl -s -n -X PROPFIND -H "Depth: 1" -H "Content-Type: application/xml" `
                   --data-binary "@$($body.FullName)" (Remote-Url $cur) 2>$null
      $t = ($o | Out-String)
      if ($t -notmatch 'multistatus') { continue }
      Parse-Multistatus $t $files $dirs
      foreach ($d in $dirs) { if (-not $before.Contains($d) -and $d -ne $cur) { $queue.Enqueue($d) } }
    }
    return @{ Files = $files; Dirs = $dirs; Ok = $true }
  } catch {
    Write-Host "  (원격 목록 조회 실패: $_ - 전부 업로드합니다)" -ForegroundColor DarkYellow
    return @{ Files = @{}; Dirs = $dirs; Ok = $false }
  } finally {
    Remove-Item $body -Force -ErrorAction SilentlyContinue
  }
}

# ---- -Sync: rclone 에 위임 --------------------------------------------
if ($Sync) {
  $rclone = Get-Command rclone -ErrorAction SilentlyContinue
  if (-not $rclone) { Die "-Sync 에는 rclone 이 필요합니다. winget install Rclone.Rclone" }
  if ((& rclone listremotes 2>$null) -notcontains "nc:") { Die "rclone 원격 'nc' 가 없습니다. Setup-Nextcloud.ps1 재실행." }

  $copyOptions = @()
  if ($DryRun) { $copyOptions += '--dry-run' }
  # -Exclude has to be translated for rclone, not forwarded. rclone's `*` stops
  # at a '/' where Test-Excluded's spans them, and a bare name matches a *file*,
  # so `--exclude __pycache__` - the example in this script's own help - excludes
  # nothing at all. `<p>/**` adds the directory's contents, and `*` becomes `**`
  # once a pattern spans segments. Checked against rclone 1.75.1: both paths now
  # keep the same files for `dist/*`, `__pycache__` and `*.pyc`.
  foreach ($pat in $Exclude) {
    $p = ($pat -replace '\\', '/').Trim('/')
    if ($p -eq '') { continue }
    if ($p.Contains('/')) { $p = $p -replace '\*+', '**' }
    $copyOptions += @('--exclude', $p, '--exclude', "$p/**")
  }
  foreach ($fs in $inputs) {
    $dst = if ($fs.PSIsContainer) { "nc:$root/$($fs.Name)" } else { "nc:$root" }
    $src = if ($fs.PSIsContainer) { $fs.FullName } else { $fs.DirectoryName }
    Write-Host "[sync] $($fs.FullName)  ->  /$($dst.Substring(3))" -ForegroundColor Cyan
    if ($fs.PSIsContainer) {
      & rclone copy $src $dst --transfers $Transfers --checkers $Transfers --progress --stats-one-line --stats 1s @copyOptions
    } else {
      & rclone copy $src $dst --include $fs.Name --transfers $Transfers --progress --stats-one-line --stats 1s @copyOptions
    }
    if ($LASTEXITCODE -ne 0) { $failed.Add($fs.Name) } else { $uploaded.Add($fs.Name) }
  }
}
else {
  # ---- 대상 수집 (폴더는 재귀 전개, -Exclude 는 내려가기 전에 걸러낸다) --
  $jobs = [Collections.Generic.List[object]]::new()
  $excluded = 0
  foreach ($fs in $inputs) {
    if ($fs.PSIsContainer) {
      # Get-ChildItem -Recurse 로 다 훑고 나서 거르면, 걸러낼 폴더 안까지 이미
      # 다 걸어간 뒤다. 직접 훑으면서 제외된 폴더는 아예 안 내려간다.
      $stack = [Collections.Generic.Stack[object]]::new()
      $stack.Push(@{ Path = $fs.FullName; Rel = '' })
      while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        foreach ($e in Get-ChildItem -LiteralPath $cur.Path -ErrorAction SilentlyContinue) {
          $sub = if ($cur.Rel) { "$($cur.Rel)/$($e.Name)" } else { $e.Name }
          if (Test-Excluded $sub $Exclude) {
            # 폴더 하나를 세면 그 안의 파일 수를 알 수 없으니, 항목 단위로 센다.
            $excluded++
            continue
          }
          if ($e.PSIsContainer) {
            # Get-ChildItem -Recurse never followed junctions or symlinked
            # directories; walking by hand has to refuse them explicitly. A link
            # pointing at an ancestor otherwise re-uploads the whole tree under
            # sub/loop/sub/loop/... until MAX_PATH quietly stops the walk.
            if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $stack.Push(@{ Path = $e.FullName; Rel = $sub })
          }
          else { $jobs.Add(@{ Local = $e.FullName; Rel = "$root/$($fs.Name)/$sub"; Info = $e }) }
        }
      }
    } elseif (Test-Excluded $fs.Name $Exclude) {
      $excluded++
    } else {
      $jobs.Add(@{ Local = $fs.FullName; Rel = "$root/$($fs.Name)"; Info = $fs })
    }
  }
  if ($excluded -gt 0) {
    # $()로 감싸야 한다: 한글은 PowerShell 식별자로 유효해서 "$excluded개" 는
    # $excluded 가 아니라 "$excluded개" 라는 이름의 (없는) 변수로 읽힌다.
    Write-Host "[제외] 패턴에 걸린 항목 $($excluded)개" -ForegroundColor DarkGray
  }
  if ($jobs.Count -eq 0) { Die "업로드할 파일이 없습니다." }

  # ---- 원격과 비교해서 스킵 -------------------------------------------
  $index = @{ Files = @{}; Dirs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal) }
  if (-not $Force) {
    $isw = [Diagnostics.Stopwatch]::StartNew()
    $index = Get-RemoteIndex $root
    $isw.Stop()
    Write-Host ("[인덱스] 원격 {0}개 파일 / {1}개 폴더 ({2:N2}s)" -f $index.Files.Count, $index.Dirs.Count, $isw.Elapsed.TotalSeconds) -ForegroundColor DarkGray

    $todo = [Collections.Generic.List[object]]::new()
    foreach ($j in $jobs) {
      $r = $index.Files[$j.Rel]
      if ($r -and $r.Size -eq $j.Info.Length) {
        $lm = $j.Info.LastWriteTimeUtc
        $delta = ($r.Mtime - $lm).TotalSeconds
        # 정확히 일치(±2s, exFAT/네트워크 드라이브 오차) 또는 (비엄격) 원격이 더 최신
        if ([Math]::Abs($delta) -le 2 -or (-not $Strict -and $delta -gt 0)) {
          $skipped.Add($j.Rel); continue
        }
      }
      $todo.Add($j)
    }
    $jobs = $todo
  }

  if ($skipped.Count -gt 0) {
    Write-Host "[스킵] 이미 동일한 파일 $($skipped.Count)개" -ForegroundColor DarkGray
  }
  if ($jobs.Count -eq 0) {
    $sw.Stop()
    Write-Host ("최신 상태입니다. 전송할 것 없음 ({0:N2}s)" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
    if (-not $Share -or $DryRun) { exit 0 }
  }

  foreach ($j in $jobs) { $totalSize += $j.Info.Length }

  if ($DryRun) {
    Write-Host "[DryRun] 업로드 예정 $($jobs.Count)개, $("{0:N1}" -f ($totalSize/1MB)) MB" -ForegroundColor Yellow
    $jobs | ForEach-Object { Write-Host "  + $($_.Rel)" -ForegroundColor Yellow }
    exit 0
  }

  # ---- 없는 폴더만 MKCOL (한 번의 curl 로 일괄) -----------------------
  $needDirs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($j in $jobs) {
    $acc = @()
    foreach ($seg in (((Split-Path $j.Rel -Parent) -replace '\\', '/').Trim('/') -split '/')) {
      if ($seg -eq '') { continue }
      $acc += $seg
      $sub = $acc -join '/'
      if (-not $index.Dirs.Contains($sub)) { [void]$needDirs.Add($sub) }
    }
  }
  if ($needDirs.Count -gt 0) {
    # 부모 먼저 생성해야 하므로 깊이 순으로 정렬, 병렬 금지.
    # @() 필수: Sort-Object 는 원소가 하나면 배열이 아니라 스칼라를 돌려주고,
    # 그러면 $ordered[0] 이 문자열의 첫 "글자"가 된다 ("Uploads/output" -> "U").
    $ordered = @($needDirs | Sort-Object { ($_ -split '/').Count }, { $_ })
    $mk = New-TemporaryFile
    $mb = [Text.StringBuilder]::new()
    for ($i = 0; $i -lt $ordered.Count; $i++) {
      [void]$mb.AppendLine("netrc")
      [void]$mb.AppendLine("silent")
      [void]$mb.AppendLine("globoff")
      [void]$mb.AppendLine("output = `"NUL`"")
      [void]$mb.AppendLine("write-out = `"%{http_code}\n`"")
      [void]$mb.AppendLine("request = `"MKCOL`"")
      [void]$mb.AppendLine("url = `"$(Remote-Url $ordered[$i])`"")
      if ($i -lt $ordered.Count - 1) { [void]$mb.AppendLine("next") }
    }
    Set-Content $mk.FullName $mb.ToString() -Encoding utf8

    # 201=생성, 405=이미 있음. 그 밖은 실패이고, 그대로 두면 뒤이은 PUT 이
    # 영문 모를 404 로 죽는다 (부모 컬렉션이 없으면 WebDAV 는 404 를 준다).
    $codes = @(& $curl -K $mk.FullName 2>$null)
    Remove-Item $mk -Force -ErrorAction SilentlyContinue
    $bad = @()
    for ($i = 0; $i -lt $ordered.Count; $i++) {
      $c = if ($i -lt $codes.Count) { "$($codes[$i])".Trim() } else { "응답 없음" }
      if ($c -notmatch '^(201|405)$') { $bad += "$($ordered[$i])  (HTTP $c)" }
    }
    if ($bad.Count -gt 0) {
      Write-Host "폴더 생성 실패 $($bad.Count)건:" -ForegroundColor Red
      $bad | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
      Die "상위 폴더를 만들지 못해 중단합니다."
    }
    Write-Host "[폴더] $($needDirs.Count)개 생성" -ForegroundColor DarkGray
  }

  function Unix-Mtime($fi) { [int64]([DateTimeOffset]$fi.LastWriteTimeUtc).ToUnixTimeSeconds() }

  if ($jobs.Count -le 4) {
    # 적은 수 -> 진행률 바를 보여준다
    $idx = 0
    foreach ($j in $jobs) {
      $idx++
      $size = "{0:N1} MB" -f ($j.Info.Length / 1MB)
      Write-Host ("[{0}/{1}] {2}  ({3})" -f $idx, $jobs.Count, $j.Rel, $size) -ForegroundColor Cyan
      & $curl -n -g --fail --progress-bar -H "X-OC-Mtime: $(Unix-Mtime $j.Info)" -T $j.Local (Remote-Url $j.Rel)
      if ($LASTEXITCODE -ne 0) { $failed.Add($j.Rel) } else { $uploaded.Add($j.Rel) }
    }
  }
  else {
    # 많은 수 -> 연결 재사용 + 병렬 전송
    Write-Host "[전송] $($jobs.Count)개 파일, $("{0:N1}" -f ($totalSize/1MB)) MB (병렬 $Transfers)" -ForegroundColor Cyan
    $conf = New-TemporaryFile
    $byUrl = @{}
    $sb = [Text.StringBuilder]::new()
    for ($i = 0; $i -lt $jobs.Count; $i++) {
      $local = $jobs[$i].Local -replace '\\', '/'   # curl 설정 파일에서 역슬래시는 이스케이프
      $url   = Remote-Url $jobs[$i].Rel
      $byUrl[$url] = $jobs[$i].Rel
      [void]$sb.AppendLine("netrc")
      [void]$sb.AppendLine("silent")
      [void]$sb.AppendLine("show-error")
      [void]$sb.AppendLine("globoff")
      [void]$sb.AppendLine("write-out = `"%{http_code} %{url_effective}\n`"")
      [void]$sb.AppendLine("header = `"X-OC-Mtime: $(Unix-Mtime $jobs[$i].Info)`"")
      [void]$sb.AppendLine("upload-file = `"$local`"")
      [void]$sb.AppendLine("url = `"$url`"")
      if ($i -lt $jobs.Count - 1) { [void]$sb.AppendLine("next") }
    }
    Set-Content $conf.FullName $sb.ToString() -Encoding utf8

    # -Z 는 완료 순서대로 출력하므로 URL 로 되짚는다 (인덱스 매칭 불가)
    $done = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $n = 0
    & $curl -Z --parallel-max $Transfers -K $conf.FullName | ForEach-Object {
      # write-out 이 낸 "<코드> <URL>" 줄만 받는다. -Z 는 stdout/stderr 를
      # 뒤섞어 내보내므로, 느슨하게 자르면 curl 에러 문구가 가짜 결과로 잡힌다.
      if ($_ -notmatch '^\s*(\d{3})\s+(\S+)\s*$') { return }
      $code = $matches[1]
      $rel  = $byUrl[$matches[2]]
      if (-not $rel) { $rel = $matches[2] }
      [void]$done.Add($rel)
      $n++
      if ($code -match '^2\d\d$') {
        $uploaded.Add($rel)
        Write-Host ("  [{0}/{1}] {2}" -f $n, $jobs.Count, $rel) -ForegroundColor DarkGray
      } else {
        $failed.Add("$rel  (HTTP $code)")
        Write-Host ("  [{0}/{1}] {2}  HTTP {3}" -f $n, $jobs.Count, $rel, $code) -ForegroundColor Red
      }
    }
    Remove-Item $conf -Force -ErrorAction SilentlyContinue
    foreach ($j in $jobs) { if (-not $done.Contains($j.Rel)) { $failed.Add("$($j.Rel)  (응답 없음)") } }
  }
}

$sw.Stop()

# ---- 결과 -------------------------------------------------------------
Write-Host ""
if ($failed.Count -gt 0) {
  Write-Host "실패 $($failed.Count)건:" -ForegroundColor Red
  $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}
$secs = [Math]::Max($sw.Elapsed.TotalSeconds, 0.001)
$rate = if ($totalSize -gt 0) { " / {0:N1} MB, {1:N1} MB/s" -f ($totalSize / 1MB), ($totalSize / 1MB / $secs) } else { "" }
$skipMsg = if ($skipped.Count -gt 0) { ", 스킵 $($skipped.Count)건" } else { "" }
Write-Host ("완료: {0}건{1}  ({2:N1}s{3})" -f $uploaded.Count, $skipMsg, $secs, $rate) -ForegroundColor Green

# ---- 공개 링크 --------------------------------------------------------
if ($Share -and -not $DryRun -and $failed.Count -eq 0 -and ($uploaded.Count + $skipped.Count) -gt 0) {
  $curlArgs = @(
    "-s", "-n", "-H", "OCS-APIRequest: true",
    "-X", "POST", "$server/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json",
    "--data-urlencode", "path=$shareTarget",
    "--data-urlencode", "shareType=3",
    "--data-urlencode", "permissions=1"
  )
  if ($Expire -gt 0) {
    $curlArgs += @("--data-urlencode", "expireDate=$((Get-Date).AddDays($Expire).ToString('yyyy-MM-dd'))")
  }
  try {
    $resp = (& $curl @curlArgs) | ConvertFrom-Json
    $url = $resp.ocs.data.url
    if ($url) {
      Set-Clipboard -Value $url
      Write-Host "공유 링크 (클립보드 복사됨): $url" -ForegroundColor Yellow
    } else {
      Write-Host "공유 링크 생성 실패: $($resp.ocs.meta.message)" -ForegroundColor Red
    }
  } catch {
    Write-Host "공유 링크 생성 실패: $_" -ForegroundColor Red
  }
}

if ($failed.Count -gt 0) { exit 1 }

