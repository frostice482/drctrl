--- @meta cc.textutils

--- @class cc.textutils
textutils = {
    --- @param t any
    --- @param opts? {compact?: boolean, allow_repetitions?: boolean}
    --- @return string
    serialize = function(t, opts) end;

    --- @param t string
    --- @returns any
    unserialize = function(t) end;
}