#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <insurgency>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
		name			= "[INS] Medic",
		author		  = "rrrfffrrr",
		description	 = "Make player medic",
		version		 = "2.0.0",
		url			 = ""
};

#define TEAM_SPECTATE 1
#define TEAM_SECURITY 2
#define TEAM_INSURGENT 3

Handle cGameConfig;
Handle fForceRespawn;

ConVar CvarAnnounceNewMedic;
ConVar CvarMedicClass;
ConVar CvarMedicReviveItem;

ConVar CvarMaxReviveCount;
ConVar CvarMaxDistanceToRevive;
ConVar CvarRevivingTime;
ConVar CvarCooldown;

ConVar CvarScoreWhenRevive;
ConVar CvarTokenWhenRevive;
ConVar CvarTokenWhenReviveCount;

ConVar CvarSoulSize;
ConVar CvarSoulColorR;
ConVar CvarSoulColorG;
ConVar CvarSoulColorB;
ConVar CvarSoulSprite;

ConVar CvarDisplayDelay;
Handle tTick;

#define ENT_NONE -1
int entSprite[MAXPLAYERS + 1];

// optimize strings
#define MAX_NUMBER_OF_CLASS 10
#define MAX_CLASS_NAME_LENGTH 64
int iNumOfClass;
char sMedicClass[MAX_NUMBER_OF_CLASS][MAX_CLASS_NAME_LENGTH];

#define MAX_NUMBER_OF_ITEM 10
#define MAX_ITEM_NAME_LENGTH 64
int iNumOfItem;
char sMedicReviveItem[MAX_NUMBER_OF_ITEM][MAX_ITEM_NAME_LENGTH];

int iRevivePoint[MAXPLAYERS + 1];
int iRevivingMedic[MAXPLAYERS + 1];
bool bIsMedic[MAXPLAYERS + 1];
Handle hReviveTimer[MAXPLAYERS + 1];
float flStartRevivingTime[MAXPLAYERS + 1];
float vecDeadPosition[MAXPLAYERS + 1][3];

Handle hMedicCooldown[MAXPLAYERS + 1];
int iScore[MAXPLAYERS + 1];
int iReviveCount[MAXPLAYERS + 1];

public void OnPluginStart() {
	InitSDKCalls();
	InitCvars();
	HookCvars();
	HookEvents();
	iNumOfClass = ExplodeString("breacher bomber", " ", sMedicClass, MAX_NUMBER_OF_CLASS, MAX_CLASS_NAME_LENGTH);
	iNumOfItem = ExplodeString("kabar gurkha", " ", sMedicReviveItem, MAX_NUMBER_OF_ITEM, MAX_ITEM_NAME_LENGTH);

	UpdateTickTimer();
}
public void OnPluginEnd() {
	for(int i = 1; i <= MaxClients; ++i) {
		DestroySprite(entSprite[i]);
	}
}

public void OnMapStart() {
	tTick = INVALID_HANDLE;
	UpdateTickTimer();

	for(int i = 1; i <= MaxClients; ++i) {
		iScore[i] = 0;
		entSprite[i] = CreateSprite();
		HideSprite(entSprite[i]);
		hReviveTimer[i] = INVALID_HANDLE;
		hMedicCooldown[i] = INVALID_HANDLE;
		iReviveCount[i] = 0;
	}

	SDKHook(GetPlayerResourceEntity(), SDKHook_ThinkPost, OnPlayerResourceThinkPost);
}
public void OnMapEnd() {
	for(int i = 1; i <= MaxClients; ++i) {
		DestroySprite(entSprite[i]);
	}
}

public void OnClientPutInServer(int client) {
	bIsMedic[client] = false;
	hReviveTimer[client] = INVALID_HANDLE;
	hMedicCooldown[client] = INVALID_HANDLE;
	iScore[client] = 0;
	vecDeadPosition[client][0] = vecDeadPosition[client][1] = vecDeadPosition[client][2] = 0.0;
	if (IsValidPlayer(client)) {
		SDKHook(client, SDKHook_WeaponSwitchPost, OnPostWeaponSwitch);
	}
}

public void OnClientDisconnect_Post(int client) {
	if (IsReviving(client))
		AbortRevive(client);
	if (IsCooldown(client))
		StopCooldown(client);

	int target = FindPatientByMedic(client);
	if (target != -1)
		AbortRevive(target);
}

void InitSDKCalls() {
	cGameConfig = LoadGameConfigFile("insurgency.games");
	if (cGameConfig == INVALID_HANDLE) {
		SetFailState("Fatal Error: Missing File \"insurgency.games\"!");
	}

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(cGameConfig, SDKConf_Virtual, "CINSPlayer::ForceRespawn");
	fForceRespawn = EndPrepSDKCall();
	if (fForceRespawn == INVALID_HANDLE) {
		SetFailState("Fatal Error: Unable to find ForceRespawn");
	}
}
void InitCvars() {
	CvarAnnounceNewMedic = CreateConVar("sm_medic_announce", "1", "Announce new medic.", FCVAR_NOTIFY);

	CvarMedicClass = CreateConVar("sm_medic_class", "breacher bomber", "Class name of Medic", FCVAR_NOTIFY);
	CvarMedicReviveItem = CreateConVar("sm_medic_revive_item", "kabar gurkha", "Weapon to revive", FCVAR_NOTIFY);
	CvarMaxReviveCount = CreateConVar("sm_medic_revive_count", "8", "Max revive count", FCVAR_NOTIFY);
	CvarMaxDistanceToRevive = CreateConVar("sm_medic_revive_distance", "100", "Maxinum distance to revive", FCVAR_NOTIFY);
	CvarRevivingTime = CreateConVar("sm_medic_revive_delay", "10", "Delay for revive in seconds", FCVAR_NOTIFY);
	CvarCooldown = CreateConVar("sm_medic_cooltime", "30", "Delay before next revive", FCVAR_NOTIFY);

	CvarScoreWhenRevive = CreateConVar("sm_medic_score", "50", "Get score when success to revive somone", FCVAR_NOTIFY, true, 0.0);
	CvarTokenWhenRevive = CreateConVar("sm_medic_token", "0", "Get token when success to revive somone", FCVAR_NOTIFY, true, 0.0);
	CvarTokenWhenReviveCount = CreateConVar("sm_medic_token_count", "10", "Number of revive count to recive token.", FCVAR_NOTIFY, true, 1.0);

	CvarSoulSize = CreateConVar("sm_medic_soul_size", "1.0", "Size of soul to draw", FCVAR_NOTIFY);
	CvarSoulColorR = CreateConVar("sm_medic_soul_color_r", "255", "Red color of soul to draw", FCVAR_NOTIFY, true, 0.0, true, 255.0);
	CvarSoulColorG = CreateConVar("sm_medic_soul_color_g", "255", "Green color of soul to draw", FCVAR_NOTIFY, true, 0.0, true, 255.0);
	CvarSoulColorB = CreateConVar("sm_medic_soul_color_b", "255", "Blue color of soul to draw", FCVAR_NOTIFY, true, 0.0, true, 255.0);
	CvarSoulSprite = CreateConVar("sm_medic_soul_sprite", "fire.vmt", "Sprite of soul to draw", FCVAR_NOTIFY);

	CvarDisplayDelay = CreateConVar("sm_medic_tick", "20", "Number of tick per 1 second", FCVAR_NOTIFY);
}
void HookCvars() {
	HookConVarChange(CvarMedicClass, OnChangeClass);
	HookConVarChange(CvarMedicReviveItem, OnChangeItem);
	HookConVarChange(CvarDisplayDelay, UpdateCvarTick);
}
void HookEvents() {
	HookEvent("player_pick_squad", Event_PlayerPickSquad);
	HookEvent("weapon_fire", Event_WeaponFired);

	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);

	HookEvent("controlpoint_captured", Event_Captured);
	HookEvent("object_destroyed", Event_Captured);
	HookEvent("round_start", Event_Captured);
	HookEvent("round_begin", Event_Captured);
}

// Display
void UpdateCvarTick(Handle cvar, const char[] oldValue, const char[] newValue) {
	UpdateTickTimer();
}

void UpdateTickTimer() {
	if (tTick != INVALID_HANDLE) {
		KillTimer(tTick);
	}

	tTick = CreateTimer(1.0 / CvarDisplayDelay.FloatValue, Timer_Tick,_, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_Tick(Handle timer) {
	OnReviveTick();
	return Plugin_Continue;
}

// Hooks
void OnChangeClass(ConVar convar, const char[] oldValue, const char[] newValue) {
	iNumOfClass = ExplodeString(newValue, " ", sMedicClass, MAX_NUMBER_OF_CLASS, MAX_CLASS_NAME_LENGTH);
}
void OnChangeItem(ConVar convar, const char[] oldValue, const char[] newValue) {
	iNumOfItem = ExplodeString(newValue, " ", sMedicReviveItem, MAX_NUMBER_OF_ITEM, MAX_ITEM_NAME_LENGTH);
}
Action Event_PlayerPickSquad(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidPlayer(client))
		return Plugin_Continue;
	char class_template[MAX_CLASS_NAME_LENGTH];
	GetEventString(event, "class_template", class_template, sizeof(class_template));
	if(strlen(class_template) < 1)
		return Plugin_Continue;

	bIsMedic[client] = false;

	if (StrContainsFromArray(sMedicClass, iNumOfClass, class_template, false) != -1) {
		bIsMedic[client] = true;
		if (CvarAnnounceNewMedic.BoolValue) {
			char cname[64];
			GetClientName(client, cname, sizeof(cname));
			PrintCenterTextAll("%s is now medic.", cname);
		}
	}
	return Plugin_Continue;
}

Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	OnSpawn(client);

	if (IsReviving(client)) {
		AbortRevive(client);
	}

	return Plugin_Continue;
}

Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsClientInGame(client) && !IsFakeClient(client) && (GetClientTeam(client) == TEAM_SECURITY || GetClientTeam(client) == TEAM_INSURGENT)) {
		GetClientAbsOrigin(client, vecDeadPosition[client]);

		vecDeadPosition[client][2] += 50.0;
		TeleportEntity(entSprite[client], vecDeadPosition[client], NULL_VECTOR, NULL_VECTOR);
		vecDeadPosition[client][2] -= 50.0;

		ShowSprite(entSprite[client]);

		int target = FindPatientByMedic(client);
		if (target != -1) {
			AbortRevive(target);
		}
	}
	return Plugin_Continue;
}

Action Event_WeaponFired(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	char weapon_name[MAX_ITEM_NAME_LENGTH];
	GetClientWeapon(client, weapon_name, MAX_ITEM_NAME_LENGTH);

	if (!IsValidPlayer(client) || -1 == StrContainsFromArray(sMedicReviveItem, iNumOfItem, weapon_name, false) || !bIsMedic[client]) {
		return Plugin_Continue;
	}
	
	TryRevive(client);

	return Plugin_Continue;
}

Action Event_Captured(Event event, const char[] name, bool dontBroadcast) {
	for(int i = 1; i <= MaxClients; ++i) {
		if (IsValidPlayer(i) && bIsMedic[i])
			ResupplyToken(i);
		else
			iRevivePoint[i] = 0;
	}
	return Plugin_Continue;
}

void OnPostWeaponSwitch(int client, int weapon) {
	int target = FindPatientByMedic(client);
	if (target != -1)
		AbortRevive(target);
}

// revive
void OnReviveTick() {
	char name1[64];
	char name2[64];
	int medic;
	float eye[3];
	float time = GetGameTime();
	int remain;
	for(int i = 1; i <= MaxClients; i++) {
		if (IsValidPlayer(i)) {
			if (IsPlayerAlive(i)) {
				
			} else if (IsReviving(i)) {
				medic = iRevivingMedic[i];
				if (!IsValidPlayer(medic) || !IsPlayerAlive(medic)) {
					AbortRevive(i);
					continue;
				}

				GetClientEyePosition(medic, eye);
				if (GetVectorDistance(vecDeadPosition[i], eye, false) > CvarMaxDistanceToRevive.FloatValue) {
					AbortRevive(i);
					continue;
				}

				remain = RoundToNearest(100.0 * (time - flStartRevivingTime[i]) / CvarRevivingTime.FloatValue);
				GetClientName(i, name1, sizeof(name1));
				GetClientName(medic, name2, sizeof(name2));
				PrintCenterText(i, "%s is reviving you. %d\%", name2, remain);
				PrintCenterText(medic, "You reviving %s. %d\%", name1, remain);
			}
		}
	}
}

void OnSpawn(int client) {
	HideSprite(entSprite[client]);
}

void OnReviveSuccess(int client) {	// give reward here
	iScore[client] += CvarScoreWhenRevive.IntValue;
	iReviveCount[client]++;
	if (iReviveCount[client] == CvarTokenWhenReviveCount.IntValue) {
		int token = CvarTokenWhenRevive.IntValue;
		if (token > 0)
			AddToken(client, token);
		iReviveCount[client] = 0;
	}
}

void ResupplyToken(int client) {
	iRevivePoint[client] = CvarMaxReviveCount.IntValue;
}

void TryRevive(int client) {
	int target = FindPatientByMedic(client);
	if (target != -1)
		return;

	if (iRevivePoint[client] < 1) {
		PrintCenterText(client, "No more revive available.");
		return;
	}

	target = FindNearDeathPlayer(client);
	if (target == -1) {
		PrintCenterText(client, "No player detected.");
		return;
	}

	StartRevive(client, target);
}

void StartRevive(int client, int target) {
	if (!IsValidPlayer(client) || !IsValidPlayer(target) || IsReviving(target) || IsFakeClient(target))
		return;

	iRevivingMedic[target] = client;
	flStartRevivingTime[target] = GetGameTime();
	hReviveTimer[target] = CreateTimer(CvarRevivingTime.FloatValue, Timer_Revive, target, TIMER_FLAG_NO_MAPCHANGE);
}

int FindPatientByMedic(int client) {
	for(int i = 1; i <= MaxClients; ++i) {
		if (client == iRevivingMedic[i] && IsReviving(i)) {
			return i;
		}
	}
	return -1;
}

void AbortRevive(int client) {
	if (hReviveTimer[client] != INVALID_HANDLE) {
		KillTimer(hReviveTimer[client]);
		hReviveTimer[client] = INVALID_HANDLE;
		PrintCenterText(client, "");
		PrintCenterText(iRevivingMedic[client], "Reviving aborted.");
	}
}

int FindNearDeathPlayer(int client) {
	float pos[3];
	GetClientEyePosition(client, pos);
	int team = GetClientTeam(client);

	for(int i = 1; i <= MaxClients; ++i) {
		if (IsValidPlayer(i) && team == GetClientTeam(i) && !IsPlayerAlive(i) && !IsReviving(i) && GetVectorDistance(pos, vecDeadPosition[i], false) <= CvarMaxDistanceToRevive.FloatValue)
			return i;
	}

	return -1;
}

bool IsReviving(int client) {
	return hReviveTimer[client] != INVALID_HANDLE;
}

Action Timer_Revive(Handle timer, int target) {
	if (!IsValidPlayer(target) || IsPlayerAlive(target))
		return Plugin_Continue;
	int medic = iRevivingMedic[target];
	if (!IsValidPlayer(medic) || !IsPlayerAlive(medic))
		return Plugin_Continue;

	RemoveRagdoll(target);

	hReviveTimer[target] = INVALID_HANDLE;
	SDKCall(fForceRespawn, target);
	TeleportEntity(target, vecDeadPosition[target], NULL_VECTOR, NULL_VECTOR);
	OnReviveSuccess(medic);
	StartCooldown(medic);
	HideSprite(entSprite[target]);

	char name1[64];
	char name2[64];
	GetClientName(target, name1, sizeof(name1));
	GetClientName(medic, name2, sizeof(name2));
	PrintCenterText(target, "You are revived by %s.", name2);
	iRevivePoint[medic]--;
	PrintCenterText(medic, "You revived %s. %d remain.", name1, iRevivePoint[medic]);

	return Plugin_Continue;
}

// cooltime
void StartCooldown(int client) {
	if (!IsValidPlayer(client))
		return;

	if (hMedicCooldown[client] == INVALID_HANDLE) {
		hMedicCooldown[client] = CreateTimer(CvarCooldown.FloatValue, Timer_Cooldown, client, TIMER_FLAG_NO_MAPCHANGE);
	}
}

void StopCooldown(int client) {
	if (!IsValidPlayer(client))
		return;

	if (IsCooldown(client)) {
		KillTimer(hMedicCooldown[client]);
	}

	hMedicCooldown[client] = INVALID_HANDLE;
}

bool IsCooldown(int client) {
	if (!IsValidPlayer(client))
		return false;
	
	return hMedicCooldown[client] != INVALID_HANDLE;
}

Action Timer_Cooldown(Handle timer, int client) {
	hMedicCooldown[client] = INVALID_HANDLE;
	return Plugin_Continue;
}

// set score
void OnPlayerResourceThinkPost(int entity) {
	int offset = FindSendPropInfo("CINSPlayerResource", "m_iPlayerScore");
	int iTotalScore[MAXPLAYERS];

	GetEntDataArray(entity, offset, iTotalScore, MAXPLAYERS);

	for(int i = 1; i < MAXPLAYERS; ++i) {
		if (IsValidPlayer(i) && iScore[i] > 0) {
			iTotalScore[i] += iScore[i];
		}
	}

	SetEntDataArray(entity, offset, iTotalScore, MAXPLAYERS);
}

// soul Sprite
int CreateSprite() {
	int ent = CreateEntityByName("env_sprite");
	if (IsValidEdict(ent)) {
		char param[64];
		CvarSoulSprite.GetString(param, sizeof(param));
		DispatchKeyValue(ent, "model", param);
		DispatchKeyValue(ent, "classname", "env_sprite");
		DispatchKeyValue(ent, "spawnflags", "1");
		DispatchKeyValue(ent, "scale", "1");
		DispatchKeyValue(ent, "rendermode", "1");
		DispatchKeyValue(ent, "renderamt", "75");
		DispatchKeyValue(ent, "rendercolor", "255 255 255");

		DispatchSpawn(ent);
		ActivateEntity(ent);
		SetVariantFloat(CvarSoulSize.FloatValue);
		AcceptEntityInput(ent, "SetScale");
		SetVariantFloat(CvarSoulColorR.FloatValue);
		AcceptEntityInput(ent, "ColorRedValue");
		SetVariantFloat(CvarSoulColorG.FloatValue);
		AcceptEntityInput(ent, "ColorGreenValue");
		SetVariantFloat(CvarSoulColorB.FloatValue);
		AcceptEntityInput(ent, "ColorBlueValue");
	} else {
		ent = ENT_NONE;
	}

	return ent;
}

void DestroySprite(int entity) {
	if (IsValidEdict(entity)) {
		AcceptEntityInput(entity, "Deactivate");
		AcceptEntityInput(entity, "Kill");
	}
}

void ShowSprite(int entity) {
	if (IsValidEdict(entity)) {
		AcceptEntityInput(entity, "ShowSprite"); 
	}
}

void HideSprite(int entity) {
	if (IsValidEdict(entity)) {
		AcceptEntityInput(entity, "HideSprite"); 
	}
}

// Utils
bool IsValidPlayer(int client) {
	if (client < 1 || client > MaxClients)
		return false;

	if (!IsClientInGame(client))
		return false;

	return true;
}

int StrContainsFromArray(const char[][] str, int numofstr, const char[] substr, bool caseSensitive = true) {
	for (int i = 0; i < numofstr; i++) {
		if (StrContains(substr, str[i], caseSensitive) > -1) {
			return i;
		}
	}

	return -1;
}

void RemoveRagdoll(int client) {
	int clientRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
	if(clientRagdoll > 0 && IsValidEdict(clientRagdoll) && IsValidEntity(clientRagdoll))
	{
		// Get dead body's entity
		int ref = EntIndexToEntRef(clientRagdoll);
		int entity = EntRefToEntIndex(ref);
		if(entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
		{
			// Remove dead body's entity
			AcceptEntityInput(entity, "Kill");
		}
	}
}