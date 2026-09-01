class_name BladeHistory
extends RefCounted
## Undo and redo for the Propulsion room: two stacks of whole-document snapshots.
##
## ## Why this is `FrameHistory` again rather than something cleverer
##
## The airframe designer already answered this question and the answer transfers without an
## argument: a blade document is a name, nine scalars and two flat tables of a few dozen doubles,
## so a full `to_dictionary()` snapshot costs microseconds and kilobytes, while an inverse-operation
## table would be a second implementation of every function in `PlanformEdits` — each of which can
## silently disagree with its forward version and leave the planform slightly off rather than
## crash. Snapshots in, snapshots out, and `PlanformEdits` stays a set of one-way pure functions.
##
## The snapshot is the SERIALISED form for `FrameHistory`'s own correctness reason: the room edits
## its document in place, so storing the object would put the live blade on the stack and every
## later drag would mutate the memory of how it used to be. That bug reads as "there was nothing to
## undo", so the checks in `test_propulsion_room.gd` undo TWICE.
##
## ## The one thing this has that `FrameHistory` does not
##
## A redo stack. Not because the propulsion room deserves more than the airframe room, but because
## the gesture it exists for is different: a blade is drawn by pushing a station and looking at the
## section, and "put it back, I want to see that again" is half of that loop. `FrameHistory` can
## grow the same two methods the day the frame designer wants them; nothing here is blade-shaped.
##
## Redo is cleared by `record()`, which is the standard and the only self-consistent choice: once a
## new edit is made from an undone state, the states that used to lie ahead belong to a branch
## nobody can reach any more, and offering to redo into one would jump the document sideways.

## How far back the room can step. `FrameHistory.MAX_DEPTH`'s number and its reason — well past what
## anyone undoes by hand, and a bound so a long session cannot leak. Not a new free constant: it is
## the same policy one room over, and a second number would be two answers to one question.
const MAX_DEPTH := FrameHistory.MAX_DEPTH

var _undone: Array = []
var _redone: Array = []


## Remembers the document as it is NOW, before the edit that is about to happen.
##
## BEFORE, not after: a caller that records afterwards has a stack that is always one edit behind
## and every entry in it is a state the builder never saw.
func record(document: PropellerDocument) -> void:
	if document == null:
		return
	_undone.append(document.to_dictionary())
	if _undone.size() > MAX_DEPTH:
		_undone.remove_at(0)
	_redone.clear()


func can_undo() -> bool:
	return not _undone.is_empty()


func can_redo() -> bool:
	return not _redone.is_empty()


## The document as it was before the most recent recorded edit, with the current one put aside so
## `redo()` can bring it back. Returns a NEW document and leaves `current` untouched; returns
## `current` itself when there is nothing to undo, so a caller can always assign the result.
func undo(current: PropellerDocument) -> PropellerDocument:
	if _undone.is_empty():
		return current
	if current != null:
		_redone.append(current.to_dictionary())
	return PropellerDocument.from_dictionary(_undone.pop_back())


## The state an `undo()` stepped out of. Symmetric with the above: the document being left is pushed
## back onto the undo stack, so undo and redo walk the same line in opposite directions rather than
## redo being a one-way door.
func redo(current: PropellerDocument) -> PropellerDocument:
	if _redone.is_empty():
		return current
	if current != null:
		_undone.append(current.to_dictionary())
	return PropellerDocument.from_dictionary(_redone.pop_back())


## Forgets everything, both ways. For opening a different blade: an undo that reached across an
## open would replace the blade on screen with an unrelated propeller's shape.
func clear() -> void:
	_undone.clear()
	_redone.clear()


func depth() -> int:
	return _undone.size()


func redo_depth() -> int:
	return _redone.size()
