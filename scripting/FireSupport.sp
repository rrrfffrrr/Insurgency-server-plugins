//(C) 2020 rrrfffrrr <rrrfffrrr@naver.com>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
	name		= "[INS] Test",
	author		= "rrrfffrrr",
	description	= "Test",
	version		= "0.0.1",
	url			= ""
};

#include <sourcemod>
#include <entity>
#include <sdktools_functions>
#include <sdktools_entinput>
#include <sdktools_trace>
#include <sdktools>

#define UPGRADE_SCOPE 0
#define UPGRADE_PRIMARY_AMMO 1
#define UPGRADE_MAGAZINE 2
#define UPGRADE_BARREL 3
#define UPGRADE_SIDERAIL 5
#define UPGRADE_UNDERBARREL 6
#define UPGRADE_STOCK 0		// need to check value
#define UPGRADE_AESTHETIC 0	// need to check value
#define UPGRADE_SOMETHING 0	// need to check what it is

float UP_VECTOR[3] = {-90.0, 0.0, 0.0};
float DOWN_VECTOR[3] = {90.0, 0.0, 0.0};

int g_BeamSprite;

Handle c_gameconfig;
Handle f_CreateRocket;
Handle f_UpdateRocket;

public void OnPluginStart() {
	c_gameconfig = LoadGameConfigFile("insurgency.games");
	if (c_gameconfig == INVALID_HANDLE) {
		SetFailState("Fatal Error: Missing File \"insurgency.games\"!");
	}

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(c_gameconfig, SDKConf_Signature, "CBaseRocketMissile::CreateRocketMissile");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef);
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_ByValue);
	f_CreateRocket = EndPrepSDKCall();
	if (f_CreateRocket == INVALID_HANDLE) {
		SetFailState("Fatal Error: Unable to find CBaseRocketMissile::CreateRocketMissile");
	}
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(c_gameconfig, SDKConf_Signature, "CINSWeaponRocketBase::UpdateRocketBodygroup");
	f_UpdateRocket = EndPrepSDKCall();
	if (f_UpdateRocket == INVALID_HANDLE) {
		SetFailState("Fatal Error: Unable to find CINSWeaponRocketBase::UpdateRocketBodygroup");
	}

	RegAdminCmd("sm_upgrade", fffu, 0);
	RegAdminCmd("sm_weapons", fff, 0);
	RegAdminCmd("sm_ammos", fffa, 0);
	RegAdminCmd("sm_gears", fffg, 0);
}

public void OnMapStart() {
	g_BeamSprite = PrecacheModel("sprites/laserbeam.vmt");
	PrecacheModel("models/weapons/w_rpg7_projectile.mdl");
}

Action fffu(int client, int args) {
	float ground[3];
	float sky[3];
	if (GetAimPos(client, ground)) {
		if (GetSkyPos(client, ground, sky)) {
			ground[2] += 20.0;
			sky[2] -= 20.0;
			TE_SetupBeamPoints(ground, sky, g_BeamSprite, 0, 0, 1, 30.0, 1.0, 0.0, 5, 0.0, {255, 0, 0, 255}, 10);
			TE_SendToAll();
			TE_SetupBeamRingPoint(ground, 500.0, 0.0, g_BeamSprite, 0, 0, 1, 30.0, 5.0, 0.0, {255, 0, 0, 255}, 10, 0);
			TE_SendToAll();
			SDKCall(f_CreateRocket, client, "rocket_rpg7", sky, DOWN_VECTOR);
		}
	}
	return Plugin_Handled;
}

//	PrintToChat(client, "%d", GetEntProp(client, Prop_Send, "m_nClassTemplateHandle"));
Action fff(int client, int args) {
	int ent = -1;
	int att = -1;
	char weaponname[64];
	char classname[64];
	int chamber = 0;
	for(int i = 0; i <= 47; ++i) {
		ent = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if (ent != -1) {
			GetEdictClassname(ent, weaponname, sizeof(weaponname));
			GetEntityClassname(ent, classname, sizeof(classname));
			if (HasEntProp(ent, Prop_Send, "m_bChamberedRound")) {
				chamber = GetEntProp(ent, Prop_Send, "m_bChamberedRound");
			} else {
				chamber = 0;
			}
			PrintToChat(client, "%d: %d - %s(%s)\nClip1(Chamber, type): %d(%d, %d)", i, ent, weaponname, classname, GetEntProp(ent, Prop_Send, "m_iClip1"), chamber, GetEntProp(ent, Prop_Send, "m_iPrimaryAmmoType"));
			for(int j = 0; j <= 8; ++j) {
				att = GetEntProp(ent, Prop_Send, "m_upgradeSlots", 1, j);
				if (att != 255) {
					PrintToChat(client, "-- %d: %d, %d, %d", j, att, EntIndexToEntRef(att), EntRefToEntIndex(att));
				}
			}

			//int t = GetEntProp(ent, Prop_Send, "m_hWeaponDefinitionHandle");
			//	PrintToChat(client, "m_hWeaponDefinitionHandle: %d", t);
		}
	}

	return Plugin_Handled;
}

Action fffa(int client, int args) {
	int ent = -1;
	for(int i = 0; i <= 255; ++i) {
		ent = GetEntProp(client, Prop_Send, "m_iAmmo", 2, i);
		if (ent != 255) {
			PrintToChat(client, "%d: %d", i, ent);
		}
	}
	return Plugin_Handled;
}


Action fffg(int client, int args) {
	int ent = -1;
	for(int i = 0; i <= 6; ++i) {
		ent = GetEntProp(client, Prop_Send, "m_EquippedGear", 1, i);
		if (ent != 255) {
			PrintToChat(client, "%d: %d", i, ent);
		}
	}
	return Plugin_Handled;
}

bool GetAimPos(int client, float vec[3]) {
	float pos[3];
	float dir[3];
	GetClientEyePosition(client, pos);
	GetClientEyeAngles(client, dir);
	Handle ray = TR_TraceRayFilterEx(pos, dir, MASK_SOLID_BRUSHONLY, RayType_Infinite, TraceWorldOnly, client);

	if (TR_DidHit(ray)) {
		TR_GetEndPosition(vec, ray);
		CloseHandle(ray);
		return true;
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
