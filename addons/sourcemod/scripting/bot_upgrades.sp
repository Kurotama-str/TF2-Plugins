// bot_upgrades.sp

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>

#pragma semicolon 1

#define PLUGIN_NAME    "Bot Upgrades"
#define PLUGIN_VERSION "1.4.0"

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

// Enables or disables Hyper Upgrades integration
ConVar g_hBotHUEnableAuto;         // bot_hu_enable_auto
ConVar g_hBotHUScalingMode;        // bot_hu_scaling_mode
ConVar g_hBotHUScalingValue;       // bot_hu_scaling_value
ConVar gCvarBotLevelMax; // bu_bot_level_max
bool g_bHyperUpgradesLoaded = false;
ConVar g_hHyperUpgradesMoneyPool = null;

// Attempt at supporting GBMW
#include <tf_econ_data>  // for TF2Econ_* slot queries
ConVar g_hGBMWEnabled;   // sm_gbmw_enabled (optional)
ConVar g_hGBMWDelay;     // sm_gbmw_delay

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
    gCvarBotLevel = CreateConVar("bu_bot_level", "1", "Bot upgrade level (Minimum 1 ; configurable Max)");
    gCvarUpgradeHealth = CreateConVar("bu_upgrade_health", "1", "Enable bot health upgrades (0 = off, 1 = on)");
    gCvarUpgradeDamage = CreateConVar("bu_upgrade_damage", "1", "Enable bot weapon damage upgrades (0 = off, 1 = on)");

    gCvarHealthBase = CreateConVar("bu_health_base", "2.0", "Base multiplier for bot health scaling", _, true, 1.0);
    gCvarPrimaryBase = CreateConVar("bu_primary_dmg_base", "2.0", "Base multiplier for primary weapon damage", _, true, 1.0);
    gCvarSecondaryBase = CreateConVar("bu_secondary_dmg_base", "2.0", "Base multiplier for secondary weapon damage", _, true, 1.0);
    gCvarMeleeBase = CreateConVar("bu_melee_dmg_base", "2.0", "Base multiplier for melee weapon damage", _, true, 1.0);

    g_hMvmMode = CreateConVar("hu_mvm_mode", "0", "Hyper Upgrades MvM mode. 0 = auto, 1 = manual disable, 2 = manual enable.", FCVAR_NOTIFY);

    g_hBotHUEnableAuto = CreateConVar("bot_hu_enable_auto", "1", "Enable Hyper Upgrades auto-scaling. 0 = Disabled, 1 = Enabled");
    g_hBotHUScalingValue = CreateConVar("bot_hu_scaling_value", "1000", "Scaling value for determining bot upgrade level from Hyper Upgrades money pool.");
    g_hBotHUScalingMode = CreateConVar("bot_hu_scaling_mode", "1", "Scaling mode: 0 = Linear, 1 = Exponential");
    gCvarBotLevelMax = CreateConVar("bu_bot_level_max", "10", "Maximum bot level (applies to auto-scaling and manual sets).");

    g_hGBMWEnabled = FindConVar("sm_gbmw_enabled"); // may be null if plugin absent
    g_hGBMWDelay   = FindConVar("sm_gbmw_delay");   // default is 0.2 in GBMW

    if (LibraryExists("hyperupgrades"))
    {
        OnLibraryAdded("hyperupgrades"); // Simulate the callback to initialize it right away
    }

    AutoExecConfig(true, "bot_upgrades");

    HookConVarChange(gCvarBotLevel, OnBotLevelChanged);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("mvm_wave_failed", Event_MvMWaveFailed, EventHookMode_Post);

    // Hook any already connected bots
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsFakeClient(i))
        {
            SDKHook(i, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
        }
    }
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

public void OnBotLevelChanged(ConVar cvar, const char[] oldVal, const char[] newVal)
{
    int val  = StringToInt(newVal);
    int maxL = gCvarBotLevelMax.IntValue;
    if (maxL < 1) maxL = 1; // guard against goofy configs

    if (val < 1)       cvar.IntValue = 1;
    else if (val > maxL) cvar.IntValue = maxL;
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

    int maxL = gCvarBotLevelMax.IntValue;
    if (maxL < 1) maxL = 1;

    int newLevel = (1000 + currency) / 1000;
    if (newLevel > maxL) newLevel = maxL;
    if (newLevel < 1)    newLevel = 1;

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
        CreateTimer(0.05, Timer_ApplyUpgrades, client); // keep existing quick pass

        // If GBMW is enabled, schedule a pass AFTER its give delay as well.
        float extra = (g_hGBMWEnabled && g_hGBMWEnabled.BoolValue && g_hGBMWDelay)
                      ? g_hGBMWDelay.FloatValue + 0.05
                      : 0.0;
        if (extra > 0.0)
            CreateTimer(extra, Timer_ApplyWepUpgrades, client);

        if (g_bMvMActive)
            UpdateBotLevelFromMvMCurrency();
    }
    return Plugin_Continue;
}

// ─────────────────────────────────────────────────────────────────────────────
// Applying Upgrades
// ─────────────────────────────────────────────────────────────────────────────
void ApplyBotUpgrades(int client)
{
    int level = gCvarBotLevel.IntValue;

    // Upgrade health
    if (gCvarUpgradeHealth.BoolValue)
    {
        float baseHealth = gCvarHealthBase.FloatValue;
        float basePrimDmg = gCvarPrimaryBase.FloatValue;

        float multiplier = BU_CalcDamageMult(baseHealth, level); // Health
        float multprim   = BU_CalcSentryDamageMult(basePrimDmg, level); // Sentry dmg

        int playerClass = GetPlayerClass(client);
        int base = GetClassBaseHealth(playerClass);
        int newHealth = RoundToNearest(float(base) * multiplier);

        TF2Attrib_SetByName(client, "max health additive bonus", float(newHealth - base));
        if (TF2_GetPlayerClass(client) == TFClass_Engineer)
        {
            TF2Attrib_SetByName(client, "engy building health bonus", multiplier);
            TF2Attrib_SetByName(client, "engy sentry damage bonus", multprim);
            TF2Attrib_SetByName(client, "engy dispenser radius increased", float(1 + (9 * (level - 1)) / (GetConVarInt(gCvarBotLevelMax) - 1)));
        }
        TF2_RegeneratePlayer(client);
    }
    CreateTimer(0.2, Timer_ApplyWepUpgrades, client);
}

public Action Timer_ApplyUpgrades(Handle timer, any client)
{
    if (!IsClientInGame(client) || !IsFakeClient(client)
     || TF2_GetClientTeam(client) == TFTeam_Unassigned
     || TF2_GetClientTeam(client) == TFTeam_Spectator)
        return Plugin_Stop;

    if (g_bMvMActive && TF2_GetClientTeam(client) != TFTeam_Red)
        return Plugin_Stop;

    UpdateBotLevelFromHyperUpgrades();
    ApplyBotUpgrades(client);
    return Plugin_Stop;
}

public Action Timer_ApplyWepUpgrades(Handle timer, any client)
{
    int level = gCvarBotLevel.IntValue;

    if (gCvarUpgradeDamage.BoolValue)
    {
        // Primary
        UpgradeWeaponSlot(client, 0, gCvarPrimaryBase.FloatValue, level);
        // Secondary
        UpgradeWeaponSlot(client, 1, gCvarSecondaryBase.FloatValue, level);
        // Melee
        UpgradeWeaponSlot(client, 2, gCvarMeleeBase.FloatValue, level);
    }
    return Plugin_Stop;
}

void UpgradeWeaponSlot(int client, int slot, float base, int level)
{
    int weapon = GetPlayerWeaponSlot(client, slot);
    if (weapon <= 0) return;

    // Reuse the exact same applier so slot path == equip path
    BU_ApplyDamageToWeapon(client, weapon, base, level);
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

// ─────────────────────────────────────────────────────────────────────────────
// Shared math helpers (single source of truth)
// ─────────────────────────────────────────────────────────────────────────────
static float BU_CalcDamageMult(float base, int level)
{
    return Pow(base, float(level) - 1.0);
}

static float BU_CalcSentryDamageMult(float basePrimary, int level)
{
    // used by Engineer sentry damage
    return 0.75 + 0.25 * Pow(basePrimary, float(level) - 1.0);
}

static float BU_CalcMedicHealRatePenalty(float base, int level, int maxLevel)
{
    // matches your existing medic logic
    float maxmult = Pow(4.0, base);
    return Pow(maxmult, float(level - 1) / float(maxLevel - 1));
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared applier for a specific weapon entity (uses a *given* base)
// Both slot-path and equip-post path end up here.
// ─────────────────────────────────────────────────────────────────────────────
static void BU_ApplyDamageToWeapon(int client, int weapon, float base, int level)
{
    if (!IsValidEntity(weapon)) return;

    float mult = BU_CalcDamageMult(base, level);
    TF2Attrib_SetByName(weapon, "damage bonus", mult);

    if (TF2_GetPlayerClass(client) == TFClass_Medic)
    {
        int maxLevel = GetConVarInt(gCvarBotLevelMax);
        float healPenalty = BU_CalcMedicHealRatePenalty(base, level, maxLevel);
        TF2Attrib_SetByName(weapon, "heal rate penalty", healPenalty);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Entity-path adapter used by WeaponEquipPost (derives base from econ slot)
// ─────────────────────────────────────────────────────────────────────────────
static bool BU_GetBaseForWeaponEntity(int client, int weapon, float &outBase)
{
    int def = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
    if (def <= 0) return false;

    TFClassType cls = TF2_GetPlayerClass(client);
    int econSlot = TF2Econ_GetItemLoadoutSlot(def, cls);
    if (econSlot < 0) return false;

    char slotName[32];
    if (!TF2Econ_TranslateLoadoutSlotIndexToName(econSlot, slotName, sizeof(slotName)))
        return false;

    if (StrEqual(slotName, "primary"))
        outBase = gCvarPrimaryBase.FloatValue;
    else if (StrEqual(slotName, "secondary"))
        outBase = gCvarSecondaryBase.FloatValue;
    else if (StrEqual(slotName, "melee"))
        outBase = gCvarMeleeBase.FloatValue;
    else
        return false; // ignore tools/PDAs/etc.

    return true;
}

static void BU_UpgradeWeaponEntityByEquip(int client, int weapon, int level)
{
    float base;
    if (!BU_GetBaseForWeaponEntity(client, weapon, base))
        return;

    BU_ApplyDamageToWeapon(client, weapon, base, level);
}


// Hyper Upgrades detection
public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "hyperupgrades"))
    {
        g_bHyperUpgradesLoaded = true;
        g_hHyperUpgradesMoneyPool = FindConVar("hu_money_pool");

        if (g_hHyperUpgradesMoneyPool != null)
        {
            PrintToServer("[Bot Upgrades] Hyper Upgrades compatibility enabled.");
        }
    }
}
public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "hyperupgrades"))
    {
        g_bHyperUpgradesLoaded = false;
        g_hHyperUpgradesMoneyPool = null;

        PrintToServer("[Bot Upgrades] Hyper Upgrades compatibility disabled.");
    }
}
// === Hyper Upgrades → Bot Level auto-scaling ===
// Uses: g_bHyperUpgradesLoaded, g_hHyperUpgradesMoneyPool
//       g_hBotHUEnableAuto, g_hBotHUScalingValue, g_hBotHUScalingMode
//       gCvarBotLevel (existing)
void UpdateBotLevelFromHyperUpgrades()
{
    if (g_bMvMActive)
        return;

    if (!g_bHyperUpgradesLoaded || !g_hBotHUEnableAuto.BoolValue)
        return;

    if (g_hHyperUpgradesMoneyPool == null)
        return;

    int money = g_hHyperUpgradesMoneyPool.IntValue;
    int step  = g_hBotHUScalingValue.IntValue;
    if (step <= 0)
        return;

    int mode  = g_hBotHUScalingMode.IntValue; // 0=linear, 1=expo
    int cur   = gCvarBotLevel.IntValue;
    int level = cur;

    int maxL = gCvarBotLevelMax.IntValue;
    if (maxL < 1) maxL = 1;

    if (mode == 0)
    {
        while (level < maxL && money >= (level + 1) * step)
            level++;

        while (level > 1 && money < level * step)
            level--;
    }
    else
    {
        float avgBase = ComputeAverageBotUpgradeBase();
        if (maxL < 1) maxL = 1;

        // Upgrade
        while (level < maxL && float(money) >= float(step) * Pow(avgBase, float(level)))
            level++;

        // Downgrade
        while (level > 1 && float(money) < float(step) * Pow(avgBase, float(level - 1)))
            level--;
    }

    if (level < 1)   level = 1;
    if (level > maxL) level = maxL;

    if (level != cur)
    {
        gCvarBotLevel.IntValue = level;
        PrintToServer("[Bot Upgrades] HU auto-level: %d -> %d (money=%d, step=%d, mode=%s, max=%d)",
            cur, level, money, step, (mode == 0 ? "linear" : "expo"), maxL);
    }
}

float ComputeAverageBotUpgradeBase()
{
    float sum = 0.0;
    int count = 0;

    if (gCvarUpgradeHealth.BoolValue)
    {
        sum += gCvarHealthBase.FloatValue;
        count++;
    }

    if (gCvarUpgradeDamage.BoolValue)
    {
        sum += gCvarPrimaryBase.FloatValue;
        sum += gCvarSecondaryBase.FloatValue;
        sum += gCvarMeleeBase.FloatValue;
        count += 3;
    }

    if (count == 0)
        return 1.0;

    return sum / float(count);
}

// ─────────────────────────────────────────────────────────────────────────────
// Hook: apply upgrades as soon as GBMW equips a weapon
// ─────────────────────────────────────────────────────────────────────────────
public void OnClientPutInServer(int client)
{
    if (IsFakeClient(client))
        SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
}

public void OnClientDisconnect(int client)
{
    if (IsFakeClient(client))
        SDKUnhook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
}

public void OnWeaponEquipPost(int client, int weapon)
{
    if (!IsClientInGame(client) || !IsFakeClient(client))
        return;
    if (g_bMvMActive && TF2_GetClientTeam(client) != TFTeam_Red)
        return;
    if (!gCvarUpgradeDamage.BoolValue)
        return;

    int level = gCvarBotLevel.IntValue;
    BU_UpgradeWeaponEntityByEquip(client, weapon, level);
}
