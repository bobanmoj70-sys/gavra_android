$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$libRoot = Join-Path $projectRoot "lib"
$outFile = Join-Path $PSScriptRoot "_dead_code_report.txt"

$allFiles = Get-ChildItem -Path $libRoot -Recurse -Filter "*.dart"
$fileMap = @{}
foreach ($f in $allFiles) {
  $rel = $f.FullName.Substring($libRoot.Length + 1).Replace('\','/')
  $fileMap[$rel] = $f.FullName
}

$importsByFile = @{}
$importedTargets = New-Object 'System.Collections.Generic.HashSet[string]'
$partTargets = New-Object 'System.Collections.Generic.HashSet[string]'
$importersOf = @{}

function Resolve-RelPath($fromRel, $importPath) {
  $dir = Split-Path $fromRel -Parent
  if (-not $dir -or $dir -eq '.') { $dir = "" }
  $baseParts = @()
  if ($dir) { $baseParts = @($dir -split '/' | Where-Object { $_ -ne '' }) }
  $impParts = $importPath -split '/'
  $stack = New-Object System.Collections.ArrayList
  foreach ($b in $baseParts) { [void]$stack.Add($b) }
  foreach ($p in $impParts) {
    if ($p -eq '.' -or $p -eq '') { continue }
    elseif ($p -eq '..') {
      if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) }
    } else {
      [void]$stack.Add($p)
    }
  }
  return ($stack -join '/')
}

foreach ($f in $allFiles) {
  $rel = $f.FullName.Substring($libRoot.Length + 1).Replace('\','/')
  $content = [System.IO.File]::ReadAllText($f.FullName)
  $imports = New-Object System.Collections.ArrayList

  foreach ($m in [regex]::Matches($content, "import\s+['\`"]package:gavra_android/([^'\`"]+)['\`"]")) {
    $target = $m.Groups[1].Value
    [void]$imports.Add($target)
    [void]$importedTargets.Add($target)
    if (-not $importersOf.ContainsKey($target)) { $importersOf[$target] = New-Object System.Collections.ArrayList }
    [void]$importersOf[$target].Add($rel)
  }

  foreach ($m in [regex]::Matches($content, "import\s+['\`"](\.\.?/[^'\`"]+)['\`"]")) {
    $resolved = Resolve-RelPath $rel $m.Groups[1].Value
    [void]$imports.Add($resolved)
    [void]$importedTargets.Add($resolved)
    if (-not $importersOf.ContainsKey($resolved)) { $importersOf[$resolved] = New-Object System.Collections.ArrayList }
    [void]$importersOf[$resolved].Add($rel)
  }

  foreach ($m in [regex]::Matches($content, "(?m)^\s*part\s+['\`"]([^'\`"]+)['\`"]\s*;")) {
    $resolved = Resolve-RelPath $rel $m.Groups[1].Value
    [void]$imports.Add($resolved)
    [void]$importedTargets.Add($resolved)
    [void]$partTargets.Add($resolved)
    if (-not $importersOf.ContainsKey($resolved)) { $importersOf[$resolved] = New-Object System.Collections.ArrayList }
    [void]$importersOf[$resolved].Add($rel)
  }

  # export directives
  foreach ($m in [regex]::Matches($content, "export\s+['\`"](\.\.?/[^'\`"]+)['\`"]")) {
    $resolved = Resolve-RelPath $rel $m.Groups[1].Value
    [void]$imports.Add($resolved)
    [void]$importedTargets.Add($resolved)
    if (-not $importersOf.ContainsKey($resolved)) { $importersOf[$resolved] = New-Object System.Collections.ArrayList }
    [void]$importersOf[$resolved].Add("export:$rel")
  }
  foreach ($m in [regex]::Matches($content, "export\s+['\`"]package:gavra_android/([^'\`"]+)['\`"]")) {
    $target = $m.Groups[1].Value
    [void]$imports.Add($target)
    [void]$importedTargets.Add($target)
    if (-not $importersOf.ContainsKey($target)) { $importersOf[$target] = New-Object System.Collections.ArrayList }
    [void]$importersOf[$target].Add("export:$rel")
  }

  $importsByFile[$rel] = @($imports)
}

# BFS from main.dart
$reachable = New-Object 'System.Collections.Generic.HashSet[string]'
$queue = New-Object System.Collections.Queue
[void]$reachable.Add('main.dart')
$queue.Enqueue('main.dart')

while ($queue.Count -gt 0) {
  $current = $queue.Dequeue()
  if ($importsByFile.ContainsKey($current)) {
    foreach ($imp in $importsByFile[$current]) {
      if ($fileMap.ContainsKey($imp) -and -not $reachable.Contains($imp)) {
        [void]$reachable.Add($imp)
        $queue.Enqueue($imp)
      }
    }
  }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("TOTAL_DART=$($fileMap.Count)")
[void]$sb.AppendLine("REACHABLE=$($reachable.Count)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== NEVER_IMPORTED ===")
$neverImported = @()
foreach ($rel in ($fileMap.Keys | Sort-Object)) {
  if ($rel -eq 'main.dart') { continue }
  if (-not $importedTargets.Contains($rel)) {
    $neverImported += $rel
    [void]$sb.AppendLine($rel)
  }
}

[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== UNREACHABLE_FROM_MAIN ===")
$unreachable = @()
foreach ($rel in ($fileMap.Keys | Sort-Object)) {
  if ($rel -eq 'main.dart') { continue }
  if (-not $reachable.Contains($rel)) {
    $unreachable += $rel
    $imps = if ($importersOf.ContainsKey($rel)) { ($importersOf[$rel] -join ', ') } else { '(none)' }
    [void]$sb.AppendLine("$rel  << importers: $imps")
  }
}

[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== ALL_FILES_WITH_IMPORTER_COUNT ===")
foreach ($rel in ($fileMap.Keys | Sort-Object)) {
  $cnt = if ($importersOf.ContainsKey($rel)) { $importersOf[$rel].Count } else { 0 }
  $r = if ($reachable.Contains($rel)) { 'R' } else { 'U' }
  [void]$sb.AppendLine("[$r] importers=$cnt  $rel")
}

# Check dynamic/string references for unreachable files (class names)
[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== CLASS_NAME_REFS_FOR_UNREACHABLE ===")
foreach ($rel in $unreachable) {
  $full = $fileMap[$rel]
  $content = [System.IO.File]::ReadAllText($full)
  $classes = [regex]::Matches($content, '(?m)^\s*(?:class|enum|typedef|mixin|extension)\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
  $basename = [System.IO.Path]::GetFileNameWithoutExtension($rel)
  $searchTerms = @($basename) + @($classes) | Select-Object -Unique
  $foundAnywhere = @()
  foreach ($term in $searchTerms) {
    if ($term.Length -lt 4) { continue }
    $hits = Select-String -Path (Join-Path $libRoot '**\*.dart') -Pattern "\b$([regex]::Escape($term))\b" -SimpleMatch:$false -ErrorAction SilentlyContinue |
      Where-Object { $_.Path -ne $full } |
      Select-Object -First 5
    # Select-String with ** may not work on PS 5.1 - use Get-ChildItem
  }
  # Manual scan
  foreach ($term in $searchTerms) {
    if ([string]::IsNullOrWhiteSpace($term) -or $term.Length -lt 5) { continue }
    $count = 0
    $sampleFiles = @()
    foreach ($of in $allFiles) {
      if ($of.FullName -eq $full) { continue }
      $oc = [System.IO.File]::ReadAllText($of.FullName)
      if ($oc -match "\b$([regex]::Escape($term))\b") {
        $count++
        if ($sampleFiles.Count -lt 3) {
          $oref = $of.FullName.Substring($libRoot.Length + 1).Replace('\','/')
          $sampleFiles += $oref
        }
      }
    }
    if ($count -gt 0) {
      $foundAnywhere += "$term=>$count hits in: $($sampleFiles -join ', ')"
    }
  }
  if ($foundAnywhere.Count -eq 0) {
    [void]$sb.AppendLine("$rel :: NO external class/name refs (classes: $($classes -join ', '))")
  } else {
    [void]$sb.AppendLine("$rel :: $($foundAnywhere -join ' | ')")
  }
}

# Also check test folder imports
[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== TEST_FILES ===")
$testRoot = Join-Path $projectRoot 'test'
if (Test-Path $testRoot) {
  $testFiles = Get-ChildItem -Path $testRoot -Recurse -Filter '*.dart' -ErrorAction SilentlyContinue
  foreach ($tf in $testFiles) {
    [void]$sb.AppendLine($tf.FullName)
    $tc = [System.IO.File]::ReadAllText($tf.FullName)
    foreach ($m in [regex]::Matches($tc, "import\s+['\`"]([^'\`"]+)['\`"]")) {
      [void]$sb.AppendLine("  import: $($m.Groups[1].Value)")
    }
  }
  if (-not $testFiles -or $testFiles.Count -eq 0) {
    [void]$sb.AppendLine('(no test dart files)')
  }
}

# Non-dart candidates
[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== ROOT_FILES ===")
Get-ChildItem -Path $projectRoot -File | ForEach-Object { [void]$sb.AppendLine($_.FullName) }

[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== TEMP_SECRETS ===")
if (Test-Path (Join-Path $projectRoot 'temp_secrets')) {
  Get-ChildItem -Path (Join-Path $projectRoot 'temp_secrets') -File | ForEach-Object { [void]$sb.AppendLine($_.FullName) }
}

[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== DOCS ===")
if (Test-Path (Join-Path $projectRoot 'docs')) {
  Get-ChildItem -Path (Join-Path $projectRoot 'docs') -Recurse -File | ForEach-Object { [void]$sb.AppendLine($_.FullName) }
}

[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== TOOLS ===")
if (Test-Path (Join-Path $projectRoot 'tools')) {
  Get-ChildItem -Path (Join-Path $projectRoot 'tools') -Recurse -File | Where-Object { $_.Name -ne '_dead_code_scan.ps1' -and $_.Name -ne '_dead_code_report.txt' } | ForEach-Object { [void]$sb.AppendLine($_.FullName) }
}

[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== BAK_OLD_COPY ===")
Get-ChildItem -Path $projectRoot -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object {
    $_.FullName -notmatch '\\(build|\.git|node_modules|\.dart_tool)\\' -and
    ($_.Name -match '\.(bak|old|tmp|orig|swp)$' -or $_.Name -match 'copy|backup|_old|_bak|unused|_fixed')
  } |
  ForEach-Object { [void]$sb.AppendLine($_.FullName) }

[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== DISTRIBUTION ===")
if (Test-Path (Join-Path $projectRoot 'distribution')) {
  Get-ChildItem -Path (Join-Path $projectRoot 'distribution') -Recurse -File | ForEach-Object { [void]$sb.AppendLine($_.FullName) }
}

[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== OSRM ===")
if (Test-Path (Join-Path $projectRoot 'osrm-service')) {
  Get-ChildItem -Path (Join-Path $projectRoot 'osrm-service') -Recurse -File | Where-Object { $_.FullName -notmatch '__pycache__' } | ForEach-Object { [void]$sb.AppendLine($_.FullName) }
}

[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== HTML_AT_ROOT_AND_DOCS ===")
Get-ChildItem -Path $projectRoot -Recurse -Filter '*.html' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '\\(build|\.git|node_modules|\.dart_tool)\\' } |
  ForEach-Object { [void]$sb.AppendLine($_.FullName) }

[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== CERT_KEY_AT_ROOT ===")
Get-ChildItem -Path $projectRoot -File | Where-Object { $_.Extension -match '\.(crt|key|pem|p12|jks)$' } | ForEach-Object { [void]$sb.AppendLine($_.FullName) }

[System.IO.File]::WriteAllText($outFile, $sb.ToString())
Write-Output "Wrote $outFile"
Write-Output "Never imported: $($neverImported.Count)"
Write-Output "Unreachable: $($unreachable.Count)"
