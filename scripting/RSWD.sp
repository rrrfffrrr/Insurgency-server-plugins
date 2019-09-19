//(C) 2019 rrrfffrrr <rrrfffrrr@naver.com>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
  name        = "[INS] Reset supply when dead",
  author      = "rrrfffrrr",
  description = "1.0.0",
  version     = "Reset supply token when player is dead",
  url         = ""
};

#include <sourcemod>
#include <entity>

ConVar SupplyTokenBase;
ConVar SupplyTokenBaseForBot;

int AvailableTokenOffset = -1;
int RecievedTokenOffset = -1;

public void OnPluginStart() {
	SupplyTokenBase = FindConVar("mp_supply_token_base");
	if (SupplyTokenBase == null) {
		SetFailState("Fatal Error: Unable to find convar. mp_supply_token_base");
	}
	SupplyTokenBaseForBot = FindConVar("mp_supply_token_bot_base");
	if (SupplyTokenBaseForBot == null) {
		SetFailState("Fatal Error: Unable to find convar. mp_supply_token_bot_base");
	}

	AvailableTokenOffset = FindSendPropInfo("CINSPlayer", "m_nAvailableTokens");
	if (AvailableTokenOffset == -1) {
		SetFailState("Fatal Error: Cannot find send prop. CINSPlayer::m_nAvailableTokens");
	}
	RecievedTokenOffset = FindSendPropInfo("CINSPlayer", "m_nRecievedTokens");
	if (RecievedTokenOffset == -1) {
		SetFailState("Fatal Error: Cannot find send prop. CINSPlayer::m_nRecievedTokens");
	}

	HookEvent("player_spawn", Event_PlayerDeath);
	HookEvent("player_death", Event_PlayerDeath);
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId( event.GetInt("userid") );
	if (!IsValidPlayer(client)) {
		return Plugin_Continue;
	}

	int newToken = 1;
	if (IsFakeClient(client)) {
		newToken = SupplyTokenBaseForBot.IntValue;
	} else {
		newToken = SupplyTokenBase.IntValue;
	}
	int lastRecievedToken = 0;
	lastRecievedToken = GetEntData(client, RecievedTokenOffset, 1);

	SetEntData(client, AvailableTokenOffset, clamp(newToken - lastRecievedToken, 0, 255), 1, true);
	SetEntData(client, RecievedTokenOffset, newToken, 1, true);

	return Plugin_Continue;
}

// math
stock int clamp(int value, int min, int max) {
	value = value < max ? value : max;
	return  value > min ? value : min;
}

// etc
stock bool IsValidPlayer(int client) {
	if (client <= 0)
		return false;
	
	if (!IsClientConnected(client))
		return false;
	
	if (!IsClientInGame(client))
		return false;
	
	return true;
}