# Bootstrapping this workspace without cloning

**You probably don't need this file.** This repository *is* the template: click **Use this
template** on GitHub, or `git clone` it, and you have the whole workspace — skills, subagents,
config template, build pipeline, CI, and a working example mod. Then run `/mod-new-plugin` to
scaffold your own plugin and delete `src/ExampleMod/`.

This file is the fallback for the cases where copying the repo isn't an option:

- you're adding the workspace to an **existing** mod project that already has its own history;
- you want the conventions but not the CI, the FOMOD build, or the example mod;
- you're targeting a **different Bethesda game** (Fallout 4, Starfield, Oblivion) and want to
  rebuild the scaffold from first principles rather than editing SkyrimSE defaults out.

Copy everything inside the fenced block below into a Claude Code session opened in your target
folder. It recreates the core scaffold — config-driven tool paths, `.spriggit`, `.gitignore`,
folder layout, `README.md` and a `CLAUDE.md` template — with no project-specific content.

**What the prompt below does NOT cover**, because it predates them and they are easier to copy than
to describe: `build/build.ps1` + `build/manifest.json` (the manifest-driven FOMOD build),
`build/Test-RecordYaml.ps1` and its `PostToolUse` hook, the `.github/` workflows and composite
action, and `arch-docs/skyrim-record-patterns.md`. If you want those, take them from this repo
directly — they are game-agnostic apart from the Spriggit package name.

---

````markdown
You are setting up a **reusable Bethesda mod-development workspace** that uses **Spriggit** to
convert plugin files (.esp/.esm/.esl) to/from human-editable YAML kept under git, plus a
command-line **Papyrus toolchain** (extract → decompile → compile → package). Bootstrap this folder
as a clean, version-controlled workspace following the conventions below. Ask me the Step 0
questions first, then create the scaffold. **Plan the scaffold, then create it; do not generate any
project-specific records until I ask.**

## Step 0 — Ask me before scaffolding
1. **Game release?** SkyrimSE (default), SkyrimLE, SkyrimVR, Fallout4, Starfield, Oblivion.
2. **Spriggit version** installed (e.g. 0.40.0), and CLI or GUI.
3. **First plugin** I'll work on (filename), or "none yet". Is it **ESL/`Small`-flagged**
   (FormID range limited to `0x800–0xFFF`)?
4. Do I use a **Wabbajack modlist** (which ships the game copy, Creation Kit, Papyrus compiler, xEdit)
   or plain tool installs? If a modlist, where is it installed?

Map the game release to the Spriggit package/source:
- Skyrim* → `Spriggit.Yaml.Skyrim` · Fallout4 → `Spriggit.Yaml.Fallout4`
- Starfield → `Spriggit.Yaml.Starfield` · Oblivion → `Spriggit.Yaml.Oblivion`

Verify exact package names and CLI flags against my installed Spriggit version rather than assuming.

## Step 1 — Config-driven tool paths (NO hardcoded paths anywhere)

Every tool path lives in **one** gitignored file so nothing machine-specific leaks into skills or docs.

### `.claude/config/tools.example.json` (committed template)
Documented keys with **generic placeholder** paths (never a real username). Cover at least:
`spriggitCli`, `bsab` (BSA Browser), `champollion`, `papyrusCompiler`, `creationKit`, `gameRoot`,
`gameDataDir`, `gameSourceScripts`, `papyrusFlags`, `sseedit` + `sseeditQuickAutoClean` +
`xeditScriptsDir`, `bsarch`, `modlistRoot`, `modlistsRoot`, an `importDirs` array (extra Papyrus
`Source/Scripts` dirs), and a `spriggit` object `{ gameRelease, packageName, packageVersion }`.
Give each key a sibling `_<key>_help` string.

### `.claude/config/tools.json` (gitignored, per-machine)
A copy of the template with my real paths filled in. **Add `/.claude/config/tools.json` to
`.gitignore`.**

### `.claude/config/tools.ps1` (committed loader)
Dot-sourced by skills; exposes `$Tools` (parsed JSON) and an `Assert-Tool $path 'name'` guard that
throws on a missing/empty path. Skills resolve every tool through `$Tools.*` — **changing a path
means editing `tools.json`, never a skill.**

## Step 2 — Workspace scaffold

### `.spriggit` (root config)
```json
{
  "PackageName": "<Spriggit.Yaml.* for my game>",
  "Version": "<my spriggit version>",
  "Source": "<Spriggit.Yaml.* for my game>",
  "Release": "<my game release>",
  "KnownMasters": []
}
```

### `.gitignore`
Commit only the YAML I author + Papyrus source + tooling. Ignore everything large, binary, derived,
machine-specific, or third-party:
```
# Editor / OS
.vscode/
.venv/
.DS_Store
Thumbs.db

# Machine-specific tool paths
/.claude/config/tools.json

# Wabbajack modlist installed into the repo — hundreds of GB, third-party
/modlist/
/downloads/

# Binary plugins & archives — never commit; deserialize/extract to rebuild
*.esp
*.esm
*.esl
*.bsa
*.ba2

# Papyrus & packaging build artifacts — derivable
# Compiled Papyrus is ignored BY DEFAULT. A plugin that ships scripts opts its compiled
# folder back in with a "!src/<ModName>/Scripts/compiled/" exception, because cloud CI cannot
# run the Creation Kit compiler and must package the committed .pex as-is.
*.pex
/dist/

# Reference decompiles — third-party/vanilla, serialized for FormKey LOOKUP only
/reference/
```
Explain to me that **my own mod's** YAML and `.psc` source ARE committed; only third-party/vanilla
reference decompiles, modlists, and build artifacts are ignored. Ask which folders are reference-only.

### `.editorconfig`
Enforce **LF** line endings and UTF-8 for `*.yaml`/`*.psc` (Spriggit YAML uses LF).

### Folder layout (document; create on demand)
Every mod lives under a single top-level `src/` folder, one subfolder per mod, so a repo can carry
a main plugin and its compatibility patches side by side without cluttering the root:
```
src/<ModName>/<modFolderName>/           # your plugin as YAML — COMMITTED (source of truth)
  RecordData.yaml                        # header: ModKey, GameRelease, masters, author, Stats.Version
  spriggit-meta.json                     # { PackageName, Version, Release, ModKey }
  <RecordType>/                          # one folder per record type (Activators, MagicEffects, …)
    <EditorID> - <FormID>_<PluginName>.esp.yaml   # naming fixed by Spriggit
src/<ModName>/Scripts/source/*.psc       # your Papyrus source — COMMITTED
src/<ModName>/Scripts/compiled/*.pex     # build output — COMMITTED via a .gitignore exception
reference/<name>/                        # third-party/vanilla decompiles — gitignored, lookup only
dist/<ModName>/                          # packaged loose mod for MO2 testing — gitignored
```

### `README.md`
Document the Spriggit round-trip, folder layout, naming convention, FormKey discipline, the
config-driven tool setup, and the serialize/deserialize commands (Step 4).

### `CLAUDE.md` (AI-guidance template — fill placeholders as the project grows)
Create with these sections, `<...>` placeholders I fill per project:
```markdown
# <Mod Name> — Spriggit Workspace Guide

## What this is
A Spriggit YAML workspace for <game release>. Edit the YAML, never the binary plugin.

## Tooling config (no hardcoded paths)
All tool paths live in .claude/config/tools.json (gitignored; template at tools.example.json),
loaded via .claude/config/tools.ps1 ($Tools + Assert-Tool). Never hardcode a path in a skill.

## Workflow (round-trip)
Serialize (plugin → YAML) / deserialize (YAML → plugin): see README. Verify in xEdit/CK before shipping.

## Folder map
<each mod folder and the plugin it represents; mark reference-only (gitignored) ones>

## Architecture / core records
<the central records this mod revolves around, their FormKeys, and cross-record invariants —
parallel arrays that must stay the same length, linked spell/MGEF/perk sets, index-based logic>

## FormKey discipline
- New records use this plugin's name as the FormKey suffix; overrides keep the original suffix.
- Allocate contiguous FormKey blocks per feature for readable diffs; record the next free block.
- ALWAYS grep the whole workspace (yours + reference/) for a hex FormID before assigning it.
- ESL/Small plugins are limited to 0x800–0xFFF — confirm before exceeding.

## Record patterns / templates
<paste a known-good record set as the canonical template once you have one>

## Papyrus toolchain
<per-step tool table keyed to $Tools.*; reference-script table (read source before authoring);
per-project import dirs table for importDirs>

## Useful FormKey constants
<table of frequently referenced vanilla FormKeys for this game/mod>

## Gotchas
<compiled-script behavior, editor quirks, index-based logic that doesn't auto-extend, anything
that bit you — record it here>
```

### Skills & subagents (if I'm copying this reference workspace)
This workspace ships Claude Code helpers under `.claude/` (committed, shared). Preserve them:
- **Skills:** `modlist-install`, `mod-new-plugin`, `spriggit-serialize`, `spriggit-deserialize`,
  `spriggit-decompile-reference`, `formkey-check`, `bsa-extract`, `pex-decompile`,
  `papyrus-compile`, `package-mod`, `mod-deploy`, `github-release`.
- **Subagents:** `spriggit-record-editor` (author YAML records), `spriggit-formkey-auditor`
  (read-only collision/invariant audit), `papyrus-script-engineer` (decompiled-source cleanup &
  compile-error fixing).

If bootstrapping from scratch without them, at minimum document the equivalent CLI commands (Step 4).

## Step 3 — git init
`git init`; create an initial commit with the scaffold only. **Never commit binary plugins, archives,
reference decompiles, modlists, or `tools.json`.** Before committing, scan staged content for
personal info (usernames, emails, `C:/Users/<name>` paths) and confirm none is present.

## Step 4 — Spriggit & Papyrus commands (put in README; run on request)
Resolve paths via `. ".claude/config/tools.ps1"`; verify flags against my installed version.

**Serialize (plugin → YAML):**
`Spriggit.CLI.exe serialize --InputPath "<MyMod.esp>" --OutputPath "./<modFolderName>" --GameRelease <release> --PackageName <Spriggit.Yaml.*> --PackageVersion <ver>`

**Deserialize (YAML → plugin):**
`Spriggit.CLI.exe deserialize --InputPath "./<modFolderName>" --OutputPath "<MyMod.esp>"`

**Reference masters (vanilla/other mods, lookup only):** serialize into the gitignored `reference/<name>/`.
Note: some masters contain records with a compression Mutagen can't re-pack; if the built-in
round-trip sanity check throws on one record, the written YAML is still complete for FormKey lookups
(you never deserialize a reference back into a plugin).

**Papyrus loop:** `bsa-extract` (.pex from .bsa) → `pex-decompile` (.pex → .psc via Champollion) →
edit → `papyrus-compile` (.psc → .pex; imports = your source + `$Tools.gameSourceScripts` +
`$Tools.importDirs`; flags = `$Tools.papyrusFlags`) → `package-mod` (assemble `dist/<ModName>/`).
Prefer a mod's **original shipped `.psc`** over a decompile when it ships source.

## Step 5 — Summarize
Tell me what you created, which folders are committed vs ignored, the exact serialize/deserialize
commands for my setup, which `tools.json` keys still need filling, and the next action (decompile my
first plugin, or serialize a reference master).

## Hard rules
- No hardcoded tool paths — everything flows through `.claude/config/tools.json`.
- Never commit binary plugins, archives, reference decompiles, modlists, build artifacts, or personal info.
- Decompiled `.psc` is a reconstruction — recompile and test in-game; a clean compile is not proof.
- Verify Spriggit package names and CLI flags against my installed version rather than assuming.
````
