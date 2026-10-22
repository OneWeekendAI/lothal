extends Node
## Autoload: every tooltip in the app wraps at MAX_WIDTH instead of running off the window.
##
## The engine's tooltip is a Label with the `TooltipLabel` variation and no autowrap, so a long
## sentence becomes one line as wide as it needs. The engine builds it, so no Control can set it;
## catching it as it enters the tree is the one global lever. Custom tooltips that reuse the
## variation (part_finder.gd) are caught the same way.

const MAX_WIDTH := 480.0


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is Label and node.theme_type_variation == &"TooltipLabel":
		wrap_label(node)


## Wraps `label` only when its widest line exceeds MAX_WIDTH, so short tooltips keep their size.
static func wrap_label(label: Label) -> void:
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	var widest := 0.0
	for line in label.text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	if widest <= MAX_WIDTH:
		return
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = MAX_WIDTH
