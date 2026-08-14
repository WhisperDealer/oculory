# SkyrimSE record patterns — known-good archetypes and the traps

A field guide to record shapes that **actually work in-game**, and the plausible-looking ones that
silently don't. Every entry here cost someone a build-deploy-launch-test cycle to discover.

**Why this file exists.** A Skyrim plugin can be perfectly valid — Spriggit deserializes it, xEdit
reports no errors, the Creation Kit opens it — and still do nothing at all when you play. The engine
has a large set of unwritten rules about which field combinations are live and which are inert. None
of them produce an error message. The only feedback is "I pressed the button and nothing happened,"
twenty minutes after you started the game.

**How to use it:**

- **Before authoring a new mechanic**, find the closest archetype below and copy its shape. Prefer a
  proven pattern over an invented one — the failure mode for invented mechanics is silence, not an
  error, so you pay for the experiment in full test cycles.
- **Before shipping**, run the checklist at the bottom, or ask the `spriggit-formkey-auditor`
  subagent to scan for these anti-patterns.
- **When something doesn't fire in-game**, read the anti-pattern column first. It is usually there.

Confidence is marked per entry:
**[verified]** — observed failing and then fixed in a real playthrough in this project's lineage.
**[community]** — long-established Skyrim modding knowledge, not independently re-tested here.

---

## 1. Spells and Magic Effects

### Delivery and casting type must match how the effect reaches its target

| Intent | Casting Type | Delivery | Notes |
|---|---|---|---|
| Passive always-on bonus (an "ability") | `ConstantEffect` | `Self` | The standard boon/perk-carrier shape. Duration 0. Added with `AddSpell`. |
| Player-activated, once per day | `FireAndForget` | `Self` | A **Greater Power**. `Spell.Type = Power`. |
| Player-activated, unlimited uses | `FireAndForget` | `Self` | A **Lesser Power**. `Spell.Type = LesserPower`. |
| Effect applied to another actor at range | `FireAndForget` | `Aimed` | **Requires a Projectile on the MGEF.** |
| Effect applied to whoever you touch | `FireAndForget` | `Touch` | No projectile needed. |
| Radius effect around the caster | `ConstantEffect` | `Self` + Cloak archetype | See §1.2. |
| Shrine / altar blessing | `FireAndForget` | `Self`, `Spell.Type = Blessing` | See §3. |

> **Anti-pattern [verified]: an `Aimed` spell with no projectile.**
> The spell casts, the animation plays, magicka is spent — and nothing ever arrives at the target,
> because `Aimed` delivery is implemented by firing a projectile and there isn't one. This is
> especially insidious for effects like *force the target to flee*, where you stand there watching an
> enemy calmly not fleeing with no indication why.
> **Fix:** either attach a Projectile to the MGEF, or restructure so the *victim* self-casts the
> effect (script: `victim.DoCombatSpellApply(fleeSpell, victim)` or `victim.AddSpell(...)`), which is
> usually what you actually wanted for a debuff.

> **Anti-pattern [verified]: using a Greater Power where you meant scaling or repeatable use.**
> `Spell.Type = Power` is hard-gated to once per game day by the engine. If the design says "costs a
> resource" or "usable whenever the condition is met," you want `LesserPower` plus your own gating
> condition — otherwise the mechanic appears broken the second time the player tries it.

### 1.2 Cloak effects always need a cooldown gate

The cloak pattern is: an ability (`ConstantEffect`/`Self`) whose MGEF uses
`MagicEffectCloakArchetype` and points at a **proc spell**; the engine re-applies that proc spell to
every actor in the radius **on a repeating tick**, not once on entry.

```
<Ability Spell>  ConstantEffect / Self, magnitude = radius
  └── <Cloak MGEF>  MagicEffectCloakArchetype, Association -> <Proc Spell>
        └── <Proc Spell>  FireAndForget / Contact (or Self, cast on the victim)
              ├── <Real Effect MGEF>   conditions: cooldown marker ABSENT (+ any filters)
              └── <Cooldown Marker MGEF>  Script archetype, no script, duration = cooldown
```

> **Anti-pattern [verified]: a cloak proc with no cooldown marker.**
> The real effect re-fires on every cloak tick. A "heal a nearby ally" boon becomes an infinite heal;
> a "chance to frighten" becomes a permanent stunlock; a favor/point award becomes a rapidly
> incrementing counter. It reads as a wildly overpowered bug rather than a subtle one.
> **Fix:** add a second MGEF to the proc spell that does nothing but exist for `duration` seconds,
> and put `HasMagicEffect(<marker>) == 0` in the real effect's conditions. The marker's *only* job is
> to answer "have I fired recently?"

### 1.3 A Script-archetype MGEF with no script attached is decoration

`MagicEffectArchetype: Script` tells the engine "the behaviour lives in an attached Papyrus script."
If `VirtualMachineAdapter` is empty, the effect has **no behaviour at all** — it only contributes its
name, description and duration to the active-effects UI.

This is a legitimate and common technique — it is how you show a tenet, a status, or a cooldown
marker in the UI — but it is a trap when someone reads the description text and assumes the mechanic
is implemented. **[verified]** in this project's lineage, an entire set of "tenets" was cosmetic for
a long time because the enforcement actually lived, hardcoded by index, inside a third-party mod's
compiled `.pex`.

**Rule:** if a MGEF's description promises a mechanic, either attach a script that implements it, or
write a comment in the YAML saying explicitly that it is display-only and where the real logic lives.

### 1.4 `PeakValueModArchetype` needs an association keyword

Peak-value-modifier effects (the shape used by shrine blessings and similar stacking-but-replaceable
buffs) rely on an `Association` keyword so the game knows which other effects they replace.
For blessings that keyword is `0FB98C:Skyrim.esm`. **[community]** Without it, blessings stack or
fail to clear as expected.

---

## 2. Perks and entry points

> **Anti-pattern [verified]: `MultiplyOnePlusAVMult` on a value-modifying perk entry point.**
> The multiplier is applied to the underlying value, so the mechanic *works* — but the **inventory
> card never updates**. A player looking at their weapon's damage number sees no change and concludes
> the boon is broken, then reports it as a bug.
> **Fix:** use a flat `Multiply: <ratio>` entry point instead. The displayed number then tracks the
> real value. Take the loss in flexibility; a mechanic the player can't see is worth very little.

**[community]** Other perk-entry-point notes worth knowing:

- Perk entry points are evaluated by the engine at specific moments; a perk added mid-combat may not
  affect an already-swung attack.
- A perk attached via `PerkToApply` on a MGEF is added/removed with the effect. A perk added by
  script via `AddPerk` persists until you `RemovePerk` it — including across the effect ending.
  Mixing the two mechanisms for the same perk leaves orphaned copies in the save.

---

## 3. Activators (shrines, altars, prayer nodes)

The vanilla shrine shape is an Activator running `TempleBlessingScript` (or
`defaultTempleBlessingScript`) with three properties wired: the blessing spell, the "blessing added"
message, and the "previous blessing removed" message (`10E4F9:Skyrim.esm` is the vanilla one).

```yaml
VirtualMachineAdapter:
  Scripts:
  - Name: TempleBlessingScript
    Properties:
    - MutagenObjectType: ScriptObjectProperty
      Name: AltarRemoveMsg
      Object: 10E4F9:Skyrim.esm
    - MutagenObjectType: ScriptObjectProperty
      Name: BlessingMessage
      Object: <your "blessing added" Message>
    - MutagenObjectType: ScriptObjectProperty
      Name: TempleBlessing
      Object: <your Blessing spell>
```

> **[verified]** Prefer a **clickable activator** ("prayer node") over an effect that tries to detect
> praying. Detecting the vanilla prayer action is fragile; an activator the player walks up to and
> presses E on is unambiguous, discoverable, and trivially debuggable.

> **[verified] Property names are matched by string.** `Name:` must equal the Papyrus property name
> exactly, including case. A typo doesn't fail the build — the property is simply `None` at runtime,
> and the script silently no-ops or throws into the Papyrus log where nobody looks.

---

## 4. Placed objects, map markers and cell edits

Map markers are **two** PlacedObject records in the target worldspace's **persistent** cell:

```yaml
- MutagenObjectType: PlacedObject
  FormKey: <markerKey>:<YourPlugin>.esp
  MajorRecordFlagsRaw: 1024                 # 0x400 = Persistent — required
  SkyrimMajorRecordFlags: [0x400]
  Base: 000010:Skyrim.esm                   # MapMarker base
  LocationRefTypes: [10F63C:Skyrim.esm]     # MapMarkerRef — REQUIRED for discoverability
  LinkedReferences:
  - Reference: <linkKey>:<YourPlugin>.esp   # the XMarker you fast-travel to
  MapMarker:
    Name: { TargetLanguage: English, Value: <Marker Name> }
    Type: <Shrine|Town|Cave|...>
  Placement:
    Position: <X>, <Y>, <Z>
- MutagenObjectType: PlacedObject
  FormKey: <linkKey>:<YourPlugin>.esp
  MajorRecordFlagsRaw: 1024
  SkyrimMajorRecordFlags: [0x400]
  Base: 000034:Skyrim.esm                   # XMarker base
  Placement:
    Position: <X+300>, <Y>, <Z>
    Rotation: 0, 0, 0
```

> **Anti-pattern [verified]: a map marker with no `LocationRefTypes`.**
> It renders on the map but does not behave as a discoverable location — no discovery notification,
> no fast-travel entry. Add `10F63C:Skyrim.esm`.

> **Anti-pattern [verified]: reading placement coordinates off the in-game console.**
> Console coordinates are the *player's* position, not the object's origin, and mesh geometry is
> frequently offset from the reference origin. Read the canonical `Position` from the existing
> PlacedObject record in the serialized worldspace instead. (Concretely, in this project's lineage a
> shrine `.nif` sat **55 units above** its reference origin, so every shrine placed from console
> coordinates floated.)

> **[community] Never delete a reference** in a cell you're patching. A deleted reference (UDR) that
> another mod or a save still points at causes crashes. Set it *Initially Disabled* and move it far
> below the world instead. xEdit's QuickAutoClean pass catches deleted refs and ITMs.

---

## 5. Quests, aliases and script attachment

**Start-game-enabled setup quest** — the standard way to run code once when a mod first loads, and
the standard way to attach a script to the player:

- `Quest.Flags` includes `StartGameEnabled` (and `RunOnce` if it is genuinely one-shot).
- Put persistent per-player behaviour on a **ReferenceAlias pointing at PlayerRef**
  (`000014:Skyrim.esm`), not on the quest itself — alias scripts receive `OnObjectEquipped`,
  `OnHit`, `OnPlayerLoadGame` and friends; a bare quest script does not.

> **Anti-pattern [community]: relying on `RunOnce` for something that must survive a mod update.**
> A `RunOnce` quest that has already run will not re-run for players updating from a previous
> version. Version your setup with a global or a script property and re-run on version bump.

> **[verified] Index-based logic in a third-party compiled script does not extend to your records.**
> If you are appending to arrays inside another mod's quest, be aware that any behaviour keyed off
> `if index == 4` inside their compiled `.pex` applies only to *their* indices. Your new entries
> inherit the data-driven parts and none of the hardcoded parts. Verify which is which by reading
> their decompiled source before you promise the mechanic works.

---

## 6. Globals, gating and persistence

**[community]** `GlobalVariable.SetValue` from Papyrus persists in the save. The standard daily-gate
pattern is to store `GameDaysPassed` (`000039:Skyrim.esm`) at use time and compare on the next
attempt:

```papyrus
If (GameDaysPassed.GetValue() as Int) > (LastUsedDay.GetValue() as Int)
    LastUsedDay.SetValue(GameDaysPassed.GetValue())
    ; ... do the thing
Else
    Debug.Notification("You must wait until tomorrow.")
EndIf
```

Prefer this over a Greater Power's built-in once-per-day when you need the cooldown to be visible,
adjustable, or conditional.

---

## 7. Plugin-level shapes

- **ESL / `Small`-flagged plugins are limited to FormIDs `0x800–0xFFF`** — 2048 records. Allocate a
  contiguous block per feature so diffs stay readable, and grep the whole workspace before assigning
  a hex ID. The `formkey-check` skill does this.
- **New records** take your plugin's ModKey as the FormKey suffix (`000801:YourMod.esp`).
  **Overrides keep the defining master's suffix** (`0099B0:Skyrim.esm`) — that is how you tell at a
  glance which records you invented and which you are modifying.
- **Set a sane `Stats.Version` in `RecordData.yaml`.** SSE Wrye Bash rejects `0.85`-style versions;
  use `1.7` or similar. **[verified]**
- **Every master you reference must be declared** in `RecordData.yaml`'s `MasterReferences`, in load
  order. A FormKey pointing at an undeclared master resolves to garbage at runtime.

---

## Pre-ship checklist

Run through this before packaging. The `spriggit-formkey-auditor` subagent can check most of it.

| # | Check | Failure mode if skipped |
|---|---|---|
| 1 | No duplicate FormIDs within the plugin | Spriggit or the game picks one arbitrarily |
| 2 | ESL-flagged → all new FormIDs in `0x800–0xFFF` | Records silently dropped or remapped |
| 3 | Every referenced FormKey resolves; every master declared | Dangling ref, garbage at runtime |
| 4 | Filename `<EditorID> - <FormID>_<Master>.esp.yaml` matches the `EditorID:`/`FormKey:` inside | Confusing diffs; usually a copy-paste bug with a real wrong-record behind it |
| 5 | No `Aimed` spell without a projectile | Spell casts, nothing happens |
| 6 | Every cloak proc gated by a cooldown-marker MGEF | Effect fires every tick |
| 7 | No value-modifying perk entry point using `MultiplyOnePlusAVMult` | Works, but inventory card never updates |
| 8 | Every map marker has `LocationRefTypes: [10F63C:Skyrim.esm]` and a linked XMarker | Not discoverable, no fast travel |
| 9 | Every Script-archetype MGEF either has a script or is documented as display-only | Description promises a mechanic that doesn't exist |
| 10 | Every `ScriptObjectProperty.Name` matches the `.psc` property exactly | Property is `None`; script silently no-ops |
| 11 | Every `.psc` changed → recompiled **and the `.pex` committed** | Ships stale scripts; CI cannot detect this |
| 12 | Parallel arrays / linked record sets are the same length | Silent per-index failure |
| 13 | No deleted references in patched cells | Crashes for anyone whose save references them |

**And the rule that supersedes all of the above:** a clean deserialize, a clean xEdit report, and a
clean Papyrus compile prove the mod *builds*. They prove nothing about whether it *runs*. Deploy to a
real MO2 profile and look at it with your own eyes before you call it done.
