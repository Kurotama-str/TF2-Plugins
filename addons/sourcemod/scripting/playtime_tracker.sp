/*
Changelog:

Version 1.1:
- Added an in-game menu (sm_playtime_menu) for displaying player playtime.
- Improved database query efficiency.
- Enhanced plugin description and admin command documentation.

Version 1.0:
- Initial release.
- Tracks and stores players total playtime, SteamID, and nickname in an SQLite database.
- Provides the sm_playtime_check command to query individual player data.
*/


#include <sourcemod>

public Plugin myinfo = {
    name = "[AMD] Playtime Tracker",
    author = "Amodd, Kuro",
    description = "Tracks and stores players total playtime on the server in an SQLite",
    version = "1.2"
};

Handle g_hDB = null;
int g_JoinTime[MAXPLAYERS + 1];

public void OnPluginStart()
{
    InitDB();

    // Usage: sm_playtime_check <SteamID>
    // Description: Retrieves the total playtime and nickname of a player by SteamID and prints it to the admin's console.
    RegAdminCmd("sm_playtime_check", Command_PlaytimeCheck, ADMFLAG_GENERIC);

    // Usage: sm_playtime_menu
    // Description: Opens an in-game menu displaying players sorted by total playtime.
    RegAdminCmd("sm_playtime_menu", Command_PlaytimeMenu, ADMFLAG_GENERIC);

    // Usage sm_playtime_list
    // Description : List players by playtime in console, with argument n restricting to first n players.
    RegAdminCmd("sm_playtime_list", Command_PlaytimeList, ADMFLAG_GENERIC);

    // Usage sm_playtime_current
    // Description : List players by playtime in console, selecting only players currently in the server.
    RegAdminCmd("sm_playtime_current", Command_PlaytimeCurrent, ADMFLAG_GENERIC);
}

public void InitDB()
{
    char error[255];
    g_hDB = SQLite_UseDatabase("playtime_tracker", error, sizeof(error));

    if (g_hDB == null)
    {
        SetFailState("SQL error: %s", error);
    }

    SQL_LockDatabase(g_hDB);
    SQL_FastQuery(g_hDB, "VACUUM");
    SQL_FastQuery(g_hDB, "CREATE TABLE IF NOT EXISTS playtime_tracker (steamid TEXT PRIMARY KEY, nickname TEXT, total_playtime INTEGER); ");
    SQL_UnlockDatabase(g_hDB);
}

public void OnClientPostAdminCheck(int client)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    char steamId[32];
    GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId));

    char nickName[64];
    GetClientName(client, nickName, sizeof(nickName));

    g_JoinTime[client] = GetTime();
}

public void OnClientDisconnect(int client)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    char steamId[32];
    char nickName[64];
    if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId)))
    {
        LogError("Failed to retrieve SteamID for client %d. Skipping database entry.", client);
        return;
    }
    GetClientName(client, nickName, sizeof(nickName));

    int joinTime = g_JoinTime[client];
    int currentTime = GetTime();
    int playTime = currentTime - joinTime;

    UpdatePlayerData(steamId, nickName, playTime);
}

void UpdatePlayerData(const char[] steamId, const char[] nickName, int playTime)
{
    if (g_hDB == null)
    {
        LogError("Database handle is invalid.");
        return;
    }

    char query[512];
    Format(query, sizeof(query), "INSERT INTO playtime_tracker (steamid, nickname, total_playtime) VALUES ('%s', '%s', %d) ON CONFLICT(steamid) DO UPDATE SET nickname = '%s', total_playtime = total_playtime + %d;", steamId, nickName, playTime, nickName, playTime);

    SQL_LockDatabase(g_hDB);
    SQL_FastQuery(g_hDB, query);
    SQL_UnlockDatabase(g_hDB);
}

public Action Command_PlaytimeCheck(int client, int args)
{
    if (args != 1)
    {
        PrintToConsole(client, "Usage: sm_playtime_check <SteamID>");
        return Plugin_Handled;
    }

    char steamId[32];
    GetCmdArg(1, steamId, sizeof(steamId));

    if (g_hDB == null)
    {
        PrintToConsole(client, "Database handle is invalid.");
        return Plugin_Handled;
    }

    char query[256];
    Format(query, sizeof(query), "SELECT nickname, total_playtime FROM playtime_tracker WHERE steamid = '%s';", steamId);

    Handle hQuery = SQL_Query(g_hDB, query);

    if (hQuery == null)
    {
        PrintToConsole(client, "Error executing query: %s", g_hDB);
        return Plugin_Handled;
    }

    if (SQL_GetRowCount(hQuery) == 0)
    {
        PrintToConsole(client, "No data found for the provided SteamID.");
        return Plugin_Handled;
    }

    char nickName[64];
    int totalPlaytime;

    SQL_FetchRow(hQuery);
    SQL_FetchString(hQuery, 0, nickName, sizeof(nickName));
    totalPlaytime = SQL_FetchInt(hQuery, 1);

    int days = totalPlaytime / 86400;
    int hours = (totalPlaytime % 86400) / 3600;
    int minutes = (totalPlaytime % 3600) / 60;
    int seconds = totalPlaytime % 60;

    PrintToConsole(client, "SteamID: %s", steamId);
    PrintToConsole(client, "Nickname: %s", nickName);
    PrintToConsole(client, "Time Played: %d days, %d hours, %d minutes, %d seconds", days, hours, minutes, seconds);

    return Plugin_Handled;
}

public Action Command_PlaytimeList(int client, int args)
{
    if (g_hDB == null)
    {
        PrintToConsole(client, "[PlaytimeTracker] Database handle is invalid.");
        return Plugin_Handled;
    }

    int limit = -1;  // -1 means no limit
    if (args >= 1)
    {
        char arg[16];
        GetCmdArg(1, arg, sizeof(arg));
        limit = StringToInt(arg);

        if (limit <= 0)
        {
            PrintToConsole(client, "Invalid number. Usage: sm_playtime_list [topN]");
            return Plugin_Handled;
        }
    }

    Handle hQuery = SQL_Query(g_hDB, "SELECT steamid, nickname, total_playtime FROM playtime_tracker ORDER BY total_playtime DESC;");

    if (hQuery == null)
    {
        PrintToConsole(client,"[PlaytimeTracker] Error executing query.");
        return Plugin_Handled;
    }

    PrintToConsole(client, "=== [PlaytimeTracker] Player List (Time - Highest to Lowest) ===");

    int rank = 1;
    while (SQL_FetchRow(hQuery))
    {
        if (limit > 0 && rank > limit)
        {
            break;
        }

        char steamId[32], nickName[64];
        int totalPlaytime;

        SQL_FetchString(hQuery, 0, steamId, sizeof(steamId));
        SQL_FetchString(hQuery, 1, nickName, sizeof(nickName));
        totalPlaytime = SQL_FetchInt(hQuery, 2);

        int days = totalPlaytime / 86400;
        int hours = (totalPlaytime % 86400) / 3600;
        int minutes = (totalPlaytime % 3600) / 60;

        PrintToConsole(client,"#%d: %s (%s) - %d days, %d hours, %d minutes", rank, nickName, steamId, days, hours, minutes);
        rank++;
    }

    CloseHandle(hQuery);
    return Plugin_Handled;
}

public Action Command_PlaytimeCurrent(int client, int args)
{
    if (g_hDB == null)
    {
        PrintToConsole(client, "[PlaytimeTracker] Database handle is invalid.");
        return Plugin_Handled;
    }

    int connectedCount = 0;
    char steamIds[MAXPLAYERS + 1][32];
    char names[MAXPLAYERS + 1][64];
    int playtimes[MAXPLAYERS + 1];

    // Gather SteamIDs of connected human clients
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            GetClientAuthId(i, AuthId_Steam2, steamIds[connectedCount], sizeof(steamIds[]));
            GetClientName(i, names[connectedCount], sizeof(names[]));
            connectedCount++;
        }
    }

    if (connectedCount == 0)
    {
        PrintToConsole(client, "No human players currently connected.");
        return Plugin_Handled;
    }

    char query[512];
    Format(query, sizeof(query), "SELECT steamid, total_playtime FROM playtime_tracker WHERE steamid IN (");

    for (int i = 0; i < connectedCount; i++)
    {
        StrCat(query, sizeof(query), "'");
        StrCat(query, sizeof(query), steamIds[i]);
        StrCat(query, sizeof(query), "'");
        if (i < connectedCount - 1)
        {
            StrCat(query, sizeof(query), ", ");
        }
    }
    StrCat(query, sizeof(query), ");");

    Handle hQuery = SQL_Query(g_hDB, query);

    if (hQuery == null)
    {
        PrintToConsole(client, "[PlaytimeTracker] Error executing query.");
        return Plugin_Handled;
    }

    // Store results temporarily
    int found = 0;
    while (SQL_FetchRow(hQuery))
    {
        char sid[32];
        int time;
        SQL_FetchString(hQuery, 0, sid, sizeof(sid));
        time = SQL_FetchInt(hQuery, 1);

        for (int i = 0; i < connectedCount; i++)
        {
            if (StrEqual(sid, steamIds[i]))
            {
                playtimes[i] = time;
                found++;
                break;
            }
        }
    }

    CloseHandle(hQuery);

    // Simple selection sort for small data sets
    for (int i = 0; i < connectedCount - 1; i++)
    {
        for (int j = i + 1; j < connectedCount; j++)
        {
            if (playtimes[j] > playtimes[i])
            {
                SwapStrings(names[i], names[j], sizeof(names[]));
                SwapStrings(steamIds[i], steamIds[j], sizeof(steamIds[]));
                int temp = playtimes[i];
                playtimes[i] = playtimes[j];
                playtimes[j] = temp;
            }
        }
    }

    PrintToConsole(client, "=== [PlaytimeTracker] Joueurs connectés triés par temps de jeu ===");

    for (int i = 0; i < connectedCount; i++)
    {
        int days = playtimes[i] / 86400;
        int hours = (playtimes[i] % 86400) / 3600;
        int minutes = (playtimes[i] % 3600) / 60;

        PrintToConsole(client, "#%d: %s (%s) - %d days, %d hours, %d minutes", i + 1, names[i], steamIds[i], days, hours, minutes);
    }

    return Plugin_Handled;
}

stock void SwapStrings(char[] a, char[] b, int size)
{
    char tmp[64];
    strcopy(tmp, size, a);
    strcopy(a, size, b);
    strcopy(b, size, tmp);
}

public Action Command_PlaytimeMenu(int client, int args)
{
    if (g_hDB == null)
    {
        PrintToConsole(client, "Database handle is invalid.");
        return Plugin_Handled;
    }

    Handle hQuery = SQL_Query(g_hDB, "SELECT nickname, total_playtime FROM playtime_tracker ORDER BY total_playtime DESC;");

    if (hQuery == null)
    {
        PrintToConsole(client, "Error executing query.");
        return Plugin_Handled;
    }

    Menu menu = CreateMenu(MenuHandler_PlaytimeMenu);
    SetMenuTitle(menu, "Top Playtime List");
    SetMenuExitButton(menu, true);
    SetMenuPagination(menu, true);

    while (SQL_FetchRow(hQuery))
    {
        char nickName[64];
        int totalPlaytime;

        SQL_FetchString(hQuery, 0, nickName, sizeof(nickName));
        totalPlaytime = SQL_FetchInt(hQuery, 1);

        int days = totalPlaytime / 86400;
        int hours = (totalPlaytime % 86400) / 3600;
        int minutes = (totalPlaytime % 3600) / 60;

        char display[128];
        Format(display, sizeof(display), "%s - %d days, %d hours, %d minutes", nickName, days, hours, minutes);
        AddMenuItem(menu, nickName, display);
    }

    CloseHandle(hQuery);
    DisplayMenu(menu, client, 60);
    return Plugin_Handled;
}

public int MenuHandler_PlaytimeMenu(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        int client = param1;
        char info[64];
        GetMenuItem(menu, param2, info, sizeof(info));
        PrintToConsole(client, "You selected: %s", info);
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }

    return 0;
}

public void OnPluginUnload()
{
    if (g_hDB != null)
    {
        SQL_LockDatabase(g_hDB);
        SQL_FastQuery(g_hDB, "VACUUM");
        SQL_UnlockDatabase(g_hDB);

        delete g_hDB;
    }
}
