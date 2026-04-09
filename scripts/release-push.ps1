param(
  [switch]$DryRun,
  [string]$CommitMessage = "chore: bump version",
  [string]$Remote = "origin"
)

$ErrorActionPreference = "Stop"

function Run-External {
  param(
    [string]$File,
    [string[]]$Args
  )

  Write-Host ("→ " + $File + " " + ($Args -join " "))
  if ($DryRun) {
    return
  }

  & $File @Args
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed: $File $($Args -join ' ')"
  }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$bumpScript = Join-Path $repoRoot "scripts\bump-pubspec.ps1"

if (-not (Test-Path $bumpScript)) {
  throw "Missing bump script: $bumpScript"
}

Push-Location $repoRoot
try {
  $currentBranch = (& git branch --show-current).Trim()
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($currentBranch)) {
    throw "Unable to detect current git branch."
  }

  if ($DryRun) {
    Run-External -File "powershell" -Args @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $bumpScript)
    Run-External -File "git" -Args @("add", "pubspec.yaml")
    Run-External -File "git" -Args @("commit", "-m", $CommitMessage)
    Run-External -File "git" -Args @("push", $Remote, $currentBranch)
    Write-Host "✅ Dry run complete."
    return
  }

  Run-External -File "powershell" -Args @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $bumpScript)
  Run-External -File "git" -Args @("add", "pubspec.yaml")

  $stagedPubspec = (& git diff --cached --name-only -- pubspec.yaml) -join ""
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to verify staged pubspec change."
  }

  if ([string]::IsNullOrWhiteSpace($stagedPubspec)) {
    throw "No staged change detected for pubspec.yaml after bump."
  }

  Run-External -File "git" -Args @("commit", "-m", $CommitMessage)
  Run-External -File "git" -Args @("push", $Remote, $currentBranch)

  Write-Host "✅ Release push completed."
}
finally {
  Pop-Location
}