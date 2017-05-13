#include <sourcemod>
#include <sdktools>
#include <adt_array>
#include <timers>

#define PLUGIN_DESCRIPTION "Handling bot respawn system"
#define PLUGIN_NAME "RespawnBots"
#define PLUGIN_VERSION "0.0.1"
#define PLUGIN_WORKING "1"
#define PLUGIN_LOG_PREFIX "BRESPAWN"
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
new Handle:cvarRTime = INVALID_HANDLE;
new Handle:cvarDefaultPoint = INVALID_HANDLE;
new Handle:cvarAddPoint = INVALID_HANDLE;
new Handle:cvarDisplay = INVALID_HANDLE;
new Handle:cvarDisplayDelay = INVALID_HANDLE;

new Handle:f_respawn = INVALID_HANDLE;
new Handle:c_gameconfig;
bool v_capturing = false;

int i_display = 0;	//0 = don't display, 1 = display teams, 2 = display all, 3 = display enemy

int i_maxRespawn = 0;
int i_remainPoint = 0;

new Handle:t_respawn[MAXPLAYERS+1];
new Handle:t_display = INVALID_HANDLE;

new Handle:t_frame = INVALID_HANDLE;

public void OnPluginStart()
{
	cvarEnable = CreateConVar("sm_botrespawn_enabled", "1", "Let bot spawn infinitly before touch the point", FCVAR_NOTIFY);
	cvarStop = CreateConVar("sm_botrespawn_stop_when_touch", "0", "Stop spawn bot when touch the point", FCVAR_NOTIFY);
	cvarRTime = CreateConVar("sm_botrespawn_delay", "1", "How many times delay before spawn for insurgent, 0 is disable", FCVAR_NOTIFY);
	cvarDefaultPoint = CreateConVar("sm_botrespawn_rp", "5", "How many times can be respawn for insurgent, 0 is infinity", FCVAR_NOTIFY);
	cvarAddPoint = CreateConVar("sm_botrespawn_rp_add", "5", "How many times can be respawn for insurgent when more player has connected", FCVAR_NOTIFY);
	cvarDisplay = CreateConVar("sm_botrespawn_display", "1", "Display respawn point(0 = don't display, 1 = display)", FCVAR_NOTIFY);
	cvarDisplayDelay = CreateConVar("sm_botrespawn_display_delay", "1", "Display delay(sec)", FCVAR_NOTIFY);

	HookConVarChange(cvarRTime,cvarUpdate);
	HookConVarChange(cvarDefaultPoint,cvarUpdate);
	HookConVarChange(cvarAddPoint,cvarUpdate);
	HookConVarChange(cvarDisplay,cvarUpdate);

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
	FStart();
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
	i_maxRespawn = GetConVarInt(cvarDefaultPoint) + (GetRealClientCount() * GetConVarInt(cvarAddPoint));
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
	i_remainPoint = i_maxRespawn;

	if (t_display == INVALID_HANDLE) {
		t_display = CreateTimer(GetConVarFloat(cvarDisplayDelay), FDisplayPoint,_, TIMER_REPEAT);
	}

	if (t_frame == INVALID_HANDLE) {
		t_frame = CreateTimer(1.0, FFrame,_, TIMER_REPEAT);
	}
}

public Action:FFrame(Handle:timer) {
	for(new i = 1; i < MaxClients+1; ++i) {
		if (IsValidPlayer(i) && IsFakeClient(i) && !IsPlayerAlive(i) && i_remainPoint > 0) {
			SDKCall(f_respawn, i);
			i_remainPoint--;
			break;
		}
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
		if (i_maxRespawn == 0 || i_remainPoint > 0) {
			delay = GetConVarFloat(cvarRTime);
			PrintToServer("Insurgent RP remain %i of %i", i_remainPoint, i_maxRespawn);
		}
	}

	if (delay > 0) {
		t_respawn[client] = CreateTimer(delay, FSpawn, client);
	}

	return Plugin_Continue;
}


public Action:Event_Spawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	return Plugin_Continue;
}

public Action:Event_Captured(Handle:event, const String:name[], bool:dontBroadcast) {
	if (!GetConVarBool(cvarEnable)) {
		return Plugin_Continue;
	}
	v_capturing = false;
	RPUpdate();
	i_remainPoint = i_maxRespawn;
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
		t_respawn[client] = INVALID_HANDLE;
	}
}

public Action:FDisplayPoint(Handle:timer) {
	if (i_display == 0) {
		return Plugin_Continue;
	}

	decl String:hint[MAXHINTSIZE];

	if (i_display == 1) {
		Format(hint, MAXHINTSIZE, "남은 Insurgent : %i", ((i_remainPoint > 0) ? i_remainPoint : 0) + GetFakeClientCount());
	}

	for( new i = 1; i < MaxClients+1; i++) {
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
	for( new i = 1; i < MaxClients+1; i++) {
		if ( ( ( inGameOnly ) ? IsClientInGame( i ) : IsClientConnected( i ) ) && !IsFakeClient( i ) ) {
			clients++;
		}
	}
	return clients;
}

stock GetFakeClientCount(bool:inGameOnly = true)
{
	new clients = 0;
	for( new i = 1; i < MaxClients+1; i++) {
		if ( ( ( inGameOnly ) ? IsClientInGame( i ) : IsClientConnected( i ) ) && IsFakeClient( i ) && IsPlayerAlive(i)) {
			clients++;
		}
	}
	return clients;
}
