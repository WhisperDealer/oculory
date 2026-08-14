---
name: spriggit-decompile-reference
description: Serialize a vanilla or third-party SkyrimSE plugin into the gitignored reference/ folder for FormKey lookups only. Use when the user wants to decompile Skyrim.esm, Update.esm, a DLC, or another mod purely for reference/lookup (not to edit or commit).
---

# Spriggit: Decompile a reference master (lookup only)

Serialize a master you do **not** own (vanilla game files, DLC, or another author's mod) into
the gitignored `reference/<name>/` folder so you can grep it for FormKeys without committing it.

## Workspace settings (from config)

Paths and Spriggit settings come from `.claude/config/tools.json` (loaded via
`.claude/config/tools.ps1`): `$Tools.spriggitCli`, and `$Tools.spriggit.{gameRelease,packageName,packageVersion}`
(defaults `SkyrimSE` / `Spriggit.Yaml.Skyrim` / `0.40.0`).

## Inputs to collect

1. **Plugin path** (`--InputPath`) — e.g. `Skyrim.esm`.
2. **Reference name** — a short folder name under `reference/`, e.g. `skyrimBaseGame`,
   `skyrimUpdate`, `dawnguard`, or the source mod name.

## Steps

1. Run (PowerShell):

```powershell
. ".claude/config/tools.ps1"
& (Assert-Tool $Tools.spriggitCli 'spriggitCli') serialize `
  --InputPath   "<Skyrim.esm>" `
  --OutputPath  "./reference/<name>" `
  --GameRelease $Tools.spriggit.gameRelease `
  --PackageName $Tools.spriggit.packageName `
  --PackageVersion $Tools.spriggit.packageVersion
```

2. Confirm `reference/<name>/` is covered by `.gitignore` (the blanket `/reference/` rule
   already handles it). **These decompiles are never committed** — they are large and fully
   regenerable from the local game/mod files.
3. Add (or remind the user to add) a folder-map entry in `CLAUDE.md` marking
   `reference/<name>/` as reference-only (gitignored), with a note on what plugin it represents.

## Why reference decompiles are separated

They exist solely for **FormKey discipline** — looking up a vanilla record's FormKey before you
reference it, and checking for collisions. Use the **formkey-check** skill to search across both
your own YAML and these reference folders.
