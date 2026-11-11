class_name TestIdentity
## B5 (UI_REDESIGN_TRACKER): DsIdentity says which drone this is. Two different designs read differently;
## the text carries the class and the frame id; no source refuses; the chip and sheet follow the session.

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var a := DesignSession.default_for_class("five_inch")
	var b := DesignSession.default_for_class("tiny_whoop")
	var ia := DsIdentity.describe(a, catalog, "Racer", "class seed")
	var ib := DsIdentity.describe(b, catalog, "Racer", "class seed")
	results.append(TestResult.new("describe works for a class seed", bool(ia["ok"]) and bool(ib["ok"]), str(ia["reason"])))
	results.append(TestResult.new("two different designs have different text and chip",
		ia["text"] != ib["text"] and ia["chip"] != ib["chip"], "%s | %s" % [ia["text"], ib["text"]]))
	results.append(TestResult.new("the text contains the class id and the frame id",
		"five_inch" in String(ia["text"]) and String(a.selection["frame"]) in String(ia["text"])
		and "tiny_whoop" in String(ib["text"]) and String(b.selection["frame"]) in String(ib["text"]), ia["text"]))
	results.append(TestResult.new("it names all four key parts, the weight and the source",
		(ia["lines"] as Array).size() == 4 and float(ia["auw_g"]) > 10.0 and "class seed" in String(ia["text"]), str(ia["lines"])))
	# A part swap changes the identity.
	var c := DesignSession.default_for_class("five_inch")
	for opt in catalog.list_category("battery"):
		var id := String(opt["part_id"])
		if id != String(c.selection["battery"]):
			c.set_part("battery", id)
			break
	var ic := DsIdentity.describe(c, catalog, "Racer", "class seed")
	results.append(TestResult.new("a swapped battery changes the identity text", ic["text"] != ia["text"], ic["text"]))
	# Refusals.
	var none := DsIdentity.describe(a, catalog, "Racer", "")
	results.append(TestResult.new("an empty source refuses, with a reason", not bool(none["ok"]) and String(none["reason"]) != "" and none["text"] == "", str(none["reason"])))
	var odd := DsIdentity.describe(a, catalog, "Racer", "somewhere")
	results.append(TestResult.new("an unknown source refuses", not bool(odd["ok"]), str(odd["reason"])))
	var broken := DesignSession.default_for_class("five_inch")
	broken.selection["frame"] = "no_such_frame"
	results.append(TestResult.new("a design that does not build refuses", not bool(DsIdentity.describe(broken, catalog, "x", "class seed")["ok"]), ""))
	results.append(TestResult.new("an empty name reads Untitled", DsIdentity.describe(a, catalog, "  ", "design file")["name"] == "Untitled", ""))
	# The Design Space: chip and sheet.
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	var chip_before := ds.file_bar.identity_button.text
	results.append(TestResult.new("the top bar has an identity chip with the class in it",
		ds.file_bar.identity_button.visible and "5" in chip_before and ds.identity()["source"] == "class seed", chip_before))
	ds.toggle_identity()
	var sheet_texts := _texts(ds.identity_sheet)
	results.append(TestResult.new("the chip opens a sheet naming the frame, and as the side drawer",
		ds.identity_sheet.visible and ds.side_drawer == ds.identity_sheet and String(catalog.get_part(String(ds.session.selection["frame"])).get("name", "?")) in sheet_texts and not (String(ds.session.selection["frame"]) in sheet_texts), sheet_texts))
	ds.identity_sheet.hide()
	for opt in catalog.list_category("battery"):
		var id := String(opt["part_id"])
		if id != String(ds.session.selection["battery"]):
			ds.set_part("battery", id)
			break
	results.append(TestResult.new("a part change rewrites the chip", ds.file_bar.identity_button.text != chip_before, ds.file_bar.identity_button.text))
	ds.free()
	return results


static func _texts(node: Node) -> String:
	var out := ""
	for c in node.find_children("*", "Label", true, false):
		out += (c as Label).text + "\n"
	return out
