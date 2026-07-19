[CmdletBinding()]
param(
    [string]$ClaudeHome = (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".claude"),
    [string]$CollectorModel = "claude-opus-4-8",
    [string]$AnalystModel = "claude-opus-4-8",
    [string]$WorkerModel = "sonnet",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

foreach ($modelSetting in @{
    CollectorModel = $CollectorModel
    AnalystModel = $AnalystModel
    WorkerModel = $WorkerModel
}.GetEnumerator()) {
    if ($modelSetting.Value -notmatch "^[A-Za-z0-9._:/\[\]-]+$") {
        throw "$($modelSetting.Key) contains unsupported characters: $($modelSetting.Value)"
    }
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$collectorAgentSource = Join-Path $repoRoot ".claude\agents\data-collector.md"
$analystAgentSource = Join-Path $repoRoot ".claude\agents\data-analyst.md"
$workerAgentSource = Join-Path $repoRoot ".claude\agents\research-worker.md"
$collectSkillSource = Join-Path $repoRoot ".claude\skills\collect-data\SKILL.md"
$analyzeSkillSource = Join-Path $repoRoot ".claude\skills\analyze-data\SKILL.md"
$executeSkillSource = Join-Path $repoRoot ".claude\skills\execute-research\SKILL.md"
$routeSkillSource = Join-Path $repoRoot ".claude\skills\route-research\SKILL.md"
$planSkillSource = Join-Path $repoRoot ".claude\skills\execute-research-plan\SKILL.md"
$policySource = Join-Path $repoRoot "templates\research-model-routing.md"
$collectorAgentTarget = Join-Path $ClaudeHome "agents\data-collector.md"
$analystAgentTarget = Join-Path $ClaudeHome "agents\data-analyst.md"
$workerAgentTarget = Join-Path $ClaudeHome "agents\research-worker.md"
$collectSkillTarget = Join-Path $ClaudeHome "skills\collect-data\SKILL.md"
$analyzeSkillTarget = Join-Path $ClaudeHome "skills\analyze-data\SKILL.md"
$executeSkillTarget = Join-Path $ClaudeHome "skills\execute-research\SKILL.md"
$routeSkillTarget = Join-Path $ClaudeHome "skills\route-research\SKILL.md"
$planSkillTarget = Join-Path $ClaudeHome "skills\execute-research-plan\SKILL.md"
$policyTarget = Join-Path $ClaudeHome "CLAUDE.md"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $ClaudeHome "backups\optimize-claude-model-research\$timestamp"
$utf8 = New-Object System.Text.UTF8Encoding($false)

foreach ($source in @(
    $collectorAgentSource,
    $analystAgentSource,
    $workerAgentSource,
    $collectSkillSource,
    $analyzeSkillSource,
    $executeSkillSource,
    $routeSkillSource,
    $planSkillSource,
    $policySource
)) {
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing package file: $source"
    }
}

$collectorAgentContent = (Get-Content -Raw -Encoding UTF8 -LiteralPath $collectorAgentSource) -replace "(?m)^model:\s*.*$", "model: $CollectorModel"
$analystAgentContent = (Get-Content -Raw -Encoding UTF8 -LiteralPath $analystAgentSource) -replace "(?m)^model:\s*.*$", "model: $AnalystModel"
$workerAgentContent = (Get-Content -Raw -Encoding UTF8 -LiteralPath $workerAgentSource) -replace "(?m)^model:\s*.*$", "model: $WorkerModel"
$collectSkillContent = (Get-Content -Raw -Encoding UTF8 -LiteralPath $collectSkillSource) -replace "(?m)^model:\s*.*$", "model: $CollectorModel"
$analyzeSkillContent = (Get-Content -Raw -Encoding UTF8 -LiteralPath $analyzeSkillSource) -replace "(?m)^model:\s*.*$", "model: $AnalystModel"
$executeSkillContent = (Get-Content -Raw -Encoding UTF8 -LiteralPath $executeSkillSource) -replace "(?m)^model:\s*.*$", "model: $WorkerModel"
$routeSkillContent = Get-Content -Raw -Encoding UTF8 -LiteralPath $routeSkillSource
$planSkillContent = Get-Content -Raw -Encoding UTF8 -LiteralPath $planSkillSource
$policyBody = Get-Content -Raw -Encoding UTF8 -LiteralPath $policySource
$policyBody = $policyBody.Replace("{{COLLECTOR_MODEL}}", $CollectorModel)
$policyBody = $policyBody.Replace("{{ANALYST_MODEL}}", $AnalystModel)
$policyBody = $policyBody.Replace("{{WORKER_MODEL}}", $WorkerModel)
$policyBody = $policyBody.Trim()

$beginMarker = "<!-- BEGIN optimize-claude-model-research -->"
$endMarker = "<!-- END optimize-claude-model-research -->"
$newline = [Environment]::NewLine
$policyBlock = $beginMarker + $newline + $policyBody + $newline + $endMarker
$existingPolicy = if (Test-Path -LiteralPath $policyTarget) {
    Get-Content -Raw -Encoding UTF8 -LiteralPath $policyTarget
} else {
    ""
}
$legacyNeedle = "Use the main Fable 5 context only for work that materially requires high-level judgment:"
$topLevelHeadingCount = [regex]::Matches($existingPolicy, "(?m)^# ").Count
if (
    -not $existingPolicy.Contains($beginMarker) -and
    $existingPolicy.Contains($legacyNeedle) -and
    $topLevelHeadingCount -eq 1
) {
    $existingPolicy = ""
    Write-Host "Migrating legacy unmarked router-only CLAUDE.md"
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

Install-Content -Target $collectorAgentTarget -Content $collectorAgentContent
Install-Content -Target $analystAgentTarget -Content $analystAgentContent
Install-Content -Target $workerAgentTarget -Content $workerAgentContent
Install-Content -Target $collectSkillTarget -Content $collectSkillContent
Install-Content -Target $analyzeSkillTarget -Content $analyzeSkillContent
Install-Content -Target $executeSkillTarget -Content $executeSkillContent
Install-Content -Target $routeSkillTarget -Content $routeSkillContent
Install-Content -Target $planSkillTarget -Content $planSkillContent
Install-Content -Target $policyTarget -Content $mergedPolicy

$override = [Environment]::GetEnvironmentVariable("CLAUDE_CODE_SUBAGENT_MODEL", "Process")
if ([string]::IsNullOrWhiteSpace($override)) {
    $override = [Environment]::GetEnvironmentVariable("CLAUDE_CODE_SUBAGENT_MODEL", "User")
}
if ([string]::IsNullOrWhiteSpace($override)) {
    $override = [Environment]::GetEnvironmentVariable("CLAUDE_CODE_SUBAGENT_MODEL", "Machine")
}
if (-not [string]::IsNullOrWhiteSpace($override) -and $override -ne "inherit") {
    Write-Warning "CLAUDE_CODE_SUBAGENT_MODEL=$override overrides all configured agent models. Unset it or set it to inherit."
}

Write-Host ""
Write-Host "Claude Research Router is installed."
Write-Host "  Collector: $CollectorModel"
Write-Host "  Data analyst: $AnalystModel"
Write-Host "  Research worker: $WorkerModel"
Write-Host "Restart Claude Code, then run /doctor, /memory, /skills, and /agents."
Write-Host "Plan workflow: create and approve a plan in Plan mode, then run /execute-research-plan <plan>."
Write-Host "Smoke tests: /collect-data, /analyze-data, and /execute-research."
