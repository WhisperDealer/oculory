---
name: modlist-install
description: Install a Wabbajack (.wabbajack) SkyrimSE modlist into a gitignored location and auto-discover its tool paths (Creation Kit, Papyrus compiler, game folder, xEdit, etc.) into .claude/config/tools.json. Use when the user wants to set up a modlist, point the workspace at an installed modlist, install a .wabbajack file, or stop using hardcoded tool paths.
---

# Install a Wabbajack modlist & wire it into the workspace

A Wabbajack modlist is a self-contained MO2 instance — game folder, mods, and tools (often
**including the Creation Kit and the Papyrus compiler**) — that can be **hundreds of GB**. It is
**never committed**; it lives outside or under a gitignored path and the workspace points at it
through `.claude/config/tools.json`. This skill (1) guides the install, then (2) discovers the
tool paths inside it and writes them to the config so every other skill uses them automatically.

## Why

The skills no longer hardcode tool paths — they read `.claude/config/tools.json` via
`.claude/config/tools.ps1`. Installing a modlist and running the discovery below repoints the
**whole toolchain** (Spriggit aside, which is a standalone CLI) at the modlist in one step.

## Part 1 — Install the `.wabbajack` (manual, GUI step)

The actual install is done by the **Wabbajack** app; it cannot be driven headlessly here. Guide
the user:

1. Get Wabbajack from <https://www.wabbajack.org/> and the `.wabbajack` file for the list.
2. In Wabbajack: select the `.wabbajack` file, then set:
   - **Install Location** — where the modlist (MO2 instance) is built. Pick a big drive. If you
     want it *inside* the repo, use `modlists/<ListName>/` (already gitignored); otherwise any
     external path like `D:/Modlists/<ListName>` is fine.
   - **Download Location** — where mod archives are cached (also huge; keep outside git).
3. Click **Install** and wait (long — tens of minutes to hours).
4. When done, the **Install Location** is the *modlist root* (it contains `ModOrganizer.exe`,
   `mods/`, `profiles/`, usually `tools/` and a game copy like `Stock Game/` or `Game Root/`).

**Confirm the modlist root path with the user before continuing.**

## Part 2 — Discover tools & write `tools.json`

Run this with the confirmed modlist root. It probes the usual Wabbajack layout, fills in whatever
it finds, and **preserves existing values** for anything it can't locate. Review the output, then
hand-fill any blanks.

```powershell
$modlistRoot = "<CONFIRMED MODLIST ROOT>"   # e.g. D:/Modlists/LoreRim  or  modlists/LoreRim

$cfgPath = ".claude/config/tools.json"
$cfg = if (Test-Path $cfgPath) { Get-Content -Raw $cfgPath | ConvertFrom-Json } else { @{} | ConvertTo-Json | ConvertFrom-Json }

function First-Path { param([string[]]$Candidates) foreach ($c in $Candidates) { if ($c -and (Test-Path -LiteralPath $c)) { return ((Resolve-Path -LiteralPath $c).Path -replace '\\','/') } } return $null }
function Find-One { param([string]$Root,[string]$Filter) if (Test-Path -LiteralPath $Root) { $h = Get-ChildItem -LiteralPath $Root -Recurse -Filter $Filter -File -ErrorAction SilentlyContinue | Select-Object -First 1; if ($h) { return ($h.FullName -replace '\\','/') } } return $null }

# Game root: Wabbajack lists name the self-contained game folder a few different ways.
$gameRoot = First-Path @(
  (Join-Path $modlistRoot 'Stock Game'),
  (Join-Path $modlistRoot 'Game Root'),
  (Join-Path $modlistRoot 'Stock Game Folder'),
  (Join-Path $modlistRoot 'root'),
  $modlistRoot
)

$cfg.modlistRoot      = ($modlistRoot -replace '\\','/')
if ($gameRoot) {
  $cfg.gameRoot         = $gameRoot
  $cfg.gameDataDir      = "$gameRoot/Data"
  $cfg.gameSourceScripts= "$gameRoot/Data/Source/Scripts"
  $ck = First-Path @("$gameRoot/CreationKit.exe");                                   if ($ck) { $cfg.creationKit = $ck }
  $pc = First-Path @("$gameRoot/Papyrus Compiler/PapyrusCompiler.exe");              if ($pc) { $cfg.papyrusCompiler = $pc }
}
# Tools bundled in the modlist (xEdit/bsab/Champollion often live under tools/ or mods/).
$bsab = First-Path @((Join-Path $modlistRoot 'tools/BSA Browser/bsab.exe')); if (-not $bsab) { $bsab = Find-One $modlistRoot 'bsab.exe' }; if ($bsab) { $cfg.bsab = $bsab }
$champ = Find-One $modlistRoot 'Champollion*.exe'; if ($champ) { $cfg.champollion = $champ }

# Dev-tool exes wrapped by the workspace skills. Assign only if found so re-running preserves keys.
function Set-IfFound { param($Key,$Filter) $p = Find-One $modlistRoot $Filter; if ($p) { $cfg.$Key = $p } }
Set-IfFound 'sseedit'               'SSEEdit.exe'
Set-IfFound 'sseeditQuickAutoClean' 'SSEEditQuickAutoClean.exe'
Set-IfFound 'bsarch'                'BSArch64.exe'
Set-IfFound 'synthesis'             'Synthesis.exe'
Set-IfFound 'resaver'               'ReSaver.exe'
Set-IfFound 'cao'                   'Cathedral_Assets_Optimizer.exe'
Set-IfFound 'nifskope'              'NifSkope.exe'
Set-IfFound 'octagon'               'Octagon.exe'
Set-IfFound 'bae'                   'bae.exe'
# xEdit 'Edit Scripts' dir (holds 'Check for Errors.pas') — derive from the SSEEdit exe we found.
if ($cfg.sseedit) { $es = Join-Path (Split-Path $cfg.sseedit) 'Edit Scripts'; if (Test-Path -LiteralPath $es) { $cfg.xeditScriptsDir = ($es -replace '\\','/') } }

# Auto-populate Papyrus importDirs from framework mods that ship loose .psc source. Each entry is
# tried against a couple of common layouts; matches are de-duped into importDirs (existing kept).
$frameworks = @(
  'Skyrim Script Extender (SKSE64)','MCM SDK','MCM Helper',
  'PapyrusUtil SE - Modders Scripting Utility Functions','JContainers SE',
  'powerofthree Papyrus Extender',"Scrab's Papyrus Extender",'ConsoleUtilSSE NG'
)
$imports = [System.Collections.Generic.List[string]]::new()
if ($cfg.importDirs) { foreach ($d in $cfg.importDirs) { if ($d) { [void]$imports.Add($d) } } }
$modsDir = Join-Path $modlistRoot 'mods'
foreach ($fw in $frameworks) {
  $hit = First-Path @(
    (Join-Path $modsDir "$fw/Source/Scripts"),
    (Join-Path $modsDir "$fw/Scripts/Source"),
    (Join-Path $modsDir "$fw/scripts/source"),
    (Join-Path $modsDir "$fw/source/scripts")
  )
  if ($hit -and ($imports -notcontains $hit)) { [void]$imports.Add($hit) }
}
$cfg.importDirs = @($imports)

$cfg | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $cfgPath
Write-Host "Wrote $cfgPath. Review below:"
Get-Content $cfgPath
```

Then:

1. **Report what was found vs. left blank.** Common gaps: Creation Kit isn't always in the list
   (some are play-only), and `gameSourceScripts` may need `Scripts.zip` extracted (see the
   `papyrus-compile` skill's one-time setup). Dev lists (e.g. **STD — Styyx Tooling For Dev**) also
   fill `sseedit`/`sseeditQuickAutoClean`/`bsarch`/`synthesis`/`resaver` and auto-populate
   `importDirs` from bundled framework mods (SKSE/MCM/PapyrusUtil/JContainers/po3/Scrab/ConsoleUtil);
   play-only lists leave those blank. Re-running is idempotent — it preserves keys it can't find and
   never drops `importDirs` entries you added by hand.
2. **Spriggit CLI is independent** of the modlist — leave `spriggitCli` pointing at its standalone
   install unless the user moved it.
3. Tell the user any tool reached **through MO2** (so it sees virtual files) should be launched via
   `ModOrganizer.exe`; the discovered paths are the raw executables, fine for our CLI steps which
   operate on files in this repo, not on the virtual file system.

## Part 3 — Verify

```powershell
. ".claude/config/tools.ps1"
Assert-Tool $Tools.papyrusCompiler 'papyrusCompiler'
Assert-Tool $Tools.creationKit     'creationKit'
$Tools | ConvertTo-Json -Depth 4
```

`Assert-Tool` throws on a missing/empty path — fix those before relying on the toolchain.

## Notes

- The modlist itself is gitignored (`modlists/`, plus `tools.json`). Never commit it or its
  archives — they are enormous and licensed third-party content.
- Re-run Part 2 any time you reinstall or move the modlist; it's idempotent and preserves keys it
  can't rediscover.
- After this, the `papyrus-compile`, `bsa-extract`, `pex-decompile`, `package-mod`, and the
  Spriggit skills all resolve their paths from `tools.json` — no manual edits to each skill needed.
