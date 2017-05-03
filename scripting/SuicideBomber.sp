#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <timers>

#define PLUGIN_DESCRIPTION "Make suicide bomber"
#define PLUGIN_NAME "SuicideBomber"
#define PLUGIN_VERSION "1.0.4"
#define PLUGIN_WORKING "1"
#define PLUGIN_LOG_PREFIX "Suicide"
#define PLUGIN_AUTHOR "rrrfffrrr"
#define PLUGIN_URL ""

public Plugin:myinfo = {
        name            = PLUGIN_NAME,
        author          = PLUGIN_AUTHOR,
        description     = PLUGIN_DESCRIPTION,
        version         = PLUGIN_VERSION,
        url             = PLUGIN_URL
};

new Handle:cvarEnable = INVALID_HANDLE;
new Handle:cvarBomber = INVALID_HANDLE;
new Handle:cvarRange = INVALID_HANDLE;
new Handle:cvarResist = INVALID_HANDLE;
new Handle:cvarDetoDelay = INVALID_HANDLE;

new Handle:repeater = INVALID_HANDLE;

new bool:i_enabled = false;
new String:s_type[64];
new String:s_class[MAXPLAYERS+1][64];
float f_detonate_range;
float f_resist;

public void OnPluginStart()
{
	cvarEnable = CreateConVar("sm_suicide_enabled", "1", "Let bot suicide", FCVAR_NOTIFY);
	cvarBomber = CreateConVar("sm_suicide_bomber", "sharpshooter", "Let bot suicide", FCVAR_NOTIFY);
	cvarRange = CreateConVar("sm_suicide_detonate_range", "600", "Detonate range", FCVAR_NOTIFY);
	cvarResist = CreateConVar("sm_suicide_resist", "20", "Damage resistance", FCVAR_NOTIFY);
	cvarDetoDelay = CreateConVar("sm_suicide_delay", "0.01", "Detonate delay", FCVAR_NOTIFY);

	HookConVarChange(cvarEnable,cvarUpdate);
	HookConVarChange(cvarBomber,cvarUpdate);
	HookConVarChange(cvarRange,cvarUpdate);
	HookConVarChange(cvarResist,cvarUpdate);
	HookConVarChange(cvarDetoDelay,cvarUpdate);

	HookEvent("player_pick_squad", Event_PlayerPickSquad);
	HookEvent("round_start", Event_Start);

	UpdateCvar();
}

public cvarUpdate(Handle:cvar, const String:oldvalue[], const String:newvalue[]) {
	UpdateCvar();
}

public UpdateCvar() {
	float val = GetConVarFloat(cvarResist);
	i_enabled = GetConVarBool(cvarEnable);
	f_detonate_range = GetConVarFloat(cvarRange);
	if (val == 0.0) {
		PrintToServer("Cannot change bomber resistance to zero.");
	} else {
		f_resist = 1.0 / val;
		PrintToServer("Resist is now %f", f_resist);
	}
	GetConVarString(cvarBomber, s_type, sizeof(s_type));
	CheckNames();
}

public OnMapStart() {
	PrecacheModel("models/weapons/w_ied.mdl",true);
	PrecacheSound("weapons/IED/handling/IED_throw.wav", true);
	PrecacheSound("weapons/IED/handling/IED_trigger_ins.wav", true);
	PrecacheSound("weapons/IED/water/IED_water_detonate_01.wav", true);
	PrecacheSound("weapons/IED/water/IED_water_detonate_02.wav", true);
	PrecacheSound("weapons/IED/water/IED_water_detonate_03.wav", true);
	PrecacheSound("weapons/IED/water/IED_water_detonate_dist_01.wav", true);
	PrecacheSound("weapons/IED/water/IED_water_detonate_dist_02.wav", true);
	PrecacheSound("weapons/IED/water/IED_water_detonate_dist_03.wav", true);
	PrecacheSound("weapons/IED/IED_bounce_01.wav", true);
	PrecacheSound("weapons/IED/IED_bounce_02.wav", true);
	PrecacheSound("weapons/IED/IED_bounce_03.wav", true);
	PrecacheSound("weapons/IED/IED_detonate_01.wav", true);
	PrecacheSound("weapons/IED/IED_detonate_02.wav", true);
	PrecacheSound("weapons/IED/IED_detonate_03.wav", true);
	PrecacheSound("weapons/IED/IED_detonate_dist_01.wav", true);
	PrecacheSound("weapons/IED/IED_detonate_dist_02.wav", true);
	PrecacheSound("weapons/IED/IED_detonate_dist_03.wav", true);
	PrecacheSound("weapons/IED/IED_detonate_far_dist_01.wav", true);
	PrecacheSound("weapons/IED/IED_detonate_far_dist_02.wav", true);
	PrecacheSound("weapons/IED/IED_detonate_far_dist_03.wav", true);
}

public Action:Event_Start(Handle:event, const String:name[], bool:dontBroadcast) {
	RefreshTimer();
	return Plugin_Continue;
}

public RefreshTimer() {
	if (repeater != INVALID_HANDLE) {
		KillTimer(repeater);
		repeater = INVALID_HANDLE;
	}
	repeater = CreateTimer(1.0, FFrame,_, TIMER_REPEAT);
}

// make bomber more tank
public OnClientPutInServer(client) {
	SDKHook(client, SDKHook_TraceAttack, FTraceAttack);
}


public Action:FTraceAttack(victim, &attacker, &inflictor, &Float:damage, &damagetype, &ammotype, hitbox, hitgroup) {
	if (i_enabled && IsFakeClient(victim) && StrContains(s_class[victim], s_type, false) != -1) {
		damage *= f_resist;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}


public Event_PlayerPickSquad(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId( GetEventInt( event, "userid" ) );
	decl String:class_template[64];
	GetEventString(event, "class_template",class_template,sizeof(class_template));
	if(IsValidPlayer(client) && strlen(class_template) > 1) {
		strcopy(s_class[client], 64, class_template);
	}
	return;
}

public Action:FFrame(Handle:timer) {
	for(new i = 1; i < MaxClients  + 1; i++) {
		if (IsValidPlayer(i) && IsFakeClient(i) && IsPlayerAlive(i)) {
			check_explode(i);
		}
	}
	return Plugin_Continue;
}

public check_explode(client) {

	if (!i_enabled || StrContains(s_class[client], s_type, false) == -1) {
		SetEntityRenderColor(client, 255, 255, 255, 255);
		return;
	}

	SetEntityRenderColor(client, 255, 0, 0, 255);

	new Float:vecOrigin[3];
	new Float:vecAngles[3];
	GetClientEyePosition(client, vecOrigin);

	bool check = false;
	float distance = 0.0;

	for(new j = 1; j < MaxClients + 1; j++) {
		if (IsValidPlayer(j) && !IsFakeClient(j) && IsPlayerAlive(j)) {
			GetClientEyePosition(j, vecAngles);
			distance = GetVectorDistance(vecAngles, vecOrigin);
			if (distance < f_detonate_range) {
				check = true;
			}
		}
	}

	if (!check) {
		return;
	}

	// by jaredballou
	new ent = CreateEntityByName("grenade_ied");
	if(IsValidEntity(ent))
	{
		vecAngles[0] = vecAngles[1] = vecAngles[2] = 0.0;
		TeleportEntity(ent, vecOrigin, vecAngles, vecAngles);
		SetEntPropEnt(ent, Prop_Data, "m_hOwnerEntity", client);
		SetEntProp(ent, Prop_Data, "m_nNextThinkTick", GetConVarFloat(cvarDetoDelay)); //for smoke
		SetEntProp(ent, Prop_Data, "m_takedamage", 2);
		SetEntProp(ent, Prop_Data, "m_iHealth", 1);
		DispatchSpawn(ent);
		ActivateEntity(ent);
		if (DispatchSpawn(ent)) {
			DealDamage(ent,380,client,DMG_BLAST,"weapon_c4_ied");
		}
	}
	
	return;
}

// by jaredballou
DealDamage(victim,damage,attacker=0,dmg_type=DMG_GENERIC,String:weapon[]="")
{
	if(victim>0 && IsValidEdict(victim) && damage>0)
	{
		new String:dmg_str[16];
		IntToString(damage,dmg_str,16);
		new String:dmg_type_str[32];
		IntToString(dmg_type,dmg_type_str,32);
		new pointHurt=CreateEntityByName("point_hurt");
		if(pointHurt)
		{
			DispatchKeyValue(victim,"targetname","hurtme");
			DispatchKeyValue(pointHurt,"DamageTarget","hurtme");
			DispatchKeyValue(pointHurt,"Damage",dmg_str);
			DispatchKeyValue(pointHurt,"DamageType",dmg_type_str);
			if(!StrEqual(weapon,""))
			{
				DispatchKeyValue(pointHurt,"classname",weapon);
			}
			DispatchSpawn(pointHurt);
			AcceptEntityInput(pointHurt,"Hurt",(attacker>0)?attacker:-1);
			DispatchKeyValue(pointHurt,"classname","point_hurt");
			DispatchKeyValue(victim,"targetname","donthurtme");
			RemoveEdict(pointHurt);
		}
	}
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

public CheckNames() {
	for(new i = 1; i < MaxClients + 1; ++i) {
		if (IsValidPlayer(i)) {
			PrintToServer("%i is %s, and %s", i, IsFakeClient(i) ? "bot" : "player", s_class[i]);
		}
	}
}