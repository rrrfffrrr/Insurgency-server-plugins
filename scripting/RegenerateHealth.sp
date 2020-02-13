#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
		name			= "[INS] Regenerate health",
		author		  = "rrrfffrrr",
		description	 = "Regenerate player health",
		version		 = "1.0.0",
		url			 = ""
};

Handle hPlayerRegenerationTimer[MAXPLAYERS + 1];

#define MAX_LIMIT 10
int iLimits[MAX_LIMIT];
int iNumOfLimit;

int iPlayerLimit[MAXPLAYERS + 1];

ConVar ConVarRegenerationDelay;
ConVar ConVarRegenerationInterval;
ConVar ConVarRegenerationHeal;
ConVar ConVarRegenerationLimit;

public void OnPluginStart() {
	InitConVar();
	HookConVar();

	OnChangeLimit(ConVarRegenerationLimit, "", "80 20");
	HookEvent("player_death", Event_PlayerDeath);
}

public void OnClientPutInServer(int client) {
	if (IsValidPlayer(client))
		SDKHook(client, SDKHook_OnTakeDamagePost, Event_OnTakeDamagePost);
}

public void OnClientDisconnect_Post(int client) {
	StopRegenerate(client);
}

void Event_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype) {
	if (IsValidPlayer(victim)) {
		StartRegenerate(victim);
	}
}

void InitConVar() {
	ConVarRegenerationDelay = CreateConVar("sm_rhealth_delay", "5", "Delay before start to regenerate.", FCVAR_NOTIFY, true, 0.0);
	ConVarRegenerationInterval = CreateConVar("sm_rhealth_interval", "0.2", "Interval on each heal.", FCVAR_NOTIFY, true, 0.05);
	ConVarRegenerationHeal = CreateConVar("sm_rhealth_heal", "1", "Heal num on each interval.", FCVAR_NOTIFY, true, 0.01);
	ConVarRegenerationLimit = CreateConVar("sm_rhealth_limit", "80 20", "Maximum of regeneration.", FCVAR_NOTIFY);
}

void HookConVar() {
	HookConVarChange(ConVarRegenerationLimit, OnChangeLimit);
}

void OnChangeLimit(ConVar convar, const char[] oldValue, const char[] newValue) {
	char explode[MAX_LIMIT][4];
	iNumOfLimit = ExplodeString(newValue, " ", explode, MAX_LIMIT, sizeof(explode[]));
	for(int i = 0; i < MAX_LIMIT; ++i) {
		if (i < iNumOfLimit)
			iLimits[i] = StringToInt(explode[i]);
		else
			iLimits[i] = 0;
	}
	SortIntegers(iLimits, iNumOfLimit, Sort_Ascending);
}

Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	StopRegenerate(client);
	return Plugin_Continue;
}

void StartRegenerate(int client) {
	if (!IsValidPlayer(client) || !IsPlayerAlive(client))
		return;

	if (hPlayerRegenerationTimer[client] != INVALID_HANDLE)
		KillTimer(hPlayerRegenerationTimer[client]);
	hPlayerRegenerationTimer[client] = CreateTimer(ConVarRegenerationDelay.FloatValue, Timer_Delay, client, TIMER_FLAG_NO_MAPCHANGE);

	int health = GetEntProp(client, Prop_Send, "m_iHealth", 4);
	int limit = MAX_LIMIT;
	for(int i = 0; i < iNumOfLimit; ++i) {
		if (health <= iLimits[i])
			limit = i;
		else
			break;
	}
	iPlayerLimit[client] = limit + 1;
}

void StopRegenerate(int client) {
	if (hPlayerRegenerationTimer[client] != INVALID_HANDLE)
		KillTimer(hPlayerRegenerationTimer[client]);
	hPlayerRegenerationTimer[client] = INVALID_HANDLE;
}

Action Timer_Delay(Handle timer, int client) {
	hPlayerRegenerationTimer[client] = INVALID_HANDLE;
	if (!IsValidPlayer(client) || !IsPlayerAlive(client))
		return Plugin_Stop;

	HealPlayer(client, ConVarRegenerationHeal.FloatValue);
	hPlayerRegenerationTimer[client] = CreateTimer(ConVarRegenerationInterval.FloatValue, Timer_Heal, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

Action Timer_Heal(Handle timer, int client) {
	if (!IsValidPlayer(client) || !IsPlayerAlive(client)) {
		StopRegenerate(client);
		return Plugin_Stop;
	}

	HealPlayer(client, ConVarRegenerationHeal.FloatValue);
	return Plugin_Continue;
}

void HealPlayer(int client, float heal) {
	int max = GetEntProp(client, Prop_Send, "m_iMaxHealth", 4);
	if (iPlayerLimit[client] < MAX_LIMIT) {
		int limit = iLimits[iPlayerLimit[client]];
		max = (max > limit) ? limit : max;
	}
	float health = view_as<float>(GetEntProp(client, Prop_Send, "m_iHealth", 4));
	health += heal;
	if (health > max) {
		health = view_as<float>(max);
		StopRegenerate(client);
	}
	SetEntProp(client, Prop_Send, "m_iHealth", RoundToCeil(health), 4);
}

bool IsValidPlayer(int client) {
	if (client < 1 || client > MaxClients)
		return false;

	if (!IsClientInGame(client))
		return false;

	return true;
}