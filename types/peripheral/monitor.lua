--- @class MonitorPeripheral
--- @field nativePaletteColor fun(colour: number): number, number, number
--- @field write fun(text: string)
--- @field scroll fun(y: number)
--- @field getCursorPos fun(): number, number
--- @field setCursorPos fun(x: number, y: number)
--- @field getCursorBlink fun(): boolean
--- @field setCursorBlink fun(blink: boolean)
--- @field getSize fun(): number, number
--- @field clear fun()
--- @field clearLine fun()
--- @field getTextColor fun(): number
--- @field setTextColor fun(colour: number)
--- @field getBackgroundColor fun(): number
--- @field setBackgroundColor fun(colour: number)
--- @field isColor fun(): boolean
--- @field blit fun(text: string, textColour: string, backgroundColour: string)
--- @field setPaletteColor fun(number...)
--- @field getPaletteColor fun(colour: number): number, number, number
