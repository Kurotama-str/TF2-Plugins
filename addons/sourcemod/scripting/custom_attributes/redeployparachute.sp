// Parachute Redeploy Attribute Sub-plugin

#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>
#include <tf_custom_attributes>

#define ATTR_PARACHUTE_COND TFCond_Parachute
#define ATTR_NAME "parachute redeploy" // <=== ATTRIBUTE NAME HERE

public Plugin myinfo =
{
    name = "Custom Attr: Parachute Redeploy",
    author = "Kuro + OpenAI",
    description = "Allows parachute redeployment mid-air if a custom attribute is present.",
    version = "1.0"
};

bool g_bParachuteActive[MAXPLAYERS + 1];
bool g_bJumpPressed[MAXPLAYERS + 1];
bool g_bHasDeployedParachute[MAXPLAYERS + 1];
bool g_bCanRedeploy[MAXPLAYERS + 1];
bool g_bWasAirborne[MAXPLAYERS + 1];

public void OnPluginStart()
{
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    CreateTimer(0.02, Timer_CheckParachuteInput, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
    ResetFlags(client);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsClientInGame(client))
    {
        ResetFlags(client);
    }
}

void ResetFlags(int client)
{
    g_bParachuteActive[client] = false;
    g_bJumpPressed[client] = false;
    g_bHasDeployedParachute[client] = false;
    g_bCanRedeploy[client] = true;
    g_bWasAirborne[client] = false;
}

public void TF2_OnConditionAdded(int client, TFCond condition)
{
    if (condition == ATTR_PARACHUTE_COND)
    {
        g_bParachuteActive[client] = true;
        g_bHasDeployedParachute[client] = true;
        g_bCanRedeploy[client] = false;
    }
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
    if (condition == ATTR_PARACHUTE_COND)
    {
        g_bParachuteActive[client] = false;
        g_bCanRedeploy[client] = false; // prevent immediate redeploy until jump is released
    }
}

public Action Timer_CheckParachuteInput(Handle timer)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsPlayerAlive(client))
            continue;

        bool airborne = IsPlayerAirborne(client);
        if (!airborne && g_bWasAirborne[client])
        {
            g_bCanRedeploy[client] = true; // touched ground, can redeploy after jump
            g_bHasDeployedParachute[client] = false; // force redeploy via normal trigger
        }
        g_bWasAirborne[client] = airborne;

        bool jumpHeld = (GetClientButtons(client) & IN_JUMP) != 0;
        bool wasHeld = g_bJumpPressed[client];
        g_bJumpPressed[client] = jumpHeld;

        if (!jumpHeld && wasHeld)
        {
            // jump released — allow redeploy if other conditions met later
            g_bCanRedeploy[client] = true;
        }

        if (jumpHeld && !wasHeld && !g_bParachuteActive[client] && g_bHasDeployedParachute[client] && g_bCanRedeploy[client] && airborne)
        {
            int chute = FindParachuteItem(client);
            if (chute != -1 && TF2CustAttr_GetFloat(chute, ATTR_NAME, 0.0) > 0.0)
            {
                TF2_AddCondition(client, TFCond_Parachute, -1.0);
                g_bCanRedeploy[client] = false;
            }
        }
    }

    return Plugin_Continue;
}

bool IsPlayerAirborne(int client)
{
    return (GetEntityFlags(client) & FL_ONGROUND) == 0;
}

int FindParachuteItem(int client)
{
    for (int slot = 0; slot <= 5; slot++)
    {
        int weapon = GetPlayerWeaponSlot(client, slot);
        if (!IsValidEntity(weapon))
            continue;

        if (TF2Attrib_GetByName(weapon, "parachute attribute") != Address_Null)
            return weapon;
    }

    if (TF2Attrib_GetByName(client, "parachute attribute") != Address_Null)
        return client;

    return -1;
}
