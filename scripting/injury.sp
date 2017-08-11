#include <sourcemod>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_DESCRIPTION "make injury"
#define PLUGIN_NAME "injury"
#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_WORKING "1"
#define PLUGIN_LOG_PREFIX "INJ"
#define PLUGIN_AUTHOR "rrrfffrrr"
#define PLUGIN_URL ""

public Plugin myinfo = {
        name            = PLUGIN_NAME,
        author          = PLUGIN_AUTHOR,
        description     = PLUGIN_DESCRIPTION,
        version         = PLUGIN_VERSION,
        url             = PLUGIN_URL
};

Handle cvarStamina = INVALID_HANDLE;

// offsets
int g_iStamina = -1;
int g_vAimPunch = -1;
int g_vAimPunchVel = -1;

bool bPlayerArmInjured[MAXPLAYERS + 1];
bool bPlayerLegInjured[MAXPLAYERS + 1];

public void OnPluginStart() {
	g_iStamina = FindSendPropInfo("CINSPlayer", "m_flStamina");
	if (g_iStamina == -1) {
		SetFailState("Fatal Error: Cannot find send prop.");
	}

	g_vAimPunch = FindSendPropInfo("CBasePlayer", "m_aimPunchAngle");
	if (g_vAimPunch == -1) {
		SetFailState("Fatal Error: Cannot find send prop.");
	}

	g_vAimPunchVel = FindSendPropInfo("CBasePlayer", "m_aimPunchAngleVel");
	if (g_vAimPunchVel == -1) {
		SetFailState("Fatal Error: Cannot find send prop.");
	}

	cvarStamina = CreateConVar("sm_inj_stamina", "5.0", "test", FCVAR_NOTIFY);

	HookEvent("weapon_fire", Event_Fire);
	HookEvent("player_hurt", Event_Hurt);
	HookEvent("player_death", Event_Death);
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_PreThinkPost, SDKHooks_OnPreThink);	
}

public Action SDKHooks_OnPreThink(int client) {
	if (IsValidPlayer(client) && IsPlayerAlive(client)) {
		if (GetEntProp(client, Prop_Data, "m_iHealth", 2) > 95) {
			bPlayerArmInjured[client] = false;
			bPlayerLegInjured[client] = false;
		}

		if (bPlayerArmInjured[client] == true) {
			SetEntDataFloat(client, g_iStamina, GetConVarFloat(cvarStamina), true);
		}

		if (bPlayerLegInjured[client] == true) {
			SetEntPropFloat(client, Prop_Data, "m_flMaxspeed", 80.0);
		}
	}
	return Plugin_Continue;
}

public void OnClientPostAdminCheck(int client) {
	bPlayerLegInjured[client] = false;
	bPlayerArmInjured[client] = false;
}

//public void OnGameFrame() {
//	for(int client = 1; client <= MaxClients; client++) {
//	}
//}

public Action Event_Fire(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (bPlayerArmInjured[client] != true) {
		return Plugin_Continue;
	}

	float punch[3];
	GetEntDataVector(client, g_vAimPunch, punch);
	float punchvel[3];
	GetEntDataVector(client, g_vAimPunchVel, punchvel);

	punch[0] -= 10.0 / (punchvel[0] < 1.0 ? 1.0 : punchvel[0] );
	SetEntDataVector(client, g_vAimPunch, punch, true);
	punchvel[0] *= 2;
	SetEntDataVector(client, g_vAimPunchVel, punchvel, true);

	return Plugin_Continue;
}

public Action Event_Hurt(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	int hitgroup = GetEventInt(event, "hitgroup");	// 4,5 is arms and 6,7 is legs

	if (hitgroup == 4 || hitgroup == 5) {
		bPlayerArmInjured[client] = true;
	}

	if (hitgroup == 6 || hitgroup == 7) {
		bPlayerLegInjured[client] = true;
	}

	return Plugin_Continue;
}

public Action Event_Death(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	bPlayerLegInjured[client] = false;
	bPlayerArmInjured[client] = false;

	return Plugin_Continue;
}

bool IsValidPlayer(int client) {
	if (client == 0)
		return false;
	
	if (!IsClientConnected(client))
		return false;
	
	if (!IsClientInGame(client))
		return false;
	
	return true;
}