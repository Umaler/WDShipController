local component=require("component")
local table=require("table")
local Logger = require("logger")
--local Logger=dofile("/home/WDShipController/logger.lua")
local string=require("string")
local math=require("math")
local thread = require("thread")
local event = require("event")

local createController = function (controllerComponent)
    local argType = type(controllerComponent)
    if argType == "string" then
        _controller = component.proxy(controllerComponent)
    elseif argType == "table" then
        _controller = controllerComponent
    else
        error("createController: passed " .. argType .. " instead of string or table")
    end

    local findCoreByController = function(controller)
        s, _ = controller.isAssemblyValid()
        if not s then
            Logger.log("Failed to find associatied core for controller " .. controller.address, {message_type="warning", prefix="Test"})
            return
        end

        local controllerCoords = {controller.position()}
        --local orientation      = {controller.getOrientation()}

        local coords = {
            controllerCoords[1],
            controllerCoords[2],
            controllerCoords[3]
        }

        local sameCoords = function(coords_one, coords_two)
            local same = true
            for i=1, #coords_one do
                same = same and (coords_one[i] == coords_two[i])
            end
            return same
        end

        local cores = component.list("warpdriveShipCore")
        for k, _ in pairs(cores) do
            if sameCoords(coords, {component.invoke(k, "position")}) then
                return component.proxy(k)
            end
        end
        Logger.log("Failed to find associatied core for controller " .. controller.address, {message_type="warning", prefix="Test"})
    end

    Controller = {
        rawController = _controller,
        associatedCore = findCoreByController(_controller),

        globalToRelativeMoves = function(self, x, y, z)
            local xdir, _, zdir = self.rawController.getOrientation()
            if zdir == 1 then
                f, r = z, -x
            elseif xdir == -1 then
                f, r = -x, -z
            elseif zdir == -1 then
                f, r = -z, x
            elseif xdir == 1 then
                f, r = x, z
            else
                error("Controller proxy: received strange orientation ("
                        .. "xdir="   .. tostring(xdir)
                        .. "; ydir=" .. tostring(ydir)
                        .. "; zdir=" .. tostring(zdir)
                        .. ") by controller " .. self.rawController.address)
            end
            return f, y, r
        end,

        relativeToGlobalMoves = function(self, f, u, r)
            local xdir, _, zdir = self.rawController.getOrientation()
            if zdir == 1 then
                x, z = -r, f
            elseif xdir == -1 then
                x, z = -f, -r
            elseif zdir == -1 then
                x, z = r, -f
            elseif xdir == 1 then
                x, z = f, r
            else
                error("Controller proxy: received strange orientation ("
                        .. "xdir="   .. tostring(xdir)
                        .. "; ydir=" .. tostring(ydir)
                        .. "; zdir=" .. tostring(zdir)
                        .. ") by controller " .. self:getControllerAddr())
            end
            return x, u, z
        end,

        getCoords = function(self)
            return self.rawController.position()
        end,

        getDims = function(self)
            local f, r, u = self.rawController.dim_positive()
            local b, l, d = self.rawController.dim_negative()
            return f, u, r, b, d, l
        end,

        setDims = function(self, f, u, r, b, d, l) -- forward, up, right...
            self.rawController.dim_positive(f, r, u)
            self.rawController.dim_negative(b, l, d)
        end,

        getGlobalDims = function(self)
            local rpx, rpy, rpz, rnx, rny, rnz = self:getDims()
            local px, py, pz = self:relativeToGlobalMoves(rpx, rpy, rpz)
            local nx, ny, nz = self:relativeToGlobalMoves(rnx, rny, rnz)
            local x, y, z = self:getCoords()
            if px < nx then px, nx = nx, px end
            if pz < nz then pz, nz = nz, pz end

            return x + px,
                   y + rpy,
                   z + pz,
                   x - nx,
                   y - rny,
                   z - nz
        end,

        setGlobalDims = function(self, px, py, pz, nx, ny, nz)
            local x, y, z = self:getCoords()
            if px < nx then px, nx = nx, px end
            if py < ny then py, ny = ny, py end
            if pz < nz then pz, nz = nz, pz end

            px, py, pz = px - x, py - y, pz - z
            nx, ny, nz = x - nx, y - ny, z - nz

            local f, u, r = self:globalToRelativeMoves(px, py, pz)
            local b, d, l = self:globalToRelativeMoves(nx, ny, nz)

            self:setDims(f, u, r, b, d, l)
        end,

        getControllerAddr = function(self)
            return self.rawController.address
        end,

        getCoreAddr = function(self)
            return self.associatedCore.address
        end,

        jumpTo = function(self, x, y, z)
            local _x, _y, _z = self:getCoords()
            _x, _y, _z = x - _x, y - _y, z - _z
            local f, u, r = self:globalToRelativeMoves(_x, _y, _z)
            self.rawController.movement(f, u, r)
            self.rawController.command("MANUAL")
            self.rawController.enable(true)
        end,

        jump = function(self, f, u, r)
            self.rawController.movement(f, u, r)
            self.rawController.command("MANUAL")
            self.rawController.enable(true)
        end,

        getMaxJumpDistance = function(self)
            local c = self.rawController.command()
            self.rawController.command("MANUAL")
            local s, d = self.rawController.getMaxJumpDistance()
            self.rawController.command(c)
            return s, d
        end,

        changeHyper = function(self)
            local rc = self.rawController
            if rc.isInHyperspace() or rc.isInSpace() then
                self.rawController.command("HYPERDRIVE")
                self.rawController.enable(true)
                return true
            else
                return false, "failed to engage hyperdrive"
            end
        end,

        deactivate = function(self)
            self.rawController.enable(false)
            self.rawController.command("OFFLINE")
        end,

        setName = function(self, name)
            self.rawController.shipName(name)
        end,

        getName = function(self)
            return self.rawController.shipName()
        end
    }

    return Controller
end

local createControllersManager = function (controllersList)
    -- construct list of controllers
    if controllersList == nil then
        controllerComponentName = "warpdriveShipController"
        compList = component.list(controllerComponentName)
        controllersList = {}
        for k, v in pairs(compList) do
            if v == controllerComponentName then
                table.insert(controllersList, createController(k))
            end
        end
    else
        for i, controller in ipairs(controllersList) do
            s, e = pcall(createController, controller)
            if s then
                controllersList[i] = e
            else
                Logger.log(string.format("In passed list of controllers found strange value (%s) of type %s", controller, type(controller)), {message_type="error", prefix="createControllersManager"})
            end
        end
    end

    local confControllersList = {}
    for _, v in ipairs(controllersList) do
        table.insert(confControllersList, {
            ready = true,
            controller = v
        })
    end

    local ControllersManager = {
        controllers = confControllersList,
        nowJumping = 0,
        isMainThreadCreated = false,

        getAvailableController = function (self)
            for i, controllerConf in ipairs(self.controllers) do
                if controllerConf.ready then
                    return i, controllerConf
                end
            end
        end,

        selectController = function(self)
            for _, contr in ipairs(self.controllers) do
                contr.controller:deactivate()
            end
            local i, controller = self:getAvailableController()
            if controller == nil then
                return false, "No available controller"
            end
            return true, {i, controller}
        end,

        useJumpFunc = function(self, funcName, ...)
            local s, v = self:selectController()
            if not s then
                return false, v
            end
            local i, v = v[1], v[2]
            local s = {v.controller[funcName](v.controller, ...)}
            if #s >= 1 and s[1] ~= nil and s[1] == false then
                return table.unpack(s)
            end
            --v.ready = false
            self.nowJumping = i
            return true
        end,

        jumpTo = function (self, x, y, z)
            checkArg(1, x, "number")
            checkArg(2, y, "number")
            checkArg(3, z, "number")
            return self:useJumpFunc("jumpTo", x, y, z)
        end,

        jump = function(self, f, u, r)
            checkArg(1, f, "number")
            checkArg(2, u, "number")
            checkArg(3, r, "number")
            return self:useJumpFunc("jump", f, u, r)
        end,

        getMaxJumpDistance = function(self)
            local s, v = self:selectController()
            if not s then
                return false, v
            end
            local v = v[2]
            return v.controller:getMaxJumpDistance()
        end,

        getCurrentPosition = function(self)
            local s, v = self:selectController()
            if not s then
                return false, v
            end
            local v = v[2]
            return v.controller:getCoords()
        end,

        changeHyper = function(self)
            return self:useJumpFunc("changeHyper")
        end,

        configDimesions = function (self, configurableController, controllerConfigurer)
            configurableController:setGlobalDims(controllerConfigurer:getGlobalDims())
        end,

        configAllBasedOn = function(self, referenceController)
            for _, controller in ipairs(self.controllers) do
                if controller.controller:getControllerAddr() ~= referenceController:getControllerAddr() then
                    self:configDimesions(controller.controller, referenceController)
                end
            end
        end,

        stopJumping = function(self)
            local nj = self.nowJumping
            if nj == 0 or nj == nil then
                return
            end
            self.controllers[nj].controller:deactivate()
        end,

        setName = function(self, name, idx)
            if idx == nil then
                for _, controller in ipairs(self.controllers) do
                    controller.controller:setName(name)
                end
            else
                self.controllers[idx].controller:setName(name)
            end
        end,

        createMainThread = function(self)
            if isMainThreadCreated then
                return
            end

            local function main()
                local state = "nothing"
                while true do
                    event.pull()
                end
                self:getAvailableController()
            end

            isMainThreadCreated = true
        end,
    }

    return ControllersManager
end

local function processCooldownEvent(controller, name, ...)
    local r_addr = select(1, ...)
    for _, cont in ipairs(controller.controllers) do
        local c = cont.controller
        local addr = c:getControllerAddr()
        if addr == r_addr then
            cont.ready = true
            break
        end
    end
end

local function processEvents(controller, name, ...)
    if name == "shipCoreCooldownDone" then
        processCooldownEvent(controller, name, ...)
    else
        return
    end
end

local function registerEventsDriver(controller)
    return {
        event.listen("shipCoreCooldownDone", function(...) processCooldownEvent(controller, ...); end)
    }
end

local function unregisterEventsDriver(ids)
    for _, id in ipairs(ids) do
        event.cancel(id)
    end
end

return {
    ["createController"] = createController,
    ["createControllersManager"] = createControllersManager,
    ["processCooldownEvent"] = processCooldownEvent,
    ["processEvents"] = processEvents,
    ["registerEventsDriver"] = registerEventsDriver,
    ["unregisterEventsDriver"] = unregisterEventsDriver
}
