---
description: Set up OpenCode for Business Central AL development in this repository
---

Set up this repository for Business Central AL development with OpenCode.

Run the following PowerShell command using the Bash tool:

```bash
pwsh -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/dfredborg/OpenCode-BC/main/Setup-BCOpenCode.ps1 | iex"
```

This will:
1. Check that the AL Language VS Code extension is installed
2. Download and install the AL LSP wrapper (go-to-definition, find references, hover, call hierarchy)
3. Copy the compile-alc skill, /compile-alc command, and Compile-Alc.ps1 script into .opencode/
4. Write or merge opencode.json with the AL LSP and Microsoft Learn MCP configuration

After setup completes, report what was installed and remind the user to:
- Commit `opencode.json` and `.opencode/` to the repository
- Use `/compile-alc` to compile their AL app
- Open any `.al` file to activate the language server
