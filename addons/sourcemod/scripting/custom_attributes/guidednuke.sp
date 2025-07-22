// att_guided_nuke.sp - Guided Nuke custom attribute

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <tf2utils>
#include <tf2attributes>
#include <tf_custom_attributes>
#include <stocksoup/math>
#include <stocksoup/tf/entity_prop_stocks>

#define ATTR_NAME "guided nuke"
#define ATTR_TURNSPEED "guided nuke turn speed"
#define DEFAULT_TURNSPEED 0.14
#define ATTR_DAMAGE "damage penalty"
#define DEFAULT_DAMAGE_MULTIPLIER 3.0

ConVar g_cvNukeDamagePenalty;

public Plugin myinfo = {
    name = "Guided Nuke Attribute",
    author = "Kuro + OpenAI",
    description = "Rocket follows player's aim with blast and crit flag",
    version = "1.0",
    url = ""
};

public void OnPluginStart() {
    HookUserMessage(GetUserMessageId("VotePass"), DummyHook, true); // ensures OnPlayerRunCmd is active
    PrecacheModel("models/weapons/w_models/w_rocket.mdl", true);
    g_cvNukeDamagePenalty = CreateConVar("nuke_dmgmult", "3.0", "Damage multiplier for guided nuke rockets", FCVAR_NONE, true, 1.0, true, 20.0);
}

public void OnMapStart() {
    PrecacheModel("models/weapons/w_models/w_rocket.mdl", true);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon) {
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Continue;

    int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEntity(activeWeapon))
        return Plugin_Continue;

    float attr = TF2CustAttr_GetFloat(activeWeapon, ATTR_NAME, 0.0);
    if (attr <= 0.0)
        return Plugin_Continue;

    // Only apply when pressing attack
    if (buttons & IN_ATTACK) {
        int clip = GetEntProp(activeWeapon, Prop_Send, "m_iClip1");
        int ammoType = GetEntProp(activeWeapon, Prop_Data, "m_iPrimaryAmmoType");
        int ammoOffset = FindSendPropInfo("CTFPlayer", "m_iAmmo") + (ammoType * 4);
        int reserve = GetEntData(client, ammoOffset);

        // 🔍 Debug print
        //PrintToServer("[NUKE DEBUG] client %N | clip = %d | reserve = %d", client, clip, reserve);

        if (reserve > 0 && clip != 1) {
            SetEntProp(activeWeapon, Prop_Send, "m_iClip1", 1);
            SetEntData(client, ammoOffset, reserve - 1, 4, true); // directly subtract reserve
            //PrintToServer("[NUKE] Ammo Handled");
        }

        TF2Attrib_SetByName(activeWeapon, "fire rate bonus", 2.0);
        TF2Attrib_SetByName(activeWeapon, "faster reload rate", 0.0);
        TF2Attrib_SetByName(activeWeapon, "clip size bonus", 0.0);
        TF2Attrib_SetByName(activeWeapon, "Projectile speed increased", 0.75);

        // Damage handling
        float Multiplier = g_cvNukeDamagePenalty.FloatValue * (1.0 + (attr / 10.0));
        TF2Attrib_SetByName(activeWeapon, "damage penalty", Multiplier);

        // Forces crits universally
        TF2Attrib_SetByName(activeWeapon, "crit vs non burning players", 1.0);
        TF2Attrib_SetByName(activeWeapon, "crit vs burning players", 1.0);
    }

    return Plugin_Continue;
}

public void OnGameFrame() {
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "tf_projectile_rocket")) != -1) {
        int launcher = GetEntPropEnt(ent, Prop_Send, "m_hOriginalLauncher");
        if (!IsValidEntity(launcher)) continue;

        float attr = TF2CustAttr_GetFloat(launcher, ATTR_NAME, 0.0);
        if (attr > 0.0) {
            Think_GuidedRocket(ent);
        }
    }
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

void Think_GuidedRocket(int rocket) {
    int launcher = GetEntPropEnt(rocket, Prop_Send, "m_hOriginalLauncher");
    if (!IsValidEntity(launcher)) return;

    int owner = TF2_GetEntityOwner(launcher);
    if (owner < 1 || owner > MaxClients) return;

    float attr = TF2CustAttr_GetFloat(launcher, ATTR_NAME, 0.0);
    float baseTurn = TF2CustAttr_GetFloat(launcher, ATTR_TURNSPEED, DEFAULT_TURNSPEED);
    float turnRate = baseTurn * attr;

    float rocketPos[3], aimPoint[3], curVel[3], targetVel[3];
    GetEntPropVector(rocket, Prop_Data, "m_vecAbsOrigin", rocketPos);
    GetEntPropVector(rocket, Prop_Data, "m_vecAbsVelocity", curVel);
    float speed = NormalizeVector(curVel, curVel);

    ComputePlayerAimPoint(owner, aimPoint);
    MakeVectorFromPoints(rocketPos, aimPoint, targetVel);
    NormalizeVector(targetVel, targetVel);

    for (int i = 0; i < 3; i++) {
        curVel[i] = LerpFloat(turnRate, curVel[i], targetVel[i]);
    }

    NormalizeVector(curVel, curVel);
    ScaleVector(curVel, speed);

    SetEntPropVector(rocket, Prop_Data, "m_vecAbsVelocity", curVel);

    float newAngles[3];
    GetVectorAngles(curVel, newAngles);
    TeleportEntity(rocket, NULL_VECTOR, newAngles, NULL_VECTOR);

}

void ComputePlayerAimPoint(int client, float vecOut[3]) {
    float eyePos[3], eyeAng[3];
    GetClientEyePosition(client, eyePos);
    GetClientEyeAngles(client, eyeAng);

    float fwd[3];
    GetAngleVectors(eyeAng, fwd, NULL_VECTOR, NULL_VECTOR);
    ScaleVector(fwd, 10000.0);
    AddVectors(eyePos, fwd, vecOut);
}

public Action DummyHook(UserMsg msg_id, Protobuf pbf, const int[] players, int playersNum, bool reliable, bool init) {
    return Plugin_Continue;
}


// Particles

// Visual overrides for guided rockets
void ApplyNukeVisualsToRocket(int rocket) {
    if (!IsValidEntity(rocket))
        return;

    int launcher = GetEntPropEnt(rocket, Prop_Send, "m_hOriginalLauncher");
    if (!IsValidEntity(launcher))
        return;

    int owner = TF2_GetEntityOwner(launcher);
    if (!IsValidClient(owner))
        return;

    int team = GetClientTeam(owner);
    //PrintToServer("[NUKE DEBUG] Rocket %d from owner %N (team %d)", rocket, owner, team);

    // Set a visible, glowing model
    SetEntityModel(rocket, "models/weapons/w_models/w_rocket.mdl");

    // Apply team-colored tint and particles
    if (team == 3) {
        SetEntityRenderColor(rocket, 0, 255, 255, 255);  // Cyan
        AttachParticle(rocket, "critical_rocket_bluesparks");
        AttachParticle(rocket, "critical_rocket_blue");
    } else {
        SetEntityRenderColor(rocket, 255, 64, 64, 255);  // Red-orange
        AttachParticle(rocket, "critical_rocket_redsparks");
        AttachParticle(rocket, "critical_rocket_red");
    }

    SetEntPropFloat(rocket, Prop_Send, "m_flModelScale", 1.5);
    SetEntityRenderMode(rocket, RENDER_NORMAL);
    //PrintToServer("[NUKE] Rocket visuals applied.");
}

// Hook rocket spawn
public void OnEntityCreated(int entity, const char[] classname) {
    if (StrEqual(classname, "tf_projectile_rocket")) {
        SDKHook(entity, SDKHook_SpawnPost, OnRocketSpawned);
    }
}

public void OnRocketSpawned(int rocket) {
    if (!IsValidEntity(rocket))
        return;

    int launcher = GetEntPropEnt(rocket, Prop_Send, "m_hOriginalLauncher");
    if (!IsValidEntity(launcher))
        return;

    float attr = TF2CustAttr_GetFloat(launcher, ATTR_NAME, 0.0);
    if (attr <= 0.0)
        return; // Not a guided nuke rocket

    ApplyNukeVisualsToRocket(rocket);
}

void AttachParticle(int parent, const char[] name) {
    int particle = CreateEntityByName("info_particle_system");
    if (!IsValidEntity(particle))
        return;

    DispatchKeyValue(particle, "effect_name", name);
    DispatchKeyValue(particle, "start_active", "1");
    DispatchSpawn(particle);

    float pos[3];
    GetEntPropVector(parent, Prop_Send, "m_vecOrigin", pos);
    TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);

    SetVariantString("!activator");
    AcceptEntityInput(particle, "SetParent", parent);
    ActivateEntity(particle);
    AcceptEntityInput(particle, "start");

    CreateTimer(5.0, DeleteParticleLater, EntIndexToEntRef(particle));
}

public Action DeleteParticleLater(Handle timer, any ref) {
    int ent = EntRefToEntIndex(ref);
    if (ent != INVALID_ENT_REFERENCE && IsValidEntity(ent)) {
        AcceptEntityInput(ent, "Kill");
    }
    return Plugin_Stop;
}