//(C) 2020 rrrfffrrr <rrrfffrrr@naver.com>

#if defined _ins_utils
 #endinput
#endif
#define _ins_utils

#include<entity>
#include<clients>
#include<sdktools_gamerules>

public void AddToken(int client, int token) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;
	
	int at = GetEntProp(client, Prop_Send, "m_nAvailableTokens");
	int rt = GetEntProp(client, Prop_Send, "m_nRecievedTokens");
	SetEntProp(client, Prop_Send, "m_nAvailableTokens", at + token);
	SetEntProp(client, Prop_Send, "m_nRecievedTokens", rt + token);
}

/// insurgency specific round state function
stock RoundState GameRules_GetGameState()
{
	return view_as<RoundState>(GameRules_GetProp("m_iGameState"));
}

stock bool IsCounterAttack() {
	return view_as<bool>(GameRules_GetProp("m_bCounterAttack"));
}