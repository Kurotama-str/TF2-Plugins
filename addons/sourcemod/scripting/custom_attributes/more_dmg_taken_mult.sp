// Plugin: Custom Damage Type Multipliers
// Description: Applies damage scaling based on custom attributes per damage type
// Author: Kuro

#include <sourcemod>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <tf_custom_attributes>

#define PLUGIN_NAME "DamageTypeMultipliers"
#define ATTR_PREFIX "dmg mult"

public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = "Kuro",
    description = "Scales damage taken per damage type via custom attributes",
    version = "1.0"
};

public void OnPluginStart()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
    }

    RegConsoleCmd("sm_listdmgattrs", Cmd_ListDamageAttributes);
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage,
                           int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    if (!IsClientInGame(victim) || !IsPlayerAlive(victim))
        return Plugin_Continue;

    // Each check applies multiplicatively
    float finalMultiplier = 1.0;

    char types[512];
    types[0] = '\0'; // clear

    AppendDamageType(types, sizeof(types), "DMG_GENERIC", damagetype, DMG_GENERIC);
    AppendDamageType(types, sizeof(types), "DMG_CRIT", damagetype, DMG_CRIT);
    AppendDamageType(types, sizeof(types), "DMG_BULLET", damagetype, DMG_BULLET);
    AppendDamageType(types, sizeof(types), "DMG_SLASH", damagetype, DMG_SLASH);
    AppendDamageType(types, sizeof(types), "DMG_BURN", damagetype, DMG_BURN);
    AppendDamageType(types, sizeof(types), "DMG_CLUB", damagetype, DMG_CLUB);
    AppendDamageType(types, sizeof(types), "DMG_SHOCK", damagetype, DMG_SHOCK);
    AppendDamageType(types, sizeof(types), "DMG_SONIC", damagetype, DMG_SONIC);
    AppendDamageType(types, sizeof(types), "DMG_BLAST", damagetype, DMG_BLAST);
    AppendDamageType(types, sizeof(types), "DMG_ACID", damagetype, DMG_ACID);
    AppendDamageType(types, sizeof(types), "DMG_POISON", damagetype, DMG_POISON);
    AppendDamageType(types, sizeof(types), "DMG_RADIATION", damagetype, DMG_RADIATION);
    AppendDamageType(types, sizeof(types), "DMG_DROWN", damagetype, DMG_DROWN);
    AppendDamageType(types, sizeof(types), "DMG_PARALYZE", damagetype, DMG_PARALYZE);
    AppendDamageType(types, sizeof(types), "DMG_NERVEGAS", damagetype, DMG_NERVEGAS);
    AppendDamageType(types, sizeof(types), "DMG_SLOWBURN", damagetype, DMG_SLOWBURN);
    AppendDamageType(types, sizeof(types), "DMG_PLASMA", damagetype, DMG_PLASMA);
    AppendDamageType(types, sizeof(types), "DMG_AIRBOAT", damagetype, DMG_AIRBOAT);
    AppendDamageType(types, sizeof(types), "DMG_DISSOLVE", damagetype, DMG_DISSOLVE);
    AppendDamageType(types, sizeof(types), "DMG_PREVENT_PHYSICS_FORCE", damagetype, DMG_PREVENT_PHYSICS_FORCE);
    AppendDamageType(types, sizeof(types), "DMG_NEVERGIB", damagetype, DMG_NEVERGIB);
    AppendDamageType(types, sizeof(types), "DMG_ALWAYSGIB", damagetype, DMG_ALWAYSGIB);
    AppendDamageType(types, sizeof(types), "DMG_ENERGYBEAM", damagetype, DMG_ENERGYBEAM);

    //PrintToServer("[DEBUG] %N took %.1f damage. Flags matched: %s", victim, damage, types);

    ApplyDamageMultiplier(victim, damagetype, "generic", DMG_GENERIC, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "crit", DMG_CRIT, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "bullet", DMG_BULLET, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "slash", DMG_SLASH, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "burn", DMG_BURN, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "club", DMG_CLUB, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "shock", DMG_SHOCK, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "sonic", DMG_SONIC, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "blast", DMG_BLAST, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "acid", DMG_ACID, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "poison", DMG_POISON, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "radiation", DMG_RADIATION, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "drown", DMG_DROWN, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "paralyze", DMG_PARALYZE, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "nervegas", DMG_NERVEGAS, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "slowburn", DMG_SLOWBURN, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "plasma", DMG_PLASMA, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "airboat", DMG_AIRBOAT, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "dissolve", DMG_DISSOLVE, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "prevent_physics_force", DMG_PREVENT_PHYSICS_FORCE, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "nevergib", DMG_NEVERGIB, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "alwaysgib", DMG_ALWAYSGIB, finalMultiplier);
    ApplyDamageMultiplier(victim, damagetype, "energybeam", DMG_ENERGYBEAM, finalMultiplier);

    damage *= finalMultiplier;
    return Plugin_Changed;
}

void AppendDamageType(char[] buffer, int bufferLen, const char[] flagName, int damagetype, int flag)
{
    if ((damagetype & flag) != 0)
    {
        if (buffer[0] != '\0')
            strcopy(buffer[strlen(buffer)], bufferLen - strlen(buffer), ", ");
        strcopy(buffer[strlen(buffer)], bufferLen - strlen(buffer), flagName);
    }
}


void ApplyDamageMultiplier(int client, int damagetype, const char[] label, int flag, float &multiplier)
{
    if ((damagetype & flag) != 0)
    {
        char attr[64];
        Format(attr, sizeof(attr), "%s dmg mult", label);
        float mod = GetLiveCustomAttributeTotal(client, attr);
        multiplier *= mod;
    }
}

public Action Cmd_ListDamageAttributes(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
        return Plugin_Handled;

    PrintAvailableDamageAttributes(client);
    return Plugin_Handled;
}

public void PrintAvailableDamageAttributes(int client)
{
    char types[][24] = {
        "generic", "crit", "bullet", "slash", "burn", "club", "shock", "sonic", "blast",
        "acid", "poison", "radiation", "drown", "paralyze", "nervegas",
        "slowburn", "plasma", "airboat", "dissolve", "prevent_physics_force",
        "nevergib", "alwaysgib", "energybeam"
    };

    PrintToConsole(client, "Available damage multiplier attributes:");
    for (int i = 0; i < sizeof(types); i++)
    {
        char attr[64];
        Format(attr, sizeof(attr), "%s dmg mult", types[i]);
        PrintToConsole(client, "- %s", attr);
    }
}

float GetLiveCustomAttributeTotal(int client, const char[] attrName)
{
    float total = 1.0;

    if (!IsClientInGame(client))
        return 1.0;

    float value = TF2CustAttr_GetFloat(client, attrName, 1.0);
    if (value != 1.0)
        //PrintToServer("[DEBUG] Source: client %d (body), attr: %s = %.3f", client, attrName, value);
    total *= value;

    for (int ent = MaxClients + 1; ent < GetMaxEntities(); ent++)
    {
        if (!IsEquippedByClient(ent, client))
            continue;

        char classname[64];
        GetEntityClassname(ent, classname, sizeof(classname));
        if (StrContains(classname, "tf_wearable") == -1 &&
            StrContains(classname, "tf_powerup") == -1 &&
            StrContains(classname, "tf_weapon") == -1)
            continue;

        value = TF2CustAttr_GetFloat(ent, attrName, 1.0);
        if (value != 1.0)
            //PrintToServer("[DEBUG] Source: prop ent %d (%s), attr: %s = %.3f", ent, classname, attrName, value);
        total *= value;
    }

    //PrintToServer("[DEBUG] Final total for attr %s: %.3f", attrName, total);
    return total;
}

bool IsEquippedByClient(int ent, int client)
{
    if (!IsValidEntity(ent)) return false;
    if (!HasEntProp(ent, Prop_Send, "m_hOwnerEntity")) return false;
    return (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") == client);
}