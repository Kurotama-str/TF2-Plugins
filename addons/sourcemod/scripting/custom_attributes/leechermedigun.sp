// Plugin: Leecher Medigun Modifier
// Description: Disables healing on enemies, drains enemies, and heals medic
// Author: Kuro (based on style from hellfire.sp)

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>
#include <tf_custom_attributes>
//HealTarget Mod
#include <stocksoup/tf/client>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/tf/tempents_stocks>
#include <tf2utils>

#include <dhooks_gameconf_shim>

#define ATTR_NAME "leecher"
#define ATTR_HEAL_RATE_PENALTY "heal rate penalty"
#define ATTR_HEAL_RATE_BONUS "heal rate bonus"
#define ATTR_HEALING_MASTERY "healing mastery"

#define DRAIN_DAMAGE 10.0
#define DRAIN_INTERVAL 0.1
#define HEAL_CONVERSION_RATIO 0.1

bool g_bPlayerRandomCrit[MAXPLAYERS + 1];
Handle g_hCritTimer[MAXPLAYERS + 1] = { INVALID_HANDLE, ... };
Handle g_hDrainTimer[MAXPLAYERS+1];

ConVar g_hRandomCritChance;
float g_fRandomCritChance = 0.05; // 5% chance by default

public Plugin myinfo =
{
    name = "Leecher Medigun",
    author = "Kuro",
    description = "Custom medigun with leecher logic",
    version = "1.1"
};

public void OnPluginStart()
{
    
    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
    HookEvent("player_death", OnPlayerDeath);
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
            StartDrainTimer(i);
            StartClientCritTimer(i);
    }
    //HealTarget Mod
    Handle hGameConf = LoadGameConfigFile("tf2.cattr_starterpack");
    if (hGameConf == null) {
        SetFailState("Failed to load gamedata (tf2.cattr_starterpack).");
    }

    if (!ReadDHooksDefinitions("tf2.cattr_starterpack")) {
        SetFailState("Failed to read DHooks definitions (tf2.cattr_starterpack).");
    }
    Handle dtMedigunAllowedToHealTarget = GetDHooksDefinition(hGameConf, "CWeaponMedigun::AllowedToHealTarget()");
    if (!dtMedigunAllowedToHealTarget) {
        SetFailState("Failed to setup detour for CWeaponMedigun::AllowedToHealTarget()");
    }
    DHookEnableDetour(dtMedigunAllowedToHealTarget, false, OnAllowedToHealTargetPre);

    g_hRandomCritChance = CreateConVar("leecher_random_crit_chance", "0.15", "Chance of random crit per roll (0.0 - 1.0)", FCVAR_NOTIFY);
    g_fRandomCritChance = g_hRandomCritChance.FloatValue;
    HookConVarChange(g_hRandomCritChance, OnRandomCritChanceChanged);
}

public void OnClientPutInServer(int client)
{
    StartDrainTimer(client);
    StartClientCritTimer(client);
}

public void OnClientDisconnect(int client)
{
    StopDrainTimer(client);
    StopClientCritTimer(client);
}

public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    StopDrainTimer(client);
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsClientInGame(client) && IsPlayerAlive(client))
    {
        StartDrainTimer(client);
    }
}

public void OnRandomCritChanceChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    g_fRandomCritChance = g_hRandomCritChance.FloatValue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Continue;

    // Detect +attack (button just pressed)
    static int oldButtons[MAXPLAYERS+1];
    int newButtons = buttons;
    int pressed = newButtons & ~oldButtons[client];
    oldButtons[client] = newButtons;

    if ((pressed & IN_ATTACK) == IN_ATTACK)
    {
        int active = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
        if (IsValidEntity(active))
        {
            float attr = TF2CustAttr_GetFloat(active, ATTR_NAME, 0.0);
            if (attr > 0.0)
            {
                TF2Attrib_SetByName(active, ATTR_HEAL_RATE_PENALTY, 0.0);
            }
        }
    }

    return Plugin_Continue;
}

MRESReturn OnAllowedToHealTargetPre(int medigun, Handle hReturn, Handle hParams)
{
    float attr = TF2CustAttr_GetFloat(medigun, "leecher");
    if (attr <= 0.0)
        return MRES_Ignored;

    int target = DHookGetParam(hParams, 1);

    char type[16];
    strcopy(type, sizeof(type), GetTargetType(target));

    if (!StrEqual(type, "player") && !StrEqual(type, "revive") && !StrEqual(type, "other"))
    {
        DHookSetReturn(hReturn, false);
        return MRES_Supercede;
    }

    DHookSetReturn(hReturn, true); // Allow medigun to target player, revive, or other
    return MRES_Supercede;
}

void StartDrainTimer(int client)
{
    if (g_hDrainTimer[client] != INVALID_HANDLE)
        return;

    g_hDrainTimer[client] = CreateTimer(DRAIN_INTERVAL, Timer_DrainThink, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void StopDrainTimer(int client)
{
    if (g_hDrainTimer[client] != INVALID_HANDLE)
    {
        CloseHandle(g_hDrainTimer[client]);
        g_hDrainTimer[client] = INVALID_HANDLE;
    }
}

public Action Timer_DrainThink(Handle timer, any client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Continue;

    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    float attr = TF2CustAttr_GetFloat(weapon, ATTR_NAME, 0.0);
    if (!IsValidEntity(weapon) || attr <= 0.0)
        return Plugin_Continue;

    int target = GetEntPropEnt(weapon, Prop_Send, "m_hHealingTarget");
    if (!IsValidEntity(target))
        return Plugin_Continue;

    char type[16];
    strcopy(type, sizeof(type), GetTargetType(target));

    // Apply heal rate penalty universally while healing
    TF2Attrib_SetByName(weapon, ATTR_HEAL_RATE_PENALTY, 0.0);

    if (StrEqual(type, "player"))
    {
        if (!IsClientInGame(target) || !IsPlayerAlive(target))
            return Plugin_Continue;

        bool isEnemy = GetClientTeam(client) != GetClientTeam(target);

        if (isEnemy)
            ApplyLeecherDrain(client, target);
        else
            ApplyLeecherHeal(client, target, true); // heal with max cap
    }
    else if (StrEqual(type, "revive"))
    {
        int reviveTeam = GetEntProp(target, Prop_Send, "m_iTeamNum");
        int playerTeam = GetClientTeam(client);

        if (reviveTeam == playerTeam)
        {
            ApplyLeecherHeal(client, target, false); // heal without max cap
        }
    }
    else if (StrEqual(type, "other"))
    {
        ApplyLeecherDrain(client, target);
    }

    return Plugin_Continue;
}

void ApplyLeecherDrain(int client, int target)
{
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    float multiplier = TF2CustAttr_GetFloat(weapon, ATTR_NAME, 1.0);

    float scaledDamage = DRAIN_DAMAGE * multiplier;

    int flags = DMG_ENERGYBEAM;
    if (g_bPlayerRandomCrit[client])
    {
        flags |= DMG_CRIT;
    }

    float zeroForce[3] = {0.0, 0.0, 0.0};
    SDKHooks_TakeDamage(target, client, client, scaledDamage, flags, weapon, zeroForce, zeroForce, false);

    float selfHeal = scaledDamage * HEAL_CONVERSION_RATIO;
    int currentHealth = GetEntProp(client, Prop_Data, "m_iHealth");
    int maxHealth = GetEffectiveMaxHealth(client);

    if (currentHealth < maxHealth)
    {
        int newHealth = currentHealth + RoundFloat(selfHeal);
        if (newHealth > maxHealth)
            newHealth = maxHealth;
        SetEntProp(client, Prop_Data, "m_iHealth", newHealth);
    }
}

void ApplyLeecherHeal(int client, int target, bool respectMax)
{
    float rateBonus    = GetLiveAttributeTotal(client, ATTR_HEAL_RATE_BONUS);
    if (rateBonus <= 0.0) rateBonus = 1.0;

    float masteryBonus = GetLiveAttributeTotal(client, ATTR_HEALING_MASTERY);

    float baseHealPerTick = 24.0 * DRAIN_INTERVAL;
    float healMultiplier  = rateBonus * (1.0 + 0.25 * masteryBonus);
    float healing         = baseHealPerTick * healMultiplier;

    int targetHealth = GetEntProp(target, Prop_Data, "m_iHealth");
    int newHealth = targetHealth + RoundFloat(healing);

    if (respectMax)
    {
        int targetMaxHealth = GetEffectiveMaxHealth(target);
        if (newHealth > targetMaxHealth)
            newHealth = targetMaxHealth;
    }

    SetEntProp(target, Prop_Data, "m_iHealth", newHealth);
}

int GetEffectiveMaxHealth(int entity)
{
    if (!IsValidEntity(entity))
        return 0;

    bool isClient = (entity > 0 && entity <= MaxClients && IsClientInGame(entity));

    int baseMax;
    if (isClient)
    {
        TFClassType class = TF2_GetPlayerClass(entity);
        baseMax = TF2_GetClassMaxHealth(class);
    }
    else
    {
        baseMax = GetEntProp(entity, Prop_Data, "m_iMaxHealth");
    }

    float bonus = 0.0;
    if (isClient)
    {
        bonus += GetLiveAttributeTotal(entity, "max health additive bonus");
        bonus -= GetLiveAttributeTotal(entity, "max health additive penalty");
        bonus += GetLiveAttributeTotal(entity, "SET BONUS: max health additive bonus");
    }

    int max = RoundToCeil(baseMax + bonus);
    //PrintToServer("[Leecher] Effective max HP for entity %d: %d", entity, max);
    return max;
}

// Determine entity type/validity
char[] GetTargetType(int ent)
{
    static char result[16];

    if (!IsValidEntity(ent) || !IsValidEdict(ent))
    {
        strcopy(result, sizeof(result), "invalid");
        return result;
    }

    if (ent > 0 && ent <= MaxClients)
    {
        // Must be a valid client and alive
        if (!IsClientInGame(ent) || !IsPlayerAlive(ent))
        {
            strcopy(result, sizeof(result), "invalid");
        }
        else
        {
            strcopy(result, sizeof(result), "player");
        }
    }
    else
    {
        // Must be damageable and have health
        if (GetEntProp(ent, Prop_Data, "m_takedamage", 1) == 0 ||
            !HasEntProp(ent, Prop_Data, "m_iHealth") ||
            GetEntProp(ent, Prop_Data, "m_iHealth") <= 0)
        {
            char classname[64];
            GetEntityClassname(ent, classname, sizeof(classname));
            //PrintToServer("[Leecher Debug] Entity %d has classname: %s", ent, classname);

            if (StrEqual(classname, "entity_revive_marker", false))
            {
                strcopy(result, sizeof(result), "revive");
            }
            else
            {
                strcopy(result, sizeof(result), "invalid");
            }
        }
        else
        {
            char classname[64];
            GetEntityClassname(ent, classname, sizeof(classname));
            //PrintToServer("[Leecher Debug] Entity %d has classname: %s", ent, classname);

            if (StrContains(classname, "obj_", false) == 0)
            {
                strcopy(result, sizeof(result), "building");
            }
            else
            {
                strcopy(result, sizeof(result), "other");
            }
        }
    }

    return result;
}

float GetLiveAttributeTotal(int client, const char[] attrName)
{
    float total = 0.0;

    if (!IsClientInGame(client))
        return 0.0;

    // Check if player has m_AttributeList before using TF2Attrib
    if (HasEntProp(client, Prop_Send, "m_AttributeList"))
    {
        Address addr = TF2Attrib_GetByName(client, attrName);
        if (addr != Address_Null)
            total += TF2Attrib_GetValue(addr);
    }

    // Scan all equipped entities (weapons, wearables, powerups)
    int maxEntities = GetMaxEntities();
    for (int ent = MaxClients + 1; ent < maxEntities; ent++)
    {
        if (!IsValidEntity(ent))
            continue;

        if (!IsEquippedByClient(ent, client))
            continue;

        // Only try if m_AttributeList exists
        if (!HasEntProp(ent, Prop_Send, "m_AttributeList"))
            continue;

        Address addr = TF2Attrib_GetByName(ent, attrName);
        if (addr != Address_Null)
            total += TF2Attrib_GetValue(addr);
    }

    return total;
}

bool IsEquippedByClient(int ent, int client)
{
    if (!IsValidEntity(ent)) return false;
    if (!HasEntProp(ent, Prop_Send, "m_hOwnerEntity")) return false;
    return (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") == client);
}

int TF2_GetClassMaxHealth(TFClassType class)
{
    switch (class)
    {
        case TFClass_Scout:     return 125;
        case TFClass_Sniper:    return 125;
        case TFClass_Soldier:   return 200;
        case TFClass_DemoMan:   return 175;
        case TFClass_Medic:     return 150;
        case TFClass_Heavy:     return 300;
        case TFClass_Pyro:      return 175;
        case TFClass_Spy:       return 125;
        case TFClass_Engineer:  return 125;
    }

    return 100; // fallback default for unknown/invalid class
}

// random crits

void StartClientCritTimer(int client)
{
    if (g_hCritTimer[client] != INVALID_HANDLE)
        return;

    g_hCritTimer[client] = CreateTimer(2.0, Timer_ClientCritReroll, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void StopClientCritTimer(int client)
{
    if (g_hCritTimer[client] != INVALID_HANDLE)
    {
        CloseHandle(g_hCritTimer[client]);
        g_hCritTimer[client] = INVALID_HANDLE;
    }
}

public Action Timer_ClientCritReroll(Handle timer, any client)
{
    if (!IsClientInGame(client))
        return Plugin_Continue;

    g_bPlayerRandomCrit[client] = (GetURandomFloat() < g_fRandomCritChance);

    //PrintToServer("[Leecher] Random crit for client %d: %s", client, g_bPlayerRandomCrit[client] ? "YES" : "NO");
    return Plugin_Continue;
}
