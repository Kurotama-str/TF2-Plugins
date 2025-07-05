// Hyper Upgrades - Version 0.20
// Author: Kuro + OpenAI

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>
#include <tf_econ_data>

#define PLUGIN_NAME "Hyper Upgrades"
#define PLUGIN_VERSION "0.03"
#define CONFIG_ATTR "hu_attributes.cfg"
#define CONFIG_UPGR "hu_upgrades.cfg"
#define CONFIG_WEAP "hu_weapons_list.txt"
#define CONFIG_ALIAS "hu_alias_list.txt"
#define TRANSLATION_FILE "hu_translations.txt"

bool g_bMenuPressed[MAXPLAYERS + 1];
bool g_bPlayerBrowsing[MAXPLAYERS + 1];

char g_sPlayerCategory[MAXPLAYERS + 1][64];
char g_sPlayerAlias[MAXPLAYERS + 1][64];
char g_sPlayerUpgradeGroup[MAXPLAYERS + 1][64];

Handle g_hMoneyPool;
int g_iMoneySpent[MAXPLAYERS + 1];

Handle g_hPlayerUpgrades[MAXPLAYERS + 1];
ConVar g_hResetMoneyPoolOnMapStart;


public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = "Kuro + OpenAI",
    description = "Team-based upgrade system for TF2.",
    version = PLUGIN_VERSION,
    url = ""
};

//init weapon list
enum struct WeaponAlias
{
    int defindex;
    char alias[64];
}

ArrayList g_weaponAliases = null;
//init attribute list
enum struct AttributeMapping
{
    char alias[64];
    char attributeName[128];
}

ArrayList g_attributeMappings = null;


public void OnPluginStart()
{
    RegConsoleCmd("sm_buy", Command_OpenMenu);
    RegConsoleCmd("sm_shop", Command_OpenMenu);

    RegAdminCmd("sm_addmoney", Command_AddMoney, ADMFLAG_GENERIC, "Add money to the pool.");
    RegAdminCmd("sm_subtractmoney", Command_SubtractMoney, ADMFLAG_GENERIC, "Subtract money from the pool.");

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("teamplay_point_captured", Event_ObjectiveComplete, EventHookMode_Post);
    HookEvent("teamplay_flag_event", Event_ObjectiveComplete, EventHookMode_Post);
    HookEvent("teamplay_round_win", Event_ObjectiveComplete, EventHookMode_Post);
    HookEvent("player_changeclass", Event_PlayerChangeClass, EventHookMode_Post);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);

    CreateConVar("hu_money_per_kill", "100", "Money gained per kill.");
    CreateConVar("hu_money_per_objective", "300", "Money gained per objective.");
    CreateConVar("hu_money_boss_multiplier", "5.0", "Multiplier for boss kills.");

    g_hMoneyPool = CreateConVar("hu_money_pool", "0", "Current money pool shared by all players.", FCVAR_NOTIFY);

    LoadTranslations(TRANSLATION_FILE);

    GenerateConfigFiles();

    RegAdminCmd("sm_reloadweapons", Command_ReloadWeaponAliases, ADMFLAG_GENERIC, "Reload the weapon aliases.");

    g_weaponAliases = new ArrayList(sizeof(WeaponAlias));
    LoadWeaponAliases();
    g_attributeMappings = new ArrayList(sizeof(AttributeMapping));
    LoadAttributeMappings();

    // Reset upgrades for all connected players
    ResetAllPlayerUpgrades();

    g_hResetMoneyPoolOnMapStart = CreateConVar("hu_reset_money_on_mapstart", "1", "Reset the money pool to 0 on map start. 1 = Enabled, 0 = Disabled.", FCVAR_NOTIFY);

}

public void OnPluginEnd()
{
    if (g_weaponAliases != null)
    {
        delete g_weaponAliases;
        g_weaponAliases = null;
    }
}

public void OnClientPutInServer(int client)
{
    RefundPlayerUpgrades(client, false); // No message on join
}

public void OnClientDisconnect(int client)
{
    RefundPlayerUpgrades(client, false); // No message on disconnect
}

public void OnMapStart()
{
    if (g_hResetMoneyPoolOnMapStart.BoolValue)
    {
        SetConVarInt(g_hMoneyPool, 0);

        // Also reset player upgrades
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
            {
                RefundPlayerUpgrades(i,false);
            }
        }
    }
}

public void Event_PlayerChangeClass(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (IsClientInGame(client))
    {
        RefundPlayerUpgrades(client, false);
    }
}


public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (IsClientInGame(client))
    {
        ApplyPlayerUpgrades(client);
    }
}

// Money handler for players
void RefundPlayerUpgrades(int client, bool bShowMessage = true)
{
    if (!IsClientInGame(client))
        return;

    // Remove all applied attributes from player and their weapons
    RemovePlayerUpgrades(client);

    // Clear the KeyValues upgrades
    if (g_hPlayerUpgrades[client] != null)
    {
        CloseHandle(g_hPlayerUpgrades[client]); // Delete all stored upgrades
        g_hPlayerUpgrades[client] = CreateKeyValues("Upgrades"); // Fresh upgrades
    }
    else
    {
        g_hPlayerUpgrades[client] = CreateKeyValues("Upgrades"); // Safety in case it's null
    }

    // Reset money spent
    g_iMoneySpent[client] = 0;

    if (bShowMessage)
    {
        PrintToChat(client, "[Hyper Upgrades] All upgrades refunded.");
    }
}

// Actually removes the attributes
void RemovePlayerUpgrades(int client)
{
    if (!IsClientInGame(client))
        return;

    // Remove all body (player) attributes
    TF2Attrib_RemoveAll(client);

    // Remove attributes from all weapons
    for (int slot = 0; slot <= 5; slot++) // Check all potential weapon slots
    {
        int weapon = GetPlayerWeaponSlot(client, slot);
        if (IsValidEntity(weapon))
        {
            TF2Attrib_RemoveAll(weapon);
        }
    }
}
// Refund for all players. Should probably have called it refundallplayers. Oh well.
void ResetAllPlayerUpgrades()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            RefundPlayerUpgrades(i, false); // Reset without showing the refund message
        }
    }

    PrintToServer("[Hyper Upgrades] All player upgrades have been reset.");
}

// Reload Aliases for Weapons
public Action Command_ReloadWeaponAliases(int client, int args)
{
    g_weaponAliases.Clear();
    LoadWeaponAliases();
    PrintToChatAll("[Hyper Upgrades] Weapon aliases reloaded.");
    return Plugin_Handled;
}

// Detect scoreboard key press
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Continue;

    // Check for scoreboard key press
    if ((buttons & IN_SCORE) && !g_bMenuPressed[client])
    {
        g_bMenuPressed[client] = true;
        Command_OpenMenu(client, 0);
    }
    else if (!(buttons & IN_SCORE))
    {
        g_bMenuPressed[client] = false;
    }

    return Plugin_Continue;
}

// Console commands to open menu
public Action Command_OpenMenu(int client, int args)
{
    if (!IsClientInGame(client))
        return Plugin_Handled;

    ShowMainMenu(client);
    return Plugin_Handled;
}

// Build the main menu
void ShowMainMenu(int client)
{
    Menu menu = new Menu(MenuHandler_MainMenu);
    menu.SetTitle("Hyper Upgrades \nBalance: %d/%d$", GetPlayerBalance(client), GetConVarInt(g_hMoneyPool));

    menu.AddItem("body", "Body Upgrades");
    menu.AddItem("primary", "Primary Upgrades");
    menu.AddItem("secondary", "Secondary Upgrades");
    menu.AddItem("melee", "Melee Upgrades");
    menu.AddItem("refund", "Upgrades List / Refund");

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

// Handle main menu selection
public int MenuHandler_MainMenu(Menu menu, MenuAction action, int client, int param)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param, info, sizeof(info));

        if (StrEqual(info, "body"))
        {
            ShowCategoryMenu(client, "Body Upgrades");
        }
        else if (StrEqual(info, "primary"))
        {
            ShowCategoryMenu(client, "Primary Upgrades");
        }
        else if (StrEqual(info, "secondary"))
        {
            ShowCategoryMenu(client, "Secondary Upgrades");
        }
        else if (StrEqual(info, "melee"))
        {
            ShowCategoryMenu(client, "Melee Upgrades");
        }
        else if (StrEqual(info, "refund"))
        {
            // You can build the refund menu here later
            PrintToChat(client, "[Hyper Upgrades] Refund menu is not implemented yet.");
        }
    }
    return 0;
}

//void StrExtract(char[] dest, int destLen, const char[] src, int length)
//{
//    // Make sure we don't copy more than dest can hold
//    if (length >= destLen)
//        length = destLen - 1;
//
//    for (int i = 0; i < length; i++)
//    {
//        dest[i] = src[i];
//    }
//    dest[length] = '\0'; // Null-terminate
//}

void LoadWeaponAliases()
{
    char filePath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, filePath, sizeof(filePath), "configs/hu_weapons_list.txt");

    if (!FileExists(filePath))
    {
        PrintToServer("[Hyper Upgrades] hu_weapons_list.txt not found, create it or reload the plugin.");
        return;
    }

    Handle file = OpenFile(filePath, "r");
    if (file == null)
    {
        PrintToServer("[Hyper Upgrades] Failed to open hu_weapons_list.txt.");
        return;
    }

    // Clear the list to prevent duplicates on reload
    g_weaponAliases.Clear();

    char line[256];

    while (!IsEndOfFile(file) && ReadFileLine(file, line, sizeof(line)))
    {
        TrimString(line);

        // Skip empty lines or comment lines
        if (line[0] == '\0' || line[0] == '#')
            continue;

        // Split the line by comma
        char parts[2][64];
        int count = ExplodeString(line, ",", parts, sizeof(parts), sizeof(parts[]));

        if (count == 2)
        {
            TrimString(parts[0]);
            TrimString(parts[1]);

            WeaponAlias weapon;
            weapon.defindex = StringToInt(parts[0]);
            strcopy(weapon.alias, sizeof(weapon.alias), parts[1]);

            g_weaponAliases.PushArray(weapon);
        }
        else
        {
            PrintToServer("[Hyper Upgrades] Skipping malformed line: %s", line);
        }
    }

    CloseHandle(file);
    PrintToServer("[Hyper Upgrades] Loaded %d weapon aliases.", g_weaponAliases.Length);
}

void LoadAttributeMappings()
{
    char filePath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, filePath, sizeof(filePath), "configs/hu_alias_list.txt");

    if (!FileExists(filePath))
    {
        PrintToServer("[Hyper Upgrades] hu_alias_list.txt not found.");
        return;
    }

    Handle file = OpenFile(filePath, "r");
    if (file == null)
    {
        PrintToServer("[Hyper Upgrades] Failed to open hu_alias_list.txt.");
        return;
    }

    char line[256];

    while (!IsEndOfFile(file) && ReadFileLine(file, line, sizeof(line)))
    {
        TrimString(line);

        if (line[0] == '\0' || StrContains(line, "//") == 0)
            continue;

        char parts[2][128];
        int count = ExplodeString(line, ",", parts, sizeof(parts), sizeof(parts[]));

        if (count == 2)
        {
            TrimString(parts[0]);
            TrimString(parts[1]);

            AttributeMapping mapping;
            strcopy(mapping.alias, sizeof(mapping.alias), parts[0]);
            strcopy(mapping.attributeName, sizeof(mapping.attributeName), parts[1]);

            g_attributeMappings.PushArray(mapping);
        }
    }

    CloseHandle(file);

    PrintToServer("[Hyper Upgrades] Loaded %d attribute mappings.", g_attributeMappings.Length);
}


bool GetWeaponAlias(int defindex, char[] alias, int maxlen)
{
    for (int i = 0; i < g_weaponAliases.Length; i++)
    {
        WeaponAlias weapon;
        g_weaponAliases.GetArray(i, weapon);

        if (weapon.defindex == defindex)
        {
            strcopy(alias, maxlen, weapon.alias);
            PrintToServer("[Debug] Retrieved alias: %s", alias);
            return true;
        }
    }

    return false; // Alias not found
}

int GetPlayerBalance(int client)
{
    return GetConVarInt(g_hMoneyPool) - g_iMoneySpent[client];
}

void ShowCategoryMenu(int client, const char[] category)
{
    char filePath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, filePath, sizeof(filePath), "configs/hu_attributes.cfg");

    KeyValues kv = new KeyValues("Upgrades");
    if (!kv.ImportFromFile(filePath))
    {
        PrintToChat(client, "[Hyper Upgrades] Failed to load attributes config.");
        delete kv;
        return;
    }

    char alias[64];
    bool aliasFound = false;

    if (StrEqual(category, "Body Upgrades"))
    {
        GetBodyAlias(client, alias, sizeof(alias));
        aliasFound = true; // We assume body upgrades always resolve to a valid alias
    }
    else if (StrEqual(category, "Primary Upgrades"))
    {
        int weapon = GetPlayerWeaponSlot(client, 0);
        if (IsValidEntity(weapon))
        {
            int defindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
            aliasFound = GetWeaponAlias(defindex, alias, sizeof(alias));
        }
    }
    else if (StrEqual(category, "Secondary Upgrades"))
    {
        int weapon = GetPlayerWeaponSlot(client, 1);
        if (IsValidEntity(weapon))
        {
            int defindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
            aliasFound = GetWeaponAlias(defindex, alias, sizeof(alias));
        }
    }
    else if (StrEqual(category, "Melee Upgrades"))
    {
        int weapon = GetPlayerWeaponSlot(client, 2);
        if (IsValidEntity(weapon))
        {
            int defindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
            aliasFound = GetWeaponAlias(defindex, alias, sizeof(alias));
        }
    }

    if (!aliasFound || StrEqual(alias, "unknown"))
    {
        PrintToChat(client, "[Hyper Upgrades] No upgrades found for this category.");
        delete kv;
        return;
    }

    // Store selections immediately after alias selection
    strcopy(g_sPlayerCategory[client], sizeof(g_sPlayerCategory[]), category);
    strcopy(g_sPlayerAlias[client], sizeof(g_sPlayerAlias[]), alias);
    g_bPlayerBrowsing[client] = true;

    PrintToServer("[Debug] Showing upgrades for category: %s | alias: %s", g_sPlayerCategory[client], g_sPlayerAlias[client]);

    if (!kv.JumpToKey(category, false))
    {
        PrintToChat(client, "[Hyper Upgrades] No upgrades found for this category.");
        delete kv;
        return;
    }

    if (!kv.JumpToKey(alias, false))
    {
        PrintToChat(client, "[Hyper Upgrades] No upgrades found for this item.");
        delete kv;
        return;
    }

    Menu submenu = new Menu(MenuHandler_Submenu);
    submenu.SetTitle("%s \nBalance: %d/%d$", category, GetPlayerBalance(client), GetConVarInt(g_hMoneyPool));

    kv.GotoFirstSubKey(false);
    do
    {
        char sectionName[64];
        kv.GetSectionName(sectionName, sizeof(sectionName));
        submenu.AddItem(sectionName, sectionName);
    }
    while (kv.GotoNextKey(false));

    submenu.ExitBackButton = true;
    submenu.Display(client, MENU_TIME_FOREVER);

    delete kv;
}



public int MenuHandler_Submenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char upgradeGroup[64];
        menu.GetItem(item, upgradeGroup, sizeof(upgradeGroup));

        // Load the upgrades in the selected group
        ShowUpgradeListMenu(client, upgradeGroup);
    }
    else if (action == MenuAction_Cancel)
    {
        if (item == MenuCancel_ExitBack)
        {
            // Go back to the main category menu
            ShowMainMenu(client);
        }
    }

    return 0;
}


// Helper to get body alias by class
void GetBodyAlias(int client, char[] alias, int maxlen)
{
    int class = TF2_GetPlayerClass(client);

    switch (class)
    {
        case TFClass_Scout: strcopy(alias, maxlen, "body_scout");
        case TFClass_Soldier: strcopy(alias, maxlen, "body_soldier");
        case TFClass_Pyro: strcopy(alias, maxlen, "body_pyro");
        case TFClass_DemoMan: strcopy(alias, maxlen, "body_demoman");
        case TFClass_Heavy: strcopy(alias, maxlen, "body_heavy");
        case TFClass_Engineer: strcopy(alias, maxlen, "body_engineer");
        case TFClass_Medic: strcopy(alias, maxlen, "body_medic");
        case TFClass_Sniper: strcopy(alias, maxlen, "body_sniper");
        case TFClass_Spy: strcopy(alias, maxlen, "body_spy");
        default: strcopy(alias, maxlen, "unknown");
    }
}

public int MenuHandler_UpgradeMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char upgradeAlias[64];
        menu.GetItem(item, upgradeAlias, sizeof(upgradeAlias));

        // PrintToChat(client, "[Hyper Upgrades] You selected upgrade: %s", upgradeAlias);

        // Load the upgrade config
        char upgradesFile[PLATFORM_MAX_PATH];
        BuildPath(Path_SM, upgradesFile, sizeof(upgradesFile), "configs/hu_upgrades.cfg");

        KeyValues kvUpgrades = new KeyValues("Upgrades");
        if (!kvUpgrades.ImportFromFile(upgradesFile))
        {
            PrintToChat(client, "[Hyper Upgrades] Failed to load upgrades config.");
            delete kvUpgrades;
            return 0;
        }

        if (!kvUpgrades.JumpToKey(upgradeAlias, false))
        {
            PrintToChat(client, "[Hyper Upgrades] Upgrade not found.");
            delete kvUpgrades;
            return 0;
        }

        float baseCost = kvUpgrades.GetFloat("BaseCost", 100.0);
        float costMultiplier = kvUpgrades.GetFloat("CostMultiplier", 1.5);
        float increment = kvUpgrades.GetFloat("Increment", 0.1);

        // Get current level and cost
        float currentLevel = GetPlayerUpgradeLevel(client, upgradeAlias);
        float currentCost = baseCost * Pow(costMultiplier, currentLevel / increment);

        if (g_iMoneySpent[client] + RoundToNearest(currentCost) > GetConVarInt(g_hMoneyPool))
        {
            PrintToChat(client, "[Hyper Upgrades] Not enough money to buy this upgrade.");
            delete kvUpgrades;
            return 0;
        }

        // Apply the upgrade
        float newLevel = currentLevel + increment;
        KvSetNum(g_hPlayerUpgrades[client], upgradeAlias, RoundToNearest(newLevel * 1000.0)); // Store as int * 1000
        // Actually apply the upgrade effects
        ApplyPlayerUpgrades(client);
        

        // Deduct money
        g_iMoneySpent[client] += RoundToNearest(currentCost);

        // Feedback
        PrintToConsole(client, "[Hyper Upgrades] Purchased upgrade: %s (+%.2f). Cost: %.0f$", upgradeAlias, increment, currentCost);

        // Reload menu to refresh display
        ShowUpgradeListMenu(client, g_sPlayerUpgradeGroup[client]);

        delete kvUpgrades;
    }
    else if (action == MenuAction_Cancel)
    {
        if (item == MenuCancel_ExitBack)
        {
            ShowCategoryMenu(client, g_sPlayerCategory[client]);
        }
    }
    return 0;
}

void ShowUpgradeListMenu(int client, const char[] upgradeGroup)
{
    if (!g_bPlayerBrowsing[client])
        return;

    // Load hu_attributes.cfg to find the upgrades in the selected group
    char attrFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, attrFile, sizeof(attrFile), "configs/hu_attributes.cfg");

    KeyValues kv = new KeyValues("Upgrades");
    if (!kv.ImportFromFile(attrFile))
    {
        PrintToChat(client, "[Hyper Upgrades] Failed to load attributes config.");
        delete kv;
        return;
    }

    // Jump to the correct location: Category -> Alias -> Group
    if (!kv.JumpToKey(g_sPlayerCategory[client], false) ||
        !kv.JumpToKey(g_sPlayerAlias[client], false) ||
        !kv.JumpToKey(upgradeGroup, false))
    {
        PrintToChat(client, "[Hyper Upgrades] No upgrades found for this item.");
        delete kv;
        return;
    }

    // Build the upgrade menu
    Menu upgradeMenu = new Menu(MenuHandler_UpgradeMenu);
    upgradeMenu.SetTitle("%s - %s\nBalance: %d/%d$", g_sPlayerCategory[client], upgradeGroup, GetPlayerBalance(client), GetConVarInt(g_hMoneyPool));

    bool bFoundUpgrades = false;

    kv.GotoFirstSubKey(false);
    do
    {
        char upgradeIndex[8];
        kv.GetSectionName(upgradeIndex, sizeof(upgradeIndex));

        char upgradeAlias[64];
        kv.GetString(NULL_STRING, upgradeAlias, sizeof(upgradeAlias)); // value is the alias

        // Load hu_upgrades.cfg to get the upgrade name
        char upgradesFile[PLATFORM_MAX_PATH];
        BuildPath(Path_SM, upgradesFile, sizeof(upgradesFile), "configs/hu_upgrades.cfg");

        KeyValues kvUpgrades = new KeyValues("Upgrades");
        if (!kvUpgrades.ImportFromFile(upgradesFile))
        {
            delete kvUpgrades;
            continue;
        }

        if (kvUpgrades.JumpToKey(upgradeAlias, false))
        {
            char upgradeName[64];
            kvUpgrades.GetString("Name", upgradeName, sizeof(upgradeName));

            // Retrieve upgrade details
            float baseCost = kvUpgrades.GetFloat("BaseCost", 100.0); // Default to 100 if not defined
            float costMultiplier = kvUpgrades.GetFloat("CostMultiplier", 1.5); // Default to 1.5 if not defined
            float increment = kvUpgrades.GetFloat("Increment", 0.1); // Default to 0.1 if not defined

            float currentLevel = GetPlayerUpgradeLevel(client, upgradeAlias);

            // Calculate how many times the upgrade was purchased
            int purchases = RoundToFloor(currentLevel / increment);

            // New linear cost formula
            float currentCost = baseCost + (baseCost * costMultiplier * float(purchases));

            // Build display string
            char display[128];
            Format(display, sizeof(display), "%s (%.2f) %.0f$", upgradeName, currentLevel, currentCost);

            upgradeMenu.AddItem(upgradeAlias, display);
            bFoundUpgrades = true;
        }

        delete kvUpgrades;

    } while (kv.GotoNextKey(false));

    if (!bFoundUpgrades)
    {
        PrintToChat(client, "[Hyper Upgrades] No upgrades available in this group.");
        delete kv;
        delete upgradeMenu;
        return;
    }

    upgradeMenu.ExitBackButton = true;
    upgradeMenu.Display(client, MENU_TIME_FOREVER);

    delete kv;

    strcopy(g_sPlayerUpgradeGroup[client], sizeof(g_sPlayerUpgradeGroup[]), upgradeGroup);
}

float GetPlayerUpgradeLevel(int client, const char[] alias)
{
    if (g_hPlayerUpgrades[client] == null)
        return 0.0;

    KvRewind(g_hPlayerUpgrades[client]);
    int storedLevel = KvGetNum(g_hPlayerUpgrades[client], alias, 0);

    return float(storedLevel) / 1000.0;
}

bool GetAttributeName(const char[] alias, char[] attributeName, int maxlen)
{
    for (int i = 0; i < g_attributeMappings.Length; i++)
    {
        AttributeMapping mapping;
        g_attributeMappings.GetArray(i, mapping);

        if (StrEqual(mapping.alias, alias))
        {
            strcopy(attributeName, maxlen, mapping.attributeName);
            return true;
        }
    }

    return false;
}

void ApplyPlayerUpgrades(int client)
{
    if (g_hPlayerUpgrades[client] == null)
        return;

    KvRewind(g_hPlayerUpgrades[client]);

    if (!KvGotoFirstSubKey(g_hPlayerUpgrades[client], false))
        return;

    do
    {
        char upgradeAlias[64];
        KvGetSectionName(g_hPlayerUpgrades[client], upgradeAlias, sizeof(upgradeAlias));

        // Retrieve the upgrade level (stored as int * 1000)
        int storedLevel = KvGetNum(g_hPlayerUpgrades[client], NULL_STRING, 0);
        float level = float(storedLevel) / 1000.0;

        // Load the upgrade definition
        char upgradesFile[PLATFORM_MAX_PATH];
        BuildPath(Path_SM, upgradesFile, sizeof(upgradesFile), "configs/hu_upgrades.cfg");

        KeyValues kvUpgrades = new KeyValues("Upgrades");
        if (!kvUpgrades.ImportFromFile(upgradesFile))
        {
            delete kvUpgrades;
            continue;
        }

        if (!kvUpgrades.JumpToKey(upgradeAlias, false))
        {
            delete kvUpgrades;
            continue;
        }

        // Load initial value from config (default to 0.0 if not present)
        float initValue = KvGetFloat(kvUpgrades, "InitValue", 0.0);

        // Final value to apply
        float flevel = initValue + level;

        int weaponSlot = KvGetNum(kvUpgrades, "Slot", -1); // -1 for body upgrades
        bool isBodyUpgrade = (weaponSlot == -1);

        delete kvUpgrades;

        // Lookup the attribute name using the alias mapping
        char attributeName[128];
        if (!GetAttributeName(upgradeAlias, attributeName, sizeof(attributeName)))
        {
            PrintToServer("[Hyper Upgrades] Could not find attribute name for alias: %s", upgradeAlias);
            continue;
        }

        // Apply the attribute to the player or weapon
        if (isBodyUpgrade)
        {
            TF2Attrib_SetByName(client, attributeName, flevel);
        }
        else
        {
            int weapon = GetPlayerWeaponSlot(client, weaponSlot);
            if (IsValidEntity(weapon))
            {
                TF2Attrib_SetByName(weapon, attributeName, flevel);
            }
        }

    } while (KvGotoNextKey(g_hPlayerUpgrades[client], false));

    KvRewind(g_hPlayerUpgrades[client]);

    PrintToConsole(client, "[Hyper Upgrades] Your upgrades have been applied.");
}


public Action Command_AddMoney(int client, int args)
{
    if (args < 1) return Plugin_Handled;

    char arg[16];
    GetCmdArg(1, arg, sizeof(arg));
    int amount = StringToInt(arg);

    SetConVarInt(g_hMoneyPool, GetConVarInt(g_hMoneyPool) + amount);

    return Plugin_Handled;
}

public Action Command_SubtractMoney(int client, int args)
{
    if (args < 1) return Plugin_Handled;

    char arg[16];
    GetCmdArg(1, arg, sizeof(arg));
    int amount = StringToInt(arg);

    SetConVarInt(g_hMoneyPool, GetConVarInt(g_hMoneyPool) - amount);

    return Plugin_Handled;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if (attacker <= 0 || !IsClientInGame(attacker)) return;

    int money = GetConVarInt(FindConVar("hu_money_per_kill"));
    SetConVarInt(g_hMoneyPool, GetConVarInt(g_hMoneyPool) + money);
}

public void Event_ObjectiveComplete(Event event, const char[] name, bool dontBroadcast)
{
    int money = GetConVarInt(FindConVar("hu_money_per_objective"));
    SetConVarInt(g_hMoneyPool, GetConVarInt(g_hMoneyPool) + money);
}



void GenerateConfigFiles()
{
    char filePath[PLATFORM_MAX_PATH];

    // Generate hu_alias_list.txt
    BuildPath(Path_SM, filePath, sizeof(filePath), "configs/%s", CONFIG_ALIAS);
    if (!FileExists(filePath))
    {
        Handle file = OpenFile(filePath, "w");
        if (file != null)
        {
            // alias,attribute name
            
            WriteFileLine(file, "health_upgrade,max health additive bonus");
            WriteFileLine(file, "health_regen,health regen");
            WriteFileLine(file, "damage_reduction_fire,damage vulnerability multiplier: fire");
            WriteFileLine(file, "damage_reduction_crit,damage vulnerability multiplier: crit");
            WriteFileLine(file, "damage_reduction_blast,damage vulnerability multiplier: blast");
            WriteFileLine(file, "damage_reduction_bullet,damage vulnerability multiplier: bullet");
            WriteFileLine(file, "damage_reduction_melee,damage vulnerability multiplier: melee");
            WriteFileLine(file, "damage_reduction_sentry,damage from sentry reduced");
            WriteFileLine(file, "damage_reduction_ranged,damage vulnerability multiplier: ranged");
            WriteFileLine(file, "damage_reduction_all,damage vulnerability multiplier");
            WriteFileLine(file, "backstab_resistance,backstab vulnerability multiplier");
            WriteFileLine(file, "headshot_resistance,headshot vulnerability multiplier");
            WriteFileLine(file, "healthpack_bonus,increased health from healers");
            WriteFileLine(file, "healing_received_bonus,mult healing received");
            WriteFileLine(file, "movement_speed,move speed bonus");
            WriteFileLine(file, "jump_height,mod jump height");
            WriteFileLine(file, "air_dash,increased jump air dash count");
            WriteFileLine(file, "deploy_speed,deploy time decreased");
            WriteFileLine(file, "knockback_resistance,damage force reduction");
            WriteFileLine(file, "airblast_resistance,airblast vulnerability multiplier");
            WriteFileLine(file, "fall_damage_resistance,fall damage reduction");
            WriteFileLine(file, "gesture_speed,gesture speed increase");
            WriteFileLine(file, "parachute,parachute attribute");
            WriteFileLine(file, "redeploy_parachute,parachute redeploy attribute");
            WriteFileLine(file, "air_control,air control bonus");
            WriteFileLine(file, "capture_value,capture value bonus");
            WriteFileLine(file, "see_enemy_health,see enemy health");
            WriteFileLine(file, "primary_ammo,maxammo primary increased");
            WriteFileLine(file, "secondary_ammo,maxammo secondary increased");
            WriteFileLine(file, "metal_max,maxammo metal increased");
            WriteFileLine(file, "ammo_regen,ammoregen");
            WriteFileLine(file, "metal_regen,metal regen");
            WriteFileLine(file, "cloak_consume,cloak consume rate decreased");
            WriteFileLine(file, "cloak_rate,cloak regen rate increased");
            WriteFileLine(file, "decloak_rate,decloak rate increased");
            WriteFileLine(file, "disguise_speed,disguise speed increased");
            WriteFileLine(file, "damage_bonus,damage bonus");
            WriteFileLine(file, "heal_on_hit,add onhit addhealth");
            WriteFileLine(file, "heal_on_kill,add onkill addhealth");
            WriteFileLine(file, "slow_enemy,slow enemy on hit");
            WriteFileLine(file, "minicrits_become_crits,minicrits become crits");
            WriteFileLine(file, "minicrits_airborn,mod mini-crit airborne deploy");
            WriteFileLine(file, "reveal_cloak,reveal cloaked victim");
            WriteFileLine(file, "reveal_disguise,reveal disguised victim");
            WriteFileLine(file, "damage_vs_building,damage bonus vs buildings");
            WriteFileLine(file, "damage_vs_sapper,damage versus sappers");
            WriteFileLine(file, "attack_speed,fire rate bonus");
            WriteFileLine(file, "reload_speed,reload time decreased");
            WriteFileLine(file, "melee_range,melee bounds multiplier");
            WriteFileLine(file, "crit_on_kill,crit on kill");
            WriteFileLine(file, "crit_from_behind,crit from behind");
            WriteFileLine(file, "speed_buff_ally,speed buff ally on hit");
            WriteFileLine(file, "mark_for_death,mark for death on hit");
            WriteFileLine(file, "repair_rate,repair rate bonus");
            WriteFileLine(file, "sentry_fire_rate,sentry fire rate bonus");
            WriteFileLine(file, "sentry_damage,sentry damage bonus");
            WriteFileLine(file, "sentry_ammo,sentry max ammo bonus");
            WriteFileLine(file, "sentry_radius,sentry radius bonus");
            WriteFileLine(file, "building_deploy_speed,building deploy time decreased");
            WriteFileLine(file, "teleporter_bidirectional,bidirectional teleporter");
            WriteFileLine(file, "dispenser_range,dispenser radius increased");
            WriteFileLine(file, "dispenser_metal,dispenser ammo bonus");
            WriteFileLine(file, "damage_falloff,damage falloff reduced");
            WriteFileLine(file, "self_push_bonus,self blast impulse scale");
            WriteFileLine(file, "clip_size,clip size bonus");
            WriteFileLine(file, "projectile_speed,projectile speed bonus");
            WriteFileLine(file, "self_blast_immunity,self blast dmg reduced");
            WriteFileLine(file, "rocket_jump_reduction,rocket jump damage reduction");
            WriteFileLine(file, "blast_radius,blast radius increased");
            WriteFileLine(file, "blast_push,blast force increase");
            WriteFileLine(file, "grenades_no_bounce,grenades no bounce");
            WriteFileLine(file, "damage_causes_airblast,damage causes airblast");
            WriteFileLine(file, "remove_hit_self,remove hit self on miss");
            WriteFileLine(file, "bleed_duration,bleed duration bonus");
            WriteFileLine(file, "ignite_on_hit,ignite on hit");
            WriteFileLine(file, "afterburn_damage,afterburn damage bonus");
            WriteFileLine(file, "afterburn_duration,afterburn duration bonus");
            WriteFileLine(file, "accurate_damage_bonus,accurate damage bonus");
            WriteFileLine(file, "weapon_spread,weapon spread bonus");
            WriteFileLine(file, "attack_projectile,attack projectiles");
            WriteFileLine(file, "projectile_penetration,projectile penetration");
            WriteFileLine(file, "bullets_per_shot,bullets per shot bonus");
            WriteFileLine(file, "minigun_spinup,minigun spinup time reduced");
            WriteFileLine(file, "rage_on_damage,rage on damage");
            WriteFileLine(file, "rage_duration,rage duration bonus");
            WriteFileLine(file, "banner_duration,banner duration bonus");
            WriteFileLine(file, "uber_on_hit,add uber on hit");
            WriteFileLine(file, "heal_rate_bonus,heal rate bonus");
            WriteFileLine(file, "overheal_bonus,overheal bonus");
            WriteFileLine(file, "uber_rate_bonus,ubercharge rate bonus");
            WriteFileLine(file, "uber_duration,uber duration bonus");
            WriteFileLine(file, "shield_level,shield level");
            WriteFileLine(file, "shield_duration,shield duration bonus");
            WriteFileLine(file, "flame_life_bonus,flame life bonus");
            WriteFileLine(file, "airblast_refire,airblast refire time decreased");
            WriteFileLine(file, "airblast_push_force,airblast pushback scale");
            WriteFileLine(file, "airblast_size,airblast size bonus");
            WriteFileLine(file, "airblast_ammo_cost,airblast ammo cost reduced");
            WriteFileLine(file, "flame_ammo_cost,flame ammo cost reduced");
            WriteFileLine(file, "rage_from_flames,add rage on flame hit");
            WriteFileLine(file, "full_charge_damage,full charge damage bonus");
            WriteFileLine(file, "headshot_damage_bonus,headshot damage bonus");
            WriteFileLine(file, "explosive_headshots,explosive headshot");
            WriteFileLine(file, "sniper_charge_rate,sniper charge rate bonus");
            WriteFileLine(file, "charge_multiplier_headshot,charge multiplier after headshot");
            WriteFileLine(file, "disable_flinch,disable flinch");
            WriteFileLine(file, "aiming_movespeed,aiming move speed bonus");
            WriteFileLine(file, "minicrit_headshot,minicrit on headshot");
            WriteFileLine(file, "crit_headshot,crit on headshot");
            WriteFileLine(file, "sapper_health,sapper health bonus");
            WriteFileLine(file, "sapper_damage,sapper damage bonus");
            WriteFileLine(file, "sapper_heal,add health on sapper attach");
            WriteFileLine(file, "rocket_speed,rocket speed");
            WriteFileLine(file, "grenade_speed,grenade speed");
            WriteFileLine(file, "stickybomb_speed,stickybomb speed");
            WriteFileLine(file, "syringe_speed,syringe speed");
            WriteFileLine(file, "arrow_speed,arrow speed");
            WriteFileLine(file, "energy_ball_speed,energy ball speed");
            WriteFileLine(file, "charge_rate,shield charge rate bonus");
            WriteFileLine(file, "charge_damage,shield charge impact damage bonus");
            WriteFileLine(file, "charge_turn_rate,shield charge turn control bonus");
            WriteFileLine(file, "hit_speedboost,speed boost on hit");
            WriteFileLine(file, "lunchbox_heal_bonus,lunchbox heal amount bonus");
            WriteFileLine(file, "lunchbox_recharge,lunchbox recharge rate bonus");
            WriteFileLine(file, "slow_on_hit,slow enemy on hit");
            WriteFileLine(file, "liquid_duration,milk / jarate duration bonus");
            WriteFileLine(file, "gas_passer_explosion,gas passer explosion on ignite");
            WriteFileLine(file, "silent_killer,silent killer");
            WriteFileLine(file, "silent_uncloak,silent uncloak");
            WriteFileLine(file, "mad_milk_on_hit,mad milk on hit");
            WriteFileLine(file, "sanguisuge,backstab healing bonus");
            WriteFileLine(file, "thermal_thruster_airlaunch,thermal thruster air launch");
            WriteFileLine(file, "impact_pushback,impact pushback radius");
            WriteFileLine(file, "impact_stun,impact stun radius");
            WriteFileLine(file, "dragon_fury_recharge,dragon fury recharge rate");
            WriteFileLine(file, "building_heal_rate,building heal rate bonus");
            WriteFileLine(file, "sentry_bullet_resistance,sentry bullet resistance");
            WriteFileLine(file, "sentry_rocket_resistance,sentry rocket resistance");
            WriteFileLine(file, "sentry_flame_resistance,sentry flame resistance");
            WriteFileLine(file, "sentry_damage_resistance,sentry damage resistance");
            WriteFileLine(file, "dispenser_damage_resistance,dispenser damage resistance");
            WriteFileLine(file, "teleporter_damage_resistance,teleporter damage resistance");
            WriteFileLine(file, "bat_ball_speed,mod bat launches balls faster");
            WriteFileLine(file, "slow_on_hit_building,slow enemy on hit building");
            WriteFileLine(file, "damage_force_reduction_on_hit,damage force reduction on hit");
            WriteFileLine(file, "snare_on_hit,snare on hit");



            CloseHandle(file);
        }
    }

    // Generate hu_weapons_list.txt
    BuildPath(Path_SM, filePath, sizeof(filePath), "configs/%s", CONFIG_WEAP);
    if (!FileExists(filePath))
    {
        Handle file = OpenFile(filePath, "w");
        if (file != null)
        {


            // indexID,alias

            // Class: All/Multiple
            WriteFileLine(file, "1152,tf_weapon_grapplinghook");
            WriteFileLine(file, "1069,tf_weapon_spellbook");
            WriteFileLine(file, "1070,tf_weapon_spellbook");
            WriteFileLine(file, "1132,tf_weapon_spellbook");
            WriteFileLine(file, "5605,tf_weapon_spellbook");
            WriteFileLine(file, "30015,tf_powerup_bottle");
            WriteFileLine(file, "489,tf_powerup_bottle");

            WriteFileLine(file, "264,saxxy");
            WriteFileLine(file, "423,saxxy");
            WriteFileLine(file, "474,saxxy");
            WriteFileLine(file, "880,saxxy");
            WriteFileLine(file, "939,saxxy");
            WriteFileLine(file, "954,saxxy");
            WriteFileLine(file, "1013,saxxy");
            WriteFileLine(file, "1071,saxxy");
            WriteFileLine(file, "1123,saxxy");
            WriteFileLine(file, "1127,saxxy");
            WriteFileLine(file, "30758,saxxy");

            WriteFileLine(file, "357,tf_weapon_katana");

            WriteFileLine(file, "199,tf_weapon_shotgun");
            WriteFileLine(file, "415,tf_weapon_shotgun");
            WriteFileLine(file, "1141,tf_weapon_shotgun");
            WriteFileLine(file, "1153,tf_weapon_shotgun");
            WriteFileLine(file, "15003,tf_weapon_shotgun");
            WriteFileLine(file, "15016,tf_weapon_shotgun");
            WriteFileLine(file, "15044,tf_weapon_shotgun");
            WriteFileLine(file, "15047,tf_weapon_shotgun");
            WriteFileLine(file, "15085,tf_weapon_shotgun");
            WriteFileLine(file, "15109,tf_weapon_shotgun");
            WriteFileLine(file, "15132,tf_weapon_shotgun");
            WriteFileLine(file, "15133,tf_weapon_shotgun");
            WriteFileLine(file, "15152,tf_weapon_shotgun");

            WriteFileLine(file, "1101,tf_weapon_parachute");
            WriteFileLine(file, "160,tf_weapon_pistol");
            WriteFileLine(file, "209,tf_weapon_pistol");
            WriteFileLine(file, "294,tf_weapon_pistol");
            WriteFileLine(file, "15013,tf_weapon_pistol");
            WriteFileLine(file, "15018,tf_weapon_pistol");
            WriteFileLine(file, "15035,tf_weapon_pistol");
            WriteFileLine(file, "15041,tf_weapon_pistol");
            WriteFileLine(file, "15046,tf_weapon_pistol");
            WriteFileLine(file, "15056,tf_weapon_pistol");
            WriteFileLine(file, "15060,tf_weapon_pistol");
            WriteFileLine(file, "15061,tf_weapon_pistol");
            WriteFileLine(file, "15100,tf_weapon_pistol");
            WriteFileLine(file, "15101,tf_weapon_pistol");
            WriteFileLine(file, "15102,tf_weapon_pistol");
            WriteFileLine(file, "15126,tf_weapon_pistol");
            WriteFileLine(file, "15148,tf_weapon_pistol");
            WriteFileLine(file, "30666,tf_weapon_pistol");

            // Class: Scout, Slot: 0
            WriteFileLine(file, "13,tf_weapon_scattergun");
            WriteFileLine(file, "200,tf_weapon_scattergun");
            WriteFileLine(file, "45,tf_weapon_scattergun");
            WriteFileLine(file, "220,tf_weapon_handgun_scout_primary");
            WriteFileLine(file, "448,tf_weapon_soda_popper");
            WriteFileLine(file, "669,tf_weapon_scattergun");
            WriteFileLine(file, "772,tf_weapon_pep_brawler_blaster");
            WriteFileLine(file, "799,tf_weapon_scattergun");
            WriteFileLine(file, "808,tf_weapon_scattergun");
            WriteFileLine(file, "888,tf_weapon_scattergun");
            WriteFileLine(file, "897,tf_weapon_scattergun");
            WriteFileLine(file, "906,tf_weapon_scattergun");
            WriteFileLine(file, "915,tf_weapon_scattergun");
            WriteFileLine(file, "964,tf_weapon_scattergun");
            WriteFileLine(file, "973,tf_weapon_scattergun");
            WriteFileLine(file, "1078,tf_weapon_scattergun");
            WriteFileLine(file, "1103,tf_weapon_scattergun");
            WriteFileLine(file, "15002,tf_weapon_scattergun");
            WriteFileLine(file, "15015,tf_weapon_scattergun");
            WriteFileLine(file, "15021,tf_weapon_scattergun");
            WriteFileLine(file, "15029,tf_weapon_scattergun");
            WriteFileLine(file, "15036,tf_weapon_scattergun");
            WriteFileLine(file, "15053,tf_weapon_scattergun");
            WriteFileLine(file, "15065,tf_weapon_scattergun");
            WriteFileLine(file, "15069,tf_weapon_scattergun");
            WriteFileLine(file, "15106,tf_weapon_scattergun");
            WriteFileLine(file, "15107,tf_weapon_scattergun");
            WriteFileLine(file, "15108,tf_weapon_scattergun");
            WriteFileLine(file, "15131,tf_weapon_scattergun");
            WriteFileLine(file, "15151,tf_weapon_scattergun");
            WriteFileLine(file, "15157,tf_weapon_scattergun");

            // Class: Scout, Slot: 1
            WriteFileLine(file, "23,tf_weapon_pistol");
            WriteFileLine(file, "46,tf_weapon_lunchbox_drink");
            WriteFileLine(file, "163,tf_weapon_lunchbox_drink");
            WriteFileLine(file, "222,tf_weapon_jar_milk");
            WriteFileLine(file, "449,tf_weapon_handgun_scout_secondary");
            WriteFileLine(file, "773,tf_weapon_handgun_scout_secondary");
            WriteFileLine(file, "812,tf_weapon_cleaver");
            WriteFileLine(file, "833,tf_weapon_cleaver");
            WriteFileLine(file, "1121,tf_weapon_jar_milk");
            WriteFileLine(file, "1145,tf_weapon_lunchbox_drink");

            // Class: Scout, Slot: 2
            WriteFileLine(file, "0,tf_weapon_bat");
            WriteFileLine(file, "190,tf_weapon_bat");
            WriteFileLine(file, "44,tf_weapon_bat_wood");
            WriteFileLine(file, "221,tf_weapon_bat_fish");
            WriteFileLine(file, "317,tf_weapon_bat");
            WriteFileLine(file, "325,tf_weapon_bat");
            WriteFileLine(file, "349,tf_weapon_bat");
            WriteFileLine(file, "355,tf_weapon_bat");
            WriteFileLine(file, "450,tf_weapon_bat");
            WriteFileLine(file, "452,tf_weapon_bat");
            WriteFileLine(file, "572,tf_weapon_bat_fish");
            WriteFileLine(file, "648,tf_weapon_bat_giftwrap");
            WriteFileLine(file, "660,tf_weapon_bat");
            WriteFileLine(file, "999,tf_weapon_bat_fish");
            WriteFileLine(file, "30667,tf_weapon_bat");

            // Class: Soldier, Slot: 0
            WriteFileLine(file, "18,tf_weapon_rocketlauncher");
            WriteFileLine(file, "205,tf_weapon_rocketlauncher");
            WriteFileLine(file, "127,tf_weapon_rocketlauncher_directhit");
            WriteFileLine(file, "228,tf_weapon_rocketlauncher");
            WriteFileLine(file, "237,tf_weapon_rocketlauncher");
            WriteFileLine(file, "414,tf_weapon_rocketlauncher");
            WriteFileLine(file, "441,tf_weapon_particle_cannon");
            WriteFileLine(file, "513,tf_weapon_rocketlauncher");
            WriteFileLine(file, "658,tf_weapon_rocketlauncher");
            WriteFileLine(file, "730,tf_weapon_rocketlauncher");
            WriteFileLine(file, "800,tf_weapon_rocketlauncher");
            WriteFileLine(file, "809,tf_weapon_rocketlauncher");
            WriteFileLine(file, "889,tf_weapon_rocketlauncher");
            WriteFileLine(file, "898,tf_weapon_rocketlauncher");
            WriteFileLine(file, "907,tf_weapon_rocketlauncher");
            WriteFileLine(file, "916,tf_weapon_rocketlauncher");
            WriteFileLine(file, "965,tf_weapon_rocketlauncher");
            WriteFileLine(file, "974,tf_weapon_rocketlauncher");
            WriteFileLine(file, "1085,tf_weapon_rocketlauncher");
            WriteFileLine(file, "1104,tf_weapon_rocketlauncher_airstrike");
            WriteFileLine(file, "15006,tf_weapon_rocketlauncher");
            WriteFileLine(file, "15014,tf_weapon_rocketlauncher");
            WriteFileLine(file, "15028,tf_weapon_rocketlauncher");
            WriteFileLine(file, "15043,tf_weapon_rocketlauncher");
            WriteFileLine(file, "15052,tf_weapon_rocketlauncher");
            WriteFileLine(file, "15057,tf_weapon_rocketlauncher");
            WriteFileLine(file, "15081,tf_weapon_rocketlauncher");
            WriteFileLine(file, "15104,tf_weapon_rocketlauncher");
            WriteFileLine(file, "15105,tf_weapon_rocketlauncher");
            WriteFileLine(file, "15129,tf_weapon_rocketlauncher");
            WriteFileLine(file, "15130,tf_weapon_rocketlauncher");
            WriteFileLine(file, "15150,tf_weapon_rocketlauncher");

            // Class: Soldier, Slot: 1
            WriteFileLine(file, "10,tf_weapon_shotgun_soldier");
            WriteFileLine(file, "442,tf_weapon_raygun");

            // Class: Soldier, Slot: 2
            WriteFileLine(file, "6,tf_weapon_shovel");
            WriteFileLine(file, "196,tf_weapon_shovel");
            WriteFileLine(file, "128,tf_weapon_shovel");
            WriteFileLine(file, "154,tf_weapon_shovel");
            WriteFileLine(file, "416,tf_weapon_shovel");
            WriteFileLine(file, "447,tf_weapon_shovel");
            WriteFileLine(file, "775,tf_weapon_shovel");

            // Class: Soldier, Wearables
            WriteFileLine(file, "129,tf_weapon_buff_item"); // Buff Banner
            WriteFileLine(file, "226,tf_weapon_buff_item"); // Battalion's Backup
            WriteFileLine(file, "354,tf_weapon_buff_item"); // Concheror
            WriteFileLine(file, "1001,tf_weapon_buff_item"); // Festive Buff Banner
            WriteFileLine(file, "133,tf_wearable"); // Gunboats
            WriteFileLine(file, "444,tf_wearable"); // Mantreads

            // Class: Pyro, Slot: 0
            WriteFileLine(file, "21,tf_weapon_flamethrower");
            WriteFileLine(file, "208,tf_weapon_flamethrower");
            WriteFileLine(file, "40,tf_weapon_flamethrower");
            WriteFileLine(file, "215,tf_weapon_flamethrower");
            WriteFileLine(file, "594,tf_weapon_flamethrower");
            WriteFileLine(file, "659,tf_weapon_flamethrower");
            WriteFileLine(file, "741,tf_weapon_flamethrower");
            WriteFileLine(file, "798,tf_weapon_flamethrower");
            WriteFileLine(file, "807,tf_weapon_flamethrower");
            WriteFileLine(file, "887,tf_weapon_flamethrower");
            WriteFileLine(file, "896,tf_weapon_flamethrower");
            WriteFileLine(file, "905,tf_weapon_flamethrower");
            WriteFileLine(file, "914,tf_weapon_flamethrower");
            WriteFileLine(file, "963,tf_weapon_flamethrower");
            WriteFileLine(file, "972,tf_weapon_flamethrower");
            WriteFileLine(file, "1146,tf_weapon_flamethrower");
            WriteFileLine(file, "1178,tf_weapon_rocketlauncher_fireball");
            WriteFileLine(file, "15005,tf_weapon_flamethrower");
            WriteFileLine(file, "15017,tf_weapon_flamethrower");
            WriteFileLine(file, "15030,tf_weapon_flamethrower");
            WriteFileLine(file, "15034,tf_weapon_flamethrower");
            WriteFileLine(file, "15049,tf_weapon_flamethrower");
            WriteFileLine(file, "15054,tf_weapon_flamethrower");
            WriteFileLine(file, "15066,tf_weapon_flamethrower");
            WriteFileLine(file, "15067,tf_weapon_flamethrower");
            WriteFileLine(file, "15068,tf_weapon_flamethrower");
            WriteFileLine(file, "15089,tf_weapon_flamethrower");
            WriteFileLine(file, "15090,tf_weapon_flamethrower");
            WriteFileLine(file, "15115,tf_weapon_flamethrower");
            WriteFileLine(file, "15141,tf_weapon_flamethrower");
            WriteFileLine(file, "30474,tf_weapon_flamethrower");

            // Class: Pyro, Slot: 1
            WriteFileLine(file, "12,tf_weapon_shotgun_pyro");
            WriteFileLine(file, "39,tf_weapon_flaregun");
            WriteFileLine(file, "351,tf_weapon_flaregun");
            WriteFileLine(file, "595,tf_weapon_flaregun_revenge");
            WriteFileLine(file, "740,tf_weapon_flaregun");
            WriteFileLine(file, "1081,tf_weapon_flaregun");
            WriteFileLine(file, "1179,tf_weapon_rocketpack");
            WriteFileLine(file, "1180,tf_weapon_jar_gas");

            // Class: Pyro, Slot: 2
            WriteFileLine(file, "2,tf_weapon_fireaxe");
            WriteFileLine(file, "192,tf_weapon_fireaxe");
            WriteFileLine(file, "38,tf_weapon_fireaxe");
            WriteFileLine(file, "153,tf_weapon_fireaxe");
            WriteFileLine(file, "214,tf_weapon_fireaxe");
            WriteFileLine(file, "326,tf_weapon_fireaxe");
            WriteFileLine(file, "348,tf_weapon_fireaxe");
            WriteFileLine(file, "457,tf_weapon_fireaxe");
            WriteFileLine(file, "466,tf_weapon_fireaxe");
            WriteFileLine(file, "593,tf_weapon_fireaxe");
            WriteFileLine(file, "739,tf_weapon_fireaxe");
            WriteFileLine(file, "813,tf_weapon_breakable_sign");
            WriteFileLine(file, "834,tf_weapon_breakable_sign");
            WriteFileLine(file, "1000,tf_weapon_fireaxe");
            WriteFileLine(file, "1181,tf_weapon_slap");

            // Class: Demoman, Slot: 0
            WriteFileLine(file, "19,tf_weapon_grenadelauncher");
            WriteFileLine(file, "206,tf_weapon_grenadelauncher");
            WriteFileLine(file, "308,tf_weapon_grenadelauncher");
            WriteFileLine(file, "996,tf_weapon_cannon");
            WriteFileLine(file, "1007,tf_weapon_grenadelauncher");
            WriteFileLine(file, "1151,tf_weapon_grenadelauncher");
            WriteFileLine(file, "15077,tf_weapon_grenadelauncher");
            WriteFileLine(file, "15079,tf_weapon_grenadelauncher");
            WriteFileLine(file, "15091,tf_weapon_grenadelauncher");
            WriteFileLine(file, "15092,tf_weapon_grenadelauncher");
            WriteFileLine(file, "15116,tf_weapon_grenadelauncher");
            WriteFileLine(file, "15117,tf_weapon_grenadelauncher");
            WriteFileLine(file, "15142,tf_weapon_grenadelauncher");
            WriteFileLine(file, "15158,tf_weapon_grenadelauncher");
            WriteFileLine(file, "405,tf_wearable");
            WriteFileLine(file, "608,tf_wearable");

            // Class: Demoman, Slot: 1
            WriteFileLine(file, "20,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "207,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "130,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "131,tf_wearable_demoshield");
            WriteFileLine(file, "265,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "406,tf_wearable_demoshield");
            WriteFileLine(file, "661,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "797,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "806,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "886,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "895,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "904,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "913,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "962,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "971,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "1099,tf_wearable_demoshield");
            WriteFileLine(file, "1144,tf_wearable_demoshield");
            WriteFileLine(file, "1150,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "15009,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "15012,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "15024,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "15038,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "15045,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "15048,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "15082,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "15083,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "15084,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "15113,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "15137,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "15138,tf_weapon_pipebomblauncher");
            WriteFileLine(file, "15155,tf_weapon_pipebomblauncher");

            // Class: Demoman, Slot: 2
            WriteFileLine(file, "1,tf_weapon_bottle");
            WriteFileLine(file, "191,tf_weapon_bottle");
            WriteFileLine(file, "132,tf_weapon_sword");
            WriteFileLine(file, "172,tf_weapon_sword");
            WriteFileLine(file, "266,tf_weapon_sword");
            WriteFileLine(file, "307,tf_weapon_stickbomb");
            WriteFileLine(file, "327,tf_weapon_sword");
            WriteFileLine(file, "404,tf_weapon_sword");
            WriteFileLine(file, "482,tf_weapon_sword");
            WriteFileLine(file, "609,tf_weapon_bottle");
            WriteFileLine(file, "1082,tf_weapon_sword");

            // Class: Heavy, Slot: 0
            WriteFileLine(file, "15,tf_weapon_minigun");
            WriteFileLine(file, "202,tf_weapon_minigun");
            WriteFileLine(file, "41,tf_weapon_minigun");
            WriteFileLine(file, "298,tf_weapon_minigun");
            WriteFileLine(file, "312,tf_weapon_minigun");
            WriteFileLine(file, "424,tf_weapon_minigun");
            WriteFileLine(file, "654,tf_weapon_minigun");
            WriteFileLine(file, "793,tf_weapon_minigun");
            WriteFileLine(file, "802,tf_weapon_minigun");
            WriteFileLine(file, "811,tf_weapon_minigun");
            WriteFileLine(file, "832,tf_weapon_minigun");
            WriteFileLine(file, "850,tf_weapon_minigun");
            WriteFileLine(file, "882,tf_weapon_minigun");
            WriteFileLine(file, "891,tf_weapon_minigun");
            WriteFileLine(file, "900,tf_weapon_minigun");
            WriteFileLine(file, "909,tf_weapon_minigun");
            WriteFileLine(file, "958,tf_weapon_minigun");
            WriteFileLine(file, "967,tf_weapon_minigun");
            WriteFileLine(file, "15004,tf_weapon_minigun");
            WriteFileLine(file, "15020,tf_weapon_minigun");
            WriteFileLine(file, "15026,tf_weapon_minigun");
            WriteFileLine(file, "15031,tf_weapon_minigun");
            WriteFileLine(file, "15040,tf_weapon_minigun");
            WriteFileLine(file, "15055,tf_weapon_minigun");
            WriteFileLine(file, "15086,tf_weapon_minigun");
            WriteFileLine(file, "15087,tf_weapon_minigun");
            WriteFileLine(file, "15088,tf_weapon_minigun");
            WriteFileLine(file, "15098,tf_weapon_minigun");
            WriteFileLine(file, "15099,tf_weapon_minigun");
            WriteFileLine(file, "15123,tf_weapon_minigun");
            WriteFileLine(file, "15124,tf_weapon_minigun");
            WriteFileLine(file, "15125,tf_weapon_minigun");
            WriteFileLine(file, "15147,tf_weapon_minigun");

            // Class: Heavy, Slot: 1
            WriteFileLine(file, "11,tf_weapon_shotgun_hwg");
            WriteFileLine(file, "42,tf_weapon_lunchbox");
            WriteFileLine(file, "159,tf_weapon_lunchbox");
            WriteFileLine(file, "311,tf_weapon_lunchbox");
            WriteFileLine(file, "425,tf_weapon_shotgun_hwg");
            WriteFileLine(file, "433,tf_weapon_lunchbox");
            WriteFileLine(file, "863,tf_weapon_lunchbox");
            WriteFileLine(file, "1002,tf_weapon_lunchbox");
            WriteFileLine(file, "1190,tf_weapon_lunchbox");

            // Class: Heavy, Slot: 2
            WriteFileLine(file, "5,tf_weapon_fists");
            WriteFileLine(file, "195,tf_weapon_fists");
            WriteFileLine(file, "43,tf_weapon_fists");
            WriteFileLine(file, "239,tf_weapon_fists");
            WriteFileLine(file, "310,tf_weapon_fists");
            WriteFileLine(file, "331,tf_weapon_fists");
            WriteFileLine(file, "426,tf_weapon_fists");
            WriteFileLine(file, "587,tf_weapon_fists");
            WriteFileLine(file, "656,tf_weapon_fists");
            WriteFileLine(file, "1084,tf_weapon_fists");
            WriteFileLine(file, "1100,tf_weapon_fists");
            WriteFileLine(file, "1184,tf_weapon_fists");

            // Class: Engineer, Slot: 0
            WriteFileLine(file, "9,tf_weapon_shotgun_primary");
            WriteFileLine(file, "141,tf_weapon_sentry_revenge");
            WriteFileLine(file, "527,tf_weapon_shotgun_primary");
            WriteFileLine(file, "588,tf_weapon_drg_pomson");
            WriteFileLine(file, "997,tf_weapon_shotgun_building_rescue");
            WriteFileLine(file, "1004,tf_weapon_sentry_revenge");

            // Class: Engineer, Slot: 1
            WriteFileLine(file, "22,tf_weapon_pistol");
            WriteFileLine(file, "140,tf_weapon_laser_pointer");
            WriteFileLine(file, "528,tf_weapon_mechanical_arm");
            WriteFileLine(file, "1086,tf_weapon_laser_pointer");
            WriteFileLine(file, "30668,tf_weapon_laser_pointer");

            // Class: Engineer, Slot: 2
            WriteFileLine(file, "7,tf_weapon_wrench");
            WriteFileLine(file, "197,tf_weapon_wrench");
            WriteFileLine(file, "142,tf_weapon_robot_arm");
            WriteFileLine(file, "155,tf_weapon_wrench");
            WriteFileLine(file, "169,tf_weapon_wrench");
            WriteFileLine(file, "329,tf_weapon_wrench");
            WriteFileLine(file, "589,tf_weapon_wrench");
            WriteFileLine(file, "662,tf_weapon_wrench");
            WriteFileLine(file, "795,tf_weapon_wrench");
            WriteFileLine(file, "804,tf_weapon_wrench");
            WriteFileLine(file, "884,tf_weapon_wrench");
            WriteFileLine(file, "893,tf_weapon_wrench");
            WriteFileLine(file, "902,tf_weapon_wrench");
            WriteFileLine(file, "911,tf_weapon_wrench");
            WriteFileLine(file, "960,tf_weapon_wrench");
            WriteFileLine(file, "969,tf_weapon_wrench");
            WriteFileLine(file, "15073,tf_weapon_wrench");
            WriteFileLine(file, "15074,tf_weapon_wrench");
            WriteFileLine(file, "15075,tf_weapon_wrench");
            WriteFileLine(file, "15139,tf_weapon_wrench");
            WriteFileLine(file, "15140,tf_weapon_wrench");
            WriteFileLine(file, "15114,tf_weapon_wrench");
            WriteFileLine(file, "15156,tf_weapon_wrench");

            // Class: Engineer, Slot: 3
            WriteFileLine(file, "25,tf_weapon_pda_engineer_build");
            WriteFileLine(file, "737,tf_weapon_pda_engineer_build");

            // Class: Medic, Slot: 0
            WriteFileLine(file, "17,tf_weapon_syringegun_medic");
            WriteFileLine(file, "204,tf_weapon_syringegun_medic");
            WriteFileLine(file, "36,tf_weapon_syringegun_medic");
            WriteFileLine(file, "305,tf_weapon_crossbow");
            WriteFileLine(file, "412,tf_weapon_syringegun_medic");
            WriteFileLine(file, "1079,tf_weapon_crossbow");

            // Class: Medic, Slot: 1
            WriteFileLine(file, "29,tf_weapon_medigun");
            WriteFileLine(file, "211,tf_weapon_medigun");
            WriteFileLine(file, "35,tf_weapon_medigun");
            WriteFileLine(file, "411,tf_weapon_medigun");
            WriteFileLine(file, "663,tf_weapon_medigun");
            WriteFileLine(file, "796,tf_weapon_medigun");
            WriteFileLine(file, "805,tf_weapon_medigun");
            WriteFileLine(file, "885,tf_weapon_medigun");
            WriteFileLine(file, "894,tf_weapon_medigun");
            WriteFileLine(file, "903,tf_weapon_medigun");
            WriteFileLine(file, "912,tf_weapon_medigun");
            WriteFileLine(file, "961,tf_weapon_medigun");
            WriteFileLine(file, "970,tf_weapon_medigun");
            WriteFileLine(file, "15008,tf_weapon_medigun");
            WriteFileLine(file, "15010,tf_weapon_medigun");
            WriteFileLine(file, "15025,tf_weapon_medigun");
            WriteFileLine(file, "15039,tf_weapon_medigun");
            WriteFileLine(file, "15050,tf_weapon_medigun");
            WriteFileLine(file, "15078,tf_weapon_medigun");
            WriteFileLine(file, "15097,tf_weapon_medigun");
            WriteFileLine(file, "15121,tf_weapon_medigun");
            WriteFileLine(file, "15122,tf_weapon_medigun");
            WriteFileLine(file, "15123,tf_weapon_medigun");
            WriteFileLine(file, "15145,tf_weapon_medigun");
            WriteFileLine(file, "15146,tf_weapon_medigun");

            // Class: Medic, Slot: 2
            WriteFileLine(file, "8,tf_weapon_bonesaw");
            WriteFileLine(file, "198,tf_weapon_bonesaw");
            WriteFileLine(file, "37,tf_weapon_bonesaw");
            WriteFileLine(file, "173,tf_weapon_bonesaw");
            WriteFileLine(file, "304,tf_weapon_bonesaw");
            WriteFileLine(file, "413,tf_weapon_bonesaw");
            WriteFileLine(file, "1003,tf_weapon_bonesaw");
            WriteFileLine(file, "1143,tf_weapon_bonesaw");

            // Class: Sniper, Slot: 0
            WriteFileLine(file, "14,tf_weapon_sniperrifle");
            WriteFileLine(file, "201,tf_weapon_sniperrifle");
            WriteFileLine(file, "56,tf_weapon_compound_bow");
            WriteFileLine(file, "230,tf_weapon_sniperrifle");
            WriteFileLine(file, "402,tf_weapon_sniperrifle_decap");
            WriteFileLine(file, "526,tf_weapon_sniperrifle");
            WriteFileLine(file, "664,tf_weapon_sniperrifle");
            WriteFileLine(file, "752,tf_weapon_sniperrifle");
            WriteFileLine(file, "792,tf_weapon_sniperrifle");
            WriteFileLine(file, "801,tf_weapon_sniperrifle");
            WriteFileLine(file, "851,tf_weapon_sniperrifle");
            WriteFileLine(file, "881,tf_weapon_sniperrifle");
            WriteFileLine(file, "890,tf_weapon_sniperrifle");
            WriteFileLine(file, "899,tf_weapon_sniperrifle");
            WriteFileLine(file, "908,tf_weapon_sniperrifle");
            WriteFileLine(file, "957,tf_weapon_sniperrifle");
            WriteFileLine(file, "966,tf_weapon_sniperrifle");
            WriteFileLine(file, "1005,tf_weapon_compound_bow");
            WriteFileLine(file, "1092,tf_weapon_compound_bow");
            WriteFileLine(file, "1098,tf_weapon_sniperrifle_classic");
            WriteFileLine(file, "15000,tf_weapon_sniperrifle");
            WriteFileLine(file, "15007,tf_weapon_sniperrifle");
            WriteFileLine(file, "15019,tf_weapon_sniperrifle");
            WriteFileLine(file, "15023,tf_weapon_sniperrifle");
            WriteFileLine(file, "15033,tf_weapon_sniperrifle");
            WriteFileLine(file, "15059,tf_weapon_sniperrifle");
            WriteFileLine(file, "15070,tf_weapon_sniperrifle");
            WriteFileLine(file, "15071,tf_weapon_sniperrifle");
            WriteFileLine(file, "15072,tf_weapon_sniperrifle");
            WriteFileLine(file, "15111,tf_weapon_sniperrifle");
            WriteFileLine(file, "15112,tf_weapon_sniperrifle");
            WriteFileLine(file, "15135,tf_weapon_sniperrifle");
            WriteFileLine(file, "15136,tf_weapon_sniperrifle");
            WriteFileLine(file, "15154,tf_weapon_sniperrifle");
            WriteFileLine(file, "30665,tf_weapon_sniperrifle");

            // Class: Sniper, Slot: 1
            WriteFileLine(file, "16,tf_weapon_smg");
            WriteFileLine(file, "203,tf_weapon_smg");
            WriteFileLine(file, "58,tf_weapon_jar");
            WriteFileLine(file, "751,tf_weapon_charged_smg");
            WriteFileLine(file, "1083,tf_weapon_jar");
            WriteFileLine(file, "1105,tf_weapon_jar");
            WriteFileLine(file, "1149,tf_weapon_smg");
            WriteFileLine(file, "15001,tf_weapon_smg");
            WriteFileLine(file, "15022,tf_weapon_smg");
            WriteFileLine(file, "15032,tf_weapon_smg");
            WriteFileLine(file, "15037,tf_weapon_smg");
            WriteFileLine(file, "15058,tf_weapon_smg");
            WriteFileLine(file, "15076,tf_weapon_smg");
            WriteFileLine(file, "15110,tf_weapon_smg");
            WriteFileLine(file, "15134,tf_weapon_smg");
            WriteFileLine(file, "15153,tf_weapon_smg");
            WriteFileLine(file, "57,tf_wearable_razorback");
            WriteFileLine(file, "231,tf_wearable");
            WriteFileLine(file, "642,tf_wearable");

            // Class: Sniper, Slot: 2
            WriteFileLine(file, "3,tf_weapon_club");
            WriteFileLine(file, "193,tf_weapon_club");
            WriteFileLine(file, "171,tf_weapon_club");
            WriteFileLine(file, "232,tf_weapon_club");
            WriteFileLine(file, "401,tf_weapon_club");

            // Class: Spy, Slot: 0
            WriteFileLine(file, "24,tf_weapon_revolver");
            WriteFileLine(file, "210,tf_weapon_revolver");
            WriteFileLine(file, "61,tf_weapon_revolver");
            WriteFileLine(file, "161,tf_weapon_revolver");
            WriteFileLine(file, "224,tf_weapon_revolver");
            WriteFileLine(file, "460,tf_weapon_revolver");
            WriteFileLine(file, "525,tf_weapon_revolver");
            WriteFileLine(file, "1006,tf_weapon_revolver");
            WriteFileLine(file, "1142,tf_weapon_revolver");
            WriteFileLine(file, "15011,tf_weapon_revolver");
            WriteFileLine(file, "15027,tf_weapon_revolver");
            WriteFileLine(file, "15042,tf_weapon_revolver");
            WriteFileLine(file, "15051,tf_weapon_revolver");
            WriteFileLine(file, "15062,tf_weapon_revolver");
            WriteFileLine(file, "15063,tf_weapon_revolver");
            WriteFileLine(file, "15064,tf_weapon_revolver");
            WriteFileLine(file, "15103,tf_weapon_revolver");
            WriteFileLine(file, "15128,tf_weapon_revolver");
            WriteFileLine(file, "15127,tf_weapon_revolver");
            WriteFileLine(file, "15149,tf_weapon_revolver");

            // Class: Spy, Slot: 1
            WriteFileLine(file, "735,tf_weapon_builder");
            WriteFileLine(file, "736,tf_weapon_builder");
            WriteFileLine(file, "810,tf_weapon_sapper");
            WriteFileLine(file, "831,tf_weapon_sapper");
            WriteFileLine(file, "933,tf_weapon_sapper");
            WriteFileLine(file, "1080,tf_weapon_sapper");
            WriteFileLine(file, "1102,tf_weapon_sapper");

            // Class: Spy, Slot: 2
            WriteFileLine(file, "4,tf_weapon_knife");
            WriteFileLine(file, "194,tf_weapon_knife");
            WriteFileLine(file, "225,tf_weapon_knife");
            WriteFileLine(file, "356,tf_weapon_knife");
            WriteFileLine(file, "461,tf_weapon_knife");
            WriteFileLine(file, "574,tf_weapon_knife");
            WriteFileLine(file, "638,tf_weapon_knife");
            WriteFileLine(file, "649,tf_weapon_knife");
            WriteFileLine(file, "665,tf_weapon_knife");
            WriteFileLine(file, "727,tf_weapon_knife");
            WriteFileLine(file, "794,tf_weapon_knife");
            WriteFileLine(file, "803,tf_weapon_knife");
            WriteFileLine(file, "883,tf_weapon_knife");
            WriteFileLine(file, "892,tf_weapon_knife");
            WriteFileLine(file, "901,tf_weapon_knife");
            WriteFileLine(file, "910,tf_weapon_knife");
            WriteFileLine(file, "959,tf_weapon_knife");
            WriteFileLine(file, "968,tf_weapon_knife");
            WriteFileLine(file, "15062,tf_weapon_knife");
            WriteFileLine(file, "15094,tf_weapon_knife");
            WriteFileLine(file, "15095,tf_weapon_knife");
            WriteFileLine(file, "15096,tf_weapon_knife");
            WriteFileLine(file, "15118,tf_weapon_knife");
            WriteFileLine(file, "15119,tf_weapon_knife");
            WriteFileLine(file, "15143,tf_weapon_knife");
            WriteFileLine(file, "15144,tf_weapon_knife");

            // Class: Spy, Slot: 4
            WriteFileLine(file, "30,tf_weapon_invis");
            WriteFileLine(file, "212,tf_weapon_invis");
            WriteFileLine(file, "59,tf_weapon_invis");
            WriteFileLine(file, "60,tf_weapon_invis");
            WriteFileLine(file, "297,tf_weapon_invis");
            WriteFileLine(file, "947,tf_weapon_invis");

            // Fallback option for some other weapons, keep last
            WriteFileLine(file, "all,all weapons and body");
            
            CloseHandle(file);
        }
    }

    // Generate hu_upgrades.cfg
    BuildPath(Path_SM, filePath, sizeof(filePath), "configs/%s", CONFIG_UPGR);
    if (!FileExists(filePath))
    {
        Handle file = OpenFile(filePath, "w");
        if (file != null)
        {
            WriteFileLine(file, "\"Upgrades\"");
            WriteFileLine(file, "{");

            WriteFileLine(file, "\t\"health_upgrade\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"25.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"200\"");
            WriteFileLine(file, "\t\t\"Name\" \"Health Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"damage_bonus\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Damage Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"movement_speed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"2\"");
            WriteFileLine(file, "\t\t\"InitValue\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"health_regen\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"50\"");
            WriteFileLine(file, "\t\t\"Name\" \"Health Regen\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"damage_reduction_fire\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Fire Damage Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"damage_reduction_crit\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Crit Damage Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"damage_reduction_blast\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Blast Damage Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"damage_reduction_bullet\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Bullet Damage Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"damage_reduction_melee\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Melee Damage Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"damage_reduction_sentry\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Sentry Damage Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"damage_reduction_ranged\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Ranged Damage Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"damage_reduction_all\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Global Damage Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"backstab_resistance\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.25\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Backstab Resistance\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"headshot_resistance\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.25\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Headshot Resistance\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"healthpack_bonus\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Healthpack Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"healing_received_bonus\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Healing Received Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"jump_height\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"2\"");
            WriteFileLine(file, "\t\t\"Name\" \"Jump Height Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"air_dash\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Extra Air Dashes\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"deploy_speed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Deploy Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"knockback_resistance\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Knockback Resistance\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"airblast_resistance\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Airblast Resistance\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"fall_damage_resistance\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.25\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Fall Damage Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"gesture_speed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Gesture Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"parachute\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Parachute\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"redeploy_parachute\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Redeploy Parachute\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"air_control\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Air Control Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"capture_value\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Capture Value Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"see_enemy_health\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"See Enemy Health\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"primary_ammo\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"InitValue\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Primary Ammo Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"secondary_ammo\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Secondary Ammo Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"metal_max\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"25.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"300\"");
            WriteFileLine(file, "\t\t\"Name\" \"Max Metal Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"ammo_regen\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.5\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Ammo Regeneration\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"metal_regen\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.5\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Metal Regeneration\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"cloak_consume\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Cloak Consumption Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"cloak_rate\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"2\"");
            WriteFileLine(file, "\t\t\"Name\" \"Cloak Recharge Rate Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"decloak_rate\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"2\"");
            WriteFileLine(file, "\t\t\"Name\" \"Decloak Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"disguise_speed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"2\"");
            WriteFileLine(file, "\t\t\"Name\" \"Disguise Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"heal_on_hit\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"5.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"50\"");
            WriteFileLine(file, "\t\t\"Name\" \"Heal on Hit\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"heal_on_kill\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"20.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"100\"");
            WriteFileLine(file, "\t\t\"Name\" \"Heal on Kill\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"slow_enemy\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Slow Enemy on Hit\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"minicrits_become_crits\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Minicrits Become Crits\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"minicrits_airborn\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Minicrits vs Airborne Targets\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"reveal_cloak\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Reveal Cloaked Victim\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"reveal_disguise\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Reveal Disguised Victim\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"damage_vs_building\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Damage vs Buildings\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"damage_vs_sapper\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Damage vs Sappers\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"attack_speed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"2\"");
            WriteFileLine(file, "\t\t\"Name\" \"Attack Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"reload_speed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"2\"");
            WriteFileLine(file, "\t\t\"Name\" \"Reload Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"melee_range\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Melee Range Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"crit_on_kill\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Crits on Kill\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"crit_from_behind\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Crit from Behind\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"speed_buff_ally\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.5\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Speed Buff to Allies\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"mark_for_death\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Mark for Death on Hit\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"repair_rate\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Repair Rate Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"sentry_fire_rate\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Sentry Fire Rate Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"sentry_damage\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Sentry Damage Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"sentry_ammo\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Sentry Max Ammo Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"sentry_radius\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Sentry Radius Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"building_deploy_speed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Building Deploy Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"teleporter_bidirectional\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Bidirectional Teleporter\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"dispenser_range\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Dispenser Radius Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"dispenser_metal\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"25.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"300\"");
            WriteFileLine(file, "\t\t\"Name\" \"Dispenser Metal Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"damage_falloff\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Damage Falloff Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"self_push_bonus\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Self Blast Push Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"clip_size\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Clip Size Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"projectile_speed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Projectile Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"self_blast_immunity\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Self Blast Damage Immunity\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"rocket_jump_reduction\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.25\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Rocket Jump Damage Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"blast_radius\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Blast Radius Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"blast_push\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Blast Push Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"grenades_no_bounce\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Grenades No Bounce\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"damage_causes_airblast\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Damage Causes Airblast\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"remove_hit_self\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Remove Self Damage on Miss\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"bleed_duration\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Bleed Duration Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"ignite_on_hit\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Ignite on Hit\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"afterburn_damage\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Afterburn Damage Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"afterburn_duration\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Afterburn Duration Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"accurate_damage_bonus\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Accurate Damage Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"weapon_spread\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Weapon Spread Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"attack_projectile\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Attack Destroys Projectiles\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"projectile_penetration\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Projectile Penetration\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"bullets_per_shot\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Bullets per Shot Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"minigun_spinup\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Minigun Spinup Time Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"rage_on_damage\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Rage on Damage\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"rage_duration\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Rage Duration Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"banner_duration\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Banner Duration Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"uber_on_hit\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.5\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Uber on Hit\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"heal_rate_bonus\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Heal Rate Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"overheal_bonus\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Overheal Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"uber_rate_bonus\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"2\"");
            WriteFileLine(file, "\t\t\"Name\" \"Ubercharge Rate Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"uber_duration\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Uber Duration Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"shield_level\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Shield Level Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"shield_duration\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Shield Duration Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"flame_life_bonus\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Flame Life Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"airblast_refire\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Airblast Refire Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"airblast_push_force\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Airblast Push Force Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"airblast_size\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Airblast Size Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"airblast_ammo_cost\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Airblast Ammo Cost Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"flame_ammo_cost\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Flame Ammo Cost Reduction\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"rage_from_flames\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Rage from Flames Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"full_charge_damage\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Full Charge Damage Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"headshot_damage_bonus\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Headshot Damage Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"explosive_headshots\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Explosive Headshots\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"sniper_charge_rate\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"2\"");
            WriteFileLine(file, "\t\t\"Name\" \"Sniper Charge Rate Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"charge_multiplier_headshot\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Charge Multiplier after Headshot\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"disable_flinch\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Disable Flinch\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"aiming_movespeed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"2\"");
            WriteFileLine(file, "\t\t\"Name\" \"Aiming Move Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"minicrit_headshot\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Minicrit on Headshot\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"crit_headshot\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Crit on Headshot\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"sapper_health\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Sapper Health Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"sapper_damage\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Sapper Damage Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"sapper_heal\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"10.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"100\"");
            WriteFileLine(file, "\t\t\"Name\" \"Sapper Heal on Attach\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"rocket_speed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Rocket Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"grenade_speed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Grenade Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"stickybomb_speed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Stickybomb Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"syringe_speed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Syringe Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"arrow_speed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Arrow Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"energy_ball_speed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Energy Ball Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"charge_rate\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"2\"");
            WriteFileLine(file, "\t\t\"Name\" \"Shield Charge Rate Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"charge_damage\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Shield Charge Impact Damage Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"charge_turn_rate\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Shield Charge Turn Control Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"hit_speedboost\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Speed Boost on Hit\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"lunchbox_heal_bonus\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Lunchbox Heal Amount Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"lunchbox_recharge\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Lunchbox Recharge Rate Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"slow_on_hit\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Slow Enemy on Hit\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"liquid_duration\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"5\"");
            WriteFileLine(file, "\t\t\"Name\" \"Milk / Jarate Duration Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"gas_passer_explosion\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Gas Passer Explosion on Ignite\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"silent_killer\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Silent Killer\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"silent_uncloak\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Silent Uncloak\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"mad_milk_on_hit\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Mad Milk on Hit\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"sanguisuge\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"10.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"100\"");
            WriteFileLine(file, "\t\t\"Name\" \"Backstab Healing Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"thermal_thruster_airlaunch\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"1.0\"");
            WriteFileLine(file, "\t\t\"Limit\" \"1\"");
            WriteFileLine(file, "\t\t\"Name\" \"Thermal Thruster Air Launch\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"impact_pushback\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Impact Pushback Radius\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"impact_stun\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Impact Stun Radius\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"dragon_fury_recharge\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Dragon Fury Recharge Rate\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"building_heal_rate\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Building Heal Rate Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"sentry_bullet_resistance\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Sentry Bullet Resistance\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"sentry_rocket_resistance\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Sentry Rocket Resistance\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"sentry_flame_resistance\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Sentry Flame Resistance\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"sentry_damage_resistance\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Sentry General Damage Resistance\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"dispenser_damage_resistance\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Dispenser General Damage Resistance\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"teleporter_damage_resistance\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"-0.05\"");
            WriteFileLine(file, "\t\t\"Limit\" \"0\"");
            WriteFileLine(file, "\t\t\"Name\" \"Teleporter General Damage Resistance\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"bat_ball_speed\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Bat Ball Speed Bonus\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"slow_on_hit_building\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Slow Enemy on Hit Building\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"damage_force_reduction_on_hit\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Damage Force Reduction on Hit\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "\t\"snare_on_hit\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"Cost\" \"100\"");
            WriteFileLine(file, "\t\t\"Ratio\" \"1.5\"");
            WriteFileLine(file, "\t\t\"Increment\" \"0.1\"");
            WriteFileLine(file, "\t\t\"Limit\" \"3\"");
            WriteFileLine(file, "\t\t\"Name\" \"Snare on Hit\"");
            WriteFileLine(file, "\t}");

            WriteFileLine(file, "}");

            CloseHandle(file);
        }
    }

    // Generate hu_attributes.cfg
    BuildPath(Path_SM, filePath, sizeof(filePath), "configs/%s", CONFIG_ATTR);
    if (!FileExists(filePath))
    {
        Handle file = OpenFile(filePath, "w");
        if (file != null)
        {
            WriteFileLine(file, "\"Upgrades\"");
            WriteFileLine(file, "{");

            WriteFileLine(file, "\t\"Body Upgrades\"");
            WriteFileLine(file, "\t{");

            WriteFileLine(file, "\t\t\"body_scout\"");
            WriteFileLine(file, "\t\t{");

            WriteFileLine(file, "\t\t\t\"Protection Upgrades\"");
            WriteFileLine(file, "\t\t\t{");
            WriteFileLine(file, "\t\t\t\t\"1\"\t\"health_upgrade\"");
            WriteFileLine(file, "\t\t\t\t\"2\"\t\"health_regen\"");
            WriteFileLine(file, "\t\t\t\t\"3\"\t\"damage_reduction_fire\"");
            WriteFileLine(file, "\t\t\t\t\"4\"\t\"damage_reduction_crit\"");
            WriteFileLine(file, "\t\t\t\t\"5\"\t\"damage_reduction_blast\"");
            WriteFileLine(file, "\t\t\t\t\"6\"\t\"damage_reduction_bullet\"");
            WriteFileLine(file, "\t\t\t\t\"7\"\t\"damage_reduction_melee\"");
            WriteFileLine(file, "\t\t\t\t\"8\"\t\"damage_reduction_sentry\"");
            WriteFileLine(file, "\t\t\t\t\"9\"\t\"damage_reduction_ranged\"");
            WriteFileLine(file, "\t\t\t\t\"10\"\t\"damage_reduction_all\"");
            WriteFileLine(file, "\t\t\t\t\"11\"\t\"backstab_resistance\"");
            WriteFileLine(file, "\t\t\t\t\"12\"\t\"headshot_resistance\"");
            WriteFileLine(file, "\t\t\t\t\"13\"\t\"knockback_resistance\"");
            WriteFileLine(file, "\t\t\t\t\"14\"\t\"airblast_resistance\"");
            WriteFileLine(file, "\t\t\t\t\"15\"\t\"healthpack_bonus\"");
            WriteFileLine(file, "\t\t\t\t\"16\"\t\"healing_received_bonus\"");
            WriteFileLine(file, "\t\t\t}");

            WriteFileLine(file, "\t\t\t\"Physical Upgrades\"");
            WriteFileLine(file, "\t\t\t{");
            WriteFileLine(file, "\t\t\t\t\"1\"\t\"movement_speed\"");
            WriteFileLine(file, "\t\t\t\t\"2\"\t\"jump_height\"");
            WriteFileLine(file, "\t\t\t\t\"3\"\t\"air_control\"");
            WriteFileLine(file, "\t\t\t\t\"4\"\t\"air_dash\"");
            WriteFileLine(file, "\t\t\t\t\"5\"\t\"capture_value\"");
            WriteFileLine(file, "\t\t\t\t\"6\"\t\"fall_damage_resistance\"");
            WriteFileLine(file, "\t\t\t\t\"7\"\t\"parachute\"");
            WriteFileLine(file, "\t\t\t\t\"8\"\t\"redeploy_parachute\"");
            WriteFileLine(file, "\t\t\t}");

            WriteFileLine(file, "\t\t\t\"Ammo Upgrades\"");
            WriteFileLine(file, "\t\t\t{");
            WriteFileLine(file, "\t\t\t\t\"1\"\t\"primary_ammo\"");
            WriteFileLine(file, "\t\t\t\t\"2\"\t\"secondary_ammo\"");
            WriteFileLine(file, "\t\t\t\t\"3\"\t\"ammo_regen\"");
            WriteFileLine(file, "\t\t\t}");

            WriteFileLine(file, "\t\t}"); // body_scout
            WriteFileLine(file, "\t}");   // Body Upgrades


            WriteFileLine(file, "\t\"Primary Upgrades\"");
            WriteFileLine(file, "\t{");

            WriteFileLine(file, "\t\t\"tf_weapon_scattergun\"");
            WriteFileLine(file, "\t\t{");

            WriteFileLine(file, "\t\t\t\"Damage Upgrades\"");
            WriteFileLine(file, "\t\t\t{");
            WriteFileLine(file, "\t\t\t\t\"1\"\t\"damage_bonus\"");
            WriteFileLine(file, "\t\t\t\t\"2\"\t\"heal_on_kill\"");
            WriteFileLine(file, "\t\t\t\t\"2\"\t\"heal_on_hit\"");
            WriteFileLine(file, "\t\t\t\t\"3\"\t\"slow_enemy\"");
            WriteFileLine(file, "\t\t\t\t\"4\"\t\"reveal_cloak\"");
            WriteFileLine(file, "\t\t\t\t\"5\"\t\"reveal_disguise\"");
            WriteFileLine(file, "\t\t\t}");

            WriteFileLine(file, "\t\t\t\"Specific Upgrades\"");
            WriteFileLine(file, "\t\t\t{");
            WriteFileLine(file, "\t\t\t\t\"1\"\t\"attack_speed\"");
            WriteFileLine(file, "\t\t\t\t\"2\"\t\"reload_speed\"");
            WriteFileLine(file, "\t\t\t\t\"3\"\t\"clip_size\"");
            WriteFileLine(file, "\t\t\t\t\"4\"\t\"bullets_per_shot\"");
            WriteFileLine(file, "\t\t\t\t\"5\"\t\"weapon_spread\"");
            WriteFileLine(file, "\t\t\t\t\"6\"\t\"projectile_penetration\"");
            WriteFileLine(file, "\t\t\t}");

            WriteFileLine(file, "\t\t}"); // tf_weapon_scattergun

            WriteFileLine(file, "\t}");   // Primary Upgrades


            WriteFileLine(file, "\t\"Secondary Upgrades\"");
            WriteFileLine(file, "\t{");

            WriteFileLine(file, "\t\t\"tf_weapon_pistol\"");
            WriteFileLine(file, "\t\t{");

            WriteFileLine(file, "\t\t\t\"Damage Upgrades\"");
            WriteFileLine(file, "\t\t\t{");
            WriteFileLine(file, "\t\t\t\t\"1\"\t\"damage_bonus\"");
            WriteFileLine(file, "\t\t\t\t\"2\"\t\"heal_on_hit\"");
            WriteFileLine(file, "\t\t\t\t\"3\"\t\"heal_on_kill\"");
            WriteFileLine(file, "\t\t\t\t\"4\"\t\"slow_enemy\"");
            WriteFileLine(file, "\t\t\t}");

            WriteFileLine(file, "\t\t\t\"Specific Upgrades\"");
            WriteFileLine(file, "\t\t\t{");
            WriteFileLine(file, "\t\t\t\t\"1\"\t\"attack_speed\"");
            WriteFileLine(file, "\t\t\t\t\"2\"\t\"reload_speed\"");
            WriteFileLine(file, "\t\t\t\t\"3\"\t\"clip_size\"");
            WriteFileLine(file, "\t\t\t\t\"4\"\t\"weapon_spread\"");
            WriteFileLine(file, "\t\t\t\t\"5\"\t\"projectile_penetration\"");
            WriteFileLine(file, "\t\t\t}");

            WriteFileLine(file, "\t\t}"); // tf_weapon_pistol

            WriteFileLine(file, "\t}");   // Secondary Upgrades


            WriteFileLine(file, "\t\"Melee Upgrades\"");
            WriteFileLine(file, "\t{");

            WriteFileLine(file, "\t\t\"tf_weapon_bat\"");
            WriteFileLine(file, "\t\t{");

            WriteFileLine(file, "\t\t\t\"Damage Upgrades\"");
            WriteFileLine(file, "\t\t\t{");
            WriteFileLine(file, "\t\t\t\t\"1\"\t\"damage_bonus\"");
            WriteFileLine(file, "\t\t\t\t\"2\"\t\"heal_on_hit\"");
            WriteFileLine(file, "\t\t\t\t\"3\"\t\"heal_on_kill\"");
            WriteFileLine(file, "\t\t\t\t\"4\"\t\"slow_enemy\"");
            WriteFileLine(file, "\t\t\t\t\"5\"\t\"bleed_duration\"");
            WriteFileLine(file, "\t\t\t}");

            WriteFileLine(file, "\t\t\t\"Specific Upgrades\"");
            WriteFileLine(file, "\t\t\t{");
            WriteFileLine(file, "\t\t\t\t\"1\"\t\"attack_speed\"");
            WriteFileLine(file, "\t\t\t\t\"2\"\t\"melee_range\"");
            WriteFileLine(file, "\t\t\t\t\"3\"\t\"crit_on_kill\"");
            WriteFileLine(file, "\t\t\t\t\"4\"\t\"crit_from_behind\"");
            WriteFileLine(file, "\t\t\t\t\"5\"\t\"speed_buff_ally\"");
            WriteFileLine(file, "\t\t\t\t\"6\"\t\"mark_for_death\"");
            WriteFileLine(file, "\t\t\t}");

            WriteFileLine(file, "\t\t}"); // tf_weapon_bat
            WriteFileLine(file, "\t}");   // Melee Upgrades

            WriteFileLine(file, "}");     // Upgrades



            CloseHandle(file);
        }
    }

    // Generate hu_translations.txt
    BuildPath(Path_SM, filePath, sizeof(filePath), "translations/%s", TRANSLATION_FILE);
    if (!FileExists(filePath))
    {
        Handle file = OpenFile(filePath, "w");
        if (file != null)
        {
            WriteFileLine(file, "\"Phrases\"");
            WriteFileLine(file, "{");
            WriteFileLine(file, "\t\"Health Bonus\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"en\" \"Health Bonus\"");
            WriteFileLine(file, "\t}");
            WriteFileLine(file, "\t\"Damage Bonus\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"en\" \"Damage Bonus\"");
            WriteFileLine(file, "\t}");
            WriteFileLine(file, "\t\"Speed Bonus\"");
            WriteFileLine(file, "\t{");
            WriteFileLine(file, "\t\t\"en\" \"Speed Bonus\"");
            WriteFileLine(file, "\t}");
            WriteFileLine(file, "}");
            CloseHandle(file);
        }
    }
}
