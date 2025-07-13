#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>
#include <tf_econ_data>

#include <stocksoup/handles>
//#include <stocksoup/memory>


#define TF_ITEMDEF_DEFAULT -1
#define MAX_EDICTS 2048

#define PLUGIN_NAME "Hyper Upgrades"
#define PLUGIN_VERSION "0.75"
#define CONFIG_ATTR "hu_attributes.cfg"
#define CONFIG_UPGR "hu_upgrades.cfg"
#define CONFIG_WEAP "hu_weapons_list.txt"
#define CONFIG_ALIAS "hu_alias_list.txt"
#define TRANSLATION_FILE "hu_translations.txt"

//#define IN_DUCK (1 << 2)     // Crouch key already defined
//#define IN_RELOAD (1 << 13)  // Reload key already defined

ConVar g_hMoneyBossMultiplier;

bool g_bBossRewarded[MAX_EDICTS + 1];
bool g_bMenuPressed[MAXPLAYERS + 1];
bool g_bPlayerBrowsing[MAXPLAYERS + 1];
bool g_bShowMoneyHud[MAXPLAYERS + 1];
bool g_bInUpgradeList[MAXPLAYERS + 1];

char g_sPlayerCategory[MAXPLAYERS + 1][64];
char g_sPlayerAlias[MAXPLAYERS + 1][64];
char g_sPlayerUpgradeGroup[MAXPLAYERS + 1][64];

int g_MenuClient[MAXPLAYERS + 1];
int g_iUpgradeMenuPage[MAXPLAYERS + 1];

Handle g_hMoneyPool;
int g_iMoneySpent[MAXPLAYERS + 1];

Handle g_hPlayerUpgrades[MAXPLAYERS + 1];
int g_iPlayerBrowsingSlot[MAXPLAYERS + 1];
ConVar g_hResetMoneyPoolOnMapStart;

Handle g_hRefreshTimer[MAXPLAYERS + 1] = { INVALID_HANDLE, ... };
int g_iPlayerLastMultiplier[MAXPLAYERS + 1];

Handle g_hHudMoneySync;
Handle g_hHudResistSync;

Database g_hSettingsDB;

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

//init upgrades list
enum struct UpgradeData
{
    char name[64];
    char alias[64];
    int cost;
    int costIncrease;
    float increment;
    float limit;
    float initValue;
    bool hadLimit;
}
ArrayList g_upgrades; // Each entry is an UpgradeDat
StringMap g_upgradeIndex; // key = name, value = index into g_upgrades

enum HudCorner // Currency Hud
{
    HUD_TOP_LEFT,
    HUD_TOP_RIGHT,
    HUD_BOTTOM_LEFT,
    HUD_BOTTOM_RIGHT
};
HudCorner g_iHudCorner[MAXPLAYERS + 1];

enum ResistanceHudPosition // Res Hud
{
    HUDPOS_LEFT,
    HUDPOS_TOP,
    HUDPOS_RIGHT
};
ResistanceHudPosition g_iResistHudCorner[MAXPLAYERS + 1];

// --- Damage Types for HUD ---
enum DamageType
{
    DAMAGE_FIRE,
    DAMAGE_BULLET,
    DAMAGE_BLAST,
    DAMAGE_CRIT,
    DAMAGE_MELEE,
    DAMAGE_OTHER,
    DAMAGE_COUNT
};

float g_fDamageTaken[MAXPLAYERS + 1][DAMAGE_COUNT];
StringMap g_resistanceSources[MAXPLAYERS + 1][DAMAGE_COUNT];
ArrayList g_resistanceMappings; 
enum struct ResistanceMapping
{
    char upgradeName[64];
    DamageType type;
}
int g_iResistanceHudMode[MAXPLAYERS + 1]; // 0 = off, 1 = standard, 2 = abridged

public void OnPluginStart()
{
    RegConsoleCmd("sm_buy", Command_OpenMenu);
    RegConsoleCmd("sm_shop", Command_OpenMenu);

    RegAdminCmd("hu_addmoney", Command_AddMoney, ADMFLAG_GENERIC, "Add money to the pool.");
    RegAdminCmd("hu_subtractmoney", Command_SubtractMoney, ADMFLAG_GENERIC, "Subtract money from the pool.");

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("teamplay_point_captured", Event_ObjectiveComplete, EventHookMode_Post);
    HookEvent("teamplay_flag_event", Event_ObjectiveComplete, EventHookMode_Post);
    HookEvent("teamplay_round_win", Event_ObjectiveComplete, EventHookMode_Post);
    HookEvent("player_changeclass", Event_PlayerChangeClass, EventHookMode_Post);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);

    CreateConVar("hu_money_per_kill", "10", "Money gained per kill.");
    CreateConVar("hu_money_per_objective", "30", "Money gained per objective.");
    CreateConVar("hu_money_boss_multiplier", "3", "Multiplier for boss kills."); // advise 3.5 for 130k on ultrarasmus
    g_hMoneyBossMultiplier = FindConVar("hu_money_boss_multiplier");

    g_hMoneyPool = CreateConVar("hu_money_pool", "0", "Current money pool shared by all players.", FCVAR_NOTIFY);

    LoadTranslations(TRANSLATION_FILE);

    GenerateConfigFiles();

    RegAdminCmd("hu_reloadweapons", Command_ReloadWeaponAliases, ADMFLAG_GENERIC, "Reload the weapon aliases.");
    RegAdminCmd("hu_reloadattalias", Command_ReloadAttributesAliases, ADMFLAG_GENERIC, "Reload the attributes aliases.");
    RegAdminCmd("hu_reloadupgrades", Command_ReloadUpgrades, ADMFLAG_GENERIC, "Reload the upgrade data from hu_upgrades.cfg");

    g_weaponAliases = new ArrayList(sizeof(WeaponAlias));
    LoadWeaponAliases();
    g_attributeMappings = new ArrayList(sizeof(AttributeMapping));
    LoadAttributeMappings();
    g_upgrades = new ArrayList(sizeof(UpgradeData));
    g_upgradeIndex = new StringMap();
    LoadUpgradeData();

    // Settings stuff
    g_hHudMoneySync = CreateHudSynchronizer();
    g_hHudResistSync = CreateHudSynchronizer();
    InitSettingsDatabase();
    if (g_resistanceMappings != null)
        g_resistanceMappings.Clear();
    else
        g_resistanceMappings = new ArrayList(sizeof(ResistanceMapping));

    LoadResistanceMappingsFromFile();
    for (int i = 1; i <= MaxClients; i++) // apply settings to players
    {
        if (IsClientInGame(i) && IsClientAuthorized(i))
        {
            LoadPlayerSettings(i);
        }
        if (IsClientInGame(i))
        {
            if (g_hRefreshTimer[i] == INVALID_HANDLE)
            {
                g_hRefreshTimer[i] = CreateTimer(0.2, Timer_CheckMenuRefresh, i, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
            }
        }
    }

    // Reset upgrades for all connected players
    ResetAllPlayerUpgrades();

    g_hResetMoneyPoolOnMapStart = CreateConVar("hu_reset_money_on_mapstart", "1", "Reset the money pool to 0 on map start. 1 = Enabled, 0 = Disabled.", FCVAR_NOTIFY);

}

public void OnPluginEnd()
{
    // Notify and clean up each player
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;

        PrintToChat(i, "\x04[HU] \x01Hyper Upgrades reloaded, you may need to change class.");

        TF2_RemoveAllWeapons(i);

        int ent = -1;
        while ((ent = FindEntityByClassname(ent, "tf_wearable")) != -1)
        {
            if (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") == i)
            {
                AcceptEntityInput(ent, "Kill");
            }
        }

        // Kill any per-player refresh timers
        if (g_hRefreshTimer[i] != INVALID_HANDLE)
        {
            KillTimer(g_hRefreshTimer[i]);
            g_hRefreshTimer[i] = INVALID_HANDLE;
        }

        // Delete per-player upgrade maps
        if (g_hPlayerUpgrades[i] != null)
        {
            delete g_hPlayerUpgrades[i];
            g_hPlayerUpgrades[i] = null;
        }

        // Delete per-player resistance source maps
        for (DamageType d = view_as<DamageType>(0); d < DAMAGE_COUNT; d++)
        {
            if (g_resistanceSources[i][d] != null)
            {
                delete g_resistanceSources[i][d];
                g_resistanceSources[i][d] = null;
            }
        }

    }

    // Delete global lists/maps
    if (g_weaponAliases != null)
    {
        delete g_weaponAliases;
        g_weaponAliases = null;
    }

    if (g_attributeMappings != null)
    {
        delete g_attributeMappings;
        g_attributeMappings = null;
    }

    if (g_upgrades != null)
    {
        delete g_upgrades;
        g_upgrades = null;
    }

    if (g_upgradeIndex != null)
    {
        delete g_upgradeIndex;
        g_upgradeIndex = null;
    }

    if (g_resistanceMappings != null)
    {
        delete g_resistanceMappings;
        g_resistanceMappings = null;
    }

    // Delete HUD synchronizers
    if (g_hHudMoneySync != null)
    {
        delete g_hHudMoneySync;
        g_hHudMoneySync = null;
    }

    if (g_hHudResistSync != null)
    {
        delete g_hHudResistSync;
        g_hHudResistSync = null;
    }

    // Delete database handle if open
    if (g_hSettingsDB != null)
    {
        delete g_hSettingsDB;
        g_hSettingsDB = null;
    }

    // Delete convars
    if (g_hMoneyPool != null)
    {
        delete g_hMoneyPool;
        g_hMoneyPool = null;
    }

    if (g_hMoneyBossMultiplier != null)
    {
        delete g_hMoneyBossMultiplier;
        g_hMoneyBossMultiplier = null;
    }

    if (g_hResetMoneyPoolOnMapStart != null)
    {
        delete g_hResetMoneyPoolOnMapStart;
        g_hResetMoneyPoolOnMapStart = null;
    }
}


public void OnClientPutInServer(int client)
{
    RefundPlayerUpgrades(client, false); // No message on join
    LoadPlayerSettings(client);
    g_hRefreshTimer[client] = CreateTimer(0.2, Timer_CheckMenuRefresh, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

}

public void OnClientDisconnect(int client)
{
    RefundPlayerUpgrades(client, false); // No message on disconnect
    // Stop the refresh timer if active
    if (g_hRefreshTimer[client] != INVALID_HANDLE)
    {
        CloseHandle(g_hRefreshTimer[client]);
        g_hRefreshTimer[client] = INVALID_HANDLE;
    }

    // Reset browsing state
    g_bPlayerBrowsing[client] = false;
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
    // Money_HUD_Handler
    CreateTimer(1.0, Timer_DisplayMoneyHUD, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(1.0, Timer_DisplayResistanceHUD, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnSafeSettingsQueryResult(Database db, DBResultSet results, const char[] error, any client)
{
    if (results == null || error[0] != '\0')
    {
        PrintToServer("[Warning] Failed to query settings for client %N: %s", client, error);
        return;
    }

    if (results.FetchRow())
    {
        if (results.FieldCount < 4)
        {
            PrintToServer("[Warning] Settings row for client %N is missing columns. Using defaults.", client);
            g_bShowMoneyHud[client] = true;
            g_iHudCorner[client] = HUD_BOTTOM_RIGHT;
            g_iResistanceHudMode[client] = 0;
            g_iResistHudCorner[client] = HUDPOS_LEFT;
            SavePlayerSettings(client);
            return;
        }

        g_bShowMoneyHud[client] = results.FetchInt(0) != 0;

        char pos[32];
        results.FetchString(1, pos, sizeof(pos));
        g_iHudCorner[client] = ParseHudPosition(pos);

        g_iResistanceHudMode[client] = results.FetchInt(2);

        char resistPosStr[16];
        results.FetchString(3, resistPosStr, sizeof(resistPosStr));
        g_iResistHudCorner[client] = ParseResistanceHudPosition(resistPosStr);
        // PrintToServer("[Debug] [%N] money_hud=%d, hud_pos=%s, resist_mode=%d, resist_pos=%s", client, g_bShowMoneyHud[client], pos, g_iResistanceHudMode[client], resistPosStr);
    }
    else
    {
        PrintToServer("[Info] No settings found for client %N. Applying defaults.", client);
        g_bShowMoneyHud[client] = true;
        g_iHudCorner[client] = HUD_BOTTOM_RIGHT;
        g_iResistanceHudMode[client] = 0;
        g_iResistHudCorner[client] = HUDPOS_LEFT;
        SavePlayerSettings(client);
    }
}

void EnsureSettingsSchemaUpToDate()
{
    if (g_hSettingsDB == null)
        return;

    Handle results = SQL_Query(g_hSettingsDB, "PRAGMA table_info(settings);");

    bool hasResistHudMode = false;
    bool hasResistHudPos = false;

    while (SQL_FetchRow(results))
    {
        char columnName[64];
        SQL_FetchString(results, 1, columnName, sizeof(columnName));

        if (StrEqual(columnName, "resistance_hud_mode"))
            hasResistHudMode = true;
        else if (StrEqual(columnName, "resistance_hud_pos"))
            hasResistHudPos = true;
    }
    delete results;

    if (!hasResistHudMode)
    {
        PrintToServer("[Hyper Upgrades] Adding missing column 'resistance_hud_mode' to settings table...");
        SQL_FastQuery(g_hSettingsDB, "ALTER TABLE settings ADD COLUMN resistance_hud_mode INTEGER DEFAULT 0;");
    }

    if (!hasResistHudPos)
    {
        PrintToServer("[Hyper Upgrades] Adding missing column 'resistance_hud_pos' to settings table...");
        SQL_FastQuery(g_hSettingsDB, "ALTER TABLE settings ADD COLUMN resistance_hud_pos TEXT DEFAULT 'left';");
    }
}

public void Event_PlayerChangeClass(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (IsClientInGame(client))
    {
        RefundPlayerUpgrades(client, false);
        RefreshClientResistances(client);
    }
}


public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (IsClientInGame(client))
    {
        ApplyPlayerUpgrades(client);
        RefreshClientResistances(client);
    }
}

void LoadUpgradeData()
{
    char filePath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, filePath, sizeof(filePath), "configs/hu_upgrades.cfg");

    KeyValues kv = new KeyValues("Upgrades");
    if (!kv.ImportFromFile(filePath))
    {
        PrintToServer("[Hyper Upgrades] Failed to load hu_upgrades.cfg");
        delete kv;
        return;
    }

    if (!kv.GotoFirstSubKey(false))
    {
        delete kv;
        return;
    }

    do
    {
        UpgradeData upgrade;

        kv.GetSectionName(upgrade.name, sizeof(upgrade.name));
        kv.GetString("Alias", upgrade.alias, sizeof(upgrade.alias));

        upgrade.cost = kv.GetNum("Cost", 20);

        // Updated: Use "CostIncrease" instead of "Ratio"
        upgrade.costIncrease = kv.GetNum("CostIncrease", 10); // Default 10

        upgrade.increment = kv.GetFloat("Increment", 0.1);

        char limitStr[32];
        kv.GetString("Limit", limitStr, sizeof(limitStr), "");
        upgrade.hadLimit = limitStr[0] != '\0';
        upgrade.limit = upgrade.hadLimit ? StringToFloat(limitStr) : 0.0;

        upgrade.initValue = kv.GetFloat("InitValue", 0.0);

        int index = g_upgrades.PushArray(upgrade);
        g_upgradeIndex.SetValue(upgrade.name, index);

    } while (kv.GotoNextKey(false));

    delete kv;

    PrintToServer("[Hyper Upgrades] Loaded %d upgrades into memory.", g_upgrades.Length);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && g_iResistanceHudMode[i] != 0)
        {
            RefreshClientResistances(i);
        }
    }
}


// Settings


void InitSettingsDatabase()
{
    char error[256];
    g_hSettingsDB = SQLite_UseDatabase("hyperupgrades_settings", error, sizeof(error));

    if (g_hSettingsDB == null)
    {
        SetFailState("Could not connect to database: %s", error);
    }

    SQL_LockDatabase(g_hSettingsDB);
    SQL_FastQuery(g_hSettingsDB, "CREATE TABLE IF NOT EXISTS settings (steamid TEXT PRIMARY KEY, show_money_hud INTEGER, hud_position TEXT DEFAULT 'bottom-right');");

    EnsureSettingsSchemaUpToDate();

    SQL_UnlockDatabase(g_hSettingsDB);
}

void LoadPlayerSettings(int client)
{
    if (g_hSettingsDB == null || !IsClientAuthorized(client))
        return;

    char steamid[32], query[256];
    GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid), true);
    Format(query, sizeof(query), "SELECT show_money_hud, hud_position, resistance_hud_mode, resistance_hud_pos FROM settings WHERE steamid = '%s'", steamid);
    g_hSettingsDB.Query(OnSafeSettingsQueryResult, query, client);
}

void ShowSettingsMenu(int client)
{
    Menu menu = new Menu(MenuHandler_SettingsMenu);
    menu.SetTitle("Settings");

    menu.AddItem("toggle_money_hud", "Toggle Money Display HUD");
    menu.AddItem("money_hud_position", "Money Display HUD Position");
    menu.AddItem("toggle_resistance_hud", "Toggle Resistance HUD");
    menu.AddItem("resist_hud_position", "Resistance HUD Position");


    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_SettingsMenu(Menu menu, MenuAction action, int client, int param)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param, info, sizeof(info));

        if (StrEqual(info, "toggle_money_hud"))
        {
            ToggleHudSetting(client);
        }
        else if (StrEqual(info, "money_hud_position"))
        {
            ShowMoneyHudPositionMenu(client);
        }
        else if (StrEqual(info, "toggle_resistance_hud"))
        {
            ToggleResistanceHudSetting(client);
        }
        else if (StrEqual(info, "resist_hud_position"))
        {
            ShowResistHudPositionMenu(client);
        }
    }
    else if (action == MenuAction_Cancel && param == MenuCancel_ExitBack)
    {
        g_bInUpgradeList[client] = false;
        ShowMainMenu(client);
    }
    return 0;
}

void SavePlayerSettings(int client)
{
    if (g_hSettingsDB == null || !IsClientAuthorized(client))
        return;

    char steamid[32];
    GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid), true);

    char posStr[32];
    MoneyHudPositionToString(g_iHudCorner[client], posStr, sizeof(posStr));
    char resistPosStr[32];
    ResHudPositionToString(g_iResistHudCorner[client], resistPosStr, sizeof(resistPosStr));

    char query[256];

    

    Format(query, sizeof(query),
        "REPLACE INTO settings (steamid, show_money_hud, hud_position, resistance_hud_mode, resistance_hud_pos) VALUES ('%s', %d, '%s', %d, '%s')",
        steamid,
        g_bShowMoneyHud[client] ? 1 : 0,
        posStr,
        g_iResistanceHudMode[client],
        resistPosStr
    );


    SQL_FastQuery(g_hSettingsDB, query);
}

void ToggleHudSetting(int client)
{
    g_bShowMoneyHud[client] = !g_bShowMoneyHud[client];
    SavePlayerSettings(client);
    PrintToChat(client, "[Settings] Money HUD is now %s.", g_bShowMoneyHud[client] ? "enabled" : "disabled");
}

void ShowMoneyHudPositionMenu(int client)
{
    Menu menu = new Menu(MenuHandler_MoneyHudPositionMenu);
    menu.SetTitle("Select HUD Position");

    menu.AddItem("top-left", "Top Left");
    menu.AddItem("top-right", "Top Right");
    menu.AddItem("bottom-left", "Bottom Left");
    menu.AddItem("bottom-right", "Bottom Right");

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MoneyHudPositionMenu(Menu menu, MenuAction action, int client, int param)
{
    if (action == MenuAction_Select)
    {
        char pos[32];
        menu.GetItem(param, pos, sizeof(pos));
        g_iHudCorner[client] = ParseHudPosition(pos);
        SavePlayerSettings(client);
        PrintToChat(client, "[Settings] HUD position set to: %s", pos);
    }
    else if (action == MenuAction_Cancel && param == MenuCancel_ExitBack)
    {
        g_bInUpgradeList[client] = false;
        ShowSettingsMenu(client);
    }

    return 0;
}

void ShowResistHudPositionMenu(int client)
{
    Menu menu = new Menu(MenuHandler_ResistHudPositionMenu);
    menu.SetTitle("Select Resistance HUD Position");

    menu.AddItem("left", "Left");
    menu.AddItem("top", "Top");
    menu.AddItem("right", "Right");

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ResistHudPositionMenu(Menu menu, MenuAction action, int client, int param)
{
    if (action == MenuAction_Select)
    {
        char pos[16];
        menu.GetItem(param, pos, sizeof(pos));

        if (StrEqual(pos, "left")) g_iResistHudCorner[client] = HUDPOS_LEFT;
        else if (StrEqual(pos, "top")) g_iResistHudCorner[client] = HUDPOS_TOP;
        else g_iResistHudCorner[client] = HUDPOS_RIGHT;

        SavePlayerSettings(client);
        PrintToChat(client, "[Settings] Resistance HUD position set to: %s", pos);
    }
    else if (action == MenuAction_Cancel && param == MenuCancel_ExitBack)
    {
        g_bInUpgradeList[client] = false;
        ShowSettingsMenu(client);
    }

    return 0;
}

HudCorner ParseHudPosition(const char[] input)
{
    if (StrEqual(input, "top-left")) return HUD_TOP_LEFT;
    if (StrEqual(input, "top-right")) return HUD_TOP_RIGHT;
    if (StrEqual(input, "bottom-left")) return HUD_BOTTOM_LEFT;
    return HUD_BOTTOM_RIGHT;
}

ResistanceHudPosition ParseResistanceHudPosition(const char[] input)
{
    if (StrEqual(input, "left", false)) return HUDPOS_LEFT;
    if (StrEqual(input, "top", false)) return HUDPOS_TOP;
    return HUDPOS_LEFT; // default fallback
}

public Action Timer_DisplayMoneyHUD(Handle timer)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsPlayerAlive(i) || !g_bShowMoneyHud[i])
            continue;

        int balance = GetPlayerBalance(i);
        char buffer[64];
        Format(buffer, sizeof(buffer), "$%d", balance);

        SetHudPositionByCorner(g_iHudCorner[i]);
        ShowSyncHudText(i, g_hHudMoneySync, buffer);
    }
    return Plugin_Continue;
}

void SetHudPositionByCorner(HudCorner corner)
{
    float x = 0.0, y = 0.0;

    switch (corner)
    {
        case HUD_TOP_LEFT:
        {
            x = 0.01;
            y = 0.01;
        }
        case HUD_TOP_RIGHT:
        {
            x = 0.85;
            y = 0.01;
        }
        case HUD_BOTTOM_LEFT:
        {
            x = 0.01;
            y = 0.90;
        }
        case HUD_BOTTOM_RIGHT:
        {
            x = 0.85;
            y = 0.90;
        }
    }

    SetHudTextParams(x, y, 1.0, 255, 255, 255, 255, 0, 0.0, 0.8, 0.8); 
}

void MoneyHudPositionToString(HudCorner pos, char[] buffer, int maxlen) // money
{
    switch (pos)
    {
        case HUD_TOP_LEFT:
        {
            strcopy(buffer, maxlen, "top-left");
            return;
        }
        case HUD_TOP_RIGHT:
        {
            strcopy(buffer, maxlen, "top-right");
            return;
        }
        case HUD_BOTTOM_LEFT:
        {
            strcopy(buffer, maxlen, "bottom-left");
            return;
        }
    }

    // Default fallback
    strcopy(buffer, maxlen, "bottom-right");
}

void ResHudPositionToString(ResistanceHudPosition pos, char[] buffer, int maxlen)
{
    switch (pos)
    {
        case HUDPOS_LEFT:
        {
            strcopy(buffer, maxlen, "left");
            return;
        }
        case HUDPOS_TOP:
        {
            strcopy(buffer, maxlen, "top");
            return;
        }
        case HUDPOS_RIGHT:
        {
            strcopy(buffer, maxlen, "right");
            return;
        }
    }

    // Fallback (shouldn't happen if enum is valid)
    strcopy(buffer, maxlen, "left");
}

void ToggleResistanceHudSetting(int client)
{
    g_iResistanceHudMode[client] = (g_iResistanceHudMode[client] + 1) % 3;
    SavePlayerSettings(client);

    char modeName[16];

    switch (g_iResistanceHudMode[client])
    {
        case 0:
        {
            strcopy(modeName, sizeof(modeName), "Off");
        }
        case 1:
        {
            strcopy(modeName, sizeof(modeName), "Standard");
        }
        case 2:
        {
            strcopy(modeName, sizeof(modeName), "Abridged");
        }
    }

    PrintToChat(client, "[Settings] Resistance HUD mode set to: %s", modeName);
}

void FormatDamagePercentString(float value, char[] buffer, int maxlen)
{
    float pct = value * 100.0;
    
    if (pct > 99.5)
        Format(buffer, maxlen, "%.4f%%", pct);
    else
        Format(buffer, maxlen, "%.2f%%", pct);
    
}

public Action Timer_DisplayResistanceHUD(Handle timer)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsPlayerAlive(i))
            continue;

        if (g_iResistanceHudMode[i] == 0)
            continue;

        char buffer[256];

        char fireStr[16], bulletStr[16], blastStr[16], critStr[16], meleeStr[16], otherStr[16];
        FormatDamagePercentString(1-g_fDamageTaken[i][DAMAGE_FIRE], fireStr, sizeof(fireStr));
        FormatDamagePercentString(1-g_fDamageTaken[i][DAMAGE_BULLET], bulletStr, sizeof(bulletStr));
        FormatDamagePercentString(1-g_fDamageTaken[i][DAMAGE_BLAST], blastStr, sizeof(blastStr));
        FormatDamagePercentString(1-g_fDamageTaken[i][DAMAGE_CRIT], critStr, sizeof(critStr));
        FormatDamagePercentString(1-g_fDamageTaken[i][DAMAGE_MELEE], meleeStr, sizeof(meleeStr));
        FormatDamagePercentString(1-g_fDamageTaken[i][DAMAGE_OTHER], otherStr, sizeof(otherStr));

        if (g_iResistanceHudMode[i] == 1) // Standard
        {
            Format(buffer, sizeof(buffer), "Fire : %s%%    Bullet : %s%%\nCrit : %s%%    Melee : %s%%\nBlast : %s%%   Other : %s%%",
                fireStr, bulletStr, critStr, meleeStr, blastStr, otherStr);
        }
        else // Abridged
        {
            Format(buffer, sizeof(buffer), "f %s%%        • %s%%\nc %s%%        m %s%%\n# %s%%        o %s%%",
                fireStr, bulletStr, critStr, meleeStr, blastStr, otherStr);
        }

        float x = 0.01, y = 0.3;
        switch (g_iResistHudCorner[i])
        {
            case HUDPOS_LEFT:  { x = 0.01; y = 0.2; }
            case HUDPOS_TOP:   { x = -1.0; y = 0.05; }
            case HUDPOS_RIGHT: { x = 0.8; y = 0.2; }
        }

        SetHudTextParams(x, y, 1.0, 255, 255, 255, 255, 0, 0.0, 0.8, 0.8);
        ShowSyncHudText(i, g_hHudResistSync, buffer);
    }

    return Plugin_Continue;
}


void SetPlayerResistanceSource(int client, DamageType type, const char[] sourceKey, float multiplier)
{
    if (g_resistanceSources[client][type] == null)
        g_resistanceSources[client][type] = new StringMap();

    g_resistanceSources[client][type].SetValue(sourceKey, multiplier);
    RecalculateTotalResistance(client, type);
}

void RecalculateTotalResistance(int client, DamageType type)
{
    float total = 1.0;

    if (g_resistanceSources[client][type] != null)
    {
        StringMapSnapshot snap = g_resistanceSources[client][type].Snapshot();
        for (int i = 0; i < snap.Length; i++)
        {
            char key[64];
            snap.GetKey(i, key, sizeof(key));
            float value;
            g_resistanceSources[client][type].GetValue(key, value);
            total *= value;
            // PrintToServer("[Debug] [%N] Resistance source '%s' → %.6f for type %d", client, key, value, type);
        }
        delete snap;
    }

    g_fDamageTaken[client][type] = total;
    // PrintToServer("[Debug] [%N] Final resistance multiplier for type %d: %.6f", client, type, total);
}

void BuildResistanceKey(const char[] upgradeName, int slot, const char[] slotAlias, char[] buffer, int maxlen)
{
    if (slot == -1)
    {
        // Body upgrade
        Format(buffer, maxlen, "%s%s", upgradeName, slotAlias); // e.g., "*Fire Resistancebody_demoman"
    }
    else
    {
        Format(buffer, maxlen, "%s_slot%d", upgradeName, slot); // e.g., "*Fire Resistance_slot1"
    }
}

void LoadResistanceMappingsFromFile()
{
    char filePath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, filePath, sizeof(filePath), "configs/hu_res_mappings.txt");

    // If file doesn't exist, create a basic template
    if (!FileExists(filePath))
    {
        Handle file = OpenFile(filePath, "w");
        if (file != null)
        {
            WriteFileLine(file, "// Format: DAMAGE_TYPE,Upgrade Name");
            WriteFileLine(file, "// Example: DAMAGE_FIRE,*Fire Resistance");
            WriteFileLine(file, "");
            WriteFileLine(file, "// Available damage types:");
            WriteFileLine(file, "// DAMAGE_FIRE");
            WriteFileLine(file, "// DAMAGE_BULLET");
            WriteFileLine(file, "// DAMAGE_BLAST");
            WriteFileLine(file, "// DAMAGE_CRIT");
            WriteFileLine(file, "// DAMAGE_MELEE");
            WriteFileLine(file, "// DAMAGE_OTHER");

            CloseHandle(file);
        }

        PrintToServer("[Hyper Upgrades] Resistance mapping file not found. Created default template.");
        return;
    }

    Handle file = OpenFile(filePath, "r");
    if (file == null)
    {
        PrintToServer("[Hyper Upgrades] Failed to open hu_res_mappings.txt.");
        return;
    }

    char line[256];
    while (!IsEndOfFile(file) && ReadFileLine(file, line, sizeof(line)))
    {
        TrimString(line);

        // Skip comments or empty lines
        if (line[0] == '\0' || line[0] == '#' || StrContains(line, "//") == 0)
            continue;

        char parts[2][128];
        int count = ExplodeString(line, ",", parts, sizeof(parts), sizeof(parts[]));
        if (count != 2)
        {
            PrintToServer("[Hyper Upgrades] Skipping malformed line in hu_res_mappings.txt: %s", line);
            continue;
        }

        TrimString(parts[0]);
        TrimString(parts[1]);

        DamageType type = ParseDamageType(parts[0]);
        if (type == DAMAGE_COUNT)
        {
            PrintToServer("[Hyper Upgrades] Unknown damage type in mapping: %s", parts[0]);
            continue;
        }

        ResistanceMapping entry;
        strcopy(entry.upgradeName, sizeof(entry.upgradeName), parts[1]);
        entry.type = type;
        g_resistanceMappings.PushArray(entry);
    }

    CloseHandle(file);

    PrintToServer("[Hyper Upgrades] Resistance upgrade mappings loaded.");
}

DamageType ParseDamageType(const char[] str)
{
    if (StrEqual(str, "DAMAGE_FIRE", false)) return DAMAGE_FIRE;
    if (StrEqual(str, "DAMAGE_BULLET", false)) return DAMAGE_BULLET;
    if (StrEqual(str, "DAMAGE_BLAST", false)) return DAMAGE_BLAST;
    if (StrEqual(str, "DAMAGE_CRIT", false)) return DAMAGE_CRIT;
    if (StrEqual(str, "DAMAGE_MELEE", false)) return DAMAGE_MELEE;
    if (StrEqual(str, "DAMAGE_OTHER", false)) return DAMAGE_OTHER;
    return DAMAGE_COUNT; // Invalid
}

void RefreshClientResistances(int client)
{
    // Reset all to 0.0
    for (int i = 0; i < view_as<int>(DAMAGE_COUNT); i++)
    {
        DamageType type = view_as<DamageType>(i);

        if (g_resistanceSources[client][type] != null)
            g_resistanceSources[client][type].Clear();

        g_fDamageTaken[client][type] = 0.0;
    }

    if (g_hPlayerUpgrades[client] == null)
        return;

    KvRewind(g_hPlayerUpgrades[client]);

    if (!KvGotoFirstSubKey(g_hPlayerUpgrades[client], false))
        return;

    do
    {
        char slotName[32];
        KvGetSectionName(g_hPlayerUpgrades[client], slotName, sizeof(slotName));

        int slot = -1;
        if (!StrEqual(slotName, "body"))
        {
            slot = StringToInt(slotName[4]); // slotX → X
        }

        if (!KvGotoFirstSubKey(g_hPlayerUpgrades[client], false))
        {
            KvGoBack(g_hPlayerUpgrades[client]);
            continue;
        }

        do
        {
            char upgradeName[64];
            KvGetSectionName(g_hPlayerUpgrades[client], upgradeName, sizeof(upgradeName));

            float level = KvGetFloat(g_hPlayerUpgrades[client], NULL_STRING, 0.0);
            // PrintToServer("[Debug] [Client %d] Upgrade '%s' has raw level %.6f", client, upgradeName, level);

            // bool matched = false;

            for (int j = 0; j < g_resistanceMappings.Length; j++)
            {
                ResistanceMapping map;
                g_resistanceMappings.GetArray(j, map);

                if (StrEqual(map.upgradeName, upgradeName))
                {
                    char key[64];
                    BuildResistanceKey(upgradeName, slot, slot == -1 ? g_sPlayerAlias[client] : "", key, sizeof(key));

                    float multiplier = 1 - FloatAbs(level);

                    // PrintToServer("[Debug] [Client %d] Adding source '%s' with multiplier %.6f to damage type %d", client, key, multiplier, map.type);

                    SetPlayerResistanceSource(client, map.type, key, multiplier);
                    // matched = true;
                }
            }

            // if (!matched)
            // {
            //     PrintToServer("[Debug] Upgrade '%s' is not mapped to any resistance type.", upgradeName);
            // }
        }
        while (KvGotoNextKey(g_hPlayerUpgrades[client], false));

        KvGoBack(g_hPlayerUpgrades[client]);

    } while (KvGotoNextKey(g_hPlayerUpgrades[client], false));

    KvRewind(g_hPlayerUpgrades[client]);
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
    PrintToServer("[Hyper Upgrades] Weapon aliases reloaded.");
    return Plugin_Handled;
}
// Reload Aliases for Attributes
public Action Command_ReloadAttributesAliases(int client, int args)
{
    g_attributeMappings.Clear();
    LoadAttributeMappings();
    PrintToServer("[Hyper Upgrades] Attributes aliases reloaded.");
    return Plugin_Handled;
}

public Action Command_ReloadUpgrades(int client, int args)
{
    // Clear existing data
    g_upgrades.Clear();
    g_upgradeIndex.Clear();

    // Reload upgrade definitions
    LoadUpgradeData();

    // Reload resistance mappings from config file
    if (g_resistanceMappings != null)
        g_resistanceMappings.Clear();
    else
        g_resistanceMappings = new ArrayList(sizeof(ResistanceMapping));

    LoadResistanceMappingsFromFile();

    PrintToConsole(client, "[Hyper Upgrades] Upgrade definitions reloaded from hu_upgrades.cfg.");
    PrintToConsole(client, "[Hyper Upgrades] Resistance upgrade mappings reloaded from hu_res_mappings.txt.");
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
    g_bInUpgradeList[client] = false;
    Menu menu = new Menu(MenuHandler_MainMenu);
    menu.SetTitle("Hyper Upgrades \nBalance: %d/%d$", GetPlayerBalance(client), GetConVarInt(g_hMoneyPool));

    menu.AddItem("body", "Body Upgrades");
    menu.AddItem("primary", "Primary Upgrades");
    menu.AddItem("secondary", "Secondary Upgrades");
    menu.AddItem("melee", "Melee Upgrades");

    // Add class-specific upgrades only for applicable classes
    //TFClassType class = TF2_GetPlayerClass(client);
    //if (class == TFClass_Spy)
    //{
    //    menu.AddItem("spy", "Spy Upgrades");
    //}
    //else if (class == TFClass_Engineer)
    //{
    //    menu.AddItem("engineer", "Engineer Upgrades");
    //}

    menu.AddItem("refund", "Upgrades List / Refund");
    menu.AddItem("settings", "Settings");
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

// Handle main menu selection
public int MenuHandler_MainMenu(Menu menu, MenuAction action, int client, int param)
{
    if (action == MenuAction_End)
    {
        if (client > 0 && client < MAXPLAYERS+1)
        {
            g_bInUpgradeList[client] = false;
        }
        // PrintToServer("[Debug] MenuAction_End triggered for client %d", client);
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
            ShowRefundSlotMenu(client); // ✅ Launch the refund menu
        }
        //  else if (StrEqual(info, "engineer"))
        // {
        //     ShowCategoryMenu(client, "Engineer Upgrades");
        //     // PrintToServer("[Debug] Showing class-specific upgrades: %s", info);
        // }
        // else if (StrEqual(info, "spy"))
        // {
        //     ShowCategoryMenu(client, "Spy Upgrades");
        //     PrintToServer("[Debug] Showing class-specific upgrades: %s", info);
        // }
        else if (StrEqual(info, "settings"))
        {
            ShowSettingsMenu(client);
        }
    }
    else if (action == MenuAction_Cancel)
    {
        if (param == MenuCancel_ExitBack)
        {
            g_bPlayerBrowsing[client] = false;
            g_bInUpgradeList[client] = false;

            ShowCategoryMenu(client, g_sPlayerCategory[client]);
        }
    }
    return 0;
}

void ShowRefundSlotMenu(int client)
{
    Menu menu = new Menu(MenuHandler_RefundSlotMenu);
    menu.SetTitle("Select Upgrade Group to Refund");

    KvRewind(g_hPlayerUpgrades[client]);

    if (!KvGotoFirstSubKey(g_hPlayerUpgrades[client], false))
    {
        PrintToChat(client, "[Hyper Upgrades] No upgrades to refund.");
        g_bInUpgradeList[client] = false;
        delete menu;
        return;
    }

    do
    {
        char slotName[64];
        KvGetSectionName(g_hPlayerUpgrades[client], slotName, sizeof(slotName));

        if (StrEqual(slotName, "body"))
        {
            menu.AddItem("body", "Body Upgrades");
        }
        else if (StrEqual(slotName, "slot0"))
        {
            menu.AddItem("slot0", "Primary Upgrades");
        }
        else if (StrEqual(slotName, "slot1"))
        {
            menu.AddItem("slot1", "Secondary Upgrades");
        }
        else if (StrEqual(slotName, "slot2"))
        {
            menu.AddItem("slot2", "Melee Upgrades");
        }
        else
        {
            char label[64];
            int slotNum = StringToInt(slotName[4]); // Extract number from 'slotX'
            Format(label, sizeof(label), "Other Upgrades (%d)", slotNum);
            menu.AddItem(slotName, label);
        }

    } while (KvGotoNextKey(g_hPlayerUpgrades[client], false));

    KvRewind(g_hPlayerUpgrades[client]);

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}


// Slot Menu Handler
public int MenuHandler_RefundSlotMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char slotKey[64];
        menu.GetItem(item, slotKey, sizeof(slotKey));

        ShowRefundUpgradeMenu(client, slotKey);
    }
    else if (action == MenuAction_Cancel)
    {
        if (item == MenuCancel_ExitBack)
        {
            g_bInUpgradeList[client] = false;
            ShowMainMenu(client);
        }
    }
    return 0;
}

// Upgrade List for the Slot
void ShowRefundUpgradeMenu(int client, const char[] slotKey)
{
    Menu menu = new Menu(MenuHandler_RefundUpgradeMenu);
    char title[128];
    Format(title, sizeof(title), "Refund Upgrades - %s", slotKey);
    menu.SetTitle(title);

    if (!KvJumpToKey(g_hPlayerUpgrades[client], slotKey, false))
    {
        PrintToChat(client, "[Hyper Upgrades] No upgrades found in this group.");
        g_bInUpgradeList[client] = false;
        delete menu;
        return;
    }

    if (!KvGotoFirstSubKey(g_hPlayerUpgrades[client], false))
    {
        KvGoBack(g_hPlayerUpgrades[client]);
        PrintToChat(client, "[Hyper Upgrades] No upgrades found in this group.");
        return;
    }

    do
    {
        char upgradeName[64];
        KvGetSectionName(g_hPlayerUpgrades[client], upgradeName, sizeof(upgradeName));

        int idx;
        if (g_upgradeIndex.GetValue(upgradeName, idx))
        {
            UpgradeData upgrade;
            g_upgrades.GetArray(idx, upgrade);
            char itemData[128];
            Format(itemData, sizeof(itemData), "%s|%s", upgrade.name, slotKey); // "upgradeName|slotKey"
            menu.AddItem(itemData, upgrade.name);
        }
        else
        {
            char itemData[128];
            Format(itemData, sizeof(itemData), "%s|%s", upgradeName, slotKey);
            menu.AddItem(itemData, upgradeName);
        }

    } while (KvGotoNextKey(g_hPlayerUpgrades[client], false));

    KvGoBack(g_hPlayerUpgrades[client]);
    KvRewind(g_hPlayerUpgrades[client]);

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}


// Handle Refund Action
public int MenuHandler_RefundUpgradeMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char itemData[128];
        menu.GetItem(item, itemData, sizeof(itemData));

        // Split "upgradeName|slotKey" into two parts
        char parts[2][64];
        ExplodeString(itemData, "|", parts, sizeof(parts), sizeof(parts[]));

        char upgradeName[64], slotKey[64];
        strcopy(upgradeName, sizeof(upgradeName), parts[0]);
        strcopy(slotKey, sizeof(slotKey), parts[1]);

        RefundSpecificUpgrade(client, upgradeName, slotKey);  // Updated call
        ApplyPlayerUpgrades(client);
        ShowRefundSlotMenu(client);
    }
    else if (action == MenuAction_Cancel)
    {
        if (item == MenuCancel_ExitBack)
        {
            g_bInUpgradeList[client] = false;
            ShowRefundSlotMenu(client);
        }
    }

    return 0;
}

// Refund Logic
void RefundSpecificUpgrade(int client, const char[] upgradeName, const char[] slotKey)
{
    if (g_hPlayerUpgrades[client] == null)
        return;

    // Navigate directly to the upgrade slot section
    KvRewind(g_hPlayerUpgrades[client]);
    if (!KvJumpToKey(g_hPlayerUpgrades[client], slotKey, false))
    {
        PrintToServer("[Debug] Could not find slot '%s' for refunding upgrade '%s'", slotKey, upgradeName);
        return;
    }

    float level = KvGetFloat(g_hPlayerUpgrades[client], upgradeName, 0.0);
    if (level == 0.0)
    {
        KvGoBack(g_hPlayerUpgrades[client]); // Clean up key state
        return;
    }

    PrintToServer("[Debug] Refunding upgrade '%s' from slot '%s' with level %.6f", upgradeName, slotKey, level);

    int refundAmount = CalculateRefundAmount(upgradeName, level);
    g_iMoneySpent[client] -= refundAmount;
    if (g_iMoneySpent[client] < 0)
        g_iMoneySpent[client] = 0;

    KvDeleteKey(g_hPlayerUpgrades[client], upgradeName);
    KvGoBack(g_hPlayerUpgrades[client]); // Exit from slotKey section

    PrintToConsole(client, "[Hyper Upgrades] Refunded upgrade: %s. Amount refunded: %.0f$", upgradeName, refundAmount);
}

// I like explicit names. Just to be clear, this calculates it for one specific upgrade.
int CalculateRefundAmount(const char[] upgradeName, float currentLevel)
{
    int idx;
    if (!g_upgradeIndex.GetValue(upgradeName, idx))
        return 0;

    UpgradeData upgrade;
    g_upgrades.GetArray(idx, upgrade);

    int baseCost = upgrade.cost;
    int costIncrease = upgrade.costIncrease;
    float increment = upgrade.increment;

    int scale = 1000000;
    if (FloatAbs(currentLevel) > 2000.0)
        scale = 1000;

    int IntCurrentLevel = RoundToNearest(currentLevel * scale);
    int IntIncrement = RoundToNearest(increment * scale);

    if (IntIncrement == 0)
    {
        PrintToServer("[Hyper Upgrades] Warning: Refund for upgrade \"%s\" has increment = 0. Skipping.", upgradeName);
        return 0;
    }

    int purchases = IntCurrentLevel / IntIncrement;

    // Closed-form sum: total = n*baseCost + costIncrease * n*(n-1)/2
    int totalCost = purchases * baseCost + (costIncrease * purchases * (purchases - 1)) / 2;

    return totalCost;
}


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
            // PrintToServer("[Debug] Retrieved alias: %s", alias);
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
    int weaponSlot = -1; // ✅ Declare once at the top to avoid undefined symbol errors

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
        weaponSlot = -1;   // Body upgrades tracked as slot -1
    }
    else if (StrEqual(category, "Engineer Upgrades"))
    {
        strcopy(alias, sizeof(alias), "buildings"); // Hardcoded special alias
        aliasFound = true;
        weaponSlot = -2; // ✅ Special marker for non-slot items like buildings
    }
    else if (StrEqual(category, "Primary Upgrades"))
    {
        int weapon = GetEquippedEntityForSlot(client, 0);
        PrintToServer("[Debug] Slot %d: weapon entity index = %d", 0, weapon);
        if (IsValidEntity(weapon))
        {
            int defindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
            aliasFound = GetWeaponAlias(defindex, alias, sizeof(alias));
            weaponSlot = 0;
        }
    }
    else if (StrEqual(category, "Secondary Upgrades"))
    {
        int weapon = GetEquippedEntityForSlot(client, 1);
        PrintToServer("[Debug] Slot %d: weapon entity index = %d", 1, weapon);
        if (IsValidEntity(weapon))
        {
            int defindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
            aliasFound = GetWeaponAlias(defindex, alias, sizeof(alias));
            weaponSlot = 1;
        }
    }
    else if (StrEqual(category, "Melee Upgrades"))
    {
        int weapon = GetEquippedEntityForSlot(client, 2);
        PrintToServer("[Debug] Slot %d: weapon entity index = %d", 2, weapon);
        if (IsValidEntity(weapon))
        {
            int defindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
            aliasFound = GetWeaponAlias(defindex, alias, sizeof(alias));
            weaponSlot = 2;
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
    g_iPlayerBrowsingSlot[client] = weaponSlot;
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

int GetEquippedEntityForSlot(int client, int slot) // Used to get weapons that aren't in normal slots, comparing with hu_attributes. If conflict, takes the first option.
{
    // Step 1: Try normal weapon slot
    int weapon = GetPlayerWeaponSlot(client, slot);
    if (IsValidEntity(weapon))
    {
        int defindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
        if (defindex > 0)
        {
            return weapon;
        }
    }

    // Step 2: Fallback – scan equipped items with known aliases
    KeyValues kv = new KeyValues("Upgrades");
    char filePath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, filePath, sizeof(filePath), "configs/hu_attributes.cfg");

    if (!kv.ImportFromFile(filePath))
    {
        PrintToServer("[HU] Error loading hu_attributes.cfg");
        delete kv;
        return -1;
    }

    char slotName[32];
    switch (slot)
    {
        case 0: strcopy(slotName, sizeof(slotName), "Primary Upgrades");
        case 1: strcopy(slotName, sizeof(slotName), "Secondary Upgrades");
        case 2: strcopy(slotName, sizeof(slotName), "Melee Upgrades");
        case 3: strcopy(slotName, sizeof(slotName), "Slot3 Upgrades");
        case 4: strcopy(slotName, sizeof(slotName), "Slot4 Upgrades");
        case 5: strcopy(slotName, sizeof(slotName), "Slot5 Upgrades");
        default:
        {
            delete kv;
            return -1;
        }
    }

    // Collect potential alias misses
    ArrayList missingAliases = new ArrayList(64); // store alias strings
    ArrayList missingDefindexes = new ArrayList(); // store corresponding defindexes

    for (int ent = MaxClients + 1; ent < GetMaxEntities(); ent++)
    {
        if (!IsValidEntity(ent)) continue;
        if (!HasEntProp(ent, Prop_Send, "m_hOwnerEntity")) continue;
        if (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") != client) continue;
        if (!HasEntProp(ent, Prop_Send, "m_iItemDefinitionIndex")) continue;

        int defindex = GetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex");
        char alias[64];
        if (!GetWeaponAlias(defindex, alias, sizeof(alias)))
            continue;

        if (!kv.JumpToKey(slotName, false))
            continue;

        if (kv.JumpToKey(alias, false))
        {
            delete kv;
            delete missingAliases;
            delete missingDefindexes;
            return ent; // Found valid match
        }

        kv.GoBack(); // alias not found under this slot

        missingAliases.PushString(alias);
        missingDefindexes.Push(defindex);
    }

    delete kv;

    // Print debug info only if no match found and there were valid aliases missed
    if (missingAliases.Length > 0)
    {
        PrintToServer("[HU] No valid upgrade match found for slot %d. The following equipped items have known aliases but are missing from hu_attributes.cfg:", slot);
        for (int i = 0; i < missingAliases.Length; i++)
        {
            char alias[64];
            missingAliases.GetString(i, alias, sizeof(alias));
            int defindex = missingDefindexes.Get(i);
            PrintToServer("  • alias = \"%s\" (defindex = %d) is not listed under \"%s\"", alias, defindex, slotName);
        }
    }

    delete missingAliases;
    delete missingDefindexes;
    return -1;
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
            g_bInUpgradeList[client] = false;
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

// This one also handles upgrade bought logic, like keybound multipliers.
public int MenuHandler_UpgradeMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (g_MenuClient[i] == i)
            {
                // PrintToServer("[Menu Exit] Client %d exited a menu", i);
                g_bInUpgradeList[i] = false;
                g_MenuClient[i] = 0; // Cleanup
                break;
            }
        }

        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char itemData[64];
        menu.GetItem(item, itemData, sizeof(itemData));
        g_iUpgradeMenuPage[client] = menu.Selection;

        char parts[3][64];
        int count = ExplodeString(itemData, "|", parts, sizeof(parts), sizeof(parts[]));
        if (count != 3)
        {
            PrintToChat(client, "[Hyper Upgrades] Failed to parse item string.");
            return 0;
        }

        int weaponSlot = StringToInt(parts[0]); // Extract weapon slot
        char upgradeName[64];
        strcopy(upgradeName, sizeof(upgradeName), parts[1]); // Extract upgrade name
        char upgradeGroup[64];
        strcopy(upgradeGroup, sizeof(upgradeGroup), parts[2]); // Extract upgrade group

        // Lookup upgrade from memory
        int idx;
        if (!g_upgradeIndex.GetValue(upgradeName, idx))
        {
            PrintToChat(client, "[Hyper Upgrades] Internal error: Upgrade not found in cache.");
            return 0;
        }

        UpgradeData upgrade;
        g_upgrades.GetArray(idx, upgrade);

        char upgradeAlias[64];
        strcopy(upgradeAlias, sizeof(upgradeAlias), upgrade.alias);

        int baseCost = upgrade.cost;
        int costIncrease = upgrade.costIncrease;
        float increment = upgrade.increment;
        float initValue = upgrade.initValue;
        float limit = upgrade.limit;
        bool hasLimit = upgrade.hadLimit;

        float currentLevel = GetPlayerUpgradeLevelForSlot(client, weaponSlot, upgradeName);
        int upgradeMultiplier = g_bInUpgradeList[client] ? GetUpgradeMultiplier(client) : 1;

        // --- Integer scaling for precision ---
        int scale = 1000000;
        if (FloatAbs(limit) > 2000.0 || FloatAbs(currentLevel) > 2000.0)
        {
            scale = 1000;
        }

        int IntCurrentLevel = RoundToNearest(currentLevel * scale);
        int IntInitValue    = RoundToNearest(initValue * scale);
        int IntIncrement    = RoundToNearest(increment * scale);

        int purchases = (IntIncrement != 0) ? (IntCurrentLevel / IntIncrement) : 0;
        int legalMultiplier = upgradeMultiplier;

        // --- Limit enforcement using int scaling ---
        if (hasLimit)
        {
            int IntAppliedCurrent   = IntInitValue + IntCurrentLevel;
            int IntAppliedPotential = IntAppliedCurrent + (IntIncrement * upgradeMultiplier);
            int IntLimit            = RoundToNearest(limit * scale);

            if (IntIncrement > 0 && IntAppliedPotential > IntLimit)
            {
                int room = IntLimit - IntAppliedCurrent;
                legalMultiplier = room / IntIncrement;
            }
            else if (IntIncrement < 0 && IntAppliedPotential < IntLimit)
            {
                int room = IntAppliedCurrent - IntLimit;
                legalMultiplier = room / -IntIncrement;
            }

            if (legalMultiplier > upgradeMultiplier)
                legalMultiplier = upgradeMultiplier;

            if (legalMultiplier <= 0)
            {
                PrintToChat(client, "[Hyper Upgrades] Cannot purchase: would exceed upgrade limit.");
                return 0;
            }
        }

        // 🔸 Linear cost calculation (integer, consistent with refund logic)
        int b = baseCost;
        int n = legalMultiplier;
        int p = purchases;
        int totalCost = n * b + (costIncrease * n * (2 * p + n - 1)) / 2;

        if (g_iMoneySpent[client] + totalCost > GetConVarInt(g_hMoneyPool))
        {
            PrintToChat(client, "[Hyper Upgrades] Not enough money to buy %d levels of this upgrade.", legalMultiplier);
            return 0;
        }

        // Apply the upgrade
        float newLevel = currentLevel + (increment * legalMultiplier);

        char slotPath[16];
        if (weaponSlot == -1)
        {
            strcopy(slotPath, sizeof(slotPath), "body");
        }
        else if (weaponSlot == -2)
        {
            strcopy(slotPath, sizeof(slotPath), "buildings"); // special handling
        }
        else
        {
            Format(slotPath, sizeof(slotPath), "slot%d", weaponSlot);
        }

        KvJumpToKey(g_hPlayerUpgrades[client], slotPath, true);
        KvSetFloat(g_hPlayerUpgrades[client], upgradeName, newLevel);
        KvRewind(g_hPlayerUpgrades[client]);

        ApplyPlayerUpgrades(client);

        // Deduct money
        g_iMoneySpent[client] += totalCost;

        // Feedback
        PrintToConsole(client, "[Hyper Upgrades] Purchased upgrade: %s (+%.2f x%d). Total Cost: %d$",
            upgradeAlias, increment, legalMultiplier, totalCost);

        // Refresh menu
        DataPack dp = new DataPack();
        dp.WriteCell(client);
        dp.WriteString(upgradeGroup);
        CreateTimer(0.0, Timer_DeferMenuReopen, dp);
    }
    else if (action == MenuAction_Cancel)
    {
        // PrintToServer("[Menu Cancel] client = %d, item = %d", client, item);
        g_bInUpgradeList[client] = false;

        if (item == MenuCancel_ExitBack)
        {
            ShowCategoryMenu(client, g_sPlayerCategory[client]);
        }
    }

    return 0;
}

public Action Timer_DeferMenuReopen(Handle timer, DataPack dp)
{
    dp.Reset();
    int client = dp.ReadCell();
    char group[64];
    dp.ReadString(group, sizeof(group));
    delete dp;

    if (IsClientInGame(client) && g_bPlayerBrowsing[client])
    {
        ShowUpgradeListMenu(client, group);
    }

    return Plugin_Stop;
}



public Action Timer_CheckMenuRefresh(Handle timer, any client)
{
    // PrintToServer("[Hyper Upgrades] Client %d | g_bInUpgradeList = %d", client, g_bInUpgradeList[client]);
    // PrintToServer("[Timer] Client %d | This handle: %x | Stored handle: %x", client, timer, g_hRefreshTimer[client]);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        return Plugin_Continue;
    }
    // Only act if player is actively in the upgrade menu
    if (!g_bPlayerBrowsing[client] || !g_bInUpgradeList[client])
    {
        return Plugin_Continue;
    }
    int currentMultiplier = GetUpgradeMultiplier(client);
    
    if (currentMultiplier != g_iPlayerLastMultiplier[client])
    {
        g_iPlayerLastMultiplier[client] = currentMultiplier;

        // PrintToServer("[Timer Refresh] Client %d triggered refresh (multiplier change)", client);
        
        // Defer menu refresh
        DataPack dp = new DataPack();
        dp.WriteCell(client);
        dp.WriteString(g_sPlayerUpgradeGroup[client]);
        CreateTimer(0.0, Timer_DeferMenuRefresh, dp);
    }

    return Plugin_Continue;
}
public Action Timer_DeferMenuRefresh(Handle timer, DataPack dp)
{
    dp.Reset();
    int client = dp.ReadCell();
    char group[64];
    dp.ReadString(group, sizeof(group));
    delete dp;

    if (client >= 1 && client <= MaxClients && IsClientInGame(client) && g_bPlayerBrowsing[client])
    {
        ShowUpgradeListMenu(client, group);
    }

    return Plugin_Stop;
}

void ShowUpgradeListMenu(int client, const char[] upgradeGroup)
{
    if (!g_bPlayerBrowsing[client])
    {
        g_bInUpgradeList[client] = false;
        return;
    }

    // Load hu_attributes.cfg to find the upgrades in the selected group
    char attrFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, attrFile, sizeof(attrFile), "configs/hu_attributes.cfg");

    KeyValues kv = new KeyValues("Upgrades");
    if (!kv.ImportFromFile(attrFile))
    {
        PrintToChat(client, "[Hyper Upgrades] Failed to load attributes config.");
        delete kv;
        g_bInUpgradeList[client] = false;
        return;
    }

    // Jump to the correct location: Category -> Alias -> Group
    bool foundPath = kv.JumpToKey(g_sPlayerCategory[client], false)
                  && kv.JumpToKey(g_sPlayerAlias[client], false)
                  && kv.JumpToKey(upgradeGroup, false);

    if (!foundPath)
    {
        PrintToChat(client, "[Hyper Upgrades] No upgrades found for this item.");
        delete kv;
        g_bInUpgradeList[client] = false;
        return;
    }

    // Get the current multiplier when building the menu
    int multiplier = g_bInUpgradeList[client] ? GetUpgradeMultiplier(client) : 1; 
    g_iPlayerLastMultiplier[client] = multiplier; // Save it for refresh tracking

    // Build the upgrade menu
    Menu upgradeMenu = new Menu(MenuHandler_UpgradeMenu);
    upgradeMenu.SetTitle("%s - %s\nBalance: %d/%d$ | Multiplier: x%d",
        g_sPlayerCategory[client], upgradeGroup,
        GetPlayerBalance(client), GetConVarInt(g_hMoneyPool), multiplier);

    bool bFoundUpgrades = false;

    kv.GotoFirstSubKey(false);
    do
    {
        char upgradeIndex[8];
        kv.GetSectionName(upgradeIndex, sizeof(upgradeIndex));

        char upgradeName[64];
        kv.GetString(NULL_STRING, upgradeName, sizeof(upgradeName));
        TrimString(upgradeName);

        char upgradeAlias[64];
        if (!GetUpgradeAliasFromName(upgradeName, upgradeAlias, sizeof(upgradeAlias)))
        {
            PrintToServer("[Hyper Upgrades] Skipping upgrade with no alias (or name conflicts with alias): \"%s\" in group \"%s\"", upgradeName, upgradeGroup);
            continue;
        }

        int idx;
        if (!g_upgradeIndex.GetValue(upgradeName, idx))
        {
            PrintToServer("[Hyper Upgrades] Skipping unknown upgrade name: \"%s\" in group \"%s\"", upgradeName, upgradeGroup);
            continue;
        }

        UpgradeData upgrade;
        g_upgrades.GetArray(idx, upgrade);

        float increment = upgrade.increment;
        float initValue = upgrade.initValue;
        float limit = upgrade.limit;
        bool hasLimit = upgrade.hadLimit;

        float currentLevel = GetPlayerUpgradeLevelForSlot(client, g_iPlayerBrowsingSlot[client], upgradeName);

        int IntCurrentLevel, IntInitValue, IntIncrement;
        int scale = 1000000;

        if (FloatAbs(limit) > 2000.0 || FloatAbs(currentLevel) > 2000.0)
        {
            scale = 1000;
        }

        IntCurrentLevel = RoundToNearest(currentLevel * scale);
        IntInitValue    = RoundToNearest(initValue * scale);
        IntIncrement    = RoundToNearest(increment * scale);

        int purchases;
        if (IntIncrement != 0)
        {
            purchases = IntCurrentLevel / IntIncrement;
        }
        else
        {
            purchases = 0;
            PrintToServer("[Hyper Upgrades] Warning: Upgrade \"%s\" has increment = 0. Skipping cost scaling.", upgradeName);
        }

        int legalMultiplier = multiplier;

        // --- Limit enforcement using int scaling ---
        if (hasLimit)
        {
            int IntAppliedCurrent   = IntInitValue + IntCurrentLevel;
            int IntAppliedPotential = IntAppliedCurrent + (IntIncrement * multiplier);
            int IntLimit            = RoundToNearest(limit * scale);

            if (IntIncrement > 0 && IntAppliedPotential > IntLimit)
            {
                int room = IntLimit - IntAppliedCurrent;
                legalMultiplier = room / IntIncrement;
            }
            else if (IntIncrement < 0 && IntAppliedPotential < IntLimit)
            {
                int room = IntAppliedCurrent - IntLimit;
                legalMultiplier = room / -IntIncrement;
            }
            if (legalMultiplier > multiplier)
                legalMultiplier = multiplier;
        }

        // --- Cost calculation with base + flat increase ---
        int baseCost = upgrade.cost;
        int costIncrease = upgrade.costIncrease;

        int n = legalMultiplier;
        int p = purchases;
        int totalCost = baseCost * n + (costIncrease * n * (2 * p + n - 1)) / 2;

        char display[128];
        if (legalMultiplier <= 0)
        {
            Format(display, sizeof(display), "%s (%.2f) [MAX]", upgradeName, currentLevel);
        }
        else
        {
            Format(display, sizeof(display), "%s (%.2f) %d$ (x%d)", upgradeName, currentLevel, totalCost, legalMultiplier);
        }

        char itemData[64];
        Format(itemData, sizeof(itemData), "%d|%s|%s", g_iPlayerBrowsingSlot[client], upgradeName, upgradeGroup);

        upgradeMenu.AddItem(itemData, display);
        bFoundUpgrades = true;

    } while (kv.GotoNextKey(false));

    if (!bFoundUpgrades)
    {
        PrintToChat(client, "[Hyper Upgrades] No upgrades available in this group.");
        delete kv;
        delete upgradeMenu;
        g_bInUpgradeList[client] = false;
        return;
    }

    upgradeMenu.ExitBackButton = true;
    g_MenuClient[client] = client;
    upgradeMenu.DisplayAt(client, g_iUpgradeMenuPage[client], MENU_TIME_FOREVER);
    g_bInUpgradeList[client] = true;

    delete kv;

    strcopy(g_sPlayerUpgradeGroup[client], sizeof(g_sPlayerUpgradeGroup[]), upgradeGroup);

    if (!g_bPlayerBrowsing[client])
    {
        g_bInUpgradeList[client] = false;
        return;
    }
}


float GetPlayerUpgradeLevelForSlot(int client, int slot, const char[] upgradeName)
{
    if (g_hPlayerUpgrades[client] == null)
        return 0.0;

    KvRewind(g_hPlayerUpgrades[client]);

    char slotPath[16];
    if (slot == -1)
    {
        strcopy(slotPath, sizeof(slotPath), "body");
    }
    else if (slot == -2)
    {
        strcopy(slotPath, sizeof(slotPath), "buildings"); // ✅ Support building upgrades
    }
    else
    {
        Format(slotPath, sizeof(slotPath), "slot%d", slot);
    }

    if (!KvJumpToKey(g_hPlayerUpgrades[client], slotPath, false))
    {
        // PrintToServer("[DEBUG] False Path");
        return 0.0;
    }

    // 🔍 Debug output to track where it's looking
    // PrintToServer("[DEBUG] GetPlayerUpgradeLevelForSlot(): Looking in [%s] for \"%s\"", slotPath, upgradeName);

    float storedLevel = KvGetFloat(g_hPlayerUpgrades[client], upgradeName, 0.0);

    KvRewind(g_hPlayerUpgrades[client]);

    return storedLevel;
}

bool GetUpgradeAliasFromName(const char[] upgradeName, char[] aliasOut, int maxlen)
{
    int idx;
    if (!g_upgradeIndex.GetValue(upgradeName, idx))
        return false;

    UpgradeData upgrade;
    g_upgrades.GetArray(idx, upgrade);

    strcopy(aliasOut, maxlen, upgrade.alias);
    // PrintToServer("[DEBUG] Upgrade name: %s → alias: %s", upgradeName, upgrade.alias);
    return true;
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

int GetUpgradeMultiplier(int client)
{
    int buttons = GetClientButtons(client);
    bool isCrouching = (buttons & IN_DUCK) != 0;
    bool isReloading = (buttons & IN_RELOAD) != 0;

    if (isCrouching && isReloading)
    {
        return 1000;
    }
    else if (isReloading)
    {
        return 100;
    }
    else if (isCrouching)
    {
        return 10;
    }
    return 1; // Default if neither key is pressed
}

void ApplyPlayerUpgrades(int client)
{
    if (g_hPlayerUpgrades[client] == null)
        return;

    // Clear all existing attributes from the player and their weapons
    TF2Attrib_RemoveAll(client);
    for (int slot = 0; slot <= 5; slot++)
    {
        int weapon = GetPlayerWeaponSlot(client, slot);
        if (IsValidEntity(weapon))
        {
            TF2Attrib_RemoveAll(weapon);
        }
    }

    KvRewind(g_hPlayerUpgrades[client]);

    // Go to the first top-level key (body, slot0, slot1, etc.)
    if (!KvGotoFirstSubKey(g_hPlayerUpgrades[client], false))
        return;

    do
    {
        char slotName[8];
        KvGetSectionName(g_hPlayerUpgrades[client], slotName, sizeof(slotName));

        int weapon = -1;
        bool isBody = StrEqual(slotName, "body");

        if (!isBody)
        {
            // Extract slot number from "slotX"
            int slot = StringToInt(slotName[4]);
            weapon = GetPlayerWeaponSlot(client, slot);
            if (!IsValidEntity(weapon))
                continue;

            // PrintToConsole(client, "[Debug] Applying upgrades to weapon slot %d", slot);
        }
        else
        {
            // PrintToConsole(client, "[Debug] Applying body upgrades");
        }

        // Go inside this slot section (e.g., body or slot0)
        if (!KvGotoFirstSubKey(g_hPlayerUpgrades[client], false))
        {
            KvGoBack(g_hPlayerUpgrades[client]);
            continue;
        }

        // Loop over all upgrade keys in this slot
        do
        {
            char upgradeName[64];
            KvGetSectionName(g_hPlayerUpgrades[client], upgradeName, sizeof(upgradeName));

            float level = KvGetFloat(g_hPlayerUpgrades[client], NULL_STRING, 0.0);

            // PrintToConsole(client, "[Debug] Applying upgrade: %s with stored level %d (parsed level %.2f)", upgradeName, storedLevel, level);

            // Lookup alias from name
            char upgradeAlias[64];
            if (!GetUpgradeAliasFromName(upgradeName, upgradeAlias, sizeof(upgradeAlias)))
            {
                PrintToConsole(client, "[Warning] Alias not found for upgrade name: %s", upgradeName);
                continue;
            }

            // Lookup attribute from alias
            char attributeName[128];
            if (!GetAttributeName(upgradeAlias, attributeName, sizeof(attributeName)))
            {
                PrintToConsole(client, "[Warning] Attribute not found for alias: %s", upgradeAlias);
                continue;
            }

            // Optional: Lookup init value from UpgradeData (if still needed)
            float initValue = 0.0;
            int idx;
            if (g_upgradeIndex.GetValue(upgradeName, idx))
            {
                UpgradeData upgrade;
                g_upgrades.GetArray(idx, upgrade);
                initValue = upgrade.initValue;
            }

            float flevel = initValue + level;

            if (isBody)
            {
                TF2Attrib_SetByName(client, attributeName, flevel);
            }
            else
            {
                TF2Attrib_SetByName(weapon, attributeName, flevel);
            }

        } while (KvGotoNextKey(g_hPlayerUpgrades[client], false));

        KvGoBack(g_hPlayerUpgrades[client]); // Return to slot level

    } while (KvGotoNextKey(g_hPlayerUpgrades[client], false));

    KvRewind(g_hPlayerUpgrades[client]);

    if (g_iResistanceHudMode[client] != 0)
    {
        RefreshClientResistances(client); // Updates the res hud
    }
    PrintToConsole(client, "[Hyper Upgrades] All upgrades have been applied.");
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
    int victim = GetClientOfUserId(event.GetInt("userid"));

    if (attacker <= 0 || !IsClientInGame(attacker)) return;
    if (victim <= 0 || !IsClientInGame(victim)) return;
    if (attacker == victim) return; // Ignore self-kills (e.g., killbind)

    int reward = GetConVarInt(FindConVar("hu_money_per_kill"));
    SetConVarInt(g_hMoneyPool, GetConVarInt(g_hMoneyPool) + reward);
}


public void Event_ObjectiveComplete(Event event, const char[] name, bool dontBroadcast)
{
    if (StrEqual(name, "teamplay_flag_event"))
    {
        int eventType = event.GetInt("eventtype");

        if (eventType != TF_FLAGEVENT_CAPTURED) // defined in tf2_stocks
            return;
    }

    int money = GetConVarInt(FindConVar("hu_money_per_objective"));
    SetConVarInt(g_hMoneyPool, GetConVarInt(g_hMoneyPool) + money);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (StrEqual(classname, "headless_hatman") ||
        StrEqual(classname, "eyeball_boss") ||
        StrEqual(classname, "merasmus") ||
        StrEqual(classname, "tf_zombie") ||
        StrEqual(classname, "tank_boss"))
    {
        SDKHook(entity, SDKHook_OnTakeDamagePost, OnBossDamaged);
        g_bBossRewarded[entity] = false;
        PrintToServer("[Hyper Upgrades] Hooked boss entity: %s (entindex: %d)", classname, entity);
    }
    else if (StrEqual(classname, "obj_sentrygun") ||
             StrEqual(classname, "obj_dispenser") ||
             StrEqual(classname, "obj_teleporter"))
    {
        SDKHook(entity, SDKHook_SpawnPost, OnBuildingSpawned);
        PrintToServer("[Hyper Upgrades] Hooked building entity: %s (entindex: %d)", classname, entity);
    }
}

public void OnEntityDestroyed(int entity)
{
    if (entity > 0 && entity <= MAX_EDICTS)
    {
        g_bBossRewarded[entity] = false;
    }
}

public void OnBossDamaged(int entity, int attacker, int inflictor, float damage, int damagetype)
{
    if (!IsValidEntity(entity) || g_bBossRewarded[entity])
        return;

    int health = GetEntProp(entity, Prop_Data, "m_iHealth");
    if (health > 0)
        return; // Boss still alive

    g_bBossRewarded[entity] = true; // Mark boss as rewarded

    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker))
        return;

    int maxHealth = GetEntProp(entity, Prop_Data, "m_iMaxHealth");
    int healthMultiplier = CalculateBossHealthMultiplier(maxHealth);

    int baseReward = GetConVarInt(FindConVar("hu_money_per_kill"));
    int reward = RoundToNearest(baseReward * float(healthMultiplier));

    SetConVarInt(g_hMoneyPool, GetConVarInt(g_hMoneyPool) + reward);

    PrintToChatAll("[Hyper Upgrades] %N has slain a boss and earned $%d! (×%d health multiplier)", attacker, reward, healthMultiplier);
}

int CalculateBossHealthMultiplier(int maxHealth)
{
    if (maxHealth < 4001)
        return 1; // x1 below threshold

    int tier = 0;
    while (maxHealth >= 4001 && tier < 50)
    {
        maxHealth /= 2;
        tier++;
    }

    return 1 + RoundToNearest(Pow(float(tier), GetConVarFloat(g_hMoneyBossMultiplier)));
}

public void OnBuildingSpawned(int entity)
{
    int builder = GetEntPropEnt(entity, Prop_Send, "m_hBuilder");

    if (!IsClientInGame(builder) || !IsPlayerAlive(builder))
        return;

    char classname[64];
    GetEntityClassname(entity, classname, sizeof(classname));

    // Debug message
    //  ("[Hyper Upgrades] Building spawned: %s by %N", classname, builder);

    ApplyBuildingUpgrades(builder, entity, classname);
}

void ApplyBuildingUpgrades(int client, int entity, const char[] classname)
{
    if (g_hPlayerUpgrades[client] == null)
        return;

    KvRewind(g_hPlayerUpgrades[client]);

    // Decide which alias to use (used in hu_attributes.cfg)
    char alias[64];
    if (StrEqual(classname, "obj_sentrygun"))
        strcopy(alias, sizeof(alias), "sentry");
    else if (StrEqual(classname, "obj_dispenser"))
        strcopy(alias, sizeof(alias), "dispenser");
    else if (StrEqual(classname, "obj_teleporter"))
        strcopy(alias, sizeof(alias), "teleporter");
    else
        return;

    // Jump to the "buildings" section in the player upgrade data
    if (!KvJumpToKey(g_hPlayerUpgrades[client], "buildings", false))
        return;

    // Loop through all upgrades stored directly under "buildings"
    if (!KvGotoFirstSubKey(g_hPlayerUpgrades[client], false))
        return;

    do
    {
        char upgradeName[64];
        KvGetSectionName(g_hPlayerUpgrades[client], upgradeName, sizeof(upgradeName));
        float level = KvGetFloat(g_hPlayerUpgrades[client], NULL_STRING, 0.0);

        // Get attribute alias from name
        char upgradeAlias[64];
        if (!GetUpgradeAliasFromName(upgradeName, upgradeAlias, sizeof(upgradeAlias)))
            continue;

        // Only apply upgrades meant for this building type
        if (!StrContains(upgradeAlias, alias, false)) // Case-insensitive contains check
            continue;

        // Get attribute name from alias
        char attrName[128];
        if (!GetAttributeName(upgradeAlias, attrName, sizeof(attrName)))
            continue;

        // Retrieve initValue from upgrade data
        float initValue = 0.0;
        int idx;
        if (g_upgradeIndex.GetValue(upgradeName, idx))
        {
            UpgradeData upgrade;
            g_upgrades.GetArray(idx, upgrade);
            initValue = upgrade.initValue;
        }

        float finalValue = initValue + level;

        TF2Attrib_SetByName(entity, attrName, finalValue);

        PrintToConsole(client, "[Hyper Upgrades] Applied to building: %s = %.3f (%s)", attrName, finalValue, alias);

    } while (KvGotoNextKey(g_hPlayerUpgrades[client], false));

    KvRewind(g_hPlayerUpgrades[client]);
}

void GenerateConfigFiles()
{
    char filePath[PLATFORM_MAX_PATH];

    

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
            WriteFileLine(file, "}");
            CloseHandle(file);
        }
    }
}
