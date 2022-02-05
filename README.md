# [NMRiH] Item Sharing

Allows players to share items with teammates via right click.

![image](https://user-images.githubusercontent.com/11559683/152640384-70ce6cff-04b4-43ee-b8ed-4337e5d50b28.png)

This was originally part of the [Team Healing plugin](https://github.com/dysphie/nmrih-team-healing).


## Installation
- Ensure you have [Sourcemod 1.11](https://wiki.alliedmods.net/Installing_sourcemod) or higher installed
- If [Team Healing](https://github.com/dysphie/nmrih-team-healing/releases) is installed, ensure you're running version 1.0.5 or higher
- Grab the latest zip from the [releases](https://github.com/dysphie/nmrih-item-sharing/releases) section.
- Extract the contents into `addons/sourcemod`
- Refresh the plugin list (`sm plugins refresh` or `sm plugins load item-sharing` in server console)

## Configuration

You can specify which items can be shared in `configs/item-sharing.cfg`.

By default this includes all medical items and machetes

```cpp
"Items"
{
	// item classname       // sound to play when given, or empty ("") to play "weapon_db.GenericFoley"
	"item_first_aid"        ""
	"item_bandages"         ""
	"item_pills"            "MedPills.Draw"
	"item_gene_therapy"     ""
	"me_machete"            ""
}
```

## Opting out

Clients can opt out of team sharing via `sm_settings` -> `Disable item sharing`. 

This will make the player unable to give or receive items.

## Translating

You can translate all printed text via `translations/item-sharing.phrases.txt`. See [Translations](https://wiki.alliedmods.net/Translations_(SourceMod_Scripting)#Distributing_Language_Files)
