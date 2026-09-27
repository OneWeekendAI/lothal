class_name LothalVersion
extends RefCounted
## The one place the shipped version number lives.
##
## It is a constant in code rather than a read of ProjectSettings because the update check
## compares it against a number served from the internet, and a version that could be wrong
## is worse than no update check at all: too low and every launch nags about an update the
## user already has, too high and a real release is never offered. `package.sh` asserts this
## constant matches the tag being packaged and refuses to build otherwise, so the two cannot
## drift apart silently.

const CURRENT := "0.3.0"

## Where the signed release manifest lives. A Cloudflare hostname in front of the GCS bucket
## rather than the bucket's own URL, so the origin can be moved — to another bucket, another
## provider — without stranding every copy of Lothal already installed, which reads this string
## from a binary that was compiled before the move.
##
## CHANGING THIS STRANDS EVERY INSTALL THAT PREDATES THE CHANGE. It is compiled in, so an older
## copy of Lothal goes on asking the old address for ever and simply stops being offered
## updates — silently, because a failed check is indistinguishable from being up to date. The
## download URLs are NOT like this: they live inside the manifest and are re-signed every
## release, so payloads can move hosts freely. This one line is the only permanent commitment
## in the update channel, which is why it points at a hostname on a domain rather than at a
## bucket.
const MANIFEST_URL := "https://dl.meetdev.in/latest.json"

## Where "Contact us" in the tab row sends people.
##
## The same permanent commitment MANIFEST_URL carries: compiled in, so every installed copy opens
## this address for ever. A hostname on our own domain for that reason — the site can move hosts,
## this string cannot.
const CONTACT_URL := "https://lothal.meetdev.in"


## Compares two dotted versions. Returns -1 if `a` is older, 0 if equal, 1 if `a` is newer.
##
## This exists instead of a string comparison because string comparison is WRONG in a way that
## stays hidden for exactly nine releases: "0.10.0" < "0.9.0" lexicographically, so the tenth
## release of any series would be silently never offered to anybody. That is the single most
## likely bug in this file and tests/test_update_check.gd pins it directly.
##
## Missing components read as zero, so "1.2" and "1.2.0" compare equal. Non-numeric junk in a
## component reads as zero too rather than throwing — this parses a number that arrived over
## the network, and the caller's contract is that a malformed manifest offers no update (see
## UpdateCheck.parse_manifest), not that it crashes the app on launch.
static func compare(a: String, b: String) -> int:
	var left := a.strip_edges().split(".")
	var right := b.strip_edges().split(".")
	var count: int = maxi(left.size(), right.size())

	for i in count:
		var lv := 0
		var rv := 0
		if i < left.size() and left[i].is_valid_int():
			lv = int(left[i])
		if i < right.size() and right[i].is_valid_int():
			rv = int(right[i])
		if lv != rv:
			return -1 if lv < rv else 1

	return 0


## True when `candidate` is a well-formed dotted version of at least one component.
##
## Deliberately strict: the manifest's version drives a comparison against CURRENT, and a
## version of "" or "latest" would compare equal to "0.0.0" and quietly mean "no update
## forever". Better to reject the manifest outright than to act on a number nobody wrote.
static func is_well_formed(candidate: String) -> bool:
	var parts := candidate.strip_edges().split(".")
	if parts.is_empty() or parts.size() > 4:
		return false
	for part in parts:
		if not part.is_valid_int() or int(part) < 0:
			return false
	return true
