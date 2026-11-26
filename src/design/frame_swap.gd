class_name FrameSwap
extends RefCounted
## Swapping the frame from the catalog (PLAN item 8). Pure: no Node, nothing kept.
##
## A frame is offered only when it can be SHOWN truthfully: the class fits it (ClassFit, same prop-size
## class) AND a frame document draws it (`DesignSession.frame_document_path`). The catalog's specs (arm
## length, plate and arm thickness, prop size, hole patterns) do not determine a FrameGen document (plate
## outline, holes, arm shape, hardware positions), so a document is never generated from them, and the
## class's own drawing is never shown under another frame's name. Today each class has exactly ONE
## document, its own frame, so nothing else is offered anywhere; the day a second document exists for a
## class it shows up here with no further code.


## Frames the session could swap to: [{id, name, mass_g}], the fitted frame excluded. Each is class-fitted
## and has a document. The hard-misfit verdict (HARD_IDS) is `DesignSession.swap_frame`'s, as for any part.
static func offerings(session: DesignSession, catalog: PartsCatalog) -> Array:
	var out: Array = []
	if not DesignSession.FRAME_DOCUMENTS.has(session.drone_class):
		return out
	var fitted := String(session.selection.get("frame", ""))
	for part in catalog.list_category("frame"):
		var id := String((part as Dictionary).get("part_id", ""))
		if id == fitted or DesignSession.frame_document_path(id) == "":
			continue
		if not ClassFit.verdict(session.drone_class, "frame", id, catalog)["fits"]:
			continue
		out.append({"id": id, "name": String(part.get("name", id)), "mass_g": float(part.get("mass_g", 0.0))})
	return out


## One line saying why the frame cannot be swapped here, "" when something is on offer.
static func why_not(session: DesignSession, catalog: PartsCatalog) -> String:
	if not DesignSession.FRAME_DOCUMENTS.has(session.drone_class):
		return "This class's frame is moulded or ducted and has no drawing, so it cannot be swapped."
	if offerings(session, catalog).is_empty():
		return "No other frame for this class has a drawing yet."
	return ""


## What leaving the frame costs: the edits made to it, which a swap discards (undo brings them back).
static func drops_edits(session: DesignSession, catalog: PartsCatalog) -> bool:
	return not session.frame_edit(catalog).is_empty()
