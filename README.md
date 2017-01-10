#TOGs Clan Tags
(togsclantags)

This plugin is fully customizable. You can make as many setups as desired, and have as many kinds of configurations as desired (all through a config file or database). The setups are fully explained inside the config file, but can also be found below.



##Installation:
* togsclantags.smx to /addons/sourcemod/plugins/ folder.
* Either use a database setup, similar to databases example file, or use togsclantags.cfg in /addons/sourcemod/configs/ folder.
* Configure your setups in the config file or your mysql database, then load plugin, configure your cvars (/cfgs/sourcemod/togsclantags.cfg) and then you're set! Note: After changing the cvars in your cfg file, be sure to rcon the new values to the server so that they take effect immediately.



##CVars:
* **togsclantags_admflag** - Admin flag(s) used for sm_rechecktags command.
* **togsclantags_bots** - Do bots get tags? (1 = yes, 0 = no).
* **togsclantags_enforcetags** -If no matching setup is found, should their tag be forced to be blank? (0 = allow players setting any clan tags they want, 1 = if no matching setup found, they can only use tags found in the cfg file, 2 = only get tags by having a matching setup in cfg file).
* **togsclantags_updatefreq** - Frequency to re-load clients from cfg file (0 = only check once). This function is namely used to help interact with other plugins changing admin status late.
* **togsclantags_use_mysql** - Use mysql? (1 = Use MySQL to manage setups, 0 = Use cfg file to manage setups).



##Default Cfg File:
<details>
<summary>Click to Open Spoiler</summary>
<p>
<pre><code>
//////////////////////////////////////////////////////////////////
//
// SAMPLE SETUP:
//
//		"Title"											<- This can be anything. I suggest making it something indicating what the setup is for.
//		{
//			"enabled"	"1"								<- Entering "0" here will disable a setup entirely, except as allowable tags for togsclantags_enforcetags = 1 (combo with "exclude" to block that part as well). If omitted, 1 is assumed.
//			"flag"		"INPUT"							<- There are 3 kinds of inputs. See below.
//			"tag"		"[SOME TAG]"					<- Tag.
//			"ignore"	"1"								<- Typically not included. Applies "ignore" setup to client. See below.
//			"exclude"	"1"								<- Either 0 or 1 should be entered here. If omitted, 0 is assumed. If cvar togsclantags_enforcetags = 1, 
//		}												   then "0" includes this tag as an allowed tag when no matching setups are found. "1" excludes the tag from the allowable tags list.
//
//////////////////////////////////////////////////////////////////
//
// INPUTS AND ORDER OF OPERATION:
//
// The player will get the first tag that matches them. So, a general order of setups is: Bot setup -> Steam ID setups -> group setups.
//
// BOT: This setup will apply to all bots, and only to bots.
//
// Steam ID (STEAM_X:X:XXXXXXX format): This will apply only to the player whose steam ID it is. 
// 		Note: The plugin checks both "STEAM_0" and "STEAM_1" (steam universe 0 and 1), so if you put the wrong one in, it still works.
//
// Groups: This is a single, multiple, or multiple sets of admin flags.
// 		e.g. Setting the flag as "a" requires players to have the "a" flag to be considered a match.
// 		e.g. "at" requires players to have both the "a" AND "t" flags to be considered a match.
// 		e.g. "a;t" requires players to have either the "a" OR "t" flags to be considered a match.
// 		e.g. "at;b" requires players to have EITHER: (both the "a" AND "t" flags), OR the "b" flag.
// 			If either of the two conditions apply, they are considered a match.
// 		Note: "public" and empty quotes ("") make the access available to all.
//
// "ignore" Setup: When this key-value is included in a setup, you can leave out the "tag" key-value, since it wont be read anyways.
//		The purpose of this key-value is to make exceptions for groups.
//		e.g. PlayerA doesnt want the group tag that is applied to all donators with flag "a".
//		Instead, you could make them a personal setup, using their steam ID as the flag, but with the "ignore" key-value.
//		This setup is read first (assuming you put it above the other one), and they exit the function without a tag.
//
//////////////////////////////////////////////////////////////////
// Note: Do not change the word "Setups" in the line below, else the plugin will not read this file.
"Setups"
{
	"Bot setup"
	{
		"flag"		"BOT"
		"tag"		"[BOT TAG]"
		"exclude"	"1"		//this tag is NOT included in the allowable tags list when togsclantags_enforcetags = 1
	}
	"Some Players Setup to Ignore Avoid VIP Group Tag"
	{
		"flag"		"STEAM_0:1:1234567"
		"ignore"	"1"
		"exclude"	"1"		//this tag is NOT included in the allowable tags list when togsclantags_enforcetags = 1
	}
	"Some player"
	{
		"flag"		"STEAM_0:1:1234567"
		"tag"		"[SOME TAG]"
		"exclude"	"1"		//this tag is NOT included in the allowable tags list when togsclantags_enforcetags = 1
	}
	"Some guy"
	{
		"enabled"	"0"		//this setup is disabled! The tag is also not in the allowable tags list when togsclantags_enforcetags = 1
		"flag"		"STEAM_0:1:9876554"
		"tag"		"[ANOTHER TAG]"
		"exclude"	"1"		//this tag is NOT included in the allowable tags list when togsclantags_enforcetags = 1
	}
	"Admin Tag"
	{
		"flag"		"b"
		"tag"		"[ADMIN]"
		"exclude"	"0"		//this tag IS INCLUDED in the allowable tags list when togsclantags_enforcetags = 1
	}
	"VIP Group"
	{
		"flag"		"aost"
		"tag"		"[VIP]"	 //this tag IS INCLUDED in the allowable tags list when togsclantags_enforcetags = 1
	}
	"Some other tag"
	{
		"flag"		"a;st"
		"tag"		"[MEMBER]"	 //this tag IS INCLUDED in the allowable tags list when togsclantags_enforcetags = 1
	}
}
</code></pre>
</p>
</details>



##Changelog:
<details>
<summary>Click to Open Spoiler</summary>
<p>
<br>2.2.0:</br>
<li>Fixed an improper indexing of a_sSteamIDs in GetTags.</li>
<li>Added debug cvar and full debug code.</li>
<li>Converted several things to use 1.8 syntax classes (methodmaps) where they weren't before.</li>
<li>Modidied the GetTags function a bit.</li>
<li>Added IsValidClient check inside GetTags, though i believe it was filtered in the calling functions, but perhaps not each instance.</li>

<br>2.1.4:</br>
<li>Added spec cmd hooks.</li>

<br>2.1.3:</br>
<li>Accidently returned Plugin_Handled instead of Plugin_Continue on the hooks for jointeam and joinclass. Fixed that.</li>

<br>2.1.2:</br>
<li>Removed if(!g_hUseMySQL.BoolValue){} in Event_Recheck. I dont recall why that check was there...</li>
<li>Added hooks for jointeam and joinclass commands. Previously, only the player_team event was being hooked.</li>

<br>2.1.1:</br>
<li>Added check in flags section to filter out new steam ID types.</li>
<li>Fixed index error in new steam ID array.</li>
<li>Added check for if client is authorized when getting the 4 steam IDs, else loop client.</li>

<br>2.1.0:</br>
<li>Added native to reload plugin.</li>
<li>Added native to check if using mysql.</li>
<li>Added plugin library registration.</li>
<li>Added check for NULL server_ip field in mysql (previously, it checked for blanks (''), so this was added to be extra safe, not due to any problems).</li>
<li>Added `dont_remove` column to support other plugins that are adding into the database. Default = 1. Plugins adding in setups can add it with a 0 to be able to override their own and know it is safe.</li>
<li>Added code so that setups using steam IDs can use AuthId_Steam2 (both universe 0 and 1), AuthId_Steam3, or AuthId_SteamID64.</li>
<li>Changed cvars to use methodmaps.</li>

<br>2.0.1:</br>
<li>Added check for blank IP before running queries just to be safe.</li>

<br>2.0:</br>
<li>Converted to 1.8 syntax.</li>
<li>Added option to use mysql DB and recoded plugin to support either MySQL or kv file.</li>
<li>Added "enabled" key value.</li>
<li>Edited documentation to include "exclude" key-value.</li>
<li>Added cache of all setups.</li>
<li>Added round-end re-check of DB setups count for checking if a new setup has been added.</li>

<br>1.5:</br>
<li>Added "ignore" kv.</li>

<br>1.4:</br>
<li>Edited togsclantags_enforcetags cvar: was missing 'c' in name, and added an option to allow tags if they exist in the cfg.</li>

<br>1.3:</br>
<li>Minor edits to make sure clients load tag when spawning in late, etc.</li>

<br>1.2:</br>
<li>Added OnRebuildAdminCache event.</li>
<li>Added cvar for rechecking client against cfg file on a configurable interval. This was added so that the plugin can interact with other plugins that dont fwd admin cache changes properly.</li>

<br>1.1:</br>
<li>Fixed memory leak due to missing a CloseHandle on one of the returns.</li>

<br>1.0:</br>
<li>Plugin coded for private. Released to Allied Modders after suggestion from requester.</li>
</p>
</details>






###Check out my plugin list: http://www.togcoding.tech/togcoding/index.php
