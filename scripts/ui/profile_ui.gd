extends Node
## Account, Pilot pick, Hangar and Shop screens. game.gd creates this and calls setup() with
## the Settings screen to copy its look; each screen fills one shared panel in code.
## Hangar and Shop belong to one mode ("sp" or "mp"): each mode has its own credits,
## unlocks (by that mode's level) and loadout.

signal closed
## Launch! on the single-player pre-flight page: game.gd takes you to the launch pad.
signal launch_pressed

const Pilots := preload("res://scripts/ui/pilots.gd")
const ModIcon := preload("res://scripts/ui/mod_icon.gd")
const ModInfo := preload("res://scripts/game/mods.gd")
const Rocket := preload("res://scripts/game/rocket.gd")
const Cosmetics := preload("res://scripts/game/cosmetics.gd")

const GOLD := Color(1, 0.75, 0.35)
const SOFT := Color(0.8, 0.84, 0.92)
const DIM := Color(0.6, 0.64, 0.72)
const GOOD := Color(0.45, 1, 0.6)
const BAD := Color(1, 0.6, 0.45)

var screen: Control
## Full-screen layer for the Hangar (the other pages use the centred panel in `screen`).
var wide: Control
## The hangar backdrop (hangar_bg.gd): told where to stand the rocket in the Hangar.
var stage: Control
var box: VBoxContainer
var status: Label
var _page: String = ""
## Which mode's hangar/shop is open: "sp" or "mp".
var _track: String = "sp"
var _pick: String = ""
var _shop_tab: String = "ships"
var _user_edit: LineEdit
var _pass_edit: LineEdit
var _mail_edit: LineEdit
# Password reset / report state
var _reset_login := ""
var _reset_sent := false
var _report_cat := "bug"
var _busy := false
## Keep the scroll position when a page re-renders after a pick/purchase.
var _scroll_box: ScrollContainer
var _scroll_keep := 0


func setup(template: Control) -> void:
	screen = template.duplicate(0)
	screen.name = "ProfileScreens"
	screen.visible = false
	template.add_sibling(screen)
	box = screen.get_node("Panel/VBox")
	for child in box.get_children():
		box.remove_child(child)
		child.free()
	wide = Control.new()
	wide.name = "HangarScreen"
	wide.visible = false
	wide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_sibling(wide)
	wide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wide.resized.connect(func() -> void:
		if wide.visible:
			_render())  # landscape <-> portrait
	Profile.changed.connect(func() -> void:
		if is_open() and not _busy and _page in ["hangar", "shop", "pick", "fit"]:
			_render())


func open(page: String, track := "sp") -> void:
	_page = page
	_track = track
	_pick = Profile.character()
	_scroll_box = null
	screen.visible = page != "hangar"
	wide.visible = page == "hangar"
	if page != "hangar" and stage:
		stage.set_focus_x(-1.0)
	_render()


func is_open() -> bool:
	return screen.visible or wide.visible


## Hide without emitting closed (the game moves on to something else).
func hide_all() -> void:
	screen.visible = false
	wide.visible = false
	if stage:
		stage.set_focus_x(-1.0)


func close() -> void:
	hide_all()
	closed.emit()


func _render() -> void:
	_scroll_keep = _scroll_box.scroll_vertical if _scroll_box and is_instance_valid(_scroll_box) else 0
	_scroll_box = null
	# Hangar columns scroll on their own: keep each one's position across re-renders.
	var keep_cols: Array[int] = []
	for s in wide.find_children("*", "ScrollContainer", true, false):
		keep_cols.append((s as ScrollContainer).scroll_vertical)
	for parent in [box, wide]:
		for child in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
	status = null
	match _page:
		"account": _render_account()
		"signup": _render_signup()
		"hangar": _render_hangar()
		"fit": _render_fit()
		"shop": _render_shop()
		"pick": _render_pick()
		"forgot": _render_forgot()
		"email": _render_email()
		"password": _render_password()
		"delete": _render_delete()
		"report": _render_report()
	var cols := wide.find_children("*", "ScrollContainer", true, false)
	if cols.size() == keep_cols.size():
		for i in cols.size():
			var s := cols[i] as ScrollContainer
			var v := keep_cols[i]
			if v > 0:  # restore once laid out (the range is 0 until then)
				s.get_v_scroll_bar().changed.connect(func() -> void:
					if is_instance_valid(s):
						s.scroll_vertical = v, CONNECT_ONE_SHOT)


# --- Little builders -------------------------------------------------------------------

func _label(text: String, size: int, color: Color, parent: Control = null, center := true) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	# Wrapping labels inside a row get almost no width and wrap one letter per line
	# (text running down the screen), so only wrap in vertical lists.
	if not (parent is HBoxContainer):
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	(parent if parent else box).add_child(label)
	return label


func _button(text: String, on_press: Callable, parent: Control = null, width := 300) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(on_press)
	(parent if parent else box).add_child(b)
	return b


func _row(parent: Control = null, sep := 12) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", sep)
	(parent if parent else box).add_child(row)
	return row


## Scrolling area for long pages (keeps the panel on screen on small windows).
func _scroll(height: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, minf(height, screen.get_viewport_rect().size.y - 230.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_scroll_box = scroll
	var keep := _scroll_keep
	# Restore once the content has been laid out (the range is 0 until then).
	scroll.get_v_scroll_bar().changed.connect(func() -> void:
		if keep > 0 and is_instance_valid(scroll):
			scroll.scroll_vertical = keep, CONNECT_ONE_SHOT)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 10)
	scroll.add_child(inner)
	return inner


func _flow(parent: Control) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	parent.add_child(flow)
	return flow


## A selectable card: optional picture on top, name, small note.
func _card(parent: Control, title: String, note: String, picked: bool, locked: bool, on_press: Callable, art: Control = null) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(130, 118 if art else 64)
	b.toggle_mode = true
	b.button_pressed = picked
	b.disabled = locked
	b.pressed.connect(on_press)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 6
	v.offset_bottom = -6
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	if art:
		art.custom_minimum_size = Vector2(60, 60)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(art)
	# Selected cards are orange (theme), so their text goes dark for contrast.
	var t := _label(title, 15, Color("12152a") if picked else (DIM if locked else SOFT), v)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if note != "":
		var n := _label(note, 12, Color("12152a") if picked else DIM, v)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	parent.add_child(b)
	return b


func _swatch(design: Dictionary) -> Control:
	var c := Control.new()
	c.draw.connect(func() -> void:
		var r := minf(c.size.x, c.size.y) * 0.42
		var mid := c.size / 2.0
		c.draw_circle(mid, r, Color.html(str(design["body"])))
		c.draw_circle(mid, r * 0.7, Color.html(str(design["main"])))
		c.draw_circle(mid, r * 0.35, Color.html(str(design["dark"]))))
	return c


func _avatar(id: String) -> Control:
	var a := Pilots.new()
	a.pilot = id
	return a


func _mod_art(id: String) -> Control:
	var icon := ModIcon.new()
	icon.mod_id = id
	return icon


## Your rocket as it will fly (ship size, paint, pilot, fitted mods).
func _rocket_preview(parent: Control) -> void:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(150, 150)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(holder)
	var r := Rocket.new()
	r.active = false
	r.flame_on = true
	r.flame_power = 0.8
	r.monitoring = false
	r.monitorable = false
	var d := Profile.design(_track)
	r.paint_main = Color.html(str(d.get("main", "#db3333")))
	r.paint_dark = Color.html(str(d.get("dark", "#991a1f")))
	r.paint_body = Color.html(str(d.get("body", "#f2f5fa")))
	r.finish = str(Profile.loadout(_track).get("finish", "none"))
	r.mods.assign(Profile.loadout(_track)["mods"])
	r.missile_count = 5
	r.ship = str(Profile.loadout(_track)["ship"])
	r.scale = Vector2.ONE * 1.8 * float(Profile.ship(_track).get("size", 1.0))
	r.position = Vector2(75, 72)
	holder.add_child(r)
	r.set_process(false)  # just a picture: don't let it fly around
	r.set_process_unhandled_input(false)


func _set_status(text: String, color: Color) -> void:
	if status and is_instance_valid(status):
		status.text = text
		status.add_theme_color_override("font_color", color)


func _xp_bar(parent: Control, title: String, xp: int) -> void:
	var info := Profile.level_info(xp)
	var row := _row(parent)
	_label("%s  ·  Level %d" % [title, info["level"]], 17, GOLD, row)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(220, 18)
	bar.show_percentage = false
	bar.max_value = maxi(int(info["need"]), 1)
	bar.value = int(info["into"]) if int(info["need"]) > 0 else bar.max_value
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	_label("MAX" if int(info["need"]) == 0 else "%d / %d XP" % [info["into"], info["need"]], 14, SOFT, row)


# --- Account -----------------------------------------------------------------------------

## A labelled text field in a row. secret = password dots.
func _field(label: String, placeholder: String, secret := false, max_len := 64, parent: Control = null) -> LineEdit:
	var r := _row(parent)
	_label(label, 17, SOFT, r).custom_minimum_size.x = 150
	var e := LineEdit.new()
	e.secret = secret
	e.max_length = max_len
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size", 17)
	e.custom_minimum_size = Vector2(270, 40)
	r.add_child(e)
	return e


func _render_account() -> void:
	if Profile.is_account():
		_label("PILOT PROFILE", 40, GOLD)
		var top := _row()
		var av := _avatar(Profile.character())
		av.custom_minimum_size = Vector2(76, 108)  # pilot portrait
		top.add_child(av)
		var names := VBoxContainer.new()
		names.custom_minimum_size.x = 360  # give the name/email room (a column inside a row gets no width otherwise)
		top.add_child(names)
		_label(Profile.username, 28, Color("ffbf5a"), names, false)
		_label(Profile.email if Profile.email != "" else "No email set (needed to reset your password)", 14,
			DIM if Profile.email != "" else BAD, names, false)
		_xp_bar(box, "Single Player", int(Profile.data["sp"]["xp"]))
		_xp_bar(box, "Multiplayer", int(Profile.data["mp"]["xp"]))
		var st: Dictionary = Profile.data["stats"]
		_label("Single Player: %d cr · best %d · %d runs" % [Profile.credits("sp"), int(st["sp_best"]), int(st["sp_runs"])], 15, SOFT)
		_label("Multiplayer: %d cr · %d wins / %d races · best %d" % [Profile.credits("mp"), int(st["mp_wins"]),
			int(st["mp_races"]), int(st["mp_best"])], 15, SOFT)
		var r1 := _row()
		_button("Change Pilot", func() -> void: open("pick"), r1, 190)
		_button("Change Email", func() -> void: open("email"), r1, 190)
		_button("Change Password", func() -> void: open("password"), r1, 190)
		status = _label("", 15, SOFT)
		var r2 := _row()
		_button("Log Out", func() -> void:
			Profile.logout()
			_render(), r2, 190)
		_button("Back", close, r2, 190).grab_focus()
		return

	_label("PILOT LOGIN", 40, GOLD)
	_label("Sign up to save your progress online and race friends in Multiplayer." +
		("\nYour guest progress comes with you." if Profile.is_guest() else ""), 15, SOFT).custom_minimum_size.x = 440
	_user_edit = _field("Username / email", "", false, 120)
	_pass_edit = _field("Password", "", true, 128)
	_pass_edit.text_submitted.connect(func(_t: String) -> void: _do_login())
	var r3 := _row()
	_button("Log In", _do_login, r3, 150)
	_button("Sign Up", func() -> void: open("signup"), r3, 150)
	_button("Forgot password?", func() -> void:
		_reset_login = _user_edit.text.strip_edges()
		_reset_sent = false
		open("forgot"), r3, 190)
	status = _label("", 15, SOFT)
	_label("Guests can play Single Player only (progress saved on this device).", 13, DIM)
	if Profile.is_guest():
		_button("Back", close)
	else:
		_button("Play as Guest", func() -> void:
			Profile.start_guest()
			open("pick"))  # new guests choose their pilot first
	_user_edit.grab_focus()


func _do_login() -> void:
	if _busy:
		return
	var user := _user_edit.text.strip_edges()
	var password := _pass_edit.text
	if user == "" or password == "":
		_set_status("Enter your username or email and your password.", BAD)
		return
	_busy = true
	_set_status("Logging in…", Color(0.9, 0.85, 0.5))
	var err: String = await Profile.login(user, password)
	_busy = false
	_after_auth(err)


## Create an account: its own page with username, email and password (typed twice).
func _render_signup() -> void:
	_label("CREATE ACCOUNT", 38, GOLD)
	_label("Save your progress online and race friends in Multiplayer." +
		("\nYour guest progress comes with you." if Profile.is_guest() else ""), 15, SOFT).custom_minimum_size.x = 440
	_user_edit = _field("Username", "", false, 64)
	_mail_edit = _field("Email", "for password resets", false, 120)
	_pass_edit = _field("Password", "at least 8 characters", true, 128)
	var pw2 := _field("Repeat password", "", true, 128)
	pw2.text_submitted.connect(func(_t: String) -> void: _do_signup(pw2.text))
	status = _label("", 15, SOFT)
	var r := _row()
	_button("Create Account", func() -> void: _do_signup(pw2.text), r, 190)
	_button("Back", func() -> void: open("account"), r, 150)
	_user_edit.grab_focus()


func _do_signup(repeat: String) -> void:
	if _busy:
		return
	var user := _user_edit.text.strip_edges()
	var mail := _mail_edit.text.strip_edges()
	var password := _pass_edit.text
	if user == "" or password == "":
		_set_status("Choose a username and password.", BAD)
		return
	if mail == "":
		_set_status("Add an email so you can reset your password if you forget it.", BAD)
		return
	if password != repeat:
		_set_status("The passwords don't match.", BAD)
		return
	_busy = true
	_set_status("Creating account…", Color(0.9, 0.85, 0.5))
	var err: String = await Profile.signup(user, password, mail)
	_busy = false
	_after_auth(err)


func _after_auth(err: String) -> void:
	if not is_instance_valid(box):
		return
	if err != "":
		_set_status(err, BAD)
		return
	if Profile.needs_pilot_pick:
		open("pick")  # new account: choose your pilot before flying
	else:
		close()


## Forgotten password: 1) email me a code, 2) type the code + a new password.
func _render_forgot() -> void:
	_label("RESET PASSWORD", 38, GOLD)
	if not _reset_sent:
		_label("Enter your username or email. We'll email you a 6-digit code.", 16, SOFT)
		var who := _field("Username / email", "", false, 120)
		who.text = _reset_login
		status = _label("", 15, SOFT)
		var r := _row()
		_button("Send Code", func() -> void:
			if _busy or who.text.strip_edges() == "":
				return
			_busy = true
			_set_status("Sending…", Color(0.9, 0.85, 0.5))
			var err: String = await Profile.forgot_password(who.text.strip_edges())
			_busy = false
			if err != "":
				_set_status(err, BAD)
				return
			_reset_login = who.text.strip_edges()
			_reset_sent = true
			_render(), r, 190)
		_button("Back", func() -> void: open("account"), r, 150)
		who.grab_focus()
		return
	_label("If that account has an email, a code is on its way (it works for 15 minutes).\nCheck your spam folder too.", 15, SOFT)
	var code := _field("Code", "6 digits", false, 6)
	var pw := _field("New password", "at least 8 characters", true, 128)
	var pw2 := _field("Repeat password", "", true, 128)
	status = _label("", 15, SOFT)
	var r2 := _row()
	_button("Reset Password", func() -> void:
		if _busy:
			return
		if pw.text != pw2.text:
			_set_status("The passwords don't match.", BAD)
			return
		_busy = true
		_set_status("Resetting…", Color(0.9, 0.85, 0.5))
		var err: String = await Profile.reset_password(_reset_login, code.text.strip_edges(), pw.text)
		_busy = false
		if err != "":
			_set_status(err, BAD)
			return
		close(), r2, 190)
	_button("Send a New Code", func() -> void:
		_reset_sent = false
		_render(), r2, 190)
	_button("Back", func() -> void: open("account"), r2, 120)
	code.grab_focus()


func _render_email() -> void:
	_label("CHANGE EMAIL", 38, GOLD)
	_label("Current: " + (Profile.email if Profile.email != "" else "none"), 16, SOFT)
	var mail := _field("New email", "", false, 120)
	var pw := _field("Password", "to confirm it's you", true, 128)
	status = _label("", 15, SOFT)
	var r := _row()
	_button("Save Email", func() -> void:
		if _busy:
			return
		_busy = true
		var err: String = await Profile.change_email(pw.text, mail.text.strip_edges())
		_busy = false
		if err != "":
			_set_status(err, BAD)
			return
		open("account")
		_set_status("Email updated.", GOOD), r, 190)
	_button("Back", func() -> void: open("account"), r, 150)
	mail.grab_focus()


func _render_password() -> void:
	_label("CHANGE PASSWORD", 38, GOLD)
	_label("Other devices logged in to this account will be signed out.", 15, SOFT)
	var cur := _field("Current password", "", true, 128)
	var pw := _field("New password", "at least 8 characters", true, 128)
	var pw2 := _field("Repeat new", "", true, 128)
	status = _label("", 15, SOFT)
	var r := _row()
	_button("Save Password", func() -> void:
		if _busy:
			return
		if pw.text != pw2.text:
			_set_status("The new passwords don't match.", BAD)
			return
		_busy = true
		var err: String = await Profile.change_password(cur.text, pw.text)
		_busy = false
		if err != "":
			_set_status(err, BAD)
			return
		open("account")
		_set_status("Password changed.", GOOD), r, 190)
	_button("Back", func() -> void: open("account"), r, 150)
	cur.grab_focus()


## Opened from Settings. Needs the password; can't be undone.
func _render_delete() -> void:
	_label("DELETE ACCOUNT", 38, BAD)
	_label("This permanently deletes %s: both levels, credits, ships, mods, paint jobs and race stats.\nIt can't be undone." % Profile.username, 16, SOFT).custom_minimum_size.x = 460
	var pw := _field("Password", "to confirm", true, 128)
	var confirm := _field("Type DELETE", "", false, 6)
	status = _label("", 15, SOFT)
	var r := _row()
	var del := _button("Delete Forever", func() -> void:
		if _busy:
			return
		if confirm.text.strip_edges().to_upper() != "DELETE":
			_set_status("Type DELETE to confirm.", BAD)
			return
		_busy = true
		_set_status("Deleting…", Color(0.9, 0.85, 0.5))
		var err: String = await Profile.delete_account(pw.text)
		_busy = false
		if err != "":
			_set_status(err, BAD)
			return
		open("account")
		_set_status("Your account has been deleted.", GOOD), r, 190)
	del.add_theme_color_override("font_color", BAD)
	_button("Cancel", close, r, 150).grab_focus()


## Report a bug, a player, an idea... Stored on the server for the developer to read.
func _render_report() -> void:
	_label("REPORT A PROBLEM", 38, GOLD)
	var cats := _row(null, 8)
	for spec in [["bug", "Bug"], ["player", "Player"], ["suggestion", "Idea"], ["other", "Other"]]:
		var b := _button(spec[1], func() -> void:
			_report_cat = spec[0]
			_render(), cats, 120)
		b.toggle_mode = true
		b.button_pressed = _report_cat == spec[0]
	var hint: String = {
		"bug": "What happened, and what were you doing? (level, mode, screen…)",
		"player": "Which player, and what did they do?",
		"suggestion": "What would make the game better?",
		"other": "Tell us what's on your mind.",
	}[_report_cat]
	_label(hint, 15, SOFT)
	var target: LineEdit = null
	if _report_cat == "player":
		target = _field("Player name", "their username", false, 40)
	var msg := TextEdit.new()
	msg.custom_minimum_size = Vector2(520, 130)
	msg.add_theme_font_size_override("font_size", 16)
	msg.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	msg.placeholder_text = "Describe it here…"
	box.add_child(msg)
	status = _label("Sent as %s." % (Profile.username if Profile.is_account() else "a guest"), 13, DIM)
	var r := _row()
	_button("Send Report", func() -> void:
		if _busy:
			return
		if msg.text.strip_edges().length() < 5:
			_set_status("Please describe it in a few words.", BAD)
			return
		_busy = true
		_set_status("Sending…", Color(0.9, 0.85, 0.5))
		var err: String = await Profile.send_report(_report_cat, msg.text.strip_edges(),
			target.text.strip_edges() if target else "")
		_busy = false
		if err != "":
			_set_status(err, BAD)
			return
		msg.text = ""
		_set_status("Thanks! Your report was sent.", GOOD), r, 190)
	_button("Back", close, r, 150)
	msg.grab_focus()


# --- Hangar: full screen. Pilot | Ship type | your rocket (the backdrop) | Customization ---

## Full-screen layout over the hangar backdrop (the centred panel is hidden for this page).
## The middle column is left open: the backdrop's rocket stands there on its platform.
func _render_hangar() -> void:
	var view := screen.get_viewport_rect().size
	var portrait := view.y > view.x
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	wide.add_child(margin)
	var page := VBoxContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)
	_outlined(_label("%s HANGAR" % ("SINGLE PLAYER" if _track == "sp" else "MULTIPLAYER"), 32, GOLD, page))

	if portrait:
		# Phones: the backdrop puts the rocket on top; the three sections scroll below it.
		if stage:
			stage.set_focus_x(-1.0)
		var gap := Control.new()
		gap.custom_minimum_size.y = view.y * 0.3
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(gap)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page.add_child(scroll)
		_scroll_box = scroll
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 10)
		scroll.add_child(list)
		_fill_pilots(_column(list, 0.0), false)
		_fill_ships(_column(list, 0.0), false)
		_fill_custom(_column(list, 0.0), false)
		status = _label("", 15, SOFT, page)
		var b := _button("Back", close, page, 220)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.grab_focus()
		return

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_theme_constant_override("separation", 14)
	page.add_child(cols)
	_fill_pilots(_column(cols, 1.0), true)
	_fill_ships(_column(cols, 0.95), true)
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.size_flags_stretch_ratio = 1.8
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(middle)
	# Name of the build on top; the floor in front of the rocket is kept clear for decorations.
	var finish_name := str(Profile.finish(_track).get("name", ""))
	_outlined(_label("%s  ·  %s%s" % [str(Profile.ship(_track).get("name", "Ship")),
		str(Profile.design(_track).get("name", "")), "" if finish_name in ["", "Smooth"] else "  ·  " + finish_name],
		18, Color("ffbf5a"), middle))
	status = _label("", 15, SOFT, middle)
	_outlined(status)
	var air := Control.new()
	air.size_flags_vertical = Control.SIZE_EXPAND_FILL
	air.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(air)
	var back := _button("Back", close, middle, 220)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.grab_focus()
	_fill_custom(_column(cols, 1.0), true)
	if stage:
		middle.resized.connect(func() -> void:
			if is_instance_valid(middle) and is_instance_valid(stage):
				stage.set_focus_x(middle.get_global_rect().get_center().x - stage.get_global_rect().position.x))


func _outlined(label: Label) -> void:
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 8)


## One hangar section: a panel taking `ratio` of the width (0 = full width in portrait).
func _column(parent: Control, ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	if ratio > 0.0:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_stretch_ratio = ratio
		panel.custom_minimum_size.x = 190
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	return v


## Cards area of a section: a scrolling grid in landscape columns, a flow in portrait.
func _column_body(col: VBoxContainer, tall: bool, per_row: int) -> Container:
	if not tall:
		return _flow(col)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = per_row
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	return grid


func _fill_pilots(col: VBoxContainer, tall: bool) -> void:
	_label("PILOT", 20, GOLD, col)
	_label(Profile.character_name(Profile.character()), 15, SOFT, col)
	var body := _column_body(col, tall, 2)
	for c in Profile.characters():
		var id := str(c["id"])
		var b := _card(body, str(c["name"]), "", Profile.character() == id, false,
			func() -> void: Profile.set_character(id), _avatar(id))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(90, 146)
		(b.get_child(0).get_child(0) as Control).custom_minimum_size = Vector2(68, 98)  # portrait


func _fill_ships(col: VBoxContainer, tall: bool) -> void:
	_label("SHIP TYPE", 20, GOLD, col)
	_label(str(Profile.ship(_track).get("desc", "")), 13, SOFT, col)
	var body := _column_body(col, tall, 1)
	var lo := Profile.loadout(_track)
	for s in Profile.items("ships"):
		var id := str(s["id"])
		var owned := Profile.owns(_track, "ships", id)
		var note: String
		if owned:
			note = "%d mod slot%s\nAgility %s   Armour %s" % [s["slots"], "" if int(s["slots"]) == 1 else "s",
				_pips(float(s.get("agility", 1.0)), 0.8, 1.25), _pips(1.0 / float(s.get("damage", 1.0)), 1.0 / 1.3, 1.0 / 0.7)]
		else:
			note = "Locked · Shop · Lvl %d" % int(s["level"])
		var b := _card(body, str(s["name"]), note, lo["ship"] == id, not owned,
			func() -> void: Profile.set_loadout(_track, {"ship": id}))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(170, 84)


## A stat as 1-3 filled pips between lo and hi.
func _pips(v: float, lo: float, hi: float) -> String:
	var n := clampi(1 + roundi((v - lo) / maxf(hi - lo, 0.001) * 2.0), 1, 3)
	return "■".repeat(n) + "□".repeat(3 - n)


## Customization: paint, hull finish and hangar decorations, in one scrolling list.
func _fill_custom(col: VBoxContainer, tall: bool) -> void:
	_label("CUSTOMIZATION", 20, GOLD, col)
	var list: VBoxContainer = col
	if tall:
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		col.add_child(scroll)
		list = VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 8)
		scroll.add_child(list)
	var lo := Profile.loadout(_track)

	_label("Paint", 16, SOFT, list)
	var paints := _grid(list, tall)
	for d in Profile.items("designs"):
		var id := str(d["id"])
		var owned := Profile.owns(_track, "designs", id)
		var b := _card(paints, str(d["name"]), "" if owned else "Shop", lo["design"] == id, not owned,
			func() -> void: Profile.set_loadout(_track, {"design": id}), _swatch(d))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(90, 108)

	_label("Finish", 16, SOFT, list)
	var finishes := _grid(list, tall)
	for f in Profile.items("finishes"):
		var id := str(f["id"])
		var owned := Profile.owns(_track, "finishes", id)
		var b := _card(finishes, str(f["name"]), "" if owned else "Shop", str(lo.get("finish", "none")) == id, not owned,
			func() -> void: Profile.set_loadout(_track, {"finish": id}), _finish_art(id))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(90, 108)

	var placed: Array = lo.get("decor", [])
	_label("Hangar Decor  (%d / %d placed)" % [placed.size(), Profile.decor_slots()], 16, SOFT, list)
	var owned_decor: Array = Profile.track(_track)["owned"]["decor"]
	if owned_decor.is_empty():
		_label("Buy decorations in the Shop to place them around your rocket.", 13, DIM, list)
	var decor := _grid(list, tall)
	for d in Profile.items("decor"):
		var id := str(d["id"])
		if not owned_decor.has(id):
			continue
		var on := placed.has(id)
		var b := _card(decor, str(d["name"]), "Placed" if on else "", on, false, _toggle_decor.bind(id), _decor_art(id))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(90, 108)


## Cards grid inside a section: 2 per row in the Hangar column, a flow on phones.
func _grid(parent: Control, tall: bool) -> Container:
	if not tall:
		return _flow(parent)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	return grid


func _toggle_decor(id: String) -> void:
	var placed: Array = (Profile.loadout(_track).get("decor", []) as Array).duplicate()
	if placed.has(id):
		placed.erase(id)
	elif placed.size() >= Profile.decor_slots():
		_render()
		_set_status("All %d spots are taken. Remove a decoration first." % Profile.decor_slots(), BAD)
		return
	else:
		placed.append(id)
	Profile.set_loadout(_track, {"decor": placed})


## A square of the finish material (plain hull colour for "none", or if the art is missing).
func _finish_art(id: String) -> Control:
	var tex := Cosmetics.finish(id)
	if tex == null:
		var c := ColorRect.new()
		c.color = Color("c9d2d8")
		return c
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	return r


## The decoration's picture (a crate icon if the art is missing).
func _decor_art(id: String) -> Control:
	var tex := Cosmetics.decor(id)
	if tex == null:
		var c := Control.new()
		c.draw.connect(func() -> void:
			c.draw_rect(Rect2(c.size * 0.2, c.size * 0.6), Color("b0804a"))
			c.draw_rect(Rect2(c.size * 0.2, c.size * 0.6), Color("6b4a2a"), false, 2.0))
		return c
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return r


# --- Pre-flight: fit starting mods (opened by Launch, or Mods in a multiplayer room) ---------

func _render_fit() -> void:
	_label("PRE-FLIGHT CHECK", 36, GOLD)
	var lo := Profile.loadout(_track)
	var slots := int(Profile.ship(_track).get("slots", 1))
	_label("%s  ·  %d / %d mod slots fitted" % [str(Profile.ship(_track).get("name", "Ship")),
		(lo["mods"] as Array).size(), slots], 17, Color("ffbf5a"))
	_rocket_preview(box)
	var owned_mods: Array = Profile.track(_track)["owned"]["mods"]
	if owned_mods.is_empty():
		_label("No mods yet. Buy them in the Shop to start with them fitted.\n(Stations still offer random mods during a run.)", 14, DIM)
	else:
		_label("Choose the mods you start with:", 15, SOFT)
		var flow := _flow(box)
		flow.custom_minimum_size.x = 560
		for id in owned_mods:
			var fitted: bool = (lo["mods"] as Array).has(id)
			_card(flow, str(ModInfo.MODS[id]["name"]), "Fitted" if fitted else "", fitted, false,
				_toggle_mod.bind(str(id)), _mod_art(str(id)))
	status = _label("", 15, SOFT)
	var r := _row()
	var go: Button
	if _track == "sp":
		go = _button("Launch!", func() -> void:
			hide_all()
			launch_pressed.emit(), r, 220)
	else:
		go = _button("Done", close, r, 220)
	_button("Back", close, r, 150)
	go.grab_focus()


func _toggle_mod(id: String) -> void:
	var fitted: Array = (Profile.loadout(_track)["mods"] as Array).duplicate()
	if fitted.has(id):
		fitted.erase(id)
	elif fitted.size() >= int(Profile.ship(_track).get("slots", 1)):
		_render()
		_set_status("All slots are full. Remove a mod first, or get a bigger ship.", BAD)
		return
	else:
		fitted.append(id)
	Profile.set_loadout(_track, {"mods": fitted})


# --- Shop ----------------------------------------------------------------------------------

func _render_shop() -> void:
	var mode_name := "Single Player" if _track == "sp" else "Multiplayer"
	_label("%s SHOP" % mode_name.to_upper(), 34, GOLD)
	_label("Credits: %d   ·   %s level %d" % [Profile.credits(_track), mode_name, Profile.level(_track)], 18, Color("ffbf5a"))
	if not Profile.shop_open(_track):
		_label("This shop opens at %s level %d.\n%s" % [mode_name, int(Profile.catalog["shop_level"]),
			"Fly some runs to earn XP!" if _track == "sp" else "Race to earn Multiplayer XP!"], 17, SOFT)
		_button("Back", close).grab_focus()
		return
	var tabs := _row(null, 6)
	for t in [["ships", "Ships"], ["mods", "Mods"], ["designs", "Paint"], ["finishes", "Finish"], ["decor", "Decor"]]:
		var b := _button(t[1], func() -> void:
			_shop_tab = t[0]
			_scroll_box = null
			_render(), tabs, 108)
		b.toggle_mode = true
		b.button_pressed = _shop_tab == t[0]
	var inner := _scroll(400)
	for it in Profile.items(_shop_tab):
		_shop_row(inner, it)
	status = _label("", 15, SOFT)
	_button("Back", close).grab_focus()


func _shop_row(parent: Control, it: Dictionary) -> void:
	var id := str(it["id"])
	var row := _row(parent)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	var art: Control
	var title := str(it.get("name", id))
	var desc := str(it.get("desc", ""))
	match _shop_tab:
		"mods":
			art = _mod_art(id)
			title = str(ModInfo.MODS[id]["name"])
			desc = str(ModInfo.MODS[id]["desc"])
		"designs":
			art = _swatch(it)
		"finishes":
			art = _finish_art(id)
		"decor":
			art = _decor_art(id)
		_:
			art = Control.new()
			var slots := int(it.get("slots", 1))
			art.draw.connect(func() -> void:
				for i in slots:  # one square per mod slot
					art.draw_rect(Rect2(6 + i * 17, 20, 14, 14), Color("ffbf5a"), false, 2.0))
	art.custom_minimum_size = Vector2(56, 56)
	row.add_child(art)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	_label(title, 18, SOFT, text, false)
	if desc != "":
		_label(desc, 13, DIM, text, false).custom_minimum_size.x = 330
	var level := int(it.get("level", 1))
	var price := int(it.get("price", 0))
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 44)
	b.add_theme_font_size_override("font_size", 17)
	if Profile.owns(_track, _shop_tab, id):
		b.text = "Owned"
		b.disabled = true
	elif Profile.level(_track) < level:
		b.text = "Unlocks Lvl %d" % level
		b.disabled = true
	else:
		b.text = "Buy  %d cr" % price
		b.disabled = Profile.credits(_track) < price
		b.pressed.connect(_buy.bind(_shop_tab, id, title))
	row.add_child(b)


func _buy(kind: String, id: String, title: String) -> void:
	if _busy:
		return
	_busy = true
	var err: String = await Profile.buy(_track, kind, id)
	_busy = false
	if not is_instance_valid(box) or not screen.visible:
		return
	_render()
	if err != "":
		_set_status(err, BAD)
	else:
		var where: String = {"mods": "Fit it at your next pre-flight check.",
			"decor": "Place it in the Hangar (Customization)."}.get(kind, "Pick it in the Hangar.")
		_set_status("Bought %s! %s" % [title, where], GOOD)


# --- Choose your pilot (new players, or "Change Pilot") -------------------------------------

func _render_pick() -> void:
	_label("CHOOSE YOUR PILOT", 38, GOLD)
	_label("Who's flying? You can change this any time in the Hangar.", 16, SOFT)
	var flow := _flow(box)
	flow.custom_minimum_size.x = 640  # 5 pilots per row
	for c in Profile.characters():
		var id := str(c["id"])
		var b := _card(flow, str(c["name"]), "", _pick == id, false, func() -> void:
			_pick = id
			_render(), _avatar(id))
		b.custom_minimum_size = Vector2(118, 186)
		(b.get_child(0).get_child(0) as Control).custom_minimum_size = Vector2(90, 138)  # portrait
	var go := _button("Let's Fly as %s!" % Profile.character_name(_pick), func() -> void:
		Profile.needs_pilot_pick = false
		Profile.set_character(_pick)
		close())
	go.grab_focus()
