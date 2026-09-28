class_name BackdropHills
extends RefCounted
## Rolling hills around the flyable field — scenery only. They are drawn and never collided with:
## nothing here is read by `Terrain.height_at` or `TerrainMesh.build_collider`, so the physics of
## a site is exactly what it was. The hills start low at a margin past the field's edge and rise
## to small mountains toward the horizon.

const RADIUS_M := 450.0
const STEP_M := 6.0
## Flat grass apron between the field's edge and the first rise.
const APRON_M := 25.0
const PEAK_M := 70.0


static func build_mesh(p_terrain: Terrain) -> ArrayMesh:
	var terrain := p_terrain if p_terrain != null else Terrain.flat(Terrain.DEFAULT_WIDTH_M, Terrain.DEFAULT_LENGTH_M)
	var half := terrain.half_extent()
	var c := terrain.center()
	var n := int(ceil(RADIUS_M * 2.0 / STEP_M))
	var cols := n + 1
	var grid := PackedVector3Array()
	grid.resize(cols * cols)
	for row in range(cols):
		for col in range(cols):
			var x := c.x - RADIUS_M + col * STEP_M
			var z := c.y - RADIUS_M + row * STEP_M
			grid[row * cols + col] = Vector3(x, _height(x - c.x, z - c.y, half), z)

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(n):
		for col in range(n):
			var a := grid[row * cols + col]
			var b := grid[row * cols + col + 1]
			var cc := grid[(row + 1) * cols + col]
			var d := grid[(row + 1) * cols + col + 1]
			# Skip cells that lie entirely under the field; the field draws its own ground there.
			if _inside(a, c, half) and _inside(b, c, half) and _inside(cc, c, half) and _inside(d, c, half):
				continue
			# Same winding as TerrainMesh's floor: a, c, b and c, d, b face +y.
			tool.add_vertex(a); tool.add_vertex(cc); tool.add_vertex(b)
			tool.add_vertex(cc); tool.add_vertex(d); tool.add_vertex(b)
	tool.generate_normals()
	return tool.commit()


static func _inside(p: Vector3, c: Vector2, half: Vector2) -> bool:
	return absf(p.x - c.x) < half.x and absf(p.z - c.y) < half.y


## Height at an offset from the field centre: slightly below zero on the apron (so it never
## fights the field's own floor), then noise hills that grow with distance.
static func _height(dx: float, dz: float, half: Vector2) -> float:
	var out_x := maxf(0.0, absf(dx) - half.x)
	var out_z := maxf(0.0, absf(dz) - half.y)
	var d := Vector2(out_x, out_z).length()
	var rise := smoothstep(APRON_M, APRON_M + 70.0, d)
	var hills := _fbm(dx * 0.012, dz * 0.012)
	var ridges := _fbm(dx * 0.004 + 11.0, dz * 0.004 - 3.0)
	var h := rise * (hills * 0.45 + ridges * ridges * 1.1) * PEAK_M
	# A raised rim at the ring's edge, so a low camera never sees sky under the far hills.
	var rim := smoothstep(RADIUS_M - 150.0, RADIUS_M, maxf(absf(dx), absf(dz)))
	h += rim * (25.0 + hills * 30.0)
	return h - 0.15


static func _hash(x: int, z: int) -> float:
	var h := (x * 374761393 + z * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


static func _noise(x: float, z: float) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var fx := x - ix
	var fz := z - iz
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uz := fz * fz * (3.0 - 2.0 * fz)
	return lerpf(lerpf(_hash(ix, iz), _hash(ix + 1, iz), ux),
		lerpf(_hash(ix, iz + 1), _hash(ix + 1, iz + 1), ux), uz)


static func _fbm(x: float, z: float) -> float:
	var v := 0.0
	var a := 0.5
	for i in 4:
		v += a * _noise(x, z)
		x *= 2.03
		z *= 2.03
		a *= 0.5
	return v
