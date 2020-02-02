//(C) 2020 rrrfffrrr <rrrfffrrr@naver.com>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
	name		= "[INS] Fire support",
	author		= "rrrfffrrr",
	description	= "Fire support",
	version		= "1.1.0",
	url			= ""
};

#include <sourcemod>
#include <datapack>
#include <float>
#include <sdktools>
#include <sdktools_trace>
#include <sdktools_functions>
#include <timers>

const int TEAM_SPECTATE = 1;
const int TEAM_SECURITY = 2;
const int TEAM_INSURGENT = 3;

const float MATH_PI = 3.14159265359;

float UP_VECTOR[3] = {-90.0, 0.0, 0.0};
float DOWN_VECTOR[3] = {90.0, 0.0, 0.0};

Handle cGameConfig;
Handle fCreateRocket;
// Need signature below
//"CBaseRocketMissile::CreateRocketMissile"
//{
//	"library"	"server"
//	"windows"	"\x55\x8B\xEC\x83\xEC\x28\x53\x8B\x5D\x08"
//    "linux"		"@_ZN18CBaseRocketMissile19CreateRocketMissileEP11CBasePlayerPKcRK6VectorRK6QAngle"
//}

int gBeamSprite;

ConVar gCvarMaxSpread;
ConVar gCvarRound;
ConVar gCvarDelay;
ConVar gCvarDelayNextSupport;
ConVar gCvarClass;
ConVar gCvarCountPerRound;
ConVar gCvarEnableCmd;
ConVar gCvarEnableWeapon;
ConVar gCvarWeapon;

bool IsEnabled[MAXPLAYERS + 1];
bool IsEnabledTeam[4];
int CountAvailableSupport[4];

public void OnPluginStart() {
	cGameConfig = LoadGameConfigFile("insurgency.games");
	if (cGameConfig == INVALID_HANDLE) {
		SetFailState("Fatal Error: Missing File \"insurgency.games\"!");
	}

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(cGameConfig, SDKConf_Signature, "CBaseRocketMissile::CreateRocketMissile");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef);
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_ByValue);
	fCreateRocket = EndPrepSDKCall();
	if (fCreateRocket == INVALID_HANDLE) {
		SetFailState("Fatal Error: Unable to find CBaseRocketMissile::CreateRocketMissile");
	}

	gCvarMaxSpread = CreateConVar("sm_firesupport_spread", "800.0", "Max spread.", FCVAR_PROTECTED, true, 10.0);
	gCvarRound = CreateConVar("sm_firesupport_shell_num", "20.0", "Shells to fire.", FCVAR_PROTECTED, true, 1.0);
	gCvarDelay = CreateConVar("sm_firesupport_delay", "10.0", "Min delay to first shell.", FCVAR_PROTECTED, true, 1.0);
	gCvarDelayNextSupport = CreateConVar("sm_firesupport_delay_support", "60.0", "Min delay to next support.", FCVAR_PROTECTED, true, 1.0);
	gCvarClass = CreateConVar("sm_firesupport_class", "template_recon_security_coop", "Set fire support specialist class.", FCVAR_PROTECTED);
	gCvarCountPerRound = CreateConVar("sm_firesupport_count", "1", "Count of available support per rounds(0 = disable)", FCVAR_PROTECTED, true, 0.0);
	gCvarEnableCmd = CreateConVar("sm_firesupport_enable_cmd", "0", "Player can call fire support using sm_firesupport_call.", FCVAR_PROTECTED);
	gCvarEnableWeapon = CreateConVar("sm_firesupport_enable_weapon", "1", "Player can call fire support using weapon.", FCVAR_PROTECTED);
	gCvarWeapon = CreateConVar("sm_firesupport_weapon", "flare", "Weapon to call fire support.", FCVAR_PROTECTED);

	RegConsoleCmd("sm_firesupport_call", CmdCallFS, "Call fire support where you looking at.", 0);
	RegAdminCmd("sm_firesupport_ad_call", CmdCallAFS, 0);										// HINT: test command

	HookEvent("weapon_fire", Event_WeaponFire);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_pick_squad", Event_PlayerPickSquad);

	InitSupportCount();
}

public void OnMapStart() {
	gBeamSprite = PrecacheModel("sprites/laserbeam.vmt");
}

public Action Event_WeaponFire(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!gCvarEnableWeapon.BoolValue) {
		return Plugin_Handled;
	}

	int team = GetClientTeam(client);
	char weapon[64];
	GetClientWeapon(client, weapon, sizeof(weapon));
	char indicator[64];
	gCvarWeapon.GetString(indicator, sizeof(indicator));
	if (IsEnabled[client] != true || (team != TEAM_SECURITY && team != TEAM_INSURGENT) || !IsPlayerAlive(client) || CountAvailableSupport[team] < 1 || !IsEnabledTeam[team] || (StrContains(weapon, indicator, false) == -1)) {
		return Plugin_Handled;
	}

	float ground[3];
	if (GetAimGround(client, ground)) {
		ground[2] += 20.0;

		if (CallFireSupport(client, ground)) {
			CountAvailableSupport[team]--;
			IsEnabledTeam[team] = false;
			CreateTimer(gCvarDelayNextSupport.FloatValue, Timer_EnableTeamSupport, team, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	InitSupportCount();
	return Plugin_Continue;
}

public Action Event_PlayerPickSquad(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	char template[64];
	event.GetString("class_template", template, sizeof(template), "");
	char class[64];
	gCvarClass.GetString(class, sizeof(class));

	IsEnabled[client] = (StrContains(template, class, false) > -1);

	return Plugin_Continue;
}

Action CmdCallFS(int client, int args) {													// HINT: Fire to where client looking
	if (!gCvarEnableCmd.BoolValue) {
		return Plugin_Handled;
	}

	int team = GetClientTeam(client);
	if (IsEnabled[client] != true || (team != TEAM_SECURITY && team != TEAM_INSURGENT) || !IsPlayerAlive(client) || CountAvailableSupport[team] < 1 || !IsEnabledTeam[team]) {
		return Plugin_Handled;
	}

	float ground[3];
	if (GetAimGround(client, ground)) {
		ground[2] += 20.0;

		if (CallFireSupport(client, ground)) {
			CountAvailableSupport[team]--;
			IsEnabledTeam[team] = false;
			CreateTimer(gCvarDelayNextSupport.FloatValue, Timer_EnableTeamSupport, team, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	return Plugin_Handled;
}

Action CmdCallAFS(int client, int args) {													// HINT: Fire to where client looking
	float ground[3];
	if (GetAimGround(client, ground)) {
		ground[2] += 20.0;
		if (CallFireSupport(client, ground)) {
		}
	}
	return Plugin_Handled;
}

/// FireSupport
public bool CallFireSupport(int client, float ground[3]) {									// HINT: Fire to target pos
	float sky[3];
	if (GetSkyPos(client, ground, sky)) {
		sky[2] -= 20.0;

		float time = gCvarDelay.FloatValue;
		DataPack pack = new DataPack();
		pack.WriteCell(client);
		pack.WriteFloat(sky[0]);
		pack.WriteFloat(sky[1]);
		pack.WriteFloat(sky[2]);

		ShowDelayEffect(ground, sky, time);

		for(int i = 0; i < gCvarRound.IntValue; ++i) {
			time = time + 0.05 + GetURandomFloat();
			CreateTimer(time, Timer_LaunchMissile, pack, TIMER_FLAG_NO_MAPCHANGE);
		}
		CreateTimer(time + 0.1, Timer_DataPackExpire, pack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
		return true;
	}

	return false;
}

void InitSupportCount() {
	IsEnabledTeam[TEAM_SECURITY] = true;
	IsEnabledTeam[TEAM_INSURGENT] = true;
	CountAvailableSupport[TEAM_SECURITY] = gCvarCountPerRound.IntValue;
	CountAvailableSupport[TEAM_INSURGENT] = gCvarCountPerRound.IntValue;
}

void ShowDelayEffect(float ground[3], float sky[3], float time) {	// WARNING: Tempent can't alive more than 25 second. must use env_beam entity
	TE_SetupBeamPoints(ground, sky, gBeamSprite, 0, 0, 1, time, 1.0, 0.0, 5, 0.0, {255, 0, 0, 255}, 10);
	TE_SendToAll();
	TE_SetupBeamRingPoint(ground, 500.0, 0.0, gBeamSprite, 0, 0, 1, time, 5.0, 0.0, {255, 0, 0, 255}, 10, 0);
	TE_SendToAll();
}

public Action Timer_LaunchMissile(Handle timer, DataPack pack) {
	float dir = GetURandomFloat() * MATH_PI * 8.0;	// not 2π for good result
	float length = GetURandomFloat() * gCvarMaxSpread.FloatValue;

	float pos[3];
	pack.Reset();
	int client = pack.ReadCell();
	pos[0] = pack.ReadFloat() + Cosine(dir) * length;
	pos[1] = pack.ReadFloat() + Sine(dir) * length;
	pos[2] = pack.ReadFloat();

	SDKCall(fCreateRocket, client, "rocket_rpg7", pos, DOWN_VECTOR);
	return Plugin_Handled;
}

public Action Timer_DataPackExpire(Handle timer, DataPack pack) {
	return Plugin_Handled;
}

public Action Timer_EnableTeamSupport(Handle timer, int team) {
	IsEnabledTeam[team] = true;
	return Plugin_Handled;
}

/// UTILS
bool GetAimGround(int client, float vec[3]) {
	float pos[3];
	float dir[3];
	GetClientEyePosition(client, pos);
	GetClientEyeAngles(client, dir);
	Handle ray = TR_TraceRayFilterEx(pos, dir, MASK_SOLID_BRUSHONLY, RayType_Infinite, TraceWorldOnly, client);

	if (TR_DidHit(ray)) {
		TR_GetEndPosition(pos, ray);
		CloseHandle(ray);

		ray = TR_TraceRayFilterEx(pos, DOWN_VECTOR, MASK_SOLID_BRUSHONLY, RayType_Infinite, TraceWorldOnly, client);
		if (TR_DidHit(ray)) {
			TR_GetEndPosition(vec, ray);
			CloseHandle(ray);
			return true;
		}
	}

	CloseHandle(ray);
	return false;
}

bool GetSkyPos(int client, float pos[3], float vec[3]) {
	Handle ray = TR_TraceRayFilterEx(pos, UP_VECTOR, MASK_SOLID_BRUSHONLY, RayType_Infinite, TraceWorldOnly, client);

	if (TR_DidHit(ray)) {
		char surface[64];
		TR_GetSurfaceName(ray, surface, sizeof(surface));
		if (StrEqual(surface, "TOOLS/TOOLSSKYBOX", false)) {
			TR_GetEndPosition(vec, ray);
			CloseHandle(ray);
			return true;
		}
	}

	CloseHandle(ray);
	return false;
}

public bool TraceWorldOnly(int entity, int mask, any data) {
	if(entity == data || entity > 0)
		return false;
	return true;
}
