# [NMRiH] Item Sharing

Allows players to share items with teammates via right click.

This was originally part of the [Team Healing plugin](https://github.com/dysphie/nmrih-team-healing)


## Installation
- Ensure you have [Sourcemod 1.11](https://wiki.alliedmods.net/Installing_sourcemod) or higher installed
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
