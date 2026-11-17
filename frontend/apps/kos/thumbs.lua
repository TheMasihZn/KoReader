--[[--
Thumbnails: a small picture of what is inside a file, made only when asked for,
kept in ONE shared cache with a size cap, oldest removed first.

    local Thumbs = require("apps/kos/thumbs")
    local bb = Thumbs.get("/sdcard/photo.jpg", 96)   -- blitbuffer or nil
    Thumbs.textSnippet("/sdcard/notes.txt", 8)       -- first lines, for text files
    Thumbs.cacheInfo()                               -- { files, bytes, cap }
    Thumbs.clear()

Cache: <data>/cache/kosThumbs/<key>.png. Cap: setting `kos_thumb_cache_mb` (default 100).
Nothing is made up front: a folder with 5000 files costs nothing until you look at one.
]]

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local Thumbs = {}

local IMAGE_EXT = { jpg = true, jpeg = true, png = true, gif = true, bmp = true, webp = true, tif = true, tiff = true }
local DOC_EXT = { epub = true, pdf = true, djvu = true, cbz = true, fb2 = true, mobi = true, azw3 = true }
local TEXT_EXT = { txt = true, md = true, lua = true, log = true, csv = true, tex = true, json = true, py = true, ini = true, conf = true, sh = true }

function Thumbs.dir()
    local d = DataStorage:getDataDir() .. "/cache/kosThumbs"
    if lfs.attributes(d, "mode") ~= "directory" then
        lfs.mkdir(DataStorage:getDataDir() .. "/cache")
        lfs.mkdir(d)
    end
    return d
end

function Thumbs.kind(file)
    local ext = (file:match("%.([^./]+)$") or ""):lower()
    if IMAGE_EXT[ext] then return "image" end
    if DOC_EXT[ext] then return "doc" end
    if TEXT_EXT[ext] then return "text" end
    return nil
end

--- Cache key: changes when the file or the wanted size changes.
function Thumbs.key(file, px, mtime, size)
    local s = table.concat({ file, tostring(mtime or 0), tostring(size or 0), tostring(px) }, "|")
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x%04x", h, #s % 65536)
end

function Thumbs.capBytes()
    local mb = G_reader_settings and G_reader_settings:readSetting("kos_thumb_cache_mb") or 100
    return mb * 1024 * 1024
end

function Thumbs.cacheInfo()
    local dir, files, bytes = Thumbs.dir(), 0, 0
    for name in lfs.dir(dir) do
        if name:match("%.png$") then
            local a = lfs.attributes(dir .. "/" .. name)
            if a then files = files + 1 bytes = bytes + a.size end
        end
    end
    return { files = files, bytes = bytes, cap = Thumbs.capBytes() }
end

--- Removes the oldest files until the cache fits under the cap.
function Thumbs.trim(extra_free)
    local dir, list, total = Thumbs.dir(), {}, 0
    for name in lfs.dir(dir) do
        if name:match("%.png$") then
            local a = lfs.attributes(dir .. "/" .. name)
            if a then list[#list + 1] = { path = dir .. "/" .. name, t = a.access or a.modification, size = a.size } total = total + a.size end
        end
    end
    local limit = Thumbs.capBytes() - (extra_free or 0)
    if total <= limit then return 0 end
    table.sort(list, function(a, b) return a.t < b.t end)
    local removed = 0
    for _, f in ipairs(list) do
        if total <= limit then break end
        if os.remove(f.path) then total = total - f.size removed = removed + 1 end
    end
    return removed
end

function Thumbs.clear()
    local dir, n = Thumbs.dir(), 0
    for name in lfs.dir(dir) do
        if name:match("%.png$") and os.remove(dir .. "/" .. name) then n = n + 1 end
    end
    return n
end

local function render(file, kind, px)
    local RenderImage = require("ui/renderimage")
    if kind == "image" then
        return RenderImage:renderImageFile(file, false, px, px)
    end
    if kind == "doc" then
        local DocumentRegistry = require("document/documentregistry")
        local doc = DocumentRegistry:openDocument(file)
        if not doc then return nil end
        local bb
        local ok = pcall(function()
            if doc.getCoverPageImage then bb = doc:getCoverPageImage() end
        end)
        pcall(function() doc:close() end)
        if ok and bb then return RenderImage:scaleBlitBuffer(bb, px, px, true) end
    end
    return nil
end

--- A blitbuffer no bigger than px x px, or nil when this kind of file has no picture.
function Thumbs.get(file, px)
    local kind = Thumbs.kind(file)
    if not kind or kind == "text" then return nil end
    local attr = lfs.attributes(file)
    if not attr or attr.mode ~= "file" then return nil end
    local cached = Thumbs.dir() .. "/" .. Thumbs.key(file, px, attr.modification, attr.size) .. ".png"
    local RenderImage = require("ui/renderimage")
    if lfs.attributes(cached, "mode") == "file" then
        local ok, bb = pcall(RenderImage.renderImageFile, RenderImage, cached, false, px, px)
        if ok and bb then
            pcall(lfs.touch, cached) -- recently used: removed last
            return bb
        end
    end
    local ok, bb = pcall(render, file, kind, px)
    if not ok or not bb then
        if not ok then logger.warn("kos thumbs:", file, bb) end
        return nil
    end
    pcall(function()
        Thumbs.trim(bb:getWidth() * bb:getHeight())
        bb:writePNG(cached)
    end)
    return bb
end

--- First `n` lines of a text file (cut to 120 chars each), or nil.
function Thumbs.textSnippet(file, n)
    local f = io.open(file, "r")
    if not f then return nil end
    local lines = {}
    for line in f:lines() do
        lines[#lines + 1] = line:sub(1, 120)
        if #lines >= n then break end
    end
    f:close()
    if #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

return Thumbs
