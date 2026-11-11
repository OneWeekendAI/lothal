class_name DsIdentity
extends RefCounted
## B5: what is being designed / flown, in words. One place answers "which drone is this?" so the Design
## Space's top bar chip, its sheet and (S1/S2) the sim's read-only identity drawer all say the same thing.
##
## `describe(session, catalog, name, source)` returns {ok, reason, name, class_id, class_name, parts, auw_g,
## source, chip, lines, text}. It REFUSES (ok false, a reason) rather than inventing: no source named, an
## unknown source, or a design that does not build. Sources are what a design came from:
##   design file    opened from / saved to a design file
##   saved project  a saved project the builder had already changed
##   class seed     the class's own starting build, untouched

const SOURCES := ["design file", "saved project", "class seed"]
## The four parts that name a drone, in the order they are listed.
const KEY_PARTS := ["frame", "motor", "propeller", "battery"]


static func describe(session: DesignSession, catalog: PartsCatalog, build_name: String, source: String) -> Dictionary:
	if source == "":
		return _refuse("no source: say where this design came from")
	if not SOURCES.has(source):
		return _refuse("unknown source \"%s\"" % source)
	if session == null:
		return _refuse("no design")
	var b := session.build(catalog)
	if b == null:
		return _refuse("this design does not build")
	var entry := DroneClass.by_id(session.drone_class)
	var class_name_ := String(entry.get("name", session.drone_class))
	var shown_name := build_name.strip_edges() if build_name.strip_edges() != "" else "Untitled"
	var parts := {}
	var lines: Array[String] = []
	for category in KEY_PARTS:
		var id := String(session.selection.get(category, ""))
		var part := catalog.get_part(id)
		parts[category] = {"id": id, "name": String(part.get("name", id))}
		lines.append("%s  %s  (%s)" % [category.capitalize(), parts[category]["name"], id])
	var auw := b.all_up_weight_g()
	var text := "%s  |  %s (%s)  |  %s  |  %.0f g  |  from %s" % [
		shown_name, class_name_, session.drone_class, " / ".join(PackedStringArray(KEY_PARTS.map(
			func(c: String) -> String: return String(parts[c]["id"])))), auw, source]
	return {"ok": true, "reason": "", "name": shown_name, "class_id": session.drone_class, "class_name": class_name_,
		"parts": parts, "auw_g": auw, "source": source,
		"chip": "%s  ·  %s  ·  %.0f g" % [shown_name, class_name_, auw], "lines": lines, "text": text}


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "name": "", "class_id": "", "class_name": "", "parts": {}, "auw_g": 0.0,
		"source": "", "chip": "", "lines": [], "text": ""}


## The sheet: a Design Space drawer listing the identity. `fill` rewrites it from a `describe` result.
static func sheet() -> DsDrawer:
	var d := DsDrawer.new("This build")
	d.name = "IdentitySheet"
	d.visible = false
	return d


static func fill(d: DsDrawer, info: Dictionary) -> void:
	for c in d.content.get_children():
		d.content.remove_child(c)
		c.queue_free()
	if not bool(info.get("ok", false)):
		d.content.add_child(DsUi.label(String(info.get("reason", "")), DsUi.WARN))
		return
	var title := DsUi.label(String(info["name"]), DsUi.INK, LothalTheme.FONT_SIZE_BODY)
	d.content.add_child(title)
	d.content.add_child(DsUi.label("%s  (%s)" % [info["class_name"], info["class_id"]]))
	d.content.add_child(DsUi.rule())
	for line in info["lines"]:
		d.content.add_child(DsUi.label(String(line)))
	d.content.add_child(DsUi.rule())
	d.content.add_child(DsUi.label("All-up weight  %.0f g" % float(info["auw_g"])))
	d.content.add_child(DsUi.label("From  %s" % String(info["source"]), DsUi.INK_FAINT))
