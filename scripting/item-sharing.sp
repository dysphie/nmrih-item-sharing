#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <vscript_proxy>

#pragma semicolon 1
#pragma newdecls required

#define PREFIX "[Item Sharing] "

#define VOICECMD_THANKS 5

#define MAXPLAYERS_NMRIH 9
#define SND_GIVE_DEFAULT "weapon_db.GenericFoley"
#define MDL_FAKE_VM "models/items/firstaid/v_item_firstaid.mdl"

public Plugin myinfo = 
{	
	name        = "[NMRiH] Item Sharing",
	author      = "Dysphie",
	description = "Allows players to share items with teammates via right click",
	version     = "1.0.0",
	url         = "https://github.com/dysphie/nmrih-item-sharing"
};

Cookie optOutCookie;
StringMap givables;
bool didAttemptLastTick[MAXPLAYERS_NMRIH+1];
int fakeVM[MAXPLAYERS_NMRIH+1] = {-1, ...};
ConVar cvEnable;

public void OnPluginStart()
{
	givables = new StringMap();

	LoadTranslations("core.phrases");
	LoadTranslations("item-sharing.phrases");

	cvEnable = CreateConVar("sm_item_sharing_enabled", "1", "Toggle item sharing on or off");
	AutoExecConfig();

	// Must be called "disable_team_share" for bcompat with old teamhealing plugin w/ same feature
	optOutCookie = RegClientCookie("disable_team_share", "Disable item sharing", CookieAccess_Public);
	optOutCookie.SetPrefabMenu(CookieMenu_YesNo_Int, "Toggle item sharing", CookieToggleMenu);
	LoadGivables();

	RegAdminCmd("sm_reload_shareable_items", Cmd_ReloadItems, ADMFLAG_GENERIC);
}

void CookieToggleMenu(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	if (action == CookieMenuAction_DisplayOption) {
		FormatEx(buffer, maxlen, "%T", "Disable Item Sharing", client);	
	}
}

Action Cmd_ReloadItems(int client, int args)
{
	givables.Clear();
	LoadGivables();
	return Plugin_Handled;
}

void LoadGivables()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/item-sharing.cfg");

	KeyValues kv = new KeyValues("Items");

	if (!kv.ImportFromFile(path)) {
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
		givables.SetString(classname, giveSnd);
	}
	while (kv.GotoNextKey(false));
	delete kv;

	PrintToServer(PREFIX ... "Parsed %d shareable items", givables.Size);
}

public void OnMapStart()
{
	PrecacheModel(MDL_FAKE_VM);
	PrecacheScriptSound(SND_GIVE_DEFAULT);

	StringMapSnapshot snap = givables.Snapshot();
	int snapLen = snap.Length;
	char key[32];
	char sound[256];

	for (int i; i < snapLen; i++)
	{
		snap.GetKey(i, key, sizeof(key));
		givables.GetString(key, sound, sizeof(sound));
		if (sound[0]) {
			PrecacheScriptSound(sound);
		}
	}
}

void EmitItemSound(int client, const char[] soundEntry)
{
	char soundPath[PLATFORM_MAX_PATH];

	int entity;
	int channel = SNDCHAN_AUTO;
	int sound_level = SNDLEVEL_NORMAL;
	float volume = SNDVOL_NORMAL;
	int pitch = SNDPITCH_NORMAL;

	GetGameSoundParams(soundEntry[0] ? soundEntry : SND_GIVE_DEFAULT, 
		channel, sound_level, volume, pitch, soundPath, sizeof(soundPath), entity);

	EmitSoundToAll(soundPath, client, channel, sound_level, SND_CHANGEVOL | SND_CHANGEPITCH, volume, pitch);
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if (!(buttons & IN_ATTACK2)) {
		didAttemptLastTick[client] = false;
		return Plugin_Continue;
	}

	if (didAttemptLastTick[client]) {
		return Plugin_Continue;
	}

	didAttemptLastTick[client] = true;
	
	if (!cvEnable.BoolValue) {
		return Plugin_Continue;
	}

	if (!IsPlayerAlive(client)) {
		return Plugin_Continue;
	}

	if (ClientOptedOutSharing(client)) {
		return Plugin_Continue;
	}

	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (activeWeapon == -1 || !IsWeaponIdle(activeWeapon)) {
		return Plugin_Continue;
	}

	// Client is already in the process of sharing an item
	if (IsGivingItem(client)) {
		return Plugin_Continue;
	}

	char classname[32];
	GetEntityClassname(activeWeapon, classname, sizeof(classname));

	char giveSnd[256];
	if (!givables.GetString(classname, giveSnd, sizeof(giveSnd))) {
		return Plugin_Continue;
	}

	// We always eat input for built-in medical 
	if (HasEntProp(activeWeapon, Prop_Send, "m_bGiven"))
		buttons &= ~IN_ATTACK2;

	int target = GetClientUseTarget(client, 75.0);
	if (target == -1) {
		return Plugin_Continue;
	}

	if (!IsPlayerAlive(target)) {
		return Plugin_Continue;
	}

	// Past this point we always eat the input 
	buttons &= ~IN_ATTACK2;

	if (ClientOptedOutSharing(target))
	{
		PrintCenterText(client, "%t", "Target Opted Out", target);
		return Plugin_Continue;
	}

	if (!HasLeftoverWeight(target, GetWeaponWeight(activeWeapon)))
	{
		PrintCenterText(client, "%t", "Target Is Full", target);
		return Plugin_Continue;
	}

	if (FindWeapon(target, classname) != -1)
	{
		PrintCenterText(client, "%t", "Target Already Owns", target, client);
		return Plugin_Continue;
	}

	float targetPos[3];
	GetClientEyePosition(target, targetPos);
	SDKHooks_DropWeapon(client, activeWeapon, targetPos);
	AcceptEntityInput(activeWeapon, "Use", target, target);

	DoMedicalAnimation(client);
	TryVoiceCommand(target, VOICECMD_THANKS);

	// TODO: Don't hardcode the duration of the give animation
	SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime() + 0.84);

	EmitItemSound(client, giveSnd);

	// Eat input since we used it
	buttons &= ~IN_ATTACK2;
	
	if (!TranslationPhraseExists(classname)) {
		strcopy(classname, sizeof(classname), "Unknown Item");
	}

	PrintCenterText(target, "%t", "Received Item", client, classname, target);
	PrintCenterText(client, "%t", "Gave Item", target, classname, client);	
	
	return Plugin_Continue;
}

void DoMedicalAnimation(int client)
{
	SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 0);

	int prop = CreateEntityByName("prop_dynamic_override");

	DispatchKeyValue(prop, "model", MDL_FAKE_VM);
	DispatchKeyValue(prop, "disablereceiveshadows", "1");
	DispatchKeyValue(prop, "disableshadows", "1");
	DispatchKeyValue(prop, "solid", "0");
	DispatchSpawn(prop);

	SetEntityMoveType(prop, MOVETYPE_NONE);
	int viewmodel = GetEntPropEnt(client, Prop_Data, "m_hViewModel", 0);

	float pos[3], ang[3];
	GetEntPropVector(viewmodel, Prop_Data, "m_vecAbsOrigin", pos);
	GetEntPropVector(viewmodel, Prop_Data, "m_angAbsRotation", ang);
	TeleportEntity(prop, pos, ang);

	SetVariantString("!activator");
	AcceptEntityInput(prop, "SetParent", viewmodel);

	// Bring inwards a little bit else the FOV looks weird
	TeleportEntity(prop, {-2.00, 0.00, 0.00});

	SetVariantString("Give");
	AcceptEntityInput(prop, "SetAnimation");
	SetEntPropFloat(prop, Prop_Send, "m_flPlaybackRate", 2.0); // Faster!
	SetEntPropEnt(prop, Prop_Send, "m_hOwnerEntity", client);

	// Remove prop when animation ends
	HookSingleEntityOutput(prop, "OnAnimationDone", OnFakeViewModelFinishAnim, true);

	SDKHook(prop, SDKHook_SetTransmit, FakeVMTransmit);

	fakeVM[client] = EntIndexToEntRef(prop);

	// Also remove after 2 seconds in case the above callback doesn't fire somehow
	CreateTimer(2.0, RemoveFakeViewModel, EntIndexToEntRef(prop), TIMER_FLAG_NO_MAPCHANGE);
}

Action RemoveFakeViewModel(Handle timer, int vmRef)
{
	if (IsValidEntity(vmRef)) {
		RemoveEntity(vmRef);
	}
	return Plugin_Continue;
}

Action FakeVMTransmit(int entity, int client)
{
	if (EntIndexToEntRef(entity) != fakeVM[client]) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

void OnFakeViewModelFinishAnim(const char[] output, int caller, int activator, float delay) 
{
	int client = GetEntPropEnt(caller, Prop_Send, "m_hOwnerEntity");
	if (client != -1)
	{
		RemoveEntity(caller);
		SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 1);

		// Force client to redraw their weapon
		ReDrawWeapon(client);
	}
}

void ReDrawWeapon(int client)
{
	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	char classname[32];
	GetEntityClassname(activeWeapon, classname, sizeof(classname));

	if (!StrEqual(classname, "me_fists") && !StrEqual(classname, "item_zippo"))
	{
		SDKHooks_DropWeapon(client, activeWeapon);
		AcceptEntityInput(activeWeapon, "Use", client, client);
	}	
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
		float maxs[3] = {  10.0,  10.0,  10.0 };

		TR_TraceHullFilter(hullStart, hullEnd, mins, maxs, CONTENTS_SOLID, TR_AlivePlayers, client);
		didHit = TR_DidHit();

		// Box(hullStart, mins, maxs);
		// Box(hullEnd, mins, maxs);
		// Line(hullStart, hullEnd);
	}

	if (didHit)
	{
		int entity = TR_GetEntityIndex();
		if (entity > 0) {
			return entity;
		}
	}
	return -1;
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
	if (!IsVoiceCommandTimerExpired(client)) {
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
	if (!AreClientCookiesCached(client)) {
		return false; // assume not
	}

	char c[2];
	optOutCookie.Get(client, c, sizeof(c));
	return c[0] == '1';
}

int FindWeapon(int client, const char[] classname) 
{
	char buffer[32];

	int maxWeapons = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	for (int i; i < maxWeapons; i++)
	{
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if (weapon != -1)
		{
			GetEntityClassname(weapon, buffer, sizeof(buffer));
			if (StrEqual(classname, buffer)) {
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
	return RunEntVScriptBool(client, "HasLeftoverWeight(%d)", weight);
}

bool IsWeaponIdle(int weapon)
{
	float curTime = GetGameTime();
	return GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack") < curTime &&
		GetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack") < curTime;
}

bool IsGivingItem(int client)
{
	return IsValidEntity(fakeVM[client]);
}