local DR = require 'lib/draconicreactor'
local MonUtil = require 'lib/monutil'
local constructor = require 'lib/constructor'
local util = require 'lib/util'

--- @alias __DRMonOptScale number | {text?: string, value: number}

--- @class __DRMonOpt
--- @field name string
--- @field default number
--- @field scale number[] | __DRMonOptScale[]
--- @field scaleWidth number | nil
--- @field scaleDefault number | nil
--- @field min number | nil
--- @field max number | nil
--- @field color number | nil
--- @field plusColor number | nil
--- @field minusColor number | nil
--- @field format (fun(val: number): string) | nil

--- @enum __DRMonStateButtonEnum
local mstatusenum = {
    Charge = 0x10000,
    Activate = 0x20000,
    Stop = 0x40000,
    Exit = 0x80000,
}

--- @type table<DraconicReactorState, number>
local mstatusmap = {
    invalid = mstatusenum.Exit,
    offline = bit32.bor(mstatusenum.Charge, colors.lightGray),
    warming_up = bit32.bor(mstatusenum.Stop, colors.yellow),
    charging = bit32.bor(mstatusenum.Stop, colors.yellow),
    charged = bit32.bor(mstatusenum.Activate, mstatusenum.Stop, colors.lime),
    running = bit32.bor(mstatusenum.Stop, colors.lime),
    online = bit32.bor(mstatusenum.Stop, colors.lime),
    stopping = bit32.bor(mstatusenum.Activate, colors.yellow),
    cooling = bit32.bor(mstatusenum.Charge, colors.lightGray, colors.yellow),
    cold = bit32.bor(mstatusenum.Charge, colors.lightGray)
}

--- @type __DRMonOptScale[]
local moptscale100 = {
    {value = 0.1, text = "0.1"},
    {value = 0.5, text = "0.5"},
    {value = 1.0, text = "1.0"},
    {value = 3.0, text = "3.0"}
}

--- @type __DRMonOpt[]
local mopt = {{
    name = "Max Temp",
    scale = {
        {text = "1C", value = 1},
        {text = "5C", value = 5},
        {text = "25C", value = 25},
        {text = "100C", value = 100},
        {text = "500C", value = 500}
    },
    scaleDefault = 4,
    scaleWidth = 4,
    default = 8000,
    min = 2000,
    format = function(val) return string.format("%.2f%cC", val, 176) end
}, {
    name = "Target Field",
    scale = moptscale100,
    scaleDefault = 3,
    default = 50,
    min = 5,
    max = 99,
    format = function(val) return string.format("%.1f%%", val) end
}, {
    name = "Max Input",
    scale = {
        {text = "1", value = 1e0},
        {text = "10", value = 1e1},
        {text = "100", value = 1e2},
        {text = "1K", value = 1e3},
        {text = "10K", value = 1e4},
        {text = "100K", value = 1e5},
        {text = "1M", value = 1e6},
        {text = "5M", value = 5e6},
        {text = "10M", value = 1e7}
    },
    scaleDefault = 6,
    scaleWidth = 4,
    default = 10000000,
    min = 0,
    format = function(val) return string.format("%.2fk RF/t", val / 1000) end
}, {
    name = "Max Chaos",
    scale = moptscale100,
    scaleDefault = 3,
    default = 95,
    min = 0,
    max = 95,
    format = function(val) return string.format("%.1f%%", val) end
}}

--- "{text}: {fmt}  [-] [+]  < {scale} > " -- 18
--- "settings: < {opts+3} >" -- 14
--- "{value} < {mult} >  [-] [+]"

--- @class __DRMonDefault
--- @field opts __DRMonOpt[]
--- @field optsvalues table<string, number>
--- @field optsscales table<string, number>
--- @field otpstouchlis MonUtilTouchListenerSet
--- @field stattouchlis MonUtilTouchListenerSet
local mdefaultstate = {
    --- @type DraconicReactorState
    prevstat = 'invalid',
    optsindex = 1,
    --- @type fun(id: string, value: number): number | boolean | nil
    onOptionChange = function () end,
    onCharge = function () end,
    onStart = function () end,
    onStop = function () end,
    onExit = function () end,
}

--- @class DRMonPrototype: __DRMonDefault, MonUtilPrototype
local DRMonPrototype = {
    --- @param self DRMonPrototype
    --- @param opts __DRMonOpt
    --- @param index? number
    --- @param pos number
    updateOptsScale = function(self, opts, index, pos)
        index = index or self.optsscales[opts.name]
        self.optsscales[opts.name] = index
        local scalevalue = opts.scale[index]
        local scaletext = type(scalevalue) == 'number' and tostring(scalevalue) or scalevalue.text or tostring(scalevalue.value)
        local pad = opts.scaleWidth or 3

        self:UsetCursorPos(1, pos+1)

        -- left
        if index == 1 then
            self:blitn(" < ", colors.gray)
        else
            self.write(" < ")
        end

        -- scale value
        self.write("[")
        self:blitn("x"..scaletext..string.rep(" ", pad - scaletext:len()), colors.blue)
        self.write("]")

        -- right
        if not opts.scale[index+1] then
            self:blitn(" > ", colors.gray)
        else
            self.write(" > ")
        end
    end;

    --- @param self DRMonPrototype
    --- @param opts __DRMonOpt
    --- @param value? number
    --- @param pos number
    updateOptsValue = function(self, opts, value, pos)
        value = value or self.optsvalues[opts.name]
        self.optsvalues[opts.name] = value

        local fmt = opts.format and opts.format(value) or tostring(value)
        local offset = -1 - fmt:len()

        self:UsetCursorPos(offset, pos)
        self.write("  ")
        self:blitn(fmt, opts.color or colors.orange)
    end;

    --- @param self DRMonPrototype
    --- @param opts __DRMonOpt
    --- @param pos number
    --- @param scale number
    handleOptsScale = function(self, opts, pos, scale)
        local index = self.optsscales[opts.name] + scale
        if opts.scale[index] then self:updateOptsScale(opts, index, pos) end
    end;

    --- @param self DRMonPrototype
    --- @param opts __DRMonOpt
    --- @param pos number
    --- @param decrement boolean
    handleOptsValue = function(self, opts, pos, decrement)
        local name = opts.name
        local scaleindex = opts.scale[self.optsscales[name]]
        local scalevalue = type(scaleindex) == "number" and scaleindex or scaleindex.value

        local newval = self.optsvalues[name]

        if decrement then
            newval = newval - scalevalue
            local min = opts.min
            if min and newval < min then newval = min end
        else
            newval = newval + scalevalue
            local max = opts.max
            if max and newval > max then newval = max end
        end

        local on = self.onOptionChange(name, newval)
        if on == false then return end
        if type(on) == "number" then newval = on end

        self:updateOptsValue(opts, newval, pos)
    end;

    --- @param self DRMonPrototype
    --- @param index? number
    --- @param size? number
    refreshOptions = function(self, index, size)
        index = index or self.optsindex
        size = size or 2
        local top = -2 - 2 * size
        self.optsindex = index

        -- clear touch listeners for opts
        local touchListeners = self.optstouchlis
        self:clearTouchListener(touchListeners)

        self:UsetCursorPos(1, top)
        self.clearLine()
        self.write("Options:")

        self:UsetCursorPos(-5, top)
        -- previous
        if index == 1 then
            self:blitn(" < ", colors.gray)
        else
            self:setCursorStart()
            self.write(" < ")
            self:listenTouch(function() self:refreshOptions(math.max(index - size, 1), size) end, touchListeners)
        end
        -- next
        if not self.opts[index + size] then
            self:blitn(" > ", colors.gray)
        else
            self:setCursorStart()
            self.write(" > ")
            self:listenTouch(function() self:refreshOptions(index + size, size) end, touchListeners)
        end

        for j = 1,size,1 do
            --- @type __DRMonOpt
            local opt = self.opts[index+j-1]
            local pos = top - 1 + j * 2

            self:UsetCursorPos(1, pos+1)
            self.clearLine()
            self:UsetCursorPos(1, pos)
            self.clearLine()

            if opt then
                self.write(opt.name)
                self:updateOptsValue(opt, nil, pos)

                self:UsetCursorPos(1, pos+1)
                self.clearLine()

                -- scale left
                self:setCursorStart():UmoveCursor(3, 0):listenTouch(function () self:handleOptsScale(opt, pos, -1) end, touchListeners)
                -- scale default
                self:setCursorStart():UmoveCursor(3 + (opt.scaleWidth or 3), 0):listenTouch(function () self:updateOptsScale(opt, opt.scaleDefault, pos) end, touchListeners)
                -- scale middle
                self:setCursorStart():UmoveCursor(3, 0):listenTouch(function () self:handleOptsScale(opt, pos, 1) end, touchListeners)

                self:UsetCursorPos(-6, pos+1)
                -- remove
                self:setCursorStart():blitn("[-]", opt.minusColor or colors.red):listenTouch(function () self:handleOptsValue(opt, pos, true) end, touchListeners)
                -- add
                self.write(" ")
                self:setCursorStart():blitn("[+]", opt.plusColor or colors.blue):listenTouch(function () self:handleOptsValue(opt, pos, false) end, touchListeners)

                self:updateOptsScale(opt, nil, pos)
            end
        end
    end;

    --- @param self DRMonPrototype
    --- @param status DraconicReactorState
    --- @param force? boolean
    refreshStatus = function(self, status, force)
        if not force and status == self.prevstat then return false end

        -- update previous stats and clear touch listeners for stat
        self.prevstat = status
        local touchListeners = self.stattouchlis
        self:clearTouchListener(touchListeners)

        self:UsetCursorPos(1, 0).clearLine()

        -- buttons
        local statusArg = mstatusmap[status]
        local btnOffset = 1
        if bit32.band(statusArg, mstatusenum.Stop) == mstatusenum.Stop then
            btnOffset = btnOffset - 7
            self:UsetCursorPos(btnOffset+1, 0)
            self:setCursorStart()
            self.write("[")
            self:blitn("stop", colors.orange)
            self.write("]")
            self:listenTouch(function() self.onStop() end, touchListeners)
        end
        if bit32.band(statusArg, mstatusenum.Activate) == mstatusenum.Activate then
            btnOffset = btnOffset - 8
            self:UsetCursorPos(btnOffset+1, 0)
            self:setCursorStart()
            self.write("[")
            self:blitn("start", colors.lime)
            self.write("]")
            self:listenTouch(function() self.onStart() end, touchListeners)
        end
        if bit32.band(statusArg, mstatusenum.Charge) == mstatusenum.Charge then
            btnOffset = btnOffset - 9
            self:UsetCursorPos(btnOffset+1, 0)
            self:setCursorStart()
            self.write("[")
            self:blitn("charge", colors.lime)
            self.write("]")
            self:listenTouch(function() self.onCharge() end, touchListeners)
        end
        if bit32.band(statusArg, bit32.bor(mstatusenum.Charge, mstatusenum.Exit)) ~= 0 then
            btnOffset = btnOffset - 7
            self:UsetCursorPos(btnOffset+1, 0)
            self:setCursorStart()
            self.write("[")
            self:blitn("exit", colors.red)
            self.write("]")
            self:listenTouch(function() self.onExit() end, touchListeners)
        end

        local color = bit32.band(statusArg, 0xffff)
        if color == 0 then color = nil end
        self:UsetCursorPos(1, 0)
        self:blitn(status:upper(), color)

        return true
    end;

    --- @param self DRMonPrototype
    refreshAll = function(self)
        self.optstouchlis = {}
        self.stattouchlis = {}
        self.touchListeners = {}
        self.clear()
        self:refreshStatus(self.prevstat, true)
        self:refreshOptions()
    end;

    --- @param self DRMonPrototype
    --- @param info DraconicReactorInfo
    --- @param inputValue number | nil
    --- @param outputValue number | nil
    --- @param limTemp number | nil
    update = function(self, info, inputValue, outputValue, limTemp)
        local status = info.status
        self:refreshStatus(status)

        local isCharging = status == "charging" or status == "warming_up" or status == "charged"
        local isOnline = status == "online" or status == "running"
        local isStopping = status == "stopping"
        local isCooling = status == "cooling"
        local isActive = isOnline or isStopping
        local isState = true

        local sat = DR.calculator:saturationRate(info)

        local stats = {}
        if isActive or isCharging or isCooling then
            local temp = info.temperature
            table.insert(stats, {
                name = "Temp.",
                stat = string.format("%.2f%cC (%+.3f)", info.temperature, 176, (isOnline or isStopping) and DR.calculator:tempDeltaReactor(info) or "0"),
                color = temp < 2000 and colors.gray
                    or temp < 5000 and colors.lime
                    or temp < 8000 and bit32.bor(colors.lime, colors.yellow)
                    or temp < 10000 and colors.yellow
                    or colors.red
            })
        end
        if isActive or isCharging then
            local fieldStrength = DR.calculator:fieldStrength(info)
            table.insert(stats, {
                name = "Field",
                stat = string.format("%.3f%%", fieldStrength * 100),
                color = fieldStrength < 0.2 and colors.red
                    or fieldStrength < 0.35 and colors.yellow
                    or fieldStrength < 0.60 and colors.lime
                    or fieldStrength < 0.80 and colors.cyan
                    or colors.blue
            })
            table.insert(stats, {
                name = "Saturation",
                stat = string.format("%.3f%%", sat * 100),
                color = colors.green
            })
        end
        if isActive then
            table.insert(stats, {
                name = "Drain",
                stat = string.format("%.2fk RF/t", info.fieldDrainRate / 1000),
                color = colors.yellow
            })

            if inputValue and outputValue then
                local maxNet = DR.calculator:targetNet(info, 8000)
                local net = outputValue - inputValue
                table.insert(stats, {
                    name = "I/O",
                    stat = string.format("%.2fM/%.2fM RF/t", inputValue / 1000000, outputValue / 1000000),
                    color = colors.green
                })
                if not isStopping then
                    table.insert(stats, {
                        name = "Net",
                        stat = string.format("%.2fM RF/t (%.2f%%)", net / 1000000, net / maxNet * 100),
                        color = colors.green
                    })
                end
            end
        end
        if isOnline then
            local maxChaos = self.optsvalues["Max Chaos"]
            local fueltime = DR.calculator:remainingFuelTimeSecond(info, maxChaos / 100)

            table.insert(stats, {
                name = "Fuel time",
                stat = string.format("%02d:%02d:%02d:%02d", fueltime / 86400, fueltime / 3600 % 24, fueltime / 60 % 60, fueltime % 60),
                color = fueltime < 86400 and colors.red
                    or fueltime < 86400*2 and colors.yellow
                    or fueltime < 86400*3 and colors.lime
                    or colors.blue
            })

            if limTemp then
                table.insert(stats, {
                    name = "Temp Limit",
                    stat = string.format("%.2f%cC", info.temperature, 176, limTemp),
                    color = colors.green
                })
            end
        end
        if isStopping then
            if sat < 0.99 then
                local net = DR.calculator:maxRftReactor(info) - (outputValue or 0)
                local base = 1 - net / info.maxEnergySaturation
                local time = math.log(1 - sat) / math.log(base)
                local maxTime = math.log(0.01) / math.log(base)

                table.insert(stats, {
                    name = "Fill time",
                    stat = string.format("%d sec", (maxTime - time) / 20),
                    color = colors.green
                })
                table.insert(stats, {
                    name = "Remaining",
                    stat = string.format("%.2fk RF", (info.maxEnergySaturation * 0.99 - info.energySaturation) / 1000),
                    color = colors.green
                })
            else
                local convLevel = DR.calculator:conversionLevel(DR.calculator:convertedFuelRate(info))
                local secs = (info.temperature - 2000) / (1 - convLevel) / 20

                table.insert(stats, {
                    name = "Cooling down",
                    stat = string.format("%02d:%02d", secs / 60, secs % 60),
                    color = colors.green
                })
            end
        end
        if isCooling then
            local cooltime = (info.temperature - 100) / 10
            table.insert(stats, {
                name = "Cool time",
                stat = string.format("%02d:%02d", cooltime / 60, cooltime % 60),
                color = colors.gray
            })
        end

        local xw, yw = self.getSize()

        for i = 1, 8, 1 do
            self.setCursorPos(1, i)

            local stat = stats[i]
            if stat then
                local name = stat.name
                local value = stat.stat
                self.write("- "..name)
                self.write(string.rep(" ", math.max(xw - 2 - name:len() - value:len(), 0)))
                self:blitn(value, stat.color)
            else
                self.clearLine()

                if isState then
                    isState = false
                    if isActive and (DR.calculator:fieldStrength(info) * 100 + 0.5) < (self.optsvalues["Target Field"] or 0) then
                        self:blitn("LOW POWER!", colors.red)
                    end
                end
            end
        end
    end;
}

--- @alias DRMon Constructable<DRMonPrototype, MonitorPeripheral, MonUtil>
--- @type DRMon
local DRMon = constructor.createConstructor(DRMonPrototype, function (self, arg, target)
    self.super:__new(arg, target)
    util.table_shallowcopy(mdefaultstate, target)
    util.table_shallowcopy({
        opts = util.table_shallowcopy(mopt),
        optsvalues = {},
        optsscales = {},
        otpstouchlis = {},
        stattouchlis = {}
    }, target)

    for index, value in ipairs(mopt) do
        target.optsvalues[value.name] = value.default
        target.optsscales[value.name] = value.scaleDefault or 1
    end
end, MonUtil)

DRMon.defaultOptions = mopt

return DRMon
