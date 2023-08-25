#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <vscript_proxy>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

#define PREFIX				   "[Item Sharing] "

#define VOICECMD_THANKS		   5

#define NMR_MAXPLAYERS		   9
#define SND_GIVE_DEFAULT	   "weapon_db.GenericFoley"
#define MDL_MEDICAL			   "models/items/firstaid/v_item_firstaid.mdl"

#define IN_DROPWEAPON		   IN_ALT2	  // Button mask when player has drop weapon button pressed.

#define MDL_GIVE_BASE_DURATION 1.2667	 // TODO: Fetch dynamically via CBaseAnimating::SequenceLength

enum struct ItemShare
{
	bool active;
	int	 fakeArmsRef;
	int	 fakeItemRef;
	int	 itemRef;	 // The actual item being given
	int	 recipientSerial;

	void Init(){
		this.active			 = false;
		this.fakeArmsRef	 = INVALID_ENT_REFERENCE;
		this.fakeItemRef	 = INVALID_ENT_REFERENCE;
		this.itemRef		 = INVALID_ENT_REFERENCE;
		this.recipientSerial = 0; }
}

char	  g_ArmNames[][] = {
	 "default",
	 "bateman",
	 "butcher",
	 "hunter",
	 "jive",
	 "molotov",
	 "roje",
	 "wally",
	 "badass"
};


ItemShare g_ShareData[NMR_MAXPLAYERS + 1];
int g_ArmIndex[NMR_MAXPLAYERS + 1];
bool	  g_WasPressingShare[NMR_MAXPLAYERS + 1] = { false, ... };
bool	  g_HasShareable[NMR_MAXPLAYERS] = { false, ... };

Cookie	  g_OptOutCookie;
StringMap g_Shareables;	   // key: classname | value: sound to play

ConVar	  sm_item_sharing_enabled;
ConVar	  sm_item_sharing_speed;
ConVar	  sv_item_give_distance;
ConVar	  sv_item_give;
ConVar	  sm_item_sharing_keys;
// ConVar	  sm_item_share_key_behavior;

public Plugin myinfo =
{
	name		= "[NMRiH] Item Sharing",
	author		= "Dysphie",
	description = "Allows players to share items with teammates via right click",
	version		= "1.1.0",
	url			= "https://github.com/dysphie/nmrih-item-sharing"
};

public void OnClientPutInServer(int client)
{
	g_HasShareable[client] = false;
	g_WasPressingShare[client] = false;
	g_ArmIndex[client]	   = 0;
	g_ShareData[client].Init();
	QueryClientConVar(client, "cl_modelname", ModelNameQueryFinished);
	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch);
}

void ModelNameQueryFinished(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue)
{
	if (result != ConVarQuery_Okay)
	{
		return;
	}

	for (int i = 0; i < sizeof(g_ArmNames); i++)
	{
		if (StrEqual(cvarValue, g_ArmNames[i], false))
		{
			g_ArmIndex[client] = i;
			return;
		}
	}
}

public void OnPluginStart()
{
	sv_item_give = FindConVar("sv_item_give");

	// Old versions of the game require we detour CNMRiH_BaseMedicalItem::CanBeGiven
	if (!sv_item_give)
	{
		LoadGamedata();
	}

	g_Shareables = new StringMap();

	LoadTranslations("item-sharing.phrases");

	sm_item_sharing_keys = CreateConVar(
		"sm_item_sharing_keys", "3",
		"Keys that trigger item sharing. 1 = Secondary Attack, 2 = Drop, 3 = Both",
		_, true, 1.0, true, 3.0);

	sm_item_sharing_keys.AddChangeHook(OnTriggerKeysChanged);

	sm_item_sharing_enabled = CreateConVar(
		"sm_item_sharing_enabled", "1",
		"Enable or disable item sharing (1 = enabled, 0 = disabled)",
		_, true, 0.0, true, 1.0);

	sm_item_sharing_speed	   = CreateConVar("sm_item_sharing_speed", "2.0",
											  "Speed of the item sharing animation",
											  _, true, 0.1);

	// sm_item_share_key_behavior = CreateConVar("sm_item_share_key_behavior", "0",
	// 										  "Determines when the item sharing keystrokes will be consumed.\n" ... "0 = Only if the sharing was successful.\n" ... "1 = Always consume",
	// 										  _, true, 0.0, true, 1.0);

	sv_item_give_distance	   = FindConVar("sv_item_give_distance");

	AutoExecConfig();

	// Must be called "disable_team_share" for bcompat with old teamhealing plugin w/ same feature
	g_OptOutCookie = RegClientCookie("disable_team_share", "Disable item sharing", CookieAccess_Public);
	g_OptOutCookie.SetPrefabMenu(CookieMenu_YesNo_Int, "Toggle item sharing", CookieToggleMenu);
	LoadGivables();

	RegAdminCmd("sm_reload_shareable_items", Cmd_ReloadItems, ADMFLAG_GENERIC);

	// Lateload support
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			OnClientPutInServer(client);
			OnWeaponSwitch(client, GetActiveWeapon(client));
		}
	}
}

void OnTriggerKeysChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	CacheTriggerKeys();
}

public void OnConfigsExecuted()
{
	CacheTriggerKeys();
}

int	 g_KeyTriggers;

void CacheTriggerKeys()
{
	int value = sm_item_sharing_keys.IntValue;
	if (value & 1)
	{
		g_KeyTriggers |= IN_DROPWEAPON;
	}

	if (value & 2)
	{
		g_KeyTriggers |= IN_ATTACK2;
	}
}

void CookieToggleMenu(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	if (action == CookieMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlen, "%T", "Disable Item Sharing", client);
	}
}

void LoadGamedata()
{
	char	 filename[] = "item-sharing.games";

	GameData gamedata	= new GameData(filename);
	if (!gamedata)
	{
		SetFailState("Failed to find gamedata/%d", filename);
	}

	DynamicDetour detour = DynamicDetour.FromConf(gamedata, "CNMRiH_BaseMedicalItem::CanBeGiven");
	if (!detour)
		SetFailState("Failed to find signature CNMRiH_BaseMedicalItem::CanBeGiven");
	detour.Enable(Hook_Pre, Detour_CanMedicalBeGiven);

	delete detour;
	delete gamedata;
}

MRESReturn Detour_CanMedicalBeGiven(int item, DHookReturn ret, DHookParam params)
{
	if (sm_item_sharing_enabled.BoolValue)
	{
		ret.Value = false;
		return MRES_ChangedOverride;
	}

	return MRES_Ignored;
}

Action Cmd_ReloadItems(int client, int args)
{
	g_Shareables.Clear();
	LoadGivables();
	return Plugin_Handled;
}

void LoadGivables()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/item-sharing.cfg");

	KeyValues kv = new KeyValues("Items");

	if (!kv.ImportFromFile(path))
	{
		SetFailState("Failed to open %s", path);
	}

	if (!kv.GotoFirstSubKey(false))
	{
		delete kv;
		return;
	}

	char classname[32], giveSnd[256];

	do
	{
		kv.GetSectionName(classname, sizeof(classname));
		kv.GetString(NULL_STRING, giveSnd, sizeof(giveSnd));
		g_Shareables.SetString(classname, giveSnd);
	}
	while (kv.GotoNextKey(false));

	delete kv;

	PrintToServer(PREFIX... "Parsed %d shareable items", g_Shareables.Size);
}

public void OnMapStart()
{
	PrecacheModel(MDL_MEDICAL);
	PrecacheScriptSound(SND_GIVE_DEFAULT);

	StringMapSnapshot snap	  = g_Shareables.Snapshot();
	int				  snapLen = snap.Length;
	char			  key[32];
	char			  sound[256];

	for (int i; i < snapLen; i++)
	{
		snap.GetKey(i, key, sizeof(key));
		g_Shareables.GetString(key, sound, sizeof(sound));
		if (sound[0])
		{
			PrecacheScriptSound(sound);
		}
	}
}

void EmitItemSound(int client, const char[] soundEntry)
{
	char  soundPath[PLATFORM_MAX_PATH];
	int	  entity;
	int	  channel	  = SNDCHAN_AUTO;
	int	  sound_level = SNDLEVEL_NORMAL;
	float volume	  = SNDVOL_NORMAL;
	int	  pitch		  = SNDPITCH_NORMAL;
	GetGameSoundParams(soundEntry, channel, sound_level, volume, pitch, soundPath, sizeof(soundPath), entity);
	EmitSoundToAll(soundPath, client, channel, sound_level, SND_CHANGEVOL | SND_CHANGEPITCH, volume, pitch);
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	bool isPressingShare	   = (buttons & g_KeyTriggers) != 0;
	bool wasPressingShare	   = g_WasPressingShare[client];
	g_WasPressingShare[client] = isPressingShare;

	if (!isPressingShare || wasPressingShare)
	{
		return Plugin_Continue;
	}

	// Some code here

	if (!g_HasShareable[client])
	{
		return Plugin_Continue;
	}

	if (!sm_item_sharing_enabled.BoolValue)
	{
		return Plugin_Continue;
	}

	if (IsGivingItem(client))
	{
		return Plugin_Continue;
	}

	int activeWeapon = GetActiveWeapon(client);
	if (activeWeapon == -1)
	{
		return Plugin_Continue;
	}

	char classname[80];
	GetEntityClassname(activeWeapon, classname, sizeof(classname));

	if (!GetShareableData(classname))
	{
		return Plugin_Continue;
	}

	int target = GetClientUseTarget(client, sv_item_give_distance.FloatValue);
	if (target == -1)
	{
		return Plugin_Continue;
	}

	Action result = TestGiveAction(client, target, activeWeapon);

	if (result == Plugin_Handled)
	{
		buttons &= ~IN_ATTACK2;
		BeginGiveAction(client, target, activeWeapon);
		return Plugin_Changed;
	}

	// TODO: Perhaps consume the button if Plugin_Changed is returned (no client pred though)

	return Plugin_Continue;
}

void OnWeaponSwitch(int client, int weapon)
{
	if (weapon == -1)
	{
		return;
	}

	static char classname[80];
	GetEntityClassname(weapon, classname, sizeof(classname));
	g_HasShareable[client] = GetShareableData(classname);
}

void BeginGiveAction(int client, int recipient, int item)
{
	g_ShareData[client].Init();

	int viewmodel = GetEntPropEnt(client, Prop_Data, "m_hViewModel", 0);
	ToggleViewModel(client, false);

	// Create a fake item item and parent it to the real viewmodel
	int fakeItem = CreateFakeMedical();

	SetVariantString("!activator");
	AcceptEntityInput(fakeItem, "SetParent", viewmodel);

	TeleportEntity(fakeItem, { -8.00, -3.00, -3.00 }, { 0.0, 0.0, 0.0 });

	// Create fake arms and bone merge them to the fake item item
	int fakeArms = CreateFakeArms(g_ArmIndex[client]);
	SetVariantString("!activator");
	AcceptEntityInput(fakeArms, "SetAttached", fakeItem);
	SetVariantString("!activator");
	AcceptEntityInput(fakeArms, "TurnOn");

	float speedMultiplier = sm_item_sharing_speed.FloatValue;
	// Now animate the fake item item
	SetVariantString("Give");
	AcceptEntityInput(fakeItem, "SetAnimation");
	SetEntPropFloat(fakeItem, Prop_Send, "m_flPlaybackRate", speedMultiplier);

	float giveEndTime = GetGameTime() + MDL_GIVE_BASE_DURATION * speedMultiplier;

	SetEntPropFloat(item, Prop_Send, "m_flNextPrimaryAttack", giveEndTime);
	SetEntPropFloat(item, Prop_Send, "m_flNextSecondaryAttack", giveEndTime);

	SetEntityOwner(fakeItem, client);

	int itemRef							= EntIndexToEntRef(item);

	// Remember all this data for when we are done giving
	g_ShareData[client].fakeItemRef		= EntIndexToEntRef(fakeItem);
	g_ShareData[client].fakeArmsRef		= EntIndexToEntRef(fakeArms);
	g_ShareData[client].recipientSerial = GetClientSerial(recipient);
	g_ShareData[client].itemRef			= itemRef;
	g_ShareData[client].active			= true;

	// Set up a callback to get called when we are finished giving the item
	HookSingleEntityOutput(fakeItem, "OnAnimationDone", OnFakeViewModelFinishAnim, true);

	// Failsafe in case OnAnimationDone never fires to ensure proper cleanup
	CreateTimer(10.0, Timer_EndGiveAction, itemRef);

	// Hide our fake item for everyone but the player
	SDKHook(fakeItem, SDKHook_SetTransmit, HideFakeMedicalFromTeammates);

	// Make sound
	char classname[80];
	GetEntityClassname(item, classname, sizeof(classname));

	char giveSnd[PLATFORM_MAX_PATH];
	if (GetShareableData(classname, giveSnd, sizeof(giveSnd)))
	{
		EmitItemSound(client, giveSnd[0] ? giveSnd : SND_GIVE_DEFAULT);
	}
}

bool IsGivingItem(int client)
{
	return g_ShareData[client].active;
}

Action Timer_EndGiveAction(Handle timer, int itemRef)
{
	if (!IsValidEntity(itemRef))
	{
		return Plugin_Continue;
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (g_ShareData[client].itemRef == itemRef)
		{
			EndGiveAction(client);
			break;
		}
	}

	return Plugin_Continue;
}
bool GetShareableData(const char[] classname, char[] sound = "", int maxlen = 0)
{
	return g_Shareables.GetString(classname, sound, maxlen);
}

Action TestGiveAction(int client, int target, int item)
{
	if (!IsValidClient(client) || !IsValidClient(target))
	{
		return Plugin_Continue;
	}

	if (!IsPlayerAlive(target) || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	if (!IsValidEntity(item) || IsMedicalSpent(item) || GetActiveWeapon(client) != item)
	{
		return Plugin_Continue;
	}

	// Past this point we eat the input

	int weight = GetWeaponWeight(item);
	if (weight > 0 && !HasLeftoverWeight(target, weight))
	{
		PrintCenterText(client, "%t", "Target Is Full", target);
		return Plugin_Changed;
	}

	if (ClientOptedOutSharing(target))
	{
		PrintCenterText(client, "%t", "Target Opted Out", target);
		return Plugin_Changed;
	}

	char classname[80];
	GetEntityClassname(item, classname, sizeof(classname));

	if (FindWeapon(target, classname) != -1)
	{
		PrintCenterText(client, "%t", "Target Already Owns", target, client);
		return Plugin_Changed;
	}

	return Plugin_Handled;
}

int GetActiveWeapon(int client)
{
	return GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
}

bool IsValidClient(int client)
{
	return 0 < client <= MaxClients && IsClientInGame(client);
}

int CreateFakeMedical()
{
	int fakeItem = CreateEntityByName("prop_dynamic_override");
	if (fakeItem != -1)
	{
		DispatchKeyValue(fakeItem, "model", MDL_MEDICAL);
		DispatchKeyValue(fakeItem, "disablereceiveshadows", "1");
		DispatchKeyValue(fakeItem, "disableshadows", "1");
		DispatchKeyValue(fakeItem, "solid", "0");
		DispatchSpawn(fakeItem);
	}

	return fakeItem;
}

int CreateFakeArms(int armsIndex)
{
	// Spawn fake hands and bonemerge them to our fake weapon
	int fakeArms = CreateEntityByName("prop_dynamic_ornament");
	if (fakeArms != -1)
	{
		// DispatchKeyValue(fakeArms, "targetname", "hands");
		char modelName[PLATFORM_MAX_PATH];
		FormatEx(modelName, sizeof(modelName), "models/arms/c_%s_arms.mdl", g_ArmNames[armsIndex]);
		DispatchKeyValue(fakeArms, "model", modelName);
		DispatchKeyValue(fakeArms, "disablereceiveshadows", "1");
		DispatchKeyValue(fakeArms, "disableshadows", "1");
		DispatchKeyValue(fakeArms, "solid", "0");
		DispatchSpawn(fakeArms);
	}

	return fakeArms;
}

void RemoveEntityByRef(int entRef)
{
	if (entRef && IsValidEntity(entRef))
	{
		RemoveEntity(entRef);
	}
}

Action HideFakeMedicalFromTeammates(int entity, int client)
{
	return GetEntityOwner(entity) == client ? Plugin_Continue : Plugin_Handled;
}

int GetEntityOwner(int entity)
{
	return GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
}

void OnFakeViewModelFinishAnim(const char[] output, int fakeItem, int activator, float delay)
{
	// Item sharing just finished, find out who caused it
	int owner = GetEntityOwner(fakeItem);
	if (owner != -1)
	{
		CompleteGiveAction(owner);
	}
}

bool IsMedicalSpent(int item)
{
	return HasEntProp(item, Prop_Send, "_applied") && GetEntProp(item, Prop_Send, "_applied") != 0;
}

void CompleteGiveAction(int client)
{
	int	   recipient = GetClientFromSerial(g_ShareData[client].recipientSerial);
	int	   item		 = EntRefToEntIndex(g_ShareData[client].itemRef);

	// The most important part
	Action result	 = TestGiveAction(client, recipient, item);
	if (result == Plugin_Handled)
	{
		float recipientPos[3];
		GetClientEyePosition(recipient, recipientPos);
		SDKHooks_DropWeapon(client, item, recipientPos);
		AcceptEntityInput(item, "Use", recipient, recipient);

		TryVoiceCommand(recipient, VOICECMD_THANKS);

		// FIXME: Calculate nextattack based on playback rate
		SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime() + 0.84);

		char itemPhrase[128];
		GetEntityClassname(item, itemPhrase, sizeof(itemPhrase));

		if (!TranslationPhraseExists(itemPhrase))
		{
			strcopy(itemPhrase, sizeof(itemPhrase), "Unknown Item");
		}

		PrintCenterText(recipient, "%t", "Received Item", client, itemPhrase, recipient);
		PrintCenterText(client, "%t", "Gave Item", recipient, itemPhrase, client);
	}

	EndGiveAction(client);
}

// void ReDrawWeapon(int client)
// {
// 	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
// 	char classname[32];
// 	GetEntityClassname(activeWeapon, classname, sizeof(classname));

// 	if (!StrEqual(classname, "me_fists") && !StrEqual(classname, "item_zippo"))
// 	{
// 		SDKHooks_DropWeapon(client, activeWeapon);
// 		AcceptEntityInput(activeWeapon, "Use", client, client);
// 	}
// }

void ToggleViewModel(int client, bool state)
{
	SetEntProp(client, Prop_Send, "m_bDrawViewmodel", state);
}

void EndGiveAction(int client)
{
	RemoveEntityByRef(g_ShareData[client].fakeItemRef);
	RemoveEntityByRef(g_ShareData[client].fakeArmsRef);
	ToggleViewModel(client, true);
	g_ShareData[client].Init();
}

int GetClientUseTarget(int client, float range)
{
	float hullAng[3], hullStart[3], hullEnd[3];
	GetClientEyeAngles(client, hullAng);

	GetClientEyePosition(client, hullStart);
	ForwardVector(hullStart, hullAng, range, hullEnd);

	TR_TraceRayFilter(hullStart, hullEnd, CONTENTS_SOLID, RayType_EndPoint, TR_AlivePlayers, client);

	bool didHit = TR_DidHit();
	if (!didHit)
	{
		float mins[3] = { -10.0, -10.0, -10.0 };
		float maxs[3] = { 10.0, 10.0, 10.0 };

		TR_TraceHullFilter(hullStart, hullEnd, mins, maxs, CONTENTS_SOLID, TR_AlivePlayers, client);
		didHit = TR_DidHit();
	}

	int hitEnt = TR_GetEntityIndex();
	return hitEnt > 0 ? hitEnt : -1;
}

bool TR_AlivePlayers(int entity, int mask, int client)
{
	return entity != client && 0 < entity <= MaxClients && IsPlayerAlive(entity);
}

void ForwardVector(const float vPos[3], const float vAng[3], float fDistance, float vReturn[3])
{
	float vDir[3];
	GetAngleVectors(vAng, vDir, NULL_VECTOR, NULL_VECTOR);
	vReturn = vPos;
	vReturn[0] += vDir[0] * fDistance;
	vReturn[1] += vDir[1] * fDistance;
	vReturn[2] += vDir[2] * fDistance;
}

void TryVoiceCommand(int client, int voice)
{
	if (!IsVoiceCommandTimerExpired(client))
	{
		return;
	}

	float origin[3];
	GetClientAbsOrigin(client, origin);

	TE_Start("TEVoiceCommand");
	TE_WriteNum("_playerIndex", client);
	TE_WriteNum("_voiceCommand", view_as<int>(voice));
	TE_SendToAllInRange(origin, RangeType_Audibility);
}

bool IsVoiceCommandTimerExpired(int client)
{
	return RunEntVScriptBool(client, "IsVoiceCommandTimerExpired()");
}

bool ClientOptedOutSharing(int client)
{
	char value[12];
	g_OptOutCookie.Get(client, value, sizeof(value));
	return StrEqual(value, "1");
}

int FindWeapon(int client, const char[] classname)
{
	char buffer[32];

	int	 maxWeapons = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	for (int i; i < maxWeapons; i++)
	{
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if (weapon != -1)
		{
			GetEntityClassname(weapon, buffer, sizeof(buffer));
			if (StrEqual(classname, buffer))
			{
				return weapon;
			}
		}
	}

	return -1;
}

int GetWeaponWeight(int weapon)
{
	return RunEntVScriptInt(weapon, "GetWeight()");
}

bool HasLeftoverWeight(int client, int weight)
{
	char code[32];
	FormatEx(code, sizeof(code), "HasLeftoverWeight(%d)", weight);
	return RunEntVScriptBool(client, code);
}