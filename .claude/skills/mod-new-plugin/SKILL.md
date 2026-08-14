---
name: mod-new-plugin
description: Scaffold a brand-new plugin in this workspace — a Spriggit YAML folder with a correct header and a build/manifest.json entry (plus a FOMOD only if the install has options) — so it is buildable and CI-packaged from the first commit. Use when the user wants to start a new mod, add a second plugin, or add a compatibility patch to an existing mod.
---

# Scaffold a new plugin

Create everything a new plugin needs to be built by `build/build.ps1` and packaged by CI, **without
serializing an existing `.esp`**. Use this when authoring a plugin from scratch; use
**spriggit-serialize** instead when importing one that already exists as a binary.

## Inputs to collect

Ask for anything not supplied. Do **not** guess these — a wrong `ModKey` or master list means the
plugin builds and then misbehaves in-game, which is expensive to discover.

1. **Plugin filename** — e.g. `MyMod.esp`. This becomes the `ModKey` and must match exactly,
   including case and extension, everywhere it appears.
2. **Folder name** — conventionally `src/<ModName>/<ModName>ESP/`. Mod content **always** goes under
   `src/`; never scaffold a mod folder at the repo root. See the layout below.
3. **ESL-flagged?** Default **yes** for a small mod or a patch (`Flags: [Small]`), which restricts
   FormIDs to `0x800–0xFFF`. Say so explicitly when confirming, because it constrains every FormID
   allocated afterwards.
4. **Masters**, in load order. `Skyrim.esm` at minimum. A patch also masters onto every mod whose
   records it overrides — list them in the order they load.
5. **Does it ship Papyrus scripts?** If yes, scaffold `Scripts/source/` and `Scripts/compiled/` and
   add the `.gitignore` exception (see step 4).
6. **Its own release archive, or a plugin inside an existing one?** A compatibility patch usually
   belongs in an existing release; a new mod gets its own.
7. **Does the install have anything to ask?** Optional or alternative plugins, optional assets, a
   requirement the user must read. Do **not** ask this as an open question — infer it from what the
   release ships and confirm. A single `.esp` with no variants answers *no*, and gets **no FOMOD**
   (step 5).

## Layout to create

```
src/<ModName>/
  <ModName>ESP/
    RecordData.yaml        # the plugin header
    spriggit-meta.json     # { PackageName, Version, Release, ModKey }
  Scripts/source/          # .psc — committed        (only if it ships scripts)
  Scripts/compiled/        # .pex — committed        (only if it ships scripts)
```

Record folders (`Weapons/`, `Quests/`, `MagicEffects/`, …) are **not** pre-created — Spriggit adds
them as records appear. Do not scaffold empty ones.

## Steps

1. **Write `src/<ModName>/<ModName>ESP/RecordData.yaml`.** Fill `ModKey`, the ESL flag, and the masters from the
   answers above. Set a real `Stats.Version` — SSE Wrye Bash rejects `0.85`-style versions, so use
   `1.0` or similar:

   ```yaml
   SpriggitSource:
     PackageName: Spriggit.Yaml.Skyrim
     Version: 0.40
   ModKey: <MyMod.esp>
   GameRelease: SkyrimSE
   ModHeader:
     Flags:
     - Small                      # omit this list entirely if not ESL-flagged
     Author: <author>
     Stats:
       Version: 1.0
     MasterReferences:
     - Master: Skyrim.esm
       FileSize: 0
     INTV: 1
   ```

2. **Write `src/<ModName>/<ModName>ESP/spriggit-meta.json`** — values must match `.spriggit` in the repo root and
   the `ModKey` above. `build/build.ps1` refuses to build a folder without this file:

   ```json
   {
     "PackageName": "Spriggit.Yaml.Skyrim",
     "Version": "0.40.0",
     "Release": "SkyrimSE",
     "ModKey": "<MyMod.esp>"
   }
   ```

3. **Add it to `build/manifest.json`** — the single source of truth for what CI builds. Either a new
   release object, or a new entry in an existing release's `plugins` array:

   ```jsonc
   {
     "name":        "<Release Name>",          // must match build/staging/<name>/ exactly
     "archiveName": "<Release Name>",          // -> build/dist/<archiveName>.7z
     "scripts":     { "from": "src/<ModName>/Scripts/compiled", "to": "Scripts" },  // omit if no scripts
     "fomod":       false,                     // see step 5 — omit only when the install has options
     "plugins": [
       { "yamlSource": "src/<ModName>/<ModName>ESP", "dest": "<MyMod.esp>" }
     ]
   }
   ```

   `dest` is the path **inside the release tree**. When the release *has* a FOMOD, `dest` must also
   match the `source=` attribute in that release's `fomod/ModuleConfig.xml` — `build/build.ps1
   -CheckFomod` fails the build otherwise. Releases with `"fomod": false` are skipped by that check.

4. **If it ships scripts, add the `.gitignore` exception.** `.pex` are ignored by default; a plugin
   that ships scripts must opt its compiled folder back in, because CI cannot run the Creation Kit
   compiler and packages the committed `.pex` as-is:

   ```gitignore
   !src/<ModName>/Scripts/compiled/
   !src/<ModName>/Scripts/compiled/*.pex
   ```

5. **Create a FOMOD only if the install has something to ask.** The default for a new release is
   **no FOMOD**: set `"fomod": false` on it in `build/manifest.json` and ship a plain archive — the
   `.esp` (and `Scripts/`) at the root. Every mod manager installs that correctly with no wizard,
   and there is nothing for the user to get wrong. Build one **only** when at least one holds:

   - the release ships **optional or alternative plugins** the user picks between — a patch per
     third-party mod, a "lite" variant, mutually exclusive presets;
   - it ships **optional assets** — an alternative texture/mesh set, an optional folder;
   - the install carries a **requirement or warning the user must read** at install time.

   **A single `.esp` with no variants meets none of these.** Do not scaffold a FOMOD for it and do
   not offer the user the choice — an installer with one always-selected option is pure friction.
   `build.ps1` *refuses* to build if a `fomod/` still exists for a release marked `"fomod": false`,
   so the manifest and the tree cannot silently disagree.

   **If it does need one**, create the stub at `build/staging/<Release Name>/fomod/` — `info.xml`
   and `ModuleConfig.xml`. This is the one part of `build/staging/` that is committed source
   (everything else there is derived and regenerated by `build.ps1`, and stays gitignored via the
   blanket `*.esp`/`*.pex` rules). Copy the shape from an existing release and keep it minimal;
   `fomod/` must sit at the **archive root**, which `build.ps1` handles. Files that install
   unconditionally go in `<requiredInstallFiles>`, the actual choices in `<installSteps>`:

   ```xml
   <requiredInstallFiles>
       <file source="<MyMod.esp>" destination="<MyMod.esp>"/>
       <folder source="Scripts" destination="Scripts"/>
   </requiredInstallFiles>
   ```

   **If the release ships an installer image**, follow the confirmed-working recipe in CLAUDE.md's
   "FOMOD images that actually render in MO2" gotcha — archive-root-relative `path=` *including*
   the `fomod` prefix, backslashes, an `<installSteps>` block even with no real choices, and a
   baseline (not progressive) JPEG. Copy `build/fomod-example/ModuleConfig.xml` — kept in the repo
   as reference, belonging to no release — verbatim and edit the deltas. A wrong image setup still builds and still passes `-CheckFomod`;
   it just silently renders nothing, so it costs a full install cycle to spot.

6. **Verify before reporting success.** Both must pass:

   ```powershell
   pwsh build/build.ps1 -CheckFomod     # manifest <-> ModuleConfig.xml parity
   pwsh build/build.ps1                 # full build -> build/dist/<archiveName>.7z
   ```

   A plugin with no records yet still deserializes to a valid empty `.esp`, so this is a real check
   that the scaffold is wired up — run it now rather than discovering a typo three records later.

7. **Report** the created files, the FormID range available (`0x800–0xFFF` if ESL), and the next
   step: add records with the **spriggit-record-editor** subagent, then audit with
   **formkey-check** / the **spriggit-formkey-auditor** subagent.

## Notes

- Record `<ModName>` and its FormKey allocations in `CLAUDE.md` as you go — that file is what future
  sessions read to avoid reassigning a FormID.
- Read `arch-docs/skyrim-record-patterns.md` before authoring the first mechanic; it documents the
  record shapes that work in-game and the ones that silently don't.
- If the plugin overrides another mod's records, the override records keep the **defining master's**
  FormKey suffix. Only genuinely new records use `<hex>:<MyMod.esp>`.
