// att_rocketeer.sp - Rocketeer Attribute
// Description: Converts hitscan weapons into rocket launchers with adjusted fire rate and projectile speed.
// Author: Kuro + OpenAI

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>
#include <tf_custom_attributes>
#include <tf2utils>

#define ATTR_NAME "rocketeer"

// Stock attributes we apply alongside
#define ATTR_FIRE_RATE "fire rate penalty HIDDEN"
#define ATTR_PROJECTILE_OVERRIDE "override projectile type"
#define ATTR_MAXAMMO "maxammo primary reduced"
#define ATTR_DAMAGE "damage bonus HIDDEN"

// Default fire rate slowdown (4.0x slower)
#define BASE_FIRE_RATE 4.0

// Default projectile type override (2 = rocket)
#define PROJECTILE_ROCKET 2

// Default maxammo multiplier (value = mult * 200)
#define BASE_MAXAMMO 0.25

// Default damage multiplier
#define BASE_DAMAGE 4.0

int g_iPrevButtons[MAXPLAYERS+1];
bool g_bRocketeerFired[MAXPLAYERS+1];

public Plugin myinfo =
{
    name        = "Rocketeer Attribute",
    author      = "Kuro + OpenAI",
    description = "Converts hitscan weapons to fire rockets",
    version     = "1.0"
};

// Tracks if we have tf2custattr available
bool g_bHasCustomAttributes = false;

public void OnPluginStart()
{
    g_bHasCustomAttributes = LibraryExists("tf2custattr");
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "tf2custattr"))
    {
        g_bHasCustomAttributes = true;
    }
}
public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "tf2custattr"))
    {
        g_bHasCustomAttributes = false;
    }
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client)) return;

    ApplyRocketeerAttributes(client);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse,
                             float vel[3], float angles[3], int &weapon)
{
    if (!IsValidClient(client) || !g_bHasCustomAttributes)
        return Plugin_Continue;

    ApplyRocketeerAttributes(client);

    int prev = g_iPrevButtons[client];
    int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

    if (IsValidEntity(wep))
    {
        // Enforce cooldown only if a rocket was recently fired
        if (g_bRocketeerFired[client])
        {
            // Detect release -> spam tap
            if (!(buttons & IN_ATTACK) && (prev & IN_ATTACK))
                ForceRocketeerCooldown(wep);

            // Detect tap-press while revved
            if ((buttons & IN_ATTACK2) && (buttons & IN_ATTACK) && !(prev & IN_ATTACK))
                ForceRocketeerCooldown(wep);
        }
    }

    g_iPrevButtons[client] = buttons;
    return Plugin_Continue;
}

void ForceRocketeerCooldown(int weapon)
{
    float nextAttack = GetGameTime() + 0.420;
    SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", nextAttack);
}

// === Core logic ===
void ApplyRocketeerAttributes(int client)
{
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEntity(weapon))
        return;

    float rocketeerLevel = TF2CustAttr_GetFloat(weapon, ATTR_NAME, 0.0);
    if (rocketeerLevel <= 0.0)
        return;

    // 1. Override projectile type → rocket
    TF2Attrib_SetByName(weapon, ATTR_PROJECTILE_OVERRIDE, float(PROJECTILE_ROCKET));

    // 2. Apply fire rate penalty (stock attr)
    TF2Attrib_SetByName(weapon, ATTR_FIRE_RATE, BASE_FIRE_RATE);

    // 3. Apply projectile speed multiplier (custom attr)
    TF2CustAttr_SetFloat(weapon, "aproj speed", rocketeerLevel);

    // 4. Apply maxammo primary penalty (stock attr)
    TF2Attrib_SetByName(weapon, ATTR_MAXAMMO, BASE_MAXAMMO);

    // 5. Apply centerfire
    TF2Attrib_SetByName(weapon, "centerfire projectile", 1.0);

    // 6. Apply damage bonus
    TF2Attrib_SetByName(weapon, ATTR_DAMAGE, BASE_DAMAGE + rocketeerLevel);
}

// === Utility ===
bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client));
}

public void OnEntityCreated(int ent, const char[] classname)
{
    if (StrEqual(classname, "tf_projectile_rocket", false))
    {
        SDKHook(ent, SDKHook_SpawnPost, OnRocketSpawnPost);
    }
}

public void OnRocketSpawnPost(int rocket)
{
    SDKUnhook(rocket, SDKHook_SpawnPost, OnRocketSpawnPost);

    if (!IsValidEntity(rocket))
        return;

    int owner = GetEntPropEnt(rocket, Prop_Send, "m_hOwnerEntity");
    if (owner <= 0 || owner > MaxClients || !IsClientInGame(owner))
        return;

    int weapon = GetEntPropEnt(owner, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEntity(weapon))
        return;

    // Only adjust if the weapon actually has rocketeer
    float rocketeerLevel = TF2CustAttr_GetFloat(weapon, ATTR_NAME, 0.0);
    if (rocketeerLevel <= 0.0)
        return;

    // Attempt at preventing tap fire abuse
    if (owner > 0 && owner <= MaxClients && IsClientInGame(owner))
    {
        g_bRocketeerFired[owner] = true;

        // Clear the flag after ~0.1s (enough to detect spam but not block tap-fire)
        CreateTimer(0.420, Timer_ClearFired, GetClientUserId(owner));
    }

    // Get rocket’s current origin
    float origin[3];
    GetEntPropVector(rocket, Prop_Data, "m_vecAbsOrigin", origin);

    // Get owner’s view angles to calculate “up” vector
    float angles[3], fwd[3], right[3], up[3];
    GetClientEyeAngles(owner, angles);
    GetAngleVectors(angles, fwd, right, up);

    // Offset downwards (tweak until it looks right)
    const float offsetDown = -25.0;
    origin[0] += up[0] * offsetDown;
    origin[1] += up[1] * offsetDown;
    origin[2] += up[2] * offsetDown;

    // Teleport only origin (don’t touch velocity/angles!)
    TeleportEntity(rocket, origin, NULL_VECTOR, NULL_VECTOR);
}

public Action Timer_ClearFired(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && client <= MaxClients)
    {
        g_bRocketeerFired[client] = false;
    }
    return Plugin_Stop;
}
