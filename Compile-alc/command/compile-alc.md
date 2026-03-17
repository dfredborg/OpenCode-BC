---
description: Compile an AL app with alc.exe using the shareable compile-alc skill
---

Compile an AL app with `alc.exe` using the `compile-alc` skill and the repository helper script.

**Input**: The argument after `/compile-alc` is optional and can be one of:

- an app name from `app.json`, for example `/compile-alc HJHansenBaseApp`
- an app folder path, for example `/compile-alc apps/HJHansenBaseApp`
- flags only, for example `/compile-alc --no-analyzers`
- app selector plus flags, for example `/compile-alc HJHansenBaseApp --include-lintercop`

## Steps

1. **Load the skill**

   Load the `compile-alc` skill first and follow its instructions.

2. **Interpret the input**

   Parse the optional input using these rules:

   - If the first non-flag token contains `/`, `\`, or starts with `apps`, treat it as `-ProjectPath`
   - Otherwise, treat the first non-flag token as `-AppName`
   - Supported flags:
     - `--no-analyzers` -> `-NoAnalyzers`
     - `--include-lintercop` -> `-IncludeLinterCop`
     - `--out <path>` -> `-OutFolder <path>`

3. **Run the helper script**

   The script lives inside `.opencode/scripts/` so it travels with the skill and works in any repository without pipeline infrastructure. Run it from the repo root:

   ```bash
   pwsh -NoProfile -ExecutionPolicy Bypass -File .opencode/scripts/Compile-Alc.ps1
   ```

   Add arguments only when needed:

   - App name example:
     ```bash
     pwsh -NoProfile -ExecutionPolicy Bypass -File .opencode/scripts/Compile-Alc.ps1 -AppName MyApp
     ```

   - Project path example:
     ```bash
     pwsh -NoProfile -ExecutionPolicy Bypass -File .opencode/scripts/Compile-Alc.ps1 -ProjectPath apps/MyApp
     ```

   - No analyzers example:
     ```bash
     pwsh -NoProfile -ExecutionPolicy Bypass -File .opencode/scripts/Compile-Alc.ps1 -AppName MyApp -NoAnalyzers
     ```

4. **Report the result**

   - If compilation succeeds, report the output `.app` path
   - If compilation fails, summarize the AL errors grouped by file
   - If compilation succeeds with warnings, note that the build passed and summarize the warnings briefly

## Output

Use this structure:

```text
Compiled: <app or path>
Result: success | failed
Output: <.app path if available>

Errors/Warnings:
- <summary>
```

## Guardrails

- Always use the `compile-alc` skill first
- Prefer the helper script over re-implementing the compiler command inline
- If the project cannot be determined automatically and no selector was provided, ask for either an app name or a project path
- Do not hardcode repository-specific app paths
