# OpenCode for Business Central

One-command setup that turns [OpenCode](https://opencode.ai) into a fully equipped AI coding agent for Business Central AL development.

## Quick start

**Option A — PowerShell one-liner** (run from your AL repository root):

```powershell
irm https://raw.githubusercontent.com/dfredborg/OpenCode-BC/main/Setup-BCOpenCode.ps1 | iex
```

**Option B — inside OpenCode** (if you already have OpenCode open in any project):

```
/setup-bc
```

Both options do the same thing. Option B uses the `/setup-bc` command that this setup installs, so you can re-run setup or set up new projects without ever leaving OpenCode.

---

## What you get

| Feature | What it does |
|---|---|
| **AL Language Server** | Go-to-definition, find references, call hierarchy, and hover — directly inside OpenCode |
| **Microsoft Learn MCP** | Live documentation search from `learn.microsoft.com` available to the agent without leaving the terminal |
| **`compile-alc` skill** | Teaches OpenCode how to compile AL apps directly via `alc.exe` — no BcContainerHelper, no Docker, no pipeline |
| **`/compile-alc` command** | Slash-command that triggers a full AL compilation with a single prompt |
| **`/review-bc` command** | Deep, brutally honest AL code review across the entire codebase — security, performance, upgrade safety, and more |
| **`/setup-bc` command** | Re-run setup or set up a new project from inside OpenCode |
| **`Compile-Alc.ps1` script** | The PowerShell driver behind the skill — works in any AL repo regardless of folder structure |

Everything is project-scoped. The setup writes to `.opencode/` and `opencode.json` in your repository root. Nothing is modified globally.

---

## Prerequisites

- [OpenCode](https://opencode.ai) installed (`npm install -g opencode-ai` or see the [install docs](https://opencode.ai/docs))
- [VS Code](https://code.visualstudio.com) with the [AL Language extension](https://marketplace.visualstudio.com/items?itemName=ms-dynamics-smb.al) installed
- PowerShell 5.1 or later (built into Windows)
- An LLM provider configured in OpenCode (Anthropic, Azure OpenAI, etc.)

> **Cursor users:** The AL extension is also detected from `~/.cursor/extensions` automatically.

---

## Setup

### Option A: PowerShell one-liner

Open PowerShell, change to your AL repository root, and run:

```powershell
cd C:\Repos\MyBCProject
irm https://raw.githubusercontent.com/dfredborg/OpenCode-BC/main/Setup-BCOpenCode.ps1 | iex
```

The script downloads everything it needs from GitHub automatically. No clone required.

### Option B: From inside OpenCode

If OpenCode is already running in your project (or any project that has had this setup run before), just type:

```
/setup-bc
```

OpenCode will run the setup script via Bash and report what was installed.

### After setup: commit the generated files

```powershell
git add opencode.json .opencode/
git commit -m "Add OpenCode BC development setup"
```

Once committed, every developer who clones the repository gets the same OpenCode experience with no additional setup. They only need to run the script once to install the AL LSP binaries on their own machine.

---

## What the script does

```
Step 1  Check prerequisites
        Locates the AL Language extension in VS Code / Cursor.
        If not found, warns and skips the LSP step without aborting.

Step 2  Install AL LSP binaries
        Downloads al-lsp-wrapper.exe from the latest release of
        SShadowS/al-lsp-for-agents into %LOCALAPPDATA%\al-lsp\bin.
        Skips the download if already on the latest version.

        Step 3  Copy .opencode/ assets into the target project
        .opencode/skills/compile-alc/SKILL.md
        .opencode/commands/compile-alc.md
        .opencode/commands/review-bc.md
        .opencode/commands/setup-bc.md
        .opencode/scripts/Compile-Alc.ps1

Step 4  Write / merge opencode.json
        Adds or updates the AL LSP and Microsoft Learn MCP entries.
        Deep-merges with any existing config — nothing else is touched.
```

### Files written to your repository

```
your-al-project/
├── opencode.json                        ← LSP + MCP configuration
└── .opencode/
    ├── commands/
    │   ├── compile-alc.md               ← /compile-alc slash command
    │   ├── review-bc.md                 ← /review-bc slash command
    │   └── setup-bc.md                  ← /setup-bc slash command
    ├── scripts/
    │   └── Compile-Alc.ps1              ← AL compiler driver
    └── skills/
        └── compile-alc/
            └── SKILL.md                 ← AI skill definition
```

### Files written to your machine (not the repository)

```
%LOCALAPPDATA%\al-lsp\
├── bin\
│   ├── al-lsp-wrapper.exe               ← AL Language Server bridge
│   └── al-call-hierarchy.exe            ← Call hierarchy support
└── .version                             ← Installed version tag
```

---

## Using OpenCode in your AL project

Open your AL repository in OpenCode:

```powershell
cd C:\Repos\MyBCProject
opencode
```

### AL Language Server

The LSP starts automatically when you open any `.al` or `.dal` file. OpenCode can then use it for code intelligence — the agent gains the same awareness of your codebase that you have in VS Code.

| Operation | Description |
|---|---|
| Go to definition | Jump to where a table, codeunit, enum, or procedure is defined |
| Find references | Find every place a symbol is used across the workspace |
| Hover | See type information and documentation inline |
| Document symbols | List all objects and procedures in a file |
| Call hierarchy | Trace incoming and outgoing calls for any procedure |

### Microsoft Learn documentation

The agent can search `learn.microsoft.com` directly from inside OpenCode. No copy-pasting docs, no context switching.

```
How do I post a sales order programmatically in AL?
```

### Compiling AL

Use the `/compile-alc` command to compile your app:

```
/compile-alc
```

With a specific app (when your repository has multiple):

```
/compile-alc MyBaseApp
```

With a path:

```
/compile-alc apps/MyBaseApp
```

Without analyzers (compiler errors only):

```
/compile-alc --no-analyzers
```

The command uses `alc.exe` from your installed AL Language extension directly. It auto-detects your `app.json`, `.alpackages/`, and any `rules.json` ruleset in the repository.

### Deep code review

Use the `/review-bc` command to run a full codebase audit:

```
/review-bc
```

The agent reads every `.al` file in the repository, cross-references Microsoft Learn documentation, and writes a structured report to `.opencode/reviews/review-YYYY-MM-DD.md` covering:

- **Security** — hardcoded secrets, missing permission checks, unencrypted PII
- **Standard BC coverage** — custom code that duplicates what BC already does natively
- **Performance** — N+1 queries, missing `SetLoadFields`, `CalcFields` in loops
- **Error handling** — swallowed errors, missing `TryFunction`, bad commit strategy
- **Upgrade safety** — missing OnUpgrade codeunits, `ToBeClassified` fields, breaking changes
- **AL code quality** — naming conventions, dead code, missing XML docs, suppressed warnings
- **API design** — missing `APIVersion`/`ODataKeyFields`, over-permissive fields
- **Integration patterns** — missing retry/timeout, secrets in table fields, hardcoded URLs
- **Testing** — flags codebases with no test codeunits
- **Translations** — missing labels, `MaxLength`, comment tags

> **Note:** The review command is pre-configured for a specific project structure (apps: Core, Dataplatform, Documentoutput, ForNav, Integrationer, PaymentManagement). Edit `.opencode/commands/review-bc.md` to match your own app names and codebase path before running it.

### Setting up a new project from inside OpenCode

If you are starting work on a new AL repository, just open it in OpenCode and run:

```
/setup-bc
```

OpenCode will download and run the setup script for you.

---

## Script options

```powershell
# Dry run — shows what would happen without writing anything
.\Setup-BCOpenCode.ps1 -WhatIf

# Overwrite existing .opencode/ assets (e.g. after an update)
.\Setup-BCOpenCode.ps1 -Force

# Skip individual steps
.\Setup-BCOpenCode.ps1 -SkipLsp      # don't install the AL LSP
.\Setup-BCOpenCode.ps1 -SkipMcp      # don't add the Microsoft Learn MCP
.\Setup-BCOpenCode.ps1 -SkipAssets   # don't copy .opencode/ files
```

---

## Updating

Run the script again from your AL project root:

```powershell
irm https://raw.githubusercontent.com/dfredborg/OpenCode-BC/main/Setup-BCOpenCode.ps1 | iex
```

Or from inside OpenCode:

```
/setup-bc
```

The AL LSP binaries are updated automatically if a newer version is available. Use `-Force` to also refresh the `.opencode/` assets.

---

## Repository structure

```
OpenCode-BC/
├── Setup-BCOpenCode.ps1          ← The setup script
├── opencode.json                 ← Config used by this repo itself
├── README.md
└── Compile-alc/
    ├── command/
    │   ├── compile-alc.md        ← /compile-alc command definition
    │   ├── review-bc.md          ← /review-bc command definition
    │   └── setup-bc.md           ← /setup-bc command definition
    ├── scripts/
    │   └── Compile-Alc.ps1       ← AL compiler PowerShell driver
    └── skills/
        └── compile-alc/
            └── SKILL.md          ← compile-alc AI skill definition
```

---

## How the compile-alc skill works

The skill teaches OpenCode how to use `alc.exe` — the compiler that ships with the VS Code AL Language extension — without any external tooling.

1. Locates `alc.exe` from the newest `ms-dynamics-smb.al-*` extension in your VS Code extensions folder
2. Resolves the project directory automatically (walks up from the current directory, scans `app.json` files, prefers non-test apps)
3. Finds `.alpackages/` and `.outFolder/` relative to the repository root
4. Detects any `rules.json` ruleset in the repository
5. Adds standard analyzers: CodeCop, UICop, PerTenantExtensionCop, and LinterCop if present
6. Runs `alc.exe` and reports errors grouped by file with line numbers

The `Compile-Alc.ps1` script is the actual driver. You can also call it directly:

```powershell
.\.opencode\scripts\Compile-Alc.ps1 -AppName MyApp -NoAnalyzers
```

---

## Credits

- [OpenCode](https://opencode.ai) — the AI coding agent
- [SShadowS/al-lsp-for-agents](https://github.com/SShadowS/al-lsp-for-agents) — the AL Language Server wrapper that makes LSP work inside AI agents
- Microsoft — the AL Language extension and `alc.exe` compiler
