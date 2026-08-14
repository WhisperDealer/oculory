---
name: spriggit-deserialize
description: Rebuild a Bethesda plugin (.esp/.esm/.esl) from its Spriggit YAML folder in this SkyrimSE workspace. Use when the user wants to deserialize, re-pack, build, or compile the plugin from the edited YAML.
---

# Spriggit: Deserialize (YAML → plugin)

Rebuild the binary plugin from the edited YAML. Run this after editing records.

## Workspace settings (from config)

- CLI: `$Tools.spriggitCli` from `.claude/config/tools.json` (loaded via
  `.claude/config/tools.ps1`). Run the **modlist-install** skill or edit `tools.json` to repoint it.

## Inputs to collect

1. **YAML folder** (`--InputPath`) — the Spriggit text folder under `src/`, e.g. `./src/MyMod/MyModESP`.
2. **Output plugin** (`--OutputPath`) — the plugin to (re)build, e.g. `MyMod.esp`.

## Steps

1. Confirm the YAML folder exists and contains `spriggit-meta.json`.
2. Run (PowerShell):

```powershell
. ".claude/config/tools.ps1"
& (Assert-Tool $Tools.spriggitCli 'spriggitCli') deserialize `
  --InputPath  "./src/<ModName>/<modFolderName>" `
  --OutputPath "<MyMod.esp>"
```

3. `--PackageName` / `--PackageVersion` are intentionally omitted — Spriggit auto-detects them
   from the folder's `spriggit-meta.json`. Only pass them if asked to override.

## After deserializing — ALWAYS remind

- The rebuilt `.esp/.esm` is a **build artifact** and is gitignored (commit the YAML, not the binary).
- **Load the plugin in xEdit and/or the Creation Kit to verify it before shipping.** Deserialize
  succeeding does not guarantee the records are correct.
