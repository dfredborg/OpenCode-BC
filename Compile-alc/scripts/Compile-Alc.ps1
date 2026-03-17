<#
.SYNOPSIS
    Compile an AL app directly using alc.exe from the AL Language VS Code extension.

.DESCRIPTION
    Locates alc.exe from the newest installed AL Language extension, resolves
    paths dynamically from the repository root, and runs the compiler.

    No BcContainerHelper, Docker, or pipeline infrastructure required.
    Works in any AL repository regardless of folder structure.

.PARAMETER ProjectPath
    Explicit path to the AL app folder (containing app.json). Can be absolute
    or relative to the repository root.

.PARAMETER AppName
    Compile the app whose app.json "name" property or folder name matches this value.

.PARAMETER OutFolder
    Override the output folder for the compiled .app file. Defaults to .outFolder
    in the repository root.

.PARAMETER IncludeLinterCop
    Include the LinterCop analyzer. Auto-detected by default when the DLL is present.

.PARAMETER NoAnalyzers
    Skip all analyzers. Compiler errors only.

.EXAMPLE
    .\.opencode\scripts\Compile-Alc.ps1

.EXAMPLE
    .\.opencode\scripts\Compile-Alc.ps1 -AppName MyApp

.EXAMPLE
    .\.opencode\scripts\Compile-Alc.ps1 -ProjectPath apps/MyApp -NoAnalyzers
#>

param(
    [string]$ProjectPath,
    [string]$AppName,
    [string]$OutFolder,
    [switch]$IncludeLinterCop,
    [switch]$NoAnalyzers
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) { Write-Host ">> $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail([string]$msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }

function Resolve-ProjectDirectory {
    param(
        [string]$RepoRoot,
        [string]$ExplicitProjectPath,
        [string]$ExplicitAppName
    )

    # --- Explicit path ---
    if ($ExplicitProjectPath) {
        $resolved = if ([System.IO.Path]::IsPathRooted($ExplicitProjectPath)) {
            $ExplicitProjectPath
        } else {
            Join-Path $RepoRoot $ExplicitProjectPath
        }
        $resolved = [System.IO.Path]::GetFullPath($resolved)
        if (-not (Test-Path (Join-Path $resolved 'app.json'))) {
            Write-Fail "No app.json found in explicit project path: $resolved"
            exit 1
        }
        return $resolved
    }

    # --- Explicit app name: scan repo for matching app.json ---
    if ($ExplicitAppName) {
        $hits = Get-ChildItem $RepoRoot -Recurse -Filter 'app.json' -File -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    $json = Get-Content $_.FullName -Raw | ConvertFrom-Json
                    ([string]$json.name -eq $ExplicitAppName) -or ($_.Directory.Name -eq $ExplicitAppName)
                } catch { $false }
            }
        if ($hits.Count -eq 1) { return $hits[0].Directory.FullName }
        if ($hits.Count -gt 1) {
            Write-Fail "Multiple app folders matched AppName '$ExplicitAppName'. Use -ProjectPath instead."
            $hits | ForEach-Object { Write-Host "    $($_.Directory.FullName)" -ForegroundColor Gray }
            exit 1
        }
        Write-Fail "No app folder matched AppName '$ExplicitAppName'."
        exit 1
    }

    # --- Current working directory (walk up to repo root) ---
    $probe = (Get-Location).Path
    while ($probe -and ($probe.Length -ge $RepoRoot.Length)) {
        if (Test-Path (Join-Path $probe 'app.json')) { return $probe }
        if ($probe -eq $RepoRoot) { break }
        $parent = Split-Path $probe -Parent
        if ($parent -eq $probe) { break }
        $probe = $parent
    }

    # --- Auto-detect: scan entire repo for app.json files ---
    $allAppJson = Get-ChildItem $RepoRoot -Recurse -Filter 'app.json' -File -ErrorAction SilentlyContinue |
        Where-Object {
            # Exclude well-known non-project locations
            $path = $_.FullName
            $path -notmatch '[\\/]\.opencode[\\/]' -and
            $path -notmatch '[\\/]node_modules[\\/]' -and
            $path -notmatch '[\\/]\.alpackages[\\/]'
        }

    $candidates = foreach ($f in $allAppJson) {
        try {
            $json = Get-Content $f.FullName -Raw | ConvertFrom-Json
            [PSCustomObject]@{
                Directory = $f.Directory.FullName
                Name      = [string]$json.name
                IsTest    = ($f.Directory.Name -match '(?i)test') -or ([string]$json.name -match '(?i)test')
            }
        } catch {}
    }

    $nonTest = @($candidates | Where-Object { -not $_.IsTest })
    if ($nonTest.Count -eq 1) { return $nonTest[0].Directory }
    if ($candidates.Count -eq 1) { return $candidates[0].Directory }

    Write-Fail 'Could not determine a single AL project directory automatically.'
    Write-Host '    Use -ProjectPath <path> or -AppName <name>.' -ForegroundColor Gray
    if ($candidates.Count -gt 0) {
        Write-Host '    Candidates found:' -ForegroundColor Gray
        $candidates | ForEach-Object { Write-Host "      $($_.Directory)  ($($_.Name))" -ForegroundColor Gray }
    }
    exit 1
}

function Find-RuleSet([string]$RepoRoot) {
    # Search common locations for a rules.json / ruleset file
    $candidates = @(
        'common\codeanalysis\rules.json',
        'common\rules.json',
        '.codeanalysis\rules.json',
        'rules.json'
    )
    foreach ($rel in $candidates) {
        $full = Join-Path $RepoRoot $rel
        if (Test-Path $full) { return $full }
    }
    # Generic glob fallback
    $found = Get-ChildItem $RepoRoot -Recurse -Filter 'rules.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]node_modules[\\/]' } |
        Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

# ---------------------------------------------------------------------------- #
# Locate repo root
# ---------------------------------------------------------------------------- #

Write-Step "Locating repository root"
$gitResult = $null
$ErrorActionPreference = 'SilentlyContinue'
$gitResult = & git rev-parse --show-toplevel 2>&1
$gitExit   = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($gitExit -ne 0) {
    Write-Warn "Not inside a git repository - using current directory as root."
    $repoRoot = (Get-Location).Path
} else {
    $repoRoot = $gitResult.Trim().Replace('/', '\')
}
Write-Ok "Repo root: $repoRoot"

# ---------------------------------------------------------------------------- #
# Locate alc.exe
# ---------------------------------------------------------------------------- #

Write-Step "Locating alc.exe"
$alExtension = Get-ChildItem "$env:USERPROFILE\.vscode\extensions" -Filter "ms-dynamics-smb.al-*" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1

if (-not $alExtension) {
    Write-Fail "AL Language extension not found in $env:USERPROFILE\.vscode\extensions"
    Write-Host "    Install the AL Language extension in VS Code and try again." -ForegroundColor Gray
    exit 1
}

$alcExe      = Join-Path $alExtension.FullName "bin\win32\alc.exe"
$analyzerDir = Join-Path $alExtension.FullName "bin\Analyzers"

if (-not (Test-Path $alcExe)) {
    Write-Fail "alc.exe not found at: $alcExe"
    exit 1
}

Write-Ok "Using: $alcExe"
Write-Ok "Extension: $($alExtension.Name)"

# ---------------------------------------------------------------------------- #
# Resolve project paths
# ---------------------------------------------------------------------------- #

Write-Step "Resolving project paths"

$projectDir        = Resolve-ProjectDirectory -RepoRoot $repoRoot -ExplicitProjectPath $ProjectPath -ExplicitAppName $AppName
$packageCachePath  = Join-Path $repoRoot ".alpackages"
$resolvedOutFolder = if ($OutFolder) {
    if ([System.IO.Path]::IsPathRooted($OutFolder)) { $OutFolder }
    else { Join-Path $repoRoot $OutFolder }
} else {
    Join-Path $repoRoot ".outFolder"
}
$ruleSetFile = Find-RuleSet -RepoRoot $repoRoot

if (-not (Test-Path (Join-Path $projectDir 'app.json'))) {
    Write-Fail "Resolved project directory does not contain app.json: $projectDir"
    exit 1
}
if (-not (Test-Path $packageCachePath)) {
    Write-Warn ".alpackages not found at $packageCachePath  - compilation may fail if symbols are missing."
}

New-Item -ItemType Directory -Path $resolvedOutFolder -Force | Out-Null
Write-Ok "Project : $projectDir"
Write-Ok "Packages: $packageCachePath"
Write-Ok "Output  : $resolvedOutFolder"

# ---------------------------------------------------------------------------- #
# Build argument list
# ---------------------------------------------------------------------------- #

Write-Step "Building compiler arguments"

$alcArgs = @(
    "/project:$projectDir",
    "/packagecachepath:$packageCachePath",
    "/outfolder:$resolvedOutFolder"
)

if (-not $NoAnalyzers) {
    foreach ($dll in @('Microsoft.Dynamics.Nav.CodeCop.dll', 'Microsoft.Dynamics.Nav.UICop.dll', 'Microsoft.Dynamics.Nav.PerTenantExtensionCop.dll')) {
        $full = Join-Path $analyzerDir $dll
        if (Test-Path $full) {
            $alcArgs += "/analyzer:$full"
        } else {
            Write-Warn "Analyzer not found, skipping: $dll"
        }
    }

    $linterDll = Join-Path $analyzerDir "BusinessCentral.LinterCop.dll"
    if ($IncludeLinterCop -or (Test-Path $linterDll)) {
        if (Test-Path $linterDll) {
            $alcArgs += "/analyzer:$linterDll"
            Write-Ok "LinterCop: included"
        } else {
            Write-Warn "LinterCop DLL not found in $analyzerDir  - skipping."
            Write-Host "    Open VS Code to trigger the LinterCop download, then retry." -ForegroundColor Gray
        }
    }

    if ($ruleSetFile) {
        $alcArgs += "/ruleset:$ruleSetFile"
        Write-Ok "Ruleset : $ruleSetFile"
    } else {
        Write-Warn "No rules.json found  - running without ruleset."
    }
} else {
    Write-Warn "Analyzers disabled (-NoAnalyzers)"
}

# ---------------------------------------------------------------------------- #
# Compile
# ---------------------------------------------------------------------------- #

Write-Host ""
Write-Host ">> Compiling..." -ForegroundColor Cyan
Write-Host "   $alcExe $($alcArgs -join ' ')" -ForegroundColor DarkGray
Write-Host ""

$output   = & $alcExe @alcArgs 2>&1
$exitCode = $LASTEXITCODE

# ---------------------------------------------------------------------------- #
# Output and summary
# ---------------------------------------------------------------------------- #

$lines    = $output | Out-String
$errors   = $lines -split "`n" | Where-Object { $_ -match ": error AL" }
$warnings = $lines -split "`n" | Where-Object { $_ -match ": warning AL" }

if ($exitCode -eq 0) {
    Write-Host ""
    Write-Host "------------------------------------------------------" -ForegroundColor Green
    Write-Host "  Compilation succeeded" -ForegroundColor Green
    Write-Host "------------------------------------------------------" -ForegroundColor Green
    if ($warnings.Count -gt 0) {
        Write-Host "  $($warnings.Count) warning(s)" -ForegroundColor Yellow
        $warnings | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    }
    $appFile = Get-ChildItem $resolvedOutFolder -Filter "*.app" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($appFile) {
        Write-Host "  Output: $($appFile.FullName)" -ForegroundColor Green
    }
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "------------------------------------------------------" -ForegroundColor Red
    Write-Host "  Compilation failed  - $($errors.Count) error(s)" -ForegroundColor Red
    Write-Host "------------------------------------------------------" -ForegroundColor Red
    Write-Host ""
    $lines -split "`n" | Where-Object { $_.Trim() } | ForEach-Object {
        if     ($_ -match ": error AL")   { Write-Host $_ -ForegroundColor Red }
        elseif ($_ -match ": warning AL") { Write-Host $_ -ForegroundColor Yellow }
        else                               { Write-Host $_ }
    }
    Write-Host ""
}

exit $exitCode
