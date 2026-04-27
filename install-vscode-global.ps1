<#
.SYNOPSIS
    Installs Skills for Fabric globally for VS Code GitHub Copilot.

.DESCRIPTION
    Clones (or updates) the skills-for-fabric repository to ~/.skills-for-fabric,
    generates .prompt.md wrappers for each skill, and configures VS Code user
    settings so that all agents and skills are available in every workspace.

    Agents  → appear as custom chat participants (@FabricDataEngineer, etc.)
    Skills  → appear as reusable prompts (/sqldw-authoring-cli, etc.)

.PARAMETER InstallPath
    Local directory for the repository clone. Default: ~/.skills-for-fabric

.PARAMETER RepoUrl
    Git URL of the skills-for-fabric repository.

.PARAMETER SkipSettings
    Skip modifying VS Code user settings.json.

.EXAMPLE
    .\install-vscode-global.ps1

.EXAMPLE
    .\install-vscode-global.ps1 -InstallPath "D:\fabric-skills" -SkipSettings
#>

param(
    [string]$InstallPath = (Join-Path $env:USERPROFILE ".skills-for-fabric"),
    [string]$RepoUrl = "https://github.com/microsoft/skills-for-fabric.git",
    [switch]$SkipSettings
)

$ErrorActionPreference = "Stop"

function Write-Status($message) { Write-Host "[*] $message" -ForegroundColor Cyan }
function Write-Success($message) { Write-Host "[+] $message" -ForegroundColor Green }
function Write-Info($message) { Write-Host "    $message" -ForegroundColor Gray }

Write-Host ""
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "  Skills for Fabric  -  VS Code Global Installer" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

# ── Step 1: Clone or update the repository ──────────────────────────────────

if (Test-Path (Join-Path $InstallPath ".git")) {
    Write-Status "Updating existing installation at $InstallPath"
    Push-Location $InstallPath
    try { git pull --quiet } finally { Pop-Location }
}
else {
    if (Test-Path $InstallPath) {
        Write-Info "Removing stale directory..."
        Remove-Item -Recurse -Force $InstallPath
    }
    Write-Status "Cloning repository to $InstallPath"
    git clone $RepoUrl $InstallPath --quiet
}

Write-Success "Repository ready"

# ── Step 2: Generate .prompt.md wrappers for each skill ─────────────────────

Write-Host ""
Write-Status "Generating .prompt.md wrappers for skills..."

$skillsDir = Join-Path $InstallPath "skills"
$skillCount = 0

Get-ChildItem -Path $skillsDir -Directory | ForEach-Object {
    $skillName = $_.Name
    $skillMd = Join-Path $_.FullName "SKILL.md"

    if (-not (Test-Path $skillMd)) { return }

    # Extract the description from the YAML frontmatter
    $raw = Get-Content $skillMd -Raw
    $description = "Fabric skill: $skillName"

    # Match multi-line description (with >)
    if ($raw -match '(?s)description:\s*>\s*\n(.*?)(?=\n[a-zA-Z_-]+:|\n---)') {
        $desc = ($Matches[1].Trim() -replace '\s+', ' ')
        if ($desc.Length -gt 0) { $description = $desc }
    }
    # Match single-line description
    elseif ($raw -match 'description:\s*([^\n]+)') {
        $desc = $Matches[1].Trim().Trim('"').Trim("'")
        if ($desc.Length -gt 0) { $description = $desc }
    }

    # Cap length for VS Code UI
    if ($description.Length -gt 200) {
        $description = $description.Substring(0, 197) + "..."
    }

    # Write the .prompt.md wrapper
    $promptFile = Join-Path $_.FullName "$skillName.prompt.md"
    $promptContent = @"
---
description: >
  $description
mode: agent
---
#file:SKILL.md
"@
    Set-Content -Path $promptFile -Value $promptContent -Encoding UTF8 -NoNewline
    Write-Info "Skill: $skillName"
    $script:skillCount++
}

Write-Success "Generated $skillCount prompt wrappers"

# ── Step 3: List discovered agents ──────────────────────────────────────────

Write-Host ""
Write-Status "Agents (auto-discovered from agents/*.agent.md):"
$agentsDir = Join-Path $InstallPath "agents"
Get-ChildItem -Path $agentsDir -Filter "*.agent.md" | ForEach-Object {
    Write-Info "Agent: $($_.BaseName)"
}

# ── Step 4: Update VS Code user settings ────────────────────────────────────

if (-not $SkipSettings) {
    Write-Host ""
    Write-Status "Configuring VS Code user settings..."

    $vsCodeSettingsPath = Join-Path $env:APPDATA "Code\User\settings.json"

    # Read or create settings
    if (Test-Path $vsCodeSettingsPath) {
        $settingsRaw = Get-Content $vsCodeSettingsPath -Raw
        # Strip single-line JS comments (// ...) and trailing commas before parsing
        $stripped = $settingsRaw -replace '//[^\n]*', '' -replace ',(\s*[\}\]])', '$1'
        try {
            $settings = $stripped | ConvertFrom-Json
        }
        catch {
            Write-Host "[!] Could not parse settings.json — skipping automatic config." -ForegroundColor Yellow
            Write-Host "    Add the settings shown below manually." -ForegroundColor Yellow
            $SkipSettings = $true
        }
    }
    else {
        $settingsDir = Split-Path $vsCodeSettingsPath -Parent
        if (-not (Test-Path $settingsDir)) {
            New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null
        }
        $settings = [PSCustomObject]@{}
    }

    if (-not $SkipSettings) {
        # Paths use ~ so they are portable
        $requiredPaths = @(
            "~/.skills-for-fabric/skills",
            "~/.skills-for-fabric/agents"
        )

        # Ensure chat.promptFilesLocations exists
        if (-not $settings.PSObject.Properties["chat.promptFilesLocations"]) {
            $locObj = New-Object PSObject
            $settings | Add-Member -MemberType NoteProperty -Name "chat.promptFilesLocations" -Value $locObj
        }

        $locations = $settings."chat.promptFilesLocations"
        foreach ($p in $requiredPaths) {
            if (-not $locations.PSObject.Properties[$p]) {
                $locations | Add-Member -MemberType NoteProperty -Name $p -Value $true
            }
        }

        # Write back
        $settings | ConvertTo-Json -Depth 10 | Set-Content $vsCodeSettingsPath -Encoding UTF8
        Write-Success "VS Code settings updated ($vsCodeSettingsPath)"
    }
}

# ── Done ────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Restart VS Code, then use in any workspace:" -ForegroundColor White
Write-Host ""
Write-Host "  AGENTS (type @ in Copilot Chat):" -ForegroundColor White
Write-Host "    @FabricDataEngineer   Cross-workload data engineering" -ForegroundColor Gray
Write-Host "    @FabricAdmin          Administration and governance" -ForegroundColor Gray
Write-Host "    @FabricAppDev         Full-stack app development" -ForegroundColor Gray
Write-Host ""
Write-Host "  SKILLS (type / in Copilot Chat):" -ForegroundColor White
Write-Host "    /sqldw-authoring-cli          Author SQL objects in Warehouse" -ForegroundColor Gray
Write-Host "    /sqldw-consumption-cli        Query warehouses and SQL endpoints" -ForegroundColor Gray
Write-Host "    /spark-authoring-cli          Spark and data engineering workflows" -ForegroundColor Gray
Write-Host "    /spark-consumption-cli        Interactive Spark analysis" -ForegroundColor Gray
Write-Host "    /eventhouse-authoring-cli     KQL table management and ingestion" -ForegroundColor Gray
Write-Host "    /eventhouse-consumption-cli   Read-only KQL queries" -ForegroundColor Gray
Write-Host "    /powerbi-authoring-cli        Semantic model authoring" -ForegroundColor Gray
Write-Host "    /powerbi-consumption-cli      DAX queries and model discovery" -ForegroundColor Gray
Write-Host "    /e2e-medallion-architecture   End-to-end medallion architecture" -ForegroundColor Gray
Write-Host ""
Write-Host "  To update later, re-run this script." -ForegroundColor Gray
Write-Host ""
