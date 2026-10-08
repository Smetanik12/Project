class_name ChunkMesher
extends RefCounted
## Массивы мешей чанка: рельеф (с «юбкой» по краю, чтобы не было щелей) и вода.
## Только вычисления — можно звать из рабочего потока, меш создаётся в главном.

const T := Planet.TILE_M
const SKIRT := 6.0


## Рельеф: вершины в углах тайлов, нормали по высотам с каймой (без швов между чанками).
## Диагональ квадрата выбирается вдоль меньшего перепада — склоны получаются ровнее.
static func terrain_arrays(c: Chunk) -> Array:
	var n := Chunk.N
	var vn := n + 1
	var rn := n + 3
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(vn * vn)
	norms.resize(vn * vn)
	for vy in vn:
		for vx in vn:
			var i := vy * vn + vx
			verts[i] = Vector3(vx * T, c.hgt[i], vy * T)
			var hl := c.hgt_ring[(vy + 1) * rn + vx]
			var hr := c.hgt_ring[(vy + 1) * rn + vx + 2]
			var hu := c.hgt_ring[vy * rn + vx + 1]
			var hd := c.hgt_ring[(vy + 2) * rn + vx + 1]
			norms[i] = Vector3(hl - hr, 2.0 * T, hu - hd).normalized()
	for ty in n:
		for tx in n:
			var a := ty * vn + tx
			var b := a + 1
			var cc := a + vn
			var d := cc + 1
			if absf(c.hgt[a] - c.hgt[d]) < absf(c.hgt[b] - c.hgt[cc]):
				idx.append_array(PackedInt32Array([a, b, d, a, d, cc]))
			else:
				idx.append_array(PackedInt32Array([a, b, cc, b, d, cc]))
	# юбка по периметру
	var edge: Array = []
	for vx in vn:
		edge.append(vx)
	for vy in range(1, vn):
		edge.append(vy * vn + n)
	for vx in range(n - 1, -1, -1):
		edge.append(n * vn + vx)
	for vy in range(n - 1, 0, -1):
		edge.append(vy * vn)
	edge.append(0)
	var base := verts.size()
	for k in edge.size():
		var i: int = edge[k]
		verts.append(verts[i] - Vector3(0, SKIRT, 0))
		norms.append(norms[i])
	for k in edge.size() - 1:
		var a: int = edge[k]
		var b: int = edge[k + 1]
		var a2 := base + k
		var b2 := base + k + 1
		idx.append_array(PackedInt32Array([a, a2, b, b, a2, b2]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Вода: квадраты над тайлами с уровнем воды; высота вершины — среднее по соседним водным тайлам,
## поэтому поверхность реки плавная, а плоскость заходит под берег без щелей.
static func water_arrays(c: Chunk) -> Array:
	var n := Chunk.N
	var vn := n + 1
	var lvl := PackedFloat32Array()
	lvl.resize(vn * vn)
	var cnt := PackedByteArray()
	cnt.resize(vn * vn)
	var any := false
	for ty in n:
		for tx in n:
			var w := c.water[ty * n + tx]
			if w <= Chunk.NO_WATER:
				continue
			any = true
			for o: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				var vi := (ty + o.y) * vn + tx + o.x
				lvl[vi] += w
				cnt[vi] += 1
	if not any:
		return []
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var map := PackedInt32Array()
	map.resize(vn * vn)
	map.fill(-1)
	for vi in vn * vn:
		if cnt[vi] > 0:
			map[vi] = verts.size()
			var vx := vi % vn
			var vy := vi / vn
			verts.append(Vector3(vx * T, lvl[vi] / cnt[vi], vy * T))
			uvs.append(Vector2(c.ox + vx, c.oy + vy))
	for ty in n:
		for tx in n:
			if c.water[ty * n + tx] <= Chunk.NO_WATER:
				continue
			var a := map[ty * vn + tx]
			var b := map[ty * vn + tx + 1]
			var cc := map[(ty + 1) * vn + tx]
			var d := map[(ty + 1) * vn + tx + 1]
			idx.append_array(PackedInt32Array([a, b, d, a, d, cc]))
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	return arr
