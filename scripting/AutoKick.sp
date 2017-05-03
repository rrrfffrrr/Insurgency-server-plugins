#include <sourcemod>

#define PLUGIN_DESCRIPTION "Medic"
#define PLUGIN_NAME "Medic"
#define PLUGIN_VERSION "0.8.1"
#define PLUGIN_WORKING "1"
#define PLUGIN_LOG_PREFIX "Medic"
#define PLUGIN_AUTHOR "rrrfffrrr"
#define PLUGIN_URL ""
/*
* 죽은 위치 표시, 낑김 제거
*/

public Plugin:myinfo = {
        name            = PLUGIN_NAME,
        author          = PLUGIN_AUTHOR,
        description     = PLUGIN_DESCRIPTION,
        version         = PLUGIN_VERSION,
        url             = PLUGIN_URL
};

new Handle:cvarEnable = INVALID_HANDLE;

public void OnPluginStart() {
	cvarEnable = CreateConVar("sm_autokick_enabled", "0", "Enable Autokick", FCVAR_NOTIFY);
}

public OnClientPutInServer(client) {
	if (GetConVarBool(cvarEnable)) {
		KickClient(client, "%s", "Unable to join server.\nReason : Server is on maintenance.");
	}
}