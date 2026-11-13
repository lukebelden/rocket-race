extends Node
## Account, Hangar and Shop screens. game.gd creates this and calls setup() with the
## Settings screen to copy its look; each screen fills one shared panel in code.

signal closed

const Animals := preload("res://animals.gd")
const ModIcon := preload("res://mod_icon.gd")
const ModInfo := preload("res://mods.gd")
const Rocket := preload("res://rocket.gd")

const GOLD := Color(1, 0.75, 0.35)
const SOFT := Color(0.8, 0.84, 0.92)
const DIM := Color(0.6, 0.64, 0.72)
const GOOD := Color(0.45, 1, 0.6)
const BAD := Color(1, 0.6, 0.45)

var screen: Control
var box: VBoxContainer
var status: Label
var _page: String = ""
var _shop_tab: String = "ships"
var _user_edit: LineEdit
var _pass_edit: LineEdit
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
	Profile.changed.connect(func() -> void:
		if screen.visible and not _busy and _page != "account":
			_render())


func open(page: String) -> void:
	_page = page
	_scroll_box = null
	screen.visible = true
	_render()


func close() -> void:
	screen.visible = false
	closed.emit()


func _render() -> void:
	_scroll_keep = _scroll_box.scroll_vertical if _scroll_box and is_instance_valid(_scroll_box) else 0
	_scroll_box = null
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	status = null
	match _page:
		"account": _render_account()
		"hangar": _render_hangar()
		"shop": _render_shop()


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
	var t := _label(title, 15, GOLD if picked else (DIM if locked else SOFT), v)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if note != "":
		var n := _label(note, 12, GOOD if picked else DIM, v)
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
	var a := Animals.new()
	a.animal = id
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
	var d := Profile.design()
	r.paint_main = Color.html(str(d.get("main", "#db3333")))
	r.paint_dark = Color.html(str(d.get("dark", "#991a1f")))
	r.paint_body = Color.html(str(d.get("body", "#f2f5fa")))
	r.mods.assign(Profile.loadout()["mods"])
	r.missile_count = 5
	r.scale = Vector2.ONE * 1.8 * float(Profile.ship().get("size", 1.0))
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

func _render_account() -> void:
	if Profile.is_account():
		_label("PILOT PROFILE", 40, GOLD)
		var top := _row()
		var av := _avatar(Profile.character())
		av.custom_minimum_size = Vector2(70, 70)
		top.add_child(av)
		_label(Profile.username, 30, Color(0.55, 0.85, 1), top)
		_xp_bar(box, "Single Player", int(Profile.data["sp"]["xp"]))
		_xp_bar(box, "Multiplayer", int(Profile.data["mp"]["xp"]))
		var st: Dictionary = Profile.data["stats"]
		_label("Credits: %d   ·   Runs: %d   ·   Races: %d   ·   Wins: %d" % [Profile.credits(),
			int(st["sp_runs"]), int(st["mp_races"]), int(st["mp_wins"])], 16, SOFT)
		status = _label("", 15, SOFT)
		_button("Log Out", func() -> void:
			Profile.logout()
			_render())
		_button("Back", close).grab_focus()
		return

	_label("PILOT LOGIN", 40, GOLD)
	_label("Sign up to save your progress online and race friends in Multiplayer." +
		("\nYour guest progress comes with you." if Profile.is_guest() else ""), 15, SOFT).custom_minimum_size.x = 440
	var r1 := _row()
	_label("Username", 18, SOFT, r1).custom_minimum_size.x = 110
	_user_edit = LineEdit.new()
	_user_edit.max_length = 16
	_user_edit.add_theme_font_size_override("font_size", 18)
	_user_edit.custom_minimum_size = Vector2(240, 42)
	_user_edit.placeholder_text = "3-16 letters/numbers"
	r1.add_child(_user_edit)
	var r2 := _row()
	_label("Password", 18, SOFT, r2).custom_minimum_size.x = 110
	_pass_edit = LineEdit.new()
	_pass_edit.secret = true
	_pass_edit.add_theme_font_size_override("font_size", 18)
	_pass_edit.max_length = 128
	_pass_edit.custom_minimum_size = Vector2(240, 42)
	_pass_edit.placeholder_text = "at least 6 characters"
	_pass_edit.text_submitted.connect(func(_t: String) -> void: _do_login(false))
	r2.add_child(_pass_edit)
	var r3 := _row()
	_button("Log In", _do_login.bind(false), r3, 150)
	_button("Sign Up", _do_login.bind(true), r3, 150)
	status = _label("", 15, SOFT)
	_label("Guests can play Single Player only (progress saved on this device).", 13, DIM)
	if Profile.is_guest():
		_button("Back", close)
	else:
		_button("Play as Guest", func() -> void:
			Profile.start_guest()
			close())
	_user_edit.grab_focus()


func _do_login(is_signup: bool) -> void:
	if _busy:
		return
	var user := _user_edit.text.strip_edges()
	var password := _pass_edit.text
	if user == "" or password == "":
		_set_status("Enter a username and password.", BAD)
		return
	_busy = true
	_set_status("Signing up…" if is_signup else "Logging in…", Color(0.9, 0.85, 0.5))
	var err: String
	if is_signup:
		err = await Profile.signup(user, password)
	else:
		err = await Profile.login(user, password)
	_busy = false
	if not is_instance_valid(box):
		return
	if err != "":
		_set_status(err, BAD)
		return
	close()


# --- Hangar: pilot, ship, paint, fitted mods ---------------------------------------------

func _render_hangar() -> void:
	_label("HANGAR", 40, GOLD)
	var lo := Profile.loadout()
	var inner := _scroll(470)
	_rocket_preview(inner)

	_label("PILOT", 17, GOLD, inner)
	var pilots := _flow(inner)
	for c in Profile.items("characters"):
		var id := str(c["id"])
		_card(pilots, str(c["name"]), "", lo["character"] == id, false,
			func() -> void: Profile.set_loadout({"character": id}), _avatar(id))

	_label("SHIP", 17, GOLD, inner)
	var ships := _flow(inner)
	for s in Profile.items("ships"):
		var id := str(s["id"])
		var owned := Profile.owns("ships", id)
		var note := "%d slot%s" % [s["slots"], "" if int(s["slots"]) == 1 else "s"] if owned else "Shop · Lvl %d" % int(s["level"])
		_card(ships, str(s["name"]), note, lo["ship"] == id, not owned,
			func() -> void: Profile.set_loadout({"ship": id}))
	_label(str(Profile.ship().get("desc", "")), 14, SOFT, inner)

	_label("PAINT", 17, GOLD, inner)
	var paints := _flow(inner)
	for d in Profile.items("designs"):
		var id := str(d["id"])
		var owned := Profile.owns("designs", id)
		_card(paints, str(d["name"]), "" if owned else "Shop", lo["design"] == id, not owned,
			func() -> void: Profile.set_loadout({"design": id}), _swatch(d))

	var slots := int(Profile.ship().get("slots", 1))
	_label("STARTING MODS  (%d / %d slots)" % [(lo["mods"] as Array).size(), slots], 17, GOLD, inner)
	var owned_mods: Array = Profile.data["owned"]["mods"]
	if owned_mods.is_empty():
		_label("Buy mods in the Shop to start every run with them fitted.\n(Stations still offer random mods during a run.)", 14, DIM, inner)
	else:
		var flow := _flow(inner)
		for id in owned_mods:
			var fitted: bool = (lo["mods"] as Array).has(id)
			_card(flow, str(ModInfo.MODS[id]["name"]), "Fitted" if fitted else "", fitted, false,
				_toggle_mod.bind(str(id)), _mod_art(str(id)))
	status = _label("", 15, SOFT)
	_button("Back", close).grab_focus()


func _toggle_mod(id: String) -> void:
	var fitted: Array = (Profile.loadout()["mods"] as Array).duplicate()
	if fitted.has(id):
		fitted.erase(id)
	elif fitted.size() >= int(Profile.ship().get("slots", 1)):
		_render()
		_set_status("All slots are full. Remove a mod first, or get a bigger ship.", BAD)
		return
	else:
		fitted.append(id)
	Profile.set_loadout({"mods": fitted})


# --- Shop ----------------------------------------------------------------------------------

func _render_shop() -> void:
	_label("SHOP", 40, GOLD)
	_label("Credits: %d   ·   Pilot level %d" % [Profile.credits(), Profile.pilot_level()], 18, Color(0.55, 0.85, 1))
	if not Profile.shop_open():
		_label("The shop opens at level %d.\nFly some runs to earn XP!" % int(Profile.catalog["shop_level"]), 17, SOFT)
		_button("Back", close).grab_focus()
		return
	var tabs := _row()
	for t in [["ships", "Ships"], ["mods", "Mods"], ["designs", "Paint"]]:
		var b := _button(t[1], func() -> void:
			_shop_tab = t[0]
			_scroll_box = null
			_render(), tabs, 130)
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
		_:
			art = Control.new()
			var slots := int(it.get("slots", 1))
			art.draw.connect(func() -> void:
				for i in slots:  # one square per mod slot
					art.draw_rect(Rect2(6 + i * 17, 20, 14, 14), Color(0.55, 0.85, 1), false, 2.0))
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
	if Profile.owns(_shop_tab, id):
		b.text = "Owned"
		b.disabled = true
	elif Profile.pilot_level() < level:
		b.text = "Unlocks Lvl %d" % level
		b.disabled = true
	else:
		b.text = "Buy  %d cr" % price
		b.disabled = Profile.credits() < price
		b.pressed.connect(_buy.bind(_shop_tab, id, title))
	row.add_child(b)


func _buy(kind: String, id: String, title: String) -> void:
	if _busy:
		return
	_busy = true
	var err: String = await Profile.buy(kind, id)
	_busy = false
	if not is_instance_valid(box) or not screen.visible:
		return
	_render()
	if err != "":
		_set_status(err, BAD)
	else:
		_set_status("Bought %s! Fit it in the Hangar." % title, GOOD)
