---
name: papyrus-compile
description: Compile Papyrus source (.psc) into bytecode (.pex) using the Creation Kit's command-line PapyrusCompiler.exe. Use when the user wants to build/compile scripts for SkyrimSE without opening the Creation Kit GUI.
---

# Compile .psc → .pex (PapyrusCompiler.exe)

Compile Papyrus source to the `.pex` the game loads — from the command line, no CK GUI needed.

## Tool (from config)

- `$Tools.papyrusCompiler` — from `.claude/config/tools.json` (loaded via `.claude/config/tools.ps1`).
  With a Wabbajack modlist this is `<gameRoot>/Papyrus Compiler/PapyrusCompiler.exe`; run the
  **modlist-install** skill to point it at the modlist, or edit `tools.json`.
- Usage: `PapyrusCompiler <object|folder> [args]`
  - `-all|a` compile every `.psc` in the folder (treat the positional arg as the folder)
  - `-import|i="<dir;dir;…>"` import directories (where referenced scripts' source lives)
  - `-output|o="<dir>"` output directory for `.pex`
  - `-flags|f="<file>"` user-flags file (SkyrimSE: `TESV_Papyrus_Flags.flg`)
  - `-optimize|op`, `-debug|d`, `-quiet|q`

## ONE-TIME setup (required before first compile)

The base-game Papyrus **source** ships zipped. Extract it once so its `.psc` files (and the flags
file) are available as imports:

- Extract `<gameDataDir>/Scripts.zip` → `<gameDataDir>/Source/Scripts/` — i.e. extract
  `$Tools.gameDataDir + '/Scripts.zip'` into `$Tools.gameSourceScripts`.
- This yields the vanilla `*.psc` imports **and** `TESV_Papyrus_Flags.flg`.
- Many Wabbajack modlists already ship loose source — check `$Tools.gameSourceScripts` first; if
  it exists and has `.psc` files, skip this.

`$Tools.gameSourceScripts` is the `GAME_SOURCE` import dir.

## Steps

1. Compile all source in `src/<ModName>/Scripts/source/` into `src/<ModName>/Scripts/compiled/`. Paths come from the config;
   `$Tools.importDirs` (extra API source dirs) are appended automatically:

```powershell
. ".claude/config/tools.ps1"
$compiler = Assert-Tool $Tools.papyrusCompiler 'papyrusCompiler'
$imports  = @('src/<ModName>/Scripts/source', $Tools.gameSourceScripts) + @($Tools.importDirs)
& $compiler "src/<ModName>/Scripts/source" -all `
  -f="$($Tools.papyrusFlags)" `
  -i="$($imports -join ';')" `
  -o="src/<ModName>/Scripts/compiled" `
  -optimize
```

2. **Surface compiler output verbatim** — report every error/warning line; do not summarize away
   failures. A nonzero/`failed` result means no usable `.pex`.

## Per-project imports (the common failure)

If compilation reports an **unknown type / unresolved script** (e.g. `SKSE`, `UI`, `SkyUI`,
`MCM`, or another mod's script), that API's **source `.psc`** must be on the import path. Append
it to `-i` with `;` separators. Persist it by adding the dir to **`importDirs`** in
`.claude/config/tools.json` so the build block above picks it up on every compile, e.g.:

```jsonc
"importDirs": ["C:/path/to/SKSE/Source/Scripts", "C:/path/to/SkyUI/Source/Scripts"]
```

Put `src/<ModName>/Scripts/source` first so your own scripts resolve each other (the build block already does).
Also note the import in `CLAUDE.md`'s per-project imports table once known.

## Notes

- `.pex` output is gitignored (build artifact). Commit only the `.psc` source.
- For decompiled scripts that won't compile cleanly, use the **papyrus-script-engineer** subagent.
- After a successful compile, use **package-mod** to assemble the installable mod folder.
