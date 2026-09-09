# Run with pwsh -NoProfile -File scripts/tests/cloud-upload-smoke.ps1.
# Exercise the full script with fake transports, config and input files.
$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $PSScriptRoot '../../bin/windows/cloud-upload.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('cloud-upload-test-' + [guid]::NewGuid())
$previousProfile = $env:USERPROFILE
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
  $env:USERPROFILE = $tempRoot
  @{ server='https://example.invalid'; user='test'; remoteDir='Uploads' } |
    ConvertTo-Json | Set-Content (Join-Path $tempRoot '.cloud-upload.json')
  $folder = New-Item -ItemType Directory -Path (Join-Path $tempRoot 'dist')
  'a' | Set-Content (Join-Path $folder 'a.txt')
  'b' | Set-Content (Join-Path $folder 'b.txt')
  $file = Join-Path $folder 'a.txt'

  # Replace only transport discovery; keep all control flow and request building.
  $source = Get-Content $sourcePath -Raw
  $discovery = '(?m)^\$curl = .*\r?\nif \(-not \(Test-Path \$curl\)\) \{[^\r\n]+\}'
  if ([regex]::Matches($source, $discovery).Count -ne 1) { throw 'Transport discovery changed; update harness.' }
  $testScript = Join-Path $tempRoot 'upload.ps1'
  [regex]::Replace($source, $discovery, { '$curl = ''Invoke-MockCurl''' }) | Set-Content $testScript

  $state = @{}
  function Assert($condition, $message) { if (-not $condition) { throw $message } }
  function Invoke-MockCurl {
    $state.requests.Add(@($args))
    $global:LASTEXITCODE = 0
    if ($args -contains 'PROPFIND') {
      $responses = foreach ($f in Get-ChildItem $folder -File) {
        $mtime = $f.LastWriteTimeUtc.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
        '<d:response><d:href>/remote.php/dav/files/test/Uploads/dist/' + $f.Name + '</d:href><d:propstat><d:status>HTTP/1.1 200 OK</d:status><d:prop><d:getcontentlength>' + $f.Length + '</d:getcontentlength><d:getlastmodified>' + $mtime + '</d:getlastmodified><d:resourcetype/></d:prop></d:propstat></d:response>'
      }
      '<d:multistatus xmlns:d="DAV:">' + ($responses -join '') + '</d:multistatus>'
      '207'
    } elseif ($args -contains 'POST') {
      '{"ocs":{"data":{"url":"https://example.invalid/s/mock"}}}'
    } elseif ($args -contains '-K') {
      $config = Get-Content $args[([array]::IndexOf($args, '-K') + 1)]
      foreach ($line in $config) { if ($line -match '^url = ') { '201' } }
    } elseif ($args -contains '-T') {
      if ($state.failUpload) { $global:LASTEXITCODE = 22 }
    } else { throw "Unexpected curl call: $args" }
  }
  function rclone {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'listremotes') { 'nc:' }
    else { $state.copies.Add(@($args)) }
  }
  function Set-Clipboard { param($Value) $state.clipboard = $Value }
  function Run-Case($name, $arguments, $expectedShare, $expectedCopies = 0, $dry = $false, $failure = $false) {
    $state.requests = [Collections.Generic.List[object]]::new()
    $state.copies = [Collections.Generic.List[object]]::new()
    $state.clipboard = $null
    $state.failUpload = $failure
    $global:LASTEXITCODE = 0
    & $testScript @arguments | Out-Null
    $posts = @($state.requests | Where-Object { $_ -contains 'POST' })
    Assert ($posts.Count -eq [int][bool]$expectedShare) "$name : unexpected share count"
    if ($expectedShare) {
      Assert ($posts[0] -contains "path=$expectedShare") "$name : wrong public share scope"
      Assert ($state.clipboard -eq 'https://example.invalid/s/mock') "$name : missing clipboard link"
    } else { Assert ($null -eq $state.clipboard) "$name : unexpected clipboard write" }
    Assert ($state.copies.Count -eq $expectedCopies) "$name : wrong rclone call count"
    if ($dry) {
      foreach ($copy in $state.copies) { Assert ($copy -contains '--dry-run') "$name : live rclone transfer" }
      Assert (@($state.requests | Where-Object { $_ -contains '-T' -or $_ -contains '-K' }).Count -eq 0) "$name : live curl transfer"
    }
    Write-Host "PASS: $name"
  }
  Run-Case 'folder share' @{ Path=$folder.FullName; Share=$true; Force=$true } '/Uploads/dist'
  Run-Case 'single file share' @{ Path=$file; Share=$true; Force=$true } '/Uploads/a.txt'
  Run-Case 'already uploaded folder share' @{ Path=$folder.FullName; Share=$true } '/Uploads/dist'
  Run-Case 'already uploaded file share' @{ Path=$file; To='Uploads/dist'; Share=$true } '/Uploads/dist/a.txt'
  Run-Case 'curl dry run with share' @{ Path=$folder.FullName; Share=$true; DryRun=$true; Force=$true } $null 0 $true
  Run-Case 'already uploaded dry run' @{ Path=$folder.FullName; Share=$true; DryRun=$true } $null 0 $true
  Run-Case 'sync folder share' @{ Path=$folder.FullName; Share=$true; Sync=$true } '/Uploads/dist' 1
  Run-Case 'sync file share' @{ Path=$file; Share=$true; Sync=$true } '/Uploads/a.txt' 1
  Run-Case 'sync dry run with share' @{ Path=$file; Share=$true; Sync=$true; DryRun=$true } $null 1 $true
  Run-Case 'sync folder dry run with share' @{ Path=$folder.FullName; Share=$true; Sync=$true; DryRun=$true } $null 1 $true
  Run-Case 'multiple share inputs rejected' @{ Path=(Join-Path $folder '*.txt'); Share=$true; Force=$true } $null
  Assert ($LASTEXITCODE -eq 1 -and $state.requests.Count -eq 0) 'Multiple inputs must fail before network activity'
  Run-Case 'failed upload does not share' @{ Path=$file; Share=$true; Force=$true } $null 0 $false $true
  Assert ($LASTEXITCODE -eq 1) 'Failed upload must return failure'
} finally {
  $env:USERPROFILE = $previousProfile
  $resolved = [IO.Path]::GetFullPath($tempRoot)
  $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
  if (-not $resolved.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path' }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
