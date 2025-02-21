--- @meta cc.peripheral

--- @class cc.peripheral
--- @field getNames fun(): string[]
--- @field isPresent fun(name: string): boolean
--- @field getType fun(peripheral: string | table): string[]
--- @field hasType fun(peripheral: string | table, peripheral_type: string): boolean
--- @field getMethods fun(name: string): string[]
--- @field getName fun(peripheral: any): string
--- @field call fun(name: string, method: string, ...): boolean
--- @field wrap fun(name: string): table | nil
--- @field find fun(type: string, filter: nil | (fun(name: string, wrapped: table): boolean)): table[]
peripheral = {}