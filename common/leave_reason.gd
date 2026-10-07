class_name LeaveReason
extends RefCounted
## Why a client is back at the main menu (M8): the server refused the join, kicked us, the
## connection failed or dropped, or the player left on purpose. Codes travel in on_join_rejected, so
## the server's rejections are shown in the player's language; log_text() is the English line for
## logs (the integration tests grep it).
## A game hosted from a player's game (client/local_server.gd) adds two: the host left (the server
## closes for everyone), and the server this game started for "Play solo" / "Host a game" didn't
## start (detail: "port|<port>", "exit|<log file>", "timeout|<log file>" or "spawn").
## Online games add one more: the online server (the VPS launcher, client/online_client.gd) couldn't
## start the game or list them (detail: an OnlineApi.ERR_* code, "unreachable|<host>" with the host).
## New codes go at the end: they travel as numbers.

enum Code {
	NONE,  ## left on purpose: no message
	CANNOT_CONNECT,  ## the connection never came up, or the address didn't resolve
	TIMEOUT,  ## nothing answered within Net.CONNECT_TIMEOUT_S
	LOST,  ## connected, then the server went away
	VERSION,  ## detail: "<server version>|<our version>"
	FULL,
	PASSWORD_REQUIRED,  ## the client asks for the password and tries again
	WRONG_PASSWORD,
	LEVEL,  ## detail: "<server level>|<our level>" (debug builds: --level)
	KICKED,  ## detail: the server's reason
	BAD_ADDRESS,  ## the client couldn't parse what was typed
	HOST_LEFT,  ## the player hosting the game left, so the server closed
	SERVER_START,  ## our own server (solo, hosting) didn't start; detail: see above
	ONLINE,  ## the online server refused or didn't answer; detail: see above
}


## English, for logs: "Server full", "Version mismatch: server is 0.2.0, you have 0.1.0"…
static func log_text(code: Code, detail: String = "") -> String:
	var parts := detail.split("|")
	match code:
		Code.CANNOT_CONNECT:
			return "Could not reach the server" + (": " + detail if detail != "" else "")
		Code.TIMEOUT:
			return "Connection timed out"
		Code.LOST:
			return "Lost the connection to the server"
		Code.VERSION:
			return "Version mismatch: server is %s, you have %s" % [parts[0], parts[1] if parts.size() > 1 else "?"]
		Code.FULL:
			return "Server full"
		Code.PASSWORD_REQUIRED:
			return "Password required"
		Code.WRONG_PASSWORD:
			return "Wrong password"
		Code.LEVEL:
			return "The server plays another level (%s, you have %s)" % [parts[0], parts[1] if parts.size() > 1 else "?"]
		Code.KICKED:
			return "Kicked by the server" + (": " + detail if detail != "" else "")
		Code.BAD_ADDRESS:
			return "Invalid address: %s" % detail
		Code.HOST_LEFT:
			return "The host left"
		Code.SERVER_START:
			match parts[0]:
				"port":
					return "Could not start the server: UDP port %s is in use" % (parts[1] if parts.size() > 1 else "?")
				"exit":
					return "Could not start the server: it stopped (log: %s)" % (parts[1] if parts.size() > 1 else "?")
				"timeout":
					return "Could not start the server: it took too long (log: %s)" % (parts[1] if parts.size() > 1 else "?")
			return "Could not start the server"
		Code.ONLINE:
			match parts[0]:
				OnlineApi.ERR_UNREACHABLE:
					return "Online server: unreachable (%s)" % (parts[1] if parts.size() > 1 else "?")
				OnlineApi.ERR_KEY:
					return "Online server: wrong friends key"
				OnlineApi.ERR_FULL:
					return "Online server: full"
				OnlineApi.ERR_BUSY:
					return "Online server: busy"
				OnlineApi.ERR_START:
					return "Online server: the game didn't start"
			return "Online server: refused (%s)" % detail
	return "Left the server"


## The error box's title, in the player's language (`detail` matters for ONLINE).
static func title(code: Code, detail: String = "") -> String:
	match code:
		Code.CANNOT_CONNECT:
			return TranslationServer.translate("Can't connect")
		Code.TIMEOUT:
			return TranslationServer.translate("No answer")
		Code.LOST:
			return TranslationServer.translate("Connection lost")
		Code.VERSION:
			return TranslationServer.translate("Different version")
		Code.FULL:
			return TranslationServer.translate("Server full")
		Code.PASSWORD_REQUIRED, Code.WRONG_PASSWORD:
			return TranslationServer.translate("Wrong password")
		Code.LEVEL:
			return TranslationServer.translate("Different level")
		Code.KICKED:
			return TranslationServer.translate("Kicked")
		Code.BAD_ADDRESS:
			return TranslationServer.translate("Invalid address")
		Code.HOST_LEFT:
			return TranslationServer.translate("Game closed")
		Code.SERVER_START:
			return TranslationServer.translate("Can't start the game")
		Code.ONLINE:
			match detail.get_slice("|", 0):
				OnlineApi.ERR_UNREACHABLE:
					return TranslationServer.translate("Can't reach the online server")
				OnlineApi.ERR_KEY:
					return TranslationServer.translate("Wrong friends key")
				OnlineApi.ERR_FULL:
					return TranslationServer.translate("Online server full")
			return TranslationServer.translate("Can't start the game")
	return ""


## The error box's text, in the player's language: what happened and what to try.
static func message(code: Code, detail: String = "") -> String:
	var parts := detail.split("|")
	match code:
		Code.CANNOT_CONNECT:
			return TranslationServer.translate("The server could not be reached. Check the address and that the server is running.")
		Code.TIMEOUT:
			return TranslationServer.translate("The server didn't answer. It may be offline, or a firewall is blocking UDP port 7777.")
		Code.LOST:
			return TranslationServer.translate("The connection to the server dropped. The server may have stopped or restarted.")
		Code.VERSION:
			return TranslationServer.translate("The server runs version %s and you have %s. Both must run the same build: restart the game to update it.") \
				% [parts[0], parts[1] if parts.size() > 1 else "?"]
		Code.FULL:
			return TranslationServer.translate("Every slot on this server is taken. Try again in a moment.")
		Code.PASSWORD_REQUIRED, Code.WRONG_PASSWORD:
			return TranslationServer.translate("That password is not the right one for this server.")
		Code.LEVEL:
			return TranslationServer.translate("The server plays another level (%s, you have %s).") % [parts[0], parts[1] if parts.size() > 1 else "?"]
		Code.KICKED:
			return TranslationServer.translate("The server removed you from the game.") + \
				("\n" + TranslationServer.translate(detail) if detail != "" else "")
		Code.BAD_ADDRESS:
			return TranslationServer.translate("'%s' is not a server address. Type it like 192.168.1.20:7777 or myserver.net (the port defaults to 7777).") % detail
		Code.HOST_LEFT:
			return TranslationServer.translate("The player who hosted this game left, so the game is over.")
		Code.SERVER_START:
			var more := parts[1] if parts.size() > 1 else "?"
			match parts[0]:
				"port":
					return TranslationServer.translate("UDP port %s is already used on this computer, maybe by another server. Pick another port.") % more
				"exit":
					return TranslationServer.translate("The game's server stopped while starting. Its log is in %s") % more
				"timeout":
					return TranslationServer.translate("The game's server took too long to start. Its log is in %s") % more
			return TranslationServer.translate("The game could not start its server.")
		Code.ONLINE:
			match parts[0]:
				OnlineApi.ERR_UNREACHABLE:
					return TranslationServer.translate("The online server (%s) didn't answer. Check your internet connection, or try again in a moment: it may be restarting.") \
						% (parts[1] if parts.size() > 1 else "?")
				OnlineApi.ERR_KEY:
					return TranslationServer.translate("The online server refused your friends key. Ask the person who runs it for the right one, and type it in Join a game > Online.")
				OnlineApi.ERR_FULL:
					return TranslationServer.translate("The online server already runs as many games as it can. Join one of them, or try again once one ends.")
				OnlineApi.ERR_BUSY:
					return TranslationServer.translate("Many games were just started on the online server. Try again in a minute.")
				OnlineApi.ERR_START:
					return TranslationServer.translate("The online server could not start the game. Try again in a moment.")
			return TranslationServer.translate("The online server didn't understand the request. Restart the game to update it.")
	return ""
