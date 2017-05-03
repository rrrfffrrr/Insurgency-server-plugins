#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <timers>

#define PLUGIN_DESCRIPTION "Medic"
#define PLUGIN_NAME "Medic"
#define PLUGIN_VERSION "0.8.1"
#define PLUGIN_WORKING "1"
#define PLUGIN_LOG_PREFIX "Medic"
#define PLUGIN_AUTHOR "rrrfffrrr"
#define PLUGIN_URL ""

#define MAXWEAPONNAME 64
#define MAXUSERNAME 64
#define OFFSETCOUNT 7

/*
* 죽은 위치 표시, 렉 제거
*/

public Plugin:myinfo = {
        name            = PLUGIN_NAME,
        author          = PLUGIN_AUTHOR,
        description     = PLUGIN_DESCRIPTION,
        version         = PLUGIN_VERSION,
        url             = PLUGIN_URL
};

new Handle:cvarEnable = INVALID_HANDLE;
new Handle:cvarMedic = INVALID_HANDLE;
new Handle:cvarDelay = INVALID_HANDLE;
new Handle:cvarMaxRevive = INVALID_HANDLE;
new Handle:cvarMaxDistance = INVALID_HANDLE;
new Handle:cvarMedicItem = INVALID_HANDLE;
new Handle:cvarReviveScore = INVALID_HANDLE;

new bool:iEnabled = false;

new String:sType[64];
new String:sClass[MAXPLAYERS+1][64];
new String:sItem[MAXWEAPONNAME];

new bool:bMedicEnabled[MAXPLAYERS+1];
new bool:bPlayerJoined[MAXPLAYERS+1];
int iSoulDetected[MAXPLAYERS+1];
new Handle:RespawnTimer[MAXPLAYERS+1];
int RespawnTarget[MAXPLAYERS+1];
new Float:DeadPosition[MAXPLAYERS+1][3];
int RespawnCount[MAXPLAYERS+1];

int iRevivePoint[MAXPLAYERS+1];
int iMaxRevivePoint;
int iReviveScore;

float fMaxDistance;
float fReviveDelay;

new Handle:f_respawn = INVALID_HANDLE;
new Handle:c_gameconfig;

new Handle:HGameTimer = INVALID_HANDLE;

public void OnPluginStart() {
	cvarEnable = CreateConVar("sm_medic_enabled", "1", "Enable Medic", FCVAR_NOTIFY);
	cvarMedic = CreateConVar("sm_medic_class", "breacher", "Class name of Medic", FCVAR_NOTIFY);
	cvarDelay = CreateConVar("sm_medic_delay", "10", "Delay for revive", FCVAR_NOTIFY);
	cvarMaxRevive = CreateConVar("sm_medic_rp", "8", "max revive point for revive", FCVAR_NOTIFY);
	cvarMaxDistance = CreateConVar("sm_medic_distance", "100", "Distance for revive", FCVAR_NOTIFY);
	cvarMedicItem = CreateConVar("sm_medic_item", "kabar", "Item for revive", FCVAR_NOTIFY);
	cvarReviveScore = CreateConVar("sm_medic_score", "50", "Get score when revive", FCVAR_NOTIFY);

	HookConVarChange(cvarEnable,cvarUpdate);
	HookConVarChange(cvarMedic,cvarUpdate);
	HookConVarChange(cvarDelay,cvarUpdate);
	HookConVarChange(cvarMaxRevive,cvarUpdate);
	HookConVarChange(cvarMaxDistance,cvarUpdate);
	HookConVarChange(cvarMedicItem,cvarUpdate);
	HookConVarChange(cvarReviveScore,cvarUpdate);

	c_gameconfig = LoadGameConfigFile("insurgency.games");
	if (c_gameconfig == INVALID_HANDLE) {
		SetFailState("Fatal Error: Missing File \"insurgency.games\"!");
	}

	StartPrepSDKCall(SDKCall_Player);
	decl String:game[40];
	GetGameFolderName(game, sizeof(game));
	if (StrEqual(game, "insurgency")) {
		PrepSDKCall_SetFromConf(c_gameconfig, SDKConf_Signature, "ForceRespawn");
	}
	if (StrEqual(game, "doi")) {
		PrepSDKCall_SetFromConf(c_gameconfig, SDKConf_Virtual, "ForceRespawn");
	}
	f_respawn = EndPrepSDKCall();
	if (f_respawn == INVALID_HANDLE) {
		SetFailState("Fatal Error: Unable to find ForceRespawn");
	}
	
	HookEvent("player_pick_squad", Event_PlayerPickSquad);
	HookEvent("weapon_fire", Event_WeaponFired);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("controlpoint_captured", Event_Captured);
	HookEvent("object_destroyed", Event_Captured);
	HookEvent("round_start", Event_Captured);
	HookEvent("round_begin", Event_Captured);

	UpdateCvar();
}

public OnMapStart() {
	SDKHook(GetPlayerResourceEntity(), SDKHook_ThinkPost, HookThinkPost);
}

public cvarUpdate(Handle:cvar, const String:oldvalue[], const String:newvalue[]) {
	UpdateCvar();
}

public UpdateCvar() {
	iEnabled = GetConVarBool(cvarEnable);
	iMaxRevivePoint = GetConVarInt(cvarMaxRevive);
	iReviveScore = GetConVarInt(cvarReviveScore);
	fMaxDistance = GetConVarFloat(cvarMaxDistance);
	fReviveDelay = GetConVarFloat(cvarDelay);
	GetConVarString(cvarMedic, sType, sizeof(sType));
	GetConVarString(cvarMedicItem, sItem, MAXWEAPONNAME);
}

public OnClientPutInServer(client) {
	RespawnTarget[client] = 0;
	RespawnTimer[client] = INVALID_HANDLE;
	bMedicEnabled[client] = false;
	iSoulDetected[client] = 0;
	bPlayerJoined[client] = false;
	if (HGameTimer == INVALID_HANDLE) {
		HGameTimer = CreateTimer(1.0, FTimer,_, TIMER_REPEAT);
	}
	RespawnCount[client] = 0;
}

// function that using in game
public OneGameFrame() {
	decl String:weaponName[MAXWEAPONNAME];
	int i;
	int j;
	int s;
	for(i = 1; i < MaxClients + 1; i++) {
		if (bMedicEnabled[i] && IsValidPlayer(i) && !IsFakeClient(i)) {
			decl Float:vecFrom[3];
			GetClientEyePosition(i, vecFrom);
			GetClientWeapon(i, weaponName, MAXWEAPONNAME);
			if (RespawnTimer[i] != INVALID_HANDLE) {

				if (IsValidPlayer(RespawnTarget[i]) && !IsPlayerAlive(RespawnTarget[i]) && StrContains(weaponName, sItem, false) != -1 && GetVectorDistance(vecFrom, DeadPosition[RespawnTarget[i]]) <= fMaxDistance) {
					PrintCenterText(i, "Reviving...");
				} else {
					PrintCenterText(i, "Cancel reviving");
					RespawnTarget[i] = 0;
					new Handle:temp = RespawnTimer[i];
					RespawnTimer[i] = INVALID_HANDLE;
					KillTimer(temp);
				}
			} else if (IsPlayerAlive(i)) {
				// detect soul
				s = iSoulDetected[i];
				if (IsValidPlayer(s) && !IsPlayerAlive(s)) {
					if (!(GetVectorDistance(vecFrom, DeadPosition[s]) <= fMaxDistance)) {
						iSoulDetected[i] = 0;
					}
				} else {
					iSoulDetected[i] = 0;
					for(j = 1; j < MaxClients + 1; j++) {
						if (IsValidPlayer(j) && bPlayerJoined[j] == true && !IsPlayerAlive(j) && !IsFakeClient(i) && GetVectorDistance(vecFrom, DeadPosition[j]) <= fMaxDistance && i != j) {
							iSoulDetected[i] = j;
							PrintCenterText(i, (iRevivePoint[i] > 0) ? "A soul detected..." : "A soul is detected but you can't do any thing...");
							break;
						}
					}
				}
			}
		}
	}
}

// hook
public HookThinkPost(iEnt) {
	if (iEnabled) {
		int offset = FindSendPropInfo("CINSPlayerResource", "m_iPlayerScore");
		int i;

		decl iTotalScore[MAXPLAYERS+1];
		GetEntDataArray(iEnt, offset, iTotalScore, MaxClients + 1);

		for(i = 0; i < MaxClients + 1; ++i) {
			if (IsValidPlayer(i) && RespawnCount[i] > 0) {
				iTotalScore[i] += RespawnCount[i] * iReviveScore;
			}
		}

		SetEntDataArray(iEnt, offset, iTotalScore, MaxClients + 1);
	}
}

// events
public Action:Event_PlayerPickSquad(Handle:event, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId( GetEventInt( event, "userid" ) );
	bPlayerJoined[client] = true;
	bMedicEnabled[client] = false;
	decl String:class_template[64];
	GetEventString(event, "class_template",class_template,sizeof(class_template));
	if(IsValidPlayer(client) && strlen(class_template) > 1) {
		strcopy(sClass[client], 64, class_template);
		if (StrContains(sClass[client], sType, false) != -1) {
			bMedicEnabled[client] = true;
			if (RespawnTimer[client] != INVALID_HANDLE) {
				KillTimer(RespawnTimer[client]);
			}
			RespawnTimer[client] = INVALID_HANDLE;
			decl String:user_name[MAXUSERNAME];
			GetClientName(client, user_name, MAXUSERNAME);
			PrintCenterTextAll("Now %s is Medic.", user_name);
		}
	}
	return Plugin_Continue;
}

public Action:Event_WeaponFired(Handle:event, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId( GetEventInt( event, "userid" ) );
	decl String:weapon_name[MAXWEAPONNAME];
	GetClientWeapon(client, weapon_name, MAXWEAPONNAME);

	if (!iEnabled || !IsValidPlayer(client)) {
		return Plugin_Continue;
	}	
	
	if (bMedicEnabled[client] && RespawnTimer[client] == INVALID_HANDLE && iRevivePoint[client] > 0) {
		int target = iSoulDetected[client];
		if (IsValidPlayer(target) && !IsFakeClient(target) && !IsPlayerAlive(target) && StrContains(weapon_name, sItem) != -1) {
			RespawnTimer[client] = CreateTimer(fReviveDelay, FRevive, client);
			RespawnTarget[client] = target;
		}
	}

	return Plugin_Continue;
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId( GetEventInt( event, "userid" ) );
	if (!IsFakeClient(client)) {
		GetClientAbsOrigin(client, DeadPosition[client]);
	}

	if (bMedicEnabled[client] && RespawnTimer[client] != INVALID_HANDLE) {
		PrintCenterText(client, "Cancel reviving");
		RespawnTarget[client] = 0;
		if (RespawnTimer[client] != INVALID_HANDLE) {
			KillTimer(RespawnTimer[client]);
		}
		RespawnTimer[client] = INVALID_HANDLE;
	}
	return Plugin_Continue;
}

public Action:Event_Captured(Handle:event, const String:name[], bool:dontBroadcast) {
	for(new i = 0; i < MaxClients + 1; i++) {
		iRevivePoint[i] = iMaxRevivePoint;
	}
	return Plugin_Continue;
}

// timer function
public Action:FRevive(Handle:timer, any client) {
	int s = RespawnTarget[client];
	if (!IsValidPlayer(s) || IsPlayerAlive(s) || !IsPlayerAlive(client)) {
		PrintCenterText(client, "A soul has disappeared...");
		RespawnTarget[client] = 0;
		RespawnTimer[client] = INVALID_HANDLE;
		return Plugin_Handled;
	}
	SDKCall(f_respawn, RespawnTarget[client]);
	TeleportEntity(s, DeadPosition[s], NULL_VECTOR, NULL_VECTOR);
	RespawnTarget[client] = 0;
	RespawnTimer[client] = INVALID_HANDLE;
	iRevivePoint[client]--;
	PrintCenterText(client, "Some one is revived...");
	RespawnCount[client]++;
	return Plugin_Handled;
}

public Action:FTimer(Handle:timer) {
	OneGameFrame();
	return Plugin_Continue;
}

// etc
public IsValidPlayer(client)
{
	if (client == 0)
		return false;
	
	if (!IsClientConnected(client))
		return false;
	
	if (!IsClientInGame(client))
		return false;
	
	return true;
}

stock GetRealClientCount(bool:inGameOnly = true)
{
	new clients = 0;
	for( new i = 1; i <= MaxClients + 1; i++) {
		if ( ( ( inGameOnly ) ? IsClientInGame( i ) : IsClientConnected( i ) ) && !IsFakeClient( i ) ) {
			clients++;
		}
	}
	return clients;
}