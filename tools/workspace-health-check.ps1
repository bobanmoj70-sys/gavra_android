$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$failed = $false

function Check-PathStatus {
    param(
        [string]$Path,
        [string]$Label = $Path
    )

    if (Test-Path $Path) {
        Write-Host "OK   $Label"
    }
    else {
        Write-Host "MISS $Label"
        $script:failed = $true
    }
}

Write-Host "=== Workspace Health Check ==="
Write-Host "Root: $root"
Write-Host ""

Write-Host "[1/3] Critical files"
$criticalFiles = @(
    '.vscode/settings.json',
    '.vscode/tasks.json',
    '.vscode/launch.json',
    '.vscode/mcp.json',
    '.vscode/mcp.example.json',
    'pubspec.yaml',
    'analysis_options.yaml',
    '.env',
    'lib/main.dart'
)

foreach ($file in $criticalFiles) {
    Check-PathStatus -Path $file
}

Write-Host ""
Write-Host "[2/3] MCP projects"
$mcpProjects = @(
    'appstore-mcp',
    'github-mcp',
    'google-play-mcp',
    'huawei-appgallery-mcp',
    'supabase-mcp'
)

foreach ($project in $mcpProjects) {
    Check-PathStatus -Path "$project/package.json" -Label "$project/package.json"
    Check-PathStatus -Path "$project/dist/index.js" -Label "$project/dist/index.js"
    Check-PathStatus -Path "$project/node_modules" -Label "$project/node_modules"
}

Write-Host ""
Write-Host "[3/3] MCP config parse"
try {
    $null = Get-Content '.vscode/mcp.json' -Raw | ConvertFrom-Json
    Write-Host 'OK   .vscode/mcp.json JSON valid'
}
catch {
    Write-Host 'MISS .vscode/mcp.json JSON invalid'
    $failed = $true
}

Write-Host ""
if ($failed) {
    Write-Host '❌ HEALTH CHECK: FAIL'
    exit 1
}

Write-Host '✅ HEALTH CHECK: PASS'
exit 0
