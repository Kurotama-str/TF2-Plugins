#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <tf2>
#include <tf2attributes>
#include <tf_custom_attributes>

#define ATTR_NAME "altproj speed"
#define MAX_EDICTS 2048

#define EF_NOSHADOW (1 << 4)

ConVar g_haprojMaxSpeed;
ConVar g_haprojShowWarnings;

bool g_bTimerCalled[MAX_EDICTS];

// The annoying ones. Syringes are another kind of annoying.
static const char g_ProjectileVelocityBlacklist[][] = {
    "tf_projectile_stun_ball",
    "tf_projectile_jar",
    "tf_projectile_jar_milk",
    "tf_projectile_jar_gas",
    "tf_projectile_cleaver",
    "tf_projectile_ball_ornament",
    "tf_projectile_pipe",
    "tf_projectile_pipe_remote"
};

public Plugin myinfo =
{
    name = "Alternative Projectile Speed Multiplier",
    author = "Kuro + OpenAI",
    description = "Applies 'aproj speed' custom attribute to modify initial velocity of some projectiles.",
    version = "1.01"
};

public void OnPluginStart()
{
    g_haprojMaxSpeed = CreateConVar("aproj_max_speed", "3500.0", 
    "Maximum allowed projectile speed (HU/s) before applying angle/velocity. Projectiles above 3000 units may behave unpredictably.", 
    FCVAR_REPLICATED);
    g_haprojShowWarnings = CreateConVar("aproj_show_debug", "1",
    "Whether to show debug/info messages from the Alternative Projectile Speed plugin (1 = enabled, 0 = disabled).",
    FCVAR_REPLICATED);
    HookConVarChange(g_haprojMaxSpeed, OnaprojMaxSpeedChanged);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!IsValidEntity(entity))
        return;

    // Ensure entity classname contains "tf_projectile"
    if (classname[0] == '\0' || StrContains(classname, "tf_projectile") == -1 || IsVelocityBlacklisted(classname))
        return;

    if (HasEntProp(entity, Prop_Send, "m_hOwnerEntity") &&
        HasEntProp(entity, Prop_Data, "m_vecVelocity"))
    {
        SDKHook(entity, SDKHook_SpawnPost, OnProjectileSpawnedDelayed);
        //PrintToServer("[aproj] Hooked entity: %d (%s)", entity, classname);
    }
}

public void OnEntityDestroyed(int entity)
{
    if(IsValidEntity(entity) && entity >= 0)
        g_bTimerCalled[entity] = false;
}

public void OnaprojMaxSpeedChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    float value = convar.FloatValue;

    if (value > 3500.0 && g_haprojShowWarnings.BoolValue)
    {
        PrintToServer("[aproj] WARNING: aproj_max_speed is set above 3000. Projectiles may visually deviate at high velocity.");
    }
}

// Attempt at handling annoying projectiles

public void OnProjectileSpawnedDelayed(int entity)
{
    CreateTimer(0.0, Timer_ApplyVelocityMultiplier, entity);
    //PrintToServer("[aproj] Timer fired for entity: %d", entity);
}

public Action Timer_ApplyVelocityMultiplier(Handle timer, int entity)
{
    if (!IsValidEntity(entity) && entity > -1)
        return Plugin_Stop;
    
    if (g_bTimerCalled[entity])
        return Plugin_Stop;

    g_bTimerCalled[entity] = true;

    float velocity[3];
    GetEntPropVector(entity, Prop_Data, "m_vecVelocity", velocity);

    float mult = GetProjectileCustomAttrMultiplier(entity, "aproj speed");
    if (mult != 1.0)
    {
        ScaleVector(velocity, mult);

        float maxSpeed = g_haprojMaxSpeed.FloatValue;
        float finalSpeed = GetVectorLength(velocity);

        if (finalSpeed > maxSpeed)
        {
            NormalizeVector(velocity, velocity);
            ScaleVector(velocity, maxSpeed);
            finalSpeed = maxSpeed;
        }

        float angles[3];
        GetVectorAngles(velocity, angles);
        SetEntPropVector(entity, Prop_Data, "m_vecAngVelocity", Float:{0.0, 0.0, 0.0});
        TeleportEntity(entity, NULL_VECTOR, angles, velocity);
    }

    float finalSpeed = GetVectorLength(velocity);
    if (g_haprojShowWarnings.BoolValue && finalSpeed > 0.0)
    {
        char classname[64];
        GetEntityClassname(entity, classname, sizeof(classname));
        PrintToServer("[aproj] WARNING: Entity %d (%s) has projectile speed %.1f HU/s", entity, classname, finalSpeed);
    }

    return Plugin_Stop;
}

float GetProjectileCustomAttrMultiplier(int projectile, const char[] attrName)
{
    float totalMult = 1.0;

    if (!IsValidEntity(projectile))
        return totalMult;

    // --- Check owner entity (usually the player body)
    int owner = GetEntPropEnt(projectile, Prop_Send, "m_hOwnerEntity");
    if (IsValidClient(owner))
    {
        float ownerMult = TF2CustAttr_GetFloat(owner, attrName, 1.0);
        if (ownerMult != 1.0)
            totalMult *= ownerMult;
    }

    // --- Check weapon: m_hOriginalLauncher or m_hThrower
    int weapon = -1;
    if (HasEntProp(projectile, Prop_Send, "m_hOriginalLauncher"))
    {
        weapon = GetEntPropEnt(projectile, Prop_Send, "m_hOriginalLauncher");
    }
    else if (HasEntProp(projectile, Prop_Send, "m_hThrower"))
    {
        weapon = GetEntPropEnt(projectile, Prop_Send, "m_hThrower");
    }

    if (IsValidEntity(weapon))
    {
        float weaponMult = TF2CustAttr_GetFloat(weapon, attrName, 1.0);
        if (weaponMult != 1.0)
            totalMult *= weaponMult;
    }

    // --- Special case: sentry rockets also consider the Engineer and Wrangler
    static char classname[64];
    GetEntityClassname(projectile, classname, sizeof(classname));

    if (StrEqual(classname, "tf_projectile_sentryrocket"))
    {
        // Owner here is the sentry
        int trueowner = IsValidEntity(owner) ? GetEntPropEnt(owner, Prop_Send, "m_hBuilder") : -1;

        if (IsValidClient(trueowner))
        {
            // Check for player-applied custom attribute
            float bodyMult = TF2CustAttr_GetFloat(trueowner, attrName, 1.0);
            if (bodyMult != 1.0)
                totalMult *= bodyMult;

            // Check if they have a Wrangler
            for (int slot = 0; slot <= 5; slot++)
            {
                int item = GetPlayerWeaponSlot(trueowner, slot);
                if (!IsValidEntity(item))
                    continue;

                char itemClassname[64];
                GetEntityClassname(item, itemClassname, sizeof(itemClassname));

                if (StrEqual(itemClassname, "tf_weapon_laser_pointer"))
                {
                    float wranglerMult = TF2CustAttr_GetFloat(item, attrName, 1.0);
                    if (wranglerMult != 1.0)
                        totalMult *= wranglerMult;
                    break;
                }
            }
        }
    }

    return totalMult;
}

bool IsVelocityBlacklisted(const char[] classname)
{
    for (int i = 0; i < sizeof(g_ProjectileVelocityBlacklist); i++)
    {
        if (StrEqual(classname, g_ProjectileVelocityBlacklist[i]))
            return true;
    }
    return false;
}


// Basic Helpers
bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}