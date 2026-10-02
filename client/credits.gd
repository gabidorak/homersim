extends Control
## Credits (M8): CREDITS.md (exported with the client, see export_presets.cfg) turned into BBCode:
## headings, paragraphs, lists, and each table row as one line. Links open in the browser.

signal closed

const CREDITS := "res://CREDITS.md"

@onready var text: RichTextLabel = %Text


func _ready() -> void:
	(%BackButton as Button).pressed.connect(func() -> void: closed.emit())
	text.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
	var file := FileAccess.open(CREDITS, FileAccess.READ)
	var source := file.get_as_text() if file != null else ""
	var thanks := "[center][font_size=26][color=#ffc93c]%s[/color][/font_size][/center]\n\n" % tr("Thanks for playing!")
	text.text = thanks + (to_bbcode(source) if source != "" else tr("CREDITS.md is missing from this build."))
	text.grab_focus()
	Ui.play("ui_open")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		closed.emit()
		accept_event()


## A small Markdown subset → BBCode: # headings, **bold**, `code`, [text](url), bare URLs in tables,
## "- " lists, and tables (header row in bold; each row on one line, cells joined by " · ").
static func to_bbcode(markdown: String) -> String:
	var out: Array[String] = []
	var in_table := false
	for raw in markdown.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("|"):
			var cells := line.trim_prefix("|").trim_suffix("|").split("|")
			if cells.size() > 0 and cells[0].strip_edges().begins_with("---"):
				continue  # the |---| separator
			var parts: Array[String] = []
			for cell in cells:
				var c := cell.strip_edges()
				if c != "":
					parts.append(_inline(c, true))
			if parts.is_empty():
				continue
			if not in_table:
				out.append("[color=#a3a6ad]%s[/color]" % " · ".join(parts))
			else:
				out.append("[b]%s[/b] · %s" % [parts[0], " · ".join(parts.slice(1))])
			in_table = true
			continue
		in_table = false
		if line.begins_with("#"):
			var level := line.length() - line.lstrip("#").length()
			var size := 30 if level == 1 else 24
			out.append("\n[font_size=%d][color=#ffc93c]%s[/color][/font_size]" % [size, _inline(line.lstrip("# "), false)])
		elif line.begins_with("- "):
			out.append("  •  " + _inline(line.substr(2), false))
		else:
			out.append(_inline(line, false))
	return "\n".join(out)


static func _inline(s: String, link_urls: bool) -> String:
	var bold := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	var code := RegEx.create_from_string("`([^`]+)`")
	var link := RegEx.create_from_string("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	s = link.sub(s, "[url=$2]$1[/url]", true)
	s = bold.sub(s, "[b]$1[/b]", true)
	s = code.sub(s, "[code]$1[/code]", true)
	if link_urls and s.begins_with("http"):
		s = "[url=%s]%s[/url]" % [s, s.trim_prefix("https://")]
	return s
