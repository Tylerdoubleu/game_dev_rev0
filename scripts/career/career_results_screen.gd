extends Control
## v0.7 solo career (Bluey): the post-match card. Same tournament look as Ren's CareerScreen (TournamentSkin,
## CareerScreen.Stars). Shows the three star lines (lit / NEW), the match numbers, the clout this match earned and
## whether the career is synced to the profile server or saved on this device for later.
##   show_outcome(challenge, result, outcome)   set_sync(text, ok)   set_clout_total(n)
## Buttons: RETRY -> retry_pressed, CAREER -> career_pressed.

signal retry_pressed
signal career_pressed

var title_label: Label
var sub_label: Label
var stats_label: Label
var clout_label: Label
var total_label: Label
var sync_label: Label
var star_rows: Array = [] # [{"row", "stars", "text", "new"}]
var retry_btn: Button
var career_btn: Button
var _built := false

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	name = "CareerResults"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var board := PanelContainer.new()
	board.name = "Board"
	board.custom_minimum_size = Vector2(760, 0)
	board.add_theme_stylebox_override("panel", TournamentSkin.board_style())
	center.add_child(board)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	board.add_child(col)
	title_label = TournamentSkin.label("CHALLENGE COMPLETE", 44, TournamentSkin.NEON, TournamentSkin.STENCIL, 8)
	title_label.name = "Title"
	col.add_child(title_label)
	sub_label = TournamentSkin.label("", 22, TournamentSkin.AMBER, TournamentSkin.STENCIL, 3)
	sub_label.name = "Challenge"
	col.add_child(sub_label)
	for i in 3:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", TournamentSkin.card(Color(0.2, 0.21, 0.19), 14, 6))
		col.add_child(p)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		p.add_child(row)
		var st := CareerScreen.Stars.new(1, 0, 30.0)
		st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(st)
		var t := TournamentSkin.label("", 20, TournamentSkin.CHALK, TournamentSkin.STENCIL, 2)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		var nw := TournamentSkin.marker("NEW!", 22, TournamentSkin.PINK)
		nw.visible = false
		row.add_child(nw)
		star_rows.append({"panel": p, "stars": st, "text": t, "new": nw})
	stats_label = TournamentSkin.led("", 20, TournamentSkin.CHALK)
	stats_label.name = "Stats"
	col.add_child(stats_label)
	var clout_row := HBoxContainer.new()
	col.add_child(clout_row)
	clout_label = TournamentSkin.label("", 26, TournamentSkin.NEON, TournamentSkin.STENCIL, 4)
	clout_label.name = "CloutGain"
	clout_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clout_row.add_child(clout_label)
	total_label = TournamentSkin.led("", 22, TournamentSkin.AMBER)
	total_label.name = "CloutTotal"
	clout_row.add_child(total_label)
	sync_label = TournamentSkin.led("", 16, TournamentSkin.MUTED)
	sync_label.name = "Sync"
	col.add_child(sync_label)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)
	career_btn = TournamentSkin.style_button(Button.new(), Color(0.55, 0.56, 0.52), 22)
	career_btn.name = "CareerButton"
	career_btn.text = "CAREER"
	career_btn.custom_minimum_size = Vector2(200, 54)
	career_btn.pressed.connect(func() -> void: career_pressed.emit())
	footer.add_child(career_btn)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(gap)
	retry_btn = TournamentSkin.style_button(Button.new(), TournamentSkin.NEON, 24)
	retry_btn.name = "RetryButton"
	retry_btn.text = "RETRY"
	retry_btn.custom_minimum_size = Vector2(220, 54)
	retry_btn.pressed.connect(func() -> void: retry_pressed.emit())
	footer.add_child(retry_btn)

func show_outcome(c: Dictionary, r: Dictionary, outcome: Dictionary) -> void:
	_build()
	var ev: Dictionary = outcome.get("eval", {})
	var won := bool(ev.get("won", false))
	title_label.text = "CHALLENGE COMPLETE" if won else "NOT THIS TIME"
	title_label.add_theme_color_override("font_color", TournamentSkin.NEON if won else TournamentSkin.PINK)
	sub_label.text = "%s  //  %s" % [String(c.get("name", "")).to_upper(), String(c.get("mode", "")).to_upper()]
	var lit: Array = ev.get("stars", [false, false, false])
	var fresh: Array = outcome.get("new_stars", [])
	var texts: Array = c.get("stars", ["", "", ""])
	for i in 3:
		var row: Dictionary = star_rows[i]
		var on := i < lit.size() and bool(lit[i])
		(row["stars"] as Control).set("filled", 1 if on else 0)
		(row["stars"] as Control).queue_redraw()
		(row["text"] as Label).text = String(texts[i]) if i < texts.size() else ""
		(row["text"] as Label).add_theme_color_override("font_color", TournamentSkin.CHALK if on else TournamentSkin.MUTED)
		(row["new"] as Label).visible = (i + 1) in fresh
	stats_label.text = stats_line(c, r)
	var clout := int(outcome.get("clout", 0))
	clout_label.text = ("+%s CLOUT" % CareerScreen.fmt(clout)) if clout > 0 else "NO CLOUT THIS TIME"
	if String(outcome.get("tier_cleared", "")) != "":
		clout_label.text += "   TIER CLEARED!"

static func stats_line(c: Dictionary, r: Dictionary) -> String:
	match String(c.get("kind", "")):
		"gauntlet":
			return "POPS %d   TIME %.1fs   SPLATS %d" % [int(r.get("pops", 0)), float(r.get("time_s", 0.0)), int(r.get("deaths", 0))]
		"elimination":
			return "ROUNDS %d-%d   ELIMS %d   SPLATS %d" % [int(r.get("rounds_won", 0)), int(r.get("rounds_lost", 0)), int(r.get("kills", 0)), int(r.get("deaths", 0))]
		_:
			var s := "YOU %d - %d BOTS   ELIMS %d   SPLATS %d   STYLE %d" % [int(r.get("team_you", r.get("kills", 0))), int(r.get("team_bots", r.get("deaths", 0))),
				int(r.get("kills", 0)), int(r.get("deaths", 0)), int(r.get("style_kills", 0))]
			if c.has("zone"):
				s += "   FROM THE %s %d" % [String(c["zone"].get("name", "ZONE")), int(r.get("zone_kills", 0))]
			return s

func set_clout_total(n: int) -> void:
	_build()
	total_label.text = "CLOUT %s" % CareerScreen.fmt(n)

func set_sync(text: String, ok: bool = true) -> void:
	_build()
	sync_label.text = text
	sync_label.add_theme_color_override("font_color", TournamentSkin.MUTED if ok else TournamentSkin.AMBER)
