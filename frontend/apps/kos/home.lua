-- Home folder lookup that works on every KOReader build.
-- Older builds have no filemanagerutil.getHomeFolder(), so never call it blindly.
local Home = {}

function Home.get()
    local ok, fmu = pcall(require, "apps/filemanager/filemanagerutil")
    if ok and type(fmu) == "table" and type(fmu.getHomeFolder) == "function" then
        local ok2, dir = pcall(fmu.getHomeFolder)
        if ok2 and type(dir) == "string" and dir ~= "" then return dir end
    end
    local dir
    if G_reader_settings and G_reader_settings.readSetting then
        dir = G_reader_settings:readSetting("home_dir")
    end
    if type(dir) ~= "string" or dir == "" then
        local okd, Device = pcall(require, "device")
        dir = okd and Device and Device.home_dir or nil
    end
    if type(dir) ~= "string" or dir == "" then
        local okp, DataStorage = pcall(require, "datastorage")
        dir = okp and DataStorage:getDataDir() or "."
    end
    return dir
end

return Home
