local anim8 = require("lib.anim8")

local WaterSplash = {}
WaterSplash.__index = WaterSplash

function WaterSplash.new(x, y, spriteSheet, grid)
    local self = setmetatable({}, WaterSplash)
    self.x = x
    self.y = y
    self.spriteSheet = spriteSheet
    self.anim = anim8.newAnimation(grid("1-4", 1), 0.1, "pauseAtEnd")
    self.isDone = false
    return self
end

function WaterSplash:update(dt)
    self.anim:update(dt)
    if self.anim.position == #self.anim.frames then
        self.isDone = true
    end
end

function WaterSplash:draw()
    self.anim:draw(self.spriteSheet, self.x, self.y, nil, 1, 1, 10, 10)
end

return WaterSplash