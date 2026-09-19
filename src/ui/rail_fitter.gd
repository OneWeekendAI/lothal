class_name RailFitter
extends RefCounted
## The finder's seam onto the LIVE BUILD — the other half of `PartFinder.set_fitter()`
## (plans/2026-09-19-quiet-canvas-design.md §4, QC4).
##
## `PartFinder` asks for exactly three methods — `preview_part`, `commit_part`, `restore_part` —
## and duck-types them, so this class exists to be the one object in the app that knows a part
## dictionary can be turned into a fitted part. `tests/test_part_finder.gd`'s `FitterSpy` is the
## same contract as a recorder; this is the same contract as a consequence.
##
## ## Why all three methods are one call, and why that is the honest shape rather than a stub
##
## A reviewer's first instinct here is that three identical bodies means two of them are
## unimplemented. They are not. **The aircraft has exactly one fitted part per category** — there
## is no provisional slot in `Build`, no second motor held to one side while you look at it. What
## distinguishes a preview from a commit from a restore is entirely what the SHELL does around the
## call: a preview leaves the overlay up and the snapshot held, a commit takes the overlay down,
## a restore takes it down and feeds back the record the finder was opened on.
##
## Writing three different bodies here would mean inventing a provisional-fit concept the physics
## does not have, and then keeping two fitting paths in step for the rest of the project's life.
## The three names still earn their place on the seam — they are what let `PartFinder` be tested
## against a recorder that CAN tell them apart, and what will let a later slice make a preview
## cheaper without the finder learning anything new.
##
## ## Why it drives a rail rather than a Build
##
## Fitting a part on this app's live build already has exactly one implementation, and it is
## `PartPicker.select_id()`: the rail emits `part_selected`, `LabScreen` rebuilds the aircraft,
## the panels re-render and the completeness ring moves. Reaching past that into `Build` would be
## a SECOND way to fit a part — one that the status line, the autosave and the 3D model do not
## hear about — which is the "two lists that were never the same list" defect with a different
## noun. So this class is four lines of body, and that is the measure of the seam being right.
##
## It holds the rail and not the shell for the reason `PartFinder` holds this and not a `Build`:
## an adapter that could reach the shell would grow, and the next slice would find its behaviour
## split across two files.

## The rail this adapter fits through. Public because the shell's checks assert against the same
## object they handed in, and a getter would be ceremony.
var rail: PartPicker


func _init(p_rail: PartPicker) -> void:
	rail = p_rail


## Arrowing. Provisional only in the builder's head — the drone on screen really is wearing it,
## which is §2's second defence and the entire reason browsing teaches anything.
func preview_part(part: Dictionary) -> void:
	_fit(part)


## Enter. Identical to a preview because a commit IS a preview that nothing takes back; the
## difference is the overlay closing and the snapshot being dropped, and both are the shell's.
func commit_part(part: Dictionary) -> void:
	_fit(part)


## Escape. The part handed in is the record the finder snapshotted when it opened, never the last
## thing previewed — `PartFinder.cancel()` owns that distinction and this end must not second-guess
## it by remembering a fit of its own.
func restore_part(part: Dictionary) -> void:
	_fit(part)


## `select_id` rather than `select_index`, because an index is into the rail's own FILTERED list
## and the finder's list is filtered by a different query. The id is the only thing the two lists
## agree about. It also clears the rail's filters when the part is real but hidden by them, which
## is what stops a finder commit failing silently against a rail somebody left narrowed.
func _fit(part: Dictionary) -> void:
	if rail == null:
		return
	var part_id := str(part.get("part_id", ""))
	if part_id == "":
		return
	if not rail.select_id(part_id):
		# By name, because the answer that means "this catalog does not have it" is the one case
		# `select_id` refuses rather than widening, and a finder row that fits nothing must not be
		# a no-op nobody can see.
		push_error("RailFitter: the %s rail has no part %s" % [rail.category, part_id])
