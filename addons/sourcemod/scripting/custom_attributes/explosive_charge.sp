// Plugin: Explosive Charge Impact
// Description: Triggers an explosion on shield impact during charge
// Author: Kuro

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>
#include <tf_custom_attributes>
#include <tf2utils>

#include <stocksoup/tf/tempents_stocks>
#include <stocksoup/var_strings>
#include <tf_damageinfo_tools>

#define ATTR_NAME "explosive charge"
#define BASE_RANGE 20.0
#define BASE_DAMAGE 15.0
float g_fDamageMultiplier = 1.0;

bool g_bChargeExplode[MAXPLAYERS + 1]; // tracks if explosion is allowed

public Plugin myinfo =
{
    name = "Explosive Charge",
    author = "Kuro + OpenAI",
    description = "Explodes on shield impact",
    version = "1.01"
};

public void OnPluginStart()
{
    // Hook condition removal to detect end of charge
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
            g_bChargeExplode[i] = false;
    }
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    g_bChargeExplode[client] = false;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if (!TF2_IsPlayerInCondition(client, TFCond_Charging))
        return Plugin_Continue;

    int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (wep != -1)
    {
        int active = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
        int melee = GetPlayerWeaponSlot(client, 2); // Slot 2 = melee

        if (active != -1 && active == melee && (buttons & IN_ATTACK))
        {
            g_bChargeExplode[client] = true;
            g_fDamageMultiplier = 5.0;
        }
    }
    return Plugin_Continue;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage,
                           int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    if (!(attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker)))
        return Plugin_Continue
    
    if (!IsClientInGame(attacker) || !IsPlayerAlive(attacker))
        return Plugin_Continue;

    if (!TF2_IsPlayerInCondition(attacker, TFCond_Charging))
        return Plugin_Continue;

    if (!IsValidEntity(inflictor))
        return Plugin_Continue;

    char classname[64];
    GetEntityClassname(inflictor, classname, sizeof(classname));

    if (StrEqual(classname, "tf_wearable_demoshield"))
    {
        g_bChargeExplode[attacker] = true;
    }

    return Plugin_Continue;
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
    // PrintToServer("[Explosive Charge] Condition removed for client %d: %d", client, condition);

    if (condition != TFCond_Charging)
    {
        // PrintToServer("[Explosive Charge] Condition is not TFCond_Charging. Ignored.");
        return;
    }

    if (!IsClientInGame(client) || !IsPlayerAlive(client))
    {
        // PrintToServer("[Explosive Charge] Client %d not in game or not alive.", client);
        return;
    }

    int shield = GetPlayerShieldEntity(client);
    if (!IsValidEntity(shield))
    {
        // PrintToServer("[Explosive Charge] No valid secondary (shield) for client %d.", client);
        return;
    }

    float attrValue;
    if (!TF2CustAttr_GetFloat(shield, ATTR_NAME, attrValue))
    {
        // PrintToServer("[Explosive Charge] Attribute '%s' not found on shield for client %d.", ATTR_NAME, client);
        return;
    }

    attrValue = TF2CustAttr_GetFloat(shield, ATTR_NAME);
    if (attrValue <= 0.0)
    {
        // PrintToServer("[Explosive Charge] Attribute '%s' value is %.3f (non-positive) on shield for client %d.", ATTR_NAME, attrValue, client);
        return;
    }

    if (!g_bChargeExplode[client])
    {
        // PrintToServer("[Explosive Charge] Charge ended passively or against a non living obstacle. No explosion.");
        return;
    }

    float vecOrigin[3];
    TF2Util_GetPlayerShootPosition(client, vecOrigin);

    float vecAngles[3];
    GetClientEyeAngles(client, vecAngles);

    float vecForward[3];
    GetAngleVectors(vecAngles, vecForward, NULL_VECTOR, NULL_VECTOR);

    // Offset explosion origin 50 units forward
    float forwardOffset = 50.0;
    vecOrigin[0] += vecForward[0] * forwardOffset;
    vecOrigin[1] += vecForward[1] * forwardOffset;
    vecOrigin[2] += vecForward[2] * forwardOffset;

    // PrintToServer("[Explosive Charge] Explosion position offset by %.1f units forward", forwardOffset);
    // PrintToServer("[Explosive Charge] Position = (%.1f, %.1f, %.1f)", vecOrigin[0], vecOrigin[1], vecOrigin[2]);

    TE_SetupTFExplosion(vecOrigin, .weaponid = TF_WEAPON_GRENADELAUNCHER, .entity = shield,
        .particleIndex = FindParticleSystemIndex("ExplosionCore_MidAir"));
    TE_SendToAll();
    // PrintToServer("[Explosive Charge] Explosion effect sent.");

    // Calculate radius
    float radius = BASE_RANGE + 50 * attrValue;

    // Get live attribute totals for damage increase/decrease
    float damageIncreased = GetLiveAttributeTotal(client, "charge impact damage increased");
    float damageDecreased = GetLiveAttributeTotal(client, "charge impact damage decreased");

    // Calculate final damage
    float baseDamage = BASE_DAMAGE;
    float damage = baseDamage * g_fDamageMultiplier * damageIncreased * damageDecreased * attrValue;
    if (damage < 0.0) damage = 0.0;

    // // PrintToServer("[Explosive Charge] Radius = %.1f, Base Damage = %.1f, Final Damage = %.1f", radius, baseDamage, damage);

    // Calculate knockback force: upward = 100% radius, forward = 10% radius
    float knockbackForce[3];
    knockbackForce[0] = vecForward[0] * (BASE_RANGE * 0.10);
    knockbackForce[1] = vecForward[1] * (BASE_RANGE * 0.10);
    knockbackForce[2] = BASE_RANGE * 1.0;

    // Use full CTakeDamageInfo constructor to specify damage force vector
    CTakeDamageInfo info = new CTakeDamageInfo(
        shield,           // inflictor
        client,           // attacker
        damage,           // damage amount
        DMG_BLAST | DMG_RADIATION,        // damage type
        shield,           // weapon entity
        knockbackForce,   // damage force vector (knockback)
        vecOrigin,        // damage position
        vecOrigin        // reported position
         // custom damage type is optional
    );

    CTFRadiusDamageInfo radInfo = new CTFRadiusDamageInfo(info, vecOrigin, radius);
    radInfo.Apply();
    // PrintToServer("[Explosive Charge] Radius damage applied.");

    g_fDamageMultiplier = 1.0;

    delete radInfo;
    delete info;
    g_bChargeExplode[client] = false
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker))
        return;

    // check that attacker is a Demoman with shield
    int shield = GetPlayerShieldEntity(attacker);
    if (!IsValidEntity(shield))
        return;

    // only heal if shield has explosive charge
    float attrValue = TF2CustAttr_GetFloat(shield, ATTR_NAME, 0.0);
    if (attrValue <= 0.0)
        return;

    // Apply heal from wearables
    float healOnKill = GetWearableHealOnKill(attacker);
    if (healOnKill > 0.0)
    {
        int current = GetClientHealth(attacker);
        int maxOverheal = GetExplosiveChargeMaxOverheal(attacker);
        int newHealth = current + RoundToCeil(healOnKill);

        if (newHealth > maxOverheal)
            newHealth = maxOverheal;

        SetEntityHealth(attacker, newHealth);
    }
}

int FindParticleSystemIndex(const char[] name)
{
    int tbl = FindStringTable("ParticleEffectNames");
    if (tbl == INVALID_STRING_TABLE)
        ThrowError("Could not find string table: ParticleEffectNames");

    int idx = FindStringIndex(tbl, name);
    if (idx == INVALID_STRING_INDEX)
        ThrowError("Could not find particle index: %s", name);

    return idx;
}

int GetPlayerShieldEntity(int client)
{
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "tf_wearable_demoshield")) != -1)
    {
        if (GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client)
            return entity;
    }
    return -1;
}

float GetLiveAttributeTotal(int client, const char[] attrName)
{
    float total = 1.0;

    if (!IsClientInGame(client))
        return 1.0;

    // Check if player has m_AttributeList before using TF2Attrib
    if (HasEntProp(client, Prop_Send, "m_AttributeList"))
    {
        Address addr = TF2Attrib_GetByName(client, attrName);
        if (addr != Address_Null)
        {
            float val = TF2Attrib_GetValue(addr);
            total += val;
            PrintToServer("[GetLiveAttributeTotal] Client %d (player) adding %.3f, total=%.3f", client, val, total);
        }
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
        {
            float val = TF2Attrib_GetValue(addr);
            total += val - 1; // using as additive instead of multiplicative to nerf explosion damage
        }
    }

    if (total <= 0.0)
        total = 1.0;

    return total;
}

bool IsEquippedByClient(int ent, int client)
{
    if (!IsValidEntity(ent)) return false;
    if (!HasEntProp(ent, Prop_Send, "m_hOwnerEntity")) return false;
    return (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") == client);
}

// Heal On Kill
float GetWearableHealOnKill(int client)
{
    float total = 0.0;
    int ent = -1;

    while ((ent = FindEntityByClassname(ent, "tf_wearable*")) != -1)
    {
        if (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") != client)
            continue;
        if (!HasEntProp(ent, Prop_Send, "m_AttributeList"))
            continue;

        Address addr = TF2Attrib_GetByName(ent, "heal on kill");
        if (addr != Address_Null)
        {
            float val = TF2Attrib_GetValue(addr);
            if (val > 0.0)
                total += val;
        }
    }

    return total;
}

int GetExplosiveChargeMaxOverheal(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
        return 0;

    int maxHealth = TF2_GetPlayerMaxHealth(client);

    return RoundToCeil(float(maxHealth) * 1.1); // 110%
}

stock int TF2_GetPlayerMaxHealth(int client)
{
    return GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, client);
}