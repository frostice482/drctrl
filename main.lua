if not require then os.loadAPI('lib/impl_require') end

local DR = require 'lib/draconicreactor'
local DRMon = require 'lib/drmon'
local util = require 'lib/util'
local peripherals = require 'peripherals_config'

local inputGateName = peripherals.inputGateName
local outputGateName = peripherals.outputGateName
local reactorName = peripherals.reactorName
local monitorName = peripherals.monitorName

--- @type DraconicFluxGate
local inputGate = util.getPeripheral(inputGateName, {"flux_gate", "flow_gate"})
--- @type DraconicFluxGate
local outputGate = util.getPeripheral(outputGateName, {"flux_gate", "flow_gate"})
--- @type DraconicReactorPrototype
local reactor = DR:new(util.getPeripheral(reactorName, {"draconic_reactor"}))
--- @type MonitorPeripheral
local monitorPer = util.getPeripheral(monitorName, {"monitor"}, true)
local monitor = DRMon:new(monitorPer or term)

-- Gate values
local inputGateValue = 0
local outputGateValue = 0
--Tick counter
local tick = 0
local inputTick = 0
local toff = 0
-- One tick delay
local prevTemp
local oneTickSat = false
local otoFieldCounter = 0
local oneTickField = false
-- If reaactor is virtually stopping, used for faster shutdown time
local virtualStopping = false

monitor.onOptionChange = function()
    os.queueEvent('config_change')
end
monitor.onExit = function()
    os.queueEvent("reactor_exit")
end
monitor.onCharge = function()
    os.queueEvent("reactor_statechange")
    virtualStopping = false
    reactor:charge()
end
monitor.onStop = function()
    os.queueEvent("reactor_statechange")
    outputGateValue = 0
    virtualStopping = true
end
monitor.onStart = function()
    os.queueEvent("reactor_statechange")
    virtualStopping = false
    prevTemp = nil
    reactor:activate()
end

--- @param info DraconicReactorInfo
local function updateInfo(info)
    local maxTemp = monitor.optsvalues["Max Temp"]
    local targetField = monitor.optsvalues["Target Field"] / 100
    local maxInput = monitor.optsvalues["Max Input"]
    local maxChaos = monitor.optsvalues["Max Chaos"] / 100

    local status = DR.calculator:normalizeStatus(info, true)

    -- apply one tick offset
    if oneTickSat then info.energySaturation = info.energySaturation - outputGateValue end
    if oneTickField then info.fieldStrength = info.fieldStrength - info.fieldDrainRate end

    if virtualStopping or status == "stopping" then
        local mult = 1 - targetField
        inputGateValue = math.min(info.maxFieldStrength, info.fieldDrainRate / mult)
        outputGateValue = 0
    end

    if virtualStopping then
        local conversionLevel = DR.calculator:conversionLevel(DR.calculator:convertedFuelRate(info))
        local tempDelta = DR.calculator:tempDeltaReactor(info)
        local coolDelta = 1 - conversionLevel

        if status ~= 'online' or tempDelta > -coolDelta - 0.005 then
            reactor:stop()
            virtualStopping = false
        end

        outputGateValue = 0
        info.status = "stopping"
    elseif status == "offline" or status == "cooling" then
        inputGateValue = 0
    elseif status == "charging" then
        local sat = DR.calculator:saturationRate(info)
        local field = DR.calculator:fieldStrength(info)
        local temp = info.temperature

        if field < 0.5 then
            inputGateValue = info.maxFieldStrength / 2 * math.max(0.01, (0.5 - field) / 5)
        elseif sat < 0.5 then
            inputGateValue = info.maxEnergySaturation / 2 * math.max(0.01, (0.5 - sat) / 5)
        elseif temp < 2000 then
            local reactable = DR.calculator:reactableFuel(info)
            inputGateValue = (1000 + reactable * 10) * math.max(0.8, (2000 - temp) / 8)
        end
    elseif status == "charged" then
        inputGateValue = 0
    elseif status == "online" then
        -- detect one tick offset for saturation
        local temp = info.temperature
        if not oneTickSat and status == "online" and prevTemp then
            local delta = temp - prevTemp
            local expectedDelta = DR.calculator:tempDeltaReactor(info)
            -- apply one tick offset
            if math.abs(expectedDelta - delta) > math.max(math.abs(expectedDelta / 8), 0.08) then
                oneTickSat = true
                if monitor.mon ~= term then print("OTO Sat enabled") end
            end
        end
        -- detect one tick offset for field
        -- only effective when temperature is stable
        if not oneTickField then
            if math.abs(info.fieldStrength - info.fieldDrainRate - targetField * info.maxFieldStrength) < 500 then
                otoFieldCounter = otoFieldCounter+1
                if otoFieldCounter >= 5 then
                    -- apply one tick offset
                    oneTickField = true
                    if monitor.mon ~= term then print("OTO Field enabled") end
                end
            else
                otoFieldCounter = 0
            end
        end

        local maxField = info.maxFieldStrength
        local maxSat = info.maxEnergySaturation
        local field = DR.calculator:fieldStrength(info)
        local drain = info.fieldDrainRate
        local sat = DR.calculator:saturationRate(info)
        local convertedFuel = math.min(1, DR.calculator:convertedFuelRate(info))
        local deltaTemp = DR.calculator:tempDelta(temp, sat, convertedFuel)
        local maxRft = DR.calculator:maxRft(info.generationRate, sat)
        local baseMaxRft = DR.calculator:baseMaxRft(maxRft, convertedFuel)

        -- Set output drain rate
        local appliedMax = math.min(maxInput, maxField, inputGateValue + targetField * maxField / 5) * (1 - targetField)
        local minSatByTemp = DR.calculator:targetEnergySaturationByTemperature(convertedFuel, maxTemp, 18)
        local minSatByInput = DR.calculator:minPossibleSaturation(baseMaxRft, appliedMax, convertedFuel, 18, 18)
        local minSat = math.max(minSatByTemp, minSatByInput)

        toff = tick - inputTick
        local tickAheads = 3 - toff

        -- increases tick ahead by 1 for every 0.4% field below target - 0.1%
        if targetField < field - 0.001 then
            tickAheads = tickAheads + (targetField - 0.001 - field) / 0.004
        end

        -- set output
        outputGateValue = maxRft * (1 - minSat)
        if sat < minSat then
            local required = (minSat - sat) * maxSat
            outputGateValue = outputGateValue - required
        end

        -- Calculate next saturation by 2 ticks
        local nextSat = (info.energySaturation + tickAheads * (-outputGateValue + (1 - sat) * maxRft)) / maxSat

        -- Set input drain rate for 2 ticks in the future
        local nextDrain = DR.calculator:targetFieldDrain(baseMaxRft, temp + deltaTemp * tickAheads, nextSat)
        local fieldMult = 1 - targetField
        local appliedDrain = math.max(drain, nextDrain)
        inputGateValue = appliedDrain / fieldMult

        -- additional input - increase required field
        if field < targetField then
            local required = appliedDrain * (targetField / field - 1) / 2
            inputGateValue = inputGateValue + required
        end

        -- limit input to field strength
        if inputGateValue > maxField then inputGateValue = maxField end

        -- auto stop
        if convertedFuel > maxChaos then
            monitor.onStop()
        end

        prevTemp = temp
    end

    -- update monitor
    monitor:update(info, inputGateValue, outputGateValue)

    if status == "invalid" or status == "offline" or status == "cold" then
        parallel.waitForAny(function() sleep(0.8) end, function() os.pullEvent("reactor_statechange") end)
    elseif status == "charging" or status == "warming_up" or status == "charged" or status == "cooling" then
        parallel.waitForAny(function() sleep(0.05) end, function() os.pullEvent("reactor_statechange") end)
    end
end

--- @class Loops
local loops = {
    reactorInfo = function()
        monitor:refreshAll()
        while true do
            local curTick = tick
            local info = reactor:info()
            if tick == curTick then sleep(0.05) end
            if info then updateInfo(info) end
        end
    end;

    inputSet = function()
        sleep(0.1)
        while true do
            local curTick = tick
            inputTick = tick
            inputGate.setSignalLowFlow(inputGateValue)
            if tick == curTick then sleep(0.05) end
        end
    end;

    outputSet = function()
        sleep(0.1)
        while true do
            local curTick = tick
            outputGate.setSignalLowFlow(outputGateValue)
            if tick == curTick then sleep(0.05) end
        end
    end;

    configSave = function()
        while true do
            os.pullEvent('config_change')
            local fd = fs.open("drctrl_config", "w")
            fd.write(textutils.serialize(monitor.optsvalues, { compact = true }))
            fd.close()
        end
    end;

    commands = function()
        while true do
            local input = read()
            if input == "h" or input == "help" then
                print("help, charge, start, stop, quit, status, debug")
            elseif input == "charge" then
                monitor.onCharge()
            elseif input == "activate" or input == "start" then
                monitor.onStart()
            elseif input == "stop" then
                monitor.onStop()
            elseif input == "q" or input == "quit" then
                local info = reactor:info()
                if not info or info.status == "cooling" or info.status == "cold" or info.status == "offline" then
                    monitor.onExit()
                else
                    printError("Cannot shutdown while reactor is active")
                end
            elseif input == "status" then
                local info = reactor:info()
                local status = info and DR.calculator:normalizeStatus(info) or "invalid"
                print(status)
            elseif input == 'debug' then
                print(string.format("toff: %d", toff))
                print(string.format("otosat: %d", oneTickSat == true and 1 or 0))
                print(string.format("otofield: %d", oneTickField == true and 1 or 0))
                print(string.format("vstop: %d", virtualStopping == true and 1 or 0))
            else
                printError("Unknown command, type h for help")
            end
        end
    end;

    tick = function()
        while true do
            tick = tick + 1
            sleep(0.05)
        end
    end;

    waitMonInteract = function()
        while true do
            local xe, ye
            if monitorPer then
                local event, name, x, y = os.pullEvent("monitor_touch")
                if name == monitorName then
                    xe = x
                    ye = y
                end
            else
                local event, button, x, y = os.pullEvent("mouse_click")
                xe = x
                ye = y
            end

            if xe and ye then
                local lis = monitor:getTouchListenerAt(xe, ye)
                if lis then
                    local status, err = pcall(lis.func, xe, ye)
                    if status == false then printError(err) end
                end
            end
        end
    end;

    waitMonResize = function()
        if not monitorPer then return end
        while true do
            local event, name = os.pullEvent("monitor_resize")
            if name == monitorName then monitor:refreshAll() end
        end
    end;

    --- @param self Loops
    all = function(self)
        while true do
            local status, err = pcall(parallel.waitForAll, self.reactorInfo, self.inputSet, self.outputSet, self.configSave, self.tick, self.waitMonInteract, self.waitMonResize, self.commands)
            if status then break end

            printError("Loop error!", err)
            sleep(1)
        end
    end;
}

--- load config
if fs.exists("drctrl_config") then
    local fd = fs.open("drctrl_config", "r")
    local content = fd.readAll()

    if content then
        local des = textutils.unserialize(content)
        if des then
            for key, value in pairs(des) do
                monitor.optsvalues[key] = value
            end
        else
            if monitor.mon ~= term then print("Config exists but failed to load") end
        end
    end

    fd.close()
end

parallel.waitForAny(
    function() loops:all() end, -- loop all
    function() os.pullEvent("reactor_exit") end -- wait for reactor exit event
)

monitor.clear()
monitor.setCursorPos(1, 1)
