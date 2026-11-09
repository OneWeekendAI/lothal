class_name GeoTiff
extends RefCounted
## A minimal GeoTIFF reader: exactly what USGS 3DEP ImageServer `exportImage?format=tiff&pixelType=F32` returns, and the same
## in other layouts a hand-made file might use. Single band, UNCOMPRESSED (compression tag 1), strips or tiles, 16-bit
## signed/unsigned integer or 32-bit float samples, little- or big-endian. Anything else (LZW, deflate, multi-band, planar
## separate) returns {"ok": false, "error": ...} naming the unsupported feature rather than a wrong grid.
##
## Georeferencing: ModelPixelScale (33550) and ModelTiepoint (33922) with the tie at raster (0,0), in geographic degrees
## (EPSG:4326). GTRasterTypeGeoKey (1025) = 2 means pixel-is-point; the default is pixel-is-area (value at the cell centre).
## GDAL_NODATA (42113) is read as text. Rows run north to south.

const TAG_WIDTH := 256
const TAG_HEIGHT := 257
const TAG_BITS := 258
const TAG_COMPRESSION := 259
const TAG_SAMPLES := 277
const TAG_STRIP_OFFSETS := 273
const TAG_ROWS_PER_STRIP := 278
const TAG_STRIP_BYTES := 279
const TAG_PLANAR := 284
const TAG_TILE_W := 322
const TAG_TILE_H := 323
const TAG_TILE_OFFSETS := 324
const TAG_TILE_BYTES := 325
const TAG_SAMPLE_FORMAT := 339
const TAG_PIXEL_SCALE := 33550
const TAG_TIEPOINT := 33922
const TAG_GEOKEYS := 34735
const TAG_NODATA := 42113


class Raster extends RefCounted:
	var width := 0
	var height := 0
	var values := PackedFloat32Array()
	var west := 0.0          ## longitude of the raster's outer west edge (area) or first sample (point), degrees
	var north := 0.0
	var dx := 0.0            ## degrees per pixel (east)
	var dy := 0.0            ## degrees per pixel (south, positive)
	var nodata := NAN
	var point_is_area := true

	## Value at the sample (col,row); NAN for nodata.
	func at(col: int, row: int) -> float:
		var v := values[row * width + col]
		if is_nan(nodata) or v != nodata:
			return v
		return NAN

	func lon_of(col: int) -> float:
		return west + (float(col) + (0.5 if point_is_area else 0.0)) * dx

	func lat_of(row: int) -> float:
		return north - (float(row) + (0.5 if point_is_area else 0.0)) * dy

	func bbox() -> Rect2:     ## x = west, y = south, size = (east-west, north-south), degrees
		var east := west + float(width) * dx
		var south := north - float(height) * dy
		return Rect2(west, south, east - west, north - south)

	## Bilinear sample at a lat/lon between pixel centres. NAN outside the raster or touching a nodata cell.
	func sample(lat: float, lon: float) -> float:
		var fx := (lon - west) / dx - (0.5 if point_is_area else 0.0)
		var fy := (north - lat) / dy - (0.5 if point_is_area else 0.0)
		if fx < -1.0e-9 or fy < -1.0e-9 or fx > float(width - 1) + 1.0e-9 or fy > float(height - 1) + 1.0e-9:
			return NAN
		fx = clampf(fx, 0.0, float(width - 1))
		fy = clampf(fy, 0.0, float(height - 1))
		var c0 := mini(int(floor(fx)), width - 2) if width > 1 else 0
		var r0 := mini(int(floor(fy)), height - 2) if height > 1 else 0
		var c1 := mini(c0 + 1, width - 1)
		var r1 := mini(r0 + 1, height - 1)
		var tx := fx - float(c0)
		var ty := fy - float(r0)
		var v00 := at(c0, r0)
		var v10 := at(c1, r0)
		var v01 := at(c0, r1)
		var v11 := at(c1, r1)
		if is_nan(v00) or is_nan(v10) or is_nan(v01) or is_nan(v11):
			return NAN
		return lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), ty)


static func parse(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 8:
		return _err("too short to be a TIFF")
	var big := false
	if bytes[0] == 0x4D and bytes[1] == 0x4D:
		big = true
	elif not (bytes[0] == 0x49 and bytes[1] == 0x49):
		return _err("not a TIFF (bad byte-order mark)")
	if _u16(bytes, 2, big) != 42:
		return _err("not a classic TIFF (BigTIFF is unsupported)")
	var ifd := _u32(bytes, 4, big)
	if ifd + 2 > bytes.size():
		return _err("IFD offset outside the file")
	var count := _u16(bytes, ifd, big)
	var tags := {}
	for i in count:
		var e := ifd + 2 + i * 12
		if e + 12 > bytes.size():
			return _err("IFD truncated")
		var tag := _u16(bytes, e, big)
		var typ := _u16(bytes, e + 2, big)
		var n := _u32(bytes, e + 4, big)
		tags[tag] = {"type": typ, "count": n, "entry": e + 8}
	var width := _first(bytes, tags, TAG_WIDTH, big)
	var height := _first(bytes, tags, TAG_HEIGHT, big)
	var bits := _first(bytes, tags, TAG_BITS, big)
	var compression := _first(bytes, tags, TAG_COMPRESSION, big, 1)
	var samples := _first(bytes, tags, TAG_SAMPLES, big, 1)
	var fmt := _first(bytes, tags, TAG_SAMPLE_FORMAT, big, 1)
	if compression != 1:
		return _err("compression %d is unsupported (only uncompressed); request the tile with compression none" % compression)
	if samples != 1:
		return _err("%d samples per pixel is unsupported (single band only)" % samples)
	if _first(bytes, tags, TAG_PLANAR, big, 1) != 1:
		return _err("separate planes are unsupported")
	if not ((fmt == 3 and bits == 32) or ((fmt == 1 or fmt == 2) and bits == 16)):
		return _err("sample format %d at %d bits is unsupported (float32, int16 and uint16 only)" % [fmt, bits])
	if width <= 0 or height <= 0 or width * height > 64000000:
		return _err("raster size %d x %d is out of range" % [width, height])
	var r := Raster.new()
	r.width = width
	r.height = height
	r.values.resize(width * height)
	var bps := bits >> 3
	# pixel data: tiles or strips
	if tags.has(TAG_TILE_OFFSETS):
		var tw := _first(bytes, tags, TAG_TILE_W, big)
		var th := _first(bytes, tags, TAG_TILE_H, big)
		var offs := _array(bytes, tags, TAG_TILE_OFFSETS, big)
		var across := floori(float(width + tw - 1) / float(tw))
		for ti in offs.size():
			var tcol := ti % across
			var trow := floori(float(ti) / float(across))
			for y in th:
				var row := trow * th + y
				if row >= height:
					break
				for x in tw:
					var col := tcol * tw + x
					if col >= width:
						break
					var p: int = offs[ti] + (y * tw + x) * bps
					if p + bps > bytes.size():
						return _err("tile data truncated")
					r.values[row * width + col] = _sample(bytes, p, bits, fmt, big)
	elif tags.has(TAG_STRIP_OFFSETS):
		var offs2 := _array(bytes, tags, TAG_STRIP_OFFSETS, big)
		var rps := _first(bytes, tags, TAG_ROWS_PER_STRIP, big, height)
		for si in offs2.size():
			for y in rps:
				var row := si * rps + y
				if row >= height:
					break
				for x in width:
					var p2: int = offs2[si] + (y * width + x) * bps
					if p2 + bps > bytes.size():
						return _err("strip data truncated")
					r.values[row * width + x] = _sample(bytes, p2, bits, fmt, big)
	else:
		return _err("no strip or tile offsets")
	# georeferencing
	if not (tags.has(TAG_PIXEL_SCALE) and tags.has(TAG_TIEPOINT)):
		return _err("not georeferenced (no ModelPixelScale / ModelTiepoint)")
	var scale := _doubles(bytes, tags, TAG_PIXEL_SCALE, big)
	var tie := _doubles(bytes, tags, TAG_TIEPOINT, big)
	if scale.size() < 2 or tie.size() < 6:
		return _err("georeferencing tags are short")
	r.dx = scale[0]
	r.dy = scale[1]
	r.west = tie[3] - tie[0] * r.dx
	r.north = tie[4] + tie[1] * r.dy
	if tags.has(TAG_GEOKEYS):
		var keys := _array(bytes, tags, TAG_GEOKEYS, big)
		var k := 4
		while k + 3 < keys.size():
			if keys[k] == 1025 and keys[k + 3] == 2:
				r.point_is_area = false
			k += 4
	if tags.has(TAG_NODATA):
		var t: Dictionary = tags[TAG_NODATA]
		var off := _u32(bytes, t["entry"], big) if int(t["count"]) > 4 else int(t["entry"])
		var txt := bytes.slice(off, off + int(t["count"])).get_string_from_ascii().strip_edges()
		if txt.is_valid_float():
			r.nodata = float(txt)
	return {"ok": true, "error": "", "raster": r}


static func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "raster": null}


static func _u16(b: PackedByteArray, o: int, big: bool) -> int:
	return (b[o] << 8 | b[o + 1]) if big else (b[o + 1] << 8 | b[o])


static func _u32(b: PackedByteArray, o: int, big: bool) -> int:
	if big:
		return b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3]
	return b[o + 3] << 24 | b[o + 2] << 16 | b[o + 1] << 8 | b[o]


static func _value_at(b: PackedByteArray, typ: int, o: int, big: bool) -> int:
	if typ == 3:
		return _u16(b, o, big)
	return _u32(b, o, big)


static func _first(b: PackedByteArray, tags: Dictionary, tag: int, big: bool, fallback: int = 0) -> int:
	if not tags.has(tag):
		return fallback
	var t: Dictionary = tags[tag]
	return _value_at(b, int(t["type"]), int(t["entry"]), big)


## SHORT or LONG array: inline when it fits in the 4-byte value field, otherwise at the offset stored there.
static func _array(b: PackedByteArray, tags: Dictionary, tag: int, big: bool) -> Array:
	var t: Dictionary = tags[tag]
	var typ := int(t["type"])
	var size := 2 if typ == 3 else 4
	var n := int(t["count"])
	var base := int(t["entry"]) if n * size <= 4 else _u32(b, int(t["entry"]), big)
	var out: Array = []
	for i in n:
		out.append(_value_at(b, typ, base + i * size, big))
	return out


static func _doubles(b: PackedByteArray, tags: Dictionary, tag: int, big: bool) -> Array:
	var t: Dictionary = tags[tag]
	var base := _u32(b, int(t["entry"]), big)
	var out: Array = []
	for i in int(t["count"]):
		var buf := StreamPeerBuffer.new()
		buf.big_endian = big
		buf.data_array = b.slice(base + i * 8, base + i * 8 + 8)
		out.append(buf.get_double())
	return out


static func _sample(b: PackedByteArray, p: int, bits: int, fmt: int, big: bool) -> float:
	if bits == 32:
		var buf := StreamPeerBuffer.new()
		buf.big_endian = big
		buf.data_array = b.slice(p, p + 4)
		return buf.get_float()
	var v := _u16(b, p, big)
	if fmt == 2 and v >= 32768:
		v -= 65536
	return float(v)
