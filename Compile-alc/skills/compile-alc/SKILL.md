---
name: compile-alc
description: Compile the AL app directly using alc.exe from the AL Language VS Code extension. No BcContainerHelper or Docker required.
allowed-tools: Bash
---

# Skill: compile-alc

# Compile AL App Directly with alc.exe

Compile the AL application directly using `alc.exe` from the installed AL Language VS Code extension. This is faster than the BcContainerHelper approach as it uses the locally installed compiler with no container or cloud dependencies.

## Prerequisites

- VS Code with the AL Language extension installed (`ms-dynamics-smb.al-*`)
- Symbol packages (`.app` files) present in `.alpackages/`

## Steps

### 1. Locate alc.exe

Find the newest installed AL Language extension:

```powershell
$alExtension = Get-ChildItem "$env:USERPROFILE\.vscode\extensions" -Filter "ms-dynamics-smb.al-*" -Directory |
    Sort-Object Name -Descending |
    Select-Object -First 1

$alcExe = Join-Path $alExtension.FullName "bin\win32\alc.exe"
$analyzerDir = Join-Path $alExtension.FullName "bin\Analyzers"
```

### 2. Locate LinterCop (optional)

The LinterCop analyzer DLL is downloaded by the VS Code extension into a versioned subfolder. Locate it dynamically:

```powershell
$linterCopExtension = Get-ChildItem "$env:USERPROFILE\.vscode\extensions" -Filter "stefanmaron.businesscentral-lintercop-*" -Directory |
    Sort-Object Name -Descending |
    Select-Object -First 1

# LinterCop downloads its DLL next to alc.exe in the AL extension analyzer folder
# Fall back gracefully if not found
$linterCopDll = $null
if ($linterCopExtension) {
    $candidate = Join-Path $analyzerDir "BusinessCentral.LinterCop.dll"
    if (Test-Path $candidate) {
        $linterCopDll = $candidate
    }
}
```

### 3. Determine project and output paths

Do not hardcode an app folder. Resolve the repo root dynamically and then choose the project directory using one of these approaches:

1. If the current working directory already contains `app.json`, use that folder.
2. Otherwise inspect `apps/*/app.json`.
3. If there is exactly one non-test app, use that.
4. If multiple app folders are valid candidates, specify the app explicitly via the helper script using `-AppName` or `-ProjectPath`.

```powershell
$repoRoot = git rev-parse --show-toplevel
$currentDir = (Get-Location).Path

if (Test-Path (Join-Path $currentDir 'app.json')) {
    $projectDir = $currentDir
} else {
    $appJsonFiles = Get-ChildItem (Join-Path $repoRoot 'apps') -Recurse -Filter 'app.json' -File
    $appCandidates = foreach ($appJsonFile in $appJsonFiles) {
        $appJson = Get-Content $appJsonFile.FullName -Raw | ConvertFrom-Json
        [PSCustomObject]@{
            Directory = $appJsonFile.Directory.FullName
            Name = [string]$appJson.name
            IsTest = ($appJsonFile.Directory.Name -match 'test') -or ([string]$appJson.name -match 'test')
        }
    }

    $nonTestCandidates = @($appCandidates | Where-Object { -not $_.IsTest })
    if ($nonTestCandidates.Count -eq 1) {
        $projectDir = $nonTestCandidates[0].Directory
    } elseif ($appCandidates.Count -eq 1) {
        $projectDir = $appCandidates[0].Directory
    } else {
        throw 'Could not determine a single AL project directory automatically.'
    }
}

$packageCachePath = Join-Path $repoRoot '.alpackages'
$outFolder = Join-Path $repoRoot '.outFolder'
$ruleSetFile = Join-Path $repoRoot 'common\codeanalysis\rules.json'

# Ensure output folder exists
New-Item -ItemType Directory -Path $outFolder -Force | Out-Null
```

### 4. Build the alc.exe argument list

```powershell
$alcArgs = @(
    "/project:`"$projectDir`"",
    "/packagecachepath:`"$packageCachePath`"",
    "/outfolder:`"$outFolder`"",
    "/analyzer:`"$analyzerDir\Microsoft.Dynamics.Nav.CodeCop.dll`"",
    "/analyzer:`"$analyzerDir\Microsoft.Dynamics.Nav.UICop.dll`"",
    "/analyzer:`"$analyzerDir\Microsoft.Dynamics.Nav.PerTenantExtensionCop.dll`""
)

# Add ruleset if it exists
if (Test-Path $ruleSetFile) {
    $alcArgs += "/ruleset:`"$ruleSetFile`""
}

# Add LinterCop if found
if ($linterCopDll) {
    $alcArgs += "/analyzer:`"$linterCopDll`""
}
```

### 5. Run the compiler

```powershell
$result = & $alcExe @alcArgs 2>&1
$exitCode = $LASTEXITCODE
$output = $result | Out-String
```

### 6. Parse and report output

Run the full command as a single PowerShell one-liner suitable for Bash:

```bash
pwsh -NoProfile -ExecutionPolicy Bypass -Command "
\$repoRoot = git rev-parse --show-toplevel
\$alExt = Get-ChildItem \"\$env:USERPROFILE\.vscode\extensions\" -Filter 'ms-dynamics-smb.al-*' -Directory | Sort-Object Name -Descending | Select-Object -First 1
\$alcExe = Join-Path \$alExt.FullName 'bin\win32\alc.exe'
\$analyzerDir = Join-Path \$alExt.FullName 'bin\Analyzers'
\$currentDir = (Get-Location).Path
if (Test-Path (Join-Path \$currentDir 'app.json')) {
  \$projectDir = \$currentDir
} else {
  \$appJsonFiles = Get-ChildItem (Join-Path \$repoRoot 'apps') -Recurse -Filter 'app.json' -File
  \$appCandidates = foreach (\$appJsonFile in \$appJsonFiles) {
    \$appJson = Get-Content \$appJsonFile.FullName -Raw | ConvertFrom-Json
    [PSCustomObject]@{ Directory = \$appJsonFile.Directory.FullName; Name = [string]\$appJson.name; IsTest = (\$appJsonFile.Directory.Name -match 'test') -or ([string]\$appJson.name -match 'test') }
  }
  \$nonTestCandidates = @(\$appCandidates | Where-Object { -not \$_.IsTest })
  if (\$nonTestCandidates.Count -eq 1) {
    \$projectDir = \$nonTestCandidates[0].Directory
  } elseif (\$appCandidates.Count -eq 1) {
    \$projectDir = \$appCandidates[0].Directory
  } else {
    throw 'Could not determine a single AL project directory automatically.'
  }
}
\$packageCachePath = Join-Path \$repoRoot '.alpackages'
\$outFolder = Join-Path \$repoRoot '.outFolder'
\$ruleSetFile = Join-Path \$repoRoot 'common\codeanalysis\rules.json'
New-Item -ItemType Directory -Path \$outFolder -Force | Out-Null
\$alcArgs = @('/project:"\$projectDir"', '/packagecachepath:"\$packageCachePath"', '/outfolder:"\$outFolder"', '/analyzer:"\$analyzerDir\Microsoft.Dynamics.Nav.CodeCop.dll"', '/analyzer:"\$analyzerDir\Microsoft.Dynamics.Nav.UICop.dll"', '/analyzer:"\$analyzerDir\Microsoft.Dynamics.Nav.PerTenantExtensionCop.dll"')
if (Test-Path \$ruleSetFile) { \$alcArgs += '/ruleset:"\$ruleSetFile"' }
\$linterDll = Join-Path \$analyzerDir 'BusinessCentral.LinterCop.dll'
if (Test-Path \$linterDll) { \$alcArgs += '/analyzer:"\$linterDll"' }
\$output = & \$alcExe @alcArgs 2>&1 | Out-String
Write-Host \$output
exit \$LASTEXITCODE
"
```

**Alternatively**, use the helper script in this skill (see below).

### 7. Interpret results

AL compiler output format:
```
path\to\file.al(line,col): error ALXXXX: Message
path\to\file.al(line,col): warning ALXXXX: Message
```

- **No output / exit code 0**: Compilation succeeded. Report the `.app` file location in `.outFolder/`.
- **Errors (exit code non-zero)**: Extract and summarize each `error ALXXXX` line. Group by file. Provide specific guidance on how to fix each error.
- **Warnings only**: Compilation succeeded with warnings. Summarize the warnings but note the build passed.

Common errors:
- `AL0001` / `AL0003`: Syntax errors
- `AL0132`: Object with same ID already exists
- `AL0185`: Missing dependency / symbol not found
- `AL0604`: Missing TDY affix on object name
- `AL0161` / `AL0162`: AppSourceCop violations

## Helper Script

A self-contained PowerShell helper script lives at `.opencode/scripts/Compile-Alc.ps1` alongside this skill. It has no dependency on any pipeline infrastructure and works in any AL repository. Run it from the repo root:

```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File .opencode/scripts/Compile-Alc.ps1
```

Options:
- `-ProjectPath <path>` - compile a specific AL app folder (absolute or relative to repo root)
- `-AppName <name>` - compile the app whose `app.json` name or folder name matches
- `-OutFolder <path>` - override the output folder (defaults to `.outFolder` in repo root)
- `-IncludeLinterCop` - include the LinterCop analyzer (default: auto-detected when DLL is present)
- `-NoAnalyzers` - skip all analyzers, compiler errors only

Recommended usage when multiple apps exist:

```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File .opencode/scripts/Compile-Alc.ps1 -AppName MyApp
```

## Notes

- The `.alpackages/` folder must contain BC symbol packages (`.app` files). If missing, copy them from a working developer machine.
- `alc.exe` version must match or exceed the `runtime` version in the selected `app.json`.
- LinterCop DLL is auto-detected from the VS Code extensions folder. If not found, the build runs without it.
- The script discovers `rules.json` automatically by searching common locations (`common/codeanalysis/rules.json`, `common/rules.json`, `.codeanalysis/rules.json`, `rules.json`). If none is found the build runs without a ruleset.
- The script scans the entire repo for `app.json` files when no app is specified, so it works regardless of folder structure (`apps/`, `src/`, or any other).
