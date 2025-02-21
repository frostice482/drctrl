local constructor = require 'lib/constructor'

---@alias DraconicReactorState 'invalid' | 'offline' | 'stopping' | 'charging' | 'cooling' | 'cold' | 'charged' | 'running' | 'online' | 'warming_up'

---@class DraconicReactorInfo
---@field energySaturation number
---@field failSafe boolean
---@field fieldDrainRate number
---@field fieldStrength number
---@field fuelConversion number
---@field fuelConversionRate number
---@field generationRate number
---@field maxEnergySaturation number
---@field maxFieldStrength number
---@field maxFuelConversion number
---@field status DraconicReactorState
---@field temperature number

---@class DraconicReactorPeripheral
---@field activateReactor fun(): boolean
---@field chargeReactor fun(): boolean
---@field stopReactor fun(): boolean
---@field toggleFailSafe fun(): boolean
---@field getReactorInfo fun(): DraconicReactorInfo | nil

---@class DraconicFluxGate
---@field getFlow fun(): number
---@field getOverrideEnabled fun(): boolean
---@field getSignalHighFlow fun(): number
---@field getSignalLowFlow fun(): number
---@field setFlowOverride fun(override: number)
---@field setOverrideEnabled fun(override: boolean)
---@field setSignalHighFlow fun(flow: number)
---@field setSignalLowFlow fun(flow: number)

---@type fun(seconds: number): nil
sleep = sleep

--- @class DraconicReactorPrototype
--- @field reactor DraconicReactorPeripheral
local DraconicReactorPrototype = {
    ---@param self DraconicReactorPrototype
    charge = function(self)
        return self.reactor.chargeReactor()
    end;

    ---@param self DraconicReactorPrototype
    activate = function(self)
        return self.reactor.activateReactor()
    end;

    ---@param self DraconicReactorPrototype
    stop = function(self)
        return self.reactor.stopReactor()
    end;

    ---@param self DraconicReactorPrototype
    info = function(self)
        return self.reactor.getReactorInfo()
    end;

    -- Charges reactor and wait
    --- @param self DraconicReactorPrototype
    --- @param pollTimeSeconds? number Poll time for status, in seconds
    --- @param forceCharge? boolean Charges if the reactor is somehow stopping
    chargeWait = function(self, pollTimeSeconds, forceCharge)
        pollTimeSeconds = pollTimeSeconds or 0.2
        forceCharge = forceCharge or false

        self:charge()

        while true do
            local info = self:info()
            local status = info and info.status

            -- invalid
            if (not info or status == "invalid") then
                return false
            -- turned offline
            elseif (status == "offline" or status == "stopping" or status == "cooling" or status == "cold") then
                if (forceCharge) then
                    self:charge()
                else
                    return false
                end
            -- charged
            elseif (status == "charged" or info.temperature >= 2000) then
                return true
            -- online
            elseif (status == "running" or status == "online") then
                return true
            end

            sleep(pollTimeSeconds)
        end
    end;
}

--- @class DraconicReactorCalculator
local DraconicReactorCalculator = {
    -- Normalize status
    --- @param self DraconicReactorCalculator
    --- @param reactorInfo DraconicReactorInfo
    --- @param apply? boolean
    normalizeStatus = function(self, reactorInfo, apply)
        local status = reactorInfo.status
        if status == "warming_up" then
            if reactorInfo.temperature >= 2000 then status = "charged"
            else status = "charging" end
        elseif status == "cold" then
            status = "offline"
        elseif status == "running" then
            status = "online"
        end
        if apply then reactorInfo.status = status end
        return status
    end;

    -- Calculate saturation rate
    --- @param self DraconicReactorCalculator
    --- @param reactorInfo DraconicReactorInfo
    saturationRate = function(self, reactorInfo)
        return reactorInfo.energySaturation / reactorInfo.maxEnergySaturation
    end;

    -- Calculate fuel conversion rate
    --- @param self DraconicReactorCalculator
    --- @param reactorInfo DraconicReactorInfo
    convertedFuelRate = function(self, reactorInfo)
        return reactorInfo.fuelConversion / reactorInfo.maxFuelConversion
    end;

    -- Calculates remaining fuel
    --- @param self DraconicReactorCalculator
    --- @param reactorInfo DraconicReactorInfo
    reactableFuel = function(self, reactorInfo)
        return reactorInfo.maxFuelConversion - reactorInfo.fuelConversion
    end;

    -- Calculate conversion level (-0.3 to 1.0)
    --- @param self DraconicReactorCalculator
    --- @param conversionRate number
    conversionLevel = function(self, conversionRate)
        return (conversionRate * 1.3) - 0.3
    end;

    -- Calculate field strength
    --- @param self DraconicReactorCalculator
    --- @param reactorInfo DraconicReactorInfo
    fieldStrength = function(self, reactorInfo)
        return reactorInfo.fieldStrength / reactorInfo.maxFieldStrength
    end;

    --- Calculate normal fuel use rate at specified temperature and saturation.
    --- Note that this isn't affected by the config, which has default multiplier of 0.005.
    --- @param self DraconicReactorCalculator
    --- @param temperature number
    --- @param saturation number
    normalFuelUseRate = function(self, temperature, saturation)
        return self:tempDrainFactor(temperature) * (1 - saturation)
    end;

    --- normalFuelUseRate from reactor
    --- @param info DraconicReactorInfo
    --- @param self DraconicReactorCalculator
    normalFuelUseRateReactor = function(self, info)
        return self:normalFuelUseRate(info.temperature, self:saturationRate(info))
    end;

    -- Calculate field input rate
    --- @param self DraconicReactorCalculator
    --- @param fieldStrengthRate number
    --- @param fieldDrain number
    --- @param temperature number
    fieldInputRate = function(self, fieldStrengthRate, fieldDrain, temperature)
        local tempFactor = 1
        if temperature then
            if temperature >= 25000 then return 0 end
            if temperature > 15000 then tempFactor = 1 - (temperature - 15000) / 10000 end
        end

        if fieldStrengthRate >= 0.999 then fieldStrengthRate = 0.999 end
        return fieldDrain / (1 - fieldStrengthRate) / tempFactor
    end;

    -- Calculate field input rate
    --- @param self DraconicReactorCalculator
    --- @param reactorInfo DraconicReactorInfo
    fieldInputRateReactor = function(self, reactorInfo)
        return self:fieldInputRate(self:fieldStrength(reactorInfo), reactorInfo.fieldDrainRate, reactorInfo.temperature)
    end;

    -- Calculate max energy/tick at saturation = 0
    --- @param self DraconicReactorCalculator
    --- @param generationRate number
    --- @param saturationRate number
    maxRft = function(self, generationRate, saturationRate)
        if saturationRate == 1 or generationRate == 0 then return 1000000 end
        return generationRate / (1 - saturationRate)
    end;

    -- maxRft from reactor info
    --- @param self DraconicReactorCalculator
    --- @param reactorInfo DraconicReactorInfo
    maxRftReactor = function(self, reactorInfo)
        return self:maxRft(reactorInfo.generationRate, self:saturationRate(reactorInfo))
    end;

    -- Calculate baseMaxRft, accounts fuel conversion level for maxRft
    --- @param self DraconicReactorCalculator
    --- @param maxRft number
    --- @param convertedFuelRate number
    baseMaxRft = function(self, maxRft, convertedFuelRate)
        return maxRft / (1 + 2 * self:conversionLevel(convertedFuelRate))
    end;

    -- baseMaxRft from reactor info
    --- @param self DraconicReactorCalculator
    --- @param reactorInfo DraconicReactorInfo
    baseMaxRftReactor = function(self, reactorInfo)
        return self:baseMaxRft(self:maxRftReactor(reactorInfo), self:convertedFuelRate(reactorInfo))
    end;

    -- Calculate temperature drain factor
    --- @param self DraconicReactorCalculator
    --- @param temperature number
    tempDrainFactor = function(self, temperature)
        if temperature > 8000 then return 1 + (temperature - 8000) ^ 2 * 0.0000025
        elseif temperature > 2000 then return 1
        elseif temperature > 1000 then return (temperature - 1000) / 1000
        else return 0
        end
    end;

    -- Calculate exponential temperature rise
    --- @param self DraconicReactorCalculator
    --- @param saturationRate number
    tempRiseExpo = function(self, saturationRate)
        local negSat100 = (1 - saturationRate) * 99
        return negSat100 ^ 3 / (100 - negSat100) + 444.7
    end;

    -- Calculate exponential temperature resistance
    --- @param self DraconicReactorCalculator
    --- @param temperature number
    tempRiseResist = function(self, temperature)
        local temp50 = math.min(temperature / 10000 * 50, 99)
        return temp50 ^ 4 / (100 - temp50)
    end;

    -- Calculates temperature at given saturation and conversion. Temperature ranges from 2000 to 18384
    --- @param self DraconicReactorCalculator
    --- @param saturationRate number
    --- @param convertedFuelRate number
    --- @param precision? number Interval 2^(-n) for temperature approximation. Defaults to 15
    tempAt = function(self, saturationRate, convertedFuelRate, precision)
        precision = precision or 15
        if convertedFuelRate >= 1 then return 25000 end

        local conv = self:conversionLevel(convertedFuelRate)
        local tRise = self:tempRiseExpo(saturationRate)
        local tResist = (conv * 1000 + tRise) / (1 - conv)

        -- approximate temperature from temperature resist
        -- O(n)
        local approx = 2000
        for i = 1,precision,1 do
            local step = 16384 / (2 ^ i)
            local next = approx + step
            if self:tempRiseResist(next) <= tResist then approx = next end
        end

        return approx
    end;

    -- Calculate temperature change
    --- @param self DraconicReactorCalculator
    --- @param temperature number
    --- @param saturationRate number
    --- @param convertedFuelRate number
    tempDelta = function(self, temperature, saturationRate, convertedFuelRate)
        local conv = self:conversionLevel(convertedFuelRate)
        local tRise = self:tempRiseExpo(saturationRate)
        local tResist = self:tempRiseResist(temperature)
        local tResistMult = tResist * (1 - conv)
        return (tRise - tResistMult) / 1000 + conv
    end;

    -- tempDelta from reactor info
    --- @param self DraconicReactorCalculator
    --- @param reactorInfo DraconicReactorInfo
    tempDeltaReactor = function(self, reactorInfo)
        return self:tempDelta(reactorInfo.temperature, self:saturationRate(reactorInfo), self:convertedFuelRate(reactorInfo))
    end;

    -- Calculate target energy saturation from given fuel onversion rate and temperature
    --- @param self DraconicReactorCalculator
    --- @param convertedFuelRate number
    --- @param temperature number
    --- @param precision? number Interval 2^(-n) for temeprature approximation. Defaults to 15
    targetEnergySaturationByTemperature = function(self, convertedFuelRate, temperature, precision)
        if convertedFuelRate >= 1 then convertedFuelRate = 1 end
        precision = precision or 15

        local conv = self:conversionLevel(convertedFuelRate)
        local tResist = self:tempRiseResist(temperature)
        local tRise = tResist * (1 - conv) - 1000 * conv

        -- approximate energy saturation from temperature rise
        -- O(n)
        local approx = 1
        for i = 1,precision,1 do
            local step = 1 / (2 ^ i)
            local next = approx - step
            if self:tempRiseExpo(next) <= tRise then approx = next end
        end

        return approx
    end;

    -- Calculate target field drain from given temperature and saturation
    --- @param self DraconicReactorCalculator
    --- @param baseMaxRft number
    --- @param temperature number
    --- @param saturationRate number
    targetFieldDrain = function(self, baseMaxRft, temperature, saturationRate)
        return self:tempDrainFactor(temperature)
            * math.max(0.01, 1 - saturationRate)
            * baseMaxRft / 10.923556
    end;

    -- Calculate net worth of energy produced for specified temperature.
    --- @param self DraconicReactorCalculator
    --- @param reactorInfo DraconicReactorInfo
    --- @param temperature? number Defaults to 8000
    targetNet = function(self, reactorInfo, temperature)
        temperature = temperature or 8000

        local targetSaturation = self:targetEnergySaturationByTemperature(self:convertedFuelRate(reactorInfo), temperature)
        local maxRft = self:maxRftReactor(reactorInfo)
        local baseMaxRft = self:baseMaxRft(maxRft, self:convertedFuelRate(reactorInfo))
        local targetDrain = self:targetFieldDrain(baseMaxRft, temperature, targetSaturation)
        return maxRft * (1 - targetSaturation) - targetDrain
    end;

    -- Calculate remaining fuel time, in second
    --- @param reactorInfo DraconicReactorInfo
    --- @param targetMax? number
    remainingFuelTimeSecond = function(self, reactorInfo, targetMax)
        targetMax = targetMax or 1

        local remainingFuel = reactorInfo.maxFuelConversion * targetMax - reactorInfo.fuelConversion
        if remainingFuel <= 0 then return 0 end
        local fuelRateBps = reactorInfo.fuelConversionRate / 1000000 * 20
        if fuelRateBps <= 0 then return 999*86400 end
        return remainingFuel / fuelRateBps
    end;

    --- Approximates minimum possible saturation before reaching reactor meltdown. Can also be used to approximate temperature for specified saturation.
    --- @param self DraconicReactorCalculator
    --- @param baseMaxRft number
    --- @param maxDrain number
    --- @param convertedFuelRate number
    --- @param precision? number Interval 2^(-n) for field drain approximation. Defaults to 20
    --- @param tPrecision? number Interval 2^(-n) for temperature approximation
    --- @return number saturation, number temperature, number drain
    minPossibleSaturation = function(self, baseMaxRft, maxDrain, convertedFuelRate, precision, tPrecision)
        precision = precision or 20
        if convertedFuelRate >= 1 then return 1, 25000, maxDrain end

        -- FIeld drain approximation through saturation and temperature
        -- O(n^2) -- i can't believe i'm writing this
        local approx = 1
        local tapprox = 0
        local dapprox = 0
        for i = 1,precision,1 do
            local step = 1 / (2 ^ i)
            local next = approx - step
            local temp = self:tempAt(next, convertedFuelRate, tPrecision)
            local drain = self:targetFieldDrain(baseMaxRft, temp, next)
            if drain < maxDrain then
                approx = next
                tapprox = temp
                dapprox = drain
            end
        end

        return approx, tapprox, dapprox
    end;

    -- minPossibleSaturation for reactor
    --- @param self DraconicReactorCalculator
    --- @param reactorInfo DraconicReactorInfo
    --- @param maxDrain? number
    --- @param precision? number
    --- @param tPrecision? number
    minPossibleSaturationReactor = function(self, reactorInfo, maxDrain, precision, tPrecision)
        maxDrain = maxDrain or reactorInfo.maxFieldStrength
        return self:minPossibleSaturation(self:baseMaxRftReactor(reactorInfo), maxDrain, self:convertedFuelRate(reactorInfo), precision, tPrecision)
    end;
};

--- @alias DraconicReactor Constructable<DraconicReactorPrototype, DraconicReactorPeripheral> | { calculator: DraconicReactorCalculator }
--- @type DraconicReactor
local DraconicReactor = constructor.createConstructor(DraconicReactorPrototype, function(self, arg, target)
    target.reactor = arg
end)
DraconicReactor.calculator = DraconicReactorCalculator

return DraconicReactor
