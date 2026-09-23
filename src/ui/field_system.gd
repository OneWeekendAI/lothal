class_name FieldSystem
extends Control
## THE FIELD ROOM, as a system on the dock (design §5.1-§5.3, slice F10).
##
## ---------------------------------------------------------------------------
## WHAT IS DIFFERENT ABOUT THIS SYSTEM, IN ONE LINE
## ---------------------------------------------------------------------------
##
## Every other system on the dock is a way of looking at THE AIRCRAFT. This one is a way of looking
## at THE PLACE. So selecting it does what no other system does: the viewport stops showing the
## drone and shows the site.
##
## That is a real departure and it is not asserted, it is inherited. `glass_shell.gd`'s
## `_on_room_changed` already says "EVERY room retracts the chrome, not only Sim" — the shell has a
## shape for a destination whose subject is not the aircraft, and Field is that shape promoted from
## the Rooms menu to the dock. The Airframe room is the other one: it owns the window, hides Lab's
## viewport, and brings its own columns. This room is built to that pattern deliberately, so the
## shell has two instances of one rule rather than one rule and one exception.
##
## **The two camera laws never meet.** Lab's distance is FIXED across the whole catalog, so that a
## whoop looks small beside a 10" (see `LabScreen._camera_distance_m`). Field's camera FRAMES THE
## SITE, so a 30 m park and a 400 m field both fill the window. Those two rules would fight in one
## viewport; they are in two, and each one keeps its reason.
##
## ---------------------------------------------------------------------------
## THE RAIL IS TWO-LEVEL, WHICH IS THE ONE SHAPE THE OTHER SYSTEMS DO NOT HAVE
## ---------------------------------------------------------------------------
##
## A system's rail is normally that system's parts — one flat shelf. Field's is the SITES, and
## within the selected site, ITS COURSES. One level deeper, because a course without the place it
## is laid out in has no elevation, no ground and no obstacles, and F1 through F5 spent five slices
## making that relationship real. Selecting a site selects its first course, so the second list is
## never showing a route that belongs somewhere else.
##
## ---------------------------------------------------------------------------
## THE DRONE SILHOUETTE IS BEHIND A FLAG THAT DEFAULTS ON (§11 Q1)
## ---------------------------------------------------------------------------
##
## It is the one element here that could read as clutter rather than as information, and the design
## marks it open. It is built ON so the question can be answered by LOOKING at it — see the F10
## report for what the screenshot showed.
##
## **It is a footprint and not a body, and that is a refusal rather than an omission.** `Build`
## publishes `airframe_span_m()` — a real, derived width — and publishes no overall HEIGHT for an
## assembled aircraft. Drawing a box "about so tall" would be inventing a spec to unlock a feature,
## which §0.1 forbids. So the silhouette is the span, drawn flat on the ground at the start gate,
## and the thing it makes visible is exactly the thing the aircraft contributes to the field: how
## big it is next to a ring.

## The two levels of the rail, and the three panels of §5.2, named ONCE.
##
## `GlassShell.SYSTEMS`' Field entry points at these constants rather than repeating the words.
## P10f's finding was two lists that had to be the same list and were never checked to be; a
## reference is the version of that which cannot drift.
const RAIL_TITLES := ["Sites", "Courses"]
const PANEL_TITLES := ["Site", "Course", "Conditions"]

## Horizontal field of view, matching the field editor's. The camera is KEEP_WIDTH for
## `LabScreen`'s reason: this room is a viewport between two columns, so its aspect is decided by
## the window, and under Godot's default KEEP_HEIGHT the horizontal angle would move with it.
const CAMERA_FOV := 50.0

## How much of the view the site's widest dimension takes. Below 1.0 so the ground has an edge you
## can see — a field drawn exactly to the frame reads as an infinite plane, which is the one thing
## a bounded site is not.
const SITE_SCREEN_FRACTION := 0.82

## Looking down at the field from a third of the way up the sky. Steeper reads as a map and loses
## gate height entirely; shallower hides the far half of the course behind the near half.
const CAMERA_ELEVATION_DEG := 34.0

## How thick the footprint plate is drawn. A DRAWING THICKNESS, in the sense a line width is one,
## and not a claim about any aircraft: the width of the plate is `Build.airframe_span_m()` and is
## real, and nothing here says how tall a drone is. See the header.
const PLATE_THICKNESS_M := 0.02

## THE WIDTH THE THREE PANELS' ROW GRIDS ARE HELD OPEN AT, and it is a repair rather than a
## decoration — the screenshot is what found it.
##
## `SpecPanel._add_row` makes every VALUE label autowrap, and an autowrapping `Label` reports a
## minimum width of ONE PIXEL (that is what makes wrapping possible — `content_width`'s own
## comment says so). A `ScrollContainer` hands its child the child's minimum width, so a panel
## whose footer asks for nothing collapses its value column to a few pixels and renders every
## value one letter per line. Photographed at 1280x720: the Site panel read "F / i / e / l / d"
## down the right-hand edge, in a 316 px panel with 200 px of room to spare, and the five rows
## below it were pushed out of sight by that one 100 px tall row.
##
## Lab does not show this because `PartDetails` carries a footer — build stats and a warning list —
## whose own minimum holds the column open. The Course panel here has a `WarningList` and rendered
## correctly in the same shot; the two without a footer did not. So the floor is stated rather than
## inherited from whatever a panel happens to put underneath its rows.
const PANEL_CONTENT_WIDTH := 268.0

## The node names the world uses, spelled once so the room and its tests agree without either
## reading the other's spelling out of the implementation.
const SILHOUETTE_NAME := "DroneSilhouette"
const TERRAIN_NAME := "Terrain"

## The places, the routes and the weather. Handed in by the shell, which holds the one instance of
## each for the session — a second copy here is how the garage and the field come to disagree about
## where the builder is (see `RoomHost`).
var sites: SiteLibrary
var courses: CourseLibrary
var conditions: ConditionsLibrary

## The aircraft, for the one number the aircraft contributes to a field: how wide it is. Null is a
## legitimate state — the empty shell has no drone — and the silhouette simply is not drawn.
var build: Build = null

## §11 Q1, built ON. See the header.
var show_drone_silhouette := true

var site_list: ItemList
var course_list: ItemList
var viewport_container: SubViewportContainer
var renderer: CourseRenderer

var _viewport: SubViewport
var _orbit: Node3D
var _camera: Camera3D
var _terrain: MeshInstance3D
var _silhouette: MeshInstance3D
var _panels: Dictionary = {}
var _warnings: WarningList
## True while a list is being repopulated, so `item_selected` firing as a side effect of `clear()`
## and `add_item()` does not read as a builder clicking a row.
var _filling := false

## Emitted when the builder picked a different site or course, so the shell can put the garage's
## air in step — the whole of §5.3's "every quoted number names its conditions" depends on the
## garage hearing about it.
signal selection_changed


func _init(p_sites: SiteLibrary, p_courses: CourseLibrary, p_conditions: ConditionsLibrary,
		p_build: Build = null) -> void:
	sites = p_sites
	courses = p_courses
	conditions = p_conditions
	build = p_build

	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0

	var row := HBoxContainer.new()
	row.name = "Row"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.anchor_right = 1.0
	row.anchor_bottom = 1.0
	add_child(row)

	row.add_child(_build_rail())

	viewport_container = SubViewportContainer.new()
	viewport_container.name = "SiteView"
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(viewport_container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	# Its own World3D, for the reason Lab's and the field editor's both have one: Sim is a separate
	# scene with its own cameras, and a shared world is how two rooms render into each other.
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport_container.add_child(_viewport)

	_build_world()

	row.add_child(_build_panels())

	refresh()


# ---------------------------------------------------------------------------
# The rail — two levels
# ---------------------------------------------------------------------------

func _build_rail() -> Control:
	var rail := PanelContainer.new()
	rail.name = "Rail"
	rail.custom_minimum_size = Vector2(216, 0)
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(column)

	site_list = _titled_list(column, RAIL_TITLES[0])
	site_list.item_selected.connect(choose_site)
	course_list = _titled_list(column, RAIL_TITLES[1])
	course_list.item_selected.connect(choose_course)
	return rail


func _titled_list(column: VBoxContainer, title_text: String) -> ItemList:
	var title := Label.new()
	title.text = title_text.to_upper()
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	column.add_child(title)

	var list := ItemList.new()
	list.name = title_text
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.auto_height = false
	column.add_child(list)
	return list


## A site chosen: SELECT ITS FIRST COURSE TOO.
##
## Not a convenience. The second list is the courses of the selected site, and the panels below
## describe "the selected course" — so a site change that left the previous site's course selected
## would put a route from somewhere else under a Site panel describing here, with no click in
## between to blame it on.
## PUBLIC, and named for what it does rather than for the signal it happens to be wired to. A check
## about "selecting a site selects its first course" has to CALL the function that does it —
## asserting the outcome and trusting that the right function produced it is how a check passes a
## defect it was written to catch (the F8 finding).
func choose_site(index: int) -> void:
	if _filling:
		return
	var ids := sites.ids()
	if index < 0 or index >= ids.size():
		return
	sites.select(str(ids[index]))
	var here := courses_of_selected_site()
	if not here.is_empty():
		courses.select(str(here[0]))
	refresh()
	selection_changed.emit()


## `choose_site`'s twin, public for its reason.
func choose_course(index: int) -> void:
	if _filling:
		return
	var here := courses_of_selected_site()
	if index < 0 or index >= here.size():
		return
	courses.select(str(here[index]))
	refresh()
	selection_changed.emit()


## The ids of the courses laid out at the SELECTED site, in the library's order.
##
## The whole of the two-level rail is this function: a flat list of every course in the file is
## what the second level must NOT be, because a course belongs to one place and the panels beneath
## describe that place.
func courses_of_selected_site() -> Array[String]:
	var out: Array[String] = []
	var here := sites.selected().site_id
	for id in courses.ids():
		if courses.course(id).site_id == here:
			out.append(id)
	return out


# ---------------------------------------------------------------------------
# The three panels (§5.2)
# ---------------------------------------------------------------------------

func _build_panels() -> Control:
	var column := VBoxContainer.new()
	column.name = "Panels"
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# THE THREE SHARE THE COLUMN'S HEIGHT EQUALLY, and each one's rows are cut to fit that share.
	#
	# A panel sized to its own content was tried first and is WRONG here, which the screenshot
	# settled: `SpecPanel` puts its rows inside a vertically-expanding `ScrollContainer`, whose
	# minimum height is nearly nothing, so three `SIZE_FILL` panels collapsed into three 24 px
	# bars with no text in them at all. They stretch, and what gives instead is the number of rows
	# each panel asks for — see the row lists below, which were cut until nothing clipped. That is
	# the right direction anyway: three panels at 190 px is 15 rows of the 604 px this column has,
	# and a row that has to be scrolled to is a row nobody reads in a theme whose scrollbars paint
	# nothing (`SpecPanel._add_row` says so).
	var site_panel := SitePanel.new()
	site_panel.name = PANEL_TITLES[0]
	site_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(site_panel)

	var course_panel := CoursePanel.new()
	course_panel.name = PANEL_TITLES[1]
	course_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_warnings = course_panel.warnings
	column.add_child(course_panel)

	var conditions_panel := ConditionsPanel.new()
	conditions_panel.name = PANEL_TITLES[2]
	conditions_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(conditions_panel)

	for each in [site_panel, course_panel, conditions_panel]:
		_panels[str(each.name)] = each
	return column


## One panel by its §5.2 name. The seam a test reads through, so a check asks for "Conditions"
## rather than walking a container and taking the third child — which would keep passing if the
## three were reordered into nonsense.
func panel(title: String) -> SpecPanel:
	return _panels.get(title, null) as SpecPanel


# ---------------------------------------------------------------------------
# The world — the SITE, not the drone
# ---------------------------------------------------------------------------

## The room's own 3D world, its camera and the plate at the start gate — the three things a check
## about the viewport swap and about the silhouette has to be able to look at. Accessors rather
## than public members so the room still owns when they are rebuilt.
func world() -> SubViewport:
	return _viewport


func camera() -> Camera3D:
	return _camera


func silhouette() -> MeshInstance3D:
	return _silhouette


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.57, 0.66)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_environment := WorldEnvironment.new()
	world_environment.environment = env
	_viewport.add_child(world_environment)

	# The ground, generated from the site's typed dimensions by F3's mesh builder. Never sculpted
	# and never imported (§0.1) — and never a bare PlaneMesh either, which is what the old field
	# editor drew and which cannot show a slope, a bowl or a wall.
	_terrain = MeshInstance3D.new()
	_terrain.name = TERRAIN_NAME
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.24, 0.27, 0.24)
	# Both faces, because a bowl and an enclosure are seen from inside as well as from above and a
	# back-face-culled wall vanishes exactly when you are standing in the field it encloses.
	ground.cull_mode = BaseMaterial3D.CULL_DISABLED
	_terrain.material_override = ground
	_viewport.add_child(_terrain)

	renderer = CourseRenderer.new(course())
	_viewport.add_child(renderer)

	# THE AIRCRAFT, AT THE START GATE, AS A FOOTPRINT. See the header for why there is no body.
	_silhouette = MeshInstance3D.new()
	_silhouette.name = SILHOUETTE_NAME
	var plate := StandardMaterial3D.new()
	plate.albedo_color = LothalTheme.ACCENT
	plate.emission_enabled = true
	plate.emission = LothalTheme.ACCENT
	plate.emission_energy_multiplier = 0.8
	_silhouette.material_override = plate
	_viewport.add_child(_silhouette)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_energy = 1.2
	_viewport.add_child(sun)

	_orbit = Node3D.new()
	_orbit.name = "Orbit"
	_viewport.add_child(_orbit)

	_camera = Camera3D.new()
	_camera.name = "SiteCamera"
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = CAMERA_FOV
	_camera.near = 0.1
	# Far enough for the biggest field the camera can be pulled back from. A 400 m site puts the
	# camera about 430 m out, and the far corner of the ground is further than the camera is.
	_camera.far = 6000.0
	_orbit.add_child(_camera)


## THE ONE PLACE THE SITE'S OWN SIZE DECIDES THE FRAMING (§5.1).
##
## Lab's camera distance is computed once from the catalog's largest frame and then held for every
## build, so that a whoop looks like a whoop beside a 10". That rule is exactly wrong here: a 30 m
## park and a 400 m field are the same picture at a fixed distance, one of them a dot. So this
## asks the SITE, every time, and a site whose extent changes reframes.
##
## Derived and not authored: the widest dimension of the site has to span
## `SITE_SCREEN_FRACTION` of a `CAMERA_FOV`-wide view, which is one line of trigonometry and no
## constant anybody picked. A GATE MOVING CANNOT CHANGE IT — nothing here asks the course anything,
## which is what stops the field jumping every time a ring is dragged.
func camera_distance_m() -> float:
	var extent := site().extent()
	var widest := maxf(extent.x, extent.y)
	if widest <= 0.0:
		widest = Terrain.DEFAULT_WIDTH_M
	var required_width_m := widest / SITE_SCREEN_FRACTION
	return (required_width_m * 0.5) / tan(deg_to_rad(CAMERA_FOV) * 0.5)


# ---------------------------------------------------------------------------
# What is selected
# ---------------------------------------------------------------------------

## The place the selected course is laid out in — `RoomHost.site_of_selected_course()`'s rule,
## asked of the libraries this room was handed. A course pointing at a site that is not there falls
## back to the selected site: the builder is somewhere, and the nearest true answer to where is
## where they are.
func site() -> Site:
	var id := course().site_id
	return sites.site(id) if sites.has(id) else sites.selected()


func course() -> GateCourse:
	return courses.selected()


## The air the field is flown in: the site's elevation and the selected conditions' temperature,
## composed by the one function that knows which two typed facts the density comes from (F2).
func air() -> AirDensity:
	return AirDensity.compose(site(), conditions.selected())


# ---------------------------------------------------------------------------
# Repaint
# ---------------------------------------------------------------------------

## Everything on screen, from whatever the libraries now say. One function rather than five, for
## `LabScreen.set_air`'s reason: a repaint that updated the panels and not the world would leave a
## picture of one field under a description of another.
func refresh() -> void:
	_fill_lists()
	_refresh_world()
	_refresh_panels()


func _fill_lists() -> void:
	_filling = true
	site_list.clear()
	var site_ids := sites.ids()
	for i in site_ids.size():
		var id := str(site_ids[i])
		site_list.add_item(sites.site(id).site_name)
		if id == sites.selected().site_id:
			site_list.select(i)

	course_list.clear()
	var here := courses_of_selected_site()
	for i in here.size():
		var id := str(here[i])
		course_list.add_item(courses.course(id).course_name)
		if id == courses.selected().course_id:
			course_list.select(i)
	_filling = false


func _refresh_world() -> void:
	var here := site()
	_terrain.mesh = TerrainMesh.build_mesh(here.terrain, here.obstacles)

	renderer.course = course()
	renderer.rebuild()

	_place_silhouette()

	# The pivot sits on the middle of the ground, so the camera swings around the SITE and not
	# around the world origin — which is metres away for any site the migration sized around a
	# course that was laid out off-centre (F1).
	var centre := here.center()
	_orbit.position = Vector3(centre.x, here.terrain.height_at(centre.x, centre.y), centre.y)
	_orbit.rotation_degrees = Vector3(-CAMERA_ELEVATION_DEG, 0.0, 0.0)
	# Parked out along the pivot's +Z with no rotation of its own, `LabScreen`'s arrangement and
	# for its reason: a camera looks down its own -Z, so from there it already points back at the
	# pivot, for every rotation, with no look_at that could drift.
	_camera.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, camera_distance_m()))


## The footprint, at the start line, at the size the fitted aircraft actually is.
##
## `Build.airframe_span_m()` is the same number `CourseWarnings.RING_SMALLER_THAN_AIRCRAFT` compares
## a ring against, so what this draws and what that warns about cannot come apart. `start_position`
## is asked WITH the terrain, so the plate sits on a slope rather than through it.
func _place_silhouette() -> void:
	var span := footprint_m()
	_silhouette.visible = show_drone_silhouette and span > 0.0
	if not _silhouette.visible:
		return
	var box := BoxMesh.new()
	box.size = Vector3(span, PLATE_THICKNESS_M, span)
	_silhouette.mesh = box
	_silhouette.position = course().start_position(site().terrain)


## How wide the silhouette is, in metres — zero when there is no drone to draw.
##
## A function rather than a mesh read, because it is what the §11 question is ABOUT: whether the
## thing on screen is the real aircraft at real scale, or a marker at a convenient size.
func footprint_m() -> float:
	return 0.0 if build == null else build.airframe_span_m()


func _refresh_panels() -> void:
	(panel(PANEL_TITLES[0]) as SitePanel).show_site(site())
	(panel(PANEL_TITLES[1]) as CoursePanel).show_course(course(), site())
	_warnings.show_warnings(CourseWarnings.evaluate(course(), build, site()))
	(panel(PANEL_TITLES[2]) as ConditionsPanel).show_conditions(conditions.selected(), air())


# ---------------------------------------------------------------------------
# The panels themselves
# ---------------------------------------------------------------------------

## §5.2's Site panel: name, shape, typed dimensions, elevation datum, obstacles.
class SitePanel extends SpecPanel:
	var site: Site = null

	func _init() -> void:
		super([
			{"key": "name", "label": "Site"},
			{"key": "shape", "label": "Ground"},
			{"key": "size", "label": "Extent"},
			{"key": "elevation", "label": "Elevation"},
			{"key": "obstacles", "label": "Obstacles"},
		])

	## No footer, only the width floor — see `PANEL_CONTENT_WIDTH`.
	func _build_footer(root: VBoxContainer) -> void:
		root.custom_minimum_size = Vector2(FieldSystem.PANEL_CONTENT_WIDTH, 0)

	func show_site(p_site: Site) -> void:
		site = p_site
		render_rows("Site")

	func row_text(key: String) -> String:
		if site == null:
			return "—"
		match key:
			"name": return site.site_name
			"shape": return String(site.terrain.shape)
			"size": return "%.0f × %.0f m" % [site.extent().x, site.extent().y]
			"elevation": return "%.0f m" % site.elevation_m
			"obstacles": return "%d" % site.obstacles.size()
		return "—"


## §5.2's Course panel: the selected gate's height, heading and radius — the three things a drag
## cannot express — and the course's warnings underneath.
class CoursePanel extends SpecPanel:
	var course: GateCourse = null
	var gate_index := 0
	var warnings: WarningList

	func _init() -> void:
		super([
			{"key": "name", "label": "Course"},
			{"key": "gate", "label": "Selected gate"},
			{"key": "height", "label": "Height"},
			{"key": "heading", "label": "Heading"},
			{"key": "radius", "label": "Radius"},
		])

	func _build_footer(root: VBoxContainer) -> void:
		root.custom_minimum_size = Vector2(FieldSystem.PANEL_CONTENT_WIDTH, 0)
		warnings = WarningList.new(260.0)
		root.add_child(warnings)

	func show_course(p_course: GateCourse, _site: Site) -> void:
		course = p_course
		render_rows("Course")

	func row_text(key: String) -> String:
		if course == null or course.gates.is_empty():
			return "—"
		var index: int = clampi(gate_index, 0, course.gates.size() - 1)
		var gate: Dictionary = course.gates[index]
		match key:
			"name": return course.course_name
			"gate": return "%d of %d" % [index + 1, course.gates.size()]
			"height": return "%.1f m" % float(gate["position"].y)
			# NORTH IS -Z AND EAST IS +X, the compass `Terrain._banked_height()` is pinned to.
			# `atan2(x, -z)` is that compass and not the other one: a gate facing -Z reads 0°, and
			# one facing +X reads 90°.
			"heading": return "%.0f°" % fposmod(
				rad_to_deg(atan2(gate["normal"].x, -gate["normal"].z)), 360.0)
			"radius": return "%.2f m" % float(gate["radius"])
		return "—"


## §5.2's Conditions panel: the four typed fields, the named set they belong to, and the derived ρ
## WITH ITS PERCENTAGE BELOW STANDARD.
##
## The percentage is a row of its own rather than a suffix on the density, because it is the number
## the builder actually reads: "16.3% down on sea level" means something to a pilot in a way that
## "1.0259 kg/m³" does not (`AirDensity.fraction_below_standard`'s own words). Two rows also means
## dropping it is a visibly missing row rather than a shorter string.
class ConditionsPanel extends SpecPanel:
	var conditions: Conditions = null
	var air: AirDensity = null

	func _init() -> void:
		super([
			{"key": "set", "label": "Conditions"},
			# THE DERIVED PAIR SITS DIRECTLY UNDER THE NAME OF THE SET, above the four typed
			# fields, and the order is the screenshot's doing: at the bottom of a 190 px panel the
			# percentage was the row that got cut, and it is the row §5.2 names.
			{"key": "density", "label": "Air density"},
			{"key": "below", "label": "Below standard"},
			{"key": "wind", "label": "Wind"},
			{"key": "from", "label": "Wind from"},
			{"key": "gust", "label": "Gustiness"},
			{"key": "temperature", "label": "Temperature"},
		])

	## No footer, only the width floor — see `PANEL_CONTENT_WIDTH`.
	func _build_footer(root: VBoxContainer) -> void:
		root.custom_minimum_size = Vector2(FieldSystem.PANEL_CONTENT_WIDTH, 0)

	func show_conditions(p_conditions: Conditions, p_air: AirDensity) -> void:
		conditions = p_conditions
		air = p_air
		render_rows("Conditions")

	func row_text(key: String) -> String:
		if conditions == null or air == null:
			return "—"
		match key:
			"set": return conditions.conditions_name
			"wind": return "%.1f m/s" % conditions.wind_speed_mps
			"from": return "%.0f°" % conditions.wind_from_deg
			"gust": return "%.1f m/s" % conditions.gustiness_mps
			"temperature": return "%.0f °C" % conditions.temperature_c
			"density": return "%.4f kg/m³" % air.kgm3()
			"below": return "%.1f%%" % (air.fraction_below_standard() * 100.0)
		return "—"
