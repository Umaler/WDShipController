local shell = require('shell')

local repo = "https://raw.githubusercontent.com/Umaler/WDShipController/refs/heads/"
local branch = "master"

local function getFileURL(fileName)
    return string.format("%s%s/%s", repo, branch, fileName)
end

require("filesystem").makeDirectory("/usr/lib")

shell.execute(string.format('wget -f %s %s', getFileURL("cli.lua"),               "/home/cli.lua"))
shell.execute(string.format('wget -f %s %s', getFileURL("updater.lua"),           "/home/updater.lua"))
shell.execute(string.format('wget -f %s %s', getFileURL("WDControllerProxy.lua"), "/usr/lib/WDControllerProxy.lua"))
shell.execute(string.format('wget -f %s %s', getFileURL("logger.lua"),            "/usr/lib/logger.lua"))

local p = require("package")
p.loaded.WDControllerProxy = nil
p.logger = nil
