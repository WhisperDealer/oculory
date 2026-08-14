---
name: mod-deploy
description: Deploy the packaged mod from dist/<ModName>/ into an MO2 modlist's mods folder and verify it actually landed under the exact expected name. Use when the user wants to install, deploy, or test the built mod in a modlist, or asks why their change isn't showing up in-game.
---

# Deploy to an MO2 modlist (and verify it landed)

Copy `dist/<ModName>/` into a Mod Organizer 2 instance and then **prove it arrived**. The verify
step is the point of this skill: a mod deployed into a wrongly-named folder is invisible to MO2, the
game runs happily without it, and the symptom is "my change didn't work" — which sends you debugging
records that were never loaded.

## Inputs (from config — do not go hunting on the filesystem)

Read `.claude/config/tools.json` via `. ".claude/config/tools.ps1"`:

| Key | Meaning |
|---|---|
| `$Tools.modsDir` | The MO2 instance's `mods\` folder you deploy into. |
| `$Tools.deployModName` | The **exact** folder name to create inside it. |
| `$Tools.modlistsRoot` | Parent of several MO2 instances, when you switch between them. |
| `$Tools.modlistRoot` | A single Wabbajack instance root (its `mods\` is `<modlistRoot>\mods`). |

If `modsDir` or `deployModName` is blank, **ask the user** — do not guess and do not search the
filesystem for something that looks like a modlist. Then offer to write the answer into `tools.json`
so the next deploy needs no questions.

> `deployModName` is a deliberate, separate setting rather than something derived from the plugin
> name. MO2 folder names frequently differ from the `.esp` name — spaces, dashes and casing all vary
> — and getting it wrong is the single most common cause of "the change never appeared in-game".

## Steps

1. **Confirm the source exists.** `dist/<ModName>/` must be present and current. If it is missing or
   older than the YAML/scripts, run the **package-mod** skill first (which itself runs
   **spriggit-deserialize** and **papyrus-compile** as needed).

2. **Show the user the exact destination and confirm it** before copying:

   ```
   dist/<ModName>/  ->  <modsDir>\<deployModName>\
   ```

   If `<modsDir>\<deployModName>\` already exists, say so — this is an overwrite. Note whether MO2
   is currently running; deploying under a running MO2 works but needs a refresh (F5) to show up.

3. **Copy** (PowerShell):

   ```powershell
   . ".claude/config/tools.ps1"
   $src  = "dist/<ModName>"
   $dest = Join-Path (Assert-Tool $Tools.modsDir 'modsDir') $Tools.deployModName
   New-Item -ItemType Directory -Force $dest | Out-Null
   Copy-Item "$src\*" $dest -Recurse -Force
   ```

4. **Verify — always, and report the evidence.** Do not claim success from the copy's exit code:

   ```powershell
   # a) the folder exists under EXACTLY the expected name (case-correct, no stray spaces)
   $actual = Get-ChildItem (Split-Path -Parent $dest) -Directory |
             Where-Object { $_.Name -eq (Split-Path -Leaf $dest) }
   if (-not $actual) { throw "Deploy target not found: $dest" }

   # b) what actually landed
   Get-ChildItem $dest -Recurse -File | Select-Object -ExpandProperty FullName

   # c) MO2 sees it: the profile's modlist.txt should carry a "+<deployModName>" line
   #    (a "-" prefix means present but DISABLED, which looks identical in-game to not installed)
   Get-ChildItem (Join-Path (Split-Path -Parent $Tools.modsDir) 'profiles') -Directory |
     ForEach-Object {
       $ml = Join-Path $_.FullName 'modlist.txt'
       if (Test-Path $ml) {
         $line = Select-String -Path $ml -Pattern ([regex]::Escape($Tools.deployModName)) -SimpleMatch
         "$($_.Name): $(if ($line) { $line.Line } else { 'NOT LISTED' })"
       }
     }
   ```

   Report each of the three results explicitly. Flag loudly if:
   - a folder with a *similar but different* name exists next to the target (a previous mis-deploy —
     the usual culprit; offer to remove it, since two copies will conflict);
   - the mod is absent from every `modlist.txt` (MO2 has not registered it — the user must refresh
     and enable it in the left pane);
   - it is listed with a `-` prefix (installed but **disabled**).

5. **Tell the user what is left to do by hand.** This skill cannot do these:
   - refresh MO2 (F5) and **enable** the mod in the left pane;
   - **enable the `.esp`** and set its load order in the right pane;
   - launch the game through MO2 and confirm the change in-game.

## Notes

- `dist/` is gitignored — it is fully derivable from the committed Spriggit YAML plus
  `src/<ModName>/Scripts/source/`.
- **A clean build and a successful deploy still prove nothing about behaviour.** See
  `arch-docs/skyrim-record-patterns.md` for record shapes that install perfectly and do nothing.
- For a release archive rather than a loose test deploy, use `build/build.ps1`, which produces the
  FOMOD-installable `.7z` in `build/dist/`.
