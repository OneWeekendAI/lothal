class_name HarnessHistory
extends RefCounted
## Undo and redo for the Power room: two stacks of whole-override-table snapshots.
##
## `BladeHistory` again, and deliberately so — the third room to want this and the third to answer
## it the same way. A harness document is a sparse dictionary of at most six entries, so a full
## snapshot costs nothing, while an inverse-operation table would be a second implementation of
## `Harness.set_value` and `Harness.clear` that could silently disagree with the forward version.
##
## THE SNAPSHOT IS THE DICTIONARY, DUPLICATED. `Harness.overrides()` already returns a copy, and
## that copy is what goes on the stack for `FrameHistory`'s stated correctness reason: the room
## edits its harness in place, so storing a live reference would put the current override table on
## the stack and every later edit would rewrite the memory of how it used to be. That bug reads as
## "there was nothing to undo", which is why `tests/test_power_room.gd` undoes TWICE.
##
## ## Why this is not `BladeHistory` with a different type on it
##
## Because the thing being snapshotted is a plain Dictionary rather than an object with a
## `to_dictionary()`, and GDScript has no generics to express "history of T". A shared base would
## be an abstract class with one method in it and two subclasses that each override that method to
## call a differently-named serialiser — more machinery than the twenty lines it would save.

## How far back the room can step. `FrameHistory.MAX_DEPTH`'s number and its reason, reached the
## way `BladeHistory` reaches it: the same policy one room over, and a second number would be two
## answers to one question.
const MAX_DEPTH := FrameHistory.MAX_DEPTH

var _undone: Array = []
var _redone: Array = []


## Remembers the override table as it is NOW, before the edit that is about to happen.
##
## BEFORE, not after: a caller that records afterwards has a stack that is always one edit behind
## and every entry in it is a state the builder never saw.
func record(overrides: Dictionary) -> void:
	_undone.append(overrides.duplicate())
	if _undone.size() > MAX_DEPTH:
		_undone.remove_at(0)
	_redone.clear()


func can_undo() -> bool:
	return not _undone.is_empty()


func can_redo() -> bool:
	return not _redone.is_empty()


## The table as it was before the most recent recorded edit, with the current one put aside so
## `redo()` can bring it back. Returns `current` itself when there is nothing to undo, so a caller
## can always assign the result.
func undo(current: Dictionary) -> Dictionary:
	if _undone.is_empty():
		return current
	_redone.append(current.duplicate())
	return _undone.pop_back()


## The state an `undo()` stepped out of. Symmetric with the above, so undo and redo walk the same
## line in opposite directions rather than redo being a one-way door.
func redo(current: Dictionary) -> Dictionary:
	if _redone.is_empty():
		return current
	_undone.append(current.duplicate())
	return _redone.pop_back()


## Forgets everything, both ways. For opening a different aircraft: an undo that reached across a
## part change would put a cinelifter's 12 AWG trunk on a whoop.
func clear() -> void:
	_undone.clear()
	_redone.clear()


func depth() -> int:
	return _undone.size()


func redo_depth() -> int:
	return _redone.size()
