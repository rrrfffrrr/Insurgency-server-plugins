//(C) 2020 rrrfffrrr <rrrfffrrr@naver.com>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
	name		= "[INS] RespawnBots",
	author		= "rrrfffrrr",
	description	= "Handling bot respawn system for coop",
	version		= "2.1.0",
	url			= ""
};

#include <sourcemod>
#include <sdktools>
#include <timers>
//#include <counterattack>
#define TEAM_SPECTATE 1
#define TEAM_SECURITY 2
#define TEAM_INSURGENT 3

ConVar CvarRTime;
ConVar CvarDisplay;
ConVar CvarDisplayDelay;
ConVar CvarDefaultPoint;
ConVar CvarAddPoint;
ConVar CvarDefaultPointCA;
ConVar CvarAddPointCA;
ConVar CvarInfiniteOnCA;
ConVar CvarOnlyAliveCA;
ConVar CvarEnableAdjustSpawnLocation;
ConVar CvarAdjustDistance;

Handle fToggleSpawnZone;
Handle fPointInSpawnZone;
Handle fGetBaseEntity;
Handle fForceRespawn;
Handle cGameConfig;

int iBotRespawnRemain = 0;

Handle tRespawnDelay[MAXPLAYERS+1];
Handle tDisplay;

Handle tOnRespawnFrame;

StringMap hSpawnZone;
StringMapSnapshot hSpawnZoneKeys;

/// Counter attack forward.
/// If you don't use CustomCounterAttack, delete #include <counterattack> in line 17 to disable it (default: disabled)
#if defined _ins_counterattack
public void OnCounterAttackFinished(bool isCustom) {
	ResetRespawnCount();
}
#endif

public void OnPluginStart()
{
	InitSDKCalls();
	InitCvars();
	HookCvars();
	HookEvents();

	UpdateDisplayTimer();
	UpdateRespawnTimer();

	hSpawnZone = new StringMap();
	hSpawnZoneKeys = hSpawnZone.Snapshot();
	BuildSpawnZoneList();
}

public void OnMapStart() {
	tDisplay = INVALID_HANDLE;
	UpdateDisplayTimer();

	tOnRespawnFrame = INVALID_HANDLE;
	UpdateRespawnTimer();

	for(int i = 1; i <= MaxClients; ++i) {
		tRespawnDelay[i] = INVALID_HANDLE;
	}
	BuildSpawnZoneList();
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
		SetFailState("Fatal Error: Unable to find CINSPlayer::ForceRespawn");
	}

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(cGameConfig, SDKConf_Signature, "CINSSpawnZone::PointInSpawnZone");
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer, 0, VENCODE_FLAG_COPYBACK);
	fPointInSpawnZone = EndPrepSDKCall();
	if (fPointInSpawnZone == INVALID_HANDLE) {
		SetFailState("Fatal Error: Unable to find CINSSpawnZone::PointInSpawnZone");
	}
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(cGameConfig, SDKConf_Virtual, "CINSSpawnZone::GetBaseEntity");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Plain);
	fGetBaseEntity = EndPrepSDKCall();
	if (fGetBaseEntity == INVALID_HANDLE) {
		SetFailState("Fatal Error: Unable to find CINSSpawnZone::GetBaseEntity");
	}

	StartPrepSDKCall(SDKCall_GameRules);
	PrepSDKCall_SetFromConf(cGameConfig, SDKConf_Signature, "CINSRules::ToggleSpawnZone");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	fToggleSpawnZone = EndPrepSDKCall();
	if (fToggleSpawnZone == INVALID_HANDLE) {
		SetFailState("Fatal Error: Unable to find CINSRules::ToggleSpawnZone");
	}
}

void InitCvars() {
	CvarRTime = CreateConVar("sm_botrespawn_delay", "1", "How many seconds wait before spawn for insurgent, 0 is disable delay", FCVAR_NOTIFY);

	CvarDefaultPoint = CreateConVar("sm_botrespawn_rp", "5", "Default bots count, 0 is infinity", FCVAR_NOTIFY);
	CvarAddPoint = CreateConVar("sm_botrespawn_rp_add", "5", "Number of bots that each player (rp + players * rp_add)", FCVAR_NOTIFY);

	CvarDefaultPointCA = CreateConVar("sm_botrespawn_carp", "5", "Default bots count when counter attack", FCVAR_NOTIFY);
	CvarAddPointCA = CreateConVar("sm_botrespawn_carp_add", "5", "Number of bots that each player when counter attack (carp + players * carp_add)", FCVAR_NOTIFY);
	CvarInfiniteOnCA = CreateConVar("sm_botrespawn_infinite_ca", "1", "Infinity spawn when counter attack", FCVAR_NOTIFY);

	CvarDisplay = CreateConVar("sm_botrespawn_display", "1", "Display respawn point(0 = don't display, 1 = display)", FCVAR_NOTIFY);
	CvarDisplayDelay = CreateConVar("sm_botrespawn_display_delay", "1", "Display delay(sec)", FCVAR_NOTIFY);

	CvarOnlyAliveCA = CreateConVar("sm_botrespawn_count_alive", "1", "Count only alive players when counter attack.", FCVAR_NOTIFY);

	CvarEnableAdjustSpawnLocation = CreateConVar("sm_botrespawn_adjust", "1", "Adjust spawn location to where player can't see.", FCVAR_NOTIFY);
	CvarAdjustDistance = CreateConVar("sm_botrespawn_adjust_distance", "100", "Adjust spawn location when someone close enough (Include teams)", FCVAR_NOTIFY, true, 50.0);
}

void HookCvars() {
	HookConVarChange(CvarDisplayDelay, UpdateCvarDisplay);
}

void HookEvents() {
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_start", Event_BeginRound);
	HookEvent("round_begin", Event_StartRound);
	HookEvent("controlpoint_captured", Event_Captured);
	HookEvent("object_destroyed", Event_Captured);
}

/// Display
void UpdateCvarDisplay(Handle cvar, const char[] oldValue, const char[] newValue) {
	UpdateDisplayTimer();
}

void UpdateDisplayTimer() {
	if (tDisplay != INVALID_HANDLE) {
		KillTimer(tDisplay);
	}

	tDisplay = CreateTimer(CvarDisplayDelay.FloatValue, Timer_DisplayCount,_, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_DisplayCount(Handle timer) {
	if (CvarDisplay.BoolValue != true) {
		return Plugin_Continue;
	}

	char hint[64];
	if (IsCounterAttack() && CvarInfiniteOnCA.BoolValue)
		Format(hint, sizeof(hint), "Infinite respawn");
	else
		Format(hint, sizeof(hint), "남은 Insurgent : %i", ((iBotRespawnRemain > 0) ? iBotRespawnRemain : 0) + GetFakeClientCount());

	for(int i = 1; i <= MaxClients; i++) {
		if (IsValidPlayer(i) && !IsFakeClient(i)) {
			PrintHintText(i, "%s", hint);
		}
	}
	return Plugin_Continue;
}

/// Respawn tick
void UpdateRespawnTimer() {
	if (tOnRespawnFrame == INVALID_HANDLE) {
		tOnRespawnFrame = CreateTimer(1.0, Timer_RespawnTick,_, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action Timer_RespawnTick(Handle timer) {
	bool IsInfiniteRespawn = (IsCounterAttack() && CvarInfiniteOnCA.BoolValue);
	if (!IsInfiniteRespawn && iBotRespawnRemain <= 0)
		return Plugin_Continue;

	for(int i = 1; i <= MaxClients; ++i) {
		if (IsValidPlayer(i) && IsFakeClient(i) && !IsPlayerAlive(i) && tRespawnDelay[i] == INVALID_HANDLE) {
			if (RespawnPlayer(i)) {
				iBotRespawnRemain -= (IsInfiniteRespawn ? 0 : 1);
				break;
			}
		}
	}
	
	return Plugin_Continue;
}

Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (tRespawnDelay[client] != INVALID_HANDLE) {
		KillTimer(tRespawnDelay[client]);
		tRespawnDelay[client] = INVALID_HANDLE;
	}
	return Plugin_Continue;
}

void ResetRespawnCount() {
	if (IsCounterAttack()) {
		iBotRespawnRemain = CalcRespawnCount(CvarDefaultPointCA, CvarAddPointCA, GetRealClientCount(true, CvarOnlyAliveCA.BoolValue));
	} else {
		iBotRespawnRemain = CalcRespawnCount(CvarDefaultPoint, CvarAddPoint, GetRealClientCount());
	}
}

int CalcRespawnCount(ConVar def, ConVar add, int player) {
	return def.IntValue + player * add.IntValue;
}

Action Event_BeginRound(Event event, const char[] name, bool dontBroadcast) {
	ResetRespawnCount();
	return Plugin_Continue;
}

Action Event_StartRound(Event event, const char[] name, bool dontBroadcast) {
	ResetRespawnCount();
	return Plugin_Continue;
}

Action Event_Captured(Handle event, const char[] name, bool dontBroadcast) {
	ResetRespawnCount();
	return Plugin_Continue;
}

/// Death handler
Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidPlayer(client) || !IsFakeClient(client)) {
		return Plugin_Continue;
	}

	bool isCA = IsCounterAttack();
	bool enableRespawn = (((isCA) ? CvarDefaultPointCA.IntValue : CvarDefaultPoint.IntValue) != 0);	// idk why this code exists... should i delete it?
	if (enableRespawn)
		return Plugin_Continue;

	float delay = CvarRTime.FloatValue;
	if (delay > 0.0) {
		tRespawnDelay[client] = CreateTimer(delay, Timer_RespawnDelay, client, TIMER_FLAG_NO_MAPCHANGE);
	}

	return Plugin_Continue;
}

Action Timer_RespawnDelay(Handle timer, int client) {
	tRespawnDelay[client] = INVALID_HANDLE;
	return Plugin_Continue;
}

/// Utils
bool RespawnPlayer(int client) {
	if (IsValidPlayer(client) && !IsPlayerAlive(client) && GetClientTeam(client) != TEAM_SPECTATE) {
		SDKCall(fForceRespawn, client);
		FixSpawnPoint(client);
		return true;
	}

	return false;
}

bool IsValidPlayer(int client) {
	if (client < 1 || client > MaxClients)
		return false;

	if (!IsClientInGame(client))
		return false;
	
	return true;
}

int GetRealClientCount(bool inGameOnly = true, bool onlyAlivePlayer = true) {
	int clients = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if (((inGameOnly) ? IsClientInGame(i) : IsClientConnected(i)) && !IsFakeClient(i) && GetClientTeam(i) != TEAM_SPECTATE && ((onlyAlivePlayer) ? IsPlayerAlive(i) : true)) {
			clients++;
		}
	}
	return clients;
}

int GetFakeClientCount(bool inGameOnly = true, bool onlyAlivePlayer = true) {
	int clients = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if (((inGameOnly) ? IsClientInGame(i) : IsClientConnected(i)) && IsFakeClient(i) && ((onlyAlivePlayer) ? IsPlayerAlive(i) : true)) {
			clients++;
		}
	}
	return clients;
}

bool IsCounterAttack() {
	return view_as<bool>(GameRules_GetProp("m_bCounterAttack"));
}

int GetCurrentCPIndex() {
	int res = FindEntityByClassname(-1, "ins_objective_resource");
	if (res == -1)
		return -1;

	int CP = GetEntProp(res, Prop_Send, "m_nActivePushPointIndex");

	return CP;
}

/// Fix spawn location
// This is the main feature of RespawnBots 2.0
void FixSpawnPoint(int client) {
	if (!CvarEnableAdjustSpawnLocation.BoolValue)
		return;

	float pos[3];
	GetClientAbsOrigin(client, pos);
	if (!EnemyInSightOrClose(client, pos))
		return;

	int cp = GetCurrentCPIndex();
	int team = GetClientTeam(client);
	char key[4];
	ArrayList list;
	if (hSpawnZone.GetValue(key, list)) {
		for(int i = 0; i < list.Length; ++i) {
			GetEntPropVector(list.Get(i), Prop_Send, "m_vecOrigin", pos);
			if (!EnemyInSightOrClose(client, pos)) {
				TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
				return;
			}
		}
	}

	Format(key, sizeof(key), "%s%d", ((team == TEAM_SECURITY) ? "S" : "I"), cp + 1);
	if (hSpawnZone.GetValue(key, list)) {
		for(int i = 0; i < list.Length; ++i) {
			GetEntPropVector(list.Get(i), Prop_Send, "m_vecOrigin", pos);
			if (!EnemyInSightOrClose(client, pos)) {
				TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
				return;
			}
		}
	}
}

bool EnemyInSightOrClose(int client, float pos[3]) {
	int team = GetClientTeam(client);
	int eteam = (team == TEAM_SECURITY) ? TEAM_INSURGENT : TEAM_SECURITY;
	float minDist = Pow(CvarAdjustDistance.FloatValue, 2.0);
	float org[3];
	for(int i = 1; i <= MaxClients; ++i) {
		if (i != client && IsClientInGame(i) && IsPlayerAlive(i)) {
			GetClientEyePosition(i, org);
			if (GetVectorDistance(pos, org, true) <= minDist) {
				return true;
			}

			if (GetClientTeam(i) == eteam) {
				if (NothingBetweenClient(client, i, pos, org)) {
					return true;
				}
			}
		}
	}

	return false;
}

bool NothingBetweenClient(int client1, int client2, float c1Vec[3], float c2Vec[3]) {
	Handle tr = TR_TraceRayFilterEx(c1Vec, c2Vec, MASK_PLAYERSOLID, RayType_EndPoint, Filter_Caller, client1);
	if (TR_DidHit(tr)) {
		if (TR_GetEntityIndex(tr) == client2) {
			CloseHandle(tr);
			return true;
		}

		CloseHandle(tr);
		return false;
	}
	CloseHandle(tr);
	return true;
}

bool Filter_Caller(int entity, int contentsMask, int client) {
	if (entity == client) {
		return false;
	}

	return true;
}

int FindSpawnZone(int spawnpoint) {
	Address pSpawnZone = Address_Null;
	float absOrigin[3];
	GetEntPropVector(spawnpoint, Prop_Data, "m_vecAbsOrigin", absOrigin);
	SDKCall(fPointInSpawnZone, absOrigin, spawnpoint, pSpawnZone);
	if (pSpawnZone == Address_Null) {
		return -1;
	}
	return SDKCall(fGetBaseEntity, pSpawnZone);
}

void BuildSpawnZoneList() {
	ArrayList listIns;
	ArrayList listSec;
	char key[4];
	for(int i = 0; i < hSpawnZoneKeys.Length; ++i) {
		hSpawnZoneKeys.GetKey(i, key, sizeof(key));
		if (hSpawnZone.GetValue(key, listIns)) {
			delete listIns;
		}
	}
	hSpawnZone.Clear();

	int objective = FindEntityByClassname(-1, "ins_objective_resource");
	if (objective == -1)
		return;
	int numOfSpawnZone = GetEntProp(objective, Prop_Send, "m_iNumControlPoints");
	for(int i = 0; i <= numOfSpawnZone; ++i) {
		SDKCall(fToggleSpawnZone, i, false);
	}

	int point = -1;
	int zone = -1;
	int team = 1;
	for(int i = 0; i <= numOfSpawnZone; ++i) {
		SDKCall(fToggleSpawnZone, i, true);
		
		listIns = new ArrayList();
		listSec = new ArrayList();
		point = FindEntityByClassname(-1, "ins_spawnpoint");
		while(point != -1) {
			zone = FindSpawnZone(point);
			if (zone != -1) {
				team = GetEntProp(point, Prop_Send, "m_iTeamNum");
				float pos[3];
				GetEntPropVector(point, Prop_Send, "m_vecOrigin", pos);
				if (team == TEAM_SECURITY)
					listSec.Push(point);
				else if (team == TEAM_INSURGENT)
					listIns.Push(point);
			}
			point = FindEntityByClassname(point, "ins_spawnpoint");
		}
		Format(key, sizeof(key), "I%d", i);
		hSpawnZone.SetValue(key, listIns, true);
		Format(key, sizeof(key), "S%d", i);
		hSpawnZone.SetValue(key, listSec, true);

		SDKCall(fToggleSpawnZone, i, false);
	}
	
	hSpawnZoneKeys = hSpawnZone.Snapshot();
	SDKCall(fToggleSpawnZone, GetCurrentCPIndex(), true);
}