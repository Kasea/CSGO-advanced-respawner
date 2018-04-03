#pragma semicolon 1

#define PLUGIN_AUTHOR "Kasea"
#define PLUGIN_VERSION "1.0.0"
#define CS_TEAM_NONE		0	/**< No team yet. */
#define CS_TEAM_SPECTATOR	1	/**< Spectators. */
#define CS_TEAM_T 			2	/**< Terrorists. */
#define CS_TEAM_CT			3	/**< Counter-Terrorists. */
#define CHANGERTV 600.0
#define MAX_TIME 0.5
#define MAX_DEATH 5

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <colors_kasea>

public Plugin myinfo = 
{
	name = "Advanced-Respawner",
	author = PLUGIN_AUTHOR,
	description = "",
	version = PLUGIN_VERSION,
	url = ""
};

//variables
int ConnectionCounter;
int g_iDeathCount[MAXPLAYERS + 1];
char CurrentMap[64];
float respawntime = 9000.0;
bool g_bSpawnKillOn = false;
bool g_bMapJustStarted = false;
float g_fSpawnTime[MAXPLAYERS + 1];
float g_fStartTime;
bool g_bRespawnSprung = true;
bool g_bConnected = false;

//Handles
Handle g_hSQL = INVALID_HANDLE;
Handle g_tSpawn = INVALID_HANDLE;

//Cvars
Handle sm_respawn_pistol = INVALID_HANDLE;
Handle sm_respawn_detect = INVALID_HANDLE;
Handle sm_respawn_endround = INVALID_HANDLE;
Handle sm_respawn_knife = INVALID_HANDLE;
Handle sm_respawn_no_drop = INVALID_HANDLE;
Handle sm_respawn_rtv = INVALID_HANDLE;
Handle sm_respawn_rtv_time = INVALID_HANDLE;

public void OnPluginStart()
{
	LoadTranslations("advanced-respawner");
	sm_respawn_pistol = CreateConVar("sm_respawn_pistol", "0", "1 Enabled or 0 Disabled", _, true, 0.0, true, 1.0);
	sm_respawn_detect = CreateConVar("sm_respawn_detect", "1", "1 Enabled or 0 Disabled, Should it detect spawnkill and update the plugin accordingly.", _, true, 0.0, true, 1.0);
	sm_respawn_endround = CreateConVar("sm_respawn_endround", "1", "1 Enabled or 0 Disabled, Should the plugin use it's end round system?", _, true, 0.0, true, 1.0);
	sm_respawn_knife = CreateConVar("sm_respawn_knife", "1", "1 Enabled or 0 Disabled", _, true, 0.0, true, 1.0);
	sm_respawn_no_drop = CreateConVar("sm_respawn_no_drop", "0", "1 Enabled or 0 Disabled Make it so players don't drop their weapons upon death, or using g", _, true, 0.0, true, 1.0);
	sm_respawn_rtv = CreateConVar("sm_respawn_rtv", "1", "Change rtv to instant rtv if respawn time is x?", _, true, 0.0, true, 1.0);
	sm_respawn_rtv_time = CreateConVar("sm_respawn_rtv_time", "600.0", "Yo dawg, this is the x amount of time we talked about.", _, true, 1.0, true, 5000.0);
	
	ConnectSQL();
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_team", Event_ChangeTeam);
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("player_death", Event_Death);
	
	RegAdminCmd("sm_kasea_respawner", temp, ADMFLAG_ROOT);
	RegAdminCmd("sm_ar_time", cmd_artime, ADMFLAG_BAN);
	AutoExecConfig(true, "advanced-respawner");
}

public Action cmd_artime(int client, int args)
{
	if(args>0)
	{
		char arg[6];
		GetCmdArg(1, arg, sizeof(arg));
		RemakeArTime(StringToFloat(arg));
	}else
	{
		ReplyToCommand(client, "%f is current respawn time", respawntime);
	}
}

public Action temp(int client, int args)
{
	CPrintToChatAll("[Debug] %b, artime: %f, map started: %b", g_bSpawnKillOn, respawntime, g_bMapJustStarted);
}

/*******************************
**********GAME-EVENTS***********
*******************************/

public Action CS_OnTerminateRound(&Float:delay, &CSRoundEndReason:reason)
{
	//CPrintToChatAll("[Debug] Terminate round");
	if(GetConVarBool(sm_respawn_endround) && !g_bMapJustStarted && !g_bSpawnKillOn)
	{
		int timeleft;
		GetMapTimeLeft(timeleft);
		if(timeleft < 5 || timeleft < 0)
			return Plugin_Continue;

		if(timeleft > 5 && !g_bSpawnKillOn)
			return Plugin_Handled;
		
		if(howManyPlayersConnected() == 1 && !g_bSpawnKillOn) return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action CS_OnCSWeaponDrop(int client, int weaponIndex)
{
	if(GetConVarBool(sm_respawn_no_drop))
		return Plugin_Handled;
	return Plugin_Continue;
}

public OnMapStart()
{
	g_bSpawnKillOn = false;
	g_bMapJustStarted = true;
	GetCurrentMap(CurrentMap, sizeof(CurrentMap));
	GetArTime();
	ServerCommand("mp_warmuptime 15");
	ServerCommand("mp_warmup_start");
}

public Action Timer_MapStarted(Handle timer)
{
	g_bMapJustStarted = false;
}

public OnMapEnd()
{
	FixSpawnHandle();
	SetArTime();
	g_bRespawnSprung = true;
	//ServerCommand("sm plugins reload advanced-respawner");
}

/*******************************
************EVENTS**************
*******************************/
public Action Event_RoundStart(Handle event, char[] name, bool dontBroadcast)
{
	if(g_bMapJustStarted)
		CreateTimer(20.0, Timer_MapStarted);
	FixSpawnHandle();
	g_bRespawnSprung = false;
	g_bSpawnKillOn = false;
	g_tSpawn = CreateTimer(respawntime, end_spawn, _, TIMER_FLAG_NO_MAPCHANGE);
	g_fStartTime = GetGameTime();
	//CPrintToChatAll("[Debug] RoundStart");
}

public void FixSpawnHandle()
{
	if(!g_bRespawnSprung && g_tSpawn != INVALID_HANDLE)
		KillTimer(g_tSpawn);
	g_tSpawn = INVALID_HANDLE;
}


public Action Event_ChangeTeam(Handle event,const char[] name,bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event,"userid"));
	CreateTimer(0.1, RespawnPlayer, client, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Event_OnPlayerSpawn(Handle event,const char[] name,bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event,"userid"));
	g_fSpawnTime[client] = GetGameTime();
	CreateWeapon(client);
	if(g_bSpawnKillOn)
		CreateTimer(4.0, timer_killplayer, client, TIMER_FLAG_NO_MAPCHANGE);
	//CPrintToChatAll("[Debug] Spawned");
}

public Action timer_killplayer(Handle timer, int client)
{
	if(IsValidClient_k(client) && g_bSpawnKillOn)
		ForcePlayerSuicide(client);
}

public Action Event_PlayerHurt(Handle event,const char[] name,bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event,"userid"));
	if(GetGameTime()-g_fSpawnTime[client]<=MAX_TIME && !g_bSpawnKillOn)
		TookDamage(client);
	else
		g_iDeathCount[client] = 0;
	//CPrintToChatAll("[Debug] Hurt");
}

public Action Event_Death(Handle event,const char[] name,bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event,"userid"));
	if(GetGameTime()-g_fSpawnTime[client]<=MAX_TIME && !g_bSpawnKillOn)
		TookDamage(client);
	else
		g_iDeathCount[client] = 0;
	CreateTimer(0.1, RespawnPlayer, client, TIMER_FLAG_NO_MAPCHANGE);
}

//Set ar time to database OnMapEnd
public void SetArTime()
{
	if(!g_bConnected) return;
	char query[256];
	Format(query, sizeof(query), "UPDATE respawner SET ar_time = %f WHERE map = '%s'", respawntime, CurrentMap);
	SQL_Query(g_hSQL, query);
}

//Get ar time from database and inserts map into database if it's not there already
public void GetArTime()
{
	if(!g_bConnected)
		return;
	char query[128];
	Format(query, sizeof(query), "INSERT IGNORE INTO respawner(map, ar_time) VALUES('%s', %f)", CurrentMap, 9000.0);
	SQL_Query(g_hSQL, query);
	Format(query, sizeof(query), "SELECT ar_time FROM respawner WHERE map = '%s'", CurrentMap);
	SQL_TQuery(g_hSQL, Callback_Artime, query);
}

public Callback_Artime(Handle owner, Handle hndl, char[] errors, any client)
{
	if(hndl == INVALID_HANDLE)
	{
		GetArTime();
		return;
	}
	while(SQL_FetchRow(hndl))
		respawntime = SQL_FetchFloat(hndl, 0);
	FixSpawnHandle();
	g_tSpawn = CreateTimer(respawntime-(GetGameTime()-g_fStartTime), end_spawn, _, TIMER_FLAG_NO_MAPCHANGE);
	checkSettings();
}

//Sets new ar time
public void RemakeArTime(float newTime)
{
	FixSpawnHandle();
	CreateTimer(0.1, end_spawn);
	respawntime = newTime;
	//CPrintToChatAll("[Debug] RemakeArTime");
	checkSettings();
}

public void ConnectSQL()
{
	if(g_hSQL != INVALID_HANDLE)
		CloseHandle(g_hSQL);
	char e_buffer[512];
	g_hSQL = INVALID_HANDLE;
	g_hSQL = SQL_Connect("respawner", true, e_buffer, sizeof(e_buffer));
	//g_hSQL = Timer_SqlGetConnection();
	if(g_hSQL == INVALID_HANDLE)
	{
		CreateTimer(1.0, RetrySQL);
	}else
	{
		//Yay we're connected
		g_bConnected = true;
		ConnectionCounter = 0;
		SQL_Query(g_hSQL, "CREATE TABLE IF NOT EXISTS `respawner` (map varchar(64) NOT NULL, ar_time float NOT NULL, PRIMARY KEY(map));");
		GetArTime();
	}
}

public Action RetrySQL(Handle timer)
{
	if(ConnectionCounter == 15)
		return Plugin_Stop;
	ConnectSQL();
	++ConnectionCounter;
	return Plugin_Stop;
}

public void CreateWeapon(int client)
{
	if(!IsPlayerAlive(client)) return;
	if(GetPlayerWeaponSlot(client, 2) == -1 && GetConVarBool(sm_respawn_knife))
		GivePlayerItem(client,"weapon_knife");
		
	if(GetConVarBool(sm_respawn_pistol) && GetPlayerWeaponSlot(client, 1) == -1)
		GivePlayerItem(client,"weapon_glock");
}

public void TookDamage(int client)
{
	//check if the player is alive or not, and respawn accordingly
	if(!IsValidClient_k(client) || !GetConVarBool(sm_respawn_detect))
		return;
	if(g_iDeathCount[client] > MAX_DEATH)
	{
		//Disable it
		RemakeArTime(GetGameTime()-g_fStartTime-5.0);
	}else
		++g_iDeathCount[client];
	//CPrintToChatAll("[Debug] TookDamage");
	g_fSpawnTime[client] = GetGameTime();
}

//end spawn time
public Action end_spawn(Handle timer)
{
	g_bSpawnKillOn = true;
	CPrintToChatAll("%t", "Respawn Disabled");
	g_bRespawnSprung = true;
}

public Action RespawnPlayer(Handle timer, any data)
{
	//CPrintToChatAll("[Debug] RespawnPlayer %i", data);
	int client = data;
	if(!IsValidClient_k(client) || g_bSpawnKillOn)
		return;
	int team = GetClientTeam(client);
	if((team == CS_TEAM_CT || team == CS_TEAM_T) && !IsPlayerAlive(client))
		CS_RespawnPlayer(client);
}

public checkSettings()
{
	if(!GetConVarBool(sm_respawn_rtv))
		return;
	
	if(respawntime >=GetConVarFloat(sm_respawn_rtv_time))
	{
		ServerCommand("sm_rcon sm_rtv_changetime 0");
	}
	else if(respawntime <= GetConVarFloat(sm_respawn_rtv_time))
	{
		ServerCommand("sm_rcon sm_rtv_changetime 1");
	}
}

//Shit after this straight outta dat piece of shit thingy i call include
stock int howManyPlayersConnected(bool justTeams = true)
{
	int playersAlive = 0;
	if(justTeams)
	{
		for(new i = 1; i<Connected(); i++)
		{
			if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) > 1)
			{
				playersAlive++;
			}
		}
		return playersAlive;
	}else
	{
		for(new i = 1; i<Connected(); i++)
		{
			if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
			{
				playersAlive++;
			}
		}
		return playersAlive;
	}
}

stock int Connected()
{
	for (int i = MaxClients; i >= 1; i--)
	{
		if(IsClientConnected(i) && !IsFakeClient(i))
		{
			return i+1;
		}
	}
	return MaxClients;
}

stock bool IsValidClient_k(int client, bool bAlive = false) // when bAlive is false = technical checks, when it's true = gameplay checks
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}