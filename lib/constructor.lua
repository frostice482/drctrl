--- @class Constructable<Proto, Arg, Super>: {
---     super: Super | nil;
---     prototype: Proto;
---     new: fun(self: Constructable<Proto, Arg, Super>, arg: Arg): Proto;
---     __new: fun(self: Constructable<Proto, Arg, Super>, arg: Arg, target: Proto);
--- }
--- @alias ConstructableDefault Constructable<table, any, table>

--- @param constructor ConstructableDefault
--- @param arg any
--- @param target table | nil
local function construct(constructor, arg, target)
    local obj = target or {}
    if not target then setmetatable(obj, { __index = constructor.prototype }) end
    constructor:__new(arg, obj)
    return obj
end

--- @param proto table
--- @param callable fun(self: ConstructableDefault, arg: any, target: table) | nil
--- @param super ConstructableDefault | nil
local function createConstructor(proto, callable, super)
    if super then setmetatable(proto, { __index = super.prototype }) end

    --- @type ConstructableDefault
    local obj = {
        super = super,
        prototype = proto,
        new = construct,
        __new = callable or function (self, arg, target)
            if self.super then self.super:__new(arg, target) end
        end
    }
    return obj
end

return {
    construct = construct,
    createConstructor = createConstructor
}