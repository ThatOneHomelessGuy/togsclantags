/*
Potential To Do:
	* Make cvar for if players with required flag are restricted by default or not. (i.e., they have access, but have to be unrestricted first).
	* If color setting no longer exists (via config), set player setup to "" if that is their cookie setting.
	* Add to color config file the ability to specify color access via flags or to disable/enable certain colors.
	* Add natives to plugin to allow other plugins to specify client, and section name of a group setup to apply that setup to a player. Make a "flags" keyvalue that specifies that the setup isnt public or flag/ID based, but for external use (i.e. N/A).
	* Re-add Admin see-all.
		Add client indexes that are admin and are not part of msg recipients to datapack w/ msg (already formatted with names, etc)
		and execute msg on next game frame (or 0.1s timer?).
	* Make secondary tag usable through groups config with another kv.
	* Natives for external plugins to set a clients tag/colors.

Requests:
	* Force bracket color cfg in groups txt file?
	
To Do:
	Fix !blockchat <target>
		Only using a 1-D array, should be 2D...need to fix
	
===========================================
=========== CHANGELOG AT BOTTOM ===========
===========================================
*/

#pragma semicolon 1
#pragma dynamic 131072 		//increase stack space to from 4 kB to 131072 cells (or 512KB, a cell is 4 bytes).

#define PLUGIN_VERSION "4.9.3" //CHANGELOG AT BOTTOM
#define MAXTAGSIZE 22
#define INS_GREEN "\x01"
#define CSGO_RED "\x07"
#define CSS_RED "\x07FF0000"

#define LoopValidPlayers(%1)	for(int %1=1;%1<=MaxClients;++%1)	if(IsValidClient(%1))

#include <sourcemod>
#include <autoexecconfig>
#include <sdktools>
#include <adminmenu>
#include <clientprefs>
#include <basecomm>
#include <togschattags>
#include <regex>
#include <geoip>
#undef REQUIRE_PLUGIN
#include <extendedcomm_togedit>
#if defined(VALIDATION_TIME) || defined(VALIDATION_IP) || defined(VALIDATION_HOSTNAME) || defined(VALIDATION_DATABASE)
	#include <togservervalidation>
#endif

#pragma newdecls required

ConVar g_cAccessFlag = null;
char g_sAccessFlag[120];
ConVar g_cAdminFlag = null;
char g_sAdminFlag[120];
ConVar g_cSpamIgnoreFlag = null;
char g_sSpamIgnoreFlag[120];
ConVar g_cAdminFlag_Force = null;
char g_sAdminFlag_Force[120];
ConVar g_cAdminUnloadFlag = null;
char g_sAdminUnloadFlag[120];
ConVar g_cBracketColors = null;
char g_sBracketColors[32];
ConVar g_cDatabaseName = null;
char g_sDatabaseName[60];
ConVar g_cDBTableName = null;
char g_sDBTableName[60];
//console and team colors
ConVar g_cConsoleTag = null;
char g_sConsoleTag[50];
ConVar g_cConsoleTagColor = null;
char g_sConsoleTagColor[32];
ConVar g_cConsoleName = null;
char g_sConsoleName[50];
ConVar g_cConsoleNameColor = null;
char g_sConsoleNameColor[32];
ConVar g_cConsoleChatColor = null;
char g_sConsoleChatColor[32];
ConVar g_cCTChatColor = null;
char g_sCTChatColor[32];
ConVar g_cTChatColor = null;
char g_sTChatColor[32];
ConVar g_cCTNameColor = null;
char g_sCTNameColor[32];
ConVar g_cTNameColor = null;
char g_sTNameColor[32];
ConVar g_cSpamDetectDuration = null;
ConVar g_cGrpsAfterRemove = null;
ConVar g_cSpamGagDetectDuration = null;
ConVar g_cSpamMsgCnt = null;
ConVar g_cSpamMsgGagCnt = null;
ConVar g_cConvertTriggerCases = null;
ConVar g_cEnableTags = null;
ConVar g_cEnableTagColors = null;
ConVar g_cEnableNameColors = null;
ConVar g_cEnableChatColors = null;
ConVar g_cHideChatTriggers = null;
ConVar g_cLog = null;
ConVar g_cEnableSpamBlock = null;
ConVar g_cEnableSpamGag = null;
ConVar g_cAllowBlockChat = null;
ConVar g_cSpamGagPenalty = null;
ConVar g_cExternalPos = null;
ConVar g_cForceBrackets = null;

//player settings
int gaa_iAdminOvrd[MAXPLAYERS + 1][4];
int ga_iTagVisible[MAXPLAYERS + 1] = {0, ...};	//0 = hidden, 1 = cfg file, 2 = custom setup, 3 = admin forced setup
int ga_iIsRestricted[MAXPLAYERS + 1] = {0, ...};
int ga_iIsLoaded[MAXPLAYERS + 1] = {0, ...};
int ga_iEntOverride[MAXPLAYERS + 1] = {0, ...};
char gaa_sSteamID[MAXPLAYERS + 1][4][65];
char ga_sName[MAXPLAYERS + 1][MAX_NAME_LENGTH];
char ga_sEscapedName[MAXPLAYERS + 1][MAX_NAME_LENGTH*2 + 1];
char ga_sTagColor[MAXPLAYERS + 1][32];
char ga_sNameColor[MAXPLAYERS + 1][32];
char ga_sChatColor[MAXPLAYERS + 1][32];
char ga_sTag[MAXPLAYERS + 1][MAXTAGSIZE];
char gaa_sCleanSetupText[MAXPLAYERS + 1][4][32];
char ga_sExtTag[MAXPLAYERS + 1][30];
char ga_sExtTagColor[MAXPLAYERS + 1][32];
int ga_iTagColorAccess[MAXPLAYERS + 1] = {-1, ...};
int ga_iNameColorAccess[MAXPLAYERS + 1] = {-1, ...};
int ga_iChatColorAccess[MAXPLAYERS + 1] = {-1, ...};
int ga_iSetTagAccess[MAXPLAYERS + 1] = {-1, ...};
int ga_iGroupMatch[MAXPLAYERS + 1] = {0, ...};
bool ga_bChatBlocked[MAXPLAYERS + 1] = {false, ...};

//chat spam blocker
int ga_iChatMsgCnt[MAXPLAYERS + 1] = {0, ...};
int ga_iChatSpamCnt[MAXPLAYERS + 1] = {0, ...};

ArrayList g_aTranslationNames;
ArrayList g_aColorName;
ArrayList g_aColorCode;
ArrayList g_aBlockedTags;
ArrayList g_aMessages;

Handle g_hLoadFwd = INVALID_HANDLE;
Handle g_hClientLoadFwd = INVALID_HANDLE;
Handle g_hClientReloadFwd = INVALID_HANDLE;
TopMenu g_oTopMenu;
Regex g_oRegexHex;
Database g_oDatabase;

char g_sPath[PLATFORM_MAX_PATH];		//cfg file data
char g_sGroupPath[PLATFORM_MAX_PATH];		//cfg file data
char g_sChatLogPath[PLATFORM_MAX_PATH];		//chat logger
char g_sTag[10];
char g_sMapName[64] = "";
char g_sServerIP[64] = "";

bool g_bLateLoad;
bool g_bCSGO = false;
bool g_bIns = false;
bool g_bExtendedComm_togedit = false;
bool g_bMySQL = false;

public Plugin myinfo =
{
	name = "TOGs Chat Tags",
	author = "That One Guy",
	description = "Gives players with designated flag the ability to set their own custom tags, and much much more.",
	version = PLUGIN_VERSION,
	url = "http://www.togcoding.com"
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int err_max)
{
	g_bLateLoad = bLate;
	
	CreateNative("tct_SetExtTag", Native_SetExtTag);
	CreateNative("tct_SetSetTagAccess", Native_SetSetTagAccess);
	CreateNative("tct_SetTagColorAccess", Native_SetTagColorAccess);
	CreateNative("tct_SetNameColorAccess", Native_SetNameColorAccess);
	CreateNative("tct_SetChatColorAccess", Native_SetChatColorAccess);
	CreateNative("tct_SetCompleteAccess", Native_SetCompleteAccess);
	
	RegPluginLibrary("togschattags");
	
	return APLRes_Success;
}

public void OnPluginStart()
{
#if defined(VALIDATION_TIME) || defined(VALIDATION_IP) || defined(VALIDATION_HOSTNAME) || defined(VALIDATION_DATABASE)
	ValidateServer();
#endif
	
	char sGameFolder[32], sTranslation[PLATFORM_MAX_PATH], sDescription[64];
	GetGameDescription(sDescription, sizeof(sDescription), true);
	GetGameFolderName(sGameFolder, sizeof(sGameFolder));
	if((StrContains(sGameFolder, "csgo", false) != -1) || (StrContains(sDescription, "Counter-Strike: Global Offensive", false) != -1))
	{
		g_bCSGO = true;
	}
	else if((StrContains(sGameFolder, "insurgency", false) != -1) || StrEqual(sGameFolder, "ins", false) || (StrContains(sDescription, "Insurgency", false) != -1))
	{
		g_bIns = true;
	}
	
	g_aTranslationNames = new ArrayList(64);
	Format(sTranslation, sizeof(sTranslation), "scp.%s.phrases.txt", sGameFolder);
	LoadTranslations(sTranslation);
	BuildPath(Path_SM, sTranslation, sizeof(sTranslation), "translations/%s", sTranslation);
	if(!FileExists(sTranslation))
	{
		SetFailState("Translation file missing! %s", sTranslation);
	}
	GetTranslationNames(sTranslation);
	
	g_hLoadFwd = CreateGlobalForward("TCTLoaded", ET_Ignore);
	g_hClientLoadFwd = CreateGlobalForward("TCTClientLoaded", ET_Event, Param_Cell);
	g_hClientReloadFwd = CreateGlobalForward("TCTClientReloaded", ET_Event, Param_Cell);
	
	AutoExecConfig_SetFile("togschattags");
	AutoExecConfig_CreateConVar("tct_version", PLUGIN_VERSION, "TOGs Chat Tags: Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	LoadTranslations("core.phrases");
	LoadTranslations("common.phrases");
	
	g_cAccessFlag = AutoExecConfig_CreateConVar("tct_accessflag", "a", "If \"\", everyone can change their tags, \"none\" restricted access (other than external plugin use), otherwise, only players with the listed flag(s) can access plugin features.", _);
	g_cAccessFlag.GetString(g_sAccessFlag, sizeof(g_sAccessFlag));
	g_cAccessFlag.AddChangeHook(OnCVarChange);
	
	g_cAdminFlag = AutoExecConfig_CreateConVar("tct_adminflag", "b", "Only players with this flag can restrict/remove tags of players.", _);
	g_cAdminFlag.GetString(g_sAdminFlag, sizeof(g_sAdminFlag));
	g_cAdminFlag.AddChangeHook(OnCVarChange);

	g_cSpamIgnoreFlag = AutoExecConfig_CreateConVar("tct_spamignoreflag", "b", "Players with this flag will be ignored by the spam blocker.", _);
	g_cSpamIgnoreFlag.GetString(g_sSpamIgnoreFlag, sizeof(g_sSpamIgnoreFlag));
	g_cSpamIgnoreFlag.AddChangeHook(OnCVarChange);
	
	g_cAdminFlag_Force = AutoExecConfig_CreateConVar("tct_adminflag_force", "g", "Only players with this flag can force tags/colors for other players.", _);
	g_cAdminFlag_Force.GetString(g_sAdminFlag_Force, sizeof(g_sAdminFlag_Force));
	g_cAdminFlag_Force.AddChangeHook(OnCVarChange);
	
	g_cAdminUnloadFlag = AutoExecConfig_CreateConVar("tct_unloadflag", "h", "Only players with this flag can unload the entire plugin until map change.", _);
	g_cAdminUnloadFlag.GetString(g_sAdminUnloadFlag, sizeof(g_sAdminUnloadFlag));
	g_cAdminUnloadFlag.AddChangeHook(OnCVarChange);
	
	g_cConsoleTag = AutoExecConfig_CreateConVar("tct_console_tag", "", "Tag to use for console.", FCVAR_NONE);
	g_cConsoleTag.GetString(g_sConsoleTag, sizeof(g_sConsoleTag));
	g_cConsoleTag.AddChangeHook(OnCVarChange);
	
	g_cConsoleName = AutoExecConfig_CreateConVar("tct_console_name", "CONSOLE:", "Name to use for console.", FCVAR_NONE);
	g_cConsoleName.GetString(g_sConsoleName, sizeof(g_sConsoleName));
	g_cConsoleName.AddChangeHook(OnCVarChange);
	
	g_cDatabaseName = AutoExecConfig_CreateConVar("tct_dbname", "togschattags", "Name of the database setup for the plugin.");
	g_cDatabaseName.GetString(g_sDatabaseName, sizeof(g_sDatabaseName));
	g_cDatabaseName.AddChangeHook(OnCVarChange);
	
	g_cDBTableName = AutoExecConfig_CreateConVar("tct_dbtblname", "togschattags", "Name of the database table for the plugin.");
	g_cDBTableName.GetString(g_sDBTableName, sizeof(g_sDBTableName));
	g_cDBTableName.AddChangeHook(OnCVarChange);
	
	g_cConvertTriggerCases = AutoExecConfig_CreateConVar("tct_triggercase", "1", "Convert chat triggers to lowercase if theyre uppercase. (1 = enabled, 0 = disabled)", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cLog = AutoExecConfig_CreateConVar("tct_log", "0", "Enable chat logger. (1 = enabled, 0 = disabled)", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cExternalPos = AutoExecConfig_CreateConVar("tct_exttagspos", "0", "0 = external tags applied on left of normal tags, 1 = on right, 2 = Only one tag can show, ext tag is preferenced, 3 = Only one tag can show, personal is preferenced.", FCVAR_NONE, true, 0.0, true, 3.0);
	g_cForceBrackets = AutoExecConfig_CreateConVar("tct_forcebrackets", "0", "0 = disabled, 1 = wrap personal tags in {}, 2 = wrap personal tags in []. Note: Tags from the cfg file are not forced to have brackets.", FCVAR_NONE, true, 0.0, true, 2.0);
	//spam blocker
	g_cEnableSpamBlock = AutoExecConfig_CreateConVar("tct_spam_enable", "1", "Enable blocking chat spam (0 = disabled).", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cSpamDetectDuration = AutoExecConfig_CreateConVar("tct_spam_duration_short", "3", "Number of seconds used for the initial spam detection. If messages sent within this time frame exceed the count set by tct_spam_count_short, it blocks them and marks them as spam.", FCVAR_NONE, true, 1.0);
	g_cSpamMsgCnt = AutoExecConfig_CreateConVar("tct_spam_count_short", "3", "Number of messages within the time interval set by tct_spam_duration_short for it to be considered spam.", FCVAR_NONE, true, 2.0);
	g_cEnableSpamGag = AutoExecConfig_CreateConVar("tct_spam_enablegag", "1", "Enable muting chat spammers after spam detections exceed tct_spam_count_long within time set by tct_spam_duration_long? (1 = enabled, 0 = disabled).", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cSpamGagDetectDuration = AutoExecConfig_CreateConVar("tct_spam_duration_long", "90", "Number of spam detections within the time interval set by tct_spam_duration_long before auto-gag is issued.", FCVAR_NONE, true, 1.0);
	g_cSpamMsgGagCnt = AutoExecConfig_CreateConVar("tct_spam_count_long", "3", "Number of spam detections within the time interval set by tct_spam_duration_long before auto-gag is issued.", FCVAR_NONE, true, 2.0);
	g_cSpamGagPenalty = AutoExecConfig_CreateConVar("tct_spam_gaglength", "5", "Number of minutes to gag client if auto-detection gag is being used. This only applies if using extendedcomm (or extendedcomm_togedit). Else, mutes will be temp, per SM default.");
	g_cAllowBlockChat = AutoExecConfig_CreateConVar("tct_allowblockchat", "0", "Allow players to use !blockchat command (1 = enabled, 0 = disabled).", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cGrpsAfterRemove = AutoExecConfig_CreateConVar("tct_grps_after_remove", "1", "Apply group file configs to player after an admin removes their tags? (1 = enabled, 0 = disabled)", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cEnableTags = AutoExecConfig_CreateConVar("tct_enabletags", "1", "Enable being able to set a tags if you have access (1 = enabled, 0 = disabled).", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cEnableTagColors = AutoExecConfig_CreateConVar("tct_enabletagcolors", "1", "Enable being able to set tag colors (1 = enabled, 0 = disabled).", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cEnableNameColors = AutoExecConfig_CreateConVar("tct_enablenamecolors", "1", "Enable being able to set name colors (1 = enabled, 0 = disabled).", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cEnableChatColors = AutoExecConfig_CreateConVar("tct_enablechatcolors", "1", "Enable being able to set chat colors (1 = enabled, 0 = disabled).", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cHideChatTriggers = AutoExecConfig_CreateConVar("tct_hidechattriggers", "0", "Hides registered chat commands and messages starting with ! or / (1 = enabled, 0 = disabled).", FCVAR_NONE, true, 0.0, true, 1.0);
	
	if(g_bCSGO)	//CS:GO
	{
		Format(g_sTag, sizeof(g_sTag), " \x01[TCT] ");	//includes space
		g_cCTChatColor = AutoExecConfig_CreateConVar("tct_chatcolor_ct", "1", "Color to use as default chat color for CTs, if nothing else applies (check color cfg file for #s).", FCVAR_NONE);
		g_cTChatColor = AutoExecConfig_CreateConVar("tct_chatcolor_t", "1", "Color to use as default chat color for Ts, if nothing else applies (check color cfg file for #s).", FCVAR_NONE);
		g_cCTNameColor = AutoExecConfig_CreateConVar("tct_namecolor_ct", "1", "Color to use as default name color for CTs, if nothing else applies (check color cfg file for #s).", FCVAR_NONE);
		g_cTNameColor = AutoExecConfig_CreateConVar("tct_namecolor_t", "1", "Color to use as default name color for Ts, if nothing else applies (check color cfg file for #s).", FCVAR_NONE);
		g_cConsoleTagColor = AutoExecConfig_CreateConVar("tct_console_tagcolor", "7", "Color to use for console tag color (check color cfg file for #s).", FCVAR_NONE);
		g_cConsoleNameColor = AutoExecConfig_CreateConVar("tct_console_namecolor", "7", "Color to use for console name color (check color cfg file for #s).", FCVAR_NONE);
		g_cConsoleChatColor = AutoExecConfig_CreateConVar("tc_console_chatcolor", "7", "Color to use for console chat color (check color cfg file for #s).", FCVAR_NONE);
		g_cBracketColors = AutoExecConfig_CreateConVar("tct_bracketcolor", "", "Color to use for brackets if tct_forcebrackets is enabled (check color cfg file for #s - Blank = match tag color).", FCVAR_NONE);
	}
	else if(g_bIns)	//Insurgency
	{
		Format(g_sTag, sizeof(g_sTag), " \x01[TCT] ");	//includes space
		g_cCTChatColor = AutoExecConfig_CreateConVar("tct_chatcolor_ct", "1", "Color to use as default chat color for CTs, if nothing else applies (check color cfg file for #s).", FCVAR_NONE);
		g_cTChatColor = AutoExecConfig_CreateConVar("tct_chatcolor_t", "1", "Color to use as default chat color for Ts, if nothing else applies (check color cfg file for #s).", FCVAR_NONE);
		g_cCTNameColor = AutoExecConfig_CreateConVar("tct_namecolor_ct", "2", "Color to use as default name color for CTs, if nothing else applies (check color cfg file for #s).", FCVAR_NONE);
		g_cTNameColor = AutoExecConfig_CreateConVar("tct_namecolor_t", "2", "Color to use as default name color for Ts, if nothing else applies (check color cfg file for #s).", FCVAR_NONE);
		g_cConsoleTagColor = AutoExecConfig_CreateConVar("tct_console_tagcolor", "1", "Color to use for console tag color (check color cfg file for #s).", FCVAR_NONE);
		g_cConsoleNameColor = AutoExecConfig_CreateConVar("tct_console_namecolor", "3", "Color to use for console name color (check color cfg file for #s).", FCVAR_NONE);
		g_cConsoleChatColor = AutoExecConfig_CreateConVar("tc_console_chatcolor", "6", "Color to use for console chat color (check color cfg file for #s).", FCVAR_NONE);
		g_cBracketColors = AutoExecConfig_CreateConVar("tct_bracketcolor", "", "Color to use for brackets if tct_forcebrackets is enabled (check color cfg file for #s - Blank = match tag color).", FCVAR_NONE);
	}
	else
	{
		Format(g_sTag, sizeof(g_sTag), "\x01[TCT] ");	//no space added
		g_cCTChatColor = AutoExecConfig_CreateConVar("tct_chatcolor_ct", "", "Color to use as default chat color for CTs, if nothing else applies (check color cfg file for #s).", FCVAR_NONE);
		g_cTChatColor = AutoExecConfig_CreateConVar("tct_chatcolor_t", "", "Color to use as default chat color for Ts, if nothing else applies (check color cfg file for #s).", FCVAR_NONE);
		g_cCTNameColor = AutoExecConfig_CreateConVar("tct_namecolor_ct", "99CCFF", "Color to use as default name color for CTs, if nothing else applies (check color cfg file for #s).", FCVAR_NONE);
		g_cTNameColor = AutoExecConfig_CreateConVar("tct_namecolor_t", "FF4040", "Color to use as default name color for Ts, if nothing else applies (check color cfg file for #s).", FCVAR_NONE);
		g_cConsoleTagColor = AutoExecConfig_CreateConVar("tct_console_tagcolor", "FFFFFF", "Color to use for console tag color (check color cfg file for #s).", FCVAR_NONE);
		g_cConsoleNameColor = AutoExecConfig_CreateConVar("tct_console_namecolor", "FF0000", "Color to use for console name color (check color cfg file for #s).", FCVAR_NONE);
		g_cConsoleChatColor = AutoExecConfig_CreateConVar("tct_console_chatcolor", "FF0000", "Color to use for console chat color (check color cfg file for #s).", FCVAR_NONE);
		g_cBracketColors = AutoExecConfig_CreateConVar("tct_bracketcolor", "", "Color to use for brackets if tct_forcebrackets is enabled (check color cfg file for #s - Blank = match tag color).", FCVAR_NONE);
	}

	g_cCTChatColor.GetString(g_sCTChatColor, sizeof(g_sCTChatColor));
	g_cCTChatColor.AddChangeHook(OnCVarChange);

	g_cTChatColor.GetString(g_sTChatColor, sizeof(g_sTChatColor));
	g_cTChatColor.AddChangeHook(OnCVarChange);

	g_cCTNameColor.GetString(g_sCTNameColor, sizeof(g_sCTNameColor));
	g_cCTNameColor.AddChangeHook(OnCVarChange);

	g_cTNameColor.GetString(g_sTNameColor, sizeof(g_sTNameColor));
	g_cTNameColor.AddChangeHook(OnCVarChange);

	g_cBracketColors.GetString(g_sBracketColors, sizeof(g_sBracketColors));
	g_cBracketColors.AddChangeHook(OnCVarChange);

	g_cConsoleTagColor.GetString(g_sConsoleTagColor, sizeof(g_sConsoleTagColor));
	g_cConsoleTagColor.AddChangeHook(OnCVarChange);

	g_cConsoleNameColor.GetString(g_sConsoleNameColor, sizeof(g_sConsoleNameColor));
	g_cConsoleNameColor.AddChangeHook(OnCVarChange);

	g_cConsoleChatColor.GetString(g_sConsoleChatColor, sizeof(g_sConsoleChatColor));
	g_cConsoleChatColor.AddChangeHook(OnCVarChange);
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
	
	SetDBHandle();
	
	//player commands
	RegConsoleCmd("sm_tags", Command_Tag, "Opens TOGs Chat Tags Menu.");
	RegConsoleCmd("sm_settag", Command_SetText, "Change tag text.");
	RegConsoleCmd("sm_checktag", Command_CheckTag, "Check tag settings of another player.");
	RegConsoleCmd("sm_blockchat", Command_BlockChat, "Block player from seeing chat from others (if command is allowed).");
	//non-CS:GO commands
	RegConsoleCmd("sm_tagcolor", Command_TagColor, "Change tag color to a specified hexadecimal value.");
	RegConsoleCmd("sm_namecolor", Command_NameColor, "Change name color to a specified hexadecimal value.");
	RegConsoleCmd("sm_chatcolor", Command_ChatColor, "Change chat color to a specified hexadecimal value.");
	
	//admin commands - RegConsoleCmd used to allow setting access via cvar "tct_adminflag"
	RegConsoleCmd("sm_reloadtagcolors", Cmd_Reload, "Reloads color cfg file for tags.");
	RegConsoleCmd("sm_unrestricttag", Cmd_Unrestrict, "Unrestrict player from setting their chat tags.");
	RegConsoleCmd("sm_restricttag", Cmd_Restrict, "Restrict player from setting their chat tags.");
	RegConsoleCmd("sm_removetag", Cmd_RemoveTag, "Removes a players tag setup.");
	RegConsoleCmd("sm_unloadtags", Cmd_Unload, "Unloads the entire plugin for the current map.");
	//admin commands - RegConsoleCmd used to allow setting access via cvar "tct_adminflag_force"
	RegConsoleCmd("sm_forcetag", Cmd_ForceTag, "Force tag setup on a player.");
	RegConsoleCmd("sm_removeoverride", Cmd_RemoveOverride, "Remove admin overrides from a player.");
	
	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_SayTeam, "say_team");
	if(g_bIns)
	{
		AddCommandListener(Command_Say, "say2");
	}
	
	//hook admin chat commands for chat logging
	AddCommandListener(Command_AdminChat, "sm_say");
	AddCommandListener(Command_AdminOnlyChat, "sm_chat");
	AddCommandListener(Command_CSay, "sm_csay");
	AddCommandListener(Command_TSay, "sm_tsay");
	AddCommandListener(Command_MSay, "sm_msay");
	AddCommandListener(Command_HSay, "sm_hsay");
	AddCommandListener(Command_PSay, "sm_psay");

	HookEvent("player_changename", Event_NameChange);
	UserMsg umSayText2 = GetUserMessageId("SayText2");
	if(umSayText2 != INVALID_MESSAGE_ID)
	{
		HookUserMessage(umSayText2, OnSayText2, true);
	}
	else
	{
		UserMsg umSayText = GetUserMessageId("SayText");
		if(umSayText != INVALID_MESSAGE_ID)
		{
			HookUserMessage(umSayText, OnSayText2, true);
		}
		else
		{
			LogError("Unable to hook either SayText2 or SayText. This game is not supported!");
			SetFailState("Unable to hook either SayText2 or SayText. This game is not supported!");	
		}
	}
	
	//client prefs and cookies	
	SetCookieMenuItem(Menu_ClientPrefs, 0, "TOGs Chat Tags");
	
	//admin menu - Account for late loading
	TopMenu hTopMenu;
	if(LibraryExists("adminmenu") && ((hTopMenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		OnAdminMenuReady(hTopMenu);
	}
	
	if(LibraryExists("extendedcomm_togedit"))
	{
		g_bExtendedComm_togedit = true;
	}
	else
	{
		g_bExtendedComm_togedit = false;
	}

	//color file
	g_aColorName = new ArrayList(32);
	g_aColorCode = new ArrayList(32);
	if(g_bCSGO)
	{
		BuildPath(Path_SM, g_sPath, sizeof(g_sPath), "configs/tct_colors_csgo.cfg");
	}
	else if(g_bIns)
	{
		BuildPath(Path_SM, g_sPath, sizeof(g_sPath), "configs/tct_colors_ins.cfg");
	}
	else
	{
		BuildPath(Path_SM, g_sPath, sizeof(g_sPath), "configs/togschattags_colors.cfg");
		g_oRegexHex = new Regex("([A-Fa-f0-9]{6})");
	}
	
	BuildPath(Path_SM, g_sGroupPath, sizeof(g_sGroupPath), "configs/tct_groups.cfg");
	
	ConvertColor(g_sConsoleTagColor, sizeof(g_sConsoleTagColor));
	ConvertColor(g_sConsoleNameColor, sizeof(g_sConsoleNameColor));
	ConvertColor(g_sConsoleChatColor, sizeof(g_sConsoleChatColor));
	ConvertColor(g_sCTChatColor, sizeof(g_sCTChatColor));
	ConvertColor(g_sTChatColor, sizeof(g_sTChatColor));
	ConvertColor(g_sCTNameColor, sizeof(g_sCTNameColor));
	ConvertColor(g_sTNameColor, sizeof(g_sTNameColor));
	ConvertColor(g_sBracketColors, sizeof(g_sBracketColors));
	
	//overwrite cookies if they are cached
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && AreClientCookiesCached(i) && IsClientAuthorized(i))
		{
			SetDefaults(i);
			LoadClientData(i);
		}
	}
	
	GetServerIP();
}

public void OnCVarChange(ConVar hCVar, const char[] sOldValue, const char[] sNewValue)
{
	if(hCVar == g_cDatabaseName)
	{
		g_cDatabaseName.GetString(g_sDatabaseName, sizeof(g_sDatabaseName));
	}
	else if(hCVar == g_cDBTableName)
	{
		g_cDBTableName.GetString(g_sDBTableName, sizeof(g_sDBTableName));
	}
	else if(hCVar == g_cAccessFlag)
	{
		g_cAccessFlag.GetString(g_sAccessFlag, sizeof(g_sAccessFlag));
	}
	else if(hCVar == g_cAdminFlag)
	{
		g_cAdminFlag.GetString(g_sAdminFlag, sizeof(g_sAdminFlag));
	}
	else if(hCVar == g_cSpamIgnoreFlag)
	{
		g_cSpamIgnoreFlag.GetString(g_sSpamIgnoreFlag, sizeof(g_sSpamIgnoreFlag));
	}
	else if(hCVar == g_cAdminFlag_Force)
	{
		g_cAdminFlag_Force.GetString(g_sAdminFlag_Force, sizeof(g_sAdminFlag_Force));
	}
	else if(hCVar == g_cAdminUnloadFlag)
	{
		g_cAdminUnloadFlag.GetString(g_sAdminUnloadFlag, sizeof(g_sAdminUnloadFlag));
	}
	else if(hCVar == g_cConsoleTag)
	{
		g_cConsoleTag.GetString(g_sConsoleTag, sizeof(g_sConsoleTag));
	}
	else if(hCVar == g_cConsoleTagColor)
	{
		g_cConsoleTagColor.GetString(g_sConsoleTagColor, sizeof(g_sConsoleTagColor));
		ConvertColor(g_sConsoleTagColor, sizeof(g_sConsoleTagColor));
	}
	else if(hCVar == g_cConsoleName)
	{
		g_cConsoleName.GetString(g_sConsoleName, sizeof(g_sConsoleName));
	}
	else if(hCVar == g_cConsoleNameColor)
	{
		g_cConsoleNameColor.GetString(g_sConsoleNameColor, sizeof(g_sConsoleNameColor));
		ConvertColor(g_sConsoleNameColor, sizeof(g_sConsoleNameColor));
	}
	else if(hCVar == g_cConsoleChatColor)
	{
		g_cConsoleChatColor.GetString(g_sConsoleChatColor, sizeof(g_sConsoleChatColor));
		ConvertColor(g_sConsoleChatColor, sizeof(g_sConsoleChatColor));
	}
	else if(hCVar == g_cCTChatColor)
	{
		g_cCTChatColor.GetString(g_sCTChatColor, sizeof(g_sCTChatColor));
		ConvertColor(g_sCTChatColor, sizeof(g_sCTChatColor));
	}
	else if(hCVar == g_cTChatColor)
	{
		g_cTChatColor.GetString(g_sTChatColor, sizeof(g_sTChatColor));
		ConvertColor(g_sTChatColor, sizeof(g_sTChatColor));
	}
	else if(hCVar == g_cCTNameColor)
	{
		g_cCTNameColor.GetString(g_sCTNameColor, sizeof(g_sCTNameColor));
		ConvertColor(g_sCTNameColor, sizeof(g_sCTNameColor));
	}
	else if(hCVar == g_cTNameColor)
	{
		g_cTNameColor.GetString(g_sTNameColor, sizeof(g_sTNameColor));
		ConvertColor(g_sTNameColor, sizeof(g_sTNameColor));
	}
	else if(hCVar == g_cBracketColors)
	{
		g_cBracketColors.GetString(g_sBracketColors, sizeof(g_sBracketColors));
		ConvertColor(g_sBracketColors, sizeof(g_sBracketColors));
	}
}

void SetDBHandle()
{
	if(g_oDatabase != null)
	{
		delete g_oDatabase;
		g_oDatabase = null;
	}
	Database.Connect(SQLCallback_Connect, g_sDatabaseName);
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
		char sDriver[64], sQuery[1000], sQueryBuffer[1000];
		DBDriver oDriver = g_oDatabase.Driver;
		oDriver.GetIdentifier(sDriver, sizeof(sDriver));
		delete oDriver;
		
		Format(sQueryBuffer, sizeof(sQueryBuffer), "	`steamid` VARCHAR(65) NOT NULL, \
													`tagtext` VARCHAR(32) NOT NULL, \
													`visible` INT(2) NOT NULL, \
													`restricted` INT(2) NOT NULL, \
													`tagcolor` VARCHAR(10) NOT NULL, \
													`namecolor` VARCHAR(10) NOT NULL, \
													`chatcolor` VARCHAR(10) NOT NULL, \
													`ovrd_ttext` INT(2) NOT NULL, \
													`ovrd_tcolor` INT(2) NOT NULL, \
													`ovrd_ncolor` INT(2) NOT NULL, \
													`ovrd_ccolor` INT(2) NOT NULL");
		FormatQueryByDriver(sDriver, g_sDBTableName, sQuery, sizeof(sQuery), sQueryBuffer);
		g_oDatabase.Query(SQLCallback_Void, sQuery, 1);

		if(!StrEqual(sDriver, "sqlite"))
		{
			Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `tct_chatlogs` 	(	`id` INT(20) NOT NULL AUTO_INCREMENT, \
																							`steamid` VARCHAR(65) NULL, \
																							`mapname` VARCHAR(32) NULL, \
																							`server` VARCHAR(32) NULL, \
																							`playername` VARCHAR(65) NULL, \
																							`playerip` VARCHAR(32) NULL, \
																							`ip_country` VARCHAR(45) NULL, \
																							`chatmsg` VARCHAR(300) NULL, \
																							`chatgrp` VARCHAR(20) NULL, \
																							`logdate` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP(), \
																							PRIMARY KEY (`id`)\
																						) DEFAULT CHARSET=latin1 AUTO_INCREMENT=1");
			g_oDatabase.Query(SQLCallback_Void, sQuery, 5);
		}
		else	//if sqlite, use flat files
		{
			char sBuffer[PLATFORM_MAX_PATH];
			BuildPath(Path_SM, sBuffer, sizeof(sBuffer), "logs/chatlogger/");
			if(!DirExists(sBuffer))
			{
				CreateDirectory(sBuffer, 777);
			}
			FormatTime(sBuffer, sizeof(sBuffer), "%m%d%y");
			Format(sBuffer, sizeof(sBuffer), "logs/chatlogger/chatlogs_%s.log", sBuffer);
			BuildPath(Path_SM, g_sChatLogPath, sizeof(g_sChatLogPath), sBuffer);
			CreateTimer(60.0, Timer_UpdatePath, _, TIMER_REPEAT);
		}
	}
	GetCurrentMap(g_sMapName, sizeof(g_sMapName));	//redundancy to make sure this has a value
}

void FormatQueryByDriver(char[] sDriver, char[] sTblName, char[] sRtnQuery, int iSize, char[] sQuery)
{
	if(StrEqual(sDriver, "sqlite", false))
	{
		Format(sRtnQuery, iSize, "CREATE TABLE IF NOT EXISTS `%s` (`id` int(20) PRIMARY KEY, %s, PRIMARY KEY (`id`)) DEFAULT CHARSET=latin1 AUTO_INCREMENT=1", sTblName, sQuery);
	}
	else
	{
		Format(sRtnQuery, iSize, "CREATE TABLE IF NOT EXISTS `%s` (`id` int(20) NOT NULL AUTO_INCREMENT,  %s)", sTblName, sQuery);
	}
}

public void SQLCallback_Void(Database oDB, DBResultSet oHndl, const char[] sError, any iValue)
{
	if(oHndl == null)
	{
		SetFailState("Error (%i): %s", iValue, sError);
	}
}

public void OnMapStart()
{
	ConvertColor(g_sConsoleTagColor, sizeof(g_sConsoleTagColor));
	ConvertColor(g_sConsoleNameColor, sizeof(g_sConsoleNameColor));
	ConvertColor(g_sConsoleChatColor, sizeof(g_sConsoleChatColor));
	ConvertColor(g_sCTChatColor, sizeof(g_sCTChatColor));
	ConvertColor(g_sTChatColor, sizeof(g_sTChatColor));
	ConvertColor(g_sCTNameColor, sizeof(g_sCTNameColor));
	ConvertColor(g_sTNameColor, sizeof(g_sTNameColor));
	ConvertColor(g_sBracketColors, sizeof(g_sBracketColors));
	LoadColorCfg();
	LoadCustomConfigs();
	
	GetCurrentMap(g_sMapName, sizeof(g_sMapName));	//redundancy to make sure this has a value
	
	if(g_cLog.BoolValue && (g_oDatabase != null))
	{
		if(!g_bMySQL)	//map is already noted in MySQL DB, so this logging is not necessary.
		{
			LogToFileEx(g_sChatLogPath, "           >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> New map started: %s <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<", g_sMapName);
		}
	}
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

public Action Timer_UpdatePath(Handle hTimer)
{
	char sBuffer[256];
	FormatTime(sBuffer, sizeof(sBuffer), "%m%d%y");
	Format(sBuffer, sizeof(sBuffer), "logs/chatlogger/chatlogs_%s.log", sBuffer);
	BuildPath(Path_SM, g_sChatLogPath, sizeof(g_sChatLogPath), sBuffer);
}

public void OnConfigsExecuted()
{
	LoadColorCfg();
	LoadCustomConfigs();
	
	if(g_bLateLoad)
	{
		Reload();
		/*if(g_cLog.BoolValue && !g_bMySQL)
		{
			CreateTimer(60.0, Timer_UpdatePath, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		}*/
	}
	
	GetServerIP();
}

public void LoadColorCfg()
{
	if(!FileExists(g_sPath))
	{
		SetFailState("Configuration file %s not found!", g_sPath);
		return;
	}

	KeyValues oKeyValues = new KeyValues("TOGs Tag Colors");

	if(!oKeyValues.ImportFromFile(g_sPath))
	{
		SetFailState("Improper structure for configuration file %s!", g_sPath);
		return;
	}

	if(!oKeyValues.GotoFirstSubKey(true))
	{
		SetFailState("Can't find configuration file %s!", g_sPath);
		return;
	}

	g_aColorName.Clear();
	g_aColorCode.Clear();

	char sName[32], sCode[32];
	do
	{
		oKeyValues.GetString("name", sName, sizeof(sName));
		oKeyValues.GetString("color", sCode, sizeof(sCode));
		ReplaceString(sCode, sizeof(sCode), "#", "", false);
		
		if(!g_bCSGO && !g_bIns)
		{
			if(!IsValidHex(sCode))
			{
				LogError("Invalid hexadecimal value for color %s: %s.", sName, sCode);
				continue;
			}
		}

		g_aColorName.PushString(sName);
		g_aColorCode.PushString(sCode);
	}
	while(oKeyValues.GotoNextKey(false));
	delete oKeyValues;
}

public void LoadCustomConfigs()
{
	g_aBlockedTags = new ArrayList(64);
	g_aMessages = new ArrayList();
	char sBuffer[PLATFORM_MAX_PATH], sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, PLATFORM_MAX_PATH, "configs/tct_blocked.cfg");
	File oFile = OpenFile(sFile, "r");
	if(oFile != null)
	{
		while(oFile.ReadLine(sBuffer, sizeof(sBuffer)))
		{
			TrimString(sBuffer);		//remove spaces and tabs at both ends of string
			if((StrContains(sBuffer, "//") == -1) && (!StrEqual(sBuffer, "")))		//filter out comments and blank lines
			{
				g_aBlockedTags.PushString(sBuffer);
			}
		}
	}
	else
	{
		LogError("File does not exist: \"%s\"", sFile);
	}
	
	delete oFile;
}

public int Native_SetExtTag(Handle hPlugin, int iNumParams)
{
	int client = GetNativeCell(1);
	if(IsValidClient(client))
	{
		GetNativeString(2, ga_sExtTag[client], sizeof(ga_sExtTag[]));
		GetNativeString(3, ga_sExtTagColor[client], sizeof(ga_sExtTagColor[]));
		FormatColors(client);
		return true;
	}
	return false;
}

public int Native_SetSetTagAccess(Handle hPlugin, int iNumParams)
{
	int client = GetNativeCell(1);
	
	if(IsValidClient(client))
	{
		ga_iSetTagAccess[client] = GetNativeCell(2);
		return true;
	}
	
	return false;
}

public int Native_SetTagColorAccess(Handle hPlugin, int iNumParams)
{
	int client = GetNativeCell(1);
	
	if(IsValidClient(client))
	{
		ga_iTagColorAccess[client] = GetNativeCell(2);
		return true;
	}
	
	return false;
}

public int Native_SetNameColorAccess(Handle hPlugin, int iNumParams)
{
	int client = GetNativeCell(1);
	
	if(IsValidClient(client))
	{
		ga_iNameColorAccess[client] = GetNativeCell(2);
		return true;
	}
	
	return false;
}

public int Native_SetChatColorAccess(Handle hPlugin, int iNumParams)
{
	int client = GetNativeCell(1);
	
	if(IsValidClient(client))
	{
		ga_iChatColorAccess[client] = GetNativeCell(2);
		return true;
	}
	
	return false;
}

public int Native_SetCompleteAccess(Handle hPlugin, int iNumParams)
{
	int client = GetNativeCell(1);
	
	if(IsValidClient(client))
	{
		int iAccess = GetNativeCell(2);
		ga_iTagColorAccess[client] = iAccess;
		ga_iNameColorAccess[client] = iAccess;
		ga_iChatColorAccess[client] = iAccess;
		ga_iSetTagAccess[client] = iAccess;
		return true;
	}
	
	return false;
}

//////////////////////////////////////////////////////////////////////////////
///////////////////////////// Client Connections /////////////////////////////
//////////////////////////////////////////////////////////////////////////////

void SetDefaults(int client)
{
	gaa_sSteamID[client][0] = "";
	gaa_sSteamID[client][1] = "";
	gaa_sSteamID[client][2] = "";
	gaa_sSteamID[client][3] = "";
	ga_sName[client] = "";
	ga_sEscapedName[client] = "";
	ga_bChatBlocked[client] = false;
	ga_iTagVisible[client] = 0;
	ga_iIsRestricted[client] = 0;	
	ga_iIsLoaded[client] = 0;
	ga_iEntOverride[client] = 0;
	gaa_iAdminOvrd[client][0] = 0;
	gaa_iAdminOvrd[client][1] = 0;
	gaa_iAdminOvrd[client][2] = 0;
	gaa_iAdminOvrd[client][3] = 0;
	gaa_sCleanSetupText[client][0] = "";
	gaa_sCleanSetupText[client][1] = "";
	gaa_sCleanSetupText[client][2] = "";
	gaa_sCleanSetupText[client][3] = "";
	ga_iChatMsgCnt[client] = 0;
	ga_iChatSpamCnt[client] = 0;

	ga_sTagColor[client] = "";
	ga_sNameColor[client] = "";	
	ga_sChatColor[client] = "";		
	ga_sTag[client] = "";
	ga_sExtTag[client] = "";
	ga_sExtTagColor[client] = "";
	ga_iTagColorAccess[client] = -1;
	ga_iNameColorAccess[client] = -1;
	ga_iChatColorAccess[client] = -1;
	ga_iSetTagAccess[client] = -1;
}

public void OnClientConnected(int client)	//get names as soon as they connect
{
	SetDefaults(client);
}

public void OnClientDisconnect(int client)
{
	SetDefaults(client);
}

public void OnClientPostAdminCheck(int client)
{
	if(IsFakeClient(client))
	{
		Format(gaa_sSteamID[client][0], sizeof(gaa_sSteamID[][]), "BOT");
		Format(gaa_sSteamID[client][1], sizeof(gaa_sSteamID[][]), "BOT");
		Format(gaa_sSteamID[client][2], sizeof(gaa_sSteamID[][]), "BOT");
		Format(gaa_sSteamID[client][3], sizeof(gaa_sSteamID[][]), "BOT");
		return;
	}
	
	GetClientAuthId(client, AuthId_Steam2, gaa_sSteamID[client][0], sizeof(gaa_sSteamID[][]));
	ReplaceString(gaa_sSteamID[client][0], sizeof(gaa_sSteamID[][]), "STEAM_1", "STEAM_0", false);
	GetClientAuthId(client, AuthId_Steam2, gaa_sSteamID[client][1], sizeof(gaa_sSteamID[][]));
	ReplaceString(gaa_sSteamID[client][1], sizeof(gaa_sSteamID[][]), "STEAM_0", "STEAM_1", false);	
	GetClientAuthId(client, AuthId_Steam3, gaa_sSteamID[client][2], sizeof(gaa_sSteamID[][]));
	GetClientAuthId(client, AuthId_SteamID64, gaa_sSteamID[client][3], sizeof(gaa_sSteamID[][]));
	
	if(StrContains(gaa_sSteamID[client][0], "STEAM_", true) == -1) //invalid - retry again
	{
		CreateTimer(10.0, RefreshSteamID, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		LoadClientData(client);
	}
}

public Action RefreshSteamID(Handle hTimer, any iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if(!IsValidClient(client))
	{
		return;
	}

	GetClientAuthId(client, AuthId_Steam2, gaa_sSteamID[client][0], sizeof(gaa_sSteamID[][]));
	ReplaceString(gaa_sSteamID[client][0], sizeof(gaa_sSteamID[][]), "STEAM_1", "STEAM_0", false);
	GetClientAuthId(client, AuthId_Steam2, gaa_sSteamID[client][1], sizeof(gaa_sSteamID[][]));
	ReplaceString(gaa_sSteamID[client][1], sizeof(gaa_sSteamID[][]), "STEAM_0", "STEAM_1", false);	
	GetClientAuthId(client, AuthId_Steam3, gaa_sSteamID[client][2], sizeof(gaa_sSteamID[][]));
	GetClientAuthId(client, AuthId_SteamID64, gaa_sSteamID[client][3], sizeof(gaa_sSteamID[][]));
	
	if(StrContains(gaa_sSteamID[client][0], "STEAM_", true) == -1) //still invalid - retry again
	{
		CreateTimer(10.0, RefreshSteamID, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		LoadClientData(client);
	}
}

public Action RefreshSteamID_SendData(Handle hTimer, any iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if(!IsValidClient(client))
	{
		return;
	}

	GetClientAuthId(client, AuthId_Steam2, gaa_sSteamID[client][0], sizeof(gaa_sSteamID[][]));
	ReplaceString(gaa_sSteamID[client][0], sizeof(gaa_sSteamID[][]), "STEAM_1", "STEAM_0", false);
	GetClientAuthId(client, AuthId_Steam2, gaa_sSteamID[client][1], sizeof(gaa_sSteamID[][]));
	ReplaceString(gaa_sSteamID[client][1], sizeof(gaa_sSteamID[][]), "STEAM_0", "STEAM_1", false);	
	GetClientAuthId(client, AuthId_Steam3, gaa_sSteamID[client][2], sizeof(gaa_sSteamID[][]));
	GetClientAuthId(client, AuthId_SteamID64, gaa_sSteamID[client][3], sizeof(gaa_sSteamID[][]));
	
	if(StrContains(gaa_sSteamID[client][0], "STEAM_", true) == -1) //still invalid - retry again
	{
		CreateTimer(10.0, RefreshSteamID_SendData, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		SendClientSetupToDB(client);
	}
}

public Action TimerCB_RetrySendData(Handle hTimer, any iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if(!IsValidClient(client))
	{
		return;
	}

	if(g_oDatabase != null) //still invalid - retry again
	{
		CreateTimer(5.0, TimerCB_RetrySendData, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		SendClientSetupToDB(client);
	}
}

public Action RepeatCheck(Handle hTimer, any iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if(IsValidClient(client))
	{
		LoadClientData(client);
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

//////////////////////////////////////////////////////////////////
///////////////////////////// Events /////////////////////////////
//////////////////////////////////////////////////////////////////

public Action Command_Say(int client, const char[] sCommand, int iArcC)
{
	char sText[300], sLogMsg[256];
	GetCmdArgString(sText, sizeof(sText));
	StripQuotes(sText);
	int iNamePadding;
	
	if(!IsValidClient(client))
	{
		PrintToChatAll(" %s%s%s%s %s%s", g_sConsoleTagColor, g_sConsoleTag, g_sConsoleNameColor, g_sConsoleName, g_sConsoleChatColor, sText);
		PrintToServer("%s%s %s", g_sConsoleTag, g_sConsoleName, sText);
		if(g_cLog.BoolValue && (g_oDatabase != null))
		{
			if(!g_bMySQL)
			{
				Format(sLogMsg, sizeof(sLogMsg), "%s%s", g_sConsoleTag, g_sConsoleName);
				iNamePadding = 68 - strlen(sLogMsg);
				char[] sPad = new char[iNamePadding];	//char sPad[iNamePadding];
				Format(sPad, iNamePadding, "                                                                    ");
				Format(sLogMsg, sizeof(sLogMsg), "%s%s", sPad, sLogMsg);
				Format(sLogMsg, sizeof(sLogMsg), "%s  %s", sLogMsg, sText);
				LogToFileEx(g_sChatLogPath, sLogMsg);
			}
			else
			{
				SendChatToDB(client, sText, sizeof(sText), "ALL");
			}
		}
		return Plugin_Handled;
	}
	else
	{
		if(PreCheckMessage(client, sText) == 0)
		{
			return Plugin_Handled;
		}
		
		if(g_cLog.BoolValue && (g_oDatabase != null))
		{
			if(!g_bMySQL)
			{
				int iTeam = GetClientTeam(client);
				char sTeam[12];
				if(iTeam == 2)
				{
					Format(sTeam, sizeof(sTeam), "   TERR   ");
				}
				else if(iTeam == 3)
				{
					Format(sTeam, sizeof(sTeam), "    CT    ");
				}
				else
				{
					Format(sTeam, sizeof(sTeam), "   SPEC   ");
				}
				iNamePadding = 33 - strlen(ga_sEscapedName[client]);
				char[] sPad2 = new char[iNamePadding];	//char sPad2[iNamePadding];
				Format(sPad2, iNamePadding, "                                ");
				Format(sLogMsg, sizeof(sLogMsg), "%s%s", sPad2, ga_sEscapedName[client]);
				Format(sLogMsg, sizeof(sLogMsg), "[%20s][%s]%s:  %s", gaa_sSteamID[client][0], sTeam, sLogMsg, sText);
				LogToFileEx(g_sChatLogPath, sLogMsg);
			}
			else
			{
				SendChatToDB(client, sText, sizeof(sText), "ALL");
			}
			
			if(g_cHideChatTriggers.BoolValue)
			{
				if(IsChatTrigger())
				{
					return Plugin_Handled;
				}
				else if(StrContains(sText, "!", false) == 0)
				{
					return Plugin_Handled;
				}
				else if(StrContains(sText, "/", false) == 0)
				{
					return Plugin_Handled;
				}
			}

		}
	}
		
	return Plugin_Continue;
}

public Action Command_SayTeam(int client, const char[] sCommand, int iArcC)
{
	char sText[300], sLogMsg[256];
	GetCmdArgString(sText, sizeof(sText));
	StripQuotes(sText);
	int iNamePadding;
	
	if(!IsValidClient(client))
	{
		PrintToChatAll(" %s%s%s%s %s%s", g_sConsoleTagColor, g_sConsoleTag, g_sConsoleNameColor, g_sConsoleName, g_sConsoleChatColor, sText);
		PrintToServer("%s%s %s", g_sConsoleTag, g_sConsoleName, sText);
		if(g_cLog.BoolValue && (g_oDatabase != null))
		{
			if(!g_bMySQL)
			{
				Format(sLogMsg, sizeof(sLogMsg), "%s%s", g_sConsoleTag, g_sConsoleName);
				iNamePadding = 68 - strlen(sLogMsg);
				char[] sPad = new char[iNamePadding];	//char sPad[iNamePadding];
				Format(sPad, iNamePadding, "                                                                    ");
				Format(sLogMsg, sizeof(sLogMsg), "%s%s", sPad, sLogMsg);
				Format(sLogMsg, sizeof(sLogMsg), "%s  %s", sLogMsg, sText);
				LogToFileEx(g_sChatLogPath, sLogMsg);
			}
			else
			{
				SendChatToDB(client, sText, sizeof(sText), "TEAM SAY");
			}
		}
		return Plugin_Handled;
	}
	else
	{
		if(PreCheckMessage(client, sText) == 0)
		{
			return Plugin_Handled;
		}
		
		if(g_cLog.BoolValue && (g_oDatabase != null))
		{
			if(!g_bMySQL)
			{
				int iTeam = GetClientTeam(client);
				char sTeam[12];
				if(iTeam == 2)
				{
					Format(sTeam, sizeof(sTeam), "TERR(team)");
				}
				else if(iTeam == 3)
				{
					Format(sTeam, sizeof(sTeam), " CT(team) ");
				}
				else
				{
					Format(sTeam, sizeof(sTeam), "SPEC(team)");
				}
				iNamePadding = 33 - strlen(ga_sEscapedName[client]);
				char[] sPad2 = new char[iNamePadding];	//char sPad2[iNamePadding];
				Format(sPad2, iNamePadding, "                                ");
				Format(sLogMsg, sizeof(sLogMsg), "%s%s", sPad2, ga_sEscapedName[client]);
				Format(sLogMsg, sizeof(sLogMsg), "[%20s][%s]%s:  %s", gaa_sSteamID[client][0], sTeam, sLogMsg, sText);
				LogToFileEx(g_sChatLogPath, sLogMsg);
			}
			else
			{
				SendChatToDB(client, sText, sizeof(sText), "TEAM SAY");
			}
			
			if(g_cHideChatTriggers.BoolValue)
			{
				if(IsChatTrigger())
				{
					return Plugin_Handled;
				}
				else if(StrContains(sText, "!", false) == 0)
				{
					return Plugin_Handled;
				}
				else if(StrContains(sText, "/", false) == 0)
				{
					return Plugin_Handled;
				}
			}
		}
	}
		
	return Plugin_Continue;
}

public Action OnSayText2(UserMsg msg_id, Handle hUserMsg, int[] a_iClients, int iNumClients, bool bReliable, bool bInit)
{
	bool bProtobuf = (CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf);
	int client;
	if(bProtobuf)
	{
		client = PbReadInt(hUserMsg, "ent_idx");
	}
	else
	{
		client = BfReadByte(hUserMsg);
	}

	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}
	else
	{
		if(BaseComm_IsClientGagged(client))
		{
			CreateTimer(0.1, TimerCB_Gagged, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
			return Plugin_Handled;	
		}
	}
	
	/**
	Get the chat bool.  This determines if sent to console as well as chat
	*/
	bool bChat;
	if(bProtobuf)
	{
		bChat = PbReadBool(hUserMsg, "chat");
	}
	else
	{
		bChat = (BfReadByte(hUserMsg) ? true : false);
	}
	
	/**
	Make sure we have a default translation string for the message
	This also determines the message type...
	*/
	char sTranslationName[32];
	if(bProtobuf)
	{
		PbReadString(hUserMsg, "msg_name", sTranslationName, sizeof(sTranslationName));
	}
	else
	{
		BfReadString(hUserMsg, sTranslationName, sizeof(sTranslationName));
	}
	
	if(StrContains(sTranslationName, "Cstrike_Name_Change", false) != -1)
	{
		return Plugin_Continue;
	}

	if(g_aTranslationNames.FindString(sTranslationName) == -1)
	{
		return Plugin_Continue;
	}
	
	char sName[64], sMsg[128], sTag[35], sTranslation[256];
	if(bProtobuf)
	{
		PbReadString(hUserMsg, "params", sName, sizeof(sName), 0);
	}
	else if(BfGetNumBytesLeft(hUserMsg))
	{
		BfReadString(hUserMsg, sName, sizeof(sName));
	}

	if(bProtobuf)
	{
		PbReadString(hUserMsg, "params", sMsg, sizeof(sMsg), 1);
	}
	else if(BfGetNumBytesLeft(hUserMsg))
	{
		BfReadString(hUserMsg, sMsg, sizeof(sMsg));
	}
	
	//format message
	if(!StrEqual(ga_sChatColor[client], "", false))
	{
		Format(sMsg, sizeof(sMsg), "%s%s", ga_sChatColor[client], sMsg);
	}
	else
	{
		if(GetClientTeam(client) == 2)
		{
			Format(sMsg, sizeof(sMsg), "%s%s", g_sTChatColor, sMsg);
		}
		else if(GetClientTeam(client) == 3)
		{
			Format(sMsg, sizeof(sMsg), "%s%s", g_sCTChatColor, sMsg);
		}
		else
		{
			Format(sMsg, sizeof(sMsg), "\x01%s", sMsg);
		}
	}

	//tag
	if(!StrEqual(ga_sTag[client], "", false) && ga_iTagVisible[client])
	{
		if(!StrEqual(ga_sTagColor[client], "", false))
		{
			Format(sTag, sizeof(sTag), "%s%s", ga_sTagColor[client], ga_sTag[client]);
		}
		else
		{
			Format(sTag, sizeof(sTag), "\x01%s", ga_sTag[client]);
		}
		
		if(g_cForceBrackets.IntValue == 1)
		{
			Format(sTag, sizeof(sTag), "%s{%s%s}", g_sBracketColors, sTag, g_sBracketColors);
		}
		else if(g_cForceBrackets.IntValue == 2)
		{
			Format(sTag, sizeof(sTag), "%s[%s%s]", g_sBracketColors, sTag, g_sBracketColors);
		}
		Format(sTag, sizeof(sTag), "%s ", sTag);
	}
	else
	{
		Format(sTag, sizeof(sTag), "");
	}
	
	//external tag
	if(!StrEqual(ga_sExtTag[client], "", false))
	{
		if(g_cExternalPos.IntValue == 1) //right side
		{
			Format(sTag, sizeof(sTag), "%s%s%s", sTag, ga_sExtTagColor[client], ga_sExtTag[client]);
		}
		else if(!g_cExternalPos.IntValue) //left
		{
			Format(sTag, sizeof(sTag), "%s%s%s", ga_sExtTagColor[client], ga_sExtTag[client], sTag);
		}
		else if(g_cExternalPos.IntValue == 2)	//if external tag exists, override custom
		{
			if(!StrEqual(ga_sExtTag[client], "", false))
			{
				Format(sTag, sizeof(sTag), "%s%s", ga_sExtTagColor[client], ga_sExtTag[client]);
			}
		}
		else if(g_cExternalPos.IntValue == 3)  //if custom tag does not exist, use external, else use custom
		{
			if(!StrEqual(ga_sTag[client], "", false) && StrEqual(ga_sExtTag[client], "", false))
			{
				Format(sTag, sizeof(sTag), "%s%s", ga_sExtTagColor[client], ga_sExtTag[client]);
			}
		}
	}
	
	//name
	if(!StrEqual(ga_sNameColor[client], "", false))
	{
		Format(sName, sizeof(sName), "%s%s", ga_sNameColor[client], ga_sName[client]);
	}
	else
	{
		if(GetClientTeam(client) == 2)
		{
			Format(sName, sizeof(sName), "%s%s", g_sTNameColor, ga_sName[client]);
		}
		else if(GetClientTeam(client) == 3)
		{
			Format(sName, sizeof(sName), "%s%s", g_sCTNameColor, ga_sName[client]);
		}
		else
		{
			Format(sName, sizeof(sName), "\x03%s", ga_sName[client]);
		}
	}
	Format(sName, sizeof(sName), "%s%s", sTag, sName); //combine tag into name
	if(g_bCSGO || g_bIns)
	{
		Format(sName, sizeof(sName), " \x01%s", sName);
	}

	Format(sTranslation, sizeof(sTranslation), "%t", sTranslationName, sName, sMsg);

	int iEntIDOverride = client;
	if(ga_iEntOverride[client] == 1)
	{
		iEntIDOverride = 0;
	}
	else if(ga_iEntOverride[client] == 2)
	{
		iEntIDOverride = -1;
	}
	else if(ga_iEntOverride[client] == 3)
	{
		iEntIDOverride = -3;
	}
	
	if(g_cAllowBlockChat.BoolValue)
	{
		//debug
		/*Log("test.log", "Entered function to block chat. # clients = %i. Initial array size: %i", iNumClients, sizeof(a_iClients[]));
		for(int i = 0; i < sizeof(a_iClients[]); i++)
		{
			Log("test.log", "Client in original static array: %L", a_iClients[i]);
		}*/
		
		//check clients, pushing filtered clients to an array
		ArrayList hTempArray;
		hTempArray = new ArrayList();
		hTempArray.Clear();
		for(int i = 0; i < iNumClients; i++)
		{
			//Log("test.log", "Checking slot %i", i);
			int target = a_iClients[i];
			if(IsValidClient(target, true))
			{
				//Log("test.log", "Checking client %L", target);
				if(!ga_bChatBlocked[target])
				{
					//Log("test.log", "Adding client %L", target);
					hTempArray.Push(target);
				}
				else
				{
					//Log("test.log", "%L has chat blocked!", target);
				}
			}
			else //to server? Not sure if clients are players only....adding this just in case
			{
				hTempArray.Push(target);
				//Log("test.log", "Adding non-player client %L", target);
			}
		}
		
		//Log("test.log", "Finished checking players. # clients = %i. Temp array size: %i", iNumClients, hTempArray.Length);
		//transfer clients back to array
		if((hTempArray.Length != iNumClients))
		{
			iNumClients = hTempArray.Length;
			//Log("test.log", "Client count changed. Transferring back to array. New # clients = %i", iNumClients + 1);
			if(iNumClients != -1)
			{
				for(int j = 0; j < hTempArray.Length; j++)
				{
					//Log("test.log", "Transferring client %L", j);
					a_iClients[j] = hTempArray.Get(j);
				}
				a_iClients[iNumClients] = '\0';	//add null terminator
			}
		}
		delete hTempArray;	//clean up
	}

	if(bProtobuf)
	{
		PbSetInt(hUserMsg, "ent_idx", iEntIDOverride);
		PbSetBool(hUserMsg, "chat", bChat);
		PbSetString(hUserMsg, "msg_name", sTranslation);
		PbSetString(hUserMsg, "params", "", 0);
		PbSetString(hUserMsg, "params", "", 1);
	}
	else
	{
		DataPack oPack = new DataPack();
		//iNumClients,a_iClients[], iNumClients
		
		oPack.WriteCell(iEntIDOverride);
		oPack.WriteCell(bChat);
		oPack.WriteString(sTranslation);
		oPack.WriteCell(iNumClients);
		for(int i = 0; i < iNumClients; i++)
		{
			oPack.WriteCell(a_iClients[i]);
		}
		g_aMessages.Push(oPack);
		oPack.Reset();
		return Plugin_Handled;
		/*BfWriteByte(hUserMsg, iEntIDOverride);
		BfWriteByte(hUserMsg, bChat);
		BfWriteString(hUserMsg, sTranslation);
		BfWriteString(hUserMsg, "");
		BfWriteString(hUserMsg, "");*/
	}
	
	return Plugin_Changed;
}

void GetTranslationNames(const char[] sFile)
{
	g_aTranslationNames.Clear();

	KeyValues oKeyValues = new KeyValues("Phrases");

	if(!FileExists(sFile))
	{
		delete oKeyValues;
		SetFailState("Translation file not found: %s", sFile);
		return;
	}

	if(!oKeyValues.ImportFromFile(sFile))
	{
		delete oKeyValues;
		SetFailState("Improper structure for translation file: %s", sFile);
		return;
	}
	
	if(oKeyValues.GotoFirstSubKey(true))
	{
		do
		{
			char sSectionName[100];
			oKeyValues.GetSectionName(sSectionName, sizeof(sSectionName));
			g_aTranslationNames.PushString(sSectionName);
		} while(oKeyValues.GotoNextKey(false));
		oKeyValues.GoBack();
	}
	else
	{
		SetFailState("Can't find first subkey in translation file: %s!", sFile);
		return;
	}
	delete oKeyValues;
}

public void OnGameFrame()
{
	for(int i = 0; i < g_aMessages.Length; i++)
	{
		DataPack oPack = new DataPack();
		oPack = g_aMessages.Get(i); //does this create a second handle or use the existing one?
		char sTranslation[256];
		int client = oPack.ReadCell();
		bool bChat = oPack.ReadCell();
		oPack.ReadString(sTranslation, sizeof(sTranslation));
		int iNumClients = oPack.ReadCell();
		//get clients
		ArrayList hTempArray;
		hTempArray = new ArrayList();
		hTempArray.Clear(); //INITIALIZE ARRAY
		for(int j = 0; j < iNumClients; j++)
		{
			int target = oPack.ReadCell();
			if(IsValidClient(target))
			{
				hTempArray.Push(target);
			}
		}
		delete oPack;
		
		iNumClients = hTempArray.Length;
		int[] a_iClients = new int[iNumClients];
		/*if(client != -3)
		{*/
		for(int j = 0; j < iNumClients; j++)
		{
			a_iClients[j] = hTempArray.Get(j);
		}
		delete hTempArray;
		
		Handle hBF = StartMessage("SayText2", a_iClients, iNumClients, USERMSG_RELIABLE | USERMSG_BLOCKHOOKS);
		BfWriteByte(hBF, client);
		BfWriteByte(hBF, bChat);
		BfWriteString(hBF, sTranslation);
		EndMessage();
		/*}
		else
		{
			for(int j = 0; j < iNumClients; j++)
			{
				CPrintToChat(hTempArray.Get(j), sTranslation);
				//Client_PrintToChat(hTempArray.Get(j), bChat, sTranslation);
			}
			delete hTempArray;
		}*/
		
		g_aMessages.Erase(i);
	}
}

int PreCheckMessage(int client, char[] sText)
{
	if(!IsValidClient(client))
	{
		return 1;
	}
	
	if(g_cConvertTriggerCases.BoolValue && IsValidClient(client))
	{
		if((sText[0] == '!') || (sText[0] == '/'))
		{
			if(IsCharUpper(sText[1]))
			{
				for(int i = 0; i <= strlen(sText); ++i)
				{
					sText[i] = CharToLower(sText[i]);
				}

				FakeClientCommand(client, "say %s", sText);
				
				return 0;
			}
		}
	}

	if(g_cEnableSpamBlock.BoolValue)
	{
		if(!HasFlags(client, g_sSpamIgnoreFlag))
		{
			ga_iChatMsgCnt[client]++;
			CreateTimer(g_cSpamDetectDuration.FloatValue, TimerCB_ReduceMsgCnt, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
			if(ga_iChatMsgCnt[client] > g_cSpamMsgCnt.IntValue)
			{
				CreateTimer(0.1, TimerCB_MsgsTooFast, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
				if(g_cEnableSpamGag.BoolValue)
				{
					ga_iChatSpamCnt[client]++;
					CreateTimer(g_cSpamGagDetectDuration.FloatValue, TimerCB_ReduceSpamCnt, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
					if(ga_iChatSpamCnt[client] > g_cSpamMsgGagCnt.IntValue)
					{
						if(g_bExtendedComm_togedit)
						{
							ExtendedComm_SetGag(0, client, g_cSpamGagPenalty.IntValue, "Auto-gag for Spamming chat");
						}
						else
						{
							BaseComm_SetClientGag(client, true);
						}

						if(!BaseComm_IsClientGagged(client)) //check if not already gagged - you *shouldnt* be able to get here if gagged, but sometimes if the server sends SayText2 msgs enough, it might send you here
						{
							CreateTimer(0.1, TimerCB_Muted, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
						}
					}
				}
			}
		}
	}
	
	return 1;
}

public Action TimerCB_ReduceMsgCnt(Handle hTimer, any iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if(IsValidClient(client))
	{
		ga_iChatMsgCnt[client]--;
	}
}

public Action TimerCB_ReduceSpamCnt(Handle hTimer, any iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if(IsValidClient(client))
	{
		ga_iChatSpamCnt[client]--;
	}
}

public Action TimerCB_Gagged(Handle hTimer, any iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if(IsValidClient(client))
	{
		PrintToChat(client, "=================================");
		PrintToChat(client, " ƪ(ツ)ノ                           Nice Try!                 ( ͡° ͜ʖ ͡°)");
		PrintToChat(client, "--------- You're gagged and cannot speak. --------");
		PrintToChat(client, "(ノಠ益ಠ)ノ彡┻━┻       YOU MAD?       ლ(ಠ益ಠლ)");
		PrintToChat(client, "=================================");
	}
}

public Action TimerCB_MsgsTooFast(Handle hTimer, any iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if(IsValidClient(client))
	{
		PrintToChat(client, "%s%sYou are sending messages too fast!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
	}
}

public Action TimerCB_Muted(Handle hTimer, any iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if(IsValidClient(client))
	{
		PrintToChatAll("%s%s%N has been gagged for spamming chat.", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED), client);
	}
}

public Action Command_AdminChat(int client, const char[] sCommand, int iArgC)
{
	if(!g_cLog.BoolValue)
	{
		return Plugin_Continue;
	}
	
	char sBuffer[128], sName[MAX_NAME_LENGTH], sID[MAX_NAME_LENGTH];
	GetCmdArgString(sBuffer, sizeof(sBuffer));
	
	if(g_oDatabase != null)
	{
		if(!g_bMySQL)
		{
			if(IsValidClient(client))
			{
				strcopy(sID, sizeof(sID), gaa_sSteamID[client][0]);
				GetClientName(client, sName, sizeof(sName));
			}
			else
			{
				Format(sID, sizeof(sID), "CONSOLE");
				Format(sName, sizeof(sName), "CONSOLE");
			}
			
			int iNamePadding = 33 - strlen(sName);
			char[] sPad2 = new char[iNamePadding];
			
			char sLogMsg[256], sTeam[12];
			Format(sPad2, iNamePadding, "                                ");
			Format(sLogMsg, sizeof(sLogMsg), "%s%s", sPad2, sName);
			Format(sTeam, sizeof(sTeam), "   ADMIN  ");
			Format(sLogMsg, sizeof(sLogMsg), "[%20s][%s]%s: %s", sID, sTeam, sLogMsg, sBuffer);
			LogToFileEx(g_sChatLogPath, sLogMsg);
		}
		else
		{
			SendChatToDB(client, sBuffer, sizeof(sBuffer), "ADMIN ALL CHAT");
		}
	}
	return Plugin_Continue;
}

public Action Command_AdminOnlyChat(int client, const char[] sCommand, int iArgC)
{
	if(!g_cLog.BoolValue)
	{
		return Plugin_Continue;
	}
	
	char sBuffer[128], sName[MAX_NAME_LENGTH], sID[MAX_NAME_LENGTH];
	GetCmdArgString(sBuffer, sizeof(sBuffer));
	
	if(g_oDatabase != null)
	{
		if(!g_bMySQL)
		{
			if(IsValidClient(client))
			{
				strcopy(sID, sizeof(sID), gaa_sSteamID[client][0]);
				GetClientName(client, sName, sizeof(sName));
			}
			else
			{
				Format(sID, sizeof(sID), "CONSOLE");
				Format(sName, sizeof(sName), "CONSOLE");
			}

			int iNamePadding = 33 - strlen(sName);
			char[] sPad2 = new char[iNamePadding];
			char sLogMsg[256], sTeam[12];
			Format(sPad2, iNamePadding, "                                ");
			Format(sLogMsg, sizeof(sLogMsg), "%s%s", sPad2, sName);
			Format(sTeam, sizeof(sTeam), "ADMIN ONLY");
			Format(sLogMsg, sizeof(sLogMsg), "[%20s][%s]%s: %s", sID, sTeam, sLogMsg, sBuffer);
			LogToFileEx(g_sChatLogPath, sLogMsg);
		}
		else
		{
			SendChatToDB(client, sBuffer, sizeof(sBuffer), "ADMIN ONLY");
		}
	}
	return Plugin_Continue;
}

public Action Command_CSay(int client, const char[] sCommand, int iArgC)
{
	if(!g_cLog.BoolValue)
	{
		return Plugin_Continue;
	}
	
	char sBuffer[128], sName[MAX_NAME_LENGTH], sID[MAX_NAME_LENGTH];
	GetCmdArgString(sBuffer, sizeof(sBuffer));
	
	if(g_oDatabase != null)
	{
		if(!g_bMySQL)
		{
			if(IsValidClient(client))
			{
				strcopy(sID, sizeof(sID), gaa_sSteamID[client][0]);
				GetClientName(client, sName, sizeof(sName));
			}
			else
			{
				Format(sID, sizeof(sID), "CONSOLE");
				Format(sName, sizeof(sName), "CONSOLE");
			}
		
			int iNamePadding = 33 - strlen(sName);
			char[] sPad2 = new char[iNamePadding];
			char sLogMsg[256], sTeam[12];
			Format(sPad2, iNamePadding, "                                ");
			Format(sLogMsg, sizeof(sLogMsg), "%s%s", sPad2, sName);
			Format(sTeam, sizeof(sTeam), "   CSAY   ");
			Format(sLogMsg, sizeof(sLogMsg), "[%20s][%s]%s: %s", sID, sTeam, sLogMsg, sBuffer);
			LogToFileEx(g_sChatLogPath, sLogMsg);
		}
		else
		{
			SendChatToDB(client, sBuffer, sizeof(sBuffer), "CENTER MSG");
		}
	}
	return Plugin_Continue;
}

public Action Command_TSay(int client, const char[] sCommand, int iArgC)
{
	if(!g_cLog.BoolValue)
	{
		return Plugin_Continue;
	}
	
	char sBuffer[128], sName[MAX_NAME_LENGTH], sID[MAX_NAME_LENGTH];
	GetCmdArgString(sBuffer, sizeof(sBuffer));
	
	if(g_oDatabase != null)
	{
		if(!g_bMySQL)
		{
			if(IsValidClient(client))
			{
				strcopy(sID, sizeof(sID), gaa_sSteamID[client][0]);
				GetClientName(client, sName, sizeof(sName));
			}
			else
			{
				Format(sID, sizeof(sID), "CONSOLE");
				Format(sName, sizeof(sName), "CONSOLE");
			}
			
			int iNamePadding = 33 - strlen(sName);
			char[] sPad2 = new char[iNamePadding];
			char sLogMsg[256], sTeam[12];
			Format(sPad2, iNamePadding, "                                ");
			Format(sLogMsg, sizeof(sLogMsg), "%s%s", sPad2, sName);
			Format(sTeam, sizeof(sTeam), "   TSAY   ");
			Format(sLogMsg, sizeof(sLogMsg), "[%20s][%s]%s: %s", sID, sTeam, sLogMsg, sBuffer);
			LogToFileEx(g_sChatLogPath, sLogMsg);
		}
		else
		{
			SendChatToDB(client, sBuffer, sizeof(sBuffer), "TOP MSG");
		}
	}

	return Plugin_Continue;
}

public Action Command_MSay(int client, const char[] sCommand, int iArgC)
{
	if(!g_cLog.BoolValue)
	{
		return Plugin_Continue;
	}
	
	char sBuffer[128], sName[MAX_NAME_LENGTH], sID[MAX_NAME_LENGTH];
	GetCmdArgString(sBuffer, sizeof(sBuffer));
	
	if(g_oDatabase != null)
	{
		if(!g_bMySQL)
		{
			if(IsValidClient(client))
			{
				strcopy(sID, sizeof(sID), gaa_sSteamID[client][0]);
				GetClientName(client, sName, sizeof(sName));
			}
			else
			{
				Format(sID, sizeof(sID), "CONSOLE");
				Format(sName, sizeof(sName), "CONSOLE");
			}
			
			int iNamePadding = 33 - strlen(sName);
			char[] sPad2 = new char[iNamePadding];
			char sLogMsg[256], sTeam[12];
			Format(sPad2, iNamePadding, "                                ");
			Format(sLogMsg, sizeof(sLogMsg), "%s%s", sPad2, sName);
			Format(sTeam, sizeof(sTeam), "   MSAY   ");
			Format(sLogMsg, sizeof(sLogMsg), "[%20s][%s]%s: %s", sID, sTeam, sLogMsg, sBuffer);
			LogToFileEx(g_sChatLogPath, sLogMsg);
		}
		else
		{
			SendChatToDB(client, sBuffer, sizeof(sBuffer), "MENU MSG");
		}
	}

	return Plugin_Continue;
}

public Action Command_HSay(int client, const char[] sCommand, int iArgC)
{
	if(!g_cLog.BoolValue)
	{
		return Plugin_Continue;
	}
	
	char sBuffer[128], sName[MAX_NAME_LENGTH], sID[MAX_NAME_LENGTH];
	GetCmdArgString(sBuffer, sizeof(sBuffer));
	
	if(g_oDatabase != null)
	{
		if(!g_bMySQL)
		{
			if(IsValidClient(client))
			{
				strcopy(sID, sizeof(sID), gaa_sSteamID[client][0]);
				GetClientName(client, sName, sizeof(sName));
			}
			else
			{
				Format(sID, sizeof(sID), "CONSOLE");
				Format(sName, sizeof(sName), "CONSOLE");
			}

			int iNamePadding = 33 - strlen(sName);
			char[] sPad2 = new char[iNamePadding];
			char sLogMsg[256], sTeam[12];
			Format(sPad2, iNamePadding, "                                ");
			Format(sLogMsg, sizeof(sLogMsg), "%s%s", sPad2, sName);
			Format(sTeam, sizeof(sTeam), "   HSAY   ");
			Format(sLogMsg, sizeof(sLogMsg), "[%20s][%s]%s: %s", sID, sTeam, sLogMsg, sBuffer);
			LogToFileEx(g_sChatLogPath, sLogMsg);
		}
		else
		{
			SendChatToDB(client, sBuffer, sizeof(sBuffer), "HINT MSG");
		}
	}

	return Plugin_Continue;
}

public Action Command_PSay(int client, const char[] sCommand, int iArgC)
{
	if(!g_cLog.BoolValue)
	{
		return Plugin_Continue;
	}
	
	char sBuffer[128], sName[MAX_NAME_LENGTH], sID[MAX_NAME_LENGTH];
	GetCmdArgString(sBuffer, sizeof(sBuffer));
	
	if(g_oDatabase != null)
	{
		if(!g_bMySQL)
		{
			if(IsValidClient(client))
			{
				strcopy(sID, sizeof(sID), gaa_sSteamID[client][0]);
				GetClientName(client, sName, sizeof(sName));
			}
			else
			{
				Format(sID, sizeof(sID), "CONSOLE");
				Format(sName, sizeof(sName), "CONSOLE");
			}
			
			int iNamePadding = 33 - strlen(sName);
			char[] sPad2 = new char[iNamePadding];
			char sLogMsg[256], sTeam[12];
			Format(sPad2, iNamePadding, "                                ");
			Format(sLogMsg, sizeof(sLogMsg), "%s%s", sPad2, sName);
			Format(sTeam, sizeof(sTeam), "   PSAY   ");
			Format(sLogMsg, sizeof(sLogMsg), "[%20s][%s]%s: %s", sID, sTeam, sLogMsg, sBuffer);
			LogToFileEx(g_sChatLogPath, sLogMsg);
		}
		else
		{
			SendChatToDB(client, sBuffer, sizeof(sBuffer), "PRIVATE MSG");
		}
	}

	return Plugin_Continue;
}

void SendChatToDB(int client, char[] sMsg, int iSize, char[] sChatGrp)
{
	StripQuotes(sMsg);
	if(StrEqual(sMsg, "", false))
	{
		return;
	}
	int iEscapeSize = 2*iSize + 1;
	char[] sEscapedMsg = new char[iEscapeSize];
	g_oDatabase.Escape(sMsg, sEscapedMsg, iEscapeSize);
	char sIP[MAX_NAME_LENGTH], sCountry[45], sName[MAX_NAME_LENGTH], sSteamID[65];
	char sQuery[1000];
	if(IsValidClient(client, true))
	{
		if(IsFakeClient(client))
		{
			sIP = "BOT";
			sCountry = "BOT";
			sSteamID = "BOT";
		}
		else
		{
			GetClientIP(client, sIP, sizeof(sIP));
			GeoipCountry(sIP, sCountry, sizeof(sCountry));
			strcopy(sSteamID, sizeof(sSteamID), gaa_sSteamID[client][0]);
		}
		strcopy(sName, sizeof(sName), ga_sEscapedName[client]);
		if(!StrEqual(sName, "", false))
		{
			GetClientName(client, ga_sEscapedName[client], sizeof(ga_sEscapedName[]));
			CleanStringForSQL(ga_sEscapedName[client], sizeof(ga_sEscapedName[]));
			strcopy(sName, sizeof(sName), ga_sEscapedName[client]);
		}
	}
	else
	{
		sIP = "CONSOLE";
		sCountry = "CONSOLE";
		sSteamID = "CONSOLE";
		sName = "CONSOLE";
	}
	
	Format(sQuery, sizeof(sQuery), "INSERT INTO `tct_chatlogs` (steamid, mapname, server, playername, playerip, ip_country, chatmsg, chatgrp) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s');", sSteamID, g_sMapName, g_sServerIP, sName, sIP, sCountry, sEscapedMsg, sChatGrp);
	g_oDatabase.Query(SQLCallback_Void, sQuery, 4);
}

public Action Event_NameChange(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	if(IsValidClient(client))
	{
		if(g_oDatabase != null)
		{
			GetClientName(client, ga_sEscapedName[client], sizeof(ga_sEscapedName[]));
			strcopy(ga_sName[client], sizeof(ga_sName[]), ga_sEscapedName[client]);
			CleanStringForSQL(ga_sEscapedName[client], sizeof(ga_sEscapedName[]));
		}
	}
	return Plugin_Continue;
}

void Reload()
{
	LoadColorCfg();
	LoadCustomConfigs();
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && AreClientCookiesCached(i) && IsClientAuthorized(i))
		{
			OnClientConnected(i);
			LoadClientData(i);
		}
	}
	
	Call_StartForward(g_hLoadFwd);
	Call_Finish();
}

public void OnClientSettingsChanged(int client)
{
	if(IsValidClient(client))
	{
		if(g_oDatabase != null)
		{
			GetClientName(client, ga_sEscapedName[client], sizeof(ga_sEscapedName[]));
			strcopy(ga_sName[client], sizeof(ga_sName[]), ga_sEscapedName[client]);
			CleanStringForSQL(ga_sEscapedName[client], sizeof(ga_sEscapedName[]));
			CheckTag(client);
		}
	}
}

//////////////////////////////////////////////////////////////////////////
///////////////////////////// Admin Commands /////////////////////////////
//////////////////////////////////////////////////////////////////////////

public Action Cmd_Reload(int client, int iArgs)
{
	if(client != 0)
	{	
		if(!HasFlags(client, g_sAdminFlag))
		{
			PrintToConsole(client, "%sYou do not have access to this command!", g_sTag);
			PrintToChat(client, "%s%sYou do not have access to this command!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
			return Plugin_Handled;
		}
	}
	
	Reload();
	
	ReplyToCommand(client, "%s%sColors setups are now reloaded.", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
	
	return Plugin_Handled;
}

public Action Cmd_Unload(int client, int iArgs)
{
	if(client != 0)
	{	
		if(!HasFlags(client, g_sAdminFlag))
		{
			PrintToConsole(client, "%sYou do not have access to this command!", g_sTag);
			PrintToChat(client, "%s%sYou do not have access to this command!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
			return Plugin_Handled;
		}
	}
	
	ReplyToCommand(client, "%s%sTOGs Chat Tags is now unloaded until map change!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
	
	char sPluginName[128];
	GetPluginFilename(INVALID_HANDLE, sPluginName, sizeof(sPluginName));
	ServerCommand("sm plugins unload %s", sPluginName);
	
	return Plugin_Handled;
}

public Action Cmd_RemoveOverride(int client, int iArgs)
{
	if(client != 0)
	{	
		if(!HasFlags(client, g_sAdminFlag_Force))
		{
			PrintToConsole(client, "%sYou do not have access to this command!", g_sTag);
			PrintToChat(client, "%s%sYou do not have access to this command!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
			return Plugin_Handled;
		}
	}
	
	if(iArgs != 1)
	{
		if(client != 0)
		{
			PrintToConsole(client, "%sUsage: sm_removeoverride <target>", g_sTag);
			PrintToChat(client, "%s%sUsage: sm_removeoverride <target>", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		}
		else
		{
			ReplyToCommand(client, "%sUsage: sm_removeoverride <target>", g_sTag);
		}
		return Plugin_Handled;
	}
	
	char sTarget[65], sTargetName[MAX_TARGET_LENGTH];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	int a_iTargets[MAXPLAYERS], iTargetCount;
	bool bTN_ML;
	if((iTargetCount = ProcessTargetString(sTarget, client, a_iTargets, MAXPLAYERS, COMMAND_FILTER_NO_IMMUNITY, sTargetName, sizeof(sTargetName), bTN_ML)) <= 0)
	{
		ReplyToCommand(client, "%sNot found or invalid parameter.", g_sTag);
		return Plugin_Handled;
	}
	
	for(int i = 0; i < iTargetCount; i++)
	{
		int target = a_iTargets[i];
		if(IsValidClient(target))
		{
			gaa_iAdminOvrd[target][0] = 0;
			gaa_iAdminOvrd[target][1] = 0;
			gaa_iAdminOvrd[target][2] = 0;
			gaa_iAdminOvrd[target][3] = 0;
			SendClientSetupToDB(target);
			
			LogMessage("%L has removed the admin overrides for player %L", client, target);
			ReplyToCommand(client, "%sRemoved setup for player: %N", g_sTag);
		}
	}
	
	return Plugin_Handled;
}

public Action Cmd_ForceTag(int client, int iArgs)
{
	if(client != 0)
	{	
		if(!HasFlags(client, g_sAdminFlag_Force))
		{
			PrintToConsole(client, "%sYou do not have access to this command!", g_sTag);
			PrintToChat(client, "%s%sYou do not have access to this command!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
			return Plugin_Handled;
		}
	}
	
	if(iArgs < 2)
	{
		if(client != 0)
		{
			PrintToConsole(client, "%sUsage: sm_forcetag <target> <tag in quotes> <tag color> <name color> <chat color> (pass \"skip\" to skip overriding one, or \"remove\" to reset it - omitted args assume skip).", g_sTag);
			PrintToChat(client, "%s%sUsage: sm_forcetag <target> <tag in quotes> <tag color> <name color> <chat color> (pass \"skip\" to skip overriding one, or \"remove\" to reset it - omitted args assume skip).", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
			return Plugin_Handled;
		}
		else
		{
			ReplyToCommand(client, "%sUsage: sm_forcetag <target> <tag in quotes> <tag color> <name color> <chat color> (pass \"skip\" to skip overriding one, or \"remove\" to reset it - omitted args assume skip).", g_sTag);
			return Plugin_Handled;
		}
	}
	
	char sTarget[65], sTargetName[MAX_TARGET_LENGTH];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	int a_iTargets[MAXPLAYERS], iTargetCount;
	bool bTN_ML;
	if((iTargetCount = ProcessTargetString(sTarget, client, a_iTargets, MAXPLAYERS, COMMAND_FILTER_NO_IMMUNITY, sTargetName, sizeof(sTargetName), bTN_ML)) <= 0)
	{
		ReplyToCommand(client, "%sNot found or invalid parameter.", g_sTag);
		return Plugin_Handled;
	}
	
	int iSize = MAXTAGSIZE;
	if(iSize < 30)
	{
		iSize = 30;
	}
	
	char[] sTag = new char[iSize];
	char sTagColor[32], sNameColor[32], sChatColor[32];
	
	GetCmdArg(2, sTag, iSize);
	
	if(iArgs > 2)
	{
		GetCmdArg(3, sTagColor, sizeof(sTagColor));
	}
	else
	{
		Format(sTagColor, sizeof(sTagColor), "skip");
	}
	
	if(iArgs > 3)
	{
		GetCmdArg(4, sNameColor, sizeof(sNameColor));
	}
	else
	{
		Format(sNameColor, sizeof(sNameColor), "skip");
	}
	
	if(iArgs > 4)
	{
		GetCmdArg(5, sChatColor, sizeof(sChatColor));
	}
	else
	{
		Format(sChatColor, sizeof(sChatColor), "skip");
	}
	
	for(int i = 0; i < iTargetCount; i++)
	{
		int target = a_iTargets[i];
		if(IsValidClient(target))
		{
			if(StrEqual(sTag, "remove", false))
			{
				ga_iTagVisible[target] = 0;
				ga_sTag[target] = "";
				gaa_iAdminOvrd[target][0] = 1;
				gaa_sCleanSetupText[target][0] = "";
			}
			else if(!StrEqual(sTag, "skip", false))
			{
				ga_iTagVisible[target] = 3;
				strcopy(ga_sTag[target], sizeof(ga_sTag[]), sTag);
				strcopy(gaa_sCleanSetupText[target][0], sizeof(gaa_sCleanSetupText[][]), sTag);
				gaa_iAdminOvrd[target][0] = 1;
				gaa_sCleanSetupText[target][0] = "";
			}
			
			if(StrEqual(sTagColor, "remove", false))
			{
				ga_sTagColor[target] = "";
				gaa_sCleanSetupText[target][1] = "";
				gaa_iAdminOvrd[target][1] = 1;
			}
			else if(!StrEqual(sTagColor, "skip", false))
			{
				strcopy(ga_sTagColor[target], sizeof(ga_sTagColor[]), sTagColor);
				strcopy(gaa_sCleanSetupText[target][1], sizeof(gaa_sCleanSetupText[][]), sTagColor);
				gaa_iAdminOvrd[target][1] = 1;
			}
			
			if(StrEqual(sNameColor, "remove", false))
			{
				ga_sNameColor[target] = "";
				gaa_sCleanSetupText[target][2] = "";
				gaa_iAdminOvrd[target][2] = 1;
			}
			else if(!StrEqual(sNameColor, "skip", false))
			{
				strcopy(ga_sNameColor[target], sizeof(ga_sNameColor[]), sNameColor);
				strcopy(gaa_sCleanSetupText[target][2], sizeof(gaa_sCleanSetupText[][]), sNameColor);
				gaa_iAdminOvrd[target][2] = 1;
			}

			if(StrEqual(sChatColor, "remove", false))
			{
				ga_sChatColor[target] = "";
				gaa_sCleanSetupText[target][3] = "";
				gaa_iAdminOvrd[target][3] = 1;
			}
			else if(!StrEqual(sChatColor, "skip", false))
			{
				strcopy(ga_sChatColor[target], sizeof(ga_sChatColor[]), sChatColor);
				strcopy(gaa_sCleanSetupText[target][3], sizeof(gaa_sCleanSetupText[][]), sChatColor);
				gaa_iAdminOvrd[target][3] = 1;
			}			
			
			FormatColors(target);
			SendClientSetupToDB(target);
			
			if(IsValidClient(client))
			{
				PrintToChat(client, "%sTags/colors successfully set to: %s%s %s%N: %sChat colors...", g_sTag, ga_sTagColor[target], ga_sTag[target], ga_sNameColor[target], target, ga_sChatColor[target]);
			}
			
			LogMessage("%L has set an admin overrides for player %L: %s%s %s%N: %sChat colors...", client, target, ga_sTagColor[target], ga_sTag[target], ga_sNameColor[target], target, ga_sChatColor[target]);
		}
	}
	
	return Plugin_Handled;
}

public Action Cmd_RemoveTag(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "%s%sMust be in the server to execute command!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(iArgs != 1)
	{
		ReplyToCommand(client, "%s%sUsage: sm_removetag <name>", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(!HasFlags(client, g_sAdminFlag))
	{
		PrintToConsole(client, "%s%sYou do not have access to this command!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		PrintToChat(client, "%s%sYou do not have access to this command!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	char sTargetArg[MAX_NAME_LENGTH];
	GetCmdArg(1,sTargetArg,sizeof(sTargetArg));
	
	int iPlayers = SearchForPlayer(sTargetArg);
	if(iPlayers == 0)
	{
		ReplyToCommand(client, "%s%sNo valid clients found!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	else if(iPlayers > 1)
	{
		ReplyToCommand(client, "%s%sMore than one matching player found!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	int target = 0;
	
	if(iPlayers == -1)
	{
		ReplaceString(sTargetArg, sizeof(sTargetArg), "#", "", false);
		target = GetClientOfUserId(StringToInt(sTargetArg));
	}
	else
	{
		target = FindTarget(client, sTargetArg, true);
	}
	
	if(!IsValidClient(target))
	{
		ReplyToCommand(client, "%s%sInvalid target!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(IsFakeClient(target))
	{
		ReplyToCommand(client, "%s%sCannot target bots!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	RemoveSetup(target);
	ReplyToCommand(client, "%s%sTag settings for player '%s' are now set to default.", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED), ga_sEscapedName[target]);
	SendClientSetupToDB(target);
	
	return Plugin_Handled;
}

void RemoveSetup(int client)
{
	if(!IsValidClient(client))
	{
		return;
	}
	
	ga_iTagVisible[client] = 0;		
	//ga_iIsRestricted[client] = 0;
	ga_sTagColor[client] = "";
	ga_sNameColor[client] = "";
	ga_sChatColor[client] = "";	
	gaa_sCleanSetupText[client][0] = "";
	gaa_sCleanSetupText[client][1] = "";
	gaa_sCleanSetupText[client][2] = "";
	gaa_sCleanSetupText[client][3] = "";
	ga_sTag[client] = "";

	if(g_cGrpsAfterRemove.BoolValue)
	{
		CheckForGroups(client);
	}
	
	FormatColors(client);
	SendClientSetupToDB(client);
}

public Action Cmd_Restrict(int client, int iArgs)
{
	if(client == 0)
	{
		ReplyToCommand(client, "%s%sMust be in the server to execute command!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(iArgs != 1)
	{
		ReplyToCommand(client, "%s%sUsage: sm_restricttag <name>", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(!HasFlags(client, g_sAdminFlag))
	{
		PrintToConsole(client, "%s%sYou do not have access to this command!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		PrintToChat(client, "%s%sYou do not have access to this command!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	char sTargetArg[MAX_NAME_LENGTH];
	GetCmdArg(1,sTargetArg,sizeof(sTargetArg));
	
	int iPlayers = SearchForPlayer(sTargetArg);
	if(iPlayers == 0)
	{
		ReplyToCommand(client, "%s%sNo valid clients found!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	else if(iPlayers > 1)
	{
		ReplyToCommand(client, "%s%sMore than one matching player found!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	int target = 0;
	
	if(iPlayers == -1)
	{
		ReplaceString(sTargetArg, sizeof(sTargetArg), "#", "", false);
		target = GetClientOfUserId(StringToInt(sTargetArg));
	}
	else
	{
		target = FindTarget(client, sTargetArg, true);
	}
	
	if(!IsValidClient(target))
	{
		ReplyToCommand(client, "%s%sInvalid target!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(IsFakeClient(target))
	{
		ReplyToCommand(client, "%s%sCannot target bots!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	RestrictPlayer(client,target);
	SendClientSetupToDB(target);
	
	return Plugin_Handled;
}

void RestrictPlayer(int client, int target)
{
	if(!IsValidClient(target))
	{
		PrintToConsole(client, "%s%sTarget '%s' is either not in game, or is a bot!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED), ga_sEscapedName[target]);
		PrintToChat(client, "%s%sTarget '%s' is either not in game, or is a bot!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED), ga_sEscapedName[target]);
		return;
	}
	else if(ga_iIsRestricted[target] == 1)
	{
		PrintToConsole(client, "%s%sTarget '%s' is already restricted!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED), ga_sEscapedName[target]);
		PrintToChat(client, "%s%sTarget '%s' is already restricted!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED), ga_sEscapedName[target]);
		return;
	}
	else
	{
		PrintToConsole(client, "%s%s'%s' is now restricted from changing their chat tag!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED), ga_sEscapedName[target]);
		PrintToChatAll("%s%s%s has restricted \x01%s%s from changing their chat tag!", g_sTag, ga_sEscapedName[client], g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED), ga_sEscapedName[target], g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		
		ga_iIsRestricted[target] = 1;
		SendClientSetupToDB(target);
	}
}

public Action Cmd_Unrestrict(int client, int iArgs)
{
	if(client == 0)
	{
		ReplyToCommand(client, "%s%sMust be in the server to execute command!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(iArgs != 1)
	{
		ReplyToCommand(client, "%s%sUsage: sm_unrestricttag <name>", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(!HasFlags(client, g_sAdminFlag))
	{
		PrintToConsole(client, "%s%sYou do not have access to this command!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		PrintToChat(client, "%s%sYou do not have access to this command!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	char sTargetArg[MAX_NAME_LENGTH];
	GetCmdArg(1,sTargetArg,sizeof(sTargetArg));
	
	int iPlayers = SearchForPlayer(sTargetArg);
	if(iPlayers == 0)
	{
		ReplyToCommand(client, "%s%sNo valid clients found!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	else if(iPlayers > 1)
	{
		ReplyToCommand(client, "%s%sMore than one matching player found!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	int target = 0;
	
	if(iPlayers == -1)
	{
		ReplaceString(sTargetArg, sizeof(sTargetArg), "#", "", false);
		target = GetClientOfUserId(StringToInt(sTargetArg));
	}
	else
	{
		target = FindTarget(client, sTargetArg, true);
	}
	
	if(!IsValidClient(target))
	{
		ReplyToCommand(client, "%s%sInvalid target!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(IsFakeClient(target))
	{
		ReplyToCommand(client, "%s%sCannot target bots!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	UnrestrictPlayer(client,target);
	SendClientSetupToDB(target);
	
	return Plugin_Handled;
}

void UnrestrictPlayer(int client, int target)
{
	if(!IsValidClient(target))
	{
		PrintToConsole(client, "%s%sTarget '%s' is either not in game, or is a bot!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED), ga_sEscapedName[target]);
		PrintToChat(client, "%s%sTarget '%s' is either not in game, or is a bot!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED), ga_sEscapedName[target]);
		return;
	}
	else if(ga_iIsRestricted[target] == 0)
	{
		PrintToConsole(client, "%s%sTarget '%s' is not restricted!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED), ga_sEscapedName[target]);
		PrintToChat(client, "%s%sTarget '%s' is not restricted!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED), ga_sEscapedName[target]);
		return;
	}
	else
	{
		PrintToConsole(client, "%s%sTarget '%s' is now unrestricted from changing their chat tag!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED), ga_sEscapedName[target]);
		PrintToChatAll("%s%s%s has unrestricted \x01%s%s from changing their chat tag!", g_sTag, ga_sEscapedName[client], g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED), ga_sEscapedName[target], g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		
		ga_iIsRestricted[target] = 0;
		SendClientSetupToDB(client);
	}
}

////////////////////////////////////////////////////////////////////
///////////////////////////// Commands /////////////////////////////
////////////////////////////////////////////////////////////////////

public Action Command_Tag(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "%sYou must be in game to use this command!", g_sTag);
		return Plugin_Handled;
	}

	if(ga_iIsRestricted[client])
	{
		PrintToChat(client, "%s%sYou are currently restricted from changing your tags!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	if(!ga_iIsLoaded[client])
	{
		PrintToChat(client, "%s%sThis feature is disabled until your cookies have cached!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}

	Menu_MainTag(client);
	return Plugin_Handled;
}

public Action Command_BlockChat(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "%sYou must be in game to use this command!", g_sTag);
		return Plugin_Handled;
	}
	
	if(!g_cAllowBlockChat.BoolValue)
	{
		ReplyToCommand(client, "%s%sThis feature has been disabled by the server manager!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}

	if(ga_bChatBlocked[client])
	{
		ga_bChatBlocked[client] = false;
		ReplyToCommand(client, "%s%sYou have enabled chat blocker! You will no longer see chat from other players. To re-enable it, type !blockchat.", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
	}
	else
	{
		ga_bChatBlocked[client] = true;
		ReplyToCommand(client, "%s%sYou have disabled chat blocker! You can now see chat. To disable chat again, type !blockchat.", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
	}
	
	return Plugin_Handled;
}

public Action Command_SetText(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "%sYou must be in game to use this command!", g_sTag);
		return Plugin_Handled;
	}
	
	if(!HasFlags(client, g_sAccessFlag) && (ga_iSetTagAccess[client] != 1))
	{
		PrintToChat(client, "%s%sYou do not have access to this feature!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(ga_iIsRestricted[client])
	{
		PrintToChat(client, "%s%sYou are currently restricted from changing your tags!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(!ga_iSetTagAccess[client])
	{
		PrintToChat(client, "%s%sYour access to change your tag text has been denied by override by an external plugin!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(!ga_iIsLoaded[client])
	{
		PrintToChat(client, "%s%sThis feature is disabled until your cookies have cached!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(!g_cEnableTags.BoolValue)
	{
		PrintToChat(client, "%s%sThis feature has been disabled for everyone by the server manager!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}

	char sArg[MAXTAGSIZE];
	GetCmdArgString(sArg, sizeof(sArg));
	
	int iBlockedName = 0;
	
	for(int i = 0; i < g_aBlockedTags.Length; i++)
	{
		char sBuffer[75];
		g_aBlockedTags.GetString(i, sBuffer, sizeof(sBuffer));
		if(StrContains(sArg, sBuffer, false) != -1)
		{
			iBlockedName = 1;
		}
	}
	
	if(iBlockedName)
	{
		if(!HasFlags(client, g_sAdminFlag))
		{
			PrintToChat(client, "%s%sNice try! This tag is blocked from use.", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
			return Plugin_Handled;
		}
	}
	
	if(CheckTag(client))
	{
		return Plugin_Handled;
	}
	
	PrintToChat(client, "%s%sYour tag is now visible and is set to: %s", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED), sArg);
	strcopy(ga_sTag[client], sizeof(ga_sTag[]), sArg);
	strcopy(gaa_sCleanSetupText[client][0], sizeof(gaa_sCleanSetupText[][]), sArg);
	ga_iTagVisible[client] = 1;
	FormatColors(client);
	SendClientSetupToDB(client);
	
	return Plugin_Handled;
}

public Action Command_TagColor(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "%sYou must be in game to use this command!", g_sTag);
		return Plugin_Handled;
	}
	
	if(g_bCSGO)
	{
		ReplyToCommand(client, "%s\x03This command is not available for CS:GO!", g_sTag);
		return Plugin_Handled;
	}
	else if(g_bIns)
	{
		ReplyToCommand(client, "%s\x03This command is not available for Insurgency!", g_sTag);
		return Plugin_Handled;
	}

	if(iArgs != 1)
	{
		ReplyToCommand(client, "%s\x03Usage: sm_tagcolor <hex>", g_sTag);
		return Plugin_Handled;
	}
	
	if(!HasFlags(client, g_sAccessFlag) && (ga_iTagColorAccess[client] != 1))
	{
		PrintToChat(client, "%s\x03You do not have access to this feature!", g_sTag);
		return Plugin_Handled;
	}
	
	if(!ga_iTagColorAccess[client])
	{
		PrintToChat(client, "%s%sYour access to change your tag colors has been denied by override by an external plugin!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(ga_iIsRestricted[client])
	{
		PrintToChat(client, "%s\x03You are currently restricted from changing your tags!", g_sTag);
		return Plugin_Handled;
	}
	
	if(!ga_iIsLoaded[client])
	{
		PrintToChat(client, "%s\x03This feature is disabled until your cookies have cached!", g_sTag);
		return Plugin_Handled;
	}
	
	if(!g_cEnableTagColors.BoolValue || !g_cEnableTags.BoolValue)
	{
		PrintToChat(client, "%s\x03This feature has been disabled for everyone by the server manager!", g_sTag);
		return Plugin_Handled;
	}

	char sArg[32];
	GetCmdArgString(sArg, sizeof(sArg));
	ReplaceString(sArg, sizeof(sArg), "#", "", false);

	if(!IsValidHex(sArg))
	{
		ReplyToCommand(client, "%s\x03Invalid hex. Usage: sm_tagcolor <hex>", g_sTag);
		return Plugin_Handled;
	}
	
	
	if(CheckTag(client))
	{
		return Plugin_Handled;
	}

	PrintToChat(client, "\x01%s\x03Your tag color is now set to: \x07%s %s", g_sTag, sArg, sArg);
	strcopy(ga_sTagColor[client], sizeof(ga_sTagColor[]), sArg);
	strcopy(gaa_sCleanSetupText[client][1], sizeof(gaa_sCleanSetupText[][]), sArg);
	FormatColors(client);
	SendClientSetupToDB(client);

	return Plugin_Handled;
}

public Action Command_NameColor(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "%sYou must be in game to use this command!", g_sTag);
		return Plugin_Handled;
	}
	
	if(g_bCSGO)
	{
		ReplyToCommand(client, "%s\x03This command is not available for CS:GO!", g_sTag);
		return Plugin_Handled;
	}
	else if(g_bIns)
	{
		ReplyToCommand(client, "%s\x03This command is not available for Insurgency!", g_sTag);
		return Plugin_Handled;
	}

	if(iArgs != 1)
	{
		ReplyToCommand(client, "%s\x03Usage: sm_namecolor <hex>", g_sTag);
		return Plugin_Handled;
	}
	
	if(!HasFlags(client, g_sAccessFlag) && (ga_iNameColorAccess[client] != 1))
	{
		PrintToChat(client, "%s\x03You do not have access to this feature!", g_sTag);
		return Plugin_Handled;
	}
	
	if(!ga_iNameColorAccess[client])
	{
		PrintToChat(client, "%s%sYour access to change your name colors has been denied by override by an external plugin!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(ga_iIsRestricted[client])
	{
		PrintToChat(client, "%s\x03You are currently restricted from changing your tags!", g_sTag);
		return Plugin_Handled;
	}
	
	if(!ga_iIsLoaded[client])
	{
		PrintToChat(client, "%s\x03This feature is disabled until your cookies have cached!", g_sTag);
		return Plugin_Handled;
	}
	
	if(!g_cEnableNameColors.BoolValue)
	{
		PrintToChat(client, "%s\x03This feature has been disabled for everyone by the server manager!", g_sTag);
		return Plugin_Handled;
	}

	char sArg[32];
	GetCmdArgString(sArg, sizeof(sArg));
	ReplaceString(sArg, sizeof(sArg), "#", "", false);

	if(!IsValidHex(sArg))
	{
		ReplyToCommand(client, "%s\x03Invalid hex. Usage: sm_tagcolor <hex>", g_sTag);
		return Plugin_Handled;
	}
	
	if(CheckTag(client))
	{
		return Plugin_Handled;
	}

	PrintToChat(client, "\x01%s\x03Your name color is now set to: \x07%s %s", g_sTag, sArg, sArg);
	strcopy(ga_sNameColor[client], sizeof(ga_sNameColor[]), sArg);
	strcopy(gaa_sCleanSetupText[client][2], sizeof(gaa_sCleanSetupText[][]), sArg);
	FormatColors(client);
	SendClientSetupToDB(client);

	return Plugin_Handled;
}

public Action Command_ChatColor(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "%sYou must be in game to use this command!", g_sTag);
		return Plugin_Handled;
	}
	
	if(g_bCSGO)
	{
		ReplyToCommand(client, "%s\x03This command is not available for CS:GO!", g_sTag);
		return Plugin_Handled;
	}
	else if(g_bIns)
	{
		ReplyToCommand(client, "%s\x03This command is not available for Insurgency!", g_sTag);
		return Plugin_Handled;
	}

	if(iArgs != 1)
	{
		ReplyToCommand(client, "%s\x03Usage: sm_chatcolor <hex>", g_sTag);
		return Plugin_Handled;
	}
	
	if(!HasFlags(client, g_sAccessFlag) && (ga_iChatColorAccess[client] != 1))
	{
		PrintToChat(client, "%s\x03You do not have access to this feature!", g_sTag);
		return Plugin_Handled;
	}
	
	if(!ga_iChatColorAccess[client])
	{
		PrintToChat(client, "%s%sYour access to change your name colors has been denied by override by an external plugin!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	if(ga_iIsRestricted[client])
	{
		PrintToChat(client, "%s\x03You are currently restricted from changing your tags!", g_sTag);
		return Plugin_Handled;
	}
	
	if(!ga_iIsLoaded[client])
	{
		PrintToChat(client, "%s\x03This feature is disabled until your cookies have cached!", g_sTag);
		return Plugin_Handled;
	}
	
	if(!g_cEnableChatColors.BoolValue)
	{
		PrintToChat(client, "%s\x03This feature has been disabled for everyone by the server manager!", g_sTag);
		return Plugin_Handled;
	}

	char sArg[32];
	GetCmdArgString(sArg, sizeof(sArg));
	ReplaceString(sArg, sizeof(sArg), "#", "", false);

	if(!IsValidHex(sArg))
	{
		ReplyToCommand(client, "%s\x03Invalid hex. Usage: sm_tagcolor <hex>", g_sTag);
		return Plugin_Handled;
	}
	
	if(CheckTag(client))
	{
		return Plugin_Handled;
	}

	PrintToChat(client, "\x01%s\x03Your chat color is now set to: \x07%s %s", g_sTag, sArg, sArg);
	strcopy(ga_sChatColor[client], sizeof(ga_sChatColor[]), sArg);
	strcopy(gaa_sCleanSetupText[client][3], sizeof(gaa_sCleanSetupText[][]), ga_sChatColor[client]);
	FormatColors(client);
	SendClientSetupToDB(client);

	return Plugin_Handled;
}

public Action Command_CheckTag(int client, int iArgs)
{	
	if(iArgs != 1)
	{
		ReplyToCommand(client, "%s%sUsage: sm_checktag <target>", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return Plugin_Handled;
	}
	
	char sTarget[65], sTargetName[MAX_TARGET_LENGTH];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	int a_iTargets[MAXPLAYERS], iTargetCount;
	bool bTN_ML;
	if((iTargetCount = ProcessTargetString(sTarget, client, a_iTargets, MAXPLAYERS, COMMAND_FILTER_NO_IMMUNITY, sTargetName, sizeof(sTargetName), bTN_ML)) <= 0)
	{
		ReplyToCommand(client, "Not found or invalid parameter.");
		return Plugin_Handled;
	}
	
	for(int i = 0; i < iTargetCount; i++)
	{
		int target = a_iTargets[i];
		if(IsValidClient(target))
		{
			char sHiddenTag[10], sRestricted[24], sSetTag[10], sTagColor[10], sNameColor[10], sChatColor[10];
			if(ga_iTagVisible[target])
			{
				sHiddenTag = "Visible";
			}
			else
			{
				sHiddenTag = "Hidden";
			}
			
			if(ga_iIsRestricted[target])
			{
				sRestricted = "Restricted";
			}
			else
			{
				sRestricted = "Not Restricted";
			}
			
			if(!ga_iSetTagAccess[target])
			{
				sSetTag = "Denied";
			}
			else if(ga_iSetTagAccess[target] == 1)
			{
				sSetTag = "Granted";
			}
			else
			{
				sSetTag = "Default";
			}
			
			if(!ga_iTagColorAccess[target])
			{
				sTagColor = "Denied";
			}
			else if(ga_iTagColorAccess[target] == 1)
			{
				sTagColor = "Granted";
			}
			else
			{
				sTagColor = "Default";
			}
			
			if(!ga_iNameColorAccess[target])
			{
				sNameColor = "Denied";
			}
			else if(ga_iNameColorAccess[target] == 1)
			{
				sNameColor = "Granted";
			}
			else
			{
				sNameColor = "Default";
			}
			
			if(!ga_iChatColorAccess[target])
			{
				sChatColor = "Denied";
			}
			else if(ga_iChatColorAccess[target] == 1)
			{
				sChatColor = "Granted";
			}
			else
			{
				sChatColor = "Default";
			}
			
			if(IsValidClient(client))
			{
				PrintToConsole(client, "-------------------------- PLAYER TAG INFO --------------------------");
				PrintToConsole(client, "Player: %L, Status: \"%s\", Tag status: \"%s\"", target, sRestricted, sHiddenTag);
				PrintToConsole(client, "Tag Color: \"%s\", Name Color: \"%s\", Chat Color: \"%s\"", gaa_sCleanSetupText[target][1], gaa_sCleanSetupText[target][2], gaa_sCleanSetupText[target][3]);
				PrintToConsole(client, "Access overrides - Set Tag: %s, Tag color: %s", sSetTag, sTagColor);
				PrintToConsole(client, "Access overrides - Name color: %s, Chat color: %s", sNameColor, sChatColor);
			}
			else
			{
				ReplyToCommand(client, "-------------------------- PLAYER TAG INFO --------------------------");
				ReplyToCommand(client, "Player: %L, Status: \"%s\", Tag status: \"%s\"", target, sRestricted, sHiddenTag);
				ReplyToCommand(client, "Tag Color: \"%s\", Name Color: \"%s\", Chat Color: \"%s\"", gaa_sCleanSetupText[target][1], gaa_sCleanSetupText[target][2], gaa_sCleanSetupText[target][3]);
				ReplyToCommand(client, "Access overrides - Set Tag: %s, Tag color: %s", sSetTag, sTagColor);
				ReplyToCommand(client, "Access overrides - Name color: %s, Chat color: %s", sNameColor, sChatColor);
			}
		}
	}

	if(IsValidClient(client))
	{
		PrintToChat(client, "%s%sCheck console for output!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
	}

	return Plugin_Handled;
}

int SearchForPlayer(const char[] sTarget)
{
	if(sTarget[0] == '#')
	{
		bool bUserID = true;
		for(int i = 1; i < strlen(sTarget); i++)
		{
			if(!IsCharNumeric(sTarget[i]))
			{
				bUserID = false;
				break;
			}
		}
		
		if(bUserID)
		{
			return -1;
		}
	}
	
	char sName[MAX_NAME_LENGTH];
	int iNumberFound = 0;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			GetClientName(i, sName, sizeof(sName));
			
			if(StrContains(sName, sTarget, false) != -1)
			{
				iNumberFound++;
			}
		}
	}
	return iNumberFound;
}

//check if name/tag combo should be allowed - this section can be used to define setups that are not allowed
bool CheckTag(int client)
{
	//check if imitating console
	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));
	TrimString(sName);
	if(StrEqual(sName, g_sConsoleName, false))
	{
		RemoveSetup(client);
		PrintToChat(client, "%s\x07Your chat tags setup has been removed due to mimicking CONSOLE (change your name)!", g_sTag);
		return true;
	}
	
	return false;
}

///////////////////////////////////////////////////////////////////
///////////////////////////// Cookies /////////////////////////////
///////////////////////////////////////////////////////////////////

void LoadClientData(int client)
{
	if(!IsValidClient(client))
	{
		return;
	}
	
	if(StrContains(gaa_sSteamID[client][0], "STEAM_", true) == -1) //invalid
	{
		CreateTimer(2.0, RefreshSteamID, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		return;
	}
	
	if(g_oDatabase != null)
	{
		GetClientName(client, ga_sEscapedName[client], sizeof(ga_sEscapedName[]));
		strcopy(ga_sName[client], sizeof(ga_sName[]), ga_sEscapedName[client]);
		CleanStringForSQL(ga_sEscapedName[client], sizeof(ga_sEscapedName[]));
		
		char sQuery[300];
		Format(sQuery, sizeof(sQuery), "SELECT `visible`, `restricted`, `tagtext`, `tagcolor`, `namecolor`, `chatcolor`, `ovrd_ttext`, `ovrd_tcolor`, `ovrd_ncolor`, `ovrd_ccolor` FROM `%s` WHERE (`steamid` = '%s') ORDER BY `id` LIMIT 1", g_sDBTableName, gaa_sSteamID[client][0]);
		g_oDatabase.Query(SQLCallback_LoadPlayer, sQuery, GetClientUserId(client));
	}
	else
	{
		CreateTimer(5.0, RepeatCheck, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void SQLCallback_LoadPlayer(Database oDB, DBResultSet oResults, const char[] sError, any iUserID)
{
	if(oResults == INVALID_HANDLE)
	{
		SetFailState("Player load callback error: %s", sError);
	}
	
	int client = GetClientOfUserId(iUserID);
	if(!IsValidClient(client))
	{
		return;
	}
	else 
	{
		if(oResults.RowCount == 1)
		{
			/*	TABLE SETUP:
			`id` int(20) PRIMARY KEY
			`steamid` VARCHAR(32) NOT NULL
			`tagtext` VARCHAR(32) NOT NULL
			`visible` INT(2) NOT NULL
			`restricted` INT(2) NOT NULL
			`tagcolor` VARCHAR(10) NOT NULL
			`namecolor` VARCHAR(10) NOT NULL
			`chatcolor` VARCHAR(10) NOT NULL
			`ovrd_ttext` INT(2) NOT NULL
			`ovrd_tcolor` INT(2) NOT NULL
			`ovrd_ncolor` INT(2) NOT NULL
			`ovrd_ccolor` INT(2) NOT NULL
			QUERY ORDER:
			`visible`, `restricted`, `tagtext`, `tagcolor`, `namecolor`, `chatcolor`, `ovrd_ttext`, `ovrd_tcolor`, `ovrd_ncolor`, `ovrd_ccolor`
			*/
			char sBuffer[128];
			oResults.FetchRow();
			IntToString(oResults.FetchInt(0), sBuffer, sizeof(sBuffer));
			if(StrEqual(sBuffer, "", false) || (StrEqual(sBuffer, "0", false) && !ga_iTagVisible[client]))	//if they dont have access and the DB has it saved as disabled
			{
				ga_iTagVisible[client] = 0;
			}
			else
			{
				ga_iTagVisible[client] = StringToInt(sBuffer);
			}
			
			IntToString(oResults.FetchInt(1), sBuffer, sizeof(sBuffer));
			if(StrEqual(sBuffer, "", false))
			{
				ga_iIsRestricted[client] = 0;
			}
			else
			{
				ga_iIsRestricted[client] = StringToInt(sBuffer);
			}
			oResults.FetchString(2, ga_sTag[client], sizeof(ga_sTag[]));
			oResults.FetchString(3, ga_sTagColor[client], sizeof(ga_sTagColor[]));
			oResults.FetchString(4, ga_sNameColor[client], sizeof(ga_sNameColor[]));
			oResults.FetchString(5, ga_sChatColor[client], sizeof(ga_sChatColor[]));
			gaa_iAdminOvrd[client][0] = oResults.FetchInt(6);
			gaa_iAdminOvrd[client][1] = oResults.FetchInt(7);
			gaa_iAdminOvrd[client][2] = oResults.FetchInt(8);
			gaa_iAdminOvrd[client][3] = oResults.FetchInt(9);
			
			CheckTag(client); //this is put before group tags so that group ones can bypass this if the manager wants it (e.g. have root admins be tagged "CONSOLE"?)
			//load group setups if they dont have access per defined access flags.
			if(!HasFlags(client, g_sAccessFlag))
			{
				CheckForGroups(client);
			}
			else if(!ga_iTagVisible[client]) //has flags, but "disabled" (if they dont want a tag, they can set the text to ""). 
			{ //This isnt combined with the above check since they might not have the flag, but their cookie says "enabled". That would block the groups for such a situation.
				CheckForGroups(client);
			}

			FormatColors(client);
			ga_iIsLoaded[client] = 1;
			Call_StartForward(g_hClientLoadFwd);
			Call_PushCell(client);
			Call_Finish();
		}
		else if(!oResults.RowCount)
		{
			SendClientSetupToDB(client, false, true);
			//load group setups if they dont have access per defined access flags.
			if(!HasFlags(client, g_sAccessFlag))
			{
				CheckForGroups(client);
			}
			else if(!ga_iTagVisible[client]) //has flags, but "disabled" (if they dont want a tag, they can set the text to ""). 
			{ //This isnt combined with the above check since they might not have the flag, but their cookie says "enabled". That would block the groups for such a situation.
				CheckForGroups(client);
			}

			FormatColors(client);
			ga_iIsLoaded[client] = 1;
			Call_StartForward(g_hClientLoadFwd);
			Call_PushCell(client);
			Call_Finish();
		}
		else if(g_oDatabase == null)
		{
			CreateTimer(5.0, RepeatCheck, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

void SendClientSetupToDB(int client, bool bBlockAccess = false, bool bDefault = false)
{
	if(!IsValidClient(client))
	{
		return;
	}
	
	if(StrContains(gaa_sSteamID[client][0], "STEAM_", true) == -1) //invalid
	{
		CreateTimer(2.0, RefreshSteamID_SendData, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		return;
	}
	
	if(g_oDatabase != null)
	{
		/*	TABLE SETUP:
		`id` int(20) PRIMARY KEY
		`steamid` VARCHAR(32) NOT NULL
		`tagtext` VARCHAR(32) NOT NULL
		`visible` INT(2) NOT NULL
		`restricted` INT(2) NOT NULL
		`tagcolor` VARCHAR(10) NOT NULL
		`namecolor` VARCHAR(10) NOT NULL
		`chatcolor` VARCHAR(10) NOT NULL
		`ovrd_ttext` INT(2) NOT NULL
		`ovrd_tcolor` INT(2) NOT NULL
		`ovrd_ncolor` INT(2) NOT NULL
		`ovrd_ccolor` INT(2) NOT NULL
		*/
		
		char sQuery[750], sTagText[MAX_NAME_LENGTH * 2 + 1], sTagColor[MAX_NAME_LENGTH * 2 + 1], sNameColor[MAX_NAME_LENGTH * 2 + 1], sChatColor[MAX_NAME_LENGTH * 2 + 1];
		if(bDefault)
		{
			Format(sQuery, sizeof(sQuery), "INSERT INTO `%s` (`steamid`, `tagtext`, `visible`, `restricted`, `tagcolor`, `namecolor`, `chatcolor`, `ovrd_ttext`, `ovrd_tcolor`, `ovrd_ncolor`, `ovrd_ccolor`) VALUES('%s', '', 0, 0, '', '', '', 0, 0, 0, 0)", g_sDBTableName, gaa_sSteamID[client][0]);
			g_oDatabase.Query(SQLCallback_Void, sQuery, 2);
		}
		else
		{
			g_oDatabase.Escape(ga_sTag[client], sTagText, sizeof(sTagText));
			g_oDatabase.Escape(gaa_sCleanSetupText[client][1], sTagColor, sizeof(sTagColor));
			g_oDatabase.Escape(gaa_sCleanSetupText[client][2], sNameColor, sizeof(sNameColor));
			g_oDatabase.Escape(gaa_sCleanSetupText[client][3], sChatColor, sizeof(sChatColor));
			Format(sQuery, sizeof(sQuery), "UPDATE `%s` SET `tagtext`='%s', `visible`=%i, `restricted`=%i, `tagcolor`='%s', `namecolor`='%s', `chatcolor`='%s', `ovrd_ttext`=%i, `ovrd_tcolor`=%i, `ovrd_ncolor`=%i, `ovrd_ccolor`=%i WHERE `steamid` = '%s'", g_sDBTableName, sTagText, ((ga_iTagVisible[client] && !bBlockAccess) ? 1 : 0), ga_iIsRestricted[client], sTagColor, sNameColor, sChatColor, gaa_iAdminOvrd[client][0], gaa_iAdminOvrd[client][1], gaa_iAdminOvrd[client][2], gaa_iAdminOvrd[client][3], gaa_sSteamID[client][0]);
			g_oDatabase.Query(SQLCallback_Void, sQuery, 3);
		}
	}
	else
	{
		CreateTimer(5.0, TimerCB_RetrySendData, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

//////////////////////////////////////////////////////////////////
///////////////////////////// Setups /////////////////////////////
//////////////////////////////////////////////////////////////////

void FormatColors(int client)
{
	ConvertColor(ga_sExtTagColor[client], sizeof(ga_sExtTagColor[]));
	ConvertColor(ga_sTagColor[client], sizeof(ga_sTagColor[])/*, client*/);
	ConvertColor(ga_sNameColor[client], sizeof(ga_sNameColor[])/*, client*/);
	ConvertColor(ga_sChatColor[client], sizeof(ga_sChatColor[])/*, client*/);
	
	if(!gaa_iAdminOvrd[client][0] && (!g_cEnableTags.BoolValue || (!HasFlags(client, g_sAccessFlag) && (ga_iSetTagAccess[client] != 1) && !ga_iGroupMatch[client]) || (ga_iSetTagAccess[client] == 0) || !ga_iTagVisible[client])) //remove tag if no access or custom configs disabled by server manager or disabled by user
	{
		Format(ga_sTag[client], sizeof(ga_sTag[]), "");
		gaa_sCleanSetupText[client][0] = "";
	}
	
	if(!gaa_iAdminOvrd[client][1] && (!g_cEnableTagColors.BoolValue || (!HasFlags(client, g_sAccessFlag) && (ga_iTagColorAccess[client] != 1) && !ga_iGroupMatch[client]) || (ga_iTagColorAccess[client] == 0) || !ga_iTagVisible[client])) //remove tag color if no access or custom tag colors disabled by server manager or disabled by user
	{
		Format(ga_sTagColor[client], sizeof(ga_sTagColor[]), "");
		gaa_sCleanSetupText[client][1] = "";
	}
	
	if(!gaa_iAdminOvrd[client][2] && (!g_cEnableNameColors.BoolValue || (!HasFlags(client, g_sAccessFlag) && (ga_iNameColorAccess[client] != 1) && !ga_iGroupMatch[client]) || (ga_iNameColorAccess[client] == 0) || !ga_iTagVisible[client])) //remove name color if no access or custom name colors disabled by server manager or disabled by user
	{
		Format(ga_sNameColor[client], sizeof(ga_sNameColor[]), "");
		gaa_sCleanSetupText[client][2] = "";
	}
	
	if(!gaa_iAdminOvrd[client][3] && (!g_cEnableChatColors.BoolValue || (!HasFlags(client, g_sAccessFlag) && (ga_iChatColorAccess[client] != 1) && !ga_iGroupMatch[client]) || (ga_iChatColorAccess[client] == 0) || !ga_iTagVisible[client])) //remove chat color if no access or custom chat colors disabled by server manager or disabled by user
	{
		Format(ga_sChatColor[client], sizeof(ga_sChatColor[]), "");
		gaa_sCleanSetupText[client][3] = "";
	}
}

void ConvertColor(char[] sString, int iSize/*, client = 0*/)
{
	if(StrEqual(sString, "", false))
	{
		return;
	}
	
	if(g_bCSGO)
	{
		bool bBuffer = true;	//checking if numeric only
		for(int i = 1; i < strlen(sString); i++)
		{
			if(!IsCharNumeric(sString[i]))
			{
				bBuffer = false;
				break;
			}
		}
		
		if(!bBuffer)	//convert text into numbers
		{
			char sBuffer[32];
			for(int i = 0; i < g_aColorName.Length; i++)
			{
				g_aColorName.GetString(i, sBuffer, sizeof(sBuffer));
				if(StrEqual(sBuffer, sString, false))
				{
					g_aColorCode.GetString(i, sBuffer, sizeof(sBuffer));
					strcopy(sString, iSize, sBuffer);
					bBuffer = true;
					break;
				}
			}
		}
		
		if(!bBuffer)
		{
			return;
		}
		
		if((strlen(sString) <= 3) && !StrEqual(sString, "", false))
		{
			switch(StringToInt(sString))
			{
				case 1:
				{
					Format(sString, iSize, "\x01");
				}
				case 2:
				{
					Format(sString, iSize, "\x02");
				}
				case 3:
				{
					Format(sString, iSize, "\x03");
				}
				case 4:
				{
					Format(sString, iSize, "\x04");
				}
				case 5:
				{
					Format(sString, iSize, "\x05");
				}
				case 6:
				{
					Format(sString, iSize, "\x06");
				}
				case 7:
				{
					Format(sString, iSize, "\x07");
				}
				case 8:
				{
					Format(sString, iSize, "\x08");
				}
				case 9:
				{
					Format(sString, iSize, "\x09");
				}
				case 10:
				{
					Format(sString, iSize, "\x0A");
				}
				case 11:
				{
					Format(sString, iSize, "\x0B");
				}
				case 12:
				{
					Format(sString, iSize, "\x0C");
				}
				case 13:
				{
					Format(sString, iSize, "\x0D");
				}
				case 14:
				{
					Format(sString, iSize, "\x0E");
				}
				case 15:
				{
					Format(sString, iSize, "\x0F");
				}
				case 16: //not recommended - messes with formatting
				{
					Format(sString, iSize, "\x10");
				}
			}
		}
	}
	else if(g_bIns)
	{
		bool bBuffer = true;	//checking if numeric only
		for(int i = 1; i < strlen(sString); i++)
		{
			if(!IsCharNumeric(sString[i]))
			{
				bBuffer = false;
				break;
			}
		}
		
		if(!bBuffer)	//convert text into numbers
		{
			char sBuffer[32];
			for(int i = 0; i < g_aColorName.Length; i++)
			{
				g_aColorName.GetString(i, sBuffer, sizeof(sBuffer));
				if(StrEqual(sBuffer, sString, false))
				{
					g_aColorCode.GetString(i, sBuffer, sizeof(sBuffer));
					strcopy(sString, iSize, sBuffer);
					bBuffer = true;
					break;
				}
			}
		}
		
		if(!bBuffer)
		{
			return;
		}
		if((strlen(sString) <= 3) && !StrEqual(sString, "", false))
		{
			switch(StringToInt(sString))
			{
				case 1:	//white
				{
					Format(sString, iSize, "\x01");
				}
				case 2:	//team
				{
					Format(sString, iSize, "\x03");
				}
				case 3:	//lime
				{
					Format(sString, iSize, "\x04");
				}
				case 4:	//light green
				{
					Format(sString, iSize, "\x05");
				}
				case 5:	//olive
				{
					Format(sString, iSize, "\x06");
				}
				case 6:	//banana yellow
				{
					Format(sString, iSize, "\x11");
				}
				case 7:	//Dark yellow
				{
					Format(sString, iSize, "\x12");
				}
				/*case 8:	//light blue
				{
					Format(sString, iSize, "\x03");
					if(IsValidClient(client))
					{
						ga_iEntOverride[client] = 1;
					}
				}
				case 9:	//attempt
				{
					Format(sString, iSize, "{redblue}");
					//Format(sString, iSize, "\x03");
					if(IsValidClient(client))
					{
						ga_iEntOverride[client] = 3;
					}
				}*/
			}
		}
	}
	else
	{
		if(strlen(sString) == 6)
		{
			if(IsValidHex(sString))
			{
				Format(sString, iSize, "\x07%s", sString);
			}
			else
			{
				char sBuffer[32];
				for(int i = 0; i < g_aColorName.Length; i++)
				{
					g_aColorName.GetString(i, sBuffer, sizeof(sBuffer));
					if(StrEqual(sBuffer, sString, false))
					{
						g_aColorCode.GetString(i, sBuffer, sizeof(sBuffer));
						Format(sString, iSize, "\x07%s", sBuffer);
						break;
					}
				}
			}
		}
	}
}

void CheckForGroups(int client)
{	
	KeyValues oKeyValues = new KeyValues("Setups");
	
	if(!FileExists(g_sGroupPath))
	{
		SetFailState("Configuration file %s not found!", g_sGroupPath);
		return;
	}

	if(!oKeyValues.ImportFromFile(g_sGroupPath))
	{
		SetFailState("Improper structure for configuration file %s!", g_sGroupPath);
		return;
	}
	
	if(oKeyValues.GotoFirstSubKey(true))
	{
		do
		{
			char sFlags[30], sSectionName[100];
			oKeyValues.GetSectionName(sSectionName, sizeof(sSectionName));
			oKeyValues.GetString("flags", sFlags, sizeof(sFlags), "public");
			
			if(!StrEqual(sSectionName, gaa_sSteamID[client][0], false) && !StrEqual(sSectionName, gaa_sSteamID[client][1], false) && !StrEqual(sSectionName, gaa_sSteamID[client][2], false) && !StrEqual(sSectionName, gaa_sSteamID[client][3], false))
			{
				if(HasOnlyNumbers(sSectionName) || (StrContains(sSectionName, ":", false) != -1))	//if steam ID //if it's a steam ID, and not theirs, skip
				{
					continue;
				}
				
				if(StrContains(sSectionName, "TEAM_", false) == 0)	//if the string STARTS with TEAM_ , check if team matches - Note: need to check if at start, else "STEAM_" would trigger it
				{
					char sTeam[32];
					strcopy(sTeam, sizeof(sTeam), sSectionName);
					ReplaceString(sTeam, sizeof(sTeam), "TEAM_", "", false);
					if(IsNumeric(sTeam))
					{
						int iTeam = StringToInt(sTeam);
						if(GetClientTeam(client) != iTeam)
						{
							continue;
						}
					}
				}
				
				if(!StrEqual(sFlags, "public", false) || !StrEqual(sFlags, "", false)) //not a steam ID or team setup, so check if public
				{
					if(!HasFlags(client, sFlags)) //not public - check flags required. This one is on a separate line in case HasFlags might error while checking "public" (since there is no 'u' flag)
					{
						continue;
					}
				}
			}
			//match found - get setup
			oKeyValues.GetString("tagstring", ga_sTag[client], sizeof(ga_sTag[]), "");
			oKeyValues.GetString("tagcolor", ga_sTagColor[client], sizeof(ga_sTagColor[]), "");
			oKeyValues.GetString("namecolor", ga_sNameColor[client], sizeof(ga_sNameColor[]), "");
			oKeyValues.GetString("chatcolor", ga_sChatColor[client], sizeof(ga_sChatColor[]), "");
			strcopy(gaa_sCleanSetupText[client][0], sizeof(gaa_sCleanSetupText[][]), ga_sTag[client]);
			strcopy(gaa_sCleanSetupText[client][1], sizeof(gaa_sCleanSetupText[][]), ga_sTagColor[client]);
			strcopy(gaa_sCleanSetupText[client][2], sizeof(gaa_sCleanSetupText[][]), ga_sNameColor[client]);
			strcopy(gaa_sCleanSetupText[client][3], sizeof(gaa_sCleanSetupText[][]), ga_sChatColor[client]);
			ga_iGroupMatch[client] = 1;
			ga_iTagVisible[client] = 2;
			break;	//break loop to avoid excess processing if a matching setup is found
		}
		while(oKeyValues.GotoNextKey(false));
		oKeyValues.GoBack(); //go back one level (to main level) to leave for other functions using kv tree - may not be needed here since we re-parse each time players connect, but is good practice.
	}
	else
	{
		//SetFailState("Can't find first subkey in configuration file %s!", g_sGroupPath);	//commented out to allow zero setups
		PrintToServer("Can't find first subkey in configuration file %s!", g_sGroupPath);
	}
	delete oKeyValues;
}

bool HasOnlyNumbers(char[] sString)
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

bool IsNumeric(char[] sString)
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

bool IsValidClient(int client, bool bAllowBots = false, bool bAllowDead = true)
{
	if(!(1 <= client <= MaxClients) || !IsClientInGame(client) || (IsFakeClient(client) && !bAllowBots) || IsClientSourceTV(client) || IsClientReplay(client) || (!IsPlayerAlive(client) && !bAllowDead))
	{
		return false;
	}
	return true;
}

bool IsValidHex(const char[] sHex)
{
	if(g_oRegexHex.Match(sHex))
	{
		return true;
	}
	return false;
}

/////////////////////////////////////////////////////////////////////////////
///////////////////////////// Client Prefs Menu /////////////////////////////
/////////////////////////////////////////////////////////////////////////////

public void Menu_ClientPrefs(int client, CookieMenuAction action, any info, char[] sBuffer, int iMaxLen)
{
	if(action == CookieMenuAction_SelectOption)
	{
		if(ga_iIsRestricted[client])
		{
			PrintToChat(client, "%s%sYou are currently restricted from changing your tags!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
			return;
		}
		else
		{
			Menu_MainTag(client);
		}
	}
}

int Menu_MainTag(int client)
{
	Panel hPanel = CreatePanel();
	hPanel.SetTitle("TOGs Chat Tags");
	if((HasFlags(client, g_sAccessFlag) || (ga_iSetTagAccess[client] == 1)) && ga_iSetTagAccess[client] && (g_cEnableTags.BoolValue || (ga_iSetTagAccess[client] == 1)))
	{
		if(ga_iTagVisible[client])
		{
			hPanel.DrawItem("Disable Tag");
		}
		else
		{
			hPanel.DrawItem("Enable Tag");
		}
	}
	else
	{
		hPanel.DrawItem("Enable Tag", ITEMDRAW_DISABLED);
	}
	
	if((HasFlags(client, g_sAccessFlag) || (ga_iTagColorAccess[client] == 1)) && ga_iTagColorAccess[client] && (g_cEnableTagColors.BoolValue || (ga_iTagColorAccess[client] == 1)))
	{
		hPanel.DrawItem("Tag Colors");
	}
	else
	{
		hPanel.DrawItem("Tag Colors", ITEMDRAW_DISABLED);
	}

	//name colors menu
	if((HasFlags(client, g_sAccessFlag) || (ga_iNameColorAccess[client] == 1)) && ga_iNameColorAccess[client] && (g_cEnableNameColors.BoolValue || (ga_iNameColorAccess[client] == 1)))
	{
		hPanel.DrawItem("Name Colors");
	}
	else
	{
		hPanel.DrawItem("Name Colors", ITEMDRAW_DISABLED);
	}
	//chat colors menu
	if((HasFlags(client, g_sAccessFlag) || (ga_iChatColorAccess[client] == 1)) && ga_iChatColorAccess[client] && (g_cEnableChatColors.BoolValue || (ga_iChatColorAccess[client] == 1)))
	{
		hPanel.DrawItem("Chat Colors");
	}
	else
	{
		hPanel.DrawItem("Chat Colors", ITEMDRAW_DISABLED);
	}
		
	hPanel.DrawItem("Check Setup of Player");
	hPanel.DrawItem("------------------------", ITEMDRAW_RAWLINE);
	hPanel.DrawItem("Chat command to change tag:", ITEMDRAW_RAWLINE);
	hPanel.DrawItem("!settag Text You Want", ITEMDRAW_RAWLINE);
	char sBuffer[30];
	Format(sBuffer, sizeof(sBuffer), "(%i Characters Max)", MAXTAGSIZE);
	hPanel.DrawItem(sBuffer, ITEMDRAW_RAWLINE);
	hPanel.DrawItem("", ITEMDRAW_SPACER);
	hPanel.DrawItem("Back", ITEMDRAW_CONTROL);
	hPanel.DrawItem("", ITEMDRAW_SPACER);
	hPanel.DrawItem("Exit", ITEMDRAW_CONTROL);
	
	hPanel.Send(client, PanelHandler_MenuMainTag, MENU_TIME_FOREVER);
	delete hPanel;

	return 2;
}

public int PanelHandler_MenuMainTag(Menu oMenu, MenuAction action, int client, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			EmitSoundToClient(client, "buttons/combine_button7.wav");
			delete oMenu;
		}
		case MenuAction_Cancel: 
		{
			if(param2 == MenuCancel_ExitBack)
			{
				ShowCookieMenu(client);
			}
		}
		case MenuAction_Select:
		{
			switch(param2)
			{
				case 1:
				{
					if(HasFlags(client, g_sAccessFlag) || (ga_iSetTagAccess[client] == 1) || (ga_iTagColorAccess[client] == 1))
					{
						EmitSoundToClient(client, "buttons/button14.wav");
						if(!ga_iTagVisible[client])
						{
							ga_iTagVisible[client] = 1;
							PrintToChat(client, "%s%sYour tag is now enabled!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
							RecheckSetup(client, true);
						}
						else
						{
							ga_iTagVisible[client] = 0;
							PrintToChat(client, "%s%sYour tag is now disabled!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
							RecheckSetup(client, true);
						}
						Menu_MainTag(client);
					}
					else
					{
						EmitSoundToClient(client, "buttons/button14.wav");
						PrintToChat(client, "%s%sYou do not have access to this feature!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
						Menu_MainTag(client);
					}
				}
				case 2:
				{
					if(HasFlags(client, g_sAccessFlag) || (ga_iTagColorAccess[client] == 1))
					{
						EmitSoundToClient(client, "buttons/button14.wav");
						Menu_TagColor(client);
					}
					else
					{
						EmitSoundToClient(client, "buttons/button14.wav");
						PrintToChat(client, "%s%sYou do not have access to this feature!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
						Menu_MainTag(client);
					}
				}
				case 3:
				{
					if(HasFlags(client, g_sAccessFlag) || (ga_iNameColorAccess[client] == 1))
					{
						EmitSoundToClient(client, "buttons/button14.wav");
						Menu_NameColor(client);
					}
					else
					{
						EmitSoundToClient(client, "buttons/button14.wav");
						PrintToChat(client, "%s%sYou do not have access to this feature!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
						Menu_MainTag(client);
					}
				}
				case 4:
				{
					if(HasFlags(client, g_sAccessFlag) || (ga_iChatColorAccess[client] == 1))
					{
						EmitSoundToClient(client, "buttons/button14.wav");
						Menu_ChatColor(client);
					}
					else
					{
						EmitSoundToClient(client, "buttons/button14.wav");
						PrintToChat(client, "%s%sYou do not have access to this feature!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
						Menu_MainTag(client);
					}
				}
				case 5:
				{
					EmitSoundToClient(client, "buttons/button14.wav");
					Displaymenu_Player(client, "sm_checktag", "Check Tag Setup for:");
				}
				case 7:
				{
					EmitSoundToClient(client, "buttons/button14.wav");
					ShowCookieMenu(client);
				}
				case 9:
				{
					EmitSoundToClient(client, "buttons/combine_button7.wav");
				}
			}
		}
	}
	
	return;
}

void RecheckSetup(int client, bool bBlockAccess = false)
{
	CheckTag(client); //this is put before group tags so that group ones can bypass this if the manager wants it (e.g. have root admins be tagged "CONSOLE"?)
	
	//load group setups if they dont have access per defined access flags.
	if(!(HasFlags(client, g_sAccessFlag) || StrEqual(g_sAccessFlag, "", false)))
	{
		CheckForGroups(client);
	}
	else if(ga_iTagVisible[client] != 1) //has flags, but "disabled" (if they dont want a tag, they can set the text to ""). 
	{ //This isnt combined with the above check since they might not have the flag, but their cookie says "enabled". That would block the groups for such a situation.
		CheckForGroups(client);
	}

	FormatColors(client);
	SendClientSetupToDB(client, bBlockAccess);

	Call_StartForward(g_hClientReloadFwd);
	Call_PushCell(client);
	Call_Finish();
}

public void Menu_TagColor(int client)
{
	if(ga_iIsRestricted[client])
	{
		PrintToChat(client, "%s%sYou are currently restricted from changing your tags!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return;
	}

	if(!ga_iChatColorAccess[client])
	{
		PrintToChat(client, "%s%sYour access to change chat colors has been denied by override by an external plugin!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return;
	}
	
	if(!ga_iTagColorAccess[client])
	{
		PrintToChat(client, "%s%sYour access to change tag colors has been denied by override by an external plugin!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return;
	}
	
	if(!g_cEnableTagColors.BoolValue || !g_cEnableTags.BoolValue)
	{
		PrintToChat(client, "%s%sThis feature has been disabled for everyone by the server manager!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return;
	}
	
	Menu oMenu = new Menu(MenuCallback_TagColor);
	oMenu.SetTitle("Tag Color");
	oMenu.ExitBackButton = true;
	oMenu.Pagination = 6;

	oMenu.AddItem("Reset", "Reset");
	if(!g_bCSGO && !g_bIns)
	{
		oMenu.AddItem("SetManually", "Define Your Own Color");
	}

	char sColorIndex[5], sColorName[32];
	for(int i = 0; i < g_aColorName.Length; i++)
	{
		IntToString(i, sColorIndex, sizeof(sColorIndex));
		g_aColorName.GetString(i, sColorName, sizeof(sColorName));
		oMenu.AddItem(sColorIndex, sColorName);
	}

	oMenu.Display(client, MENU_TIME_FOREVER);
}

public int MenuCallback_TagColor(Menu oMenu, MenuAction action, int client, int param2)
{
	if(action == MenuAction_End)
	{
		delete oMenu;
		return;
	}

	if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_MainTag(client);
		return;
	}

	if(action == MenuAction_Select)
	{
		char sBuffer[32];
		oMenu.GetItem(param2, sBuffer, sizeof(sBuffer));

		if(StrEqual(sBuffer, "Reset"))
		{
			PrintToChat(client, "%s%sYour tag color is now reset to default.", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
			ga_sTagColor[client] = "";
			gaa_sCleanSetupText[client][1] = "";
			FormatColors(client);
			SendClientSetupToDB(client);
		}
		else if(StrEqual(sBuffer, "SetManually"))
		{
			PrintToChat(client, "%s\x03To define your own tag color, type !tagcolor <hexcode> (e.g. !tagcolor FFFFFF).", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		}
		else
		{
			int iColorIndex = StringToInt(sBuffer);
			g_aColorCode.GetString(iColorIndex, sBuffer, sizeof(sBuffer));
			strcopy(ga_sTagColor[client], sizeof(ga_sTagColor[]), sBuffer);
			strcopy(gaa_sCleanSetupText[client][1], sizeof(gaa_sCleanSetupText[][]), ga_sTagColor[client]);
			FormatColors(client);
			g_aColorName.GetString(iColorIndex, sBuffer, sizeof(sBuffer));
			PrintToChat(client, "\x01%sYour tag color is now set to: %s%s", g_sTag, ga_sTagColor[client], sBuffer);
			SendClientSetupToDB(client);
		}

		Menu_MainTag(client);
	}
}

public void Menu_NameColor(int client)
{
	if(ga_iIsRestricted[client])
	{
		PrintToChat(client, "%s%sYou are currently restricted from changing your tags!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return;
	}
	
	if(!ga_iNameColorAccess[client])
	{
		PrintToChat(client, "%s%sYour access to change name colors has been denied by override by an external plugin!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return;
	}
	
	if(!g_cEnableNameColors.BoolValue)
	{
		PrintToChat(client, "%s%sThis feature has been disabled for everyone by the server manager!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return;
	}

	Menu oMenu = new Menu(MenuCallback_NameColor);
	oMenu.SetTitle("Name Color");
	oMenu.ExitBackButton = true;
	oMenu.Pagination = 6;
	
	oMenu.AddItem("Reset", "Reset");
	if(!g_bCSGO && !g_bIns)
	{
		oMenu.AddItem("SetManually", "Define Your Own Color");
	}

	char sColorIndex[5], sColorName[32];
	for(int i = 0; i < g_aColorName.Length; i++)
	{
		IntToString(i, sColorIndex, sizeof(sColorIndex));
		g_aColorName.GetString(i, sColorName, sizeof(sColorName));
		oMenu.AddItem(sColorIndex, sColorName);
	}

	oMenu.Display(client, MENU_TIME_FOREVER);
}

public int MenuCallback_NameColor(Menu oMenu, MenuAction action, int client, int param2)
{
	if(action == MenuAction_End)
	{
		delete oMenu;
		return;
	}

	if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_MainTag(client);
		return;
	}

	if(action == MenuAction_Select)
	{
		char sBuffer[32];
		oMenu.GetItem(param2, sBuffer, sizeof(sBuffer));

		if(StrEqual(sBuffer, "Reset"))
		{
			PrintToChat(client, "%s%sYour name color has been reset to default!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
			ga_sNameColor[client] = "";
			gaa_sCleanSetupText[client][2] = "";
			FormatColors(client);
			SendClientSetupToDB(client);
		}
		else if(StrEqual(sBuffer, "SetManually"))
		{
			PrintToChat(client, "%s\x03To define your own tag color, type !namecolor <hexcode> (e.g. !namecolor FFFFFF).", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		}
		else
		{
			int iColorIndex = StringToInt(sBuffer);
			g_aColorCode.GetString(iColorIndex, sBuffer, sizeof(sBuffer));
			strcopy(ga_sNameColor[client], sizeof(ga_sNameColor[]), sBuffer);
			strcopy(gaa_sCleanSetupText[client][2], sizeof(gaa_sCleanSetupText[][]), ga_sNameColor[client]);
			FormatColors(client);
			g_aColorName.GetString(iColorIndex, sBuffer, sizeof(sBuffer));
			PrintToChat(client, "\x01%sYour name color is now set to: %s%s", g_sTag, ga_sNameColor[client], sBuffer);
			SendClientSetupToDB(client);
		}
		Menu_MainTag(client);
	}
}

public void Menu_ChatColor(int client)
{
	if(ga_iIsRestricted[client])
	{
		PrintToChat(client, "%s%sYou are currently restricted from changing your tags!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return;
	}
	
	if(!g_cEnableChatColors.BoolValue)
	{
		PrintToChat(client, "%s%sThis feature has been disabled for everyone by the server manager!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		return;
	}
	
	Menu oMenu = new Menu(MenuCallback_ChatColor);
	oMenu.SetTitle("Chat Color");
	oMenu.ExitBackButton = true;
	oMenu.Pagination = 6;

	oMenu.AddItem("Reset", "Reset");
	if(!g_bCSGO && !g_bIns)
	{
		oMenu.AddItem("SetManually", "Define Your Own Color");
	}

	char sColorIndex[5], sColorName[32];
	for(int i = 0; i < g_aColorName.Length; i++)
	{
		IntToString(i, sColorIndex, sizeof(sColorIndex));
		g_aColorName.GetString(i, sColorName, sizeof(sColorName));
		oMenu.AddItem(sColorIndex, sColorName);
	}

	oMenu.Display(client, MENU_TIME_FOREVER);
}

public int MenuCallback_ChatColor(Menu oMenu, MenuAction action, int client, int param2)
{
	if(action == MenuAction_End)
	{
		delete oMenu;
		return;
	}

	if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_MainTag(client);
		return;
	}

	if(action == MenuAction_Select)
	{
		char sBuffer[32];
		oMenu.GetItem(param2, sBuffer, sizeof(sBuffer));

		if(StrEqual(sBuffer, "Reset"))
		{
			PrintToChat(client, "%s%sYour chat color has been reset to default.", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
			ga_sChatColor[client] = "";
			gaa_sCleanSetupText[client][3] = "";
			FormatColors(client);
			SendClientSetupToDB(client);
		}
		else if(StrEqual(sBuffer, "SetManually"))
		{
			PrintToChat(client, "%s\x03To define your own tag color, type !chatcolor <hexcode> (e.g. !chatcolor FFFFFF).", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		}
		else
		{
			int iColorIndex = StringToInt(sBuffer);
			g_aColorCode.GetString(iColorIndex, sBuffer, sizeof(sBuffer));
			strcopy(ga_sChatColor[client], sizeof(ga_sChatColor[]), sBuffer);
			strcopy(gaa_sCleanSetupText[client][3], sizeof(gaa_sCleanSetupText[][]), ga_sChatColor[client]);
			FormatColors(client);
			g_aColorName.GetString(iColorIndex, sBuffer, sizeof(sBuffer));
			PrintToChat(client, "\x01%sYour chat color is now set to: %s%s", g_sTag, ga_sChatColor[client], sBuffer);
			SendClientSetupToDB(client);
		}

		Menu_MainTag(client);
	}
}

//////////////////////////////////////////////////////////////////////
///////////////////////////// Admin Menu /////////////////////////////
//////////////////////////////////////////////////////////////////////

public void OnAdminMenuReady(Handle hTopMenu)
{
	TopMenu oTopMenu = TopMenu.FromHandle(hTopMenu);
	
	/* Block us from being called twice */
	if(oTopMenu == g_oTopMenu)
	{
		return;
	}
	
	/* Save the Handle */
	g_oTopMenu = oTopMenu;

	//TopMenuObject oMenuObject = AddToTopMenu(hTopMenu, "togschattags", TopMenuObject_Category, Handle_Commands, INVALID_TOPMENUOBJECT);
	TopMenuObject oMenuObject = g_oTopMenu.AddCategory("togschattags", Handle_Commands, "sm_tagadmin", ReadFlagString(g_sAdminFlag), "mainmenu");
	if(oMenuObject == INVALID_TOPMENUOBJECT)
	{
		return;
	}

	g_oTopMenu.AddItem("sm_reloadtags", AdminMenu_Command, oMenuObject, "sm_reloadtags", ReadFlagString(g_sAdminFlag));
	g_oTopMenu.AddItem("sm_restricttag", Adminmenu_Player, oMenuObject, "sm_restricttag", ReadFlagString(g_sAdminFlag), "Restrict Tags");
	g_oTopMenu.AddItem("sm_unrestricttag", Adminmenu_Player, oMenuObject, "sm_unrestricttag", ReadFlagString(g_sAdminFlag), "Unrestrict Tags");
	g_oTopMenu.AddItem("sm_removetag", Adminmenu_Player, oMenuObject, "sm_removetag", ReadFlagString(g_sAdminFlag), "Remove Tags");
	g_oTopMenu.AddItem("sm_unloadtags", AdminMenu_Unload, oMenuObject, "sm_unloadtags", ReadFlagString(g_sAdminUnloadFlag));
}

public void Handle_Commands(TopMenu oMenu, TopMenuAction action, TopMenuObject object_id, int client, char[] sBuffer, int iMaxLen)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			Format(sBuffer, iMaxLen, "TOGs Chat Tags");
		}
		case TopMenuAction_DisplayTitle:
		{
			Format(sBuffer, iMaxLen, "TOGs Chat Tags");
		}
	}
}

public void AdminMenu_Unload(TopMenu oMenu, TopMenuAction action, TopMenuObject object_id, int client, char[] sBuffer, int iMaxLen)		//command via admin menu
{
	if(action == TopMenuAction_DisplayOption)
	{
		Format(sBuffer, iMaxLen, "Unload plugin until map change");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		PrintToChat(client, "%s%sTOGs Chat Tags is now unloaded until map change!", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		char sPluginName[128];
		GetPluginFilename(INVALID_HANDLE, sPluginName, sizeof(sPluginName));
		ServerCommand("sm plugins unload %s", sPluginName); 
	}
}

public void AdminMenu_Command(TopMenu oTopMenu, TopMenuAction action, TopMenuObject object_id, int client, char[] sBuffer, int iMaxLen)		//command via admin menu
{
	if(action == TopMenuAction_DisplayOption)
	{
		Format(sBuffer, iMaxLen, "Reload Chat Tag Colors");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		Reload();
	
		PrintToChat(client, "%s%sColors setups are now reloaded.", g_sTag, g_bCSGO ? CSGO_RED : (g_bIns ? INS_GREEN : CSS_RED));
		RedisplayAdminMenu(oTopMenu, client);
	}
}

public void Adminmenu_Player(TopMenu oTopMenu, TopMenuAction action, TopMenuObject object_id, int client, char[] sBuffer, int iMaxLength)
{
	char sCommand[MAX_NAME_LENGTH], sTitle[128];
	GetTopMenuObjName(oTopMenu, object_id, sCommand, sizeof(sCommand));
	GetTopMenuInfoString(oTopMenu, object_id, sTitle, sizeof(sTitle));
	
	switch(action)
	{
		case(TopMenuAction_DisplayOption):
		{
			Format(sBuffer, iMaxLength, sTitle);
		}
		case(TopMenuAction_SelectOption):
		{
			Displaymenu_Player(client, sCommand, sTitle);
		}
	}
}

public void Displaymenu_Player(int client, char[] sCommand, char[] sTitle)
{
	Menu oMenu = new Menu(Commandmenu_Player);
	oMenu.SetTitle(sTitle);
	oMenu.ExitBackButton = true;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			char sInfoBuffer[256], sName[MAX_NAME_LENGTH], sUserID[MAX_NAME_LENGTH], sDisplay[128];
			IntToString(GetClientUserId(i), sUserID, sizeof(sUserID));
			GetClientName(i, sName, sizeof(sName));
			Format(sDisplay, sizeof(sDisplay), "%s (%s)", sName, sUserID);
			Format(sInfoBuffer, sizeof(sInfoBuffer), "%s %s", sCommand, sUserID);
			oMenu.AddItem(sInfoBuffer, sDisplay);
		}
	}
	
	oMenu.Display(client, MENU_TIME_FOREVER);
}


public int Commandmenu_Player(Menu oMenu, MenuAction Selection, int client, int param2)
{
	switch(Selection)
	{
		case(MenuAction_End):
		{
			delete oMenu;
		}
		case(MenuAction_Cancel):
		{
			char sInfo[64];
			oMenu.GetItem(param2, sInfo, sizeof(sInfo));
			char sTempArray[2][32];
			ExplodeString(sInfo, " ", sTempArray, sizeof(sTempArray), sizeof(sTempArray[]));
			
			if(StrEqual(sTempArray[0],"sm_checktag",false))
			{
				Menu_MainTag(client);
			}
			else
			{
				DisplayTopMenu(g_oTopMenu, client, TopMenuPosition_LastCategory);
			}
		}
		case(MenuAction_Select):
		{
			char sInfo[64];
			oMenu.GetItem(param2, sInfo, sizeof(sInfo));
			char sTempArray[2][32];
			ExplodeString(sInfo, " ", sTempArray, sizeof(sTempArray), sizeof(sTempArray[]));

			if(!IsValidClient(GetClientOfUserId(StringToInt(sTempArray[1]))))
			{
				ReplyToCommand(client, "%sTarget is now invalid.", g_sTag);
			}
			else
			{
				char sCommand[300];
				Format(sCommand, sizeof(sCommand), "%s #%i", sTempArray[0], StringToInt(sTempArray[1]));
				FakeClientCommand(client, sCommand);
			}
		}
	}
}

void CleanStringForSQL(char[] sString, int iSize)
{
	int iEscapeSize = 2*iSize + 1;
	char[] sEscapedText = new char[iEscapeSize];
	g_oDatabase.Escape(sString, sEscapedText, iEscapeSize);
	strcopy(sString, iSize, sEscapedText);
	
	/*char[] sBuffer = new char[iSize];
	strcopy(sBuffer, iSize, sString);
	ReplaceString(sBuffer, iSize, "}", "");
	ReplaceString(sBuffer, iSize, "{", "");
	ReplaceString(sBuffer, iSize, "|", "");
	ReplaceString(sBuffer, iSize, "'", "");
	ReplaceString(sBuffer, iSize, "\%27", "");		// '
	ReplaceString(sBuffer, iSize, "\"", "");
	ReplaceString(sBuffer, iSize, "\%22", "");		// "
	ReplaceString(sBuffer, iSize, "`", "");
	ReplaceString(sBuffer, iSize, "\%60", "");		// `
	ReplaceString(sBuffer, iSize, "\\", "");
	ReplaceString(sBuffer, iSize, "\%5C", "");		// backslash
	ReplaceString(sBuffer, iSize, "#", "");
	ReplaceString(sBuffer, iSize, "\%23", "");		// #
	ReplaceString(sBuffer, iSize, "--", "");
	ReplaceString(sBuffer, iSize, "\%2D-", "");		// --
	ReplaceString(sBuffer, iSize, "-\%2D", "");		// --
	ReplaceString(sBuffer, iSize, "\%2D\%2D", "");	// --
	ReplaceString(sBuffer, iSize, "=", "");
	ReplaceString(sBuffer, iSize, "\%3D", "");		// =
	ReplaceString(sBuffer, iSize, ";", "");
	ReplaceString(sBuffer, iSize, "\%3B", "");		// ;
	ReplaceString(sBuffer, iSize, "^", "");
	ReplaceString(sBuffer, iSize, "\%5E", "");		// ^
	ReplaceString(sBuffer, iSize, "%", "");
	ReplaceString(sBuffer, iSize, "\%25", "");		// %
	strcopy(sString, iSize, sBuffer);	*/
}

stock void Log(char[] sPath, const char[] sMsg, any ...)	//TOG logging function - path is relative to logs folder.
{
	char sLogFilePath[PLATFORM_MAX_PATH], sFormattedMsg[1500];
	BuildPath(Path_SM, sLogFilePath, sizeof(sLogFilePath), "logs/%s", sPath);
	VFormat(sFormattedMsg, sizeof(sFormattedMsg), sMsg, 3);
	LogToFileEx(sLogFilePath, "%s", sFormattedMsg);
}

/*
CHANGELOG:
	2.1:
		* Added spam blocker
		* Added console color cvars
	2.2:
		* Converted team names to read team name...was using CSS ones before.
	2.3:
		* Added auto-gag after detected for spam 3x, with cvar for time span it all occurs, if it is even on, and added cvar to disable spam detection period.
	2.4:
		* Added cvar to specify length of auto-gag for spammers. This only applies for extendedcomm plugins. Else, the mute will be a SM default mute (temp).
	2.5:
		* Moved return for ignored text after the spam blockers.
	2.6:
		* Fixed the check tags command - now handles groups, and fixed that it was returning the setup of the person sending the command, not the target. Also made the command executable from rcon.
		* Edited formatting for [TCT] on all replys.
		* Added checks to make sure they arent mimicking console and have an easy place to add checks for bad names (and remove if they're found to be).
	2.7:
		* Created CS:GO version (currently not public).
		* Converted back to PrintToChat from morecolor's CPrintToChat, due to the ability to glitch their function and color text by using the tag codes in your message (e.g. "{fullred}Hey look! My text is red!")
		* Added a function to format the team names so that the first letter is capitolized, and letters after hyphens, a space, or a first parenthesis are capitolized. All else are lower case.
		* Fixed cvar names.
		* Added cvars to disable any of the 4 main tag/color functions (tags, tag colors, name colors, and chat colors).
		* Changed kv key from "hex" to "colors" to be more generic for use with CS:GO, and simplicity/similarity between the two versions.
		* Removed g_iTagSetting, and replaced with conditional formatting.
		* One cvar was missing a hook to it being change. Added in.
		* Added code to return Plugin_Continue if message was blank.
	2.8:
		* Added config setups for groups or individuals.
	3.0.3:
		* Fixed setting individual setups in ftp cfg being applied as public.
		* Made it so that if server managers put the wrong steam universe in IDs (STEAM_0), it will still work, despite their fail -.- .
	3.1:
		* Added code to allow external plugins to set additional tags.
		* Shortened cfg filenames.
		* Added a few lines to help protect against multiple messages spamming chat when gagging a client.
	3.1.2:
		* Added ability to set the access flag to "public" to make it available to all.
	3.1.3:
		* Added line at top to increase stack space.
	3.1.4:
		* Updated HasFlags function to allow more versatility/configurability.
	3.1.5:
		* Added cvars for default CT and T colors for names and chat, when no other setups apply.
	4.0:
		* Added natives for access overrides.
		* Edited HasFlags to be able to pass "none" to block all access (leaving tags only available to external plugins).
		* Added forward for plugin reload.
		* Renamed a lot of variables to use my current nomenclatures, and made global integers into booleans where there's only 2 options.
		* Combined the CS:S and CS:GO versions
		* Redid some of the admin menu to combine functions using techniques/code I made for my other plugins.
	4.1
		* Stable version with all bugs worked out from the 4.0 conversion.
	4.1.1:
		* Added more CheckClientLoad to combat the OnClientCookiesCached event not always firing (not sure if that's a sourcemod bug or what...).
	4.1.2:
		* Created Fwd for when a client finishes loading.
	4.2:
		* Added missing flag check for unload cmd.
		* Added cvars and cmd for an admin (configurable flag) to set another player's tag/color settings.
		* Removed resetting ga_iIsRestricted in RemoveSetup.
		* Rebuilt cfg file to use ADT arrays for storing colors. Didnt realize I wasnt doing this (that piece was coded a long while back).
		* Edited ConvertColor to also allow the names from the cfg file and to convert them accordingly. Increased all tag buffers to 32 to allow this.
		* Added 4 more cookies to keep track of if settings for a client were an admin override.
		* Added cmd to remove all admin overrides from a client.
		* Changed default for ga_iTagVisible to 0.
	4.2.1:
		* Edited g_iExternalPos to make it so they can have just one tag, if configured to be that, and preference one or the other.
		* Removed FCVAR_PLUGIN due to it being depreciated.
	4.3.0:
		* Added code from SCP to filter out translations.
	4.3.1:
		* Scrapped everything added from SCP for 4.3.0, and wrote my own stuff that functions better and avoids the bad translation file parsing they use, etc.
	4.3.2:
		* Edited using names to specify colors being forced. Still not tested, but noticed that it was still inside the check for string length < 3, and fixed that. Should be good now.
	4.3.3:
		* Added a SetFailState for missing translation.
		* Added CreateDirectory if they didnt make the logs/chatlogger/ folder.
	4.3.4:
		* Edited cancel button when picking players players via Displaymenu_Player function. Since it is also used in admin menu, apparently the back button allows going to the admin menu. Now, it checks the command to determine if it should draw the tags menu or admin menu.
	4.4.0:
		* Added code so that the group configs can specify team groups (e.g. TEAM_2 would be terrorists in CS:S/CS:GO).
	4.4.1:
		* Added cvar tct_hidechattriggers and supporting code to hide chat triggers, per request.
	4.4.2:
		* Added cvar tct_forcebrackets and supporting code, per request.
	4.4.3:
		* Added cvar tct_bracketcolor and supporting code, per request.
		* Removed <morecolors> include, since it wasnt being used (and hasnt been for a while).
	4.4.4:
		* Minor edit to move the bracket adding inside the check for if they get tags.
	4.5.0:
		* Added support for Insurgency.
		* Removed "tct_enabled" cvar, since they should just unload/reload plugin to enable/disable.
		* Changed player settings to store in SQL database instead of client cookies.
		* Added forward for when clients reload (called every time they change their setup) and their info is sent to the database.
	4.5.1:
		* Added a few colors to insurgency settings: Banana yellow, dark yellow. Added iEntIDOverride in SayText2 to add red color for insurgency.
		* Added code to paginate the colors better.
	4.5.2:
		* Flipped the ga_iTagHidden variable to ga_iTagVisible, and changed the DB column from `hidden` to `visible`. Flipped the logic on that variable throughout the plugin. The purpose of this was to fix the tags menu functionality around if the first option in the menu says "Disable tag", etc.
	4.5.3:
		* Added code for !blockchat command to allow players to disable all chat from others. I havent tested this feature yet though.
	4.5.4:
		* Added CleanStringForSQL(ga_sEscapedName[client], sizeof(ga_sEscapedName[])); in a couple locations where the name was being re-grabbed.
	4.5.5:
		* Fixed an error that showed up in recent edits around the ga_iTagVisible (previously ga_iTagHidden) variable. It caused players to get cfg setup even when they set their own.
	4.6.0:
		* Converted plugin to 1.8 syntax and made use of classes, etc. Plugin not tested.
	4.6.1:
		* Upped buffer from 32 to 120 for cvar flag caches.
		* Added cvar and code for admin flags for the spam blocker to ignore.
		* Added cvar and code so that after an admin removes someones setup, it will check the groups config file for a default setup (if enabled).
		* Made it so that the groups config file supports AuthId_Steam2, AuthId_Steam3, and AuthId_SteamID64. The database will use AuthId_Steam2 with steam universe = 0.
	4.7.0:
		* Attempted rainbow chat after being harassed by several people to add it. Figured out that it truncates long messages due to character limit. Rolled back changes.
		* Edited out SetFailState for key-values config for groups, allowing it to be blank inside setups. Replaced with PrintToServer msg.
		* Moved chat logger to database table if using MySQL. For SQLite, it still uses flatfiles.
		* Modified CleanStringForSQL to just use the Escape. Should change into prepared statements in the future... EDIT: Looked into prepared statements, and they still arent available threaded :(  .
		* Added separate cache for escaped and unescaped player names (unescaped is used in SayText2).
		* Added g_cHideChatTriggers check in Say_Team hook (it was only in regular say hook before).
		* Moved timer to update chat logs flatfile path to be inside DB connect when it decides it is sqlite (part of migration to MySQL logs).
		* Created web panel for displaying chat logs, grouped by server. Web page is all relative urls and the only edit needed is the database info!
	4.7.1:
		* Minor edit to incorporate the 1.8 syntax Database class fully. This does not effect the plugin in any way.
		* Made it so that CleanStringForSQL cant be called when the database is null.
	4.7.2
		* Minor edit to enforce some boundaries on some cvars.
	4.8.0
		* Made the name of the database table into a cvar so that a single database can be used with separate tables for separate servers (per request).
		* Restructured the table creation code for the database so that the bulk of the query is only written in the code once, and is more readable.
	4.8.1
		* Missed some of the queries being updated to use the new cvar tablename from 4.8.0. Edited.
		* Changed the unload cmds to auto-detect the plugin name.
	4.9.0
		* Revamped spam protection to make it more configurable. All cvars renamed accordingly.
		* Renamed some variables and functions.
		* Converted the last of the timers to pass userid instead of client index. The only ones that were still there were 0.1 second timers, so I didnt bother it using the extra resources to be safe on such a short timer, but now I changed it.
	4.9.1
		* Removed <smlib> include - wasnt being used.
	4.9.2
		* Edit so that cfg sections with numbers wouldnt be skipped by being falsely identified as steam ids (64).
	4.9.3
		* Minor edit in SQLCallback_Connect that has no change to functionality. It is simply a cleanup of code that I want to use in the future for database connections where sqlite is allowed.
*/