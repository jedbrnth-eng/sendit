# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name CarSelect extends CanvasLayer
## The garage, shown between the title and the run: a lit turntable preview in its own 3D world and
## five tabs. CAR picks the vehicle (name, tagline, stat bars from the real handling numbers, lock
## state); PAINT / WHEELS / LIGHTS / EXTRAS customise it with a live preview of the hovered item.
## Keys: Q/E (or LB/RB) tab, W/S or arrows row, A/D or arrows item, Enter (A) buy/equip or drive on
## the CAR tab, Space (X) drive from any tab, Esc (B) back. Loadouts are per car (Profile, saved to
## user://profile.cfg); the car pick is saved to user://garage.cfg and kept in CarCatalog.chosen.

signal chosen(id: String)
signal cancelled

const DISPLAY := "res://assets/fonts/RussoOne-Regular.ttf"
const BODY := "res://assets/fonts/ChakraPetch-Bold.ttf"
const SEMI := "res://assets/fonts/ChakraPetch-SemiBold.ttf"
const LIME := Color(0.55, 1.0, 0.2)
const PINK := Color(1.0, 0.24, 0.52)
const GOLD := Color(1.0, 0.82, 0.35)
const TAB_NAMES := ["CAR", "PAINT", "WHEELS", "LIGHTS", "EXTRAS"]
const PLATE_ROW := "plate_text"

var index := 0               # car index (CAR tab)
var tab := 0
var row := 0
var profile: Profile
var _ids: Array[String] = []
var _cursor := {}            # slot -> index into UnlockCatalog.items(slot) (the hovered item)
var _plate_i := 0            # index into PlateText.PRESETS (+1 = CUSTOM)
var _vp: SubViewport
var _turntable: Node3D
var _car: CarBody
var _ui: Control
var _car_page: Control
var _rows_page: Control
var _tabs: Array[Label] = []
var _tab_bg: Array[Panel] = []
var _name: Label
var _tag: Label
var _lock: Label
var _count: Label
var _small_name: Label
var _wallet: Label
var _level: Label
var _toast: Label
var _hint: Label
var _row_nodes: Array = []   # [{panel, caption, value, status, swatch, count}]
var _edit: LineEdit
var _bars := {}
var _bar_vals := {}
var _t := 0.0
var _spin := 0.0
var _swap_kick := 0.0
var _done := false
var _display: Font
var _body: Font
var _semi: Font


## Wrap-around step through `n` entries (pure, tested).
static func step(i: int, dir: int, n: int) -> int:
	return posmod(i + dir, n)


## What a garage row shows for `id` on `car` (pure, tested): {text, kind}
## kind: "equipped" | "owned" | "buy" | "poor" | "locked".
static func status(p: Profile, car: String, id: String) -> Dictionary:
	var it := UnlockCatalog.get_item(id)
	if it.is_empty():
		return {"text": "", "kind": "locked"}
	if it.slot == "car":
		if p.owns(id):
			return {"text": "UNLOCKED", "kind": "equipped"}
		return {"text": "LOCKED · REACH LVL %d" % int(it.level), "kind": "locked"}
	if p.owns(id):
		if p.loadout(car).get(it.slot, "") == id:
			return {"text": "EQUIPPED", "kind": "equipped"}
		return {"text": "OWNED · ENTER TO EQUIP", "kind": "owned"}
	if p.level() < int(it.level):
		return {"text": "LOCKED · " + UnlockCatalog.requirement_text(it), "kind": "locked"}
	if p.credits < int(it.price):
		return {"text": "NEED %s CR" % UnlockCatalog._fmt(int(it.price)), "kind": "poor"}
	return {"text": "BUY · %s CR" % UnlockCatalog._fmt(int(it.price)), "kind": "buy"}


## Enter on a garage row (pure, tested): buy if needed, then equip. Returns a toast line.
static func activate(p: Profile, car: String, id: String) -> String:
	var it := UnlockCatalog.get_item(id)
	if it.is_empty() or it.slot == "car":
		return ""
	var bought := false
	if not p.owns(id):
		match p.buy(id):
			Profile.LOCKED:
				return "LOCKED · REACH LEVEL %d" % int(it.level)
			Profile.NO_CREDITS:
				return "NOT ENOUGH CREDITS · NEED %s MORE" % UnlockCatalog._fmt(int(it.price) - p.credits)
			Profile.OK_BOUGHT:
				bought = true
			_:
				return ""
	p.equip(car, id)
	if bought:
		return "BOUGHT %s  −%s CR" % [String(it.name).to_upper(), UnlockCatalog._fmt(int(it.price))]
	return "EQUIPPED %s" % String(it.name).to_upper()


func _ready() -> void:
	layer = 6
	profile = ProfileStore.get_current()
	_ids = CarCatalog.ids()
	index = CarCatalog.index_of(CarCatalog.current_id())
	_build_stage()
	_build_ui()
	_show(index, false)
	if LaunchArgs.has("garage-tab"):  # proof shots: --garage-tab=PAINT --garage-row=1 --garage-step=3
		_set_tab(maxi(0, TAB_NAMES.find(String(LaunchArgs.get_value("garage-tab")))))
		_set_row(int(LaunchArgs.get_value("garage-row", "0")))
		for i in int(LaunchArgs.get_value("garage-step", "0")):
			_cycle(1)


# --- 3D stage --------------------------------------------------------------------------------

func _build_stage() -> void:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	holder.add_child(_vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.018, 0.012, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.33, 0.45)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.ssr_enabled = true
	env.fog_enabled = true  # melt the floor's far edge into the backdrop
	env.fog_light_color = Color(0.018, 0.012, 0.035)
	env.fog_density = 0.045
	env.fog_sky_affect = 0.0
	var sky := Sky.new()  # reflections on the paint: a dim procedural studio sky
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.25, 0.2, 0.4)
	psm.sky_horizon_color = Color(0.5, 0.35, 0.6)
	psm.ground_bottom_color = Color(0.02, 0.02, 0.03)
	psm.ground_horizon_color = Color(0.3, 0.2, 0.35)
	sky.sky_material = psm
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	# Glossy floor + a neon ring under the turntable.
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.03, 0.03, 0.04)
	fm.roughness = 0.4
	fm.metallic = 0.3
	floor_mi.material_override = fm
	_vp.add_child(floor_mi)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.35
	tm.outer_radius = 3.42
	tm.rings = 96
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = PINK * 2.2
	ring.material_override = rm
	ring.position.y = 0.01
	_vp.add_child(ring)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.3
	cm.bottom_radius = 3.3
	cm.height = 0.04
	cm.radial_segments = 96
	disc.mesh = cm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.06, 0.06, 0.075)
	dm.roughness = 0.3
	dm.metallic = 0.5
	disc.material_override = dm
	disc.position.y = -0.0
	_vp.add_child(disc)

	_turntable = Node3D.new()
	_turntable.position.y = 0.02
	_vp.add_child(_turntable)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.4
	key.rotation_degrees = Vector3(-48, 35, 0)
	key.shadow_enabled = true
	_vp.add_child(key)
	for spec in [[Vector3(-5, 3.2, -1), Color(1.0, 0.25, 0.6), 5.0], [Vector3(4, 3.5, -4.5), Color(0.3, 0.75, 1.0), 5.0],
			[Vector3(0, 5, 0), Color(1, 1, 1), 3.0]]:
		var o := OmniLight3D.new()
		o.position = spec[0]
		o.light_color = spec[1]
		o.light_energy = spec[2]
		o.omni_range = 14.0
		_vp.add_child(o)

	var cam := Camera3D.new()
	cam.fov = 38.0
	cam.position = Vector3(-1.2, 2.6, 10.5)
	_vp.add_child(cam)
	cam.look_at(Vector3(-2.3, 0.75, 0), Vector3.UP)  # car sits right of centre, UI on the left
	cam.current = true


# --- UI ----------------------------------------------------------------------------------------

func _build_ui() -> void:
	_display = load(DISPLAY)
	_body = load(BODY)
	_semi = load(SEMI)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	var shade := TextureRect.new()
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.set_color(0, Color(0.01, 0.0, 0.03, 0.88))
	g.gradient.set_color(1, Color(0.01, 0.0, 0.03, 0.0))
	g.fill_to = Vector2(1, 0)
	shade.texture = g
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 1050
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)

	# Tabs.
	var x := 120.0
	var qh := _label(_ui, _body, 22, Color(1, 1, 1, 0.5))
	qh.text = "Q / LB"
	_place(qh, x - 4, 62, 90, 30)
	x += 84.0
	for i in TAB_NAMES.size():
		var bg := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = PINK
		sb.skew = Vector2(0.25, 0)
		bg.add_theme_stylebox_override("panel", sb)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w := 40.0 + 21.0 * String(TAB_NAMES[i]).length()
		_place(bg, x, 56, w, 44)
		_ui.add_child(bg)
		_tab_bg.append(bg)
		var l := _label(_ui, _display, 28, Color.WHITE)
		l.text = TAB_NAMES[i]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_place(l, x, 58, w, 40)
		_tabs.append(l)
		x += w + 10.0
	var eh := _label(_ui, _body, 22, Color(1, 1, 1, 0.5))
	eh.text = "E / RB"
	_place(eh, x + 6, 62, 90, 30)

	# Wallet (top right).
	_level = _label(_ui, _display, 34, Color.WHITE)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_level.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_level.offset_left = -620
	_level.offset_right = -330
	_level.offset_top = 56
	_level.offset_bottom = 100
	_wallet = _label(_ui, _display, 34, GOLD)
	_wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wallet.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_wallet.offset_left = -320
	_wallet.offset_right = -80
	_wallet.offset_top = 56
	_wallet.offset_bottom = 100

	# CAR page.
	_car_page = Control.new()
	_car_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_car_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_car_page)
	var head := _label(_car_page, _body, 26, Color(PINK, 0.95))
	head.text = "CHOOSE YOUR RIDE"
	_place(head, 120, 150, 800, 40)
	_name = _label(_car_page, _display, 104, Color.WHITE)
	_place(_name, 112, 188, 1100, 130)
	_tag = _label(_car_page, _semi, 28, Color(1, 1, 1, 0.78))
	_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place(_tag, 120, 322, 720, 80)
	_lock = _label(_car_page, _display, 30, PINK)
	_place(_lock, 120, 400, 800, 44)
	var y := 470.0
	for k in ["SPEED", "ACCEL", "HANDLING", "TOUGHNESS"]:
		var cap := _label(_car_page, _body, 22, Color(1, 1, 1, 0.6))
		cap.text = k
		_place(cap, 120, y, 220, 30)
		var back := ColorRect.new()
		back.color = Color(1, 1, 1, 0.1)
		_place(back, 330, y + 9, 420, 12)
		_car_page.add_child(back)
		var fill := ColorRect.new()
		fill.color = LIME
		_place(fill, 330, y + 9, 0, 12)
		_car_page.add_child(fill)
		_bars[k] = fill
		_bar_vals[k] = 0.0
		y += 52.0
	_count = _label(_car_page, _display, 30, Color(1, 1, 1, 0.85))
	_place(_count, 120, 690, 600, 44)

	# Customisation rows page.
	_rows_page = Control.new()
	_rows_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_rows_page)
	_small_name = _label(_rows_page, _display, 56, Color.WHITE)
	_place(_small_name, 116, 138, 900, 76)

	_toast = _label(_ui, _display, 30, LIME)
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_toast.offset_left = 120
	_toast.offset_right = 1100
	_toast.offset_top = -170
	_toast.offset_bottom = -126
	_toast.modulate.a = 0.0
	_hint = _label(_ui, _body, 22, Color(1, 1, 1, 0.6))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 120
	_hint.offset_top = -100
	_hint.offset_right = 1700
	_hint.offset_bottom = -64

	_edit = LineEdit.new()
	_edit.max_length = PlateText.MAX_LEN
	_edit.placeholder_text = "TYPE PLATE"
	_edit.add_theme_font_override("font", _display)
	_edit.add_theme_font_size_override("font_size", 36)
	_edit.visible = false
	_edit.text_submitted.connect(_on_plate_submitted)
	_ui.add_child(_edit)
	_set_tab(0)


func _row_slots() -> Array:
	if tab == 0:
		return []
	var slots: Array = UnlockCatalog.TABS[TAB_NAMES[tab]].duplicate()
	if TAB_NAMES[tab] == "EXTRAS":
		slots.append(PLATE_ROW)
	return slots


func _build_rows() -> void:
	for r in _row_nodes:
		r.panel.queue_free()
	_row_nodes.clear()
	var y := 236.0
	for slot in _row_slots():
		var panel := Panel.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.03, 0.1, 0.72)
		sb.set_corner_radius_all(6)
		sb.border_color = PINK
		panel.add_theme_stylebox_override("panel", sb)
		_place(panel, 120, y, 800, 108)
		_rows_page.add_child(panel)
		var sw := ColorRect.new()
		_place(sw, 24, 34, 40, 40)
		panel.add_child(sw)
		var cap := _label(panel, _body, 20, Color(1, 1, 1, 0.55))
		cap.text = "PLATE TEXT" if slot == PLATE_ROW else String(UnlockCatalog.SLOT_NAMES[slot])
		_place(cap, 88, 10, 400, 28)
		var cnt := _label(panel, _body, 20, Color(1, 1, 1, 0.45))
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_place(cnt, 480, 10, 296, 28)
		var val := _label(panel, _display, 38, Color.WHITE)
		_place(val, 88, 36, 470, 56)
		var st := _label(panel, _body, 22, LIME)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		st.autowrap_mode = TextServer.AUTOWRAP_OFF
		_place(st, 470, 52, 306, 34)
		_row_nodes.append({"slot": slot, "panel": panel, "style": sb, "swatch": sw, "caption": cap, "count": cnt, "value": val, "status": st})
		y += 122.0


func _place(c: Control, x: float, y: float, w: float, h: float) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h


func _label(parent: Control, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


# --- state -------------------------------------------------------------------------------------

func _car_id() -> String:
	return _ids[index]


func _set_tab(t: int) -> void:
	tab = posmod(t, TAB_NAMES.size())
	for i in _tabs.size():
		_tab_bg[i].visible = i == tab
		_tabs[i].add_theme_color_override("font_color", Color.WHITE if i == tab else Color(1, 1, 1, 0.5))
	_car_page.visible = tab == 0
	_rows_page.visible = tab != 0
	_reset_cursors()
	_build_rows()
	_set_row(0)
	_hint.text = "◀ ▶  CAR      ENTER / A  DRIVE      Q E / LB RB  TABS      ESC / B  BACK" if tab == 0 \
		else "▲ ▼  ROW      ◀ ▶  BROWSE      ENTER / A  BUY · EQUIP      SPACE / X  DRIVE      ESC / B  BACK"


func _set_row(r: int) -> void:
	var n := _row_nodes.size()
	row = posmod(r, n) if n > 0 else 0
	_reset_cursors()
	_refresh()


## Hovered items snap back to what is equipped (so the preview shows the real loadout).
func _reset_cursors() -> void:
	var lo := profile.loadout(_car_id())
	for slot in UnlockCatalog.SLOTS:
		if slot == "car":
			continue
		var list := UnlockCatalog.items(slot)
		for i in list.size():
			if list[i].id == lo[slot]:
				_cursor[slot] = i
	_plate_i = maxi(0, PlateText.PRESETS.find(profile.plate(_car_id())))
	if not PlateText.PRESETS.has(profile.plate(_car_id())):
		_plate_i = PlateText.PRESETS.size()  # CUSTOM


func _hovered(slot: String) -> Dictionary:
	var list := UnlockCatalog.items(slot)
	return list[clampi(int(_cursor.get(slot, 0)), 0, list.size() - 1)]


func _plate_text_hovered() -> String:
	return PlateText.PRESETS[_plate_i] if _plate_i < PlateText.PRESETS.size() else profile.plate(_car_id())


func _preview_loadout() -> Dictionary:
	var lo := profile.loadout(_car_id())
	if tab != 0 and row < _row_nodes.size():
		var slot: String = _row_nodes[row].slot
		if slot != PLATE_ROW:
			lo[slot] = _hovered(slot).id
	return lo


func _refresh() -> void:
	var lvl := profile.level()
	var p := XpCurve.progress(profile.xp)
	_level.text = "LVL %d  ·  %d%%" % [lvl, int(p.fraction * 100.0)] if lvl < XpCurve.MAX_LEVEL else "LVL %d" % lvl
	_wallet.text = "%s CR" % UnlockCatalog._fmt(profile.credits)
	var car := _car_id()
	var unlocked := profile.can_drive(car)
	_lock.text = "" if unlocked else "LOCKED · REACH LVL %d  (%s XP TO GO)" % [
		int(UnlockCatalog.get_item("car_" + car).level),
		UnlockCatalog._fmt(maxi(0, XpCurve.total_for(int(UnlockCatalog.get_item("car_" + car).level)) - profile.xp))]
	_small_name.text = CarCatalog.spec(car).name + ("" if unlocked else "  (LOCKED)")
	for i in _row_nodes.size():
		var r: Dictionary = _row_nodes[i]
		var sel := i == row
		(r.style as StyleBoxFlat).bg_color = Color(0.1, 0.05, 0.16, 0.9) if sel else Color(0.04, 0.03, 0.1, 0.65)
		(r.style as StyleBoxFlat).border_width_left = 8 if sel else 0
		var arrows := sel
		if r.slot == PLATE_ROW:
			var custom := _plate_i >= PlateText.PRESETS.size()
			var txt := "CUSTOM: " + profile.plate(car) if custom else String(PlateText.PRESETS[_plate_i])
			r.value.text = ("◀ %s ▶" % txt) if arrows else txt
			r.count.text = "%d / %d" % [_plate_i + 1, PlateText.PRESETS.size() + 1]
			r.swatch.color = Color(0.9, 0.9, 0.85)
			var in_use := profile.plate(car) == _plate_text_hovered() and not custom
			r.status.text = "ENTER TO TYPE" if custom else ("IN USE" if in_use else "ENTER TO USE")
			r.status.add_theme_color_override("font_color", LIME if in_use else Color(1, 1, 1, 0.75))
			continue
		var it := _hovered(r.slot)
		r.value.text = ("◀ %s ▶" % String(it.name).to_upper()) if arrows else String(it.name).to_upper()
		r.count.text = "%d / %d" % [int(_cursor.get(r.slot, 0)) + 1, UnlockCatalog.items(r.slot).size()]
		r.swatch.color = GarageSwatch.color_of(it)
		var st := status(profile, car, it.id)
		r.status.text = st.text
		var col: Color = {"equipped": LIME, "owned": Color(1, 1, 1, 0.8), "buy": GOLD, "poor": Color(1, 0.55, 0.3), "locked": PINK}[st.kind]
		r.status.add_theme_color_override("font_color", col)
		r.value.add_theme_color_override("font_color", Color(1, 1, 1, 0.5) if st.kind == "locked" else Color.WHITE)
	_apply_preview()


func _apply_preview() -> void:
	if _car:
		CarStyle.apply(_car, _car_id(), _preview_loadout(), _plate_text_hovered())


func _toast_say(text: String, good := true) -> void:
	if text == "":
		return
	_toast.text = text
	_toast.add_theme_color_override("font_color", LIME if good else PINK)
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


# --- flow --------------------------------------------------------------------------------------

func _show(i: int, animate := true) -> void:
	index = i
	var id := _ids[i]
	var s := CarCatalog.spec(id)
	if _car:
		_car.queue_free()
	_car = CarCatalog.build(id, false)  # no flares/road pools on the stand
	# Small vehicles get scaled up a touch on the stand so they read at the same size.
	var he: Vector2 = _car.get_meta("half_extents")
	_car.scale = Vector3.ONE * clampf(2.2 / maxf(he.y, 0.5), 1.0, 1.3)
	_turntable.add_child(_car)
	_name.text = s.name
	_tag.text = s.tagline
	_count.text = "%d / %d" % [i + 1, _ids.size()]
	var st := CarCatalog.stats(id)
	for k in st:
		_bar_vals[k] = st[k]
	if animate:
		_swap_kick = 1.0
	_reset_cursors()
	_refresh()


func _cycle(dir: int) -> void:
	if tab == 0:
		_show(step(index, dir, _ids.size()))
		return
	if _row_nodes.is_empty():
		return
	var slot: String = _row_nodes[row].slot
	if slot == PLATE_ROW:
		_plate_i = step(_plate_i, dir, PlateText.PRESETS.size() + 1)
	else:
		_cursor[slot] = step(int(_cursor.get(slot, 0)), dir, UnlockCatalog.items(slot).size())
	_refresh()


func _activate() -> void:
	if tab == 0:
		pick()
		return
	if _row_nodes.is_empty():
		return
	var slot: String = _row_nodes[row].slot
	if slot == PLATE_ROW:
		if _plate_i >= PlateText.PRESETS.size():
			_open_plate_edit()
		else:
			profile.set_plate(_car_id(), _plate_text_hovered())
			ProfileStore.save_current()
			_toast_say("PLATE SET · " + profile.plate(_car_id()))
			_refresh()
		return
	var it := _hovered(slot)
	var msg := activate(profile, _car_id(), it.id)
	_toast_say(msg, profile.loadout(_car_id())[slot] == it.id)
	ProfileStore.save_current()
	_refresh()


func _open_plate_edit() -> void:
	_edit.text = profile.plate(_car_id())
	var r: Dictionary = _row_nodes[row]
	var pr: Panel = r.panel
	_place(_edit, 120 + 88, pr.offset_top + 34, 420, 60)
	_edit.visible = true
	_edit.grab_focus()
	_edit.select_all()


func _on_plate_submitted(text: String) -> void:
	var t := profile.set_plate(_car_id(), text)
	ProfileStore.save_current()
	_close_plate_edit()
	var filtered := PlateText.sanitize(text) != t
	_toast_say(("PLATE SET · " + t) if not filtered else "NOT ALLOWED · PLATE SET TO " + t, not filtered)
	_refresh()


func _close_plate_edit() -> void:
	_edit.visible = false
	_edit.release_focus()


func _process(delta: float) -> void:
	_t += delta
	_spin += delta * (0.45 + _swap_kick * 3.0)
	_swap_kick = maxf(0.0, _swap_kick - delta * 2.5)
	_turntable.rotation.y = 0.6 + _spin
	for k in _bars:
		var fill: ColorRect = _bars[k]
		var target: float = 420.0 * float(_bar_vals[k])
		fill.offset_right = lerpf(fill.offset_right, fill.offset_left + target, clampf(delta * 10.0, 0.0, 1.0))
	# The flame row demos its colour with a pop every second.
	if tab != 0 and row < _row_nodes.size() and _row_nodes[row].slot == "flame" and _car:
		var fx := _car.get_node_or_null("StyleFx") as CarStyleFx
		if fx and fmod(_t, 1.1) < delta:
			fx.pop(0.35)
	if _done or _edit.visible:
		return
	# Axis-driven actions (keys, stick) edge-detected here; buttons arrive as events below.
	if Input.is_action_just_pressed("steer_left"):
		UiSfx.play("ui_move")
		_cycle(-1)
	elif Input.is_action_just_pressed("steer_right"):
		UiSfx.play("ui_move")
		_cycle(1)
	elif Input.is_action_just_pressed("ui_up"):
		UiSfx.play("ui_tick")
		_set_row(row - 1)
	elif Input.is_action_just_pressed("ui_down"):
		UiSfx.play("ui_tick")
		_set_row(row + 1)


func _unhandled_input(e: InputEvent) -> void:
	if _done:
		return
	var key := e as InputEventKey
	var pad := e as InputEventJoypadButton
	var pressed := (key != null and key.pressed and not key.echo) or (pad != null and pad.pressed)
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if _edit.visible:
		if key and key.physical_keycode == KEY_ESCAPE or (pad and pad.button_index == JOY_BUTTON_B):
			_close_plate_edit()
		return
	if pad and pad.button_index == JOY_BUTTON_DPAD_LEFT:
		_cycle(-1)
	elif pad and pad.button_index == JOY_BUTTON_DPAD_RIGHT:
		_cycle(1)
	elif (key and key.physical_keycode == KEY_Q) or (pad and pad.button_index == JOY_BUTTON_LEFT_SHOULDER) \
			or (key and key.physical_keycode == KEY_TAB and key.shift_pressed):
		_set_tab(tab - 1)
	elif (key and key.physical_keycode in [KEY_E, KEY_TAB]) or (pad and pad.button_index == JOY_BUTTON_RIGHT_SHOULDER):
		_set_tab(tab + 1)
	elif e.is_action_pressed("pause") or (pad and pad.button_index == JOY_BUTTON_B):
		UiSfx.play("ui_back")
		_done = true
		cancelled.emit()
	elif (key and key.physical_keycode == KEY_SPACE) or (pad and pad.button_index == JOY_BUTTON_X):
		pick()
	elif (key and key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]) or (pad and pad.button_index == JOY_BUTTON_A):
		_activate()


## Lock in the current vehicle: remembered for this session and saved for the next.
func pick() -> void:
	var id := _ids[index]
	if not profile.can_drive(id):
		UiSfx.play("ui_deny")
		_toast_say("%s IS LOCKED · REACH LEVEL %d" % [CarCatalog.spec(id).name, int(UnlockCatalog.get_item("car_" + id).level)], false)
		return
	UiSfx.play("ui_confirm")
	_done = true
	CarCatalog.chosen = id
	GarageStore.save_last(id)
	chosen.emit(id)
