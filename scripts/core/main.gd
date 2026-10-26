# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends Node3D
## Game root: wires world, player, traffic, scoring, HUD, audio and the run flow
## (title/attract -> countdown -> 3-minute run -> results). Also the proof harness
## (--capture / --capture-frames / --autodrive / --quit-after, see scripts/core/boot.gd).
##
## Screens (--screen=<name>, after `--`):
##   title    attract mode: autopilot weaves traffic behind the SEND IT title
##   select   car select (garage) between title and run; --car=<id> picks the vehicle directly
##   run      countdown, then a run (driven by you, or the autopilot with --autodrive)
##   results  a short autopilot run (--run-seconds, default 10) that ends on the results card
##   drive    no countdown, straight into the run (the default with --autodrive; capture/gate)
## --run-seconds=<s> overrides the 180 s run length. Autopilot runs never write the best score.
## --wreck-at=a,b,c forces a 140 km/h hit at those physics frames (proof shots of the wreck path).
## Promo captures: --no-hud hides the HUD and pursuit panel.
## --menu=settings|pause opens that menu at boot (proof shots of the menus).
## Police: --pursuit[=frame], --dist=<m>, --cam=pursuit (see scripts/police/police_manager.gd).

## Screen to open after the next scene reload (survives reload_current_scene as a static).
static var _next_screen := ""

var highway: Highway
var player: PlayerCar
var traffic: TrafficManager
var hazards: ShoulderHazards
var camera: ChaseCamera
var scorer: GapScorer
var hud: Hud
var audio: CarAudio
var police: PoliceManager     # police hook
var pursuit_hud: PursuitHud
var session := RunSession.new()
var best := BestStore.new(String(LaunchArgs.get_value("best-file", BestStore.PATH)))  # --best-file: probes
var screen := ""
var round_seed := 0
var _title: TitleScreen
var _results: ResultsScreen
var _menu: CanvasLayer       # open SettingsMenu / PauseMenu (owns input while open)
var _assisted := false      # autopilot drives the run: never save a best score
var _frame := 0
var _capture_dir := ""
var _capture_frames: Array[int] = []
var _quit_after := -1
var _wreck_at: Array[int] = []
var _stats := {"gaps": 0, "crashes": 0, "max_kmh": 0.0}
var _escapes := 0             # progression: police escapes this run, and their heat
var _escape_heat_sum := 0
var _max_escape_heat := 0


func _ready() -> void:
	add_child(NightEnvironment.new())
	highway = Highway.new()
	add_child(highway)

	player = PlayerCar.new()
	player.position = Vector3(RoadSpec.lane_x(1), 0, 0)
	player.speed = 120.0 / 3.6
	add_child(player)

	traffic = TrafficManager.new()
	add_child(traffic)
	round_seed = LaunchArgs.round_seed()  # fresh per round (scene reload) unless --seed=N
	print("ROUND_SEED ", round_seed)
	traffic.setup(player, round_seed)
	# Police hook: cops live in traffic; added after it so chasers move after the traffic step.
	police = PoliceManager.new()
	add_child(police)
	police.setup(traffic, player, session, round_seed)
	# Emergency-lane hazards (crash like traffic); after traffic/police so contacts see this step's moves.
	hazards = ShoulderHazards.new()
	hazards.setup(player, round_seed)
	add_child(hazards)

	camera = ChaseCamera.new()
	camera.target = player
	add_child(camera)
	camera.global_position = player.position + Vector3(0, 2, 7)
	camera.make_current()
	if Boot.arg("cam", "") == "pursuit":
		var pc := PursuitCam.new()
		pc.police = police
		pc.player = player
		add_child(pc)

	scorer = GapScorer.new()
	hud = Hud.new()
	add_child(hud)
	hud.bind(scorer, player, session)
	hud.best_score = best.best_score
	pursuit_hud = PursuitHud.new()
	add_child(pursuit_hud)
	pursuit_hud.bind(police, session)
	audio = CarAudio.new()
	audio.player = player
	add_child(audio)

	traffic.gap.connect(_on_gap)
	player.crashed.connect(_on_crash)
	scorer.banked.connect(func(p, n): audio.on_bank(p, n))
	scorer.wiped.connect(func(_l): audio.on_wipe())
	session.state_changed.connect(_on_state)
	police.busted.connect(_on_busted)
	police.escaped.connect(_on_escaped)

	_capture_dir = String(Boot.arg("capture", ""))
	for s in String(Boot.arg("capture-frames", "")).split(",", false):
		_capture_frames.append(int(s))
	_quit_after = int(Boot.arg("quit-after", "-1"))
	for s in String(Boot.arg("wreck-at", "")).split(",", false):
		_wreck_at.append(int(s))
	if _capture_dir != "":
		DirAccess.make_dir_recursive_absolute(_capture_dir)
	highway.update_stream(player.position.z)
	hazards.update_stream(player.position.z)
	_open(_pick_screen())
	match String(Boot.arg("menu", "")):  # proof shots: --menu=settings (title) / --menu=pause
		"settings":
			open_settings()
		"pause":
			open_pause.call_deferred()


func _pick_screen() -> String:
	if _next_screen != "":
		var s := _next_screen
		_next_screen = ""
		return s
	if Boot.has_arg("screen"):
		return String(Boot.arg("screen"))
	return "drive" if Boot.has_arg("autodrive") else "title"


func _open(s: String) -> void:
	screen = s
	session.duration_s = float(Boot.arg("run-seconds", "10" if s == "results" else "180"))
	_assisted = Boot.has_arg("autodrive") or s == "results"
	match s:
		"title":
			player.autopilot = Autopilot.new(traffic)
			audio.attract = true
			hud.visible = false
			_title = TitleScreen.new()
			_title.best = best
			add_child(_title)
		"select":  # garage hook: car select over the attract world (scripts/ui/car_select.gd)
			player.autopilot = Autopilot.new(traffic)
			audio.attract = true
			hud.visible = false
			var cs := CarSelect.new()
			cs.chosen.connect(func(_id): _go("run"))
			cs.cancelled.connect(func(): _go("title"))
			add_child(cs)
		"run":
			# Rolling start: the autopilot holds the car in traffic until GO.
			var ap := Autopilot.new(traffic)
			ap.cruise_kmh = 130.0
			player.autopilot = ap
			session.start(true)
		_:  # "drive", "results"
			player.autopilot = Autopilot.new(traffic)
			session.start(false)
	if Boot.has_arg("no-hud"):  # clean frames for promo shots
		hud.visible = false
		pursuit_hud.visible = false


func _go(s: String) -> void:
	_next_screen = s
	get_tree().reload_current_scene()


func _on_state(st: RunSession.State) -> void:
	match st:
		RunSession.State.RUNNING:
			if screen == "run":
				audio.on_count(0)
				player.autopilot = Autopilot.new(traffic) if Boot.has_arg("autodrive") else null
		RunSession.State.RESULTS:
			_show_results()


func _show_results() -> void:
	if _results:
		return
	# Time up: whatever is still live banks. (A wreck-out already wiped it.)
	if scorer.combo_count > 0:
		scorer.tick(scorer.combo_time_left + 0.01)
	var prev := best.best_score
	var is_best := best.submit(scorer.banked_total, scorer.best_combo, int(session.max_kmh))
	if not _assisted:
		best.save()
	player.autopilot = Autopilot.new(traffic)
	_results = ResultsScreen.new()
	_results.score = scorer.banked_total
	_results.best_combo = scorer.best_combo
	_results.gaps = session.gaps
	_results.max_kmh = int(session.max_kmh)
	_results.distance_m = session.distance_m
	_results.wrecks = session.wrecks
	_results.reason = session.end_reason
	_results.new_best = is_best
	_results.prev_best = prev
	_results.rolled_up.connect(func(): audio.on_results(is_best))
	_award(_results)
	add_child(_results)
	hud.visible = false
	print("RESULTS score=%d best_combo=%d gaps=%d max_kmh=%d dist_m=%d wrecks=%d reason=%s new_best=%s" % [
		scorer.banked_total, scorer.best_combo, session.gaps, int(session.max_kmh), int(session.distance_m),
		session.wrecks, session.end_reason, is_best])


func _on_gap(clearance: float, side: int, _oncoming: bool, car: TrafficCar) -> void:
	var split := traffic.is_split(side)
	if not session.is_running():
		# Attract / countdown / results: whoosh, but nothing scores. Stats count what would have.
		if player.kmh() >= scorer.min_speed_kmh and clearance <= scorer.max_clearance_m:
			_stats.gaps += 1
		audio.on_gap(clearance, side, 1.0)
		return
	# Validity first (shoulder riding, re-passing the same car): see PassRules.
	var pts := 0
	if PassRules.counts(player.position.x, car.paid):
		pts = scorer.on_pass(player.kmh(), clearance, split)
	if pts > 0:
		car.paid += 1
	if pts > 0 and police.pursuit.is_chasing():
		# Police hook: gaps during a pursuit pay +50% on top (GapScorer maths untouched).
		scorer.combo_points += int(round(pts * 0.5))
	if pts > 0:
		_stats.gaps += 1
		session.on_gap()
		audio.on_gap(clearance, side, scorer.multiplier)
		camera.add_shake(0.03)  # a gap is a reward, not an impact: barely felt


func _on_crash(kmh: float) -> void:
	_stats.crashes += 1
	camera.add_shake(clampf(kmh / 90.0, 0.3, 1.0))
	audio.on_crash(kmh)
	if session.is_running():
		hud.on_wreck(session.wrecks_left() - 1)
		scorer.on_crash()
		hud.crash_flash()
		session.on_wreck()


## Police hook: BUSTED holds the car on the brakes for the banner, then ends the run.
func _on_busted() -> void:
	if not session.is_running():
		return
	player.autopilot = BustedHold.new(traffic)
	audio.on_crash(40.0)
	get_tree().create_timer(1.8).timeout.connect(func(): session.finish("busted"))


## Progression: XP + credits from this run's validated numbers. Your own runs are saved; autopilot
## runs (attract, --autodrive, the results proof screen) show what they would earn and save nothing.
func _award(r: ResultsScreen) -> void:
	var stats := {
		"score": scorer.banked_total, "gaps": session.gaps, "distance_m": session.distance_m,
		"best_combo": scorer.best_combo, "escapes": _escapes, "escape_heat_sum": _escape_heat_sum,
		"max_escape_heat": _max_escape_heat, "wrecks": session.wrecks, "reason": session.end_reason,
		"max_kmh": session.max_kmh,
	}
	var reward := RunReward.compute(stats)
	var prof := ProfileStore.get_current() if not _assisted else ProfileStore.load_from(ProfileStore.file)
	var outcome := prof.apply_run(reward, stats)
	var saved := false
	if not _assisted:
		saved = ProfileStore.save_current() == OK
	r.reward = reward
	r.progress = outcome
	r.profile = prof
	r.saved = saved
	r.assisted = _assisted
	print("PROGRESS xp=+%d (run %d, goals %d) level %d->%d credits=+%d total_cr=%d unlocked=%s goals_done=%d saved=%s capped=%s" % [
		outcome.xp_gained, reward.xp, outcome.goal_xp, outcome.level_before, outcome.level_after,
		outcome.credits_gained, prof.credits, outcome.unlocked, outcome.goals_done.size(), saved, reward.capped])


## Police hook: an escape banks its bonus straight away.
func _on_escaped(bonus: int) -> void:
	if session.is_running():
		_escapes += 1
		_escape_heat_sum += police.pursuit.heat
		_max_escape_heat = maxi(_max_escape_heat, police.pursuit.heat)
		scorer.banked_total += bonus
		audio.on_bank(bonus, 1)


func _unhandled_input(e: InputEvent) -> void:
	if is_instance_valid(_menu):
		return  # the open menu owns input
	var pressed: bool = (e is InputEventKey and e.pressed and not e.echo) or (e is InputEventJoypadButton and e.pressed)
	if not pressed:
		return
	match screen:
		"title":
			# Mark handled first: _go() reloads the scene, after which this node has no viewport.
			get_viewport().set_input_as_handled()
			if e.is_action_pressed("pause"):
				open_settings()
			else:
				_go("select")  # garage hook: pick a car first
		_:
			if e.is_action_pressed("pause"):
				get_viewport().set_input_as_handled()
				if _results:
					_go("title")
				else:
					open_pause()
			elif e.is_action_pressed("restart"):
				_go("run")
			elif _results and _results.ready_for_input:
				_go("run")


## Settings overlay from the title screen (the attract run keeps going behind it).
func open_settings() -> SettingsMenu:
	var m := SettingsMenu.new()
	_menu = m
	add_child(m)
	return m


## Pause (Esc / pad Back during a run): the tree stops until RESUME.
func open_pause() -> PauseMenu:
	var p := PauseMenu.new()
	_menu = p
	get_tree().paused = true
	p.resumed.connect(func():
		get_tree().paused = false
		p.queue_free())
	p.restart.connect(func():
		get_tree().paused = false
		_go("run"))
	p.quit_to_title.connect(func():
		get_tree().paused = false
		_go("title"))
	add_child(p)
	return p


func _physics_process(delta: float) -> void:
	_frame += 1
	var prev_count := session.countdown_number()
	session.tick(delta, player.kmh())
	if session.state == RunSession.State.COUNTDOWN and session.countdown_number() != prev_count:
		audio.on_count(session.countdown_number())
	elif _frame == 1 and session.state == RunSession.State.COUNTDOWN:
		audio.on_count(session.countdown_number())
	if session.is_running():
		scorer.tick(delta)
	highway.update_stream(player.position.z)
	hazards.update_stream(player.position.z)
	_stats.max_kmh = maxf(_stats.max_kmh, player.kmh())
	if _frame in _wreck_at:
		player.on_traffic_hit(140.0, 0.0)  # proof aid: a real hit through the normal crash path
	if _frame in _capture_frames:
		_snap.call_deferred(_frame)
	if _quit_after > 0 and _frame >= _quit_after:
		_finish()


func _snap(f: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/frame_%05d.png" % [_capture_dir, f]
	img.save_png(path)
	print("CAPTURE ", path, " kmh=", int(player.kmh()), " banked=", scorer.banked_total, " combo=", scorer.combo_points)
	if f == _capture_frames.max() and _quit_after < 0:
		_finish()


## Print the run stats, release statics and quit (exit_code: probes report their verdict).
func _finish(exit_code := 0) -> void:
	print("RUN_STATS frames=%d gaps=%d crashes=%d max_kmh=%d banked=%d best_combo=%d live=%d dist_m=%d screen=%s state=%s" % [
		_frame, _stats.gaps, _stats.crashes, int(_stats.max_kmh), scorer.banked_total, scorer.best_combo,
		scorer.combo_points, int(-player.position.z), screen, RunSession.State.keys()[session.state]])
	police.print_stats()
	police.release()  # police hook: sirens off before quit
	set_physics_process(false)
	# Freeze the world too: traffic kept stepping for the frames below and a gap it reported then
	# reached the freed audio node (SCRIPT ERROR on quit).
	for n in [player, traffic, hazards, police]:
		if n:
			n.process_mode = Node.PROCESS_MODE_DISABLED
	audio.shutdown()
	CarModel.release()
	audio.queue_free()
	for i in 3:
		await get_tree().process_frame
	get_tree().quit(exit_code)
