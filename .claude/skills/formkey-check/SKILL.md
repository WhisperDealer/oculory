---
name: formkey-check
description: Check the SkyrimSE Spriggit workspace for FormID/FormKey collisions before assigning a new one, or find the next free FormID block. Use when the user is about to create a record, asks "is this FormID free", "what's the next free FormKey", or wants a collision audit.
---

# FormKey collision check

Enforce FormKey discipline: never assign a FormID that already exists. This skill greps the
whole workspace — **both your authored YAML and the gitignored `reference/` decompiles** —
because a collision against a master is just as bad as one against your own records.

## Modes

### A) "Is this FormID free?" — collision check for a specific hex

1. Normalize the input to a 6-hex-digit FormID (e.g. `0x000812` → `000812`). Note that in
   Spriggit YAML, FormKeys appear as `<FormID>:<ModKey>` (e.g. `000812:MyMod.esp`).
2. Grep the workspace for the hex, case-insensitive, across `*.yaml`:
   - Search your record folders **and** `reference/`.
3. Report:
   - **Collision** → list each file/line that uses it, and whether it's your plugin or a reference master.
   - **Free** → confirm no matches found.

### B) "Find the next free FormID" — allocate a block

1. Collect every FormID this plugin owns: grep `*.yaml` (excluding `reference/`) for the
   `<hex>:<ThisPlugin>.esp` pattern and extract the hex values.
2. Sort them; find the highest used, then propose the next contiguous free block (the user
   usually wants a small run, e.g. 4–16 IDs, for one feature so diffs stay readable).
3. Double-check the proposed IDs are unused in `reference/` too.

## Constraints to enforce

- **ESL range:** if the plugin is ESL-flagged (`.esl`, or `.esp`/`.esm` with the ESL/light flag
  set in `RecordData.yaml`), new FormIDs are limited to `0x800–0xFFF`. Warn before exceeding.
- New records use **this plugin's** name as the FormKey suffix — don't propose IDs under a master's ModKey.

## Tips

- Use the Grep tool over `glob: "*.yaml"` rather than shell `grep`.
- If the workspace has no record YAML yet, say so plainly ("no FormIDs found yet — start anywhere
  in this plugin's range").
