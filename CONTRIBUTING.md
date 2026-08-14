# Contributing

Thanks for looking. This repo is a **template** for building SkyrimSE mods as text — so the useful
contributions are ones that make the *workspace* better for everyone, not ones that add mod content.

## What's in scope

- **Fixes and improvements to the tooling** — `build/build.ps1`, `build/Test-RecordYaml.ps1`, the
  GitHub Actions workflows, `.claude/config/tools.ps1`.
- **New or improved skills and subagents** under `.claude/`. If you have automated part of your own
  modding loop and it isn't specific to your mod, it probably belongs here.
- **`arch-docs/skyrim-record-patterns.md`.** This is the highest-value file in the repo and the one
  most likely to be incomplete. If you have lost an afternoon to a record that built cleanly and did
  nothing in-game, that belongs in the guide. Please mark it `[verified]` only if you personally saw
  it fail and then saw the fix work; use `[community]` otherwise.
- **Support for other Bethesda games.** Spriggit handles Fallout 4, Starfield and Oblivion too.
  Most of this workspace is game-agnostic; the parts that aren't are mostly in `.spriggit`,
  `tools.example.json` and the SkyrimSE-specific record guidance.
- **Documentation** — especially anywhere the README or `CLAUDE.md` is wrong, stale, or assumes
  knowledge a newcomer won't have.

## What's out of scope

- **Your mod's content.** Fork the template and build your mod in your own repo — that's the point.
  `ExampleMod` stays deliberately minimal; please don't grow it. If you want to demonstrate an
  additional record type, the record-patterns guide is the better home.
- **Anything containing Bethesda assets or third-party mod content.** Nothing under `reference/` or
  `modlist/` is committed, and it must stay that way. Before opening a PR, check `git status` — if a
  `.esp`, `.bsa`, `.pex` you didn't author, or a decompiled vanilla record has crept in, remove it.

## Before you open a PR

1. **The build must pass.** Both of these, from a clean checkout:

   ```powershell
   pwsh build/build.ps1 -CheckFomod
   pwsh build/build.ps1
   ```

2. **The record check must pass** if you touched any plugin YAML:

   ```powershell
   pwsh build/Test-RecordYaml.ps1
   ```

3. **Round-trip stability** if you hand-edited a record: deserialize, re-serialize, and confirm the
   YAML comes back identical. Spriggit output is canonical; hand-authored YAML should match it
   byte-for-byte so nobody gets a spurious whole-file diff later.

4. **Don't commit `.claude/config/tools.json`.** It's gitignored for a reason — it contains your
   machine's paths. Update `tools.example.json` instead if you're adding a key.

5. **If you changed a `.psc`, recompile and commit the `.pex`.** CI cannot compile Papyrus. The
   build fails on a *missing* `.pex` but cannot detect a *stale* one, so this one is on you.

Opening a PR triggers a test build that attaches the resulting archives as an Actions artifact, with
a comment linking to them. Fork PRs get a read-only token, so that comment step will be skipped —
the build itself still runs.

## Style

- PowerShell targets **5.1**: `Set-StrictMode` is on, and there is no `&&`, no ternary, and no
  null-coalescing operator. Test on Windows PowerShell, not just `pwsh`.
- Match the surrounding prose. The docs explain *why*, not just *what* — a rule without its reason
  gets dropped the first time it's inconvenient.
- Keep skills declarative: they describe a procedure for an agent to follow. Resolve every tool path
  through `$Tools` from `tools.json`; never hardcode one.
