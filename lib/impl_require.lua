-- implement require for older versions (e.g. 1.7.10)
if not require then
    _G.requires = {}

    --- @param modname string
    _G.require = function(modname)
        if requires[modname] then return requires[modname] end

        local fd = fs.open(modname, "r")
        if not fd then fd = fs.open(modname..".lua", "r") end
        if not fd then error("Cannot find "..modname) end

        local content = fd.readAll()
        fd.close()

        local fn, err = load(content, modname, "t")
        if not fn or err then error("Failed to load "..modname..": "..err) end

        local res = fn()
        requires[modname] = res
        return res
    end
end