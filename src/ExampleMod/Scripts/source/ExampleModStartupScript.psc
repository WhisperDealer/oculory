Scriptname ExampleModStartupScript extends Quest
{Example Mod - the Papyrus half of this template.

 Attached to ExampleMod_StartupQuest (000801), a start-game-enabled quest with no stages, so it
 runs itself once and never appears in the journal. OnInit fires the first time the quest is
 initialised: on a new game, or on the first load after this plugin is added to an existing save.

 The work happens in OnUpdate rather than directly in OnInit. On a new game OnInit runs during the
 Helgen intro, where a Debug.Notification is swallowed by the load screen; RegisterForSingleUpdate
 defers it until the player is actually in the world.

 The properties below are filled from the plugin's VirtualMachineAdapter - see
 ExampleMod_StartupQuest - 000801_ExampleMod.esp.yaml. The .psc declares them, the YAML supplies
 the values, and the names must match EXACTLY: a typo does not fail the build, it just leaves the
 property None at runtime and the script silently does nothing.}

Weapon Property RewardWeapon Auto
{The Example Blade (000800:ExampleMod.esp). Given to the player once, on first run.}

Bool Property ShowNotification = True Auto
{Set to False in the quest YAML to suppress the corner-of-screen message.}

Float Property StartupDelay = 5.0 Auto
{Seconds to wait after init before acting. Deliberately NOT set in the VMAD - this default is
 baked into the .pex, which is what an auto-property initialiser does when the plugin does not
 override it. Change it here and you must recompile; change it in the YAML and you need not.}

Event OnInit()
    RegisterForSingleUpdate(StartupDelay)
EndEvent

Event OnUpdate()
    Actor player = Game.GetPlayer()
    If player == None || RewardWeapon == None
        Return
    EndIf

    ; abSilent defaults to False, so the player also gets the vanilla item-added toast.
    player.AddItem(RewardWeapon, 1)

    If ShowNotification
        Debug.Notification("Example Mod is running - the Example Blade is in your inventory.")
    EndIf
EndEvent
