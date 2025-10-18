local table = require("table")
local string = require("string")
local fs = require("filesystem")
local tempFs = fs.proxy(require("computer").tmpAddress())

-- Code of time getting copied from here https://computercraft.ru/topic/3674-chasy-opencomputers-realtime-and-gametime/
local TIME_ZONE = 3
local t_correction = TIME_ZONE * 3600

function getRealTime()
    tempFs.close(tempFs.open("/time", "w"))
    local timestamp = tempFs.lastModified("/time") / 1000 + t_correction
    return os.date("%H:%M:%S %d.%m.%Y", timestamp)
end

fs.makeDirectory("/var/log")

if Logger ~= nil then
    return Logger
end

local defaultLogFile = io.open("/var/log/default_log_file", "a")

Logger = {
    loggingFile = defaultLogFile,
    printTime = true,

    printer = {
        writeToTerm = function(msg, prefix, fg, bg)
            local default_fg = 0xffffff
            local default_bg = 0x000000

            if fg ~= nil and type(fg) ~= 'number' then
                fg = default_fg
                Logger.log("Foreground bust be number, not ", type(fg), "! Value is ", tostring(fg), {message_type="warning", prefix="Logger_Internals"})
            end
            if bg ~= nil and type(bg) ~= 'number' then
                bg = default_bg
                Logger.log("Background bust be number, not ", type(bg), "! Value is ", tostring(bg), {message_type="warning", prefix="Logger_Internals"})
            end
            fg = fg == nil and 0xffffff or fg
            bg = bg == nil and 0x000000 or bg

            local term = require("term")
            local gpu = term.gpu()
            local lfg = gpu.setForeground(fg)
            local lbg = gpu.setBackground(bg)
            term.write(prefix)
            for _, _msg in ipairs(msg) do
                term.write(_msg)
                term.write(" ")
            end
            term.write("\n")
            gpu.setForeground(lfg)
            gpu.setBackground(lbg)
        end,

        writeToFile = function(msg, prefix)
            if Logger.loggingFile == nil then
                return
            end

            Logger.loggingFile:write(prefix)
            for _, _msg in ipairs(msg) do
                Logger.loggingFile:write(_msg)
                Logger.loggingFile:write(" ")
            end
            Logger.loggingFile:write("\n")
            Logger.loggingFile:flush()
        end,

        print = function(...)
            --[[
                list of args:
                message, {message_type [, prefix]}

                message - message to print
                message_type - may be: message/warning/error
                prefix - prefix to print. If not presented then it won't be presented

                Final print will be like:
                [Warning][Logger]: Example of message
            ]]--
            arg = table.pack(...)

            if #arg < 2 then
                error("Logger call with only " .. tostring(#arg) .. " values.")
            end

            local message_conf = arg[#arg]
            if type(message_conf) ~= "table" then
                error("Logger last argument must be table of configs, not " .. type(message_conf) .. "!")
            end

            local message_type = message_conf.message_type
            if type(message_type) ~= "string" then
                error("message_type must be string, not " .. type(message_type) .. "!")
            end

            local prefix = message_conf.prefix
            if type(prefix) ~= "string" and prefix ~= nil then
                error("prefix must be string or nil, not " .. type(prefix) .. "!")
            end

            arg[#arg] = nil
            message = arg

            local resulting_prefix = ""
            if Logger.printTime then
                resulting_prefix = resulting_prefix .. "[" .. getRealTime() .. "]"
            end
            local resulting_prefix = resulting_prefix .. "["..message_type.."]"
            if prefix ~= nil then
                resulting_prefix = resulting_prefix.."["..prefix.."]: "
            end

            local term = require("term")
            local printToTerm = false
            if term.isAvailable() then
                printToTerm = true
            end

            if message_type ~= "warning" and message_type ~= "message" and message_type ~= "error" then
                Logger.log("Next message received with unknown type \"", message_type, "\".", {message_type="warning", prefix="Logger"})
            end
            if printToTerm then
                if message_type == "message" then
                    Logger.printer.writeToTerm(message, resulting_prefix, 0xFFFFFF)
                elseif message_type == "error" then
                    Logger.printer.writeToTerm(message, resulting_prefix, 0xFF0000)
                else
                    Logger.printer.writeToTerm(message, resulting_prefix, 0xFFFF00)
                end
            end
            Logger.printer.writeToFile(message, resulting_prefix)
        end
    },

    log = function(...)
        local s, e = pcall(Logger.printer.print, ...)
        if not s then
            local toss, tose = pcall(tostring, e)
            if not toss then
                Logger.log("Error during logging. Error message is unprintable! Converted error: ", tose, {message_type="error"})
            else
                Logger.log("Error during logging: ", tose, {message_type="error", prefix="Logger"})
            end
            return false
        else
            return true
        end
    end
}

if Logger.loggingFile == nil then
    Logger.log("Failed to open logging file!", {message_type="error", prefix="Logger"})
end

--[[
Example of usage:
Logger.log("Aboba", " abobov", {message_type="warning", prefix="Test"})
Logger.log("Bebra", {message_type="error"})
Logger.log("Bulbulator")
]]--

return Logger
