//(C) 2020 rrrfffrrr <rrrfffrrr@naver.com>

/// TODO
// Attach sprite to player classes to show when player injured.
// Localization

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
	name		= "[INS] Last Standing",
	author		= "rrrfffrrr",
	description	= "Get down and use only pistol when injured",
	version		= "0.8.3",
	url			= ""
};

#include <sourcemod>
#include <convars>
#include <clients>
#include <halflife>
#include <sdkhooks>
#include <sdktools_engine>
#include <sdktools_functions>
#include <timers>

#define TEAM_OBSERVER 1
#define TEAM_SECURITY 2
#define TEAM_INSURGENT 3

#define IN_JUMP		(1 << 1)
#define IN_CROUCH_HOLD	(1 << 2)
#define IN_PRONE	(1 << 3)
#define IN_USE		(1 << 6)
#define IN_RUN		(1 << 15)
#define IN_CROUCH	(1 << 24)
#define IN_RUN_TOGGLE	(1 << 26)
#define IN_CHANGE_STANCE	(1 << 29)

ConVar g_Cvar_DamageThresholdToDeath;
ConVar g_Cvar_LastStandingPerSpawn;
ConVar g_Cvar_ReviveDelay;
ConVar g_Cvar_ReviveDistance;
ConVar g_Cvar_Damage;
ConVar g_Cvar_R;
ConVar g_Cvar_G;
ConVar g_Cvar_B;

bool IsInjured[MAXPLAYERS + 1];
int LastStandingRemain[MAXPLAYERS + 1];

int RevivingTarget[MAXPLAYERS + 1];
Handle RevivingDelay[MAXPLAYERS + 1];

bool LastUseButton[MAXPLAYERS + 1];

Handle DamageTimer = INVALID_HANDLE;

public void OnPluginStart() {
	g_Cvar_DamageThresholdToDeath = CreateConVar("sm_ls_damage", "100.0", "Need more damage then health to get killed at once.", FCVAR_PROTECTED, true, 0.0);
	g_Cvar_LastStandingPerSpawn = CreateConVar("sm_ls_num", "1", "How many times can be last standing. (-1 = infinity)", FCVAR_PROTECTED, true, -1.0);
	g_Cvar_ReviveDelay = CreateConVar("sm_ls_revivetime", "10.0", "Delay to revive.", FCVAR_PROTECTED, true, 1.0);
	g_Cvar_ReviveDistance = CreateConVar("sm_ls_distance", "200.0", "Distance limit to revive.", FCVAR_PROTECTED, true, 1.0);
	g_Cvar_Damage = CreateConVar("sm_ls_damage", "0.01", "Damage per 1 second.", FCVAR_PROTECTED, false, 0, true, 20.0);

	g_Cvar_R = CreateConVar("sm_ls_r", "255", "Red color of injured player.", FCVAR_PROTECTED, true, 0, true, 255);
	g_Cvar_G = CreateConVar("sm_ls_g", "100", "Green color of injured player.", FCVAR_PROTECTED, true, 0, true, 255);
	g_Cvar_B = CreateConVar("sm_ls_b", "100", "Blue color of injured player.", FCVAR_PROTECTED, true, 0, true, 255);

	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);

    HookAllPlayers();
}

void OnMapStart() {
	DamageTimer = CreateTimer(1.0, TIMER_DamageInjuredPlayers, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

/// HOOK
void HookAllPlayers() {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientAndInGame(i)) {
            OnClientPostAdminCheck(i);
        }
    }
}

public void OnClientPostAdminCheck(int client) {
	IsInjured[client] = false;
	RevivingTarget[client] = 0;
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client) {
	IsInjured[client] = false;
	KillReviveTimer(client);
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

/// COMMAND
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float[3] vel, float[3] angles, int& weapon) {
	if (IsValidPlayer(client) && IsPlayerAlive(client) && buttons != 0) {
		if (IsInjured[client]) {
			// cannot stand or crouch when injured
			buttons &= ~(IN_JUMP | IN_PRONE | IN_CROUCH | IN_RUN | IN_CROUCH_HOLD | IN_RUN_TOGGLE | IN_CHANGE_STANCE);
			if (GetEntProp(client, Prop_Send, "m_iCurrentStance") != 2) { // Dead when enter water
				ForcePlayerSuicide(client);
			}
			return Plugin_Changed;
		}

		if (!IsFakeClient(client)) {
			int hPlayer = -1;
			if (buttons & IN_USE != 0) { // When pressing
				if (RevivingTarget[client] <= 0 && LastUseButton[client] == false) { // Check no target has been reviving and use button pressed now
					hPlayer = GetClientAimTarget(client, false);
					if (hPlayer != -1) {
				        char strCname[128]; 
				        GetEntityClassname(hPlayer, strCname, sizeof(strCname));
			         	if (IsValidEdict(hPlayer) && IsValidEntity(hPlayer) && StrEqual(strCname, "player", false))	{// Player have fixed entity number so we can use 0 < hPlayer <= MaxClients to check it.
        					if (GetClientTeam(hPlayer) == GetClientTeam(client) && IsInjured[hPlayer]) { // Check team and target is injured.
        						if (IsBeingRevived(hPlayer)) {
        							PrintHintText(client, "Some one is reviving target.");
        						} else {
        							float tpos[3];
        							float cpos[3];
        							GetClientEyePosition(client, cpos);
        							GetClientEyePosition(hPlayer, tpos);
        							if (GetVectorDistance(cpos, tpos, false) < g_Cvar_ReviveDistance.FloatValue) { // Check distance
	        							GetClientName(hPlayer, strCname, sizeof(strCname));
	        							PrintHintText(client, "You are reviving %s.", strCname);
	        							GetClientName(client, strCname, sizeof(strCname));
	        							PrintHintText(hPlayer, "%s is reviving you.", strCname);
	        							RevivingTarget[client] = hPlayer;
	        							RevivingDelay[client] = CreateTimer(g_Cvar_ReviveDelay.FloatValue, TIMER_RevivePlayer, client);
	        						}
        						}
        					}
        				}
	      			}
	      		} else if (RevivingTarget[client] > 0) {
					hPlayer = GetClientAimTarget(client, false);
					if (hPlayer != RevivingTarget[client]) {
						KillReviveTimer(client);
					}
				}
			} else {
				KillReviveTimer(client);
			}

			LastUseButton[client] = buttons & IN_USE != 0;
		}
	}
	return Plugin_Continue;
}

/// DAMAGE TIMER
Action TIMER_DamageInjuredPlayers(Handle timer) {
	for(int i = 1; i <= MaxClients; ++i) {
		if (IsValidPlayer(i) && IsPlayerAlive(i) && IsInjured[i]) {
			SDKHooks_TakeDamage(i, i, i, g_Cvar_Damage.FloatValue, DMG_GENERIC, -1, NULL_VECTOR, NULL_VECTOR);
		}
	}
	return Plugin_Continue;
}

/// REVIVE TIMER
Action TIMER_RevivePlayer(Handle timer, int caller) {
	OnRevived(RevivingTarget[caller]);
    PrintHintText(RevivingTarget[caller], "You have been revived.");
	RevivingTarget[caller] = 0;
	return Plugin_Stop;
}

void KillReviveTimer(int client) {
	if (RevivingTarget[client] > 0) {
		RevivingTarget[client] = 0;
		KillTimer(RevivingDelay[client]);
	}
}

/// SPAWN DEATH
public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	IsInjured[client] = false;
	RevivingTarget[client] = 0;
	LastStandingRemain[client] = g_Cvar_LastStandingPerSpawn.IntValue;
}
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	IsInjured[client] = false;
	SetEntityRenderColor(client, 255, 255, 255);
	KillReviveTimer(client);
}

/// ON DAMAGE
public Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3]) {
	if (!IsClientAndInGame(victim) || !IsClientAndInGame(attacker) || damage == 0.0 || IsFakeClient(victim) || IsInjured[victim]) { return Plugin_Continue; }

	int health = GetClientHealth(victim);
	if (IsInjured[victim] == false && (LastStandingRemain[victim] > 0 || -1 == LastStandingRemain[victim]) && health <= damage && damage < health + g_Cvar_DamageThresholdToDeath.FloatValue && CountTeamAliveWithoutCaller(victim) > 0) {
		damage = health - 20.0;
		OnInjured(victim);
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

/// INJURED
void OnInjured(int client) {
	IsInjured[client] = true;
	LastStandingRemain[client]--;
	SetEntProp(client, Prop_Send, "m_iCurrentStance", 2);
	SetEntityRenderColor(client, g_Cvar_R.IntValue, g_Cvar_G.IntValue, g_Cvar_B.IntValue);
}

void OnRevived(int client) {
	IsInjured[client] = false;
	SetEntityRenderColor(client, 255, 255, 255);
}

// util
bool IsValidPlayer(int client)
{
	if (!(client > 0 && client < MaxClients))
		return false;
	
	if (!IsClientConnected(client))
		return false;
	
	if (!IsClientInGame(client))
		return false;
	
	return true;
}

bool IsClientAndInGame(int client)
{
    if (client > 0 && client < MaxClients)
    {
        return IsClientInGame(client);
    }
    return false;
}

int CountTeamAliveWithoutCaller(int client) {
	int count = 0;
	int team = GetClientTeam(client);

	for(int i = 1; i <= MaxClients; ++i) {
		if (client != i && IsValidPlayer(i) && IsPlayerAlive(i) && GetClientTeam(i) == team) {
			count++;
		}
	}

	return count;
}

bool IsBeingRevived(int client) {
	for(int i = 1; i <= MaxClients; ++i) {
		if (client != i && RevivingTarget[i] == client) {
			return true;
		}
	}

	return false;
}