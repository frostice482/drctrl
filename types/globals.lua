--- @meta cc._G

--- @type fun(...)
printError = function() end

--- @type fun(replaceChar?: string, history?: table, completeFn?: fun(partial: string): (string[] | nil), default?: string): string
read = function() end