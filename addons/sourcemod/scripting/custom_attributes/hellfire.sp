// hellfire.sp - Hellfire Ring custom attribute

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>
#include <tf_custom_attributes>

#define ATTR_NAME "hellfire ring"
#define BASE_RANGE 150.0
#define BASE_DAMAGE 16.0
#define FIRE_COOLDOWN 0.1

float g_fLastRingTime[MAXPLAYERS + 1];
bool g_bHasCustomAttributes = false;
ConVar g_cvFlameCount;

public Plugin myinfo = {
    name = "Hellfire Ring Attribute",
    author = "Kuro + OpenAI",
    description = "Replaces Pyro's flamethrower with a fire ring",
    version = "1.0",
    url = ""
};

public void OnPluginStart() {
    RegConsoleCmd("sm_testfirering", TestFireRing);
    HookEvent("player_spawn", OnPlayerSpawn);

    g_bHasCustomAttributes = LibraryExists("tf2custattr");
    if (g_bHasCustomAttributes) {
        PrintToServer("[HellfireRing] Custom Attributes support detected.");
    }

    HookUserMessage(GetUserMessageId("VotePass"), DummyHook, true); // ensure OnPlayerRunCmd triggers
    g_cvFlameCount = CreateConVar("hf_particlemult", "3", "Base number of flame particles per ring (used as multiplier)", FCVAR_NONE, true, 1.0, true, 100.0);
}

public void OnLibraryAdded(const char[] name) {
    if (StrEqual(name, "tf2custattr")) {
        g_bHasCustomAttributes = true;
        PrintToServer("[HellfireRing] Custom Attributes plugin loaded.");
    }
}
public void OnLibraryRemoved(const char[] name) {
    if (StrEqual(name, "tf2custattr")) {
        g_bHasCustomAttributes = false;
        PrintToServer("[HellfireRing] Custom Attributes plugin unloaded.");
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
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon) {
    if (!g_bHasCustomAttributes || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Continue;

    int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEntity(activeWeapon))
        return Plugin_Continue;

    float attr = TF2CustAttr_GetFloat(activeWeapon, ATTR_NAME, 0.0);
    if (attr <= 0.0)
        return Plugin_Continue;

    TF2Attrib_SetByName(activeWeapon, "flame_speed", 0.0);

    if (buttons & IN_ATTACK) {
        float now = GetGameTime();
        if (now - g_fLastRingTime[client] < FIRE_COOLDOWN)
            return Plugin_Continue;

        int ammo = GetEntProp(activeWeapon, Prop_Send, "m_iClip1");
        if (ammo <= 0) {
            PrintToConsole(client,"[HellfireRing] %N has no ammo to fire", client);
            return Plugin_Continue;
        }

        FireRing(client, attr);
        g_fLastRingTime[client] = now;
    }

    return Plugin_Continue;
}

void FireRing(int client, float rangeMult) {
    //PrintToServer("[HellfireRing] Firing ring for %N (scale %.2f)", client, rangeMult);

    float range = BASE_RANGE * rangeMult;
    float origin[3];
    GetClientAbsOrigin(client, origin);

    int team = GetClientTeam(client);
    int hits = 0;

    for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i) || !IsPlayerAlive(i) || i == client || GetClientTeam(i) == team)
            continue;

        float targetPos[3];
        GetClientAbsOrigin(i, targetPos);

        if (GetVectorDistance(origin, targetPos) <= range) {
            float damage = BASE_DAMAGE;

            int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
            Address bonus = TF2Attrib_GetByName(weapon, "damage bonus");
            Address penalty = TF2Attrib_GetByName(weapon, "damage penalty");
            Address vsPlayers = TF2Attrib_GetByName(weapon, "dmg penalty vs players");

            if (bonus != Address_Null) damage *= TF2Attrib_GetValue(bonus);
            if (penalty != Address_Null) damage *= TF2Attrib_GetValue(penalty);
            if (vsPlayers != Address_Null) damage *= TF2Attrib_GetValue(vsPlayers);

            int dmgType = DMG_BURN | DMG_IGNITE;

            // Check for crit/minicrit conditions
            bool isCrit = TF2_IsPlayerInCondition(client, TFCond_Kritzkrieged);
            bool isMiniCrit = TF2_IsPlayerInCondition(client, TFCond_Buffed) || TF2_IsPlayerInCondition(client, TFCond_MiniCritOnKill);

            // Check if target is on fire
            bool targetBurning = TF2_IsPlayerInCondition(i, TFCond_OnFire);

            // Check attribute-based crits vs burning
            Address critVsBurning = TF2Attrib_GetByName(weapon, "crit vs burning players");
            if (critVsBurning != Address_Null && TF2Attrib_GetValue(critVsBurning) > 0.0 && targetBurning) {
                isCrit = true;
            }

            Address miniCritVsBurning = TF2Attrib_GetByName(weapon, "minicrit vs burning player");
            if (miniCritVsBurning != Address_Null && TF2Attrib_GetValue(miniCritVsBurning) > 0.0 && targetBurning) {
                isMiniCrit = true;
            }

            // Apply scaling
            if (isCrit) {
                damage *= 3.0;
                dmgType |= DMG_CRIT;
            } else if (isMiniCrit) {
                damage *= 1.35;
            }

            // Use client as both attacker and inflictor to ensure proper kill credit
            SDKHooks_TakeDamage(i, client, client, damage, dmgType);
            TF2_IgnitePlayer(i, client);

            //PrintToServer("[HellfireRing] Hit %N for %.1f and ignited", i, damage);
            hits++;
        }
    }

    if (hits == 0) {
        //PrintToServer("[HellfireRing] No targets hit");
    }

    EmitFireRingParticle(client, range, rangeMult);
}

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
