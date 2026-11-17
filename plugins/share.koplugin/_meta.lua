local _ = require("gettext")
return {
    fullname = _("Share"),
    description = _([[Send files to your laptop's shared folder and fetch files from it, over Wi-Fi. Uses the same laptop address and PIN as the Gemma app. Also adds "Send to laptop" to a file's long-press menu.]]),
    app = {
        needs = {
            { name = _("A laptop running the Gemma bridge (set its address in the Gemma app)"),
              ok = function()
                  local ok, LuaSettings = pcall(require, "luasettings")
                  if not ok then return false end
                  local s = LuaSettings:open(require("datastorage"):getSettingsDir() .. "/kos_gemma.lua")
                  return s:readSetting("host") ~= nil
              end },
        },
        icon = "appbar.filebrowser",
        order = 7,
    },
}
