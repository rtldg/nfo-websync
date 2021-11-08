
#include <sourcemod>
#include <SteamWorks>
#include <convar_class>

public Plugin myinfo =
{
	name = "NFO Websync",
	author = "rtldg",
	description = "Provides a command to run the NFO websync.",
	version = "1.0.0",
	url = "https://github.com/rtldg/nfo-websync"
}

#define WEBSYNCURL "https://www.nfoservers.com/control/websync.pl"

Convar gCV_Email = null;
Convar gCV_Password = null;
Convar gCV_Cookietoken = null;
Convar gCV_ServerName = null;
Convar gCV_IPromiseThisAccountHasMinimalPermissions = null;

public void OnPluginStart()
{
	gCV_Email = new Convar("nfo_websync_email", "", "The email used by the account", FCVAR_PROTECTED);
	gCV_Password = new Convar("nfo_websync_password", "", "The password used by the account", FCVAR_PROTECTED);
	gCV_Cookietoken = new Convar("nfo_websync_cookietoken", "", "The cookietoken browser cookie", FCVAR_PROTECTED);
	gCV_ServerName = new Convar("nfo_websync_servername", "", "The servername", FCVAR_PROTECTED);
	gCV_IPromiseThisAccountHasMinimalPermissions = new Convar("nfo_websync_i_promise_this_account_has_min_perms", "0", "You promise that your account has minimal permissions set. Nothing given on the `websites` and only `websync` given on the game server.", FCVAR_PROTECTED, true, 0.0, true, 1.0);

	Convar.AutoExecConfig();

	RegAdminCmd("sm_websync", Command_Websync, ADMFLAG_RCON, "Runs the NFO websync");
}

void URLEncodeStringMostly(char[] s, int len)
{
	static char blahblah[][][] = {
		{"%",  "%25"},

		{" ",  "%20"},
		{"!",  "%21"},
		{"\"", "%22"},
		{"#",  "%23"},
		{"$",  "%24"},
		//
		{"&",  "%26"},
		{"'",  "%27"},
		{"(",  "%28"},
		{")",  "%29"},
		{"*",  "%2A"},
		{"+",  "%2B"},
		{",",  "%2C"},
		//
		{"/",  "%2F"},
		//
		{":",  "%3A"},
		{";",  "%3B"},
		{"<",  "%3C"},
		{"=",  "%3D"},
		{">",  "%3E"},
		{"?",  "%3F"},
		{"@",  "%40"},
		//
		{"[",  "%5B"},
		{"\\", "%5C"},
		{"]",  "%5D"},
		{"^",  "%5E"},
		//
		{"`",  "%60"},
	};

	for (int i = 0; i < sizeof(blahblah); i++)
	{
		ReplaceString(s, len, blahblah[i][0], blahblah[i][1]);
	}
}

public Action Command_Websync(int client, int args)
{
	if (!gCV_IPromiseThisAccountHasMinimalPermissions.BoolValue)
	{
		ReplyToCommand(client, "YOU DIDNT PROMISE");
		return Plugin_Handled;
	}

	char email[256];
	char password[256];
	char cookietoken[256];
	char servername[64];

	gCV_Email.GetString(email, sizeof(email));
	gCV_Password.GetString(password, sizeof(password));
	gCV_Cookietoken.GetString(cookietoken, sizeof(cookietoken));
	gCV_ServerName.GetString(servername, sizeof(servername));

	TrimString(email);
	TrimString(password);
	TrimString(cookietoken);
	TrimString(servername);

	if (!strlen(email))
	{
		ReplyToCommand(client, "EMAIL NOT SET");
		return Plugin_Handled;
	}

	if (!strlen(password))
	{
		ReplyToCommand(client, "PASSWORD NOT SET");
		return Plugin_Handled;
	}

	if (!strlen(cookietoken))
	{
		ReplyToCommand(client, "cookietoken NOT SET");
		return Plugin_Handled;
	}

	if (!strlen(servername))
	{
		ReplyToCommand(client, "SERVERNAME NOT SET");
		return Plugin_Handled;
	}

	URLEncodeStringMostly(email, sizeof(email));
	URLEncodeStringMostly(password, sizeof(password));

	char cookie[1024];
	FormatEx(cookie, sizeof(cookie),
		"email=%s; password=%s; logged_in=1; cookietoken=%s; name=%s; type=game",
		email, password, cookietoken, servername);

	char servernameurl[1024];
	FormatEx(servernameurl, sizeof(servernameurl), "%s.site.nfoservers.com", servername);

	DataPack pack = new DataPack();
	pack.WriteCell(client == 0 ? 0 : GetClientSerial(client));
	pack.WriteCell(GetCmdReplySource());

	Handle request;
	if (!(request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, WEBSYNCURL))
	  || !SteamWorks_SetHTTPRequestHeaderValue(request, "accept", "text/html")
	  || !SteamWorks_SetHTTPRequestContextValue(request, pack)
	  || !SteamWorks_SetHTTPRequestAbsoluteTimeoutMS(request, 4000)
	  || !SteamWorks_SetHTTPRequestHeaderValue(request, "Cookie", cookie)
	  || !SteamWorks_SetHTTPRequestGetOrPostParameter(request, "cookietoken", cookietoken)
	  || !SteamWorks_SetHTTPRequestGetOrPostParameter(request, "name", servername)
	  || !SteamWorks_SetHTTPRequestGetOrPostParameter(request, "typeofserver", "game")
	  || !SteamWorks_SetHTTPRequestGetOrPostParameter(request, "durl_addy", servernameurl)
	  || !SteamWorks_SetHTTPRequestGetOrPostParameter(request, "durl_auto", "1")
	  || !SteamWorks_SetHTTPRequestGetOrPostParameter(request, "durl_submit", "Sync Files")
	  || !SteamWorks_SetHTTPCallbacks(request, RequestCompletedCallback)
	  || !SteamWorks_SendHTTPRequest(request)
	)
	{
		delete pack;
		delete request;
		ReplyToCommand(client, "NFO Websync: failed to setup & send HTTP request");
		LogError("NFO Websync: failed to setup & send HTTP request");
		return Plugin_Handled;
	}

	ReplyToCommand(client, "NFO Websync: Request sent.");
	return Plugin_Handled;
}

public void RequestCompletedCallback(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, DataPack pack)
{
	pack.Reset();
	int client = GetClientFromSerial(pack.ReadCell());
	ReplySource src = pack.ReadCell();

	if (1 <= client <= MaxClients)
	{
		SetCmdReplySource(src);
	}

	ReplyToCommand(client, "bFailure = %d, bRequestSuccessful = %d, eStatusCode = %d", bFailure, bRequestSuccessful, eStatusCode);

	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		ReplyToCommand(client, "NFO Websync: request failed");
		LogError("NFO Websync: request failed");
		return;
	}

	ReplyToCommand(client, "NFO Websync: probably worked!");
}
