--[[--
Folder per file. `/a/something.jpg` becomes `/a/something/something.jpg` with a plain text note beside it,
`/a/something/something.jpg.md`: what the file is, where it came from, and the entropy of its bytes in LaTeX.
Several files with the same base name (a.jpg, a.png) share one folder `a`.

    FolderFile.plan(path)            -> { folder, file, meta }            nothing is touched
    FolderFile.wrap(path, fs)        -> ok, planOrError                   moves the file, writes the note; refuses to overwrite
    FolderFile.unwrap(path, fs)      -> ok                                puts the file back; the note and folder stay (nothing is lost)

`fs` is { exists, mkdir, rename, read, write, size } so it can be tested; the default uses lfs and io.
The note is written first and the file moved second; if the move fails the note is removed again.
Departure from the usual way: one folder per file multiplies directories (each needs an inode and a directory entry),
makes the path longer by the name once more, and breaks tools that expect a flat folder. Gain: every file explains itself.
]]

local Entropy = require("apps/kos/entropycalc")
local F = {}

local function split(path)
    local dir, name = path:match("^(.*)/([^/]+)$")
    if not dir then return nil end
    local base = name:match("^(.+)%.[^%.]+$") or name
    return dir, name, base
end

function F.plan(path)
    local dir, name, base = split(path)
    if not dir then return nil, "not a path" end
    local folder = dir .. "/" .. base
    return { folder = folder, file = folder .. "/" .. name, meta = folder .. "/" .. name .. ".md", from = path, name = name }
end

local function defaultFs()
    local lfs = require("libs/libkoreader-lfs")
    return {
        exists = function(p) return lfs.attributes(p, "mode") ~= nil end,
        mkdir = function(p) return lfs.mkdir(p) end,
        rename = function(a, b) return os.rename(a, b) end,
        read = function(p, n) local f = io.open(p, "rb"); if not f then return nil end local s = f:read(n or "*a"); f:close(); return s end,
        write = function(p, s) local f = io.open(p, "wb"); if not f then return false end f:write(s); f:close(); return true end,
        remove = function(p) return os.remove(p) end,
        size = function(p) return lfs.attributes(p, "size") end,
    }
end

function F.note(plan, sample, size)
    local h = Entropy.bytes(sample or "")
    return table.concat({
        "---",
        "name: " .. plan.name,
        "kind: file note",
        "moved from: " .. plan.from,
        "size: " .. tostring(size or "?") .. " bytes",
        "entropy: Shannon stand-in for Framal Entropy (sampled over the first " .. #(sample or "") .. " bytes)",
        "---",
        "",
        "This folder holds one file and this note. Write what the file is for below; the machine part is above.",
        "",
        "## Entropy of the bytes",
        Entropy.latex(h, 8),
        "",
    }, "\n")
end

function F.wrap(path, fs)
    fs = fs or defaultFs()
    local plan, err = F.plan(path)
    if not plan then return false, err end
    if not fs.exists(path) then return false, "no such file" end
    if fs.exists(plan.file) then return false, "target already exists: " .. plan.file end
    if fs.exists(plan.meta) then return false, "note already exists: " .. plan.meta end
    if fs.exists(plan.folder) and fs.read(plan.folder) then end
    if not fs.exists(plan.folder) then
        if not fs.mkdir(plan.folder) then return false, "could not make " .. plan.folder end
    end
    local sample = fs.read(path, 1048576)
    if not fs.write(plan.meta, F.note(plan, sample, fs.size(path))) then return false, "could not write the note" end
    if not fs.rename(path, plan.file) then
        if fs.remove then fs.remove(plan.meta) end
        return false, "could not move the file"
    end
    return true, plan
end

function F.unwrap(path, fs)
    fs = fs or defaultFs()
    local dir, name = split(path)       -- path is the file inside its folder: /a/something/something.jpg
    if not dir then return false, "not a path" end
    local parent = dir:match("^(.*)/[^/]+$")
    if not parent then return false, "no parent folder" end
    local back = parent .. "/" .. name
    if fs.exists(back) then return false, "something is already at " .. back end
    if not fs.rename(path, back) then return false, "could not move back" end
    return true
end

return F
