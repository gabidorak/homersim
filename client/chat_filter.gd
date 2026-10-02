class_name ChatFilter
extends RefCounted
## The chat's rude-word filter (M8, Settings → Gameplay, on by default): whole words from WORDS
## (English and French) become their first letter plus asterisks. Client side only: it changes what
## this player reads, not what others typed. Words with spaces or game meanings ("bite" is French
## for something rude, and also what rats do) are left out on purpose.

const WORDS: Array[String] = [
	"fuck", "fucks", "fucked", "fucking", "fucker", "motherfucker", "shit", "shitty", "bullshit", "bitch",
	"bitches", "bastard", "asshole", "arsehole", "dick", "dickhead", "cunt", "whore", "slut", "wanker", "twat",
	"prick", "retard", "retarded", "faggot", "fag", "nigger", "nigga",
	"merde", "putain", "connard", "connards", "connasse", "salope", "salopes", "enculé", "enculés", "encule",
	"enculer", "pute", "putes", "couille", "couilles", "nique", "niquer", "ntm", "fdp", "batard", "bâtard",
	"pd", "tg", "con", "cons", "conne",
]

static var _regex: RegEx


static func clean(text: String) -> String:
	if _regex == null:
		_regex = RegEx.create_from_string("(*UCP)(?i)\\b(%s)\\b" % "|".join(WORDS))
	var out := text
	var matches := _regex.search_all(text)
	matches.reverse()  # from the end, so earlier offsets stay valid
	for m in matches:
		var word := m.get_string()
		out = out.substr(0, m.get_start()) + word.substr(0, 1) + "*".repeat(word.length() - 1) + out.substr(m.get_end())
	return out
