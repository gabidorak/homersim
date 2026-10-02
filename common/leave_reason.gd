class_name LeaveReason
extends RefCounted
## Why a client is back at the main menu (M8): the server refused the join, kicked us, the
## connection failed or dropped, or the player left on purpose. Codes travel in on_join_rejected, so
## the server's rejections are shown in the player's language; log_text() is the English line for
## logs (the integration tests grep it).

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
	return "Left the server"


## The error box's title, in the player's language.
static func title(code: Code) -> String:
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
	return ""
