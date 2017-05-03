#include <sourcemod>
#include <sdktools>
#include <adt_array>
#include <timers>

#define PLUGIN_DESCRIPTION "Handling respawn system"
#define PLUGIN_NAME "CheckpointRespawn"
#define PLUGIN_VERSION "0.5.4"
#define PLUGIN_WORKING "1"
#define PLUGIN_LOG_PREFIX "CPRESPAWN"
#define PLUGIN_AUTHOR "rrrfffrrr"
#define PLUGIN_URL ""

#define MAXHINTSIZE 128

/*
* 할일 : 카운터 어택 체크, 렉 제거
*/

public Plugin:myinfo = {
        name            = PLUGIN_NAME,
        author          = PLUGIN_AUTHOR,
        description     = PLUGIN_DESCRIPTION,
        version         = PLUGIN_VERSION,
        url             = PLUGIN_URL
};

new Handle:cvarEnable = INVALID_HANDLE;
new Handle:cvarStop = INVALID_HANDLE;
new Handle:cvarRTimeIns = INVALID_HANDLE;
new Handle:cvarRTimeSec = INVALID_HANDLE;
new Handle:cvarDefaultPointIns = INVALID_HANDLE;
new Handle:cvarAddPointIns = INVALID_HANDLE;
new Handle:cvarMaxPointSec = INVALID_HANDLE;
new Handle:cvarDisplay = INVALID_HANDLE;
new Handle:cvarDisplayDelay = INVALID_HANDLE;

new Handle:queue_ins = INVALID_HANDLE;

new Handle:f_respawn = INVALID_HANDLE;
new Handle:c_gameconfig;
bool v_capturing = false;

int i_display = 2;	//0 = don't display, 1 = display teams, 2 = display all, 3 = display enemy

int i_maxRespawnIns = 0;	// 0 is infinity
int i_maxRespawnSec = 0;

int i_remainPointIns = 0;
int i_remainPointSec = 0;

new Handle:t_respawn[MAXPLAYERS+1];
new Handle:t_display = INVALID_HANDLE;

public void OnPluginStart()
{
	cvarEnable = CreateConVar("sm_botrespawn_enabled", "1", "Let bot spawn infinitly before touch the point", FCVAR_NOTIFY);
	cvarStop = CreateConVar("sm_botrespawn_stop_when_touch", "0", "Stop spawn bot when touch the point", FCVAR_NOTIFY);
	cvarRTimeIns = CreateConVar("sm_botrespawn_delay_ins", "1", "How many times delay before spawn for insurgent, 0 is disable", FCVAR_NOTIFY);
	cvarRTimeSec = CreateConVar("sm_botrespawn_delay_sec", "60", "How many times delay before spawn for security, 0 is disable", FCVAR_NOTIFY);
	cvarDefaultPointIns = CreateConVar("sm_botrespawn_rp_ins", "20", "How many times can be respawn for insurgent, 0 is infinity", FCVAR_NOTIFY);
	cvarAddPointIns = CreateConVar("sm_botrespawn_rp_add_ins", "5", "How many times can be respawn for insurgent when more player has connected", FCVAR_NOTIFY);
	cvarMaxPointSec = CreateConVar("sm_botrespawn_rp_sec", "10", "How many times can be respawn for security, 0 is infinity", FCVAR_NOTIFY);
	cvarDisplay = CreateConVar("sm_botrespawn_display", "2", "Display respawn point(0 = don't display, 1 = display teams, 2 = display all)", FCVAR_NOTIFY);
	cvarDisplayDelay = CreateConVar("sm_botrespawn_display_delay", "1", "Display delay(sec)", FCVAR_NOTIFY);

	HookConVarChange(cvarDefaultPointIns,cvarUpdate);
	HookConVarChange(cvarMaxPointSec,cvarUpdate);
	HookConVarChange(cvarDisplay,cvarUpdate);

	queue_ins = CreateArray();

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

	HookEvent("round_start", Event_BeginRound);
	HookEvent("round_begin", Event_StartRound);
	HookEvent("player_death", Event_Death);
	HookEvent("player_spawn", Event_Spawn);
	HookEvent("controlpoint_captured", Event_Captured);
	HookEvent("object_destroyed", Event_Captured);
	HookEvent("controlpoint_starttouch", Event_Capturing);

	UpdateValues();
}

public cvarUpdate(Handle:cvar, const String:oldvalue[], const String:newvalue[]) {
	UpdateValues();
}

public UpdateValues()
{
	RPUpdate();
	i_display = GetConVarInt(cvarDisplay);
}

public RPUpdate() {
	i_maxRespawnIns = GetConVarInt(cvarDefaultPointIns) + (GetRealClientCount() * GetConVarInt(cvarAddPointIns));
	i_maxRespawnSec = GetConVarInt(cvarMaxPointSec);
}

public Action:Event_BeginRound(Handle:event, const String:name[], bool:dontBroadcast)
{
	FStart();
	return Plugin_Continue;
}

public Action:Event_StartRound(Handle:event, const String:name[], bool:dontBroadcast)
{
	FStart();
	return Plugin_Continue;
}

public FStart() {
	v_capturing = false;
	RPUpdate();
	i_remainPointIns = i_maxRespawnIns;
	i_remainPointSec = i_maxRespawnSec;

	if (t_display == INVALID_HANDLE) {
		t_display = CreateTimer(GetConVarFloat(cvarDisplayDelay), FDisplayPoint,_, TIMER_REPEAT);
	}
}

public Action:Event_Death(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!GetConVarBool(cvarEnable)) {
		return Plugin_Continue;
	}
	if (v_capturing && GetConVarBool(cvarStop)) {
		PrintToServer("Bot respawn has been restricted");
		return Plugin_Continue;
	}

	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!IsValidPlayer(client)) {
		return Plugin_Continue;
	}

	float delay = 0.0;
	if (IsFakeClient(client)) {
		if (i_maxRespawnIns == 0 || i_remainPointIns > 0) {
			delay = GetConVarFloat(cvarRTimeIns);
			i_remainPointIns--;
			PrintToServer("Insurgent RP remain %i of %i", i_remainPointIns, i_maxRespawnIns);
		}
	} else {
		if (i_maxRespawnSec == 0 || i_remainPointSec > 0) {
			delay = GetConVarFloat(cvarRTimeSec);
			i_remainPointSec--;
			PrintToServer("Security RP remain %i of %i", i_remainPointSec, i_maxRespawnSec);
		}
	}

/*//Old feature
	if (delay > 0) {
		t_respawn[client] = CreateTimer(delay, FSpawn, client);
	}
*/
	PushArrayCell();

	return Plugin_Continue;
}


public Action:Event_Spawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (t_respawn[client] != INVALID_HANDLE) {
		KillTimer(t_respawn[client]);
		t_respawn[client] = INVALID_HANDLE;
	}
	return Plugin_Continue;
}

public Action:Event_Captured(Handle:event, const String:name[], bool:dontBroadcast) {
	if (!GetConVarBool(cvarEnable)) {
		return Plugin_Continue;
	}
	v_capturing = false;
	RPUpdate();
	i_remainPointIns = i_maxRespawnIns;
	i_remainPointSec = i_maxRespawnSec;
	return Plugin_Continue;
}

public Action:Event_Capturing(Handle:event, const String:name[], bool:dontBroadcast) {
	if (!GetConVarBool(cvarEnable)) {
		return Plugin_Continue;
	}
	v_capturing = true;
	return Plugin_Continue;
}

public Action:FSpawn(Handle:timer, client)
{
	if (IsClientInGame(client) && IsClientConnected(client) && !IsPlayerAlive(client)) {
		SDKCall(f_respawn, client);
		t_respawn[client] = INVALID_HANDLE;
	}
}

public Action:FDisplayPoint(Handle:timer) {
	if (i_display == 0) {
		return Plugin_Continue;
	}

	decl String:hint[MAXHINTSIZE];

	if (i_display == 1) {
		Format(hint, MAXHINTSIZE, "남은 Security 리스폰 포인트 : %i", i_remainPointSec + GetRealClientCount());
	} else if (i_display == 2) {
		Format(hint, MAXHINTSIZE, "남은 Security 리스폰 포인트 : %i\n남은 Insurgent 리스폰 포인트 : %i", i_remainPointSec + GetRealClientCount(), i_remainPointIns + GetFakeClientCount());
	} else {
		Format(hint, MAXHINTSIZE, "남은 Insurgent 리스폰 포인트 : %i", i_remainPointIns + GetFakeClientCount());
	}

	for( new i = 1; i <= GetMaxClients(); i++) {
		if ( IsValidPlayer(i) && !IsFakeClient(i) ) {
			PrintHintText(i, "%s", hint);
		}
	}
	return Plugin_Continue;
}

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
	for( new i = 1; i <= GetMaxClients(); i++) {
		if ( ( ( inGameOnly ) ? IsClientInGame( i ) : IsClientConnected( i ) ) && !IsFakeClient( i ) ) {
			clients++;
		}
	}
	return clients;
}

stock GetFakeClientCount(bool:inGameOnly = true)
{
	new clients = 0;
	for( new i = 1; i <= GetMaxClients(); i++) {
		if ( ( ( inGameOnly ) ? IsClientInGame( i ) : IsClientConnected( i ) ) && IsFakeClient( i ) ) {
			clients++;
		}
	}
	return clients;
}