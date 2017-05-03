#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <files>

#define PLUGIN_DESCRIPTION "Challenge"
#define PLUGIN_NAME "Challenge"
#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_WORKING "1"
#define PLUGIN_LOG_PREFIX "Challenge"
#define PLUGIN_AUTHOR "rrrfffrrr"
#define PLUGIN_URL ""

#define TEXTMAXSIZE 256
#define MAXPATHSIZE 2048

public Plugin:myinfo = {
        name            = PLUGIN_NAME,
        author          = PLUGIN_AUTHOR,
        description     = PLUGIN_DESCRIPTION,
        version         = PLUGIN_VERSION,
        url             = PLUGIN_URL
};

new Handle:cvarEnabled = INVALID_HANDLE;
new String:sChallengeText[TEXTMAXSIZE];

public OnPluginStart() {
	cvarEnabled = CreateConVar("sm_challenge_enabled", "1", "Show challenge text when join", FCVAR_NOTIFY);

	LoadNewString();
	TrimString(sChallengeText);
	HookEvent("player_first_spawn", Event_PlayerSpawn);

	RegAdminCmd("sm_challenge_reload", Command_Reload, ADMFLAG_SLAY, "Reload challenge data, usage : sm_challenge_reload");
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast) {
	if (!GetConVarBool(cvarEnabled)) {
		return Plugin_Continue;
	}
	new client = GetClientOfUserId( GetEventInt( event, "userid" ) );
	PrintToChat(client, sChallengeText);
	return Plugin_Continue;
}

public Action Command_Reload(int client, int args) {
	LoadNewString();
	return Plugin_Handled;
}

LoadNewString() {
	decl String:path[MAXPATHSIZE];
	BuildPath(Path_SM, path, MAXPATHSIZE, "challenge.txt");
	new Handle:fFile = OpenFile(path, "r");
	if (fFile == INVALID_HANDLE) {
		SetFailState("Fatal Error: Missing File \"challenge.txt\"!");
	}

	if(!(ReadFileString(fFile, sChallengeText, TEXTMAXSIZE))) {
		SetFailState("Fatal Error: Cannot read string from file!");
	}
	CloseHandle(fFile);
}