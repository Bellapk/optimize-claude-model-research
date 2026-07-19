[CmdletBinding()]
param(
    [string]$ClaudeHome = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude'),
    [string]$CollectorModel = 'claude-opus-4-8',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if ($CollectorModel -notmatch '^[A-Za-z0-9._:/\-\[\]]+$') {
    throw "Unsafe collector model value: $CollectorModel"
}

$repoRoot = $PSScriptRoot
$agentSource = Join-Path $repoRoot '.claude\agents\data-collector.md'
$skillSource = Join-Path $repoRoot '.claude\skills\collect-data\SKILL.md'
$policySource = Join-Path $repoRoot 'templates\research-model-routing.md'
$agentTarget = Join-Path $ClaudeHome 'agents\data-collector.md'
$skillTarget = Join-Path $ClaudeHome 'skills\collect-data\SKILL.md'
$memoryTarget = Join-Path $ClaudeHome 'CLAUDE.md'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $ClaudeHome "backups\optimize-claude-model-research\$timestamp"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

foreach ($source in @($agentSource, $skillSource, $policySource)) {
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing package file: $source"
    }
}

function Backup-Target([string]$Target) {
    if (-not (Test-Path -LiteralPath $Target)) {
        return
    }
    $relative = $Target.Substring($ClaudeHome.TrimEnd('\').Length).TrimStart('\')
    $backup = Join-Path $backupRoot $relative
    if ($DryRun) {
        Write-Host "[dry-run] back up $Target -> $backup"
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
    Copy-Item -LiteralPath $Target -Destination $backup -Force
}

function Write-Config([string]$Target, [string]$Content) {
    if ($DryRun) {
        Write-Host "[dry-run] write $Target"
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
    [System.IO.File]::WriteAllText($Target, $Content.TrimEnd() + "`n", $utf8NoBom)
}

$agentContent = (Get-Content -Raw -Encoding UTF8 -LiteralPath $agentSource) -replace '(?m)^model:\s*.+$', "model: $CollectorModel"
$skillContent = (Get-Content -Raw -Encoding UTF8 -LiteralPath $skillSource) -replace '(?m)^model:\s*.+$', "model: $CollectorModel"
$policyContent = (Get-Content -Raw -Encoding UTF8 -LiteralPath $policySource).Replace('{{COLLECTOR_MODEL}}', $CollectorModel).Trim()

$beginMarker = '<!-- BEGIN optimize-claude-model-research -->'
$endMarker = '<!-- END optimize-claude-model-research -->'
$policyBlock = "$beginMarker`n$policyContent`n$endMarker"
$memoryContent = if (Test-Path -LiteralPath $memoryTarget) {
    Get-Content -Raw -Encoding UTF8 -LiteralPath $memoryTarget
} else {
    ''
}
$escapedBegin = [regex]::Escape($beginMarker)
$escapedEnd = [regex]::Escape($endMarker)
$blockPattern = "(?s)$escapedBegin.*?$escapedEnd"
if ($memoryContent -match $blockPattern) {
    $mergedMemory = [regex]::Replace($memoryContent, $blockPattern, $policyBlock)
} elseif ([string]::IsNullOrWhiteSpace($memoryContent)) {
    $mergedMemory = $policyBlock
} else {
    $mergedMemory = $memoryContent.TrimEnd() + "`n`n" + $policyBlock
}

foreach ($target in @($agentTarget, $skillTarget, $memoryTarget)) {
    Backup-Target $target
}
Write-Config $agentTarget $agentContent
Write-Config $skillTarget $skillContent
Write-Config $memoryTarget $mergedMemory

$override = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_SUBAGENT_MODEL', 'Process')
if ([string]::IsNullOrWhiteSpace($override)) {
    $override = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_SUBAGENT_MODEL', 'User')
}
if (-not [string]::IsNullOrWhiteSpace($override) -and $override -ne 'inherit') {
    Write-Warning "CLAUDE_CODE_SUBAGENT_MODEL=$override overrides the configured collector model. Unset it or set it to inherit."
}

Write-Host "Installed Claude Research Router in $ClaudeHome"
Write-Host "Collector model: $CollectorModel"
Write-Host 'Restart Claude Code, then run /doctor, /skills, and /agents.'
