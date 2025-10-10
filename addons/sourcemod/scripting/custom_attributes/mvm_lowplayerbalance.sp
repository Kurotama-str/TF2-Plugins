#include <sourcemod>
#include <tf2_stocks>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "0.1"

public Plugin myinfo = {
    name = "MVM - Low Player Balance",
    author = "Kuro + Anthropic AI",
    description = "Applies conditional effects based on RED team player count",
    version = PLUGIN_VERSION,
    url = ""
};

// Convar
ConVar g_cvConfigName;

// KeyValues handle for config
KeyValues g_kvConfig;

// Supported conditions (all conditions from the document)
int g_iSupportedConditions[] = {
    5,   // TF_COND_INVULNERABLE
    11,  // TF_COND_CRITBOOSTED
    15,  // TF_COND_STUNNED
    16,  // TF_COND_OFFENSEBUFF
    19,  // TF_COND_ENERGY_BUFF
    26,  // TF_COND_DEFENSEBUFF
    29,  // TF_COND_REGENONDAMAGEBUFF
    32,  // TF_COND_SPEED_BOOST
    34,  // TF_COND_CRITBOOSTED_USER_BUFF
    35,  // TF_COND_CRITBOOSTED_DEMO_CHARGE
    36,  // TF_COND_SODAPOPPER_HYPE
    37,  // TF_COND_CRITBOOSTED_FIRST_BLOOD
    38,  // TF_COND_CRITBOOSTED_BONUS_TIME
    39,  // TF_COND_CRITBOOSTED_CTF_CAPTURE
    40,  // TF_COND_CRITBOOSTED_ON_KILL
    42,  // TF_COND_DEFENSEBUFF_NO_CRIT_BLOCK
    44,  // TF_COND_CRITBOOSTED_RAGE_BUFF
    45,  // TF_COND_DEFENSEBUFF_HIGH
    46,  // TF_COND_SNIPERCHARGE_RAGE_BUFF
    49,  // TF_COND_DISGUISED_AS_DISPENSER
    51,  // TF_COND_INVULNERABLE_HIDE_UNLESS_DAMAGED
    52,  // TF_COND_INVULNERABLE_USER_BUFF
    55,  // TF_COND_RADIUSHEAL_ON_DAMAGE
    56,  // TF_COND_CRITBOOSTED_CARD_EFFECT
    57,  // TF_COND_INVULNERABLE_CARD_EFFECT
    58,  // TF_COND_MEDIGUN_UBER_BULLET_RESIST
    59,  // TF_COND_MEDIGUN_UBER_BLAST_RESIST
    60,  // TF_COND_MEDIGUN_UBER_FIRE_RESIST
    61,  // TF_COND_MEDIGUN_SMALL_BULLET_RESIST
    62,  // TF_COND_MEDIGUN_SMALL_BLAST_RESIST
    63,  // TF_COND_MEDIGUN_SMALL_FIRE_RESIST
    64,  // TF_COND_STEALTHED_USER_BUFF
    66,  // TF_COND_STEALTHED_USER_BUFF_FADING
    67,  // TF_COND_BULLET_IMMUNE
    68,  // TF_COND_BLAST_IMMUNE
    69,  // TF_COND_FIRE_IMMUNE
    70,  // TF_COND_PREVENT_DEATH
    72,  // TF_COND_HALLOWEEN_SPEED_BOOST
    73,  // TF_COND_HALLOWEEN_QUICK_HEAL
    74,  // TF_COND_HALLOWEEN_GIANT
    75,  // TF_COND_HALLOWEEN_TINY
    79,  // TF_COND_OBSCURED_SMOKE
    84,  // TF_COND_BALLOON_HEAD
    86,  // TF_COND_SWIMMING_CURSE
    90,  // TF_COND_RUNE_STRENGTH
    91,  // TF_COND_RUNE_HASTE
    92,  // TF_COND_RUNE_REGEN
    93,  // TF_COND_RUNE_RESIST
    94,  // TF_COND_RUNE_VAMPIRE
    95,  // TF_COND_RUNE_REFLECT
    96,  // TF_COND_RUNE_PRECISION
    97,  // TF_COND_RUNE_AGILITY
    102, // TF_COND_AFTERBURN_IMMUNE
    103, // TF_COND_RUNE_KNOCKOUT
    104, // TF_COND_RUNE_IMBALANCE
    105, // TF_COND_CRITBOOSTED_RUNE_TEMP
    107, // TF_COND_SWIMMING_NO_EFFECTS
    109, // TF_COND_RUNE_KING
    110, // TF_COND_RUNE_PLAGUE
    111, // TF_COND_RUNE_SUPERNOVA
    113, // TF_COND_KING_BUFFED
    114, // TF_COND_TEAM_GLOWS
    129, // TF_COND_POWERUPMODE_DOMINANT
    130  // TF_COND_IMMUNE_TO_PUSHBACK
};

public void OnPluginStart()
{
    // Create convar for config name
    g_cvConfigName = CreateConVar("sm_lpb_config", "LPB_default", "Config file name to use (without .cfg extension)", FCVAR_NOTIFY);
    
    // Register admin command to generate default config
    RegAdminCmd("sm_lpb_genconf", Command_GenerateConfig, ADMFLAG_CONFIG, "Generate a default LPB config file");
    
    // Hook events
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_team", Event_PlayerTeam);
    
    
    //LoadConfig(); // not needed if onmapstart
    
    // Hook convar changes
    g_cvConfigName.AddChangeHook(OnConfigChanged);
    
    AutoExecConfig(true, "lpb");
}

public void OnConfigChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    LoadConfig();
}

public void OnMapStart()
{
    // Load config on plugin or map start
    LoadConfig();
}

void LoadConfig()
{
    // Close previous config if exists
    if (g_kvConfig != null)
    {
        delete g_kvConfig;
    }
    
    // Get config name from convar
    char configName[64];
    g_cvConfigName.GetString(configName, sizeof(configName));
    
    // Build config path
    char configPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configPath, sizeof(configPath), "configs/%s.cfg", configName);
    
    // Load KeyValues
    g_kvConfig = new KeyValues(configName);
    
    if (!g_kvConfig.ImportFromFile(configPath))
    {
        LogError("Failed to load config file: %s", configPath);
        delete g_kvConfig;
        g_kvConfig = null;
        return;
    }
    
    LogMessage("Successfully loaded config: %s", configPath);
}

public void OnClientConnected(int client)
{
    // Don't count fake clients (bots)
    if (IsFakeClient(client))
        return;
    
    // Apply effects when client connects
    CreateTimer(0.5, Timer_ApplyEffectsAll, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
    // Don't count fake clients (bots)
    if (IsFakeClient(client))
        return;
    
    // Apply effects when client disconnects
    CreateTimer(0.1, Timer_ApplyEffectsAll, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    // Apply effects to all RED players when someone changes team
    CreateTimer(0.1, Timer_ApplyEffectsAll, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if (client > 0 && IsClientInGame(client) && GetClientTeam(client) == 2) // RED team
    {
        // Apply effects to this specific player with a small delay
        CreateTimer(0.1, Timer_ApplyEffectsSingle, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_ApplyEffectsAll(Handle timer)
{
    ApplyEffectsToAllRed();
    return Plugin_Stop;
}

public Action Timer_ApplyEffectsSingle(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client) && GetClientTeam(client) == 2)
    {
        ApplyEffectsToPlayer(client);
    }
    return Plugin_Stop;
}

void ApplyEffectsToAllRed()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2) // RED team, not bots
        {
            ApplyEffectsToPlayer(i);
        }
    }
}

void ApplyEffectsToPlayer(int client)
{
    if (!IsPlayerAlive(client))
        return;
    
    // Count RED team players
    int redCount = GetTeamPlayerCount(2);
    
    if (g_kvConfig == null)
    {
        LogError("Config not loaded, cannot apply effects");
        return;
    }
    
    // Clear all supported conditions first
    RemoveAllSupportedConditions(client);
    
    // Navigate to the player count section
    char countStr[8];
    IntToString(redCount, countStr, sizeof(countStr));
    
    if (!g_kvConfig.JumpToKey(countStr))
    {
        // No configuration for this player count
        g_kvConfig.Rewind();
        return;
    }
    
    // Iterate through all effects for this player count
    if (g_kvConfig.GotoFirstSubKey(false))
    {
        do
        {
            char effectName[64];
            g_kvConfig.GetSectionName(effectName, sizeof(effectName));
            int conditionId = g_kvConfig.GetNum(NULL_STRING);
            
            // Check if this is a condition-based effect
            if (StrContains(effectName, "mannpower_", false) == 0 || 
                StrContains(effectName, "cond_", false) == 0)
            {
                // Apply condition
                TF2_AddCondition(client, view_as<TFCond>(conditionId), TFCondDuration_Infinite);
                LogMessage("Applied condition %d (%s) to client %N", conditionId, effectName, client);
            }
            
        } while (g_kvConfig.GotoNextKey(false));
        
        g_kvConfig.GoBack();
    }
    
    // Return to root
    g_kvConfig.Rewind();
}

void RemoveAllSupportedConditions(int client)
{
    for (int i = 0; i < sizeof(g_iSupportedConditions); i++)
    {
        if (TF2_IsPlayerInCondition(client, view_as<TFCond>(g_iSupportedConditions[i])))
        {
            TF2_RemoveCondition(client, view_as<TFCond>(g_iSupportedConditions[i]));
        }
    }
}

int GetTeamPlayerCount(int team)
{
    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == team)
        {
            count++;
        }
    }
    return count;
}

public void OnPluginEnd()
{
    // Clean up
    if (g_kvConfig != null)
    {
        delete g_kvConfig;
    }
}

public Action Command_GenerateConfig(int client, int args)
{
    char configName[64];
    
    // Get config name from arguments or use default
    if (args > 0)
    {
        GetCmdArg(1, configName, sizeof(configName));
    }
    else
    {
        strcopy(configName, sizeof(configName), "LPB_default");
    }
    
    // Build config path
    char configPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configPath, sizeof(configPath), "configs/%s.cfg", configName);
    
    // Create the config file
    File file = OpenFile(configPath, "w");
    if (file == null)
    {
        ReplyToCommand(client, "[LPB] Failed to create config file: %s", configPath);
        return Plugin_Handled;
    }
    
    // Write header with all supported conditions
    file.WriteLine("// Low Player Balance Config");
    file.WriteLine("// Supported Conditions:");
    file.WriteLine("// 5   - mannpower_invulnerable       - TF_COND_INVULNERABLE");
    file.WriteLine("// 11  - cond_critboosted            - TF_COND_CRITBOOSTED");
    file.WriteLine("// 15  - cond_stunned                - TF_COND_STUNNED");
    file.WriteLine("// 16  - cond_offensebuff            - TF_COND_OFFENSEBUFF (Buff Banner)");
    file.WriteLine("// 19  - cond_energy_buff            - TF_COND_ENERGY_BUFF (Crit-a-Cola)");
    file.WriteLine("// 26  - cond_defensebuff            - TF_COND_DEFENSEBUFF (Battalion's Backup)");
    file.WriteLine("// 29  - cond_regenondamagebuff      - TF_COND_REGENONDAMAGEBUFF (Concheror)");
    file.WriteLine("// 32  - cond_speed_boost            - TF_COND_SPEED_BOOST");
    file.WriteLine("// 34  - cond_critboosted_user_buff  - TF_COND_CRITBOOSTED_USER_BUFF (Canteen Crit)");
    file.WriteLine("// 35  - cond_critboosted_demo       - TF_COND_CRITBOOSTED_DEMO_CHARGE");
    file.WriteLine("// 36  - cond_sodapopper_hype        - TF_COND_SODAPOPPER_HYPE");
    file.WriteLine("// 37  - cond_critboosted_firstblood - TF_COND_CRITBOOSTED_FIRST_BLOOD");
    file.WriteLine("// 38  - cond_critboosted_bonustime  - TF_COND_CRITBOOSTED_BONUS_TIME");
    file.WriteLine("// 39  - cond_critboosted_ctf        - TF_COND_CRITBOOSTED_CTF_CAPTURE");
    file.WriteLine("// 40  - cond_critboosted_onkill     - TF_COND_CRITBOOSTED_ON_KILL");
    file.WriteLine("// 42  - cond_defensebuff_nocrit     - TF_COND_DEFENSEBUFF_NO_CRIT_BLOCK");
    file.WriteLine("// 44  - cond_critboosted_rage       - TF_COND_CRITBOOSTED_RAGE_BUFF (Phlog)");
    file.WriteLine("// 45  - cond_defensebuff_high       - TF_COND_DEFENSEBUFF_HIGH (Phlog defense)");
    file.WriteLine("// 46  - cond_snipercharge_rage      - TF_COND_SNIPERCHARGE_RAGE_BUFF (Focus)");
    file.WriteLine("// 49  - cond_disguised_dispenser    - TF_COND_DISGUISED_AS_DISPENSER");
    file.WriteLine("// 51  - cond_invuln_hidden          - TF_COND_INVULNERABLE_HIDE_UNLESS_DAMAGED");
    file.WriteLine("// 52  - cond_invuln_user_buff       - TF_COND_INVULNERABLE_USER_BUFF (Canteen Uber)");
    file.WriteLine("// 55  - cond_radiusheal             - TF_COND_RADIUSHEAL_ON_DAMAGE");
    file.WriteLine("// 56  - cond_critboosted_card       - TF_COND_CRITBOOSTED_CARD_EFFECT");
    file.WriteLine("// 57  - cond_invuln_card            - TF_COND_INVULNERABLE_CARD_EFFECT");
    file.WriteLine("// 58  - cond_medigun_uber_bullet    - TF_COND_MEDIGUN_UBER_BULLET_RESIST");
    file.WriteLine("// 59  - cond_medigun_uber_blast     - TF_COND_MEDIGUN_UBER_BLAST_RESIST");
    file.WriteLine("// 60  - cond_medigun_uber_fire      - TF_COND_MEDIGUN_UBER_FIRE_RESIST");
    file.WriteLine("// 61  - cond_medigun_small_bullet   - TF_COND_MEDIGUN_SMALL_BULLET_RESIST");
    file.WriteLine("// 62  - cond_medigun_small_blast    - TF_COND_MEDIGUN_SMALL_BLAST_RESIST");
    file.WriteLine("// 63  - cond_medigun_small_fire     - TF_COND_MEDIGUN_SMALL_FIRE_RESIST");
    file.WriteLine("// 64  - cond_stealthed              - TF_COND_STEALTHED_USER_BUFF");
    file.WriteLine("// 66  - cond_stealthed_fading       - TF_COND_STEALTHED_USER_BUFF_FADING");
    file.WriteLine("// 67  - cond_bullet_immune          - TF_COND_BULLET_IMMUNE");
    file.WriteLine("// 68  - cond_blast_immune           - TF_COND_BLAST_IMMUNE");
    file.WriteLine("// 69  - cond_fire_immune            - TF_COND_FIRE_IMMUNE");
    file.WriteLine("// 70  - cond_prevent_death          - TF_COND_PREVENT_DEATH");
    file.WriteLine("// 72  - cond_halloween_speed        - TF_COND_HALLOWEEN_SPEED_BOOST");
    file.WriteLine("// 73  - cond_halloween_quickheal    - TF_COND_HALLOWEEN_QUICK_HEAL");
    file.WriteLine("// 74  - cond_halloween_giant        - TF_COND_HALLOWEEN_GIANT");
    file.WriteLine("// 75  - cond_halloween_tiny         - TF_COND_HALLOWEEN_TINY");
    file.WriteLine("// 79  - cond_obscured_smoke         - TF_COND_OBSCURED_SMOKE (75% dodge)");
    file.WriteLine("// 84  - cond_balloon_head           - TF_COND_BALLOON_HEAD");
    file.WriteLine("// 86  - cond_swimming_curse         - TF_COND_SWIMMING_CURSE");
    file.WriteLine("// 90  - mannpower_strength          - TF_COND_RUNE_STRENGTH");
    file.WriteLine("// 91  - mannpower_haste             - TF_COND_RUNE_HASTE");
    file.WriteLine("// 92  - mannpower_regen             - TF_COND_RUNE_REGEN");
    file.WriteLine("// 93  - mannpower_resist            - TF_COND_RUNE_RESIST");
    file.WriteLine("// 94  - mannpower_vampire           - TF_COND_RUNE_VAMPIRE");
    file.WriteLine("// 95  - mannpower_reflect           - TF_COND_RUNE_REFLECT");
    file.WriteLine("// 96  - mannpower_precision         - TF_COND_RUNE_PRECISION");
    file.WriteLine("// 97  - mannpower_agility           - TF_COND_RUNE_AGILITY");
    file.WriteLine("// 102 - cond_afterburn_immune       - TF_COND_AFTERBURN_IMMUNE");
    file.WriteLine("// 103 - mannpower_knockout          - TF_COND_RUNE_KNOCKOUT");
    file.WriteLine("// 104 - mannpower_imbalance         - TF_COND_RUNE_IMBALANCE");
    file.WriteLine("// 105 - cond_crit_temp              - TF_COND_CRITBOOSTED_RUNE_TEMP");
    file.WriteLine("// 107 - cond_swimming_noeffects     - TF_COND_SWIMMING_NO_EFFECTS");
    file.WriteLine("// 109 - mannpower_king              - TF_COND_RUNE_KING");
    file.WriteLine("// 110 - mannpower_plague            - TF_COND_RUNE_PLAGUE");
    file.WriteLine("// 111 - mannpower_supernova         - TF_COND_RUNE_SUPERNOVA");
    file.WriteLine("// 113 - mannpower_king_buffed       - TF_COND_KING_BUFFED");
    file.WriteLine("// 114 - cond_team_glows             - TF_COND_TEAM_GLOWS");
    file.WriteLine("// 129 - cond_dominant               - TF_COND_POWERUPMODE_DOMINANT");
    file.WriteLine("// 130 - cond_immune_pushback        - TF_COND_IMMUNE_TO_PUSHBACK");
    file.WriteLine("");
    file.WriteLine("// Format:");
    file.WriteLine("// \"ConfigName\"");
    file.WriteLine("// {");
    file.WriteLine("//     \"PlayerCount\"");
    file.WriteLine("//     {");
    file.WriteLine("//         \"condition_name\"    \"condition_id\"");
    file.WriteLine("//     }");
    file.WriteLine("// }");
    file.WriteLine("");
    
    // Write the actual config structure
    file.WriteLine("\"%s\"", configName);
    file.WriteLine("{");
    
    // Create sections for 1-6 players
    for (int i = 1; i <= 6; i++)
    {
        file.WriteLine("    \"%d\"  // %d player%s on RED team", i, i, i == 1 ? "" : "s");
        file.WriteLine("    {");
        file.WriteLine("        // Add conditions here");
        file.WriteLine("        // Example: \"mannpower_vampire\"    \"94\"");
        file.WriteLine("    }");
        if (i < 6)
        {
            file.WriteLine("");
        }
    }
    
    file.WriteLine("}");
    
    delete file;
    
    ReplyToCommand(client, "[LPB] Successfully generated config file: %s", configPath);
    LogMessage("Generated default config: %s", configPath);
    
    return Plugin_Handled;
}