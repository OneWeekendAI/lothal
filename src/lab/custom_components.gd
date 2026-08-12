class_name CustomComponents
extends CustomParts
## The shared half of the four categories LTHL-11 unbundled out of the electronics lump — camera,
## VTX, antenna, receiver. Read CustomParts first for the id space, the shared document and the
## refusals that are not about any particular part.
##
## A SECOND BASE CLASS RATHER THAN FOUR COPIES, and the reason is that these four really are the
## same part from the mass model's point of view. Each is a box with a mass that sits in a bay it
## does not choose; none of them has a coefficient, a rating or a curve. What differs between them
## is the array key, the category word, and what a builder calls the thing — three lines each,
## which is exactly what the subclasses below contain.
##
## Contrast the six older categories, where a shared base would have been wrong: a frame's
## refusals are about geometry, a motor's are about a thrust test, an ESC's are about a per-channel
## rating misread as a per-board one. Those are four different questions wearing one shape. These
## four are one question asked four times.
##
## ---------------------------------------------------------------------------
## THE ONE FIELD THAT WILL BE ENTERED WRONG
## ---------------------------------------------------------------------------
##
## The three dimensions, and specifically the fact that they are REQUIRED. A camera with no
## dimensions does not fail: Build.component_size_of falls back to a 10 mm cube, so the part is
## placed correctly, weighed correctly, and spun slightly wrong — the aircraft flies, and nothing
## on screen says the tensor is carrying a stand-in. That is the shape of silence this project
## refuses everywhere else (a missing `continuous_a` reads as an unlimited ESC), so it is refused
## here too, at the point where the builder is looking at the product page that has the numbers on
## it.
##
## MASS COMES OUT OF THE BUDGET AND A CUSTOM PART IS NO EXCEPTION. A builder's 30 g camera does not
## add 30 g beside Build.ELECTRONICS_MASS_G; it takes the camera's budgeted share out of it and
## costs the aircraft the excess, exactly as a shipped 12 g one does. Nothing in this file has to
## do anything to make that true — mass_parts() reads `mass_g` and does not care where the record
## came from — and it is stated here because "my part must be being added on top" is the first
## thing a builder will assume when the all-up weight moves by less than the number they typed.

## How every one of these attaches. TRAY, on all four, because the bay a camera sits in has no
## spacing any frame in this catalog publishes — see MountPoint.TRAY. A builder is not asked for
## it: there is nothing to ask, and a field with one legal value is a field that teaches nobody
## anything.
const TRAY_ATTACHMENT := "tray"


## What a builder calls this kind of thing, for the refusal messages. The category word reads badly
## in a sentence for two of the four ("a vtx needs dimensions", "a receiver's height").
func noun() -> String:
	return category()


## A catalog-shaped record from the three dimensions and the mass a builder reads off a product
## page, plus whatever browsing metadata their category uses. Static shape, one place, same as
## every other category's make_record — except that the metadata differs per category, so it is
## handed in already assembled rather than being spelled out in a parameter list four times.
static func component_record(part_id: String, name: String, category_word: String, mass_g: float,
		length_mm: float, width_mm: float, height_mm: float, meta: Dictionary,
		source: String) -> Dictionary:
	return {
		"part_id": part_id,
		"name": name,
		"category": category_word,
		"mass_g": mass_g,
		"mounting": {
			"attachment": TRAY_ATTACHMENT,
		},
		"specs": {
			"length_mm": length_mm,
			"width_mm": width_mm,
			"height_mm": height_mm,
		},
		"catalog": meta,
		"source": source,
	}


## The refusals that are about being one of these four rather than about being a part at all.
##
## Nothing here is about whether a component is SENSIBLE. A 60 g nano camera is absurd rather than
## impossible, and labs-and-sim.md §2 warns and never blocks — what it would do is show up as 52 g
## of excess over the budgeted share, in the all-up weight, where a builder can see it.
func _category_problems(record: Dictionary, _catalog: PartsCatalog) -> Array[String]:
	var problems: Array[String] = []

	var raw_specs: Variant = record.get("specs", null)
	if not (raw_specs is Dictionary):
		problems.append("specs is required: the %s's length, width and height in millimetres" % noun())
		return problems
	var specs := raw_specs as Dictionary

	# All three, each named separately, because a builder who left one out needs to be told which.
	# A missing dimension is not a missing part — Build.component_size_of falls back to a 10 mm cube
	# and the aircraft flies — which is exactly why it is caught here instead of downstream.
	for field in ["length_mm", "width_mm", "height_mm"]:
		if not specs.has(field) or float(specs[field]) <= 0.0:
			problems.append("specs.%s must be present and positive — without all three, the %s is weighed in the right place with a stand-in box, and nothing on screen says so" % [
				field, noun()])

	# The bay has no pattern to compare, so the attachment is the whole of what mounting says. A
	# record claiming BOLT would be claiming a spacing that no frame in the catalog publishes.
	var mounting: Variant = record.get("mounting", null)
	if not (mounting is Dictionary):
		problems.append("mounting is required: a %s sits in a bay, so mounting.attachment is \"%s\"" % [
			noun(), TRAY_ATTACHMENT])
	elif str((mounting as Dictionary).get("attachment", "")) != TRAY_ATTACHMENT:
		problems.append("mounting.attachment must be \"%s\" — no frame publishes a spacing for a %s, so there is no pattern to bolt to" % [
			TRAY_ATTACHMENT, noun()])

	return problems
