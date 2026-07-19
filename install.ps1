[CmdletBinding()]
param(
    [string]$ClaudeHome = (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".claude"),
    [string]$CollectorModel = "claude-opus-4-8",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if ($CollectorModel -notmatch "^[A-Za-z0-9._:/\[\]-]+$") {
    throw "CollectorModel contains unsupported characters: $CollectorModel"
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentSource = Join-Path $repoRoot ".claude\agents\data-collector.md"
$skillSource = Join-Path $repoRoot ".claude\skills\collect-data\SKILL.md"
$policySource = Join-Path $repoRoot "templates\research-model-routing.md"
$agentTarget = Join-Path $ClaudeHome "agents\data-collector.md"
$skillTarget = Join-Path $ClaudeHome "skills\collect-data\SKILL.md"
$policyTarget = Join-Path $ClaudeHome "CLAUDE.md"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $ClaudeHome "backups\optimize-claude-model-research\$timestamp"
$utf8 = New-Object System.Text.UTF8Encoding($false)

foreach ($source in @($agentSource, $skillSource, $policySource)) {
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing package file: $source"
    }
}

$agentContent = (Get-Content -Raw -Encoding UTF8 -LiteralPath $agentSource) -replace "(?m)^model:\s*.*$", "model: $CollectorModel"
$skillContent = (Get-Content -Raw -Encoding UTF8 -LiteralPath $skillSource) -replace "(?m)^model:\s*.*$", "model: $CollectorModel"
$policyBody = (Get-Content -Raw -Encoding UTF8 -LiteralPath $policySource).Replace("{{COLLECTOR_MODEL}}", $CollectorModel).Trim()

$beginMarker = "<!-- BEGIN optimize-claude-model-research -->"
$endMarker = "<!-- END optimize-claude-model-research -->"
$newline = [Environment]::NewLine
$policyBlock = $beginMarker + $newline + $policyBody + $newline + $endMarker
$existingPolicy = if (Test-Path -LiteralPath $policyTarget) {
    Get-Content -Raw -Encoding UTF8 -LiteralPath $policyTarget
} else {
    ""
}
$markerPattern = [regex]::Escape($beginMarker) + ".*?" + [regex]::Escape($endMarker)
if ([regex]::IsMatch($existingPolicy, $markerPattern, [Text.RegularExpressions.RegexOptions]::Singleline)) {
    $mergedPolicy = [regex]::Replace(
        $existingPolicy,
        $markerPattern,
        [Text.RegularExpressions.MatchEvaluator]{ param($match) $policyBlock },
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
} elseif ([string]::IsNullOrWhiteSpace($existingPolicy)) {
    $mergedPolicy = $policyBlock + $newline
} else {
    $mergedPolicy = $existingPolicy.TrimEnd() + $newline + $newline + $policyBlock + $newline
}

function Install-Content {
    param(
        [string]$Target,
        [string]$Content
    )

    if ($DryRun) {
        Write-Host "[dry-run] install $Target"
        return
    }

    if (Test-Path -LiteralPath $Target) {
        $current = Get-Content -Raw -Encoding UTF8 -LiteralPath $Target
        if ($current -ne $Content) {
            $relative = $Target.Substring($ClaudeHome.TrimEnd("\", "/").Length).TrimStart("\", "/")
            $backupTarget = Join-Path $backupRoot $relative
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupTarget) | Out-Null
            Copy-Item -LiteralPath $Target -Destination $backupTarget
            Write-Host "Backed up $Target"
        }
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
    [IO.File]::WriteAllText($Target, $Content, $utf8)
    Write-Host "Installed $Target"
}

Install-Content -Target $agentTarget -Content $agentContent
Install-Content -Target $skillTarget -Content $skillContent
Install-Content -Target $policyTarget -Content $mergedPolicy

$override = [Environment]::GetEnvironmentVariable("CLAUDE_CODE_SUBAGENT_MODEL", "Process")
if ([string]::IsNullOrWhiteSpace($override)) {
    $override = [Environment]::GetEnvironmentVariable("CLAUDE_CODE_SUBAGENT_MODEL", "User")
}
if ([string]::IsNullOrWhiteSpace($override)) {
    $override = [Environment]::GetEnvironmentVariable("CLAUDE_CODE_SUBAGENT_MODEL", "Machine")
}
if (-not [string]::IsNullOrWhiteSpace($override) -and $override -ne "inherit") {
    Write-Warning "CLAUDE_CODE_SUBAGENT_MODEL=$override overrides the collector model. Unset it or set it to inherit."
}

Write-Host ""
Write-Host "Claude Research Router is installed with collector model: $CollectorModel"
Write-Host "Restart Claude Code, then run /doctor, /memory, /skills, and /agents."
Write-Host "Smoke test: /collect-data Collect two primary sources for a narrow research question."
