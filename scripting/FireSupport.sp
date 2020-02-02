//(C) 2020 rrrfffrrr <rrrfffrrr@naver.com>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
	name		= "[INS] Fire support",
	author		= "rrrfffrrr",
	description	= "Fire support",
	version		= "1.0.0",
	url			= ""
};

#include <sourcemod>
#include <datapack>
#include <float>
#include <sdktools>
#include <sdktools_trace>
#include <sdktools_functions>
#include <timers>

#define MATH_PI 3.14159265359

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

	RegAdminCmd("sm_firesupport_call", CmdCallFS, 0);										// HINT: test command
}

public void OnMapStart() {
	gBeamSprite = PrecacheModel("sprites/laserbeam.vmt");
	PrecacheModel("models/weapons/w_rpg7_projectile.mdl");
}

Action CmdCallFS(int client, int args) {													// HINT: Fire to where client looking
	float ground[3];
	if (GetAimGround(client, ground)) {
		ground[2] += 20.0;
		CallFireSupport(client, ground);
	}
	return Plugin_Handled;
}

/// FireSupport
public void CallFireSupport(int client, float ground[3]) {									// HINT: Fire to target pos
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
	}
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