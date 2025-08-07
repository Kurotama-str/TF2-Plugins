#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>
#include <tf_econ_data>
#include <tf_custom_attributes>

#include <stocksoup/handles>
//#include <stocksoup/memory>


#define TF_ITEMDEF_DEFAULT -1
#define MAX_EDICTS 2048

#define PLUGIN_NAME "Hyper Upgrades"
#define PLUGIN_VERSION "0.B2"
#define CONFIG_ATTR "hu_attributes.cfg"
#define CONFIG_UPGR "hu_upgrades.cfg"
#define CONFIG_WEAP "hu_weapons_list.txt"
#define CONFIG_ALIAS "hu_alias_list.txt"
#define TRANSLATION_FILE "hu_translations.txt"

ConVar g_hMoneyBossMultiplier;
ConVar g_hMoreUpgrades;
ConVar g_hMvmMode;

bool g_bBossRewarded[MAX_EDICTS + 1];
bool g_bMenuPressed[MAXPLAYERS + 1];
bool g_bPlayerBrowsing[MAXPLAYERS + 1];
bool g_bShowMoneyHud[MAXPLAYERS + 1];
bool g_bInUpgradeList[MAXPLAYERS + 1];

bool g_bHasCustomAttributes = false; // checks if Custom Attributes is loaded
bool g_bMvMActive = false;

char g_sPlayerCategory[MAXPLAYERS + 1][64];
char g_sPlayerAlias[MAXPLAYERS + 1][64];
char g_sPlayerUpgradeGroup[MAXPLAYERS + 1][64];
char g_sPreviousAliases[MAXPLAYERS + 1][6][64]; // 6 slots, 64-char alias - tracks weapon alias for slot
char g_sCurrentMission[64]; // mvm mission name if applicable

int g_MenuClient[MAXPLAYERS + 1];
int g_iUpgradeMenuPage[MAXPLAYERS + 1];

Handle g_hMoneyPool;
int g_iMoneySpent[MAXPLAYERS + 1];

ConVar g_hMoneyPerObjective;

Handle g_hPlayerUpgrades[MAXPLAYERS + 1];
Handle g_hPlayerPurchases[MAXPLAYERS + 1];
int g_iPlayerBrowsingSlot[MAXPLAYERS + 1];
ConVar g_hResetMoneyPoolOnMapStart;

Handle g_hRefreshTimer[MAXPLAYERS + 1] = { INVALID_HANDLE, ... };
int g_iPlayerLastMultiplier[MAXPLAYERS + 1];

Handle g_hHudMoneySync;
Handle g_hHudResistSync;
Handle g_hHudDamageSync;
Handle g_hCurrencySyncTimer = null;

Database g_hSettingsDB;

//MvM wave snapshot
int g_iMoneyPoolSnapshot = 0;
int g_iMoneySpentSnapshot[MAXPLAYERS + 1];
Handle g_hPlayerUpgradesSnapshot[MAXPLAYERS + 1];
Handle g_hPlayerPurchasesSnapshot[MAXPLAYERS + 1];

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

// --- Damage Types for Res HUD ---
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

enum DamageHudPosition
{
    DMGHUD_TOP = 0,
    DMGHUD_BOTTOM,
    DMGHUD_LEFT,
    DMGHUD_RIGHT
};
DamageHudPosition g_iDamageHudPosition[MAXPLAYERS + 1];

float g_fDamageTaken[MAXPLAYERS + 1][DAMAGE_COUNT];
StringMap g_resistanceSources[MAXPLAYERS + 1][DAMAGE_COUNT];
ArrayList g_resistanceMappings; 
enum struct ResistanceMapping
{
    char upgradeName[64];
    DamageType type;
}

int g_iResistanceHudMode[MAXPLAYERS + 1]; // 0 = off, 1 = standard, 2 = abridged

enum struct EquippedItem // Used to help with wearables
{
    int entity;
    int defindex;
    char alias[64];
}

int g_iDamageTypeHudMode[MAXPLAYERS + 1]; // 0 = off, 1 = basic, 2 = verbose

enum DmgFlagType
{
    DFLAG_GENERIC,
    DFLAG_DIRECT,
    DFLAG_CRUSH,
    DFLAG_CRIT,
    DFLAG_BULLET,
    DFLAG_SLASH,
    DFLAG_BUCKSHOT,
    DFLAG_BURN,
    DFLAG_IGNITE,
    DFLAG_CLUB,
    DFLAG_SHOCK,
    DFLAG_SONIC,
    DFLAG_BLAST,
    DFLAG_BLAST_SURFACE,
    DFLAG_ACID,
    DFLAG_POISON,
    DFLAG_RADIATION,
    DFLAG_DROWN,
    DFLAG_DROWNRECOVER,
    DFLAG_PARALYZE,
    DFLAG_NERVEGAS,
    DFLAG_SLOWBURN,
    DFLAG_PLASMA,
    DFLAG_AIRBOAT,
    DFLAG_VEHICLE,
    DFLAG_DISSOLVE,
    DFLAG_PREVENT_PHYSICS_FORCE,
    DFLAG_USE_HITLOCATIONS,
    DFLAG_NOCLOSEDISTANCEMOD,
    DFLAG_USEDISTANCEMOD,
    DFLAG_HALF_FALLOFF,
    DFLAG_NEVERGIB,
    DFLAG_ALWAYSGIB,
    DFLAG_REMOVENORAGDOLL,
    DFLAG_ENERGYBEAM,
    DFLAG_RADIUS_MAX,
    DFLAG_PHYSGUN,
    DFLAG_COUNT
};

static const int g_DmgFlagBits[DFLAG_COUNT] = {
    DMG_GENERIC,
    DMG_DIRECT,
    DMG_CRUSH,
    DMG_CRIT,
    DMG_BULLET,
    DMG_SLASH,
    DMG_BUCKSHOT,
    DMG_BURN,
    DMG_IGNITE,
    DMG_CLUB,
    DMG_SHOCK,
    DMG_SONIC,
    DMG_BLAST,
    DMG_BLAST_SURFACE,
    DMG_ACID,
    DMG_POISON,
    DMG_RADIATION,
    DMG_DROWN,
    DMG_DROWNRECOVER,
    DMG_PARALYZE,
    DMG_NERVEGAS,
    DMG_SLOWBURN,
    DMG_PLASMA,
    DMG_AIRBOAT,
    DMG_VEHICLE,
    DMG_DISSOLVE,
    DMG_PREVENT_PHYSICS_FORCE,
    DMG_USE_HITLOCATIONS,
    DMG_NOCLOSEDISTANCEMOD,
    DMG_USEDISTANCEMOD,
    DMG_HALF_FALLOFF,
    DMG_NEVERGIB,
    DMG_ALWAYSGIB,
    DMG_REMOVENORAGDOLL,
    DMG_ENERGYBEAM,
    DMG_RADIUS_MAX,
    DMG_PHYSGUN
};

static const char g_DmgFlagNames[DFLAG_COUNT][] = {
    "Generic",
    "Direct",
    "Crush",
    "Crit",
    "Bullet",
    "Slash",
    "Buckshot",
    "Burn",
    "Ignite",
    "Club",
    "Shock",
    "Sonic",
    "Blast",
    "Blast Surface",
    "Acid",
    "Poison",
    "Radiation",
    "Drown",
    "Drown Recovery",
    "Paralyze",
    "Nervegas",
    "Slowburn",
    "Plasma",
    "Airboat",
    "Vehicle",
    "Dissolve",
    "Physics",
    "Hit Location",
    "NCD Mod",
    "UD Mod",
    "Half Falloff",
    "Nevergib",
    "Alwaysgib",
    "Ragdoll Removal",
    "Energybeam",
    "Max Radius",
    "Physgun"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_buy", Command_OpenMenu);
    RegConsoleCmd("sm_shop", Command_OpenMenu);

    RegAdminCmd("hu_addmoney", Command_AddMoney, ADMFLAG_GENERIC, "Add money to the pool.");
    RegAdminCmd("mvm_addcash", Command_AddMvMCash, ADMFLAG_CHEATS, "Adds MvM credits to all active players");
    RegAdminCmd("hu_subtmoney", Command_SubtractMoney, ADMFLAG_GENERIC, "Subtract money from the pool.");
    RegAdminCmd("hu_attscan", Cmd_AttributeScanner, ADMFLAG_GENERIC, "Scan a client's attribute values");

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("teamplay_point_captured", Event_ObjectiveComplete, EventHookMode_Post);
    HookEvent("teamplay_flag_event", Event_ObjectiveComplete, EventHookMode_Post);
    HookEvent("teamplay_round_win", Event_ObjectiveComplete, EventHookMode_Post);
    HookEvent("player_changeclass", Event_PlayerChangeClass, EventHookMode_Post);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("mvm_begin_wave", Event_MvmWaveBegin, EventHookMode_Post);
    HookEvent("mvm_wave_failed", Event_MvmWaveFailed, EventHookMode_Post);
    HookEvent("mvm_reset_stats", OnMissionReset, EventHookMode_PostNoCopy);

    CreateConVar("hu_money_pool", "0", "Current money pool shared by all players.");
    CreateConVar("hu_money_per_kill", "10", "Money gained per kill.");
    CreateConVar("hu_money_per_objective", "30", "Money gained per objective.");
    CreateConVar("hu_money_boss_multiplier", "2", "Multiplier for boss kills.");
    CreateConVar("hu_moreupgrades", "0", "Allow precise limit upgrade behavior. 0 = snap to limit, 1 = divide increment, else =  old behavior");
    g_hMvmMode = CreateConVar("hu_mvm_mode", "0", "Hyper Upgrades MvM mode. 0 = auto, 1 = manual disable, 2 = manual enable.", FCVAR_NOTIFY);

    g_hMoneyBossMultiplier = FindConVar("hu_money_boss_multiplier");
    g_hMoreUpgrades = FindConVar("hu_moreupgrades");
    g_hMoneyPool = FindConVar("hu_money_pool");
    g_hMoneyPerObjective = FindConVar("hu_money_per_objective");

    LoadTranslations(TRANSLATION_FILE);

    GenerateConfigFiles();

    RegAdminCmd("hu_reloadweapons", Command_ReloadWeaponAliases, ADMFLAG_GENERIC, "Reload the weapon aliases.");
    RegAdminCmd("hu_reloadattalias", Command_ReloadAttributesAliases, ADMFLAG_GENERIC, "Reload the attributes aliases.");
    RegAdminCmd("hu_reloadupgrades", Command_ReloadUpgrades, ADMFLAG_GENERIC, "Reload the upgrade data from hu_upgrades.cfg");

    RegAdminCmd("hu_debugupghandle", Command_DebugUpgradeHandle, ADMFLAG_ROOT, "Dump the current upgrade array of the first valid player.");
    RegAdminCmd("hu_debugpurhandle", Command_DebugPurchaseHandle, ADMFLAG_GENERIC, "Debug Hyper Upgrades purchase tree.");

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
    g_hHudDamageSync = CreateHudSynchronizer();

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
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
            if (g_hRefreshTimer[i] == INVALID_HANDLE)
            {
                g_hRefreshTimer[i] = CreateTimer(0.2, Timer_CheckMenuRefresh, i, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
            }
        }
    }

    // Reset upgrades for all connected players
    ResetAllPlayerUpgrades();

    g_hResetMoneyPoolOnMapStart = CreateConVar("hu_reset_money_on_mapstart", "1", "Reset the money pool to 0 on map start. 1 = Enabled, 0 = Disabled.", FCVAR_NOTIFY);

    // Notify of Custom Attributes support
    g_bHasCustomAttributes = LibraryExists("tf2custattr");
    if (g_bHasCustomAttributes)
    {
        PrintToServer("[Hyper Upgrades] Custom Attributes support is enabled.");
    }
}

public void OnPluginEnd()
{
    // Notify and clean up each player
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;

        PrintToChat(i, "\x04[HU] \x01Hyper Upgrades reloaded, you may need to change class.");

        /* TF2_RemoveAllWeapons(i);

        int ent = -1;
        while ((ent = FindEntityByClassname(ent, "tf_wearable")) != -1)
        {
            if (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") == i)
            {
                AcceptEntityInput(ent, "Kill");
            }
        }*/

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
        // Delete per-player upgrade maps
        if (g_hPlayerPurchases[i] != null)
        {
            delete g_hPlayerPurchases[i];
            g_hPlayerPurchases[i] = null;
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

    if (g_hCurrencySyncTimer != null)
    {
        KillTimer(g_hCurrencySyncTimer);
        g_hCurrencySyncTimer = null;
    }
}

// Checks for libraries like Custom Upgrades
public void OnLibraryAdded(const char[] name) 
{
    if (StrEqual(name, "tf2custattr"))
    {
        g_bHasCustomAttributes = true;
        PrintToServer("[Hyper Upgrades] Custom Attributes plugin detected.");
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "tf2custattr"))
    {
        g_bHasCustomAttributes = false;
        PrintToServer("[Hyper Upgrades] Custom Attributes plugin unloaded.");
    }
}

//Client Handling
public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
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
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

// Main safety for weapon changes
public Action OnWeaponEquip(int client, int weapon)
{
    g_bInUpgradeList[client] = false;
    CancelClientMenu(client, true);
    // Defensive: only respond to valid weapon assignments
    if (!IsValidEntity(weapon) || !IsClientInGame(client))
        return Plugin_Continue;

    // Optionally: skip if weapon was already equipped
    static int lastEquipped[MAXPLAYERS + 1][6];
    int defindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");

    bool alreadySeen = false;
    for (int i = 0; i < 6; i++)
    {
        if (lastEquipped[client][i] == defindex)
        {
            alreadySeen = true;
            break;
        }
    }

    if (!alreadySeen)
    {
        // Track the weapon
        for (int i = 0; i < 6; i++)
        {
            if (lastEquipped[client][i] == 0)
            {
                lastEquipped[client][i] = defindex;
                break;
            }
        }

        CheckAndHandleWeaponAliasChange(client);
    }

    return Plugin_Continue;
}

// Damage Taken Handling

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!IsClientInGame(victim) || !IsPlayerAlive(victim))
        return Plugin_Continue;

    char typeString[256];
    int mode = g_iDamageTypeHudMode[victim];

    if (mode == 1)
    {
        FormatSimplifiedDamageFlags(damagetype, typeString, sizeof(typeString));
    }
    else if (mode == 2)
    {
        FormatDamageFlags(damagetype, typeString, sizeof(typeString));
        PrintToConsole(victim, "[HU] You took %.1f damage of type(s): %s", damage, typeString);
    }
    else // mode 0 or invalid = do nothing
    {
        return Plugin_Continue;
    }

    float x = -1.0, y = 0.35;

    switch (g_iDamageHudPosition[victim])
    {
        case DMGHUD_BOTTOM: y = 0.55;
        case DMGHUD_LEFT:   x = 0.15, y = -1.0;
        case DMGHUD_RIGHT:  x = 0.75, y = -1.0;
        // default = top/center
    }

    SetHudTextParams(x, y, 2.0, 255, 128, 128, 255, 0, 0.0, 0.1, 2.0);
    ShowSyncHudText(victim, g_hHudDamageSync, typeString);

    return Plugin_Continue;
}

//Map Handling
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
    CheckMvMMapMode();
}

// Database Handling
public void OnSafeSettingsQueryResult(Database db, DBResultSet results, const char[] error, any client)
{
    if (results == null || error[0] != '\0')
    {
        PrintToServer("[Warning] Failed to query settings for client %N: %s", client, error);
        return;
    }

    if (results.FetchRow())
    {
        if (results.FieldCount < 6)
        {
            PrintToServer("[Warning] Settings row for client %N is missing columns. Using defaults.", client);
            g_bShowMoneyHud[client] = true;
            g_iHudCorner[client] = HUD_BOTTOM_RIGHT;
            g_iResistanceHudMode[client] = 0;
            g_iResistHudCorner[client] = HUDPOS_LEFT;
            g_iDamageTypeHudMode[client] = 0;
            g_iDamageHudPosition[client] = DMGHUD_TOP;

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

        g_iDamageTypeHudMode[client] = results.FetchInt(4);

        char dmgPosStr[16];
        results.FetchString(5, dmgPosStr, sizeof(dmgPosStr));
        g_iDamageHudPosition[client] = ParseDamageHudPosition(dmgPosStr);

        // PrintToServer("[Debug] [%N] dmg_hud_mode=%d", client, g_iDamageTypeHudMode[client]);
    }
    else
    {
        PrintToServer("[Info] No settings found for client %N. Applying defaults.", client);
        g_bShowMoneyHud[client] = true;
        g_iHudCorner[client] = HUD_BOTTOM_RIGHT;
        g_iResistanceHudMode[client] = 0;
        g_iResistHudCorner[client] = HUDPOS_LEFT;
        g_iDamageTypeHudMode[client] = 0;

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
    bool hasDamageHudMode = false;
    bool hasDamageHudPos = false;

    while (SQL_FetchRow(results))
    {
        char columnName[64];
        SQL_FetchString(results, 1, columnName, sizeof(columnName));

        if (StrEqual(columnName, "resistance_hud_mode"))
            hasResistHudMode = true;
        else if (StrEqual(columnName, "resistance_hud_pos"))
            hasResistHudPos = true;
        else if (StrEqual(columnName, "damage_type_hud_mode"))
            hasDamageHudMode = true;
        else if (StrEqual(columnName, "damage_type_hud_pos"))
            hasDamageHudPos = true;
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

    if (!hasDamageHudMode)
    {
        PrintToServer("[Hyper Upgrades] Adding missing column 'damage_type_hud_mode' to settings table...");
        SQL_FastQuery(g_hSettingsDB, "ALTER TABLE settings ADD COLUMN damage_type_hud_mode INTEGER DEFAULT 1;");
    }
    if (!hasDamageHudPos)
    {
        SQL_FastQuery(g_hSettingsDB, "ALTER TABLE settings ADD COLUMN damage_type_hud_pos TEXT DEFAULT 'top';");
    }
}

//Events
public void Event_PlayerChangeClass(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (IsClientInGame(client))
    {
        g_bInUpgradeList[client] = false;
        CancelClientMenu(client, true);
        RefundPlayerUpgrades(client, false);
        RefreshClientResistances(client);
    }
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));

    if (attacker <= 0 || !IsClientInGame(attacker)) return;
    if (victim <= 0 || !IsClientInGame(victim)) return;
    if (attacker == victim) return; // Ignore self-kills (e.g., killbind)
    

    if (!g_bMvMActive)
    {
        // Classic mode kill reward
        int reward = GetConVarInt(FindConVar("hu_money_per_kill"));
        SetConVarInt(g_hMoneyPool, GetConVarInt(g_hMoneyPool) + reward);
    }

    // Force upgrade menu exit on death
    int client = victim;
    if (IsClientInGame(client))
    {
        g_bInUpgradeList[client] = false;
        CancelClientMenu(client, true);
    }
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (IsClientInGame(client))
    {
        g_bInUpgradeList[client] = false;
        CancelClientMenu(client, true);
        CheckAndHandleWeaponAliasChange(client);
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

void CheckAndHandleWeaponAliasChange(int client)
{
    for (int slot = 0; slot <= 5; slot++)
    {
        EquippedItem item;
        item = GetEquippedEntityForSlot(client, slot);

        if (!StrEqual(g_sPreviousAliases[client][slot], item.alias))
        {
            PrintToServer("[HU] Alias changed for client %N slot %d: %s → %s",
                          client, slot,
                          g_sPreviousAliases[client][slot],
                          item.alias);

            RefundAllUpgradesInSlot(client, slot);
            strcopy(g_sPreviousAliases[client][slot], sizeof(g_sPreviousAliases[][]), item.alias);
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

    SQL_FastQuery(g_hSettingsDB, "CREATE TABLE IF NOT EXISTS settings (steamid TEXT PRIMARY KEY, show_money_hud INTEGER, hud_position TEXT DEFAULT 'bottom-right', resistance_hud_mode INTEGER DEFAULT 0, resistance_hud_pos TEXT DEFAULT 'left', damage_type_hud_mode INTEGER DEFAULT 1, damage_type_hud_pos TEXT DEFAULT 'top');");

    EnsureSettingsSchemaUpToDate();

    SQL_UnlockDatabase(g_hSettingsDB);
}

void LoadPlayerSettings(int client)
{
    if (g_hSettingsDB == null || !IsClientAuthorized(client))
        return;

    char steamid[32], query[320];
    GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid), true);
    
    Format(query, sizeof(query),
        "SELECT show_money_hud, hud_position, resistance_hud_mode, resistance_hud_pos, damage_type_hud_mode, damage_type_hud_pos FROM settings WHERE steamid = '%s'",
        steamid
    );

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
    menu.AddItem("toggle_damage_hud", "Toggle Damage Type HUD");
    menu.AddItem("open_dmg_hud_pos_menu", "Damage Taken HUD Position");

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
        else if (StrEqual(info, "toggle_damage_hud"))
        {
            ToggleDamageHudSetting(client);
        }
        else if (StrEqual(info, "open_dmg_hud_pos_menu"))
        {
            ShowDamageHudPositionMenu(client);
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

    char dmgPosStr[32];
    DamageHudPositionToString(g_iDamageHudPosition[client], dmgPosStr, sizeof(dmgPosStr));

    char query[512];
    Format(query, sizeof(query), "REPLACE INTO settings (steamid, show_money_hud, hud_position, resistance_hud_mode, resistance_hud_pos, damage_type_hud_mode, damage_type_hud_pos) VALUES ('%s', %d, '%s', %d, '%s', %d, '%s')",
        steamid,
        g_bShowMoneyHud[client] ? 1 : 0,
        posStr,
        g_iResistanceHudMode[client],
        resistPosStr,
        g_iDamageTypeHudMode[client],
        dmgPosStr
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

DamageHudPosition ParseDamageHudPosition(const char[] str)
{
    if (StrEqual(str, "bottom", false)) return DMGHUD_BOTTOM;
    if (StrEqual(str, "left", false)) return DMGHUD_LEFT;
    if (StrEqual(str, "right", false)) return DMGHUD_RIGHT;
    return DMGHUD_TOP;
}

void DamageHudPositionToString(DamageHudPosition pos, char[] buffer, int maxlen)
{
    switch (pos)
    {
        case DMGHUD_BOTTOM: strcopy(buffer, maxlen, "bottom");
        case DMGHUD_LEFT:   strcopy(buffer, maxlen, "left");
        case DMGHUD_RIGHT:  strcopy(buffer, maxlen, "right");
        default:            strcopy(buffer, maxlen, "top");
    }
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

void ToggleDamageHudSetting(int client)
{
    g_iDamageTypeHudMode[client] = (g_iDamageTypeHudMode[client] + 1) % 3;
    SavePlayerSettings(client);

    char modeName[16];

    switch (g_iDamageTypeHudMode[client])
    {
        case 0: Format(modeName, sizeof(modeName), "Off");
        case 1: Format(modeName, sizeof(modeName), "Basic");
        case 2: Format(modeName, sizeof(modeName), "Verbose");
    }

    PrintToChat(client, "[Settings] Damage Type HUD mode set to: %s", modeName);
}

void ShowDamageHudPositionMenu(int client)
{
    Menu menu = new Menu(MenuHandler_DamageHudPosition);
    menu.SetTitle("Select Damage HUD Position:");

    menu.AddItem("top", "Top (above crosshair)");
    menu.AddItem("bottom", "Bottom (below crosshair)");
    menu.AddItem("left", "Left");
    menu.AddItem("right", "Right");

    menu.ExitBackButton = true;
    menu.Display(client, 20);
}

public int MenuHandler_DamageHudPosition(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(item, info, sizeof(info));
        g_iDamageHudPosition[client] = ParseDamageHudPosition(info);
        SavePlayerSettings(client);

        char buffer[16];
        DamageHudPositionToString(g_iDamageHudPosition[client], buffer, sizeof(buffer));
        PrintToChat(client, "[Settings] Damage HUD position set to: %s", buffer);

        ShowSettingsMenu(client); // re-open main menu
    }

    return 0;
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
    }
    g_hPlayerUpgrades[client] = CreateKeyValues("Upgrades"); // Fresh Upgrades
    // Clear the KeyValues purchases
    if (g_hPlayerPurchases[client] != null)
    {
        CloseHandle(g_hPlayerPurchases[client]); // Delete all stored purchases
    }
    g_hPlayerPurchases[client] = CreateKeyValues("Purchases"); // Fresh purchases
    

    // Reset money spent
    g_iMoneySpent[client] = 0;

    if (bShowMessage)
    {
        PrintToChat(client, "[Hyper Upgrades] All upgrades refunded.");
    }
}

void RefundAllPlayersUpgrades()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            RefundPlayerUpgrades(i);
        }
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

public Action Cmd_AttributeScanner(int admin, int args)
{
    if (args < 2)
    {
        PrintToServer("[Hyper Upgrades] Usage: hu_attscan <client> <attribute_name> [vanilla=0|1]");
        return Plugin_Handled;
    }

    char clientStr[64];
    GetCmdArg(1, clientStr, sizeof(clientStr));

    int client = 0;

    // Try to parse as client index
    if (StrToInt(clientStr, client) && client >= 1 && client <= MaxClients && IsClientInGame(client))
    {
        // valid client index
    }
    else
    {
        // Try to find by name
        client = FindClientByName(clientStr);
        if (client == 0)
        {
            PrintToServer("[Hyper Upgrades] Could not find client '%s'", clientStr);
            return Plugin_Handled;
        }
    }

    char attrName[64];
    GetCmdArg(2, attrName, sizeof(attrName));

    bool isVanilla = true;
    if (args >= 3)
    {
        char vanillaArg[8];
        GetCmdArg(3, vanillaArg, sizeof(vanillaArg));
        isVanilla = (StringToInt(vanillaArg) != 0);
    }

    PrintToServer("[Hyper Upgrades] Scanning client %N for attribute '%s' (%s)", client, attrName, isVanilla ? "vanilla" : "custom");

    float total = 0.0;

    // Check attribute on player entity
    if (isVanilla)
    {
        Address addr = TF2Attrib_GetByName(client, attrName);
        if (addr != Address_Null)
        {
            float val = TF2Attrib_GetValue(addr);
            total += val;
            PrintToServer("[AttributeScan] Client entity %d value: %.3f", client, val);
        }
    }
    else
    {
        float val = TF2CustAttr_GetFloat(client, attrName);
        if (val != 0.0)
        {
            total += val;
            PrintToServer("[AttributeScan] Client entity %d value: %.3f", client, val);
        }
    }

    // Scan equipped entities
    int maxEntities = GetMaxEntities();
    for (int ent = MaxClients + 1; ent < maxEntities; ent++)
    {
        if (!IsValidEntity(ent))
            continue;

        if (!IsEquippedByClient(ent, client))
            continue;

        if (isVanilla)
        {
            Address addr = TF2Attrib_GetByName(ent, attrName);
            if (addr == Address_Null)
                continue;

            float val = TF2Attrib_GetValue(addr);
            if (val == 0.0)
                continue;

            total += val;
            char classname[64];
            GetEntityClassname(ent, classname, sizeof(classname));
            PrintToServer("[AttributeScan] Entity %d (%s) value: %.3f", ent, classname, val);
        }
        else
        {
            float val = TF2CustAttr_GetFloat(ent, attrName);
            if (val == 0.0)
                continue;

            total += val;
            char classname[64];
            GetEntityClassname(ent, classname, sizeof(classname));
            PrintToServer("[AttributeScan] Entity %d (%s) value: %.3f", ent, classname, val);
        }
    }

    PrintToServer("[Hyper Upgrades] Total attribute value for client %N: %.3f", client, total);

    return Plugin_Handled;
}

bool IsEquippedByClient(int ent, int client)
{
    if (!IsValidEntity(ent)) return false;
    if (!HasEntProp(ent, Prop_Send, "m_hOwnerEntity")) return false;
    return (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") == client);
}

int FindClientByName(const char[] name)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;

        char clientName[64];
        GetClientName(i, clientName, sizeof(clientName));

        if (StrContains(clientName, name, false) != -1)
            return i;
    }
    return 0;
}

bool StrToInt(const char[] str, int &value)
{
    // StringToInt returns 0 if parsing fails, so we need to check explicitly
    // We'll assume that if str starts with a digit or '-' it is valid
    if (str[0] == '\0')
        return false;

    if ((str[0] >= '0' && str[0] <= '9') || str[0] == '-')
    {
        value = StringToInt(str);
        return true;
    }

    return false;
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
    //    menu.AddItem("engineer", "PDA Upgrades");
    //    menu.AddItem("engineer", "Building Upgrades");
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
        // else if (StrEqual(info, "spy"))
        // {
        //     ShowCategoryMenu(client, "Spy Upgrades");
        //     PrintToServer("[Debug] Showing class-specific upgrades: %s", info);
        // }
        //  else if (StrEqual(info, "engineer"))
        // {
        //     ShowCategoryMenu(client, "PDA Upgrades");
        //     // PrintToServer("[Debug] Showing class-specific upgrades: %s", info);
        //     ShowCategoryMenu(client, "Building Upgrades");
        //     // PrintToServer("[Debug] Showing class-specific upgrades: %s", info);
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
    if (g_hPlayerUpgrades[client] == null || g_hPlayerPurchases[client] == null)
        return;

    // Step 1: Look up purchases to determine refund
    KvRewind(g_hPlayerPurchases[client]);
    if (!KvJumpToKey(g_hPlayerPurchases[client], slotKey, false))
    {
        PrintToServer("[Debug] Could not find purchases slot '%s' for upgrade '%s'", slotKey, upgradeName);
        return;
    }

    int purchases = KvGetNum(g_hPlayerPurchases[client], upgradeName, 0);
    if (purchases <= 0)
    {
        KvGoBack(g_hPlayerPurchases[client]);
        return;
    }

    KvGoBack(g_hPlayerPurchases[client]);

    // Step 2: Lookup the actual value for debug info
    KvRewind(g_hPlayerUpgrades[client]);
    if (!KvJumpToKey(g_hPlayerUpgrades[client], slotKey, false))
    {
        PrintToServer("[Debug] Could not find upgrades slot '%s' for refunding upgrade '%s'", slotKey, upgradeName);
        return;
    }

    float value = KvGetFloat(g_hPlayerUpgrades[client], upgradeName, 0.0);
    KvGoBack(g_hPlayerUpgrades[client]);

    PrintToServer("[Debug] Refunding upgrade '%s' from slot '%s' (value=%.6f, purchases=%d)", upgradeName, slotKey, value, purchases);

    int refundAmount = CalculateRefundAmountFromPurchases(upgradeName, purchases);
    g_iMoneySpent[client] -= refundAmount;
    if (g_iMoneySpent[client] < 0)
        g_iMoneySpent[client] = 0;

    // Step 3: Build new handles
    KeyValues tempUpgrades = CreateKeyValues("Upgrades");
    KeyValues tempPurchases = CreateKeyValues("Purchases");

    // Rebuild UPGRADES handle
    KvRewind(g_hPlayerUpgrades[client]);
    if (KvGotoFirstSubKey(g_hPlayerUpgrades[client], false))
    {
        do
        {
            char currentSlot[64];
            KvGetSectionName(g_hPlayerUpgrades[client], currentSlot, sizeof(currentSlot));
            bool matchSlot = StrEqual(currentSlot, slotKey);

            if (KvGotoFirstSubKey(g_hPlayerUpgrades[client], false))
            {
                do
                {
                    char upgrade[64];
                    KvGetSectionName(g_hPlayerUpgrades[client], upgrade, sizeof(upgrade));

                    if (!matchSlot || !StrEqual(upgrade, upgradeName))
                    {
                        float val = KvGetFloat(g_hPlayerUpgrades[client], NULL_STRING, 0.0);
                        KvJumpToKey(tempUpgrades, currentSlot, true);
                        KvSetFloat(tempUpgrades, upgrade, val);
                        KvGoBack(tempUpgrades);
                    }
                }
                while (KvGotoNextKey(g_hPlayerUpgrades[client], false));

                KvGoBack(g_hPlayerUpgrades[client]);
            }

        } while (KvGotoNextKey(g_hPlayerUpgrades[client], false));
    }

    // Rebuild PURCHASES handle (exact same pattern)
    KvRewind(g_hPlayerPurchases[client]);
    if (KvGotoFirstSubKey(g_hPlayerPurchases[client], false))
    {
        do
        {
            char currentSlot[64];
            KvGetSectionName(g_hPlayerPurchases[client], currentSlot, sizeof(currentSlot));
            bool matchSlot = StrEqual(currentSlot, slotKey);

            if (KvGotoFirstSubKey(g_hPlayerPurchases[client], false))
            {
                do
                {
                    char upgrade[64];
                    KvGetSectionName(g_hPlayerPurchases[client], upgrade, sizeof(upgrade));

                    if (!matchSlot || !StrEqual(upgrade, upgradeName))
                    {
                        int count = KvGetNum(g_hPlayerPurchases[client], NULL_STRING, 0);
                        KvJumpToKey(tempPurchases, currentSlot, true);
                        KvSetNum(tempPurchases, upgrade, count);
                        KvGoBack(tempPurchases);
                    }
                }
                while (KvGotoNextKey(g_hPlayerPurchases[client], false));

                KvGoBack(g_hPlayerPurchases[client]);
            }

        } while (KvGotoNextKey(g_hPlayerPurchases[client], false));
    }

    // Swap handles
    KvRewind(g_hPlayerUpgrades[client]);
    CloseHandle(g_hPlayerUpgrades[client]);
    g_hPlayerUpgrades[client] = tempUpgrades;

    KvRewind(g_hPlayerPurchases[client]);
    CloseHandle(g_hPlayerPurchases[client]);
    g_hPlayerPurchases[client] = tempPurchases;

    PrintToConsole(client, "[Hyper Upgrades] Refunded upgrade: %s. Amount refunded: %d$", upgradeName, refundAmount);
}

void RefundAllUpgradesInSlot(int client, int slot)
{
    if (g_hPlayerUpgrades[client] == null || g_hPlayerPurchases[client] == null)
        return;

    char slotKey[16];
    Format(slotKey, sizeof(slotKey), "slot%d", slot);

    // Step 1: Calculate total refund from this slot
    int totalRefund = 0;

    KvRewind(g_hPlayerPurchases[client]);
    if (KvJumpToKey(g_hPlayerPurchases[client], slotKey, false))
    {
        if (KvGotoFirstSubKey(g_hPlayerPurchases[client], false))
        {
            do
            {
                char upgradeName[64];
                KvGetSectionName(g_hPlayerPurchases[client], upgradeName, sizeof(upgradeName));

                int purchases = KvGetNum(g_hPlayerPurchases[client], NULL_STRING, 0);
                if (purchases > 0)
                {
                    totalRefund += CalculateRefundAmountFromPurchases(upgradeName, purchases);
                    PrintToServer("[HU] Refunding upgrade '%s' (%d purchases) from slot %s", upgradeName, purchases, slotKey);
                }

            } while (KvGotoNextKey(g_hPlayerPurchases[client], false));

            KvGoBack(g_hPlayerPurchases[client]);
        }
        KvGoBack(g_hPlayerPurchases[client]);
    }

    g_iMoneySpent[client] -= totalRefund;
    if (g_iMoneySpent[client] < 0)
        g_iMoneySpent[client] = 0;

    // Step 2: Rebuild new handles WITHOUT this slot
    KeyValues newUpgrades = CreateKeyValues("Upgrades");
    KeyValues newPurchases = CreateKeyValues("Purchases");

    // Copy other upgrade branches
    KvRewind(g_hPlayerUpgrades[client]);
    if (KvGotoFirstSubKey(g_hPlayerUpgrades[client], false))
    {
        do
        {
            char currentSlot[64];
            KvGetSectionName(g_hPlayerUpgrades[client], currentSlot, sizeof(currentSlot));

            if (StrEqual(currentSlot, slotKey))
                continue; // Skip refunding slot

            if (KvGotoFirstSubKey(g_hPlayerUpgrades[client], false))
            {
                do
                {
                    char upgrade[64];
                    KvGetSectionName(g_hPlayerUpgrades[client], upgrade, sizeof(upgrade));
                    float val = KvGetFloat(g_hPlayerUpgrades[client], NULL_STRING, 0.0);

                    KvJumpToKey(newUpgrades, currentSlot, true);
                    KvSetFloat(newUpgrades, upgrade, val);
                    KvGoBack(newUpgrades);

                } while (KvGotoNextKey(g_hPlayerUpgrades[client], false));

                KvGoBack(g_hPlayerUpgrades[client]);
            }

        } while (KvGotoNextKey(g_hPlayerUpgrades[client], false));
    }

    // Copy other purchase branches
    KvRewind(g_hPlayerPurchases[client]);
    if (KvGotoFirstSubKey(g_hPlayerPurchases[client], false))
    {
        do
        {
            char currentSlot[64];
            KvGetSectionName(g_hPlayerPurchases[client], currentSlot, sizeof(currentSlot));

            if (StrEqual(currentSlot, slotKey))
                continue; // Skip refunding slot

            if (KvGotoFirstSubKey(g_hPlayerPurchases[client], false))
            {
                do
                {
                    char upgrade[64];
                    KvGetSectionName(g_hPlayerPurchases[client], upgrade, sizeof(upgrade));
                    int count = KvGetNum(g_hPlayerPurchases[client], NULL_STRING, 0);

                    KvJumpToKey(newPurchases, currentSlot, true);
                    KvSetNum(newPurchases, upgrade, count);
                    KvGoBack(newPurchases);

                } while (KvGotoNextKey(g_hPlayerPurchases[client], false));

                KvGoBack(g_hPlayerPurchases[client]);
            }

        } while (KvGotoNextKey(g_hPlayerPurchases[client], false));
    }

    // Swap in new handles
    CloseHandle(g_hPlayerUpgrades[client]);
    g_hPlayerUpgrades[client] = newUpgrades;

    CloseHandle(g_hPlayerPurchases[client]);
    g_hPlayerPurchases[client] = newPurchases;

    PrintToConsole(client, "[Hyper Upgrades] Refunded all upgrades in %s. Amount refunded: %d$", slotKey, totalRefund);
}

// I like explicit names. Just to be clear, this calculates it for one specific upgrade.
int CalculateRefundAmountFromPurchases(const char[] upgradeName, int purchases)
{
    int idx;
    if (!g_upgradeIndex.GetValue(upgradeName, idx))
        return 0;

    UpgradeData upgrade;
    g_upgrades.GetArray(idx, upgrade);

    int baseCost = upgrade.cost;
    int costIncrease = upgrade.costIncrease;

    // Refund formula: base * n + inc * n*(n-1)/2
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
    int weaponSlot = -1; // Declared once at the top to avoid undefined symbol errors

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
    else if (StrEqual(category, "PDA Upgrades"))
    {
        strcopy(alias, sizeof(alias), "buildings"); // Hardcoded special alias
        aliasFound = true;
        weaponSlot = 3; // Slot 3 or non slotted
    }
    else if (StrEqual(category, "Building Upgrades"))
    {
        strcopy(alias, sizeof(alias), "buildings"); // Hardcoded special alias
        aliasFound = true;
        weaponSlot = -2; // Building specific
    }
    else if (StrEqual(category, "Primary Upgrades"))
    {
        EquippedItem item;
        item = GetEquippedEntityForSlot(client, 0);
        PrintToServer("[Debug] Slot %d: weapon defindex = %d", 0, item.defindex);
        if (IsValidEntity(item.entity))
        {
            strcopy(alias, sizeof(alias), item.alias);
            aliasFound = true;
            weaponSlot = 0;
        }
    }
    else if (StrEqual(category, "Secondary Upgrades"))
    {
        EquippedItem item;
        item = GetEquippedEntityForSlot(client, 1);
        PrintToServer("[Debug] Slot %d: weapon defindex = %d", 1, item.defindex);
        if (IsValidEntity(item.entity))
        {
            strcopy(alias, sizeof(alias), item.alias);
            aliasFound = true;
            weaponSlot = 1;
        }
    }
    else if (StrEqual(category, "Melee Upgrades"))
    {
        EquippedItem item;
        item = GetEquippedEntityForSlot(client, 2);
        PrintToServer("[Debug] Slot %d: weapon defindex = %d", 2, item.defindex);
        if (IsValidEntity(item.entity))
        {
            strcopy(alias, sizeof(alias), item.alias);
            aliasFound = true;
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

EquippedItem GetEquippedEntityForSlot(int client, int slot) // Used to get equipped items not in expected slots (like wearables) | returns entity,index,alias
{
    EquippedItem result;
    result.entity = -1;
    result.defindex = -1;
    strcopy(result.alias, sizeof(result.alias), "");

    // Step 1: Try normal weapon slot
    int weapon = GetPlayerWeaponSlot(client, slot);
    if (IsValidEntity(weapon))
    {
        int defindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
        if (defindex > 0)
        {
            char alias[64];
            if (GetWeaponAlias(defindex, alias, sizeof(alias)))
            {
                result.entity = weapon;
                result.defindex = defindex;
                strcopy(result.alias, sizeof(result.alias), alias);
                return result;
            }
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
        return result;
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
            return result;
        }
    }

    // Collect potential alias misses
    ArrayList missingAliases = new ArrayList(64);
    ArrayList missingDefindexes = new ArrayList();

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
            result.entity = ent;
            result.defindex = defindex;
            strcopy(result.alias, sizeof(result.alias), alias);
            delete kv;
            delete missingAliases;
            delete missingDefindexes;
            return result;
        }

        kv.GoBack(); // alias not found under this slot
        missingAliases.PushString(alias);
        missingDefindexes.Push(defindex);
    }

    delete kv;

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
    return result;
}


public int MenuHandler_Submenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char upgradeGroup[128];
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
                g_bInUpgradeList[i] = false;
                g_MenuClient[i] = 0;
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
        if (ExplodeString(itemData, "|", parts, sizeof(parts), sizeof(parts[])) != 3)
        {
            PrintToChat(client, "[Hyper Upgrades] Failed to parse item string.");
            return 0;
        }

        int weaponSlot = StringToInt(parts[0]);
        char upgradeName[64];
        strcopy(upgradeName, sizeof(upgradeName), parts[1]);
        char upgradeGroup[64];
        strcopy(upgradeGroup, sizeof(upgradeGroup), parts[2]);

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

        float currentLevel = GetPlayerUpgradeValueForSlot(client, weaponSlot, upgradeName);
        int upgradeMultiplier = g_bInUpgradeList[client] ? GetUpgradeMultiplier(client) : 1;

        int scale = (FloatAbs(limit) > 2000.0 || FloatAbs(currentLevel) > 2000.0) ? 1000 : 100000;

        int purchases = GetPlayerUpgradePurchasesForSlot(client, weaponSlot, upgradeName);
        int legalMultiplier = upgradeMultiplier;
        float legalIncrement = increment;

        if (hasLimit)
        {
            int cvarMode = (g_hMoreUpgrades != null) ? g_hMoreUpgrades.IntValue : -1;
            int outMult = 0;
            float outInc = 0.0;

            if (!GetLegalUpgradeIncrementEx(currentLevel, initValue, increment, limit, scale, upgradeMultiplier, cvarMode, outMult, outInc))
            {
                PrintToChat(client, "[Hyper Upgrades] Cannot purchase: would exceed upgrade limit.");
                return 0;
            }

            legalMultiplier = outMult;
            legalIncrement = outInc;
        }

        // Cost calculation
        int b = baseCost;
        int n = legalMultiplier;
        int p = purchases;
        int totalCost = n * b + (costIncrease * n * (2 * p + n - 1)) / 2;

        if (g_iMoneySpent[client] + totalCost > GetConVarInt(g_hMoneyPool))
        {
            int result[2] = {0, 0};
            GetAffordableUpgradeResult(client, upgradeName, purchases, result);

            legalMultiplier = result[0];
            if (legalMultiplier <= 0)
            {
                PrintToChat(client, "[Hyper Upgrades] Not enough money to buy this upgrade.");
                return 0;
            }

            totalCost = result[1];
        }

        float newLevel = currentLevel + (legalIncrement * legalMultiplier);

        char slotPath[16];
        if (weaponSlot == -1)
            strcopy(slotPath, sizeof(slotPath), "body");
        else if (weaponSlot == -2)
            strcopy(slotPath, sizeof(slotPath), "buildings");
        else
            Format(slotPath, sizeof(slotPath), "slot%d", weaponSlot);

        // Write upgrade value
        KvRewind(g_hPlayerUpgrades[client]);
        KvJumpToKey(g_hPlayerUpgrades[client], slotPath, true);
        KvSetFloat(g_hPlayerUpgrades[client], upgradeName, newLevel);
        KvGoBack(g_hPlayerUpgrades[client]);

        // Track purchase count
        KvRewind(g_hPlayerPurchases[client]);
        if (KvJumpToKey(g_hPlayerPurchases[client], slotPath, true))
        {
            int prevCount = KvGetNum(g_hPlayerPurchases[client], upgradeName, 0);
            KvSetNum(g_hPlayerPurchases[client], upgradeName, prevCount + legalMultiplier);
            KvGoBack(g_hPlayerPurchases[client]);
        }
        else
        {
            PrintToServer("[ERROR] Failed to jump to purchases slot: %s", slotPath);
        }

        ApplyPlayerUpgrades(client);
        g_iMoneySpent[client] += totalCost;

        PrintToConsole(client, "[Hyper Upgrades] Purchased upgrade: %s (+%.4f x%d). Total Cost: %d$",
            upgradeAlias, legalIncrement, legalMultiplier, totalCost);

        DataPack dp = new DataPack();
        dp.WriteCell(client);
        dp.WriteString(upgradeGroup);
        CreateTimer(0.0, Timer_DeferMenuReopen, dp);
    }
    else if (action == MenuAction_Cancel)
    {
        g_bInUpgradeList[client] = false;
        if (item == MenuCancel_ExitBack)
            ShowCategoryMenu(client, g_sPlayerCategory[client]);
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

// Returns an array: result[0] = purchases, result[1] = totalCost
void GetAffordableUpgradeResult(int client, const char[] upgradeName, int currentPurchases, int result[2])
{
    result[0] = 0;
    result[1] = 0;

    int idx;
    if (!g_upgradeIndex.GetValue(upgradeName, idx))
        return;

    UpgradeData upgrade;
    g_upgrades.GetArray(idx, upgrade);

    int baseCost = upgrade.cost;
    int costIncrease = upgrade.costIncrease;
    int moneyLeft = GetConVarInt(g_hMoneyPool) - g_iMoneySpent[client];

    int cost = 0;
    for (int i = 1; i <= 1000; i++)
    {
        int thisCost = baseCost + costIncrease * (currentPurchases + i - 1);
        if (cost + thisCost > moneyLeft)
        {
            result[0] = i - 1;
            result[1] = cost;
            return;
        }

        cost += thisCost;
    }

    result[0] = 1000;
    result[1] = cost;
}

// Limit Handler :
/**
 * Determines the maximum legal upgrade multiplier and increment value that can be applied,
 * based on the player's current level, the upgrade configuration, and the hu_moreupgrades mode.
 *
 * @param currentValue     Player's current level (unscaled)
 * @param initValue        Initial value of the upgrade
 * @param increment        Normal increment per purchase (can be negative)
 * @param limit            Upgrade limit (same sign as increment)
 * @param scale            Integer scaling factor (e.g. 100000)
 * @param requestedMult    Multiplier the player wants to apply (e.g. 1000)
 * @param cvarMode         hu_moreupgrades mode (0, 1, or fallback)
 * @param outMult          OUTPUT: number of upgrades allowed
 * @param outIncrement     OUTPUT: increment to apply
 *
 * @return true if at least 1 upgrade is allowed, false otherwise.
 */
bool GetLegalUpgradeIncrementEx(float currentValue, float initValue, float increment, float limit, int scale, int requestedMult, int cvarMode, int &outMult, float &outIncrement)
{
    int IntInit = RoundToNearest(initValue * scale);
    int IntCurrent = RoundToNearest(currentValue * scale);
    int IntIncrement = RoundToNearest(increment * scale);
    int IntLimit = RoundToNearest(limit * scale);
    int IntApplied = IntInit + IntCurrent;

    if (IntIncrement == 0 || requestedMult <= 0)
    {
        outMult = 0;
        outIncrement = 0.0;
        return false;
    }

    int direction = IntIncrement > 0 ? 1 : -1;
    int maxSteps;

    if (direction > 0)
    {
        maxSteps = (IntLimit - IntApplied) / IntIncrement;
    }
    else
    {
        maxSteps = (IntApplied - IntLimit) / -IntIncrement;
    }

    if (maxSteps >= requestedMult)
    {
        outMult = requestedMult;
        outIncrement = increment;
        return true;
    }

    if (maxSteps > 0)
    {
        // Partially allowed before hitting the limit
        outMult = maxSteps;
        outIncrement = increment;
        return true;
    }

    // Can't apply even one full step — now check cvar behavior
    if (cvarMode == 0)
    {
        if ((direction > 0 && IntApplied < IntLimit) || (direction < 0 && IntApplied > IntLimit))
        {
            outMult = 1;
            outIncrement = float(IntLimit - IntApplied) / float(scale);
            return true;
        }
    }
    else if (cvarMode == 1)
    {
        for (int i = 2; i <= 10; i++)
        {
            int step = IntIncrement / i;
            int testApplied = IntApplied + step;

            if ((direction > 0 && testApplied <= IntLimit) ||
                (direction < 0 && testApplied >= IntLimit))
            {
                outMult = 1;
                outIncrement = float(step) / float(scale);
                return true;
            }
        }

        // fallback to mode 0 behavior
        if ((direction > 0 && IntApplied < IntLimit) || (direction < 0 && IntApplied > IntLimit))
        {
            outMult = 1;
            outIncrement = float(IntLimit - IntApplied) / float(scale);
            return true;
        }
    }

    // Nothing allowed
    outMult = 0;
    outIncrement = 0.0;
    return false;
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

    bool foundPath = kv.JumpToKey(g_sPlayerCategory[client], false)
                  && kv.JumpToKey(g_sPlayerAlias[client], false)
                  && kv.JumpToKey(upgradeGroup, false);

    if (!foundPath)
    {
        PrintToServer("[Debug] ShowUpgradeListMenu for client %d", client);
        PrintToServer("[Debug] g_sPlayerCategory = '%s'", g_sPlayerCategory[client]);
        PrintToServer("[Debug] g_sPlayerAlias = '%s'", g_sPlayerAlias[client]);
        PrintToServer("[Debug] upgradeGroup = '%s'", upgradeGroup);
        PrintToChat(client, "[Hyper Upgrades] No upgrades found for this item.");
        delete kv;
        g_bInUpgradeList[client] = false;
        return;
    }

    int multiplier = g_bInUpgradeList[client] ? GetUpgradeMultiplier(client) : 1; 
    g_iPlayerLastMultiplier[client] = multiplier;

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
            PrintToServer("[Hyper Upgrades] Skipping upgrade: \"%s\" (alias: \"%s\") in group \"%s\"", upgradeName, upgradeAlias, upgradeGroup);
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

        float currentLevel = GetPlayerUpgradeValueForSlot(client, g_iPlayerBrowsingSlot[client], upgradeName);
        int scale = (FloatAbs(limit) > 2000.0 || FloatAbs(currentLevel) > 2000.0) ? 1000 : 100000;

        int purchases = GetPlayerUpgradePurchasesForSlot(client, g_iPlayerBrowsingSlot[client], upgradeName);

        int legalMultiplier = multiplier;

        if (hasLimit)
        {
            int cvarMode = g_hMoreUpgrades != null ? g_hMoreUpgrades.IntValue : -1;
            int outMult = 0;
            float outInc = 0.0;

            if (!GetLegalUpgradeIncrementEx(currentLevel, initValue, increment, limit, scale, multiplier, cvarMode, outMult, outInc))
            {
                legalMultiplier = 0;
            }
            else
            {
                legalMultiplier = outMult;
            }
        }

        int baseCost = upgrade.cost;
        int costIncrease = upgrade.costIncrease;
        int n = legalMultiplier;
        int p = purchases;
        int totalCost = n * baseCost + (costIncrease * n * (2 * p + n - 1)) / 2;

        if (g_iMoneySpent[client] + totalCost > GetConVarInt(g_hMoneyPool))
        {
            int result[2] = {0, 0};
            GetAffordableUpgradeResult(client, upgradeName, purchases, result);

            legalMultiplier = result[0] > 0 ? result[0] : 1;
            totalCost = result[1] > 0 ? result[1] : baseCost + costIncrease * purchases;
        }

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


float GetPlayerUpgradeValueForSlot(int client, int slot, const char[] upgradeName)
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
    // PrintToServer("[DEBUG] float GetPlayerUpgradeValueForSlot(): Looking in [%s] for \"%s\"", slotPath, upgradeName);

    float storedLevel = KvGetFloat(g_hPlayerUpgrades[client], upgradeName, 0.0);

    KvRewind(g_hPlayerUpgrades[client]);

    return storedLevel;
}

int GetPlayerUpgradePurchasesForSlot(int client, int slot, const char[] upgradeName)
{
    if (g_hPlayerPurchases[client] == null)
        return 0;

    char slotPath[16];
    if (slot == -1)        strcopy(slotPath, sizeof(slotPath), "body");
    else if (slot == -2)   strcopy(slotPath, sizeof(slotPath), "buildings");
    else                   Format(slotPath, sizeof(slotPath), "slot%d", slot);

    KvRewind(g_hPlayerPurchases[client]);
    if (!KvJumpToKey(g_hPlayerPurchases[client], slotPath, false))
        return 0;

    return KvGetNum(g_hPlayerPurchases[client], upgradeName, 0);
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


public Action Command_DebugUpgradeHandle(int client, int args)
{
    bool useSnapshot = false;

    if (args >= 1)
    {
        char arg[8];
        GetCmdArg(1, arg, sizeof(arg));
        useSnapshot = (StringToInt(arg) == 1);
    }

    PrintToServer("[Hyper Upgrades] Dumping %s upgrade handle contents...", useSnapshot ? "snapshot" : "live");

    bool anyUpgradesFound = false;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;

        Handle hKv = useSnapshot ? g_hPlayerUpgradesSnapshot[i] : g_hPlayerUpgrades[i];
        if (hKv == null)
            continue;

        KvRewind(hKv);
        if (!KvGotoFirstSubKey(hKv, false))
            continue;

        bool hasUpgrades = false;

        // Pre-scan for any non-zero upgrades
        do
        {
            if (KvGotoFirstSubKey(hKv, false))
            {
                do
                {
                    float level = KvGetFloat(hKv, NULL_STRING, 0.0);
                    if (level != 0.0)
                    {
                        hasUpgrades = true;
                        break;
                    }
                }
                while (KvGotoNextKey(hKv, false));

                KvGoBack(hKv);
            }

            if (hasUpgrades)
                break;
        }
        while (KvGotoNextKey(hKv, false));

        KvRewind(hKv);

        if (!hasUpgrades)
            continue;

        anyUpgradesFound = true;
        PrintToServer("---- Client %N (%d) ----", i, i);

        KvGotoFirstSubKey(hKv, false);
        do
        {
            char slotName[64];
            KvGetSectionName(hKv, slotName, sizeof(slotName));
            PrintToServer("  [%s]", slotName);

            if (KvGotoFirstSubKey(hKv, false))
            {
                do
                {
                    char upgradeName[64];
                    float level = KvGetFloat(hKv, NULL_STRING, 0.0);
                    if (level != 0.0)
                    {
                        KvGetSectionName(hKv, upgradeName, sizeof(upgradeName));
                        PrintToServer("    %s: %.2f", upgradeName, level);
                    }
                }
                while (KvGotoNextKey(hKv, false));

                KvGoBack(hKv);
            }

        }
        while (KvGotoNextKey(hKv, false));

        KvRewind(hKv);
    }

    if (!anyUpgradesFound)
    {
        PrintToServer("[Hyper Upgrades] No players currently have any upgrades.");
    }

    PrintToServer("[Hyper Upgrades] End of dump.");
    return Plugin_Handled;
}

public Action Command_DebugPurchaseHandle(int client, int args)
{
    bool useSnapshot = false;

    if (args >= 1)
    {
        char arg[8];
        GetCmdArg(1, arg, sizeof(arg));
        useSnapshot = (StringToInt(arg) == 1);
    }

    PrintToServer("[Hyper Upgrades] Dumping %s purchase handle contents...", useSnapshot ? "snapshot" : "live");

    bool anyPurchasesFound = false;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;

        Handle hKv = useSnapshot ? g_hPlayerPurchasesSnapshot[i] : g_hPlayerPurchases[i];
        if (hKv == null)
            continue;

        KvRewind(hKv);
        if (!KvGotoFirstSubKey(hKv, false))
            continue;

        bool hasPurchases = false;

        // Pre-scan
        do
        {
            if (KvGotoFirstSubKey(hKv, false))
            {
                do
                {
                    int count = KvGetNum(hKv, NULL_STRING, 0);
                    if (count > 0)
                    {
                        hasPurchases = true;
                        break;
                    }
                }
                while (KvGotoNextKey(hKv, false));

                KvGoBack(hKv);
            }

            if (hasPurchases)
                break;
        }
        while (KvGotoNextKey(hKv, false));

        KvRewind(hKv);

        if (!hasPurchases)
            continue;

        anyPurchasesFound = true;
        PrintToServer("---- Client %N (%d) ----", i, i);

        KvGotoFirstSubKey(hKv, false);
        do
        {
            char slotName[64];
            KvGetSectionName(hKv, slotName, sizeof(slotName));
            PrintToServer("  [%s]", slotName);

            if (KvGotoFirstSubKey(hKv, false))
            {
                do
                {
                    int count = KvGetNum(hKv, NULL_STRING, 0);
                    if (count > 0)
                    {
                        char upgradeName[64];
                        KvGetSectionName(hKv, upgradeName, sizeof(upgradeName));
                        PrintToServer("    %s: %d", upgradeName, count);
                    }
                }
                while (KvGotoNextKey(hKv, false));

                KvGoBack(hKv);
            }

        }
        while (KvGotoNextKey(hKv, false));

        KvRewind(hKv);
    }

    if (!anyPurchasesFound)
    {
        PrintToServer("[Hyper Upgrades] No players currently have any purchases.");
    }

    PrintToServer("[Hyper Upgrades] End of dump.");
    return Plugin_Handled;
}


void HU_SetCustomAttribute(int entity, const char[] name, float value) // Call for Custom Upgrades Application
{
    if (!g_bHasCustomAttributes)
        return;

    char strValue[64];
    Format(strValue, sizeof(strValue), "%.3f", value);
    TF2CustAttr_SetString(entity, name, strValue);
}

void HU_ApplyAttributeFromAlias(int entity, const char[] alias, float value) // Apply attribute depending of if vanilla or custom
{
    static const char CUSTOM_PREFIX[] = "CUSTOM_";
    bool isCustom = StrContains(alias, CUSTOM_PREFIX) == 0;

    // Use alias as-is (do NOT strip the prefix)
    AttributeMapping mapping;
    bool found = false;

    for (int i = 0; i < g_attributeMappings.Length; i++)
    {
        g_attributeMappings.GetArray(i, mapping);
        if (StrEqual(mapping.alias, alias))
        {
            found = true;
            break;
        }
    }

    if (!found)
    {
        PrintToServer("[HU] Unknown attribute alias: %s", alias);
        return;
    }

    if (isCustom)
    {
        HU_SetCustomAttribute(entity, mapping.attributeName, value);
    }
    else
    {
        TF2Attrib_SetByName(entity, mapping.attributeName, value);
    }
}


void ApplyPlayerUpgrades(int client)
{
    if (g_hPlayerUpgrades[client] == null)
        return;

    // Clear all existing attributes from the player and their weapons
    TF2Attrib_RemoveAll(client);
    for (int slot = 0; slot <= 5; slot++)
    {
        EquippedItem item;
        item = GetEquippedEntityForSlot(client, slot);
        if (IsValidEntity(item.entity))
        {
            TF2Attrib_RemoveAll(item.entity);
        }
    }

    KvRewind(g_hPlayerUpgrades[client]);

    if (!KvGotoFirstSubKey(g_hPlayerUpgrades[client], false))
        return;

    do
    {
        char slotName[8];
        KvGetSectionName(g_hPlayerUpgrades[client], slotName, sizeof(slotName));

        int entity = -1;
        bool isBody = StrEqual(slotName, "body");

        if (isBody)
        {
            entity = client;
        }
        else
        {
            int slot = StringToInt(slotName[4]);
            EquippedItem item;
            item = GetEquippedEntityForSlot(client, slot);
            entity = item.entity;

            if (!IsValidEntity(entity))
                continue;
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

            float value = KvGetFloat(g_hPlayerUpgrades[client], NULL_STRING, 0.0);

            // Resolve alias from upgrade name
            char upgradeAlias[64];
            if (!GetUpgradeAliasFromName(upgradeName, upgradeAlias, sizeof(upgradeAlias)))
            {
                PrintToConsole(client, "[Warning] Alias not found for upgrade name: %s", upgradeName);
                continue;
            }

            float initValue = 0.0;
            int idx;
            if (g_upgradeIndex.GetValue(upgradeName, idx))
            {
                UpgradeData upgrade;
                g_upgrades.GetArray(idx, upgrade);
                initValue = upgrade.initValue;
            }

            float finalValue = initValue + value;

            HU_ApplyAttributeFromAlias(entity, upgradeAlias, finalValue);

        } while (KvGotoNextKey(g_hPlayerUpgrades[client], false));

        KvGoBack(g_hPlayerUpgrades[client]);

    } while (KvGotoNextKey(g_hPlayerUpgrades[client], false));

    KvRewind(g_hPlayerUpgrades[client]);

    if (g_iResistanceHudMode[client] != 0)
    {
        RefreshClientResistances(client);
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


public void Event_ObjectiveComplete(Event event, const char[] name, bool dontBroadcast)
{
    if (g_bMvMActive)
        return;
    if (StrEqual(name, "teamplay_flag_event"))
    {
        int eventType = event.GetInt("eventtype");

        if (eventType != TF_FLAGEVENT_CAPTURED) // defined in tf2_stocks
            return;
    }

    int money = g_hMoneyPerObjective;
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
    if (!IsValidEntity(entity))
        return;
    
    int builder = GetEntPropEnt(entity, Prop_Send, "m_hBuilder");

    if (!IsValidEntity(builder))
        return;
    
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
        float value = KvGetFloat(g_hPlayerUpgrades[client], NULL_STRING, 0.0);

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

        float fvalue = initValue + value;

        TF2Attrib_SetByName(entity, attrName, fvalue);

        PrintToConsole(client, "[Hyper Upgrades] Applied to building: %s = %.3f (%s)", attrName, fvalue, alias);

    } while (KvGotoNextKey(g_hPlayerUpgrades[client], false));

    KvRewind(g_hPlayerUpgrades[client]);
}

// Damage Types Handling
void FormatDamageFlags(int damagetype, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    for (int i = 0; i < view_as<int>(DFLAG_COUNT); i++)
    {
        if ((damagetype & g_DmgFlagBits[i]) != 0)
        {
            if (buffer[0] != '\0')
            {
                strcopy(buffer[strlen(buffer)], maxlen - strlen(buffer), ", ");
            }
            strcopy(buffer[strlen(buffer)], maxlen - strlen(buffer), g_DmgFlagNames[i]);
        }
    }

    if (buffer[0] == '\0')
    {
        strcopy(buffer, maxlen, "None");
    }
}

void FormatSimplifiedDamageFlags(int damagetype, char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    bool hasAny = false;
    bool written[7]; // 0=Bullet, 1=Blast, 2=Fire, 3=Crit, 4=Melee, 5=Other, 6=Weird

    char label[16];

    for (int i = 0; i < view_as<int>(DFLAG_COUNT); i++)
    {
        if ((damagetype & g_DmgFlagBits[i]) == 0)
            continue;

        int index = -1;
        label[0] = '\0';

        switch (i)
        {
            case DFLAG_BULLET:
                if (!written[0]) { strcopy(label, sizeof(label), "Bullet"); written[0] = true; index = 0; }

            case DFLAG_BLAST:
                if (!written[1]) { strcopy(label, sizeof(label), "Blast"); written[1] = true; index = 1; }

            case DFLAG_RADIATION:
                if (!written[6]) { strcopy(label, sizeof(label), "WEIRD"); written[6] = true; index = 0; }

            case DFLAG_BURN:
                if (!written[2]) { strcopy(label, sizeof(label), "Fire"); written[2] = true; index = 2; }

            case DFLAG_PLASMA:
                if (!written[6]) { strcopy(label, sizeof(label), "WEIRD"); written[6] = true; index = 0; }

            case DFLAG_CRIT:
                if (!written[3]) { strcopy(label, sizeof(label), "Crit"); written[3] = true; index = 3; }

            case DFLAG_ACID:
                if (!written[6]) { strcopy(label, sizeof(label), "WEIRD"); written[6] = true; index = 0; }

            case DFLAG_CLUB:
                if (!written[4]) { strcopy(label, sizeof(label), "Melee"); written[4] = true; index = 4; }

            case DFLAG_NEVERGIB:
                if (!written[6]) { strcopy(label, sizeof(label), "WEIRD"); written[6] = true; index = 0; }

            case DFLAG_SLOWBURN:
                if (!written[6]) { strcopy(label, sizeof(label), "WEIRD"); written[6] = true; index = 0; }

            case DFLAG_POISON:
                if (!written[6]) { strcopy(label, sizeof(label), "WEIRD"); written[6] = true; index = 0; }
            

            default:
                if (!written[5]) { strcopy(label, sizeof(label), "Other"); written[5] = true; index = 5; }
        }

        if (index == -1 || index == -2)
            continue;

        if (hasAny)
            strcopy(buffer[strlen(buffer)], maxlen - strlen(buffer), ", ");
        strcopy(buffer[strlen(buffer)], maxlen - strlen(buffer), label);
        hasAny = true;
    }

    if (!hasAny && !written[5])
    {
        strcopy(buffer, maxlen, "Other");
        written[5] = true;
    }
}

// MvM Functions

void CheckMvMMapMode()
{
    char map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));

    int mode = g_hMvmMode.IntValue;

    switch (mode)
    {
        case 0: // auto
        {
            g_bMvMActive = (StrContains(map, "mvm_", false) == 0);
        }
        case 1: // force classic
        {
            g_bMvMActive = false;
        }
        case 2: // force MvM
        {
            g_bMvMActive = true;
        }
    }

    if (g_bMvMActive)
    {
        CreateTimer(1.0, MvMStartup, _, TIMER_FLAG_NO_MAPCHANGE);
    }

    PrintToServer("[HU] hu_mvm_mode = %d → MvM mode active: %s", mode, g_bMvMActive ? "Yes" : "No");
}

public Action MvMStartup(Handle timer)
{
    DisableMvMUpgradeStations();
    CreateTimer(0.5, Timer_TryInitMissionName, _, TIMER_FLAG_NO_MAPCHANGE);
    if (g_hCurrencySyncTimer != null && IsValidHandle(g_hCurrencySyncTimer))
    {
        KillTimer(g_hCurrencySyncTimer);
        g_hCurrencySyncTimer = null;
    }
    g_hCurrencySyncTimer = CreateTimer(0.5, Timer_CurrencySync, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    PrintToServer("Money Sync Initialised");
    return Plugin_Stop;
}

public Action Timer_TryInitMissionName(Handle timer)
{
    int ent = FindEntityByClassname(-1, "tf_objective_resource");

    if (ent != -1)
    {

        char popfile[PLATFORM_MAX_PATH];
        if (GetEntPropString(ent, Prop_Send, "m_iszMvMPopfileName", popfile, sizeof(popfile)))
        {
            char filename[64];
            ExtractFileName(popfile, filename, sizeof(filename));

            char missionName[64];
            strcopy(missionName, sizeof(missionName), filename);
            int dot = FindCharInString(missionName, '.');
            if (dot != -1)
                missionName[dot] = '\0';

            strcopy(g_sCurrentMission, sizeof(g_sCurrentMission), missionName);
            PrintToServer("[HU] Mission detected on map start: \"%s\"", g_sCurrentMission);

            return Plugin_Stop;
        }
    }

    PrintToServer("[HU] Waiting for tf_objective_resource to appear...");

    // Retry in 0.5s
    CreateTimer(0.5, Timer_TryInitMissionName, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_CurrencySync(Handle timer)
{
    if (!g_bMvMActive)
    {
        g_hCurrencySyncTimer = null;
        return Plugin_Stop;
    }

    int totalMvMCurrency = 0;
    int playerCount = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) <= 1)
            continue;

        int currency = GetEntProp(i, Prop_Send, "m_nCurrency");
        if (currency < 0)
            continue;

        totalMvMCurrency += currency;
        playerCount++;
    }

    if (playerCount == 0)
        return Plugin_Continue;

    int avgCurrency = RoundToNearest(float(totalMvMCurrency) / float(playerCount));

    SetConVarInt(g_hMoneyPool, avgCurrency);
    //PrintToServer("Average MvM Currency : %d ; Money Pool : %d", avgCurrency, GetConVarInt(g_hMoneyPool));

    return Plugin_Continue;
}

public void Event_MvmWaveBegin(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bMvMActive)
        return;

    g_iMoneyPoolSnapshot = GetConVarInt(g_hMoneyPool);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;

        g_iMoneySpentSnapshot[i] = g_iMoneySpent[i];

        if (g_hPlayerUpgradesSnapshot[i] != null)
            CloseHandle(g_hPlayerUpgradesSnapshot[i]);
        if (g_hPlayerPurchasesSnapshot[i] != null)
            CloseHandle(g_hPlayerPurchasesSnapshot[i]);

        g_hPlayerUpgradesSnapshot[i] = CloneKeyValues(view_as<KeyValues>(g_hPlayerUpgrades[i]), "upgrades");
        g_hPlayerPurchasesSnapshot[i] = CloneKeyValues(view_as<KeyValues>(g_hPlayerPurchases[i]), "purchases");
    }

    PrintToServer("[HU] Wave state snapshot saved.");
}

public void Event_MvmWaveFailed(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bMvMActive)
        return;

    // Check mission popfile
    int ent = FindEntityByClassname(-1, "tf_objective_resource");
    if (ent != -1)
    {
        char popfile[PLATFORM_MAX_PATH];
        if (GetEntPropString(ent, Prop_Send, "m_iszMvMPopfileName", popfile, sizeof(popfile)))
        {
            char filename[64];
            ExtractFileName(popfile, filename, sizeof(filename));

            char missionName[64];
            strcopy(missionName, sizeof(missionName), filename);
            int dot = FindCharInString(missionName, '.');
            if (dot != -1)
                missionName[dot] = '\0';

            if (!StrEqual(g_sCurrentMission, missionName, false))
            {
                PrintToServer("[HU] Mission changed on wave fail: \"%s\" → \"%s\". Skipping snapshot restore.", g_sCurrentMission, missionName);
                strcopy(g_sCurrentMission, sizeof(g_sCurrentMission), missionName);

                RefundAllPlayersUpgrades();
                return;
            }
        }
    }

    // No mission change → restore snapshot
    SetConVarInt(g_hMoneyPool, g_iMoneyPoolSnapshot);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;

        g_iMoneySpent[i] = g_iMoneySpentSnapshot[i];

        if (g_hPlayerUpgrades[i] != null)
            CloseHandle(g_hPlayerUpgrades[i]);
        if (g_hPlayerPurchases[i] != null)
            CloseHandle(g_hPlayerPurchases[i]);

        g_hPlayerUpgrades[i] = view_as<Handle>(CloneKeyValues(view_as<KeyValues>(g_hPlayerUpgradesSnapshot[i]), "upgrades"));
        g_hPlayerPurchases[i] = view_as<Handle>(CloneKeyValues(view_as<KeyValues>(g_hPlayerPurchasesSnapshot[i]), "purchases"));

        ApplyPlayerUpgrades(i);
    }

    PrintToServer("[HU] Wave failure: restored previous money and upgrade state.");
}

public void OnMissionReset(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bMvMActive)
        return;
    
    RefundAllPlayersUpgrades();
    return;
}

KeyValues CloneKeyValues(KeyValues original, const char[] sectionName)
{
    if (original == null)
        return new KeyValues(sectionName);

    char tempPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, tempPath, sizeof(tempPath), "data/hu_kv_temp_%s.txt", sectionName);

    original.ExportToFile(tempPath);

    KeyValues clone = new KeyValues(sectionName);
    clone.ImportFromFile(tempPath);
    DeleteFile(tempPath);

    return clone;
}

void DisableMvMUpgradeStations(bool verbose = true)
{
    int ent = -1;
    bool found = false;

    while ((ent = FindEntityByClassname(ent, "func_upgradestation")) != -1)
    {
        AcceptEntityInput(ent, "Disable");
        found = true;

        if (verbose)
        {
            char targetname[64];
            GetEntPropString(ent, Prop_Data, "m_iName", targetname, sizeof(targetname));
            PrintToServer("[HU] Disabled func_upgradestation entity: %d (name: %s)", ent, targetname);
        }
    }

    if (!found && verbose)
    {
        PrintToServer("[HU] Warning: No func_upgradestation entity found to disable.");
    }
}

stock void ExtractFileName(const char[] path, char[] output, int maxlen)
{
    int lastSlash = -1;
    for (int i = 0; path[i] != '\0'; i++)
    {
        if (path[i] == '/' || path[i] == '\\')
            lastSlash = i;
    }

    if (lastSlash != -1)
        strcopy(output, maxlen, path[lastSlash + 1]);
    else
        strcopy(output, maxlen, path);
}

public Action Command_AddMvMCash(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "[HU] Usage: mvm_addcash <amount>");
        return Plugin_Handled;
    }

    int amount = GetCmdArgInt(1);
    if (amount <= 0)
    {
        ReplyToCommand(client, "[HU] Amount must be positive.");
        return Plugin_Handled;
    }

    int count = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || GetClientTeam(i) <= 1)
            continue;

        int current = GetEntProp(i, Prop_Send, "m_nCurrency");
        SetEntProp(i, Prop_Send, "m_nCurrency", current + amount);
        count++;
    }

    ReplyToCommand(client, "[HU] Gave %d credits to %d players.", amount, count);
    PrintToServer("[HU] Admin gave %d credits to %d players via mvm_addcash.", amount, count);

    return Plugin_Handled;
}

// DEFAULT CONFIGS
void GenerateConfigFiles()
{
    char filePath[PLATFORM_MAX_PATH];
    
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
