local constructor = require 'lib/constructor'

--- @class MonUtilTouchListener
--- @field x1 number
--- @field x2 number
--- @field y1 number
--- @field y2 number
--- @field id number
--- @field func fun(x: number, y: number): nil

--- @alias MonUtilTouchListenerSet table<number, MonUtilTouchListener>

--- @class MonUtilPrototype: MonitorPeripheral
--- @field mon MonitorPeripheral
--- @field touchListeners { [number]: MonUtilTouchListener }
--- @field _tlid number
--- @field _sx number | nil
--- @field _sy number | nil
local MonUtilPrototype = {
    --- @param self MonUtilPrototype
    --- @param text string
    --- @param textColor number | nil
    --- @param backgroundColor number | nil
    --- @param restore? boolean
    blitn = function(self, text, textColor, backgroundColor, restore)
        local oText = self.getTextColor()
        local oBg = self.getBackgroundColor()

        -- replace text & bg
        if textColor then self.setTextColor(textColor) end
        if backgroundColor then self.setBackgroundColor(backgroundColor) end
        -- write
        self.write(text)
        -- restore original text & bg
        if restore ~= false then
            if textColor then self.setTextColor(oText) end
            if backgroundColor then self.setBackgroundColor(oBg) end
        end

        return self
    end;

    --- @param self MonUtilPrototype
    setCursorStart = function(self)
        local x, y = self.getCursorPos()
        self._sx = x
        self._sy = y
        return self
    end;

    --- @param self MonUtilPrototype
    --- @param x number | nil
    --- @param y number | nil
    UsetCursorPos = function(self, x, y)
        local xn, yn = self.getSize()
        self.mon.setCursorPos(
            not x and xn or x <= 0 and xn + x or x or 0,
            not y and yn or y <= 0 and yn + y or y or 0
        )
        return self
    end;

    --- @param self MonUtilPrototype
    --- @param x number
    --- @param y number
    UmoveCursor = function(self, x, y)
        local xn, yn = self.getCursorPos()
        self.mon.setCursorPos( x + xn, y + yn )
        return self
    end;

    --- @param self MonUtilPrototype
    --- @param func fun(x: number, y: number): nil
    --- @param set MonUtilTouchListenerSet | nil
    --- @param x1? number
    --- @param x2? number
    --- @param y1? number
    --- @param y2? number
    listenTouch = function(self, func, set, x1, y1, x2, y2)
        local x, y = self.getCursorPos()
        local xn, yn = self.getSize()
        x1 = x1 and x1 < 1 and xn - x1 or self._sx or x
        y1 = y1 and y1 < 1 and yn - y1 or self._sy or y
        x2 = x2 and x2 < 1 and xn - x2 or x - 1
        y2 = y2 and y2 < 1 and yn - y2 or y

        if y2 < y1 or y2 == y1 and x2 < x1 then
            local tmp
            -- swap y
            tmp = y2
            y2 = y1
            y1 = tmp
            -- swap x
            tmp = x2
            x2 = x1
            x1 = tmp
        end

        local id = self._tlid
        local data = {
            x1 = x1;
            y1 = y1;
            x2 = x2;
            y2 = y2;
            func = func,
            id = id
        }
        self._tlid = id + 1
        self.touchListeners[id] = data
        if set then set[id] = data end

        return id
    end;

    --- @param self MonUtilPrototype
    --- @param x number
    --- @param y number
    --- @return MonUtilTouchListener | nil
    getTouchListenerAt = function(self, x, y)
        for index, value in pairs(self.touchListeners) do
            if y == value.y1 and value.x1 <= x and (x <= value.x2 or value.y1 < value.y2)
                or y == value.y2 and x <= value.x2 and (value.x1 <= x or value.y1 < value.y2)
                or value.y1 < y and y < value.y2
            then
                return value
            end
        end
    end;

    --- @param self MonUtilPrototype
    --- @param set? MonUtilTouchListenerSet | nil
    clearTouchListener = function(self, set)
        if set then
            local cp = {}
            for key, value in pairs(set) do
                table.insert(cp, key)
            end
            for index, key in ipairs(cp) do
                self.touchListeners[key] = nil
                cp[set] = 0
            end
        else
            self.touchListeners = {}
        end
    end;
}

--- @alias MonUtil Constructable<MonUtilPrototype, MonitorPeripheral>
--- @type MonUtil
local MonUtil = constructor.createConstructor(MonUtilPrototype, function (self, arg, target)
    target.mon = arg
    target.touchListeners = {}
    target._tlid = 1

    for key, value in pairs(arg) do target[key] = value end
end)

return MonUtil
