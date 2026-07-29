class_name TestResult
extends RefCounted
## A single PASS/FAIL line: what was checked, whether it held, and the actual value
## for context when it didn't.

var name: String
var passed: bool
var detail: String

func _init(p_name: String, p_passed: bool, p_detail: String) -> void:
	name = p_name
	passed = p_passed
	detail = p_detail
