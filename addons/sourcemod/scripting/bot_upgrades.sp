// bot_upgrades.sp

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>

#pragma semicolon 1

#define PLUGIN_NAME    "Bot Upgrades"
#define PLUGIN_VERSION "1.2.1"

// ConVars
ConVar gCvarBotLevel;
ConVar gCvarUpgradeHealth;
ConVar gCvarUpgradeDamage;
ConVar gCvarHealthBase;
ConVar gCvarPrimaryBase;
ConVar gCvarSecondaryBase;
ConVar gCvarMeleeBase;

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

    AutoExecConfig(true, "bot_upgrades");

    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client && IsClientInGame(client) && IsFakeClient(client))
    {
        // Delay applying upgrades slightly to ensure weapons are equipped
        CreateTimer(0.2, Timer_ApplyUpgrades, client);
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
        int newHealth = RoundToNearest(float(base) * (multiplier - 1));

        TF2Attrib_SetByName(client, "max health additive bonus", float(newHealth));
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
    if (IsClientInGame(client) && IsFakeClient(client))
    {
        ApplyBotUpgrades(client);
    }
    return Plugin_Stop;
}

void UpgradeWeaponSlot(int client, int slot, float base, int level)
{
    int weapon = GetPlayerWeaponSlot(client, slot);
    if (weapon <= 0) return;

    float multiplier = Pow(base, float(level));
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
