--[[--
One audio pipeline for every app (Gemma, messengers, …): play, repeat, history.

Any app hands it a clip, which is just something with a URL:

    local Audio = require("apps/kos/audiopipeline")
    Audio.play{ url = "http://…/reply-12.wav", title = "Gemma: reply 12", source = "gemma" }
    Audio.repeatLast()          -- play the last clip again (from the cache)
    Audio.recent()              -- newest first, kept across restarts

Where the audio comes out: playback is handed to Android's media player, so it
goes wherever Android sends sound, which is the Bluetooth headset or earbuds
when one is connected, otherwise the phone speaker.

Cache: the history (up to 50 clips) is saved, and a source can also give a
`file` (a local path) that is preferred over the URL when it exists.
]]

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local Audio = {
    max_history = 50,
}

local store
local function settings()
    if not store then
        store = LuaSettings:open(DataStorage:getSettingsDir() .. "/kos_audio.lua")
    end
    return store
end

function Audio.recent()
    return settings():readSetting("history") or {}
end

local function remember(clip)
    local list = Audio.recent()
    for i = #list, 1, -1 do
        if list[i].url == clip.url then table.remove(list, i) end
    end
    table.insert(list, 1, { url = clip.url, file = clip.file, title = clip.title, source = clip.source, time = os.time() })
    while #list > Audio.max_history do table.remove(list) end
    settings():saveSetting("history", list)
    settings():flush()
end

--- Plays a clip ({url=…, title=…, source=…, file=…}). Returns true if handed to a player.
function Audio.play(clip)
    if not clip or not (clip.url or clip.file) then return false end
    remember(clip)
    local link = clip.url
    if Device:canOpenLink() then
        local ok, err = pcall(Device.openLink, Device, link)
        if ok then
            Audio.last = clip
            return true
        end
        logger.warn("Audio: could not open", link, err)
    end
    UIManager:show(InfoMessage:new{
        text = _("No audio player available here.") .. "\n\n" .. (link or ""),
    })
    return false
end

function Audio.repeatLast()
    local clip = Audio.last or Audio.recent()[1]
    if not clip then
        UIManager:show(InfoMessage:new{ text = _("Nothing played yet."), timeout = 2 })
        return false
    end
    return Audio.play(clip)
end

--- A menu of recent clips, newest first (tap one to play it again).
function Audio.showRecent()
    local Menu = require("ui/widget/menu")
    local items = {}
    for _, clip in ipairs(Audio.recent()) do
        table.insert(items, {
            text = clip.title or clip.url,
            mandatory = clip.time and os.date("%H:%M", clip.time) or nil,
            callback = function() Audio.play(clip) end,
        })
    end
    if #items == 0 then
        UIManager:show(InfoMessage:new{ text = _("Nothing played yet."), timeout = 2 })
        return
    end
    local menu
    menu = Menu:new{
        title = _("Recently played"),
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        onMenuSelect = function(self_menu, item) item.callback() end,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
end

return Audio
