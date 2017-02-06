/** Double-include prevention */
#if defined _togsclantags_included_
  #endinput
#endif
#define _togsclantags_included_

/**
 * Apply an extra chat tag to the client.
 *
 * @param	client			Client index
 * @param	sExtTag			String to use as tag text
 * 
 * @return true if valid client and tags applied, false otherwise.
 */
//native bool TOGsClanTags_SetExtTag(int client, char[] sExtTag);

/* 
 * Called on plugin load / reload.
 * 
 * @return	None.
 */ 
//forward void TOGsClanTagsLoaded();

/* 
 * Called when a client finishes loading.
 * 
 * @return	None.
 */ 
//forward void TOGsClanTagsClientLoaded(int client);

/**
 * Notify clan tags plugin to reload.
 * 
 * @return None.
 */
native void TOGsClanTags_Reload();

/**
 * Check if plugin is using mysql setups (else cfg file).
 * 
 * @return 1 if using mysql, 0 otherwise.
 */
native int TOGsClanTags_UsingMysql();

public SharedPlugin __pl_togsclantags =
{
	name = "togsclantags",
	file = "togsclantags.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_togsclantags_SetNTVOptional()
{
	MarkNativeAsOptional("TOGsClanTags_Reload");
	MarkNativeAsOptional("TOGsClanTags_UsingMysql");
}
#endif
