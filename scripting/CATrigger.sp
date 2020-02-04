//(C) 2020 rrrfffrrr <rrrfffrrr@naver.com>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
	name		= "[INS] Counter attack trigger",
	author		= "rrrfffrrr",
	description	= "Trigger counter attack when some conditions.",
	version		= "1.0.0",
	url			= ""
};

#include <sourcemod>
#include <counterattack>

#define TEAM_SPECTATE 1
#define TEAM_SECURITY 2
#define TEAM_INSURGENT 3
#define TEAM_NUM 4

ConVar cvarMinThreshold;
ConVar cvarMaxThreshold;
ConVar cvarCounterAttackAlways;
ConVar cvarCounterAttackDisable;

int iDeathCount[TEAM_NUM];

public void OnPluginStart() {
	cvarMinThreshold = CreateConVar("sm_catrigger_min", "6", "Start num to try counter attack. (100 / (1 + Max - Min) %)");
	cvarMaxThreshold = CreateConVar("sm_catrigger_max", "10", "100% counter attack when num of player death. (100%)");
	cvarCounterAttackAlways = FindConVar("mp_checkpoint_counterattack_always");
	cvarCounterAttackDisable = FindConVar("mp_checkpoint_counterattack_disable");

	HookEvent("round_start", Event_Init);
	HookEvent("round_begin", Event_Init);
	HookEvent("player_death", Event_Death);
}

public void OnCounterAttackFinished(bool isCustom) {
	for(int i = 0; i < TEAM_NUM; ++i) {
		iDeathCount[i] = 0;
	}
}

public Action Event_Init(Event event, const char[] name, bool dontBroadcast) {
	for(int i = 0; i < TEAM_NUM; ++i) {
		iDeathCount[i] = 0;
	}

	return Plugin_Continue;
}

public Action Event_Death(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsFakeClient(client))
		return Plugin_Continue;

	int team = GetClientTeam(client);
	if (team != TEAM_SECURITY && team != TEAM_INSURGENT)
		return Plugin_Continue;

	iDeathCount[team]++;

	if (ShouldTriggerCounterAttack(team)) {
		StartCounterAttack();
		iDeathCount[team] = 0;
	}

	return Plugin_Continue;
}

bool ShouldTriggerCounterAttack(int team) {
	if (cvarCounterAttackDisable.BoolValue)
		return false;
	if (cvarCounterAttackAlways.BoolValue)
		return true;
	
	int min = cvarMinThreshold.IntValue;
	int max = cvarMaxThreshold.IntValue;
	if (min > max)
		return false;
	if (iDeathCount[team] >= max)
		return true;
	else if (iDeathCount[team] < min)
		return false;

	float rand = GetURandomFloat();
	float threshold = (1 + iDeathCount[team] - min) / view_as<float>(1 + max - min);

	if (rand <= threshold) {
		return true;
	}

	return false;
}