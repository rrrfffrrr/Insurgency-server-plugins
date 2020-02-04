//(C) 2020 rrrfffrrr <rrrfffrrr@naver.com>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
	name		= "[INS] Custom counter attack",
	author		= "rrrfffrrr",
	description	= "Start counter attack without capture any control points.",
	version		= "1.1.0",
	url			= ""
};

#include <sourcemod>
#include <sdktools>
#include <sdktools_functions>
#include <sdktools_gamerules>

// convars
ConVar cvarGameMode;
bool bGameModeNotSupport; // caching
ConVar cvarSaveRemainTime;

// SDKTools
Handle cGameConfig;
Handle fStartCounterAttack;
Handle fSetRoundTime;
Handle fGetRoundRemainTime;

// counter attack state variable
float flLastRemainTimeBeforeCounterAttack;
bool bIsCustomCA;
bool bPrevCA;

GlobalForward gfOnCounterAttackFinished;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	CreateNative("StartCounterAttack", Native_StartCustomCounterAttack);
	return APLRes_Success;
}

public any Native_StartCustomCounterAttack(Handle plugin, int numParams) {
	StartCustomCounterAttack();
}

public void OnPluginStart() {
	LoadConVars();
	LoadPlugins();
	gfOnCounterAttackFinished = new GlobalForward("OnCounterAttackFinished", ET_Event, Param_Cell);
	HookEvent("round_end", Event_OnRoundEnd);

	char mode[64];
	cvarGameMode.GetString(mode, sizeof(mode));
	if (strcmp(mode, "checkpoint", false) != 0) {
		bGameModeNotSupport = true;
	} else {
		bGameModeNotSupport = false;
	}
}

public void OnPluginEnd() {
	delete gfOnCounterAttackFinished;
}

void LoadConVars() {
	cvarSaveRemainTime = CreateConVar("sm_counterattack_persist_time", "1", "Persist last remaining time when custom counter attack occured.");
	cvarGameMode = FindConVar("mp_gamemode");
	cvarGameMode.AddChangeHook(CHCheckGameMode);
}

void LoadPlugins() {
	cGameConfig = LoadGameConfigFile("insurgency.games");
	if (cGameConfig == INVALID_HANDLE) {
		SetFailState("Fatal Error: Missing File \"insurgency.games\"!");
	}

	StartPrepSDKCall(SDKCall_GameRules);
	PrepSDKCall_SetFromConf(cGameConfig, SDKConf_Signature, "CINSRules_Checkpoint::CounterWaveStarted");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	fStartCounterAttack = EndPrepSDKCall();
	if (fStartCounterAttack == INVALID_HANDLE) {
		SetFailState("Fatal Error: Unable to find CINSRules_Checkpoint::CounterWaveStarted");
	}

	StartPrepSDKCall(SDKCall_GameRules);
	PrepSDKCall_SetFromConf(cGameConfig, SDKConf_Signature, "CINSRules::SetRoundTime");
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	fSetRoundTime = EndPrepSDKCall();
	if (fSetRoundTime == INVALID_HANDLE) {
		SetFailState("Fatal Error: Unable to find CINSRules::SetRoundTime");
	}

	StartPrepSDKCall(SDKCall_GameRules);
	PrepSDKCall_SetFromConf(cGameConfig, SDKConf_Signature, "CINSRules::GetRoundRemainingTime");
	PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
	fGetRoundRemainTime = EndPrepSDKCall();
	if (fGetRoundRemainTime == INVALID_HANDLE) {
		SetFailState("Fatal Error: Unable to find CINSRules::GetRoundRemainingTime");
	}
}

void CHCheckGameMode(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (strcmp(newValue, "checkpoint", false) != 0) {
		bGameModeNotSupport = true;
	} else {
		bGameModeNotSupport = false;
	}
}

public void OnGameFrame() {	/// Need to hook CINSRules_Checkpoint::CounterWaveFinished to optimize performance (but it's not virtual function!)
	if (bPrevCA) {
		if (!IsCounterAttack()) {
			OnCustomCounterAttackFinished(bIsCustomCA);
			bIsCustomCA = false;
		}
	}
	bPrevCA = IsCounterAttack();
}

public Action Event_OnRoundEnd(Event event, const char[] name, bool dontBroadcast) {
	bIsCustomCA = false;
	bPrevCA = false;

	return Plugin_Continue;
}

void OnCustomCounterAttackFinished(bool isCustom) {
	if (isCustom && cvarSaveRemainTime.BoolValue)
		SetRemainTime(flLastRemainTimeBeforeCounterAttack);

	Action result;
	Call_StartForward(gfOnCounterAttackFinished);
	Call_PushCell(isCustom);
	Call_Finish(result);
}

void StartCustomCounterAttack() {
	if (bGameModeNotSupport || IsCounterAttack())
		return;

	int res = FindEntityByClassname(-1, "ins_objective_resource");
	if (res == -1)
		return;

	int CP = GetEntProp(res, Prop_Send, "m_nActivePushPointIndex") - 1;
	if (CP < 0)	// Check First cp was captured.
		return;

	if (GetEntProp(res, Prop_Send, "m_iObjectType", 1, CP) != -1) // Check cp is capture zone.
		return;

	bIsCustomCA = true;
	flLastRemainTimeBeforeCounterAttack = GetRemainTime();
	SetEntProp(res, Prop_Send, "m_nActivePushPointIndex", CP);
	SDKCall(fStartCounterAttack, CP);	// idk what's purpose of int parameter. Looks like it's cp.
}

bool IsCounterAttack() {
	return view_as<bool>(GameRules_GetProp("m_bCounterAttack"));
}

void SetRemainTime(float time) {
	SDKCall(fSetRoundTime, time);
}

float GetRemainTime() {
	return SDKCall(fGetRoundRemainTime);
}