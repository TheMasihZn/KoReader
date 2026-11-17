--[[--
Triangle meshes for 3D printing: read and write STL, measure, check, and build simple shapes from a
script. No screen code, so it is tested on its own.

A mesh is a list of triangles; a triangle is { {x,y,z}, {x,y,z}, {x,y,z} }, in millimetres.

Measures (each is the formula the OS notes name for it):
  volume   V = (1/6) * sum over triangles of  a . (b x c)        (signed tetrahedra from the origin)
  area     A = (1/2) * sum over triangles of  |(b - a) x (c - a)|
  mass     m = rho * V, with rho in g/cm3 and V in mm3 / 1000
  overhang area of faces that face down steeper than the limit (default 45 degrees from vertical) and
           do not rest on the bed
Check "closed": every edge is used by exactly two triangles, which a printable solid needs.
]]

local Mesh = {}

local sqrt, abs, floor, cos, sin, pi = math.sqrt, math.abs, math.floor, math.cos, math.sin, math.pi

---------------------------------------------------------------------------
-- Reading and writing STL
---------------------------------------------------------------------------

local function isBinary(data)
    if #data < 84 then return false end
    local n = string.byte(data, 81) + string.byte(data, 82) * 256 + string.byte(data, 83) * 65536
        + string.byte(data, 84) * 16777216
    return 84 + n * 50 == #data
end

local function f32(data, pos)
    -- IEEE 754 single, little endian
    local b1, b2, b3, b4 = string.byte(data, pos, pos + 3)
    local sign = b4 >= 128 and -1 or 1
    local exp = (b4 % 128) * 2 + floor(b3 / 128)
    local man = (b3 % 128) * 65536 + b2 * 256 + b1
    if exp == 0 then return sign * man * 2 ^ -149 end
    if exp == 255 then return 0 end
    return sign * (1 + man / 8388608) * 2 ^ (exp - 127)
end

--- Parses STL text or bytes. Returns a mesh, or nil + a message.
function Mesh.parseSTL(data)
    local tris = {}
    if isBinary(data) then
        local n = string.byte(data, 81) + string.byte(data, 82) * 256 + string.byte(data, 83) * 65536
            + string.byte(data, 84) * 16777216
        for i = 0, n - 1 do
            local o = 85 + i * 50 + 12 -- skip the normal
            tris[#tris + 1] = {
                { f32(data, o), f32(data, o + 4), f32(data, o + 8) },
                { f32(data, o + 12), f32(data, o + 16), f32(data, o + 20) },
                { f32(data, o + 24), f32(data, o + 28), f32(data, o + 32) },
            }
        end
    else
        local v = {}
        for x, y, z in data:gmatch("vertex%s+([%-%+%d%.eE]+)%s+([%-%+%d%.eE]+)%s+([%-%+%d%.eE]+)") do
            v[#v + 1] = { tonumber(x), tonumber(y), tonumber(z) }
            if #v == 3 then tris[#tris + 1] = v; v = {} end
        end
        if #v ~= 0 then return nil, "the file ends in the middle of a triangle" end
    end
    if #tris == 0 then return nil, "no triangles found" end
    return tris
end

local function cross(ax, ay, az, bx, by, bz)
    return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

local function normal(t)
    local a, b, c = t[1], t[2], t[3]
    local nx, ny, nz = cross(b[1] - a[1], b[2] - a[2], b[3] - a[3], c[1] - a[1], c[2] - a[2], c[3] - a[3])
    local len = sqrt(nx * nx + ny * ny + nz * nz)
    if len == 0 then return 0, 0, 0, 0 end
    return nx / len, ny / len, nz / len, len
end
Mesh.normal = normal

--- STL as ASCII text (readable everywhere, larger than binary).
function Mesh.toSTL(mesh, name)
    local out = { "solid " .. (name or "design") .. "\n" }
    for _, t in ipairs(mesh) do
        local nx, ny, nz = normal(t)
        out[#out + 1] = string.format("facet normal %.6g %.6g %.6g\n outer loop\n", nx, ny, nz)
        for k = 1, 3 do
            out[#out + 1] = string.format("  vertex %.6g %.6g %.6g\n", t[k][1], t[k][2], t[k][3])
        end
        out[#out + 1] = " endloop\nendfacet\n"
    end
    out[#out + 1] = "endsolid " .. (name or "design") .. "\n"
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Measuring
---------------------------------------------------------------------------

function Mesh.bounds(mesh)
    local lo = { math.huge, math.huge, math.huge }
    local hi = { -math.huge, -math.huge, -math.huge }
    for _, t in ipairs(mesh) do
        for k = 1, 3 do
            for i = 1, 3 do
                local v = t[k][i]
                if v < lo[i] then lo[i] = v end
                if v > hi[i] then hi[i] = v end
            end
        end
    end
    return lo, hi
end

function Mesh.volume(mesh)
    local v = 0
    for _, t in ipairs(mesh) do
        local a, b, c = t[1], t[2], t[3]
        local x, y, z = cross(b[1], b[2], b[3], c[1], c[2], c[3])
        v = v + a[1] * x + a[2] * y + a[3] * z
    end
    return v / 6 -- mm3; negative means the triangles face inward
end

function Mesh.area(mesh)
    local s = 0
    for _, t in ipairs(mesh) do
        local _, _, _, len = normal(t)
        s = s + len / 2
    end
    return s
end

Mesh.MATERIALS = {
    { id = "pla", name = "PLA", density = 1.24 },
    { id = "petg", name = "PETG", density = 1.27 },
    { id = "abs", name = "ABS", density = 1.04 },
    { id = "resin", name = "Resin", density = 1.10 },
}

--- Mass in grams for a solid print of this volume (mm3) and density (g/cm3).
function Mesh.mass(volume_mm3, density)
    return abs(volume_mm3) / 1000 * density
end

local function key(v)
    local k = string.format("%.4f,%.4f,%.4f", v[1], v[2], v[3])
    return (k:gsub("%-0%.0000", "0.0000")) -- -0 and 0 are the same corner
end

--- Edge use count: returns total edges, edges used once or 3+ times (not printable), and the
-- feature edges (corners sharper than `angle_deg`) for drawing.
function Mesh.edges(mesh, angle_deg)
    local limit = cos((angle_deg or 30) * pi / 180)
    local map, order = {}, {}
    for i, t in ipairs(mesh) do
        local nx, ny, nz = normal(t)
        for k = 1, 3 do
            local a, b = t[k], t[k % 3 + 1]
            local ka, kb = key(a), key(b)
            local ek = ka < kb and (ka .. ";" .. kb) or (kb .. ";" .. ka)
            local e = map[ek]
            if not e then
                e = { a = a, b = b, n = 0, normals = {} }
                map[ek] = e
                order[#order + 1] = e
            end
            e.n = e.n + 1
            e.normals[#e.normals + 1] = { nx, ny, nz }
        end
    end
    local bad, feature = 0, {}
    for _, e in ipairs(order) do
        if e.n ~= 2 then
            bad = bad + 1
            feature[#feature + 1] = { e.a, e.b }
        else
            local p, q = e.normals[1], e.normals[2]
            if p[1] * q[1] + p[2] * q[2] + p[3] * q[3] < limit then feature[#feature + 1] = { e.a, e.b } end
        end
    end
    return #order, bad, feature
end

--- Area (mm2) of faces that point down more than `limit_deg` away from straight up, not touching the bed.
function Mesh.overhang(mesh, limit_deg)
    local lo = Mesh.bounds(mesh)
    local floor_z = lo[3]
    local c = cos((limit_deg or 45) * pi / 180)
    local total = 0
    for _, t in ipairs(mesh) do
        local _, _, nz, len = normal(t)
        if nz < -c then
            local zmax = math.max(t[1][3], t[2][3], t[3][3])
            if zmax > floor_z + 0.01 then total = total + len / 2 end
        end
    end
    return total
end

--- Everything a print needs to know, as one table.
function Mesh.report(mesh, density)
    local lo, hi = Mesh.bounds(mesh)
    local vol = Mesh.volume(mesh)
    local edges, bad = Mesh.edges(mesh, 30)
    return {
        triangles = #mesh,
        size = { hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3] },
        volume_mm3 = vol,
        area_mm2 = Mesh.area(mesh),
        mass_g = Mesh.mass(vol, density or 1.24),
        closed = bad == 0,
        open_edges = bad,
        inside_out = vol < 0,
        overhang_mm2 = Mesh.overhang(mesh, 45),
    }
end

---------------------------------------------------------------------------
-- Building shapes (for design scripts; every shape is a mesh in millimetres)
---------------------------------------------------------------------------

local function quad(a, b, c, d) return { { a, b, c }, { a, c, d } } end

--- A box with its corner at (x, y, z) and size w x d x h.
function Mesh.box(w, d, h, x, y, z)
    x, y, z = x or 0, y or 0, z or 0
    local p = {
        { x, y, z }, { x + w, y, z }, { x + w, y + d, z }, { x, y + d, z },
        { x, y, z + h }, { x + w, y, z + h }, { x + w, y + d, z + h }, { x, y + d, z + h },
    }
    local faces = {
        { 1, 4, 3, 2 }, { 5, 6, 7, 8 }, { 1, 2, 6, 5 }, { 2, 3, 7, 6 }, { 3, 4, 8, 7 }, { 4, 1, 5, 8 },
    }
    local m = {}
    for _, f in ipairs(faces) do
        for _, t in ipairs(quad(p[f[1]], p[f[2]], p[f[3]], p[f[4]])) do m[#m + 1] = t end
    end
    return m
end

--- A cylinder (or cone: r2) standing on z, centred on (x, y), with n sides.
function Mesh.cylinder(r, h, n, x, y, z, r2)
    n, x, y, z, r2 = n or 48, x or 0, y or 0, z or 0, r2 or r
    local m = {}
    local function ring(rad, zz, i)
        local a = 2 * pi * i / n
        return { x + rad * cos(a), y + rad * sin(a), zz }
    end
    local cb, ct = { x, y, z }, { x, y, z + h }
    for i = 0, n - 1 do
        local b0, b1 = ring(r, z, i), ring(r, z, i + 1)
        local t0, t1 = ring(r2, z + h, i), ring(r2, z + h, i + 1)
        m[#m + 1] = { cb, b1, b0 }
        m[#m + 1] = { ct, t0, t1 }
        m[#m + 1] = { b0, b1, t1 }
        m[#m + 1] = { b0, t1, t0 }
    end
    return m
end

--- Several meshes as one (printing them overlapping is fine for a slicer; no boolean cut).
function Mesh.join(...)
    local m = {}
    for _, part in ipairs({ ... }) do
        for _, t in ipairs(part) do m[#m + 1] = t end
    end
    return m
end

function Mesh.move(mesh, dx, dy, dz)
    local m = {}
    for i, t in ipairs(mesh) do
        m[i] = {}
        for k = 1, 3 do m[i][k] = { t[k][1] + dx, t[k][2] + dy, t[k][3] + dz } end
    end
    return m
end

--- Runs a design script (Lua text) with only the shape builders and maths available. The script returns a
-- mesh. Returns the mesh, or nil + the error.
function Mesh.runScript(text)
    local env = { math = math, string = string, table = table, ipairs = ipairs, pairs = pairs,
        tonumber = tonumber, tostring = tostring, pi = pi, box = Mesh.box, cylinder = Mesh.cylinder,
        join = Mesh.join, move = Mesh.move }
    local chunk, err
    if setfenv and loadstring then
        chunk, err = loadstring(text, "=design")
        if chunk then setfenv(chunk, env) end
    else
        chunk, err = load(text, "=design", "t", env)
    end
    if not chunk then return nil, err end
    local ok, result = pcall(chunk)
    if not ok then return nil, tostring(result) end
    if type(result) ~= "table" or #result == 0 then return nil, "the script must return a mesh" end
    return result
end

---------------------------------------------------------------------------
-- Looking at it: rotate and project
---------------------------------------------------------------------------

--- Rotation matrix for yaw (around z) then pitch (around x), in degrees.
function Mesh.rotation(yaw_deg, pitch_deg)
    local y, p = yaw_deg * pi / 180, pitch_deg * pi / 180
    local cy, sy, cp, sp = cos(y), sin(y), cos(p), sin(p)
    return {
        { cy, -sy, 0 },
        { sy * cp, cy * cp, -sp },
        { sy * sp, cy * sp, cp },
    }
end

--- Projects 3D points to a `size` x `size` square (orthographic), fitted to the mesh. Returns a function
-- that maps {x,y,z} to pixel x, y, and the depth.
function Mesh.projector(mesh, yaw, pitch, size, zoom)
    local R = Mesh.rotation(yaw, pitch)
    local lo, hi = Mesh.bounds(mesh)
    local cx, cy, cz = (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2
    local radius = sqrt((hi[1] - lo[1]) ^ 2 + (hi[2] - lo[2]) ^ 2 + (hi[3] - lo[3]) ^ 2) / 2
    if radius == 0 then radius = 1 end
    local scale = (size / 2) / radius * 0.92 * (zoom or 1)
    return function(p)
        local x, y, z = p[1] - cx, p[2] - cy, p[3] - cz
        local rx = R[1][1] * x + R[1][2] * y + R[1][3] * z
        local ry = R[2][1] * x + R[2][2] * y + R[2][3] * z
        local rz = R[3][1] * x + R[3][2] * y + R[3][3] * z
        return size / 2 + rx * scale, size / 2 - rz * scale, ry
    end
end

return Mesh
