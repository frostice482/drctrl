-- Gets peripheral and checks for peripheral type
---@param perName string Peripheral name
---@param perTypes string[] Peripheral type
---@param optional? boolean
---@return any
local function getPeripheral(perName, perTypes, optional)
    local retType = peripheral.getType(perName)

    -- check if null
    if not retType then
        if optional then return nil end
        error("per " .. perName .. " is nil")
    end

    -- check type inequality
    for i, type in ipairs(perTypes) do
        if retType == type then return peripheral.wrap(perName) end
    end

    error("per " .. perName .. " expects " .. table.concat(perTypes, ", ") .. " but got " .. retType)
end

-- Waits for key press
---@param keyNum? number Key number, defaults to backslash
local function waitKey(keyNum)
    keyNum = keyNum or keys.backslash

    repeat
        local _, key = os.pullEvent("key")
    until key == keyNum
end

--- @param num number
local function round(num)
    return math.floor(num + 0.5)
end

local function table_shallowcopy(table, target)
    target = target or {}
    for k,v in pairs(table) do
        target[k] = v
    end
    return target
end

return {
    getPeripheral = getPeripheral,
    waitKey = waitKey,
    round = round,
    table_shallowcopy = table_shallowcopy
}