local logger = require("logger")
--local logger=dofile("/home/WDShipController/logger.lua")
local wdc = require("WDControllerProxy")
local term = require("term")
local math = require("math")
local event = require("event")
local kb = require("keyboard")
local io = require("io")
local table = require("table")
local component = require("component")

local controllersManager = wdc.createControllersManager()

local function valueOrDefault(value, default)
    if value ~= nil then
        return value
    else
        return default
    end
end

local function selectingMenu(title, listOfOptions)
    local item_shift=1
    if title ~= nil and title ~= "" then
        item_shift = item_shift + 1
    end

    local ofg = 0xFFFFFF
    local obg = 0x000000

    if #listOfOptions == 0 then
        return
    end

    local getInvertedColors = function(origFG, origBG)
        return 0x000000, 0xFFFFFF
    end

    local write = function(i, fg, bg)
        term.gpu().setForeground(fg)
        term.gpu().setBackground(bg)
        term.setCursor(1, i+item_shift)
        term.clearLine()
        term.write(listOfOptions[i])
    end

    local redrawUpdatedLines = function(newSelectedI, lastSelectedI)
        if lastSelectedI ~= nil then
            write(lastSelectedI, ofg, obg)
        end
        local nfg, nbg = getInvertedColors(ofg, obg)
        write(newSelectedI, nfg, nbg)
        term.gpu().setForeground(ofg)
        term.gpu().setBackground(obg)
    end

    local selectedOptionI = 1
    term.clear()
    term.write(title)
    local ifg, ibg = getInvertedColors(ofg, obg)
    write(selectedOptionI, ifg, ibg)
    if #listOfOptions >= 2 then
        for i=2, #listOfOptions do
            write(i, ofg, obg)
        end
    end
    term.gpu().setForeground(ofg)
    term.gpu().setBackground(obg)

    local controlState = "nothing" -- can be nothing, down, up, select
    while controlState ~= "select" do
        e = {event.pull(0.25)}
        if e == nil then
            controlState = "nothing"
        else
            if e[1] == "key_down" then
                if e[4] == kb.keys.down then
                    controlState = "down"
                elseif e[4] == kb.keys.up then
                    controlState = "up"
                elseif e[4] == kb.keys.enter then
                    controlState = "select"
                end
            elseif e[1] == "key_up" then
                if (e[4] == kb.keys.down and controlState == "down") or
                   (e[4] == kb.keys.up   and controlState == "up") then
                    controlState = "nothing"
                end
            elseif e[1] == "interrupted" then
                return
            end
        end

        local lastSelectedOptionI = selectedOptionI
        if controlState == "down" then
            if selectedOptionI < #listOfOptions then
                selectedOptionI = selectedOptionI + 1
            else
                selectedOptionI = 1
            end
        elseif controlState == "up" then
            if selectedOptionI > 1 then
                selectedOptionI = selectedOptionI - 1
            else
                selectedOptionI = #listOfOptions
            end
        end

        if lastSelectedOptionI ~= selectedOptionI then
            redrawUpdatedLines(selectedOptionI, lastSelectedOptionI)
        end
    end

    return selectedOptionI
end

local function getControllersDesc()
    local descs = {}
    for _, cont in ipairs(controllersManager.controllers) do
        local contr = cont.controller
        local addr = contr:getControllerAddr()
        local x, y, z = contr:getCoords()
        local name = contr:getName()
        local desc = addr .. " " .. name .. " x=" .. tostring(x) .. "; y=" .. tostring(y) .. "; z=" .. tostring(z)
        table.insert(descs, desc)
    end
    return descs
end

local function selectController(returnIdx)
    local printedControllers = getControllersDesc()
    local controllers = {}
    for _, cont in ipairs(controllersManager.controllers) do
        local contr = cont.controller
        local addr = contr:getControllerAddr()
        table.insert(controllers, contr)
    end
    local contrIdx = selectingMenu(
        "Select controller",
        printedControllers
    )
    if returnIdx then
        return contrIdx
    else
        local selectedController = controllers[contrIdx]
        return selectedController
    end
end


local function mainMenu()
    while true do
        local i = selectingMenu(
            "Select menu",
        {
            "get dimensions",
            "set dimensions",
            "jump",
            "stop jump",
            "is jumping in progress",
            "enter/leave hyperspace",
            "get max jump distance",
            "sync controllers dimensions",
            "get controllers and cores addresses",
            "get controllers",
            "set name"
        })
        sub_menus = {
            function()
                selectedController = selectController()
                local relDims = {selectedController:getDims()}
                local absDims = {selectedController:getGlobalDims()}
                term.clear()
                print("Relative dimensions: ", table.unpack(relDims))
                print("Absolute dimensions: ", table.unpack(absDims))
                io.read()
            end,

            function()
                selectedController = selectController()
                local setType = selectingMenu(
                    "Set dimensions as coordinates or directions?",
                    {
                        "coordinates",
                        "dimensions"
                    }
                )
                if setType == 1 then
                    term.clear()
                    io.write("Enter first x: ")
                    local fx = tonumber(io.read())
                    io.write("Enter first y: ")
                    local fy = tonumber(io.read())
                    io.write("Enter first z: ")
                    local fz = tonumber(io.read())
                    io.write("Enter second x: ")
                    local sx = tonumber(io.read())
                    io.write("Enter second y: ")
                    local sy = tonumber(io.read())
                    io.write("Enter second z: ")
                    local sz = tonumber(io.read())

                    if fx == nil or fy == nil or fz == nil or
                       sx == nil or sy == nil or sz == nil
                    then
                       print("You entered one or more blank value, so leaving the old values")
                       io.read()
                       return
                    end

                    selectedController:setGlobalDims(fx, fy, fz, sx, sy, sz)
                else
                    term.clear()

                    local _f, _u, _r, _b, _d, _l = selectedController:getDims()
                    print("Enter dimensions or leave it blank to remain the old one")
                    io.write("Enter forward: ")
                    local f = valueOrDefault(tonumber(io.read()), _f)
                    io.write("Enter up: ")
                    local u = valueOrDefault(tonumber(io.read()), _u)
                    io.write("Enter right: ")
                    local r = valueOrDefault(tonumber(io.read()), _r)
                    io.write("Enter back: ")
                    local b = valueOrDefault(tonumber(io.read()), _b)
                    io.write("Enter down: ")
                    local d = valueOrDefault(tonumber(io.read()), _d)
                    io.write("Enter left: ")
                    local l = valueOrDefault(tonumber(io.read()), _l)

                    if f == nil then f = _f end

                    selectedController:setDims(f, u, r, b, d, l)
                end
                local setForAll = selectingMenu(
                    "Set for all controllers or for only one?",
                    {
                        "For all",
                        "For the current one"
                    }
                )

                if setForAll == 1 then
                    controllersManager:configAllBasedOn(selectedController)
                end
            end,

            function()
                local jumpType = selectingMenu(
                    "Jump by coordinates or relatively?",
                    {
                        "coordinates",
                        "relatively"
                    }
                )

                local oldx, oldy, oldz = controllersManager:getPosition()
                local s, e
                if jumpType == 1 then
                    term.clear()
                    print("Enter coordinates or leave it blank to remain the old one")
                    io.write("Enter x: ")
                    local x = valueOrDefault(tonumber(io.read()), oldx)
                    io.write("Enter y: ")
                    local y = valueOrDefault(tonumber(io.read()), oldy)
                    io.write("Enter z: ")
                    local z = valueOrDefault(tonumber(io.read()), oldz)

                    s, e = controllersManager:jumpTo(x, y, z)
                elseif jumpType == 2 then
                    term.clear()
                    io.write("Enter forward: ")
                     local x = valueOrDefault(tonumber(io.read()), oldx)
                    io.write("Enter up: ")
                    local y = valueOrDefault(tonumber(io.read()), oldy)
                    io.write("Enter right: ")
                    local z = valueOrDefault(tonumber(io.read()), oldz)

                    s, e = controllersManager:jump(x, y, z)
                else
                    print("something went wrong with selecting menu")
                    io.read()
                    return
                end

                if not s then
                    print("Failed to jump because: ", e)
                    io.read()
                end
            end,

            function()
                controllersManager:stopJumping()
                term.clear()
                print("Successfully stoped jumping")
                io.read()
            end,

            function()
                local jumping = controllersManager:isJumpingInProgress()
                term.clear()
                if jumping then
                    print("Jumping in progress")
                else
                    print("No jumps are planned now")
                end
                io.read()
            end,

            function()
                s, e = controllersManager:changeHyper()
                if s then
                    term.clear()
                    print("Changing hyperdrive")
                    os.sleep(2)
                else
                    term.clear()
                    print("Failed to change hyperdrives because", e)
                    io.read()
                end
            end,

            function()
                s, e = controllersManager:getMaxJumpDistance()
                if s then
                    term.clear()
                    print("Max jump distance is", e)
                    io.read()
                else
                    term.clear()
                    print("Failed to get max jump distance because", e)
                    io.read()
                end
            end,

            function()
                selectedController = selectController()
                controllersManager:configAllBasedOn(selectedController)
            end,

            function()
                term.clear()
                for _, cont in ipairs(controllersManager.controllers) do
                    local contr = cont.controller
                    print("Controller addr:", contr:getControllerAddr(), "Core addr:", contr:getCoreAddr())
                end
                io.read()
            end,

            function()
                term.clear()
                local descs = getControllersDesc()
                for _, desc in ipairs(descs) do
                    print(desc)
                end
                io.read()
            end,

            function()
                term.clear()
                print("Enter new name")
                local name = io.read()
                local setForAll = selectingMenu(
                    "Set new name for all controllers?",
                    {
                        "For all",
                        "For only one"
                    }
                )
                if setForAll == 1 then
                    controllersManager:setName(name, nil)
                elseif setForAll == 2 then
                    local i = selectController(true)
                    controllersManager:setName(name, i)
                end
            end
        }
        if i == nil then
            break
        end
        s, e = pcall(sub_menus[i])
        if not s then
            term.clear()
            print("Error in menu: ", e)
            io.read()
        end
    end

    return true
end


local function main()
    local tu_callback_id = event.listen("term_unavailable", function(...)
        local tryAttachGPU = function()
            if component.isAvailable("screen") then
                term.gpu().bind(component.screen.address)
                event.cancel(_G["taGPU_callback_id"])
            end
        end
        _G["taGPU_callback_id"] = event.timer(0.25, tryAttachGPU, math.huge)
    end)
    local eventsDrivers = wdc.registerEventsDriver(controllersManager)

    pcall(
        function()
            s, e = xpcall(mainMenu, function(err) return err .. "\n" .. debug.traceback(); end)
            if not s then
                term.clear()
                logger.log("Interface failed with error", e, {message_type="error", prefix="WDFly: main"})
            end
        end
    )

    wdc.unregisterEventsDriver(eventsDrivers)
    event.cancel(tu_callback_id)
end

main()
os.exit(0)
