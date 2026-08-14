---
name: package-mod
description: Assemble a loose SkyrimSE mod folder (the .esp plus compiled scripts and optional source) in Data layout, ready to install and test in an MO2 modlist. Use when the user wants to package their plugin + scripts into an installable/testable mod.
---

# Package a loose mod for MO2 testing

Assemble everything the game needs into one folder laid out like `Data\`, so it can be dropped
into a Mod Organizer 2 modlist and tested.

## Inputs to collect

- **Mod name** → `<ModName>` (used for the folder and the `.esp`).
- Which scripts to include (default: everything in `src/<ModName>/Scripts/compiled/`).
- Whether to ship `.psc` **source** alongside (recommended for your own mods; lets others rebuild).

## Target layout

```
dist/<ModName>/
  <ModName>.esp            # from spriggit-deserialize
  Scripts/*.pex            # from src/<ModName>/Scripts/compiled/
  Source/Scripts/*.psc     # optional, from src/<ModName>/Scripts/source/
```

## Steps

1. **Build the plugin** if not already current — run the **spriggit-deserialize** skill to produce
   `<ModName>.esp` from the YAML.
2. **Compile scripts** if not already current — run the **papyrus-compile** skill so
   `src/<ModName>/Scripts/compiled/` holds fresh `.pex`.
3. **Assemble** `dist/<ModName>/` (PowerShell):

```powershell
$mod = "<ModName>"
$dest = "dist/$mod"
New-Item -ItemType Directory -Force "$dest\Scripts" | Out-Null
Copy-Item "<ModName>.esp" "$dest\$mod.esp" -Force
Copy-Item "$mod/Scripts/compiled/*.pex" "$dest\Scripts\" -Force
# Optional: ship source too
New-Item -ItemType Directory -Force "$dest\Source\Scripts" | Out-Null
Copy-Item "$mod/Scripts/source/*.psc" "$dest\Source\Scripts\" -Force
```

## Install & test in an MO2 modlist

**Hand off to the `mod-deploy` skill** — do not copy into the modlist from here. That skill owns the
deploy path (`$Tools.modsDir` + `$Tools.deployModName`) and, critically, *verifies* the mod landed
under the exact expected folder name. A mod deployed into a wrongly-named folder is invisible to MO2
and the game runs fine without it, so the failure looks like a broken record rather than a bad path.

Keeping that logic in one place means there is exactly one definition of where this mod deploys to.

After `mod-deploy` reports success, these remain manual:

1. In MO2: refresh (F5), **enable** the mod (left pane), **enable the `.esp`** and set its load order
   (right pane), then launch the game/SKSE through MO2.
2. Verify the scripts run in-game (the only real test — a clean compile is necessary, not sufficient).

## Notes

- `dist/` is gitignored — it's fully derivable from the committed Spriggit YAML +
  `src/<ModName>/Scripts/source/`.
- Keep the `.esp` name, its ModKey in the Spriggit YAML, and the `dist` filename consistent.
- For a FOMOD-installable release archive rather than a loose test build, use `build/build.ps1`.
