--- @meta cc.fs

--- @alias cc.fs.FileMode "r" | "w" | "a" | "r+" | "w+"
--- @alias cc.fs.Seek "set" | "cur" | "end"

--- @class cc.fs.FileHandleCommon
--- @field seek fun(whence?: cc.fs.Seek, offset?: number): number | nil, string | nil
--- @field close fun()

--- @class cc.fs.ReadHandle: cc.fs.FileHandleCommon
--- @field read fun(count?: number): string | nil
--- @field readAll fun(): string | nil
--- @field readLine fun(withTrailing?: boolean): string | nil

--- @class cc.fs.WriteHandle: cc.fs.FileHandleCommon
--- @field write fun(contents: string | number)
--- @field writeLine fun(text: string)
--- @field flush fun()

--- @class cc.fs.ReadWriteHandle: cc.fs.ReadHandle, cc.fs.WriteHandle

--- @class cc.fs
fs = {
    --- @param file string
    --- @param mode cc.fs.FileMode
    --- @overload fun(file, mode: "r"): cc.fs.ReadHandle
    --- @overload fun(file, mode: "w" | "a"): cc.fs.WriteHandle
    --- @overload fun(file, mode: "r+" | "w+"): cc.fs.ReadWriteHandle
    open = function(file, mode) end;

    --- @param file string
    --- @returns boolean
    exists = function(file) end;
}
