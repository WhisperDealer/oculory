# `<Mod Name>` — Spriggit Workspace Guide

> **This file is a template.** It ships filled in for the bundled `ExampleMod` so you can see the
> shape of a real entry. Replace the mod-specific sections with your own as your project grows —
> everything above *Your mod* is generic and worth keeping as-is.
>
> **This file is the most valuable thing in the repo.** It is what a future session reads instead of
> re-deriving your conventions from scratch. When you learn something the hard way — a FormID
> allocation, a record shape that didn't work, a compile import you needed — write it here.

## What this is

A Spriggit YAML workspace for **SkyrimSE**. Plugins are decompiled to YAML, edited as text, and
re-packed to `.esp`/`.esm`. **Never hand-edit binary plugins — edit the YAML.**

- Spriggit package/source: `Spriggit.Yaml.Skyrim`
- Spriggit CLI version: **`0.40.0` — deliberately pinned, do not upgrade** (see below).
- CLI path + all tool paths: `.claude/config/tools.json` (gitignored; see Tooling config below).

> **Why 0.40.0 is pinned.** Spriggit **0.41.0 silently corrupts leveled-list entries that carry COED
> owner ExtraData**, verified 2026-07-31 and reverted. Its deserializer throws a
> `NullReferenceException` on the 0.40 shape (`MutagenObjectType: NoOwner` + `RawOwnerData`), and its
> serializer rewrites that as `UntypedOwner` + FormKeys while **dropping the next entry's `Data:`
> block** — an entry vanishes from the built plugin with no error. There is no YAML workaround: the
> `0xFFFFFFFF` "no variable" sentinel cannot survive FormKey encoding and returns as `0x04FFFFFF`, so
> even a hand-corrected record builds a different plugin.
>
> `ExampleMod` has no such record, so 0.41.0 happened to build it byte-identically — **a clean build
> here proves nothing** about a mod that does. Before ever unpinning: confirm the bug is fixed
> upstream, grep the tracked YAML for `MutagenObjectType: (No|Untyped|Typed)Owner` and
> `RawOwnerData`, and prove the upgrade by rebuilding every `.esp` and comparing SHA-256 against the
> previous release's. 0.41.0 also requires the **.NET 10 SDK** (its serializer package ships
> `tools/net10.0` only), failing with a `DotnetToolSettings.xml was not found` error that never
> mentions .NET.

## Tooling config (no hardcoded paths)

All tool paths and per-machine settings live in **`.claude/config/tools.json`** (gitignored;
template at `tools.example.json`). Skills load it via `.claude/config/tools.ps1`, which exposes
`$Tools` (e.g. `$Tools.spriggitCli`, `$Tools.papyrusCompiler`, `$Tools.creationKit`,
`$Tools.gameSourceScripts`) and an `Assert-Tool` guard. **Never reintroduce a hardcoded path into a
skill — change the config instead.**

- **Modlists:** a Wabbajack `.wabbajack` list installs a full MO2 instance (game copy + mods +
  tools, often the **Creation Kit** and Papyrus compiler) that can be hundreds of GB. It is
  gitignored (`/modlist/`, `/downloads/`). Run the **`modlist-install`** skill to install one and
  auto-discover its tool paths into `tools.json`.
- Without a modlist, fill `tools.json` by hand from `tools.example.json`.

## Workflow (round-trip)

```
.esp/.esm  ──serialize──►  YAML (committed)  ──deserialize──►  .esp/.esm
                 ▲                                                  │
                 └──────────── you edit the YAML ◄──────────────────┘
```

Serialize/deserialize commands: see `README.md`. After editing YAML, deserialize and load the plugin
in xEdit/CK to verify before shipping.

## Folder map

```
src/                       # EVERY mod lives here — one folder per mod, add as many as you like
  <ModName>/
    <ModName>ESP/          # Spriggit YAML — COMMITTED, source of truth
    Scripts/source/*.psc   # Papyrus source — COMMITTED
    Scripts/compiled/*.pex # COMMITTED via a .gitignore exception (CI can't compile Papyrus)
build/                     # build.ps1 + manifest.json + committed FOMOD trees
arch-docs/                 # design docs, record-pattern guide, generated build report
reference/                 # gitignored — vanilla/third-party decompiles, LOOKUP ONLY
modlist/                   # gitignored — an installed MO2 instance, hundreds of GB
```

`src/` is the only place mod content goes. A repo can hold several mods side by side — a main
plugin and its compatibility patches, say — each its own `src/<ModName>/` folder with its own
`build/manifest.json` release entry. Only `src/`, `build/`, `arch-docs/`, `.claude/` and the root
configs are committed.

## Guardrails — how to work in this repo

These are distilled from real failures in this workspace's lineage. They cost test cycles to learn.

1. **Ground-truth before claiming.** Do not conclude a patch is or isn't needed, or that a record
   does what its name suggests, from the name alone. Read the serialized record, trace the
   FormKeys, and **show the evidence alongside the verdict**. If a mechanic depends on a third-party
   mod's compiled script, read that script's decompiled source — data-driven parts extend to your
   records, hardcoded index checks do not.
2. **Prefer a proven archetype to an invented mechanism.** Read
   `arch-docs/skyrim-record-patterns.md` first. Skyrim fails silently: an inert record produces no
   error, so an invented mechanism costs a full build-deploy-launch-test cycle to disprove.
3. **Copy records verbatim; never retype hex.** When basing a record on an existing one, copy the
   file and edit the fields that differ. Hand-transcribing `Data:` blobs has produced odd-length hex
   that fails the build, and dropped array entries that fail silently. Prefer a script over
   retyping. Re-check array lengths after any edit.
4. **Ask for paths; don't hunt for them.** Install locations, modlist names, MO2 folders and mod
   names live in `tools.json` or in the user's head. Read the config or ask — filesystem-searching
   for them wastes time and lands on the wrong candidate.
5. **Verify the deploy target before blaming the records.** A mod in a wrongly-named MO2 folder is
   invisible; the game runs fine and the change simply isn't there. The `mod-deploy` skill checks
   this. Rule out "never loaded" before debugging "loaded but broken".
6. **A clean build is not a working mod.** Deserialize, xEdit and the Papyrus compiler all passing
   proves it *builds*. Only launching the game proves it *runs*. Say which of the two you have
   actually established.
7. **Recompile and re-commit `.pex` whenever a `.psc` changes.** CI cannot run the Creation Kit
   compiler. `build/build.ps1` fails on a *missing* `.pex` but cannot detect a *stale* one.
8. **PowerShell 5.1 is the target** for build scripts and skills: `Set-StrictMode` is on, there is
   no `&&`/`||`, no ternary, no null-coalescing, and no built-in YAML parser. Write `-Encoding utf8`
   explicitly when a file will be read by other tools.

## FormKey discipline

- New records use this plugin's name as the FormKey suffix: `<hex>:<YourMod>.esp`.
  Records that **override** a base/third-party record keep the original suffix
  (e.g. `09BC43:Skyrim.esm`) — that is how you tell at a glance which records you invented.
- **ESL (`Small`) plugins are constrained to FormIDs `0x800–0xFFF`.** Confirm with the user before
  exceeding; there is headroom but it is finite.
- Allocate a **contiguous block per feature** for readable diffs.
- ALWAYS grep the whole workspace (your plugin folders + `reference/`) for a hex FormID before
  assigning it — use the `formkey-check` skill.

## Papyrus toolchain

Scripts go through extract → decompile → edit → compile → package. Use the matching skills; the
`papyrus-script-engineer` subagent handles decompiled-source cleanup and compile-error fixing.

**Tool paths:** all resolved from `.claude/config/tools.json` — do not hardcode.

| Step | Tool | Config key |
|------|------|------------|
| Extract `.bsa`/`.ba2` | `bsab.exe` | `$Tools.bsab` |
| Decompile `.pex`→`.psc` | `Champollion.exe` | `$Tools.champollion` |
| Compile `.psc`→`.pex` | `PapyrusCompiler.exe` | `$Tools.papyrusCompiler` |
| Open Creation Kit | `CreationKit.exe` | `$Tools.creationKit` |

**Compiler imports:** base-game source = `$Tools.gameSourceScripts` (extract
`<gameDataDir>/Scripts.zip` once, or use what the modlist ships). Flags file: `$Tools.papyrusFlags`.

**Per-project import dirs** — persist in `tools.json`'s `importDirs` array (the `papyrus-compile`
skill appends them to `-i`). Record each one here as you discover it:

| API / framework | Source `.psc` dir |
|-----------------|-------------------|
| _(base only)_ | `ExampleMod`'s script compiles against base-game source only. Add SKSE/SkyUI/MCM/PapyrusUtil dirs here when a script needs them. |

**Testing:** MO2 modlists under `$Tools.modlistsRoot`, or a Wabbajack instance at
`$Tools.modlistRoot`. Use the `mod-deploy` skill rather than copying by hand.

---

# Your mod

> Everything below is `ExampleMod`'s entry, kept as a worked example. Replace it with your own.

## Architecture / core records

`ExampleMod.esp` — ESL (`Small`), masters: `Skyrim.esm` only. It exists to demonstrate all four
layers of the pipeline in as few records as possible.

| FormKey | Type | EditorID | Purpose |
|---|---|---|---|
| `000800:ExampleMod.esp` | Weapon | `ExampleMod_ExampleBlade` | **New record.** Derived from vanilla `SteelSword` (`013989:Skyrim.esm`), reusing its mesh and MODT so no assets ship. |
| `000801:ExampleMod.esp` | Quest | `ExampleMod_StartupQuest` | **Script host.** `StartGameEnabled`, no stages, so it never appears in the journal. Carries `ExampleModStartupScript`. |
| `000802:ExampleMod.esp` | ConstructibleObject | `ExampleMod_RecipeExampleBlade` | **New record.** Forge recipe, no perk condition, so it is craftable at level 1. |
| `09BC43:Skyrim.esm` | LeveledItem | `LItemWeaponSwordBlacksmith` | **Override.** Vanilla record copied verbatim with one entry appended — blacksmiths now stock the blade. Note the filename keeps `_Skyrim.esm`. |

**FormID usage:** `0x800–0x802`. **Next free: `0x803`.**

## Record patterns / templates

The weapon was produced by copying `reference/Base/01Skyrim/Weapons/SteelSword - 013989_…yaml` and
changing only `FormKey`, `EditorID`, `Name`, `BasicStats` and `Critical.Damage` — the `Model.Data`
MODT blob and the `Unknown2`/`Unused` fields are vanilla bytes and were carried across untouched.
That is the pattern to follow: **copy, then edit the deltas.**

## Useful FormKey constants

| FormKey | Meaning |
|---|---|
| `000014:Skyrim.esm` | PlayerRef |
| `000038:Skyrim.esm` | GameHour global |
| `000039:Skyrim.esm` | GameDaysPassed global |
| `00003C:Skyrim.esm` | Tamriel worldspace (map markers live in its persistent cell) |
| `000010:Skyrim.esm` | MapMarker base |
| `000034:Skyrim.esm` | XMarker base |
| `10F63C:Skyrim.esm` | MapMarkerRef LocationRefType (required for discoverability) |
| `0FB98C:Skyrim.esm` | Blessing keyword (PeakValueMod association) |
| `088105:Skyrim.esm` | `CraftingSmithingForge` bench keyword |
| `088108:Skyrim.esm` | `CraftingSmithingSharpeningWheel` (tempering bench) |
| `05ACE5 / 05ACE4 / 0800E4` | `IngotSteel` / `IngotIron` / `LeatherStrips` |
| `013F42:Skyrim.esm` | `RightHand` EquipType |
| `01E719 / 01E711 / 08F958` | `WeapMaterialSteel` / `WeapTypeSword` / `VendorItemWeapon` |

## Gotchas

- **FOMOD images that actually render in MO2** — a config can build clean, pass
  `build.ps1 -CheckFomod`, open its wizard normally, and still show *no image at all*. Nothing
  warns you. This recipe is confirmed working in MO2 — it is kept as `build/fomod-example/`, which
  is reference material only and belongs to no release; copy its shape rather than re-deriving:
  1. `path=` is relative to the **archive root**, so an image at `fomod/images/foo.jpg` is
     referenced as `path="fomod\images\foo.jpg"` — *including* the `fomod` prefix.
  2. Use **backslashes** in `path=`, as the shipped configs do.
  3. Declare an `<installSteps>` block, even for a mod with no real choices (one
     `SelectExactlyOne` group holding a single `Recommended` plugin). A config with only
     `<requiredInstallFiles>` gives MO2 no wizard page to draw the banner on.
  4. Use a **baseline** JPEG or a PNG, not a progressive JPEG. Check with
     `od -A d -t x1 -v img.jpg | grep -oE 'ff c[0-9a-f]'`: `ff c0` is baseline (fine), `ff c2` is
     progressive. Re-encode progressive files via `System.Drawing` before shipping.

  These four were fixed **together** after several one-at-a-time attempts each failed, so which is
  individually decisive is unverified — treat the set as the known-good recipe, and do not drop one
  on the assumption it does not matter.

  `build/build.ps1 -CheckFomod` now enforces points 1, 2 and 4: an unresolvable `path=` or a
  progressive JPEG **fails** the check (with a "did you mean `fomod\…`?" hint for the missing
  prefix), and forward slashes warn. It cannot check point 3 — whether an `<installSteps>` block
  exists at all — because a config legitimately may not want one.
- **Decompiled `.psc` is a reconstruction** (Champollion): auto-named vars, reconstructed control
  flow, lost comments/flags. Always recompile and test in-game; a clean compile is not proof.
- **Missing-type compile errors** → the referenced API's source isn't on the import path; add its
  `Source\Scripts` dir to `importDirs` in `tools.json` and record it in the imports table above.
- **YAML comments do not survive a re-serialize.** Spriggit rewrites the folder from the binary
  plugin, so any `#` comment you add to a record file is lost the next time anyone runs
  `/spriggit-serialize`. Put durable explanation in this file, not in the record YAML.
- Edit `.psc`/YAML, never the binary `.pex`/`.esp`. Commit source, not build artifacts.
- See `arch-docs/skyrim-record-patterns.md` for the in-game failure modes that produce no build
  error — that list is the single highest-value read before authoring a new mechanic.
