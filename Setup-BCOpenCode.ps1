#Requires -Version 5.1
<#
.SYNOPSIS
    OpenCode setup for Business Central AL development.

.DESCRIPTION
    Run this script once in the root of any Business Central repository to
    configure OpenCode with everything needed for AL development:

      - AL LSP (al-lsp-for-agents) -- go-to-definition, find references,
        call hierarchy and hover directly in OpenCode
      - Microsoft Learn MCP server -- live documentation search from
        learn.microsoft.com inside the agent context
      - compile-alc skill -- lets OpenCode compile AL apps directly via
        alc.exe from the VS Code AL extension, no BcContainerHelper or
        Docker required
      - /compile-alc command -- slash-command wired to the skill
      - Compile-Alc.ps1 helper script -- the PowerShell driver used by the
        skill and command

    All project-level files land in .opencode/ and opencode.json at the
    repository root. Nothing is written to global OpenCode config.

.PARAMETER SourceRepo
    URL of the repository that hosts the BC OpenCode assets.
    Defaults to the SShadowS/al-lsp-for-agents repo for the LSP binaries
    and to this script's own location for the .opencode assets.

.PARAMETER SkipLsp
    Skip downloading and configuring the AL LSP.

.PARAMETER SkipMcp
    Skip adding the Microsoft Learn MCP server.

.PARAMETER SkipAssets
    Skip copying skills, commands and scripts into .opencode/.

.PARAMETER Force
    Overwrite existing .opencode assets without prompting.

.EXAMPLE
    # Run directly from GitHub (recommended):
    irm https://raw.githubusercontent.com/<org>/<repo>/main/Setup-BCOpenCode.ps1 | iex

.EXAMPLE
    # Run locally from a cloned copy:
    .\Setup-BCOpenCode.ps1

.EXAMPLE
    # Skip the LSP (e.g. Linux where a different wrapper is needed):
    .\Setup-BCOpenCode.ps1 -SkipLsp
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$SkipLsp,
    [switch]$SkipMcp,
    [switch]$SkipAssets,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── Helpers ────────────────────────────────────────────────────────────────────

function Write-Header([string]$Text) {
    Write-Host ""
    Write-Host "--- $Text" -ForegroundColor Cyan
}

function Write-Info([string]$Text)  { Write-Host "  [INFO] $Text" -ForegroundColor Green }
function Write-Warn([string]$Text)  { Write-Host "  [WARN] $Text" -ForegroundColor Yellow }
function Write-Err([string]$Text)   { Write-Host "  [ERR]  $Text" -ForegroundColor Red }
function Stop-Setup([string]$Text)  { Write-Err $Text; exit 1 }

function Merge-Json {
    <#
    .SYNOPSIS
        Deep-merge $Patch into $Base. Values in $Patch win on conflicts.
        Both inputs and output are [PSCustomObject].
    #>
    param(
        [PSCustomObject]$Base,
        [PSCustomObject]$Patch
    )

    foreach ($prop in $Patch.PSObject.Properties) {
        $key   = $prop.Name
        $pVal  = $prop.Value
        $bProp = $Base.PSObject.Properties[$key]
        $bVal  = if ($bProp) { $bProp.Value } else { $null }

        if (
            $pVal  -is [PSCustomObject] -and
            $bVal  -is [PSCustomObject]
        ) {
            # Recurse into nested objects
            $Base.$key = Merge-Json -Base $bVal -Patch $pVal
        } else {
            if ($Base.PSObject.Properties[$key]) {
                $Base.$key = $pVal
            } else {
                $Base | Add-Member -NotePropertyName $key -NotePropertyValue $pVal -Force
            }
        }
    }
    return $Base
}

function Read-JsonFile([string]$Path) {
    try {
        return (Get-Content $Path -Raw -Encoding UTF8) | ConvertFrom-Json
    } catch {
        Stop-Setup "Cannot parse JSON at '$Path': $_"
    }
}

function Write-JsonFile([string]$Path, [object]$Data) {
    $json = $Data | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.Encoding]::UTF8)
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# ── Resolve script source directory ────────────────────────────────────────────
# When piped via irm|iex $PSScriptRoot is empty, so we fall back to a temp
# download. When run from a cloned copy $PSScriptRoot points to the repo.

$ScriptDir = $PSScriptRoot
$IsRemote  = [string]::IsNullOrEmpty($ScriptDir)

# ── Banner ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "+======================================================+" -ForegroundColor Cyan
Write-Host "|  OpenCode -- Business Central AL development setup    |" -ForegroundColor Cyan
Write-Host "+======================================================+" -ForegroundColor Cyan
Write-Host ""

# ── Determine target project directory ────────────────────────────────────────

$TargetDir = (Get-Location).Path
Write-Info "Target project : $TargetDir"
Write-Info "Script source  : $(if ($IsRemote) { 'remote (irm|iex)' } else { $ScriptDir })"

# ── Paths ──────────────────────────────────────────────────────────────────────

$OpenCodeDir  = Join-Path $TargetDir '.opencode'
$SkillsDir    = Join-Path $OpenCodeDir 'skills'
$CommandsDir  = Join-Path $OpenCodeDir 'commands'
$ScriptsDir   = Join-Path $OpenCodeDir 'scripts'
$ConfigPath   = Join-Path $TargetDir 'opencode.json'

$LspInstallBase = Join-Path $env:LOCALAPPDATA 'al-lsp'
$LspBinDir      = Join-Path $LspInstallBase 'bin'
$LspVersionFile = Join-Path $LspInstallBase '.version'
$LspRepo        = 'SShadowS/al-lsp-for-agents'
$LspExe         = Join-Path $LspBinDir 'al-lsp-wrapper.exe'

# ===============================================================================
# STEP 1 -- Prerequisites
# ===============================================================================

Write-Header "Checking prerequisites"

# AL Language extension
$AlExtDirs = @(
    (Join-Path $env:USERPROFILE '.vscode\extensions'),
    (Join-Path $env:USERPROFILE '.vscode-insiders\extensions'),
    (Join-Path $env:USERPROFILE '.cursor\extensions')
)

$AlExtension = $null
foreach ($dir in $AlExtDirs) {
    if (Test-Path $dir) {
        $found = Get-ChildItem $dir -Directory -Filter 'ms-dynamics-smb.al-*' -ErrorAction SilentlyContinue |
            Sort-Object { [version]($_.Name -replace '^ms-dynamics-smb\.al-', '') } -Descending |
            Select-Object -First 1
        if ($found) { $AlExtension = $found; break }
    }
}

if ($AlExtension) {
    Write-Info "AL extension    : $($AlExtension.Name)"
} else {
    Write-Warn "AL Language extension not found in VS Code / Cursor extensions."
    Write-Warn "Install it from: https://marketplace.visualstudio.com/items?itemName=ms-dynamics-smb.al"
    Write-Warn "The LSP step will be skipped. Re-run after installing the extension."
    $SkipLsp = $true
}

# ===============================================================================
# STEP 2 -- AL LSP binaries
# ===============================================================================

if (-not $SkipLsp) {
    Write-Header "AL LSP for Agents (al-lsp-wrapper)"

    # Fetch latest release
    Write-Info "Checking latest release from github.com/$LspRepo ..."
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$LspRepo/releases/latest"
    } catch {
        Stop-Setup "Failed to reach GitHub API. Check your internet connection."
    }

    $tag = $release.tag_name
    if (-not $tag) { Stop-Setup "Could not read release tag from GitHub API response." }

    # Skip if already current
    if ((Test-Path $LspVersionFile) -and ((Get-Content $LspVersionFile -Raw).Trim() -eq $tag)) {
        Write-Info "Already on $tag -- skipping download."
    } else {
        $assetName = 'al-lsp-wrapper-windows-x64.zip'
        $asset     = $release.assets | Where-Object { $_.name -eq $assetName }
        if (-not $asset) { Stop-Setup "Asset '$assetName' not found in release $tag." }

        Write-Info "Downloading $tag ..."
        $tmpDir  = Join-Path $env:TEMP "al-lsp-setup-$(Get-Random)"
        $zipPath = Join-Path $tmpDir $assetName
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

        try {
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing
        } catch {
            Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
            Stop-Setup "Download failed: $_"
        }

        Write-Info "Extracting to $LspBinDir ..."
        Ensure-Dir $LspBinDir
        Expand-Archive -Path $zipPath -DestinationPath $LspBinDir -Force
        [System.IO.File]::WriteAllText($LspVersionFile, $tag)
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
        Write-Info "Installed $tag"
    }

    Write-Info "LSP binary      : $LspExe"
}

# ===============================================================================
# STEP 3 -- .opencode/ assets  (skills, commands, scripts)
# ===============================================================================

if (-not $SkipAssets) {
    Write-Header ".opencode/ assets"

    $CleanTmpDir  = $null
    $AssetsRoot   = $ScriptDir   # points to repo root when run locally

    if ($IsRemote) {
        # irm|iex only downloads the .ps1 — fetch the full repo zip to get assets
        $AssetsZipUrl = 'https://github.com/dfredborg/OpenCode-BC/archive/refs/heads/main.zip'
        Write-Info "Downloading assets from GitHub ..."

        $tmpDir  = Join-Path $env:TEMP "bc-opencode-setup-$(Get-Random)"
        $zipPath = Join-Path $tmpDir 'repo.zip'
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

        try {
            Invoke-WebRequest -Uri $AssetsZipUrl -OutFile $zipPath -UseBasicParsing
        } catch {
            Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
            Stop-Setup "Failed to download assets: $_"
        }

        Write-Info "Extracting assets ..."
        Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force

        # GitHub zips extract to <repo>-<branch>/, e.g. OpenCode-BC-main/
        $extractedRoot = Get-ChildItem $tmpDir -Directory | Select-Object -First 1
        if (-not $extractedRoot) { Stop-Setup "Could not find extracted directory in $tmpDir." }

        $AssetsRoot  = $extractedRoot.FullName
        $CleanTmpDir = $tmpDir
        Write-Info "Assets ready    : $AssetsRoot"
    }

    # Resolve source paths from the assets root (local or downloaded)
    $SrcSkill    = Join-Path $AssetsRoot 'Compile-alc\skills\compile-alc'
    $SrcCommand  = Join-Path $AssetsRoot 'Compile-alc\command\compile-alc.md'
    $SrcSetupCmd = Join-Path $AssetsRoot 'Compile-alc\command\setup-bc.md'
    $SrcScript   = Join-Path $AssetsRoot 'Compile-alc\scripts\Compile-Alc.ps1'

    $MissingAssets = @()
    if (-not (Test-Path (Join-Path $SrcSkill 'SKILL.md'))) { $MissingAssets += (Join-Path $SrcSkill 'SKILL.md') }
    if (-not (Test-Path $SrcCommand))                       { $MissingAssets += $SrcCommand }
    if (-not (Test-Path $SrcSetupCmd))                      { $MissingAssets += $SrcSetupCmd }
    if (-not (Test-Path $SrcScript))                        { $MissingAssets += $SrcScript }

    if ($MissingAssets.Count -gt 0) {
        Write-Warn "Some source assets were not found:"
        $MissingAssets | ForEach-Object { Write-Warn "  missing: $_" }
        Write-Warn "Skipping .opencode/ asset copy."
    } else {
        # skill: .opencode/skills/compile-alc/SKILL.md
        $DstSkillDir  = Join-Path $SkillsDir 'compile-alc'
        Ensure-Dir $DstSkillDir
        $DstSkillFile = Join-Path $DstSkillDir 'SKILL.md'
        if ((Test-Path $DstSkillFile) -and -not $Force) {
            Write-Info "Skill already exists -- skipping (use -Force to overwrite)."
        } else {
            Copy-Item (Join-Path $SrcSkill 'SKILL.md') $DstSkillFile -Force
            Write-Info "Copied skill      : $DstSkillFile"
        }

        # commands: compile-alc.md and setup-bc.md
        Ensure-Dir $CommandsDir
        foreach ($CmdPair in @(
            @{ Src = $SrcCommand;  Dst = (Join-Path $CommandsDir 'compile-alc.md') },
            @{ Src = $SrcSetupCmd; Dst = (Join-Path $CommandsDir 'setup-bc.md') }
        )) {
            if ((Test-Path $CmdPair.Dst) -and -not $Force) {
                Write-Info "Command already exists -- skipping: $($CmdPair.Dst) (use -Force to overwrite)."
            } else {
                Copy-Item $CmdPair.Src $CmdPair.Dst -Force
                Write-Info "Copied command    : $($CmdPair.Dst)"
            }
        }

        # script: .opencode/scripts/Compile-Alc.ps1
        Ensure-Dir $ScriptsDir
        $DstScript = Join-Path $ScriptsDir 'Compile-Alc.ps1'
        if ((Test-Path $DstScript) -and -not $Force) {
            Write-Info "Script already exists -- skipping (use -Force to overwrite)."
        } else {
            Copy-Item $SrcScript $DstScript -Force
            Write-Info "Copied script     : $DstScript"
        }
    }

    # Clean up temp download if we fetched remotely
    if ($CleanTmpDir -and (Test-Path $CleanTmpDir)) {
        Remove-Item -Recurse -Force $CleanTmpDir -ErrorAction SilentlyContinue
    }
}

# ===============================================================================
# STEP 4 -- opencode.json
# ===============================================================================

Write-Header "opencode.json"

# Build the desired config patch
$Patch = [PSCustomObject]@{
    '$schema' = 'https://opencode.ai/config.json'
}

if (-not $SkipMcp) {
    $Patch | Add-Member -NotePropertyName 'mcp' -NotePropertyValue ([PSCustomObject]@{
        'microsoft.docs.mcp' = [PSCustomObject]@{
            type    = 'remote'
            url     = 'https://learn.microsoft.com/api/mcp'
            enabled = $true
        }
    })
    $Patch | Add-Member -NotePropertyName 'permission' -NotePropertyValue ([PSCustomObject]@{
        'microsoft.docs.mcp_microsoft_docs_search' = 'allow'
    })
}

if (-not $SkipLsp) {
    # Use forward slashes -- works on Windows and is valid JSON
    $LspExeJson = $LspExe -replace '\\', '/'
    $Patch | Add-Member -NotePropertyName 'lsp' -NotePropertyValue ([PSCustomObject]@{
        al = [PSCustomObject]@{
            command    = @($LspExeJson)
            extensions = @('.al', '.dal')
        }
    })
}

# Merge into existing config or create fresh
if (Test-Path $ConfigPath) {
    Write-Info "Merging into existing opencode.json ..."
    $Existing = Read-JsonFile $ConfigPath
    $Merged   = Merge-Json -Base $Existing -Patch $Patch
    Write-JsonFile $ConfigPath $Merged
    Write-Info "Updated : $ConfigPath"
} else {
    Write-Info "Creating opencode.json ..."
    Write-JsonFile $ConfigPath $Patch
    Write-Info "Created : $ConfigPath"
}

# ===============================================================================
# Done
# ===============================================================================

Write-Host ""
Write-Host "+======================================================+" -ForegroundColor Green
Write-Host "|  Setup complete!                                     |" -ForegroundColor Green
Write-Host "+======================================================+" -ForegroundColor Green
Write-Host ""

if (-not $SkipLsp)    { Write-Info "AL LSP installed  : $LspBinDir" }
if (-not $SkipMcp)    { Write-Info "MCP configured    : Microsoft Learn (learn.microsoft.com/api/mcp)" }
if (-not $SkipAssets) { Write-Info "Skills/commands   : $OpenCodeDir" }
Write-Info "Config            : $ConfigPath"

Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "  1. Open this repository in OpenCode: opencode" -ForegroundColor White
Write-Host "  2. Use /compile-alc to compile your AL app" -ForegroundColor White
Write-Host "  3. Open any .al file and LSP features activate automatically" -ForegroundColor White
Write-Host ""
