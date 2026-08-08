extends SceneTree
## Interop check: does a signature made by Node, with the real activation private key, verify
## in Godot against the real activation public key shipped in the binary?
##
## Everything else about this feature is tested with throwaway keys generated inside Godot, which
## proves the logic and proves nothing about the two sides agreeing. The failure this guards
## against — Node signing happily with a scheme Godot's Crypto.verify() does not implement, e.g.
## RSA-PSS instead of PKCS#1 v1.5 — would pass every other test in the suite and then reject
## every licence ever issued, on users' machines, after deploy.
##
##   node lothal-issue/functions/sign_fixture.js you@example.com > /tmp/lothal_licence.json
##   godot --headless --script res://tests/verify_interop.gd


func _init() -> void:
	var path := "/tmp/lothal_licence.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("INTEROP no fixture at %s" % path)
		quit(1)
		return

	var body := file.get_buffer(file.get_length())

	# No key argument: this is the PRODUCTION path, loading res://keys/activation_public.pem.
	var result := LicenceCheck.verify(body)
	print("INTEROP valid=%s email=%s reason=%s" % [result.valid, result.email, result.reason])

	# And the tamper case, through the same real key, so a "valid" above cannot be a verifier
	# that agrees with everything.
	var text := body.get_string_from_utf8()
	var tampered := text.replace("\\\"schema\\\":1", "\\\"schema\\\":2")
	var tampered_result := LicenceCheck.verify(tampered.to_utf8_buffer())
	print("INTEROP_TAMPERED changed=%s valid=%s reason=%s"
		% [tampered != text, tampered_result.valid, tampered_result.reason])

	quit(0 if result.valid and not tampered_result.valid else 1)
