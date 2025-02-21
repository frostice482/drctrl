local base = "https://raw.githubusercontent.com/frostice482/drctrl/refs/heads/master/"

local function wget(url, filename, dir, nooverride)
    if nooverride and fs.exists(dir..'/'..filename) then return end
    if dir then fs.makeDir(dir) end

    local res = http.get(url)
    if not res then error("nil") end

    local fd = fs.open(dir .. '/' .. filename, "w")
    fd.write(res.readAll())
    fd.close()
    res.close()
end

local filelist = {
    { file = "constructor", dir = "lib" },
    { file = "draconicreactor", dir = "lib" },
    { file = "drmon", dir = "lib" },
    { file = "monutil", dir = "lib" },
    { file = "util", dir = "lib" },
    { file = "install" },
    { file = "main" },
    { file = "peripherals_config", nooverride = true },
}

if not require then table.insert(filelist, { file = "impl_require", dir = "lib" }) end

local function fork(value)
    local dir = value.dir or "."
    local filename = value.file
    local fileurl = value.url or dir.."/"..filename..".lua"
    fileurl = base .. fileurl

    local status, err = pcall(wget, fileurl, filename, dir, value.nooverride)
    if not status then printError("wget " .. fileurl .. " -> " .. filename .. " error! ", err) end
end

local function fork2(index)
    local value = filelist[index]
    if value == nil then return end

    parallel.waitForAll(
        function() fork2(index+1) end,
        function() fork(value) end
    )
end


fork2(1)