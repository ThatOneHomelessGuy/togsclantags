/*
	Potential To Do:
	MaxTagLength = 12
	
	Add cmd for temporary tag override: sm_forcetag <target> <tag>
*/

#pragma semicolon 1
#define PLUGIN_VERSION "2.2.6"
#define LoopValidPlayers(%1,%2)\
	for(int %1 = 1;%1 <= MaxClients; ++%1)\
		if(IsValidClient(%1, %2))

#include <sourcemod>
#include <cstrike>
#include <autoexecconfig>	//https://github.com/Impact123/AutoExecConfig or http://www.togcoding.com/showthread.php?p=1862459
#pragma newdecls required

char g_sCfgPath[PLATFORM_MAX_PATH];

ConVar g_hAdminFlag;
char g_sAdminFlag[30];
ConVar g_hIncludeBots;
ConVar g_hEnforceTags;
ConVar g_hUpdateFreq;
ConVar g_hUseMySQL;
ConVar g_hDebug;

char ga_sTag[MAXPLAYERS + 1][50];
char ga_sExtTag[MAXPLAYERS + 1][50];
bool ga_bLoaded[MAXPLAYERS + 1] = {false, ...};

ArrayList g_hValidTags;
ArrayList g_hTags;
ArrayList g_hFlags;
ArrayList g_hIgnored;

Database g_oDatabase;
//bool g_bLateLoad;
char g_sServerIP[64] = "";
int g_iNumSetups = -1;
int g_iDBLoaded = 0;

public Plugin myinfo =
{
	name = "TOG Clan Tags",
	author = "That One Guy",
	description = "Configurable clan tag setups.",
	version = PLUGIN_VERSION,
	url = "http://www.togcoding.com"
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int err_max)
{
	//g_bLateLoad = bLate;
	CreateNative("TOGsClanTags_Reload", Native_ReloadPlugin);
	CreateNative("TOGsClanTags_ReloadPlayer", Native_ReloadPlayer);
	CreateNative("TOGsClanTags_UsingMysql", Native_UsingMysql);
	CreateNative("TOGsClanTags_SetExtTag", Native_SetExtTag);
	
	RegPluginLibrary("togsclantags");
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	AutoExecConfig_SetFile("togsclantags");
	AutoExecConfig_CreateConVar("togsclantags_version", PLUGIN_VERSION, "TOG Clan Tags: Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	g_hAdminFlag = CreateConVar("togsclantags_admflag", "z", "Admin flag(s) used for sm_rechecktags command.", FCVAR_NONE);
	g_hAdminFlag.GetString(g_sAdminFlag, sizeof(g_sAdminFlag));
	g_hAdminFlag.AddChangeHook(OnCVarChange);
	
	g_hIncludeBots = AutoExecConfig_CreateConVar("togsclantags_bots", "0", "Do bots get tags? (1 = yes, 0 = no)", FCVAR_NONE, true, 0.0, true, 1.0);
	
	g_hEnforceTags = AutoExecConfig_CreateConVar("togsclantags_enforcetags", "2", "If no matching setup is found, should their tag be forced to be blank? (0 = allow players setting any clan tags they want, 1 = if no matching setup found, they can only use tags found in the cfg file, 2 = only get tags by having a matching setup in cfg file or database).", FCVAR_NONE, true, 0.0, true, 2.0);
	
	g_hUpdateFreq = AutoExecConfig_CreateConVar("togsclantags_updatefreq", "0", "Frequency to re-load clients from cfg file (0 = only check once). This function is namely used to help interact with other plugins changing admin status late.", FCVAR_NONE, true, 0.0);
	
	g_hUseMySQL = AutoExecConfig_CreateConVar("togsclantags_use_mysql", "0", "Use mysql? (1 = Use MySQL to manage setups, 0 = Use cfg file to manage setups)", FCVAR_NONE, true, 0.0, true, 1.0);

	g_hDebug = AutoExecConfig_CreateConVar("togsclantags_debug", "0", "Enable debug mode? (1 = Yes, produce debug files (note, this can produce large files), 0 = Disable debug mode)", FCVAR_NONE, true, 0.0, true, 1.0);
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
	
	RegConsoleCmd("sm_rechecktags", Cmd_ResetTags, "Recheck tags for all players in the server.");
	
	HookEvent("player_spawn", Event_Recheck);
	HookEvent("player_team", Event_Recheck);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_Pre);
	
	AddCommandListener(Command_Recheck, "jointeam");
	AddCommandListener(Command_Recheck, "joinclass");
	AddCommandListener(Command_Recheck, "spec_mode");
	AddCommandListener(Command_Recheck, "spec_next");
	AddCommandListener(Command_Recheck, "spec_player");
	AddCommandListener(Command_Recheck, "spec_prev");
	
	BuildPath(Path_SM, g_sCfgPath, sizeof(g_sCfgPath), "configs/togsclantags.cfg");
	
	g_hValidTags = new ArrayList(64);
	g_hTags = new ArrayList(150);
	g_hFlags = new ArrayList(150);
	g_hIgnored = new ArrayList();
	//LoadSetups();
}

public void OnCVarChange(ConVar hCVar, const char[] sOldValue, const char[] sNewValue)
{
	if(hCVar == g_hAdminFlag)
	{
		GetConVarString(g_hAdminFlag, g_sAdminFlag, sizeof(g_sAdminFlag));
	}
}

public void OnConfigsExecuted()
{
	GetServerIP();
	if(g_hUseMySQL.BoolValue)
	{
		if(g_oDatabase == null)
		{
			SetDBHandle();
		}
	}
	
	/*LoadSetups();
	
	if(g_bLateLoad)
	{
		LoopValidPlayers_Bots(i)
		{
			OnClientConnected(i);
			OnClientPostAdminCheck(i);
		}
	}*/
}

void GetServerIP()
{
	int a_iArray[4];
	int iLongIP = GetConVarInt(FindConVar("hostip"));
	a_iArray[0] = (iLongIP >> 24) & 0x000000FF;
	a_iArray[1] = (iLongIP >> 16) & 0x000000FF;
	a_iArray[2] = (iLongIP >> 8) & 0x000000FF;
	a_iArray[3] = iLongIP & 0x000000FF;
	Format(g_sServerIP, sizeof(g_sServerIP), "%d.%d.%d.%d:%i", a_iArray[0], a_iArray[1], a_iArray[2], a_iArray[3], GetConVarInt(FindConVar("hostport")));
}

void SetDBHandle()
{
	if(g_iDBLoaded != 1)	//if connection not in progress (allow if no connection or already connected)
	{
		g_iDBLoaded = 1;
		if(g_oDatabase != null)
		{
			delete g_oDatabase;
			g_oDatabase = null;
		}
		PrintToServer("Establishing database connection for togsclantags.");
		Database.Connect(SQLCallback_Connect, "togsclantags");
	}
}

public void SQLCallback_Connect(Database oDB, const char[] sError, any data)
{
	if(oDB == null)
	{
		SetFailState("Error connecting to main database. %s", sError);
	}
	else
	{
		g_oDatabase = oDB;
		char sDriver[64], sQuery[600];
		
		DBDriver oDriver = g_oDatabase.Driver;
		oDriver.GetIdentifier(sDriver, sizeof(sDriver));
		if(StrEqual(sDriver, "sqlite", false))
		{
			SetFailState("This plugin cannot use SQLite due to the need for server operators to create setups. Either use a MySQL database (with CVar setting: \"togsclantags_use_mysql\" \"1\"), or use the config file (with CVar setting: \"togsclantags_use_mysql\" \"0\").");
		}
		
		PrintToServer("Database connection established for togsclantags!");
		
		/*	`id` INT(20) NOT NULL AUTO_INCREMENT,
			`setup_type` VARCHAR(150) NOT NULL DEFAULT 'public',
			`enable_setup` INT(1) NOT NULL DEFAULT 1,
			`exclude_setup` INT(1) NULL DEFAULT 0,
			`ignore_setup` INT(1) NULL DEFAULT 0,
			`tagtext` VARCHAR(150) NULL DEFAULT '',
			`server_ip` VARCHAR(300) NULL DEFAULT '',
			`setup_order` INT(10) NULL DEFAULT 0
			`dont_remove` INT(2) NULL DEFAULT 1
		*/
		Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `togsclantags_setups` (\
											`id` INT(20) NOT NULL AUTO_INCREMENT,\
											`setup_type` VARCHAR(150) NOT NULL DEFAULT 'public',\
											`enable_setup` INT(1) NOT NULL DEFAULT 1,\
											`exclude_setup` INT(1) NULL DEFAULT 0,\
											`ignore_setup` INT(1) NULL DEFAULT 0,\
											`tagtext` VARCHAR(150) NULL DEFAULT '',\
											`server_ip` VARCHAR(300) NULL DEFAULT '',\
											`setup_order` INT(10) NULL DEFAULT 0,\
											`dont_remove` INT(2) NULL DEFAULT 1,\
											PRIMARY KEY (`id`)) DEFAULT CHARSET=latin1 AUTO_INCREMENT=1");
		g_oDatabase.Query(SQLCallback_Void, sQuery, 1);
	}
}

public void SQLCallback_Void(Database oDB, DBResultSet oResultsSet, const char[] sError, any iValue)
{
	if(oDB == null || oResultsSet == null)
	{
		SetFailState("Error (%i): %s", iValue, sError);
	}
	else if(iValue == 1)
	{
		GetSetupsCount();
		LoadSetups();
	}
}

public void OnMapStart()
{
	LoadSetups();
}

void GetSetupsCount()
{
	if(StrEqual(g_sServerIP, "", false))
	{
		GetServerIP();
	}
	
	if(g_hUseMySQL.BoolValue)
	{
		if(g_oDatabase != null)
		{
			char sQuery[150];
			Format(sQuery, sizeof(sQuery), "SELECT COUNT(*) \
											FROM togsclantags_setups \
											WHERE (server_ip LIKE '%%%s%%') OR (server_ip = '') OR (server_ip IS NULL)", g_sServerIP);
			g_oDatabase.Query(SQLCallback_SetupsCnt, sQuery, 1);
		}
	}
}

public void SQLCallback_SetupsCnt(Database oDB, DBResultSet oResultsSet, const char[] sError, any iValue)
{
	if(oDB == null || oResultsSet == null)
	{
		SetFailState("Error (%i): %s", iValue, sError);
	}

	if(oResultsSet.RowCount > 0)
	{
		oResultsSet.FetchRow();
		int iPrevCnt = g_iNumSetups;
		g_iNumSetups = oResultsSet.FetchInt(0);
		if((iPrevCnt != -1) && (iPrevCnt != g_iNumSetups))
		{
			LoadSetups();
		}
	}
}

void LoadSetups()
{
	if(g_iDBLoaded == 2)
	{
		g_iDBLoaded = 0;
	}
	
	g_hValidTags.Clear();
	g_hTags.Clear();
	g_hFlags.Clear();
	g_hIgnored.Clear();

	if(g_hUseMySQL.BoolValue)
	{
		if(g_hDebug.BoolValue)
		{
			Log("togsclantags_debug.log", "Retrieving Setups from database.");
		}
		
		if(g_oDatabase == null)
		{
			SetDBHandle();
			return;
		}
		else
		{
			GetMySQLSetups();
			return;
		}
	}
	else
	{
		if(g_hDebug.BoolValue)
		{
			Log("togsclantags_debug.log", "Retrieving Setups from config file.");
		}
		
		if(!FileExists(g_sCfgPath))
		{
			SetFailState("Configuration file not found: %s", g_sCfgPath);
			return;
		}
		
		KeyValues oKeyValues = new KeyValues("Setups");

		if(!oKeyValues.ImportFromFile(g_sCfgPath))
		{
			delete oKeyValues;
			SetFailState("Improper structure for configuration file: %s", g_sCfgPath);
			return;
		}

		if(oKeyValues.GotoFirstSubKey(true))
		{
			do
			{
				char sBuffer2[150];
				oKeyValues.GetString("tag", sBuffer2, sizeof(sBuffer2), "");
				if(oKeyValues.GetNum("exclude", 0) == 1)
				{
					g_hValidTags.PushString(sBuffer2);
				}
				
				char sSectionName[100];
				
				if(g_hDebug.BoolValue)
				{
					oKeyValues.GetSectionName(sSectionName, sizeof(sSectionName));
					Log("togsclantags_debug.log", "Checking setup '%s' (exclude: %i). Tag: %s", sSectionName, oKeyValues.GetNum("exclude", 0), sBuffer2);
				}
				
				if(oKeyValues.GetNum("enabled", 1))
				{
					g_hTags.PushString(sBuffer2);
					oKeyValues.GetString("flag", sBuffer2, sizeof(sBuffer2), "public");
					if(g_hDebug.BoolValue)
					{
						Log("togsclantags_debug.log", "Setup '%s' is being added with flags: %s. Ignore: %i", sSectionName, sBuffer2, oKeyValues.GetNum("ignore", 0));
					}
					g_hFlags.PushString(sBuffer2);
					g_hIgnored.Push(oKeyValues.GetNum("ignore", 0));
				}
				else
				{
					if(g_hDebug.BoolValue)
					{
						Log("togsclantags_debug.log", "Setup '%s' is disabled.", sSectionName);
					}
				}
			}
			while(oKeyValues.GotoNextKey(false));
		}
		else
		{
			delete oKeyValues;
			SetFailState("Can't find subkey in configuration file %s!", g_sCfgPath);
			return;
		}
		delete oKeyValues;
		g_iDBLoaded = 2;
		LoopValidPlayers(i, true)
		{
			OnClientConnected(i);
			OnClientPostAdminCheck(i);
		}
	}
}

void GetMySQLSetups()
{
	if(g_oDatabase != null)
	{
		char sQuery[1000];
		/*	`id` INT(20) NOT NULL AUTO_INCREMENT,
			`setup_type` VARCHAR(150) NOT NULL DEFAULT 'public',
			`enable_setup` INT(1) NOT NULL DEFAULT 1,
			`exclude_setup` INT(1) NULL DEFAULT 0,
			`ignore_setup` INT(1) NULL DEFAULT 0,
			`tagtext` VARCHAR(150) NULL DEFAULT '',
			`server_ip` VARCHAR(300) NOT NULL DEFAULT ''
		*/
		Format(sQuery, sizeof(sQuery), "SELECT setup_type,ignore_setup,tagtext,exclude_setup,enable_setup \
										FROM togsclantags_setups \
										WHERE (server_ip = '') OR (server_ip LIKE '%%%s%%') OR (server_ip IS NULL) \
										ORDER BY setup_order", g_sServerIP);
		if(g_hDebug.BoolValue)
		{
			Log("togsclantags_debug.log", "Querying database for setups with query: %s", sQuery);
		}
		g_oDatabase.Query(SQLCallback_GetSetups, sQuery, 1);
	}
	else
	{
		CreateTimer(3.0, TimerCB_RetryConn, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action TimerCB_RetryConn(Handle hTimer)
{
	if(g_oDatabase != null)
	{
		char sQuery[1000];
		Format(sQuery, sizeof(sQuery), "SELECT setup_type,ignore_setup,tagtext,exclude_setup,enable_setup \
										FROM togsclantags_setups \
										WHERE (server_ip = '') OR (server_ip LIKE '%%%s%%') OR (server_ip IS NULL) \
										ORDER BY setup_order", g_sServerIP);
		if(g_hDebug.BoolValue)
		{
			Log("togsclantags_debug.log", "Querying database for setups with query: %s", sQuery);
		}
		g_oDatabase.Query(SQLCallback_GetSetups, sQuery, 1);
	}
	else
	{
		CreateTimer(5.0, TimerCB_RetryConn, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void SQLCallback_GetSetups(Database oDB, DBResultSet oResultsSet, const char[] sError, any iValue)
{
	if(oDB == null || oResultsSet == null)
	{
		SetFailState("Error (%i): %s", iValue, sError);
	}
	
	ClearExistingSetups();
	int iRowCnt = oResultsSet.RowCount;
	if(g_hDebug.BoolValue)
	{
		Log("togsclantags_debug.log", "%i setup rows returned from database.", iRowCnt);
	}
	if(iRowCnt > 0)
	{
		while(oResultsSet.FetchRow())
		{
			/*	`id` INT(20) NOT NULL AUTO_INCREMENT,
				`setup_type` VARCHAR(150) NOT NULL DEFAULT 'public',
				`enable_setup` INT(1) NOT NULL DEFAULT 1,
				`exclude_setup` INT(1) NULL DEFAULT 0,
				`ignore_setup` INT(1) NULL DEFAULT 0,
				`tagtext` VARCHAR(150) NULL DEFAULT '',
				`server_ip` VARCHAR(300) NOT NULL DEFAULT '',
				setup_order INT(10) NULL DEFAULT 0
				`dont_remove` INT(2) NULL DEFAULT 1
				
					0			1		   2	       3           4
				setup_type,ignore_setup,tagtext,exclude_setup,enable_setup
			*/

			if(g_hDebug.BoolValue)
			{
				Log("togsclantags_debug.log", "Starting new setup row.");
			}
			
			char sBuffer[150];
			int iEnabled = oResultsSet.FetchInt(4);
			if(iEnabled)
			{
				oResultsSet.FetchString(0, sBuffer, sizeof(sBuffer));
				g_hFlags.PushString(sBuffer);
				g_hIgnored.Push(oResultsSet.FetchInt(1));
				if(g_hDebug.BoolValue)
				{
					Log("togsclantags_debug.log", "Adding setup flag: %s. Ignored: %i", sBuffer, oResultsSet.FetchInt(1));
				}
				oResultsSet.FetchString(2, sBuffer, sizeof(sBuffer));
				g_hTags.PushString(sBuffer);
				if(g_hDebug.BoolValue)
				{
					Log("togsclantags_debug.log", "Adding setup tag: %s", sBuffer);
				}
			}
			else
			{
				if(g_hDebug.BoolValue)
				{
					Log("togsclantags_debug.log", "setup row is disabled.");
				}
			}

			if(oResultsSet.FetchInt(3) == 1)
			{
				g_hValidTags.PushString(sBuffer);
			}
		}
	}
	
	g_iDBLoaded = 2;
	
	LoopValidPlayers(i, true)
	{
		OnClientConnected(i);
		OnClientPostAdminCheck(i);
	}
}

void ClearExistingSetups()
{
	/*for(int i = 0; i < GetArraySize(g_hTags); i++)
	{
		DoStuff();
	}*/
	g_hTags.Clear();
}

public int Native_ReloadPlugin(Handle hPlugin, int iNumParams)
{
	LoadSetups();
	ReRetrieveAllTags();
}

public int Native_ReloadPlayer(Handle hPlugin, int iNumParams)
{
	int client = GetNativeCell(1);
	
	if(IsValidClient(client))
	{
		ReRetrieveTags(client);
		return true;
	}
	return false;
}

public int Native_SetExtTag(Handle hPlugin, int iNumParams)
{
	int client = GetNativeCell(1);
	if(IsValidClient(client))
	{
		GetNativeString(2, ga_sExtTag[client], sizeof(ga_sExtTag[]));
		ga_bLoaded[client] = false;
		GetTags(client);
		return true;
	}
	return false;
}

public int Native_UsingMysql(Handle hPlugin, int iNumParams)
{
	if(g_hUseMySQL.BoolValue)
	{
		return 1;
	}
	return 0;
}

public Action Cmd_ResetTags(int client, int iArgs)
{
	if(IsValidClient(client))
	{
		if(!HasFlags(client, g_sAdminFlag))
		{
			ReplyToCommand(client, "\x04You do not have access to this command!");
			return Plugin_Handled;
		}
	}
	
	LoadSetups();
	ReRetrieveAllTags();
	
	return Plugin_Handled;
}

void ReRetrieveAllTags()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		ReRetrieveTags(i);
	}
}

void ReRetrieveTags(int client)
{
	if(IsValidClient(client, g_hIncludeBots.BoolValue))
	{
		ga_bLoaded[client] = false;
		GetTags(client);
	}
}

public void OnClientConnected(int client)
{
	ga_sTag[client] = "";
	ga_sExtTag[client] = "";
	ga_bLoaded[client] = false;
}

public void OnClientDisconnect(int client)
{
	ga_sTag[client] = "";
	ga_sExtTag[client] = "";
	ga_bLoaded[client] = false;
}

public void OnClientPostAdminCheck(int client)
{
	if(g_iDBLoaded == 2)
	{
		GetTags(client);
		if(g_hUpdateFreq.FloatValue)
		{
			CreateTimer(g_hUpdateFreq.FloatValue, TimerCB_ReCheckCfg, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	else
	{
		CreateTimer(5.0, TimerCB_RetryLoadClient, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action TimerCB_RetryLoadClient(Handle hTimer, any iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if(!IsValidClient(client, g_hIncludeBots.BoolValue))
	{
		return Plugin_Stop;
	}
	if(g_iDBLoaded == 2)
	{
		GetTags(client);
		if(g_hUpdateFreq.FloatValue)
		{
			CreateTimer(g_hUpdateFreq.FloatValue, TimerCB_ReCheckCfg, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	else
	{
		CreateTimer(5.0, TimerCB_RetryLoadClient, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Continue;
}

public Action TimerCB_ReCheckCfg(Handle hTimer, any iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if(!IsValidClient(client, g_hIncludeBots.BoolValue))
	{
		return Plugin_Stop;
	}
	ga_bLoaded[client] = false;
	GetTags(client);
	return Plugin_Continue;
}

public void OnClientSettingsChanged(int client)	//hooked in case they change their clan tag
{
	if(ga_bLoaded[client]) //dont want them to try loading before steam id loads - could also lead to multiple timers
	{
		CheckTags(client);
	}
}

public Action Event_RoundEnd(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
	GetSetupsCount();
}

public Action Event_Recheck(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	if(IsValidClient(client, g_hIncludeBots.BoolValue))
	{
		if(!ga_bLoaded[client])
		{
			GetTags(client);
		}
		else
		{
			CheckTags(client);
		}
	}
	return Plugin_Continue;
}

public Action Command_Recheck(int client, char[] sCommand, int iArgs) 
{
	if(IsValidClient(client, g_hIncludeBots.BoolValue))
	{
		if(!ga_bLoaded[client])
		{
			GetTags(client);
		}
		else
		{
			CheckTags(client);
		}
	}
	return Plugin_Continue;
}

void GetTags(int client)
{
	if(!IsValidClient(client, true))
	{
		return;
	}
	
	if(g_iDBLoaded != 2)
	{
		CreateTimer(5.0, TimerCB_RetryLoadClient, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	
	if(g_hDebug.BoolValue)
	{
		Log("togsclantags_debug.log", "%L is starting checks for tags", client);
	}
	
	ga_sTag[client] = "";
	
	if(StrEqual(ga_sExtTag[client], "", false))
	{
		char sBuffer[150], a_sSteamIDs[4][65];
		if(!IsValidClient(client))
		{
			Format(a_sSteamIDs[0], sizeof(a_sSteamIDs[]), "BOT");
			Format(a_sSteamIDs[1], sizeof(a_sSteamIDs[]), "BOT");
			Format(a_sSteamIDs[2], sizeof(a_sSteamIDs[]), "BOT");
			Format(a_sSteamIDs[3], sizeof(a_sSteamIDs[]), "BOT");
		}
		else
		{
			if(IsClientAuthorized(client))
			{
				GetClientAuthId(client, AuthId_Steam2, a_sSteamIDs[0], sizeof(a_sSteamIDs[]));
				ReplaceString(a_sSteamIDs[0], sizeof(a_sSteamIDs[]), "STEAM_1", "STEAM_0", false);
				GetClientAuthId(client, AuthId_Steam2, a_sSteamIDs[1], sizeof(a_sSteamIDs[]));
				ReplaceString(a_sSteamIDs[1], sizeof(a_sSteamIDs[]), "STEAM_0", "STEAM_1", false);
				GetClientAuthId(client, AuthId_Steam3, a_sSteamIDs[2], sizeof(a_sSteamIDs[]));
				GetClientAuthId(client, AuthId_SteamID64, a_sSteamIDs[3], sizeof(a_sSteamIDs[]));
			}
			else
			{
				CreateTimer(5.0, TimerCB_RetryLoadClient, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
			}
		}
		
		if(g_hDebug.BoolValue)
		{
			Log("togsclantags_debug.log", "Auth IDs for %L: %s ; %s ; %s ; %s", client, a_sSteamIDs[0], a_sSteamIDs[1], a_sSteamIDs[2], a_sSteamIDs[3]);
		}

		int iSetupCnt = g_hFlags.Length;
		for(int i = 0; i < iSetupCnt; i++)
		{
			g_hFlags.GetString(i, sBuffer, sizeof(sBuffer));
			if(g_hDebug.BoolValue)
			{
				Log("togsclantags_debug.log", "Checking %L against flag (%i/%i): %s", client, i+1, iSetupCnt, sBuffer);
			}
			if(StrEqual("BOT", sBuffer, false)) //check if BOT config
			{
				if(g_hDebug.BoolValue)
				{
					Log("togsclantags_debug.log", "Checking %L against flag (%i/%i): %s. Setup is in 'BOT' category.", client, i+1, iSetupCnt, sBuffer);
				}
				if(StrEqual("BOT", a_sSteamIDs[0], false)) //check if player is BOT
				{
					g_hTags.GetString(i, ga_sTag[client], sizeof(ga_sTag[]));
					break;
				}
			}
			else if(HasNumbers(sBuffer) || (StrContains(sBuffer, ":", false) != -1))	//if steam ID
			{
				if(StrEqual(sBuffer, a_sSteamIDs[0], false) || StrEqual(sBuffer, a_sSteamIDs[1], false) || StrEqual(sBuffer, a_sSteamIDs[2], false) || StrEqual(sBuffer, a_sSteamIDs[3], false))
				{
					if(g_hDebug.BoolValue)
					{
						Log("togsclantags_debug.log", "Checking %L against flag (%i/%i): %s. Matching setup found in Steam IDs!", client, i+1, iSetupCnt, sBuffer);
					}
					
					if(!g_hIgnored.Get(i))
					{
						g_hTags.GetString(i, ga_sTag[client], sizeof(ga_sTag[]));
					}
					break;
				}
				else if(g_hDebug.BoolValue)
				{
					Log("togsclantags_debug.log", "Checking %L against flag (%i/%i): %s. Setup is in Steam ID category, but does not match.", client, i+1, iSetupCnt, sBuffer);
				}
			}
			else if(HasFlags(client, sBuffer)) //check if player has defined flags
			{
				if(g_hDebug.BoolValue)
				{
					Log("togsclantags_debug.log", "Checking %L against flag (%i/%i): %s. Matching setup found in flags category!", client, i+1, iSetupCnt, sBuffer);
				}
				if(!g_hIgnored.Get(i))
				{
					g_hTags.GetString(i, ga_sTag[client], sizeof(ga_sTag[]));
				}
				break;
			}
			else
			{
				if(g_hDebug.BoolValue)
				{
					Log("togsclantags_debug.log", "No matches found for %L against flag (%i/%i): %s.", client, i+1, iSetupCnt, sBuffer);
				}
			}
		}
	}
	else
	{
		strcopy(ga_sTag[client], sizeof(ga_sTag[]), ga_sExtTag[client]);
		if(g_hDebug.BoolValue)
		{
			Log("togsclantags_debug.log", "Tag for %L set by external plugin: %s.", client, ga_sTag[client]);
		}
	}
	ga_bLoaded[client] = true;
	CheckTags(client);
}

stock bool HasNumbers(char[] sString)
{
	for(int i = 0; i < strlen(sString); i++)
	{
		if(IsCharNumeric(sString[i]))
		{
			return true;
		}
	}
	return false;
}

stock bool IsNumeric(char[] sString)
{
	for(int i = 0; i < strlen(sString); i++)
	{
		if(!IsCharNumeric(sString[i]))
		{
			return false;
		}
	}
	return true;
}

void CheckTags(int client)
{
	if(!ga_bLoaded[client])
	{
		GetTags(client);
		return;
	}
	
	if(!StrEqual(ga_sTag[client], "", true))
	{
		CS_SetClientClanTag(client, ga_sTag[client]);
	}
	else if(g_hEnforceTags.IntValue == 1)
	{
		char sTag[50];
		CS_GetClientClanTag(client, sTag, sizeof(sTag));
		if(g_hValidTags.FindString(sTag) == -1)
		{
			CS_SetClientClanTag(client, "");
		}
	}
	else if(g_hEnforceTags.IntValue == 2)
	{
		CS_SetClientClanTag(client, "");
	}
}

bool HasFlags(int client, char[] sFlags)
{
	if(StrEqual(sFlags, "public", false) || StrEqual(sFlags, "", false))
	{
		return true;
	}
	else if(StrEqual(sFlags, "none", false))	//useful for some plugins
	{
		return false;
	}
	else if(!client)	//if rcon
	{
		return true;
	}
	else if(CheckCommandAccess(client, "sm_not_a_command", ADMFLAG_ROOT, true))
	{
		return true;
	}
	
	AdminId id = GetUserAdmin(client);
	if(id == INVALID_ADMIN_ID)
	{
		return false;
	}
	int flags, clientflags;
	clientflags = GetUserFlagBits(client);
	
	if(StrContains(sFlags, ";", false) != -1) //check if multiple strings
	{
		int i = 0, iStrCount = 0;
		while(sFlags[i] != '\0')
		{
			if(sFlags[i++] == ';')
			{
				iStrCount++;
			}
		}
		iStrCount++; //add one more for stuff after last comma
		
		char[][] a_sTempArray = new char[iStrCount][30];
		ExplodeString(sFlags, ";", a_sTempArray, iStrCount, 30);
		bool bMatching = true;
		
		for(i = 0; i < iStrCount; i++)
		{
			bMatching = true;
			flags = ReadFlagString(a_sTempArray[i]);
			for(int j = 0; j <= 20; j++)
			{
				if(bMatching)	//if still matching, continue loop
				{
					if(flags & (1<<j))
					{
						if(!(clientflags & (1<<j)))
						{
							bMatching = false;
						}
					}
				}
			}
			if(bMatching)
			{
				return true;
			}
		}
		return false;
	}
	else
	{
		flags = ReadFlagString(sFlags);
		for(int i = 0; i <= 20; i++)
		{
			if(flags & (1<<i))
			{
				if(!(clientflags & (1<<i)))
				{
					return false;
				}
			}
		}
		return true;
	}
}

bool IsValidClient(int client, bool bAllowBots = false, bool bAllowDead = true)
{
	if(!(1 <= client <= MaxClients) || !IsClientInGame(client) || (IsFakeClient(client) && !bAllowBots) || IsClientSourceTV(client) || IsClientReplay(client) || (!IsPlayerAlive(client) && !bAllowDead))
	{
		return false;
	}
	return true;
}

public void OnRebuildAdminCache(AdminCachePart part)
{
	ReRetrieveAllTags();
}

stock void Log(char[] sPath, const char[] sMsg, any ...)	//TOG logging function - path is relative to logs folder.
{
	char sLogFilePath[PLATFORM_MAX_PATH], sFormattedMsg[256];
	BuildPath(Path_SM, sLogFilePath, sizeof(sLogFilePath), "logs/%s", sPath);
	VFormat(sFormattedMsg, sizeof(sFormattedMsg), sMsg, 3);
	LogToFileEx(sLogFilePath, "%s", sFormattedMsg);
}
/*
CHANGELOG:
	1.0:
		* Plugin coded for private. Released to Allied Modders after suggestion from requester.
	1.1:
		* Fixed memory leak due to missing a CloseHandle on one of the returns.
	1.2:
		* Added OnRebuildAdminCache event.
		* Added cvar for rechecking client against cfg file on a configurable interval. This was added so that the plugin can interact with other plugins that dont fwd admin cache changes properly.
	1.3:
		* Minor edits to make sure clients load tag when spawning in late, etc.
	1.4:
		* Edited togsclantags_enforcetags cvar: was missing 'c' in name, and added an option to allow tags if they exist in the cfg.
	1.5:
		* Added "ignore" kv.
	2.0:
		* Converted to 1.8 syntax.
		* Added option to use mysql DB and recoded plugin to support either MySQL or kv file.
		* Added "enabled" key value.
		* Edited documentation to include "exclude" key-value.
		* Added cache of all setups.
		* Added round-end re-check of DB setups count for checking if a new setup has been added.
	2.0.1:
		* Added check for blank IP before running queries just to be safe.
	2.1.0:
		* Added native to reload plugin.
		* Added native to check if using mysql.
		* Added plugin library registration.
		* Added check for NULL server_ip field in mysql (previously, it checked for blanks (''), so this was added to be extra safe, not due to any problems).
		* Added `dont_remove` column to support other plugins that are adding into the database. Default = 1. Plugins adding in setups can add it with a 0 to be able to override their own and know it is safe.
		* Added code so that setups using steam IDs can use AuthId_Steam2 (both universe 0 and 1), AuthId_Steam3, or AuthId_SteamID64.
		* Changed cvars to use methodmaps.
	2.1.1:
		* Added check in flags section to filter out new steam ID types.
		* Fixed index error in new steam ID array.
		* Added check for if client is authorized when getting the 4 steam IDs, else loop client.
	2.1.2:
		* Removed if(!g_hUseMySQL.BoolValue){} in Event_Recheck. I dont recall why that check was there...
		* Added hooks for jointeam and joinclass commands. Previously, only the player_team event was being hooked.
	2.1.3:
		* Accidently returned Plugin_Handled instead of Plugin_Continue on the hooks for jointeam and joinclass. Fixed that.
	2.1.4:
		* Added spec cmd hooks.
	2.2.0:
		* Fixed an improper indexing of a_sSteamIDs in GetTags.
		* Added debug cvar and full debug code.
		* Converted several things to use 1.8 syntax classes (methodmaps) where they weren't before.
		* Modidied the GetTags function a bit.
		* Added IsValidClient check inside GetTags, though i believe it was filtered in the calling functions, but perhaps not each instance.
	2.2.1:
		* Added handling for when no setups apply to server.
	2.2.2:
		* Added SetFailState for if the user is attempting to use SQLite.
	2.2.3:
		* Added check inside GetSetupsCount for if MySQL is being used before checking setups count. It doesnt make any difference because it wouldnt have passed the null check for the database handle, but still good practice.
	2.2.4:
		* Made reload cmd rcon compatible.
		* Added native to reload a single player.
	2.2.5:
		* Added back native TOGsClanTags_SetExtTag.
	2.2.6:
		* Fixed bug introduced with 2.2.5 regarding reverse logic for if an external tag is set.
		
*/