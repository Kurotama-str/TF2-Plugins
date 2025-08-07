// bot_upgrades.sp

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>

#pragma semicolon 1

#define PLUGIN_NAME    "Bot Upgrades"
#define PLUGIN_VERSION "1.3.0"

// ConVars
ConVar gCvarBotLevel;
ConVar gCvarUpgradeHealth;
ConVar gCvarUpgradeDamage;
ConVar gCvarHealthBase;
ConVar gCvarPrimaryBase;
ConVar gCvarSecondaryBase;
ConVar gCvarMeleeBase;

bool g_bMvMActive = false; // mvm handling
ConVar g_hMvmMode;

public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = "Kuro",
    description = "Upgrades bot stats based on level",
    version = PLUGIN_VERSION,
    url = ""
};

public void OnPluginStart()
{
    gCvarBotLevel = CreateConVar("bu_bot_level", "1", "Bot upgrade level (1-10)", _, true, 1.0, true, 10.0);
    gCvarUpgradeHealth = CreateConVar("bu_upgrade_health", "1", "Enable bot health upgrades (0 = off, 1 = on)");
    gCvarUpgradeDamage = CreateConVar("bu_upgrade_damage", "1", "Enable bot weapon damage upgrades (0 = off, 1 = on)");

    gCvarHealthBase = CreateConVar("bu_health_base", "2.0", "Base multiplier for bot health scaling", _, true, 1.0);
    gCvarPrimaryBase = CreateConVar("bu_primary_dmg_base", "2.0", "Base multiplier for primary weapon damage", _, true, 1.0);
    gCvarSecondaryBase = CreateConVar("bu_secondary_dmg_base", "2.0", "Base multiplier for secondary weapon damage", _, true, 1.0);
    gCvarMeleeBase = CreateConVar("bu_melee_dmg_base", "2.0", "Base multiplier for melee weapon damage", _, true, 1.0);

    g_hMvmMode = CreateConVar("hu_mvm_mode", "0", "Hyper Upgrades MvM mode. 0 = auto, 1 = manual disable, 2 = manual enable.", FCVAR_NOTIFY);

    AutoExecConfig(true, "bot_upgrades");

    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("mvm_wave_failed", Event_MvMWaveFailed, EventHookMode_Post);
}

//Map Handling
public void OnMapStart()
{
    CheckMvMMapMode();
}

void CheckMvMMapMode()
{
    char map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));

    int mode = g_hMvmMode.IntValue;

    switch (mode)
    {
        case 0: // auto
            g_bMvMActive = (StrContains(map, "mvm_", false) == 0);
        case 1: // force classic
            g_bMvMActive = false;
        case 2: // force MvM
            g_bMvMActive = true;
    }

    PrintToServer("[BotUpgrades] bot_mvm_mode = %d → MvM mode active: %s", mode, g_bMvMActive ? "Yes" : "No");
}

public void Event_MvMWaveFailed(Event event, const char[] name, bool dontBroadcast)
{
    UpdateBotLevelFromMvMCurrency();
}

void UpdateBotLevelFromMvMCurrency()
{
    if (!g_bMvMActive)
        return;

    int currency = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsFakeClient(i))
            continue;

        if (TF2_GetClientTeam(i) == TFTeam_Red && HasEntProp(i, Prop_Send, "m_nCurrency"))
        {
            currency = GetEntProp(i, Prop_Send, "m_nCurrency");
            break; // use the first valid fakeclient on red team
        }
    }

    if (currency < 1)
        return; // no red bots with valid m_nCurrency

    int newLevel = (1000+currency) / 1000;
    if (newLevel > 10)
        newLevel = 10;
    if (newLevel < 1)
        newLevel = 1;

    if (newLevel != gCvarBotLevel.IntValue)
    {
        PrintToServer("[BotUpgrades] Updated bot level to %d based on red bot currency = %d", newLevel, currency);
        gCvarBotLevel.IntValue = newLevel;
    }
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client && IsClientInGame(client) && IsFakeClient(client))
    {
        // Delay applying upgrades slightly to ensure weapons are equipped
        CreateTimer(0.2, Timer_ApplyUpgrades, client);
        if (g_bMvMActive)
            UpdateBotLevelFromMvMCurrency();
    }
    return Plugin_Continue;
}

void ApplyBotUpgrades(int client)
{
    int level = gCvarBotLevel.IntValue;

    // Upgrade health
    if (gCvarUpgradeHealth.BoolValue)
    {
        float baseHealth = gCvarHealthBase.FloatValue;
        float multiplier = Pow(baseHealth, float(level) - 1);
        int playerClass = GetPlayerClass(client);
        int base = GetClassBaseHealth(playerClass);
        int newHealth = RoundToNearest(float(base) * (multiplier));

        TF2Attrib_SetByName(client, "max health additive bonus", float(newHealth - base));
        SetEntProp(client, Prop_Send, "m_iHealth", newHealth);
    }

    // Upgrade weapon damage
    if (gCvarUpgradeDamage.BoolValue)
    {
        UpgradeWeaponSlot(client, 0, gCvarPrimaryBase.FloatValue, level);   // Primary
        UpgradeWeaponSlot(client, 1, gCvarSecondaryBase.FloatValue, level); // Secondary
        UpgradeWeaponSlot(client, 2, gCvarMeleeBase.FloatValue, level);     // Melee
    }
}

public Action Timer_ApplyUpgrades(Handle timer, any client)
{
    if (!IsClientInGame(client) || !IsFakeClient(client) || TF2_GetClientTeam(client) == TFTeam_Unassigned || TF2_GetClientTeam(client) == TFTeam_Spectator)
        return Plugin_Stop;

    if (g_bMvMActive && TF2_GetClientTeam(client) != TFTeam_Red)
        return Plugin_Stop; // Skip applying upgrades to blue bots in MvM

    ApplyBotUpgrades(client);
    return Plugin_Stop;
}

void UpgradeWeaponSlot(int client, int slot, float base, int level)
{
    int weapon = GetPlayerWeaponSlot(client, slot);
    if (weapon <= 0) return;

    float multiplier = Pow(base, float(level) - 1);
    TF2Attrib_SetByName(weapon, "damage bonus", multiplier);
}

int GetPlayerClass(int client)
{
    // Returns TFClassType enum (e.g., TFClass_Scout = 1)
    return view_as<int>(TF2_GetPlayerClass(client));
}

int GetClassBaseHealth(int tfclass)
{
    switch (tfclass)
    {
        case TFClass_Scout: return 125;
        case TFClass_Soldier: return 200;
        case TFClass_Pyro: return 175;
        case TFClass_DemoMan: return 175;
        case TFClass_Heavy: return 300;
        case TFClass_Engineer: return 125;
        case TFClass_Medic: return 150;
        case TFClass_Sniper: return 125;
        case TFClass_Spy: return 125;
    }
    return 100; // Fallback
}
