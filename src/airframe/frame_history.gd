class_name FrameHistory
extends RefCounted
## Undo for the plan editor: a stack of whole-document snapshots.
##
## ## Why whole snapshots and not a command log
##
## The textbook answer is an undoable-command pattern — each edit knows how to invert itself. It is
## the right shape for a large document and the wrong one here, for a measurable reason: a frame is
## a handful of polygons, a few hundred doubles, and a full snapshot costs microseconds to take and
## kilobytes to hold. Against that, an inverse-operation table is a second implementation of every
## edit in `FrameEdits`, each of which can disagree with its forward version — and a wrong inverse
## does not crash, it silently leaves the geometry slightly different from where it was, which is
## the one failure this feature exists to prevent.
##
## So: snapshot in, snapshot out, and `FrameEdits` stays a set of one-way functions with nothing to
## keep in sync.
##
## ## The snapshot is a SERIALISED copy, and that is the whole correctness argument
##
## `record()` stores `to_dictionary()`, not the document. Storing the object would put the live
## frame on the stack: every later edit would mutate the thing that was supposed to be the memory of
## how it used to be, and undo would restore the present. That bug looks like it works — the first
## undo appears to do nothing, which reads as "there was nothing to undo" — and
## `test_frame_edits.gd` catches it by undoing twice.
##
## Going through the same dictionary a SAVE goes through also means an undone frame is one that
## could have been written to disk and read back: outlines stay float64, unknown fields survive, and
## there is no second copying path that could quietly drop something `save_to` keeps.

## How many steps back the editor can go. Bounded because a long drag can record many edits and an
## unbounded stack is a slow leak; sixty-four is far past what anybody undoes by hand and still a
## trivial amount of memory for documents this size.
const MAX_DEPTH := 64

var _snapshots: Array = []


## Remembers the document as it is NOW, before the edit that is about to happen.
##
## Called before the change rather than after it, which is what makes `undo()` return the state a
## builder remembers. A caller that records afterwards gets an undo stack that is always one edit
## behind, and every entry in it is a state the builder never saw.
func record(document: AirframeDocument) -> void:
	if document == null:
		return
	_snapshots.append(document.to_dictionary())
	if _snapshots.size() > MAX_DEPTH:
		_snapshots.remove_at(0)


func can_undo() -> bool:
	return not _snapshots.is_empty()


## The document as it was before the most recent recorded edit.
##
## Returns a NEW document and leaves the one passed in untouched, so a caller that keeps a reference
## to the old object does not find it mutating underneath them. `current` is returned unchanged when
## there is nothing to undo, so a caller can always assign the result.
func undo(current: AirframeDocument) -> AirframeDocument:
	if _snapshots.is_empty():
		return current
	return AirframeDocument.from_dictionary(_snapshots.pop_back())


## Forgets everything. For opening a different frame: the previous frame's history is not this
## frame's, and an undo that reached across a file open would replace the document with an unrelated
## one.
func clear() -> void:
	_snapshots.clear()


func depth() -> int:
	return _snapshots.size()
