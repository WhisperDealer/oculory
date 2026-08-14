---
name: pex-decompile
description: Decompile compiled Papyrus bytecode (.pex) back into readable source (.psc) using Champollion. Use after extracting .pex files from a .bsa or from loose Scripts, when the user wants editable Papyrus source.
---

# Decompile .pex → .psc (Champollion)

Turn compiled Papyrus bytecode into human-readable `.psc` source you can edit, then recompile.

## Tool (from config)

- `$Tools.champollion` — from `.claude/config/tools.json` (loaded via `.claude/config/tools.ps1`).
  Run the **modlist-install** skill to point it at a modlist's copy, or edit `tools.json`.
- Usage: `Champollion [options] <pex file or folder>`
  - `-p, --psc <dir>` output directory for decompiled `.psc`
  - `-a, --asm <file>` also output assembly; `-c` put assembly in `.psc` comments
  - `-t, --threaded` parallel decompile (use for whole folders)

## Steps

1. Decompile a single file or an entire folder (Champollion recurses):

```powershell
. ".claude/config/tools.ps1"
& (Assert-Tool $Tools.champollion 'champollion') `
  -t -p "<outputDir>" "<file.pex or folder>"
```

2. Choose the output dir by intent:
   - Scripts **you will edit / own** → `src/<ModName>/Scripts/source/` (committed source of truth).
   - **Reference-only** lookups → `reference/<name>/` (gitignored).

## CRITICAL: decompiled source is a reconstruction

Champollion output compiles in most cases but is **not** the original author's source. Expect:
- auto-generated temporary variable names and reconstructed `If/Else`/`GoTo` control flow,
- occasional missing or mangled property/auto-var names,
- comments and original formatting are gone.

Always **recompile** (`papyrus-compile`) and **test in-game** before trusting decompiled scripts.
For non-trivial cleanup and compile-error fixing, hand off to the **papyrus-script-engineer** subagent.

## Notes

- Commit the `.psc` source in `src/<ModName>/Scripts/source/`. `.pex` are gitignored by default;
  a plugin that ships scripts opts its `Scripts/compiled/` folder back in (see `.gitignore`).
- If you only have a `.bsa`/`.ba2`, run **bsa-extract** first to get the `.pex` files.
