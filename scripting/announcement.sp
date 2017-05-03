#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <files>

#define PLUGIN_DESCRIPTION "Announcement"
#define PLUGIN_NAME "Announcement"
#define PLUGIN_VERSION "2.0.0"
#define PLUGIN_WORKING "1"
#define PLUGIN_LOG_PREFIX "anno"
#define PLUGIN_AUTHOR "rrrfffrrr"
#define PLUGIN_URL ""

#define TEXTMAXSIZE 256
#define MAXPATHSIZE 2048
#define MAXTEXTNUM  30

public Plugin:myinfo = {
        name            = PLUGIN_NAME,
        author          = PLUGIN_AUTHOR,
        description     = PLUGIN_DESCRIPTION,
        version         = PLUGIN_VERSION,
        url             = PLUGIN_URL
};

new Handle:cvarEnabled = INVALID_HANDLE;
new Handle:cvarDelay = INVALID_HANDLE;

new Handle:hTimer = INVALID_HANDLE;

new String:AnnounceText[MAXTEXTNUM][TEXTMAXSIZE];

int textNum;

public OnPluginStart() {
	cvarEnabled = CreateConVar("sm_announce_enabled", "1", "Show announcement text", FCVAR_NOTIFY);
	cvarDelay = CreateConVar("sm_announce_delay", "45", "Timer delay", FCVAR_NOTIFY);

	RegAdminCmd("sm_announce_reload", Command_Reload, ADMFLAG_SLAY, "Reload announcement data, usage : sm_announce_reload");
	
	HookConVarChange(cvarDelay,cvarUpdate);
	LoadNewString();

	hTimer = CreateTimer(GetConVarFloat(cvarDelay), FTimer,_, TIMER_REPEAT);
}

public cvarUpdate(Handle:cvar, const String:oldvalue[], const String:newvalue[]) {
	UpdateCvar();
}

public UpdateCvar() {
	if (INVALID_HANDLE != hTimer) {
		KillTimer(hTimer, false);
	}
	hTimer = CreateTimer(GetConVarFloat(cvarDelay), FTimer,_, TIMER_REPEAT);
}

public Action Command_Reload(int client, int args) {
	LoadNewString();
	return Plugin_Handled;
}

public OnClientPutInServer() {
	if (hTimer == INVALID_HANDLE) {
		hTimer = CreateTimer(GetConVarFloat(cvarDelay), FTimer,_, TIMER_REPEAT);
	}
}

public Action:FTimer(Handle:timer) {
	if (!GetConVarBool(cvarEnabled) || 0 == textNum) {
		return Plugin_Continue;
	}

	PrintToChatAll(AnnounceText[GetURandomInt() % textNum]);

	return Plugin_Continue;
}

LoadNewString() {
	textNum = 0;

	decl String:path[MAXPATHSIZE];
	BuildPath(Path_SM, path, MAXPATHSIZE, "announcement.txt");
	new Handle:fFile = OpenFile(path, "r");
	if (fFile == INVALID_HANDLE) {
		SetFailState("Fatal Error: Missing File \"announcement.txt\"!");
	}

	while(ReadFileLine(fFile, AnnounceText[textNum], TEXTMAXSIZE)) {
		TrimString(AnnounceText[textNum]);
		++textNum;
	}

	CloseHandle(fFile);
}