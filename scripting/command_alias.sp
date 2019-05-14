#include <sourcemod>
#pragma newdecls required
#pragma semicolon 1
#file "Command Aliases"

StringMap gSM_Commands;
ArrayList gA_OldCommands;
char gS_ConfigPath[PLATFORM_MAX_PATH];

public Plugin myinfo = 
{
	name = "Command Aliases",
	author = "KiD Fearless",
	description = "redirects commands to other commands",
	version = "1.3",
	url = "https://github.com/kidfearless"
}

// Initialize our global variables, and create our commands
public void OnPluginStart()
{
	gSM_Commands = new StringMap();
	gA_OldCommands = new ArrayList(ByteCountToCells(64));

	BuildPath(Path_SM, gS_ConfigPath, sizeof(gS_ConfigPath), "configs/command_aliases.cfg");
	if(!FileExists(gS_ConfigPath))
	{
		File temp = OpenFile(gS_ConfigPath, "a");
		temp.WriteString("\"Aliases\"\n{\n\t\"sm_reloadaliases\"\t\"sm_reload_aliases\"\n}", false);
		temp.Close();
	}
	
	RegAdminCmd("sm_reload_aliases", Command_Aliases, ADMFLAG_CONFIG, "Reload the command alias config");
}

public Action Command_Aliases(int client, int args)
{
	DoCleanup();

	if(ReadConfig())
	{
		ReplyToCommand(client, "[SM] Config Reloaded Successfully!");
	}
	else
	{
		ReplyToCommand(client, "[SM] There was an error while reading the config.");
	}
	return Plugin_Handled;
}

// Add a chat listener for our commands
public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	char value[64];
	char say_command[64];
	// Copy the argument string in case there's no spaces to be found
	strcopy(say_command, sizeof(say_command), sArgs);

	// split the command from the arguments and save the index that they are split from
	int index = SplitString(sArgs, " ", say_command, sizeof(say_command));

	// Check the command against our list of aliases
	if(gSM_Commands.GetString(say_command, value, sizeof(value)))
	{
		// If we found arguments pass them along
		if(index > 0)
		{
			StrCat(value, sizeof(value), sArgs[index - 1]);
		}

		FakeClientCommand(client, value);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

// Do setups on map start. If the plugin is loaded late this will automatically be called.
public void OnMapStart()
{
	ReadConfig();
}

// Clean up any commands in case we want to add some new ones
public void OnMapEnd()
{
	DoCleanup();
}

// Clean up function to remove any chat listeners and clear up memory.
void DoCleanup()
{
	// Get the length of our command list
	int length = gA_OldCommands.Length;
	// Remove all the command listeners that we've added
	for(int i = 0; i < length; ++i)
	{
		char buffer[64];
		gA_OldCommands.GetString(i, buffer, sizeof(buffer));
		RemoveCommandListener(AliasListener, buffer);
	}
	// Clear up both lists
	gA_OldCommands.Clear();
	gSM_Commands.Clear();
}

// Function to start parsing the config, and log any errors that may occur
bool ReadConfig()
{
	int line, column;
	// Create a new SMCParser object
	SMCParser parser = new SMCParser();
	// Set it's OnKeyValue Callback to OnKeyValue
	parser.OnKeyValue = OnKeyValue;
	// Attempt to parse it and save it's return state
	SMCError error = parser.ParseFile(gS_ConfigPath, line, column);

	// Check for any errors
	if(error != SMCError_Okay)
	{
		// Grab it's error and log it.
		char errorMessage[128];
		parser.GetErrorString(error, errorMessage, sizeof(errorMessage));
		LogError("Error parsing alias config line: %i, col: %i ERROR: %s", line, column, errorMessage);
	}

	// Cleanup
	delete parser;

	return (error == SMCError_Okay);
}

// Callback for when a line is processed. Key being the command to listen to and value being the new command.
// If it's a sourcemod command then it will add the default chat listeners to it.
public SMCResult OnKeyValue(SMCParser smc, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
	SetCommandAlias(key, value);

	char cmd[64];
	strcopy(cmd, sizeof(cmd), key);

	// Try to replace sm_ with ! and if it succeeds replace it with /
	if(ReplaceStringEx(cmd, sizeof(cmd), "sm_", "!") != -1)
	{
		SetCommandAlias(cmd, value);
		ReplaceStringEx(cmd, sizeof(cmd), "!", "/");
		SetCommandAlias(cmd, value);
	}
	
	return SMCParse_Continue;
}

// Sets checks for the existance of a key and removes it's previous listener.
// Then adds a new one.
void SetCommandAlias(const char[] listen_command, const char[] output_command, bool replace = true)
{
	char old_command[64];
	// If the stringmap has this command then remove the old one
	if(gSM_Commands.GetString(listen_command, old_command, sizeof(old_command)))
	{
		RemoveCommandListener(AliasListener, listen_command);
	}
	// Otherwise add it to the list for later removal
	else
	{
		gA_OldCommands.PushString(listen_command);
	}

	// Update the stringmap, and arraylist with it's corresponding command
	gSM_Commands.SetString(listen_command, output_command, replace);
	AddCommandListener(AliasListener, listen_command);
}

// CommandListener Callback, if the current command can be found in the stringmap then it will execute it's corresponding alias instead.
// Can also be used as a generic block if the value is empty
public Action AliasListener(int client, const char[] command, int argc)
{
	char value[64];

	// Replace the command that we passed with its alias.
	if(gSM_Commands.GetString(command, value, sizeof(value)))
	{
		char arg_string[64];

		// Grab any arguments that we passed originally and append them as well.
		GetCmdArgString(arg_string, sizeof(arg_string));
		Format(value, sizeof(value), "%s %s", value, arg_string);

		FakeClientCommand(client, value);

		return Plugin_Handled;
	}

	return Plugin_Continue;
}