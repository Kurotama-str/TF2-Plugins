// att_hellfire_ring.sp - Hellfire Ring custom attribute

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <tf2utils>
#include <tf2attributes>
#include <tf_custom_attributes>

#define ATTR_NAME "hellfire ring"
#define BASE_RANGE 150.0
#define BASE_DAMAGE 12.0
#define FIRE_COOLDOWN 0.1

// sound support
#define FLAME_LOOP   "weapons/flame_thrower_loop.wav"

// attribute support 1
#define NUM_HF_ATTRIBUTES 17

enum HFAttributeIndex 
{
    HF_BurnDamageIncrease = 0,
    HF_BurnTimeIncrease,
    HF_BurnDamageReduction,
    HF_BurnTimeReduction,
    HF_HealOnHitRapid,
    HF_HealOnHitSlow,
    HF_HealOnKill,
    HF_SlowOnHitMinor,
    HF_SlowOnHitMajor,
    HF_RevealCloaked,
    HF_RevealDisguised,
    HF_DamageBonus,
    HF_DamagePenalty,
    HF_DamagePenaltyVsPlayers,

    // Ammo handling
    HF_MaxAmmoPrimaryIncreased,   // multiplier, default 1
    HF_MaxAmmoPrimaryReduced,     // multiplier, default 1
    HF_HiddenPrimaryMaxAmmoBonus  // multiplier, default 1
};

float g_fLastRingTime[MAXPLAYERS + 1];
bool g_bHasCustomAttributes = false;
ConVar g_cvFlameCount;

ConVar g_cvHFBlockNative, g_cvHFCostPerRing, g_cvHFBlockPad;

int  g_iHFReserve[MAXPLAYERS + 1];     // our custom reserve
bool g_bHFAmmoInit[MAXPLAYERS + 1];    // did we latch starting reserve
int g_iHFMaxReserve[MAXPLAYERS + 1];   // computed max reserve cap (after multipliers)
ConVar g_cvHFBaseMaxReserve;                 // base max reserve before multipliers (default: Pyro 200)
bool g_bHellfireLoopPlaying[MAXPLAYERS+1];

public Plugin myinfo = {
    name = "Hellfire Ring Attribute",
    author = "Kuro + OpenAI",
    description = "Replaces Pyro's flamethrower with a fire ring",
    version = "1.4",
    url = ""
};

public void OnPluginStart() 
{
    RegConsoleCmd("sm_testfirering", TestFireRing);
    HookEvent("player_spawn", OnPlayerSpawn);

    // Block native flames & custom ammo cost
    g_cvHFBlockNative = CreateConVar("hf_block_native", "1", "Block native flamethrower firing when hellfire is present", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvHFCostPerRing = CreateConVar("hf_cost_per_ring", "1", "Custom ammo consumed per Hellfire ring", FCVAR_NONE, true, 0.0, true, 100.0);
    g_cvHFBlockPad    = CreateConVar("hf_block_pad", "0.25", "Seconds to push next primary attack when blocking native fire", FCVAR_NONE, true, 0.05, true, 0.5);
    g_cvHFBaseMaxReserve = CreateConVar("hf_base_max_reserve", "200", "Base primary reserve for Hellfire (before maxammo multipliers)", FCVAR_NONE, true, 1.0, true, 1000.0);


    g_bHasCustomAttributes = LibraryExists("tf2custattr");
    if (g_bHasCustomAttributes) {
        //PrintToServer("[HellfireRing] Custom Attributes support detected.");
    }

    PrecacheSound(FLAME_LOOP);

    HookUserMessage(GetUserMessageId("VotePass"), DummyHook, true); // ensure OnPlayerRunCmd triggers
    g_cvFlameCount = CreateConVar("hf_particlemult", "3", "Base number of flame particles per ring (used as multiplier)", FCVAR_NONE, true, 1.0, true, 100.0);

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
}

public void OnLibraryAdded(const char[] name) 
{
    if (StrEqual(name, "tf2custattr")) {
        g_bHasCustomAttributes = true;
        PrintToServer("[HellfireRing] Custom Attributes plugin loaded.");
    }
}
public void OnLibraryRemoved(const char[] name) 
{
    if (StrEqual(name, "tf2custattr")) {
        g_bHasCustomAttributes = false;
        PrintToServer("[HellfireRing] Custom Attributes plugin unloaded.");
    }
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (!IsValidClient(attacker) || attacker == victim)
        return;

    int activeWeapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEntity(activeWeapon))
        return;

    // Only proceed if weapon has hellfire
    if (TF2CustAttr_GetFloat(activeWeapon, ATTR_NAME, 0.0) <= 0.0)
        return;

    float attrs[NUM_HF_ATTRIBUTES];
    GetHellfireAttributesFromWeapon(activeWeapon, attrs);

    if (attrs[HF_HealOnKill] > 0.0)
    {
        int current = GetClientHealth(attacker);
        int maxOverheal = GetHellfireMaxOverheal(attacker);
        int newHealth = current + RoundToCeil(attrs[HF_HealOnKill]);

        if (newHealth > maxOverheal)
            newHealth = maxOverheal;

        SetEntityHealth(attacker, newHealth);
    }
}

public Action TestFireRing(int client, int args) {
    if (IsClientInGame(client) && IsPlayerAlive(client)) {
        FireRing(client, 1.0);
    }
    return Plugin_Handled;
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    g_fLastRingTime[client] = 0.0;

    // reset hellfire custom ammo for this life; we’ll latch on first use
    g_bHFAmmoInit[client] = false;
    g_iHFReserve[client] = 0;
    HandleHellfireLoop(client, false);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if (!g_bHasCustomAttributes || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Continue;

    // Active weapon must be valid and be the one with Hellfire
    int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEntity(activeWeapon))
        return Plugin_Continue;

    float strength = TF2CustAttr_GetFloat(activeWeapon, ATTR_NAME, 0.0);
    if (strength <= 0.0)
        return Plugin_Continue;

    // === Fetch attributes and compute ammo cap ===
    float hfAttrs[NUM_HF_ATTRIBUTES];
    GetHellfireAttributesFromWeapon(activeWeapon, hfAttrs);
    g_iHFMaxReserve[client] = ComputeHellfireMaxReserve(hfAttrs, client);

    // Initialize/maintain our custom reserve
    InitHellfireAmmoIfNeeded(client, activeWeapon);
    AbsorbEngineReserveIncreases(client, activeWeapon); // pick up packs/dispenser refills

    // Clamp reserve to computed cap
    if (g_iHFReserve[client] > g_iHFMaxReserve[client])
        g_iHFReserve[client] = g_iHFMaxReserve[client];

    bool pressing = (buttons & IN_ATTACK) != 0;
    float now = GetGameTime();

    // Always block native primary while M1 is down (so no stock flames, no stock ammo drain)
    if (pressing && g_cvHFBlockNative.BoolValue) {
        BlockPrimaryNow(activeWeapon, g_cvHFBlockPad.FloatValue);
    }

    if (pressing) {
        if (now - g_fLastRingTime[client] >= FIRE_COOLDOWN) {
            int cost = RoundToFloor(Max(g_cvHFCostPerRing.IntValue * strength, 1.0));
            if (g_iHFReserve[client] >= cost) {
                // Keep native flames inert as an extra safety
                TF2Attrib_SetByName(activeWeapon, "flame_speed", 0.0);
                TF2Attrib_SetByName(activeWeapon, "flame_up_speed", 0.0);
                TF2Attrib_SetByName(activeWeapon, "flame_lifetime", -100.0);

                FireRing(client, strength);
                HandleHellfireLoop(client, true); // keep loop sound alive
                g_fLastRingTime[client] = now;
                g_iHFReserve[client] -= cost;

                if (g_iHFReserve[client] < 0) 
                    g_iHFReserve[client] = 0;
            }
        }
    }
    else {
        HandleHellfireLoop(client, false); // shut off loop sound
    }

    // Final clamp and HUD sync
    if (g_iHFReserve[client] > g_iHFMaxReserve[client])
        g_iHFReserve[client] = g_iHFMaxReserve[client];
    SyncReserveToEngine(client, activeWeapon);

    return Plugin_Continue;
}

// attribute support 2

void GetHellfireAttributesFromWeapon(int weapon, float output[NUM_HF_ATTRIBUTES])
{
    // Set default values
    output[HF_BurnDamageIncrease]     = 1.0;
    output[HF_BurnTimeIncrease]       = 1.0;
    output[HF_BurnDamageReduction]    = 1.0;
    output[HF_BurnTimeReduction]      = 1.0;
    output[HF_HealOnHitRapid]         = 0.0;
    output[HF_HealOnHitSlow]          = 0.0;
    output[HF_HealOnKill]             = 0.0;
    output[HF_SlowOnHitMinor]         = 0.0;
    output[HF_SlowOnHitMajor]         = 0.0;
    output[HF_RevealCloaked]          = 0.0;
    output[HF_RevealDisguised]        = 0.0;
    output[HF_DamageBonus]            = 1.0;
    output[HF_DamagePenalty]          = 1.0;
    output[HF_DamagePenaltyVsPlayers] = 1.0;
    // Ammo mult defaults (default to 1.0)
    output[HF_MaxAmmoPrimaryIncreased]   = 1.0;
    output[HF_MaxAmmoPrimaryReduced]     = 1.0;
    output[HF_HiddenPrimaryMaxAmmoBonus] = 1.0;

    static const char attrNames[NUM_HF_ATTRIBUTES][] = {
        "weapon burn dmg increased",
        "weapon burn time increased",
        "weapon burn dmg reduced",
        "weapon burn time reduced",
        "heal on hit for rapidfire",
        "heal on hit for slowfire",
        "heal on kill",
        "slow enemy on hit",
        "slow enemy on hit major",
        "reveal cloaked victim on hit",
        "reveal disguised victim on hit",
        "damage bonus",
        "damage penalty",
        "dmg penalty vs players",
        "maxammo primary increased",
        "maxammo primary reduced",
        "hidden primary max ammo bonus"
    };

    for (int i = 0; i < NUM_HF_ATTRIBUTES; i++)
    {
        Address attr = TF2Attrib_GetByName(weapon, attrNames[i]);
        if (attr != Address_Null)
        {
            float value = TF2Attrib_GetValue(attr);
            if (value == value && value != 0.0) // not NaN and not zero
            {
                output[i] = value;
            }
        }
    }
}

void FireRing(int client, float rangeMult)
{
    float range = BASE_RANGE * rangeMult;
    float origin[3];
    GetClientAbsOrigin(client, origin);

    int team = GetClientTeam(client);
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

    float attrs[NUM_HF_ATTRIBUTES];
    GetHellfireAttributesFromWeapon(weapon, attrs);


    float attr = TF2CustAttr_GetFloat(weapon, ATTR_NAME, 0.0);
    int maxEntities = GetMaxEntities();
    for (int ent = 1; ent < maxEntities; ent++) {
        if (!IsValidEntity(ent) || !IsValidEdict(ent))
            continue;

        float targetPos[3];
        bool hasPos = false;

        if (HasEntProp(ent, Prop_Send, "m_vecOrigin")) {
            GetEntPropVector(ent, Prop_Send, "m_vecOrigin", targetPos);
            hasPos = true;
        } else if (HasEntProp(ent, Prop_Data, "m_vecAbsOrigin")) {
            GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", targetPos);
            hasPos = true;
        }

        if (!hasPos)
            continue;

        if (GetVectorDistance(origin, targetPos) > range)
            continue;

        char type[16];
        strcopy(type, sizeof(type), GetTargetType(ent));

        char classname[64];
        GetEntityClassname(ent, classname, sizeof(classname));

        //PrintToServer("[HellfireRing] Entity %d (class: %s) is of type: %s", ent, classname, type);
        float damage = CalculateHellfireDamage(BASE_DAMAGE + RoundFloat(attr * 4.0), attrs);
        int dmgType = DMG_BURN | DMG_IGNITE;

        bool isCrit, isMiniCrit;
        CheckHellfireCrits(client, ent, weapon, isCrit, isMiniCrit);

        if (isCrit) {
            damage *= 1.1;
            dmgType |= DMG_CRIT;
        } else if (isMiniCrit) {
            damage *= 1.35;
        }

        bool shouldDamage = false;

        if (StrEqual(type, "player")) {
            if (GetClientTeam(ent) != team) {
                shouldDamage = true;
            }
        }
        else if (StrEqual(type, "building")) {
            if (GetEntProp(ent, Prop_Send, "m_iTeamNum") != team) {
                damage /= 10.0;
                shouldDamage = true;
            }
        }
        // Other entities like bosses
        else if (StrEqual(type, "other")) {
            damage *= 3.0;
            shouldDamage = true;
        }
        if (shouldDamage) {
            float zeroForce[3] = {0.0, 0.0, 0.0};
            SDKHooks_TakeDamage(ent, client, client, damage, dmgType, -1, zeroForce, zeroForce, false);
            ApplyHellfireOnHitEffects(client, ent, attrs);
        }
    }

    EmitFireRingParticle(client, range, rangeMult);
}

float Max(float a, float b = 1.0)
{
    if (a > b)
        return a;
    return b
}

// attribute support 3
float CalculateHellfireDamage(float baseDamage, const float attrs[NUM_HF_ATTRIBUTES])
{
    float damage = baseDamage;
    damage *= attrs[HF_DamageBonus];
    damage *= attrs[HF_DamagePenalty];
    damage *= attrs[HF_DamagePenaltyVsPlayers];
    return damage;
}

int GetHellfireMaxOverheal(int client)
{
    if (!IsValidEntity(client))
        return 0;

    bool isClient = (client > 0 && client <= MaxClients && IsClientInGame(client));

    int baseMax;
    if (isClient)
    {
        TFClassType class = TF2_GetPlayerClass(client);
        baseMax = TF2_GetClassMaxHealth(class);
    }
    else
    {
        baseMax = GetEntProp(client, Prop_Data, "m_iMaxHealth");
    }

    float bonus = 0.0;
    if (isClient)
    {
        bonus += GetLiveAttributeTotal(client, "max health additive bonus");
        bonus -= GetLiveAttributeTotal(client, "max health additive penalty");
        bonus += GetLiveAttributeTotal(client, "SET BONUS: max health additive bonus");
    }

    float effectiveMax = float(baseMax) + bonus;

    // You can adjust this multiplier if overheal should exceed 100%
    return RoundToCeil(effectiveMax * 1.5);
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

void ApplyHellfireOnHitEffects(int client, int target, const float attrs[NUM_HF_ATTRIBUTES])
{
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEntity(weapon))
        return;

    // Only apply hellfire effects if the weapon actually has the hellfire attribute
    if (TF2CustAttr_GetFloat(weapon, ATTR_NAME, 0.0) <= 0.0)
        return;

    // Heal on hit
    float heal = attrs[HF_HealOnHitRapid] + attrs[HF_HealOnHitSlow];
    if (heal > 0.0) {
        int current = GetClientHealth(client);
        int maxOverheal = GetHellfireMaxOverheal(client);
        int newHealth = current + RoundToCeil(heal);
        if (newHealth > maxOverheal) newHealth = maxOverheal;
        SetEntityHealth(client, newHealth);
    }

    // Skip effects if target is invalid
    if (target <= 0 || target > MaxClients || !IsClientInGame(target) || !IsPlayerAlive(target))
        return;

    // Slow on hit using stun
    if (attrs[HF_SlowOnHitMinor] > 0.0) {
        TF2_StunPlayer(target, 0.5, 0.0, TF_STUNFLAG_SLOWDOWN, client);
    }
    if (attrs[HF_SlowOnHitMajor] > 0.0) {
        TF2_StunPlayer(target, 1.0, 0.0, TF_STUNFLAG_SLOWDOWN, client);
    }

    // Reveal spy
    if (attrs[HF_RevealCloaked] > 0.0)
        TF2_RemoveCondition(target, TFCond_Cloaked);
    if (attrs[HF_RevealDisguised] > 0.0)
        TF2_RemoveCondition(target, TFCond_Disguised);

    // Ignite using TF2Utils to allow weapon attribute effects
    TF2Util_IgnitePlayer(target, client, 5.0, weapon); // 10s is the cap in Jungle Inferno
}

void CheckHellfireCrits(int client, int target, int weapon, bool &isCrit, bool &isMiniCrit)
{
    isCrit = TF2_IsPlayerInCondition(client, TFCond_Kritzkrieged);
    isMiniCrit = TF2_IsPlayerInCondition(client, TFCond_Buffed) || TF2_IsPlayerInCondition(client, TFCond_MiniCritOnKill);

    if (target <= MaxClients && IsClientInGame(target) && IsPlayerAlive(target)) {
        bool burning = TF2_IsPlayerInCondition(target, TFCond_OnFire);

        Address critVsBurning = TF2Attrib_GetByName(weapon, "crit vs burning players");
        if (critVsBurning != Address_Null && TF2Attrib_GetValue(critVsBurning) > 0.0 && burning)
            isCrit = true;

        Address miniCritVsBurning = TF2Attrib_GetByName(weapon, "minicrit vs burning player");
        if (miniCritVsBurning != Address_Null && TF2Attrib_GetValue(miniCritVsBurning) > 0.0 && burning)
            isMiniCrit = true;
    }
}

// Particle handling
void EmitFireRingParticle(int client, float radius, float rangeMult) {
    float origin[3];
    GetClientAbsOrigin(client, origin);
    float angleOffset = GetGameTime() * 2.0; // rotation

    int ringCount = (rangeMult >= 1.5) ? 2 : 1; // spawn inner ring only if value is large enough

    for (int ring = 0; ring < ringCount; ring++) {
        float ringRadius = radius * (1.0 - 0.5 * ring); // first ring = 1.0, second ring = 0.5
        int baseCount = g_cvFlameCount.IntValue;
        int count = RoundToNearest(float(baseCount) * rangeMult * (ring == 0 ? 1.0 : 0.75)); // fewer inner particles
        float angleStep = 360.0 / count;

        for (int i = 0; i < count; i++) {
            float angle = DegToRad(angleStep * i) + angleOffset;
            float offset[3];
            offset[0] = Cosine(angle) * FloatAbs(ringRadius - 40.0);
            offset[1] = Sine(angle) * FloatAbs(ringRadius - 40.0);
            offset[2] = 0.0;

            float pos[3];
            pos[0] = origin[0] + offset[0];
            pos[1] = origin[1] + offset[1];
            pos[2] = origin[2];

            int particle = CreateEntityByName("info_particle_system");
            if (!IsValidEntity(particle)) {
                PrintToServer("[HellfireRing] Failed to create particle %d in ring %d", i + 1, ring + 1);
                continue;
            }

            DispatchKeyValue(particle, "effect_name", "dragons_fury_effect_parent");

            TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
            DispatchSpawn(particle);
            ActivateEntity(particle);
            AcceptEntityInput(particle, "start");

            //PrintToServer("[HellfireRing] Spawned ring %d particle %d at (%.1f %.1f %.1f)", ring + 1, i + 1, pos[0], pos[1], pos[2]);
            CreateTimer(0.5, DeleteParticle, EntIndexToEntRef(particle));
        }
    }
}

public Action DeleteParticle(Handle timer, any ref) {
    int ent = EntRefToEntIndex(ref);
    if (ent != INVALID_ENT_REFERENCE && IsValidEntity(ent))
        AcceptEntityInput(ent, "Kill");
    return Plugin_Stop;
}

public Action DummyHook(UserMsg msg_id, Protobuf pbf, const int[] players, int playersNum, bool reliable, bool init) {
    return Plugin_Continue;
}

// Entity Handler
/**
 * Determines if an entity is a valid damageable target and categorizes it.
 *
 * @param ent The entity index to evaluate.
 * @return A string: "invalid", "player", "building", or "other"
 */
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
            strcopy(result, sizeof(result), "invalid");
        }
        else
        {
            char classname[64];
            GetEntityClassname(ent, classname, sizeof(classname));

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

// Ensure our custom reserve is initialized from the engine the first time we see hellfire
void InitHellfireAmmoIfNeeded(int client, int weapon)
{
    if (g_bHFAmmoInit[client])
        return;

    int ammoType = GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType");
    if (ammoType < 0) {
        // Weird case (shouldn't happen on flamethrowers), just mark initialized
        g_iHFReserve[client] = 0;
        g_bHFAmmoInit[client] = true;
        return;
    }

    int reserve = GetEntProp(client, Prop_Send, "m_iAmmo", _, ammoType);

    // Clamp to current cap if it's been computed already
    if (g_iHFMaxReserve[client] > 0 && reserve > g_iHFMaxReserve[client]) {
        reserve = g_iHFMaxReserve[client];
    }

    g_iHFReserve[client] = reserve;  // start from (clamped) HUD value
    g_bHFAmmoInit[client] = true;
}

// Read any increases from pickups/dispenser before we overwrite the HUD,
// so our custom reserve can grow naturally.
void AbsorbEngineReserveIncreases(int client, int weapon)
{
    int ammoType = GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType");
    if (ammoType < 0) 
        return;

    int engineVal = GetEntProp(client, Prop_Send, "m_iAmmo", _, ammoType);

    if (engineVal > g_iHFReserve[client]) {
        g_iHFReserve[client] = engineVal;

        // clamp to cap
        if (g_iHFReserve[client] > g_iHFMaxReserve[client]) {
            g_iHFReserve[client] = g_iHFMaxReserve[client];
        }
    }
}

// Mirror our custom reserve back to the engine so the HUD displays correctly.
void SyncReserveToEngine(int client, int weapon)
{
    int ammoType = GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType");
    if (ammoType < 0) return;
    if (g_iHFReserve[client] < 0) g_iHFReserve[client] = 0;
    SetEntProp(client, Prop_Send, "m_iAmmo", g_iHFReserve[client], _, ammoType);
}

// Push the weapon’s next primary attack forward to block native firing this tick.
void BlockPrimaryNow(int weapon, float pad)
{
    float now = GetGameTime();
    SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", now + pad);
}

// Compute maxammo
int ComputeHellfireMaxReserve(const float attrs[NUM_HF_ATTRIBUTES], int client)
{
    float base = g_cvHFBaseMaxReserve.FloatValue;

    // Weapon-local multipliers (already filled in attrs by GetHellfireAttributesFromWeapon)
    float inc = attrs[HF_MaxAmmoPrimaryIncreased];
    float red = attrs[HF_MaxAmmoPrimaryReduced];
    float hid = attrs[HF_HiddenPrimaryMaxAmmoBonus];

    if (!(inc > 0.0)) inc = 1.0;
    if (!(red > 0.0)) red = 1.0;
    if (!(hid > 0.0)) hid = 1.0;

    // Client-wide multipliers (scan client entity directly)
    float bodyInc = 1.0;
    float bodyRed = 1.0;
    float bodyHid = 1.0;

    static const char ammoAttrs[3][] = {
        "maxammo primary increased",
        "maxammo primary reduced",
        "hidden primary max ammo bonus"
    };

    float bodyVals[3] = { 1.0, 1.0, 1.0 };

    for (int i = 0; i < 3; i++)
    {
        Address addr = TF2Attrib_GetByName(client, ammoAttrs[i]);
        if (addr != Address_Null)
        {
            float val = TF2Attrib_GetValue(addr);
            if (val > 0.0 && val == val) // valid and not NaN
            {
                bodyVals[i] = val;
            }
        }
    }

    bodyInc = bodyVals[0];
    bodyRed = bodyVals[1];
    bodyHid = bodyVals[2];

    // Final cap
    float cap = base * inc * red * hid * bodyInc * bodyRed * bodyHid;

    if (cap < 1.0) cap = 1.0;
    if (cap > 2000000.0) cap = 2000000.0;

    return RoundToFloor(cap);
}

public void HandleHellfireLoop(int client, bool pressing)
{
    if (pressing) {
        if (!g_bHellfireLoopPlaying[client]) {
            EmitSoundToAll(FLAME_LOOP, client, SNDCHAN_WEAPON, SNDLEVEL_NORMAL, SND_NOFLAGS);
            g_bHellfireLoopPlaying[client] = true;
            //PrintToChatAll("Triggered On");
        }
    } 
    else {
        if (g_bHellfireLoopPlaying[client]) {
            StopSound(client, SNDCHAN_WEAPON, FLAME_LOOP);
            g_bHellfireLoopPlaying[client] = false;
            //PrintToChatAll("Triggered Off");
        }
    }
}