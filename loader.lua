local Services = setmetatable({}, {
    __index = function(self, name)
        local s = game:GetService(name)
        rawset(self, name, s)
        return s
    end
})

local url = ("https://raw.githubusercontent.com/kio6z/Azurite/refs/heads/main/games/%d/init.lua"):format(game.PlaceId)

local ok, src = pcall(game.HttpGet, game, url, true)
if not ok or type(src) ~= "string" or #src < 20 or src:find("404: Not Found", 1, true) then
    return warn("[Azurite] fetch failed:", game.PlaceId)
end

local chunk = loadstring(src)
if not chunk then
    return warn("[Azurite] compile failed")
end

local ok2, err = pcall(chunk, Services)
if not ok2 then
    warn("[Azurite] runtime error:", err)
end