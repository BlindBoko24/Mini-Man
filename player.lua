-- libraries
anim8 = require("lib.anim8")
local WaterSplash = require("vfx.player.water_splash")

Player = {}
Player.callbacks = {}

local PLAYERSTATE = {
    IDLE = "idle",
    RUN = "run",
    AIR = "air"
}

function Player:registerCallbacks(callbacksTable)
    self.callbacks = callbacksTable
end

function Player:load(posX, posY)
    self.initialX = posX
    self.initialY = posY
    self.x = posX -- This is now the 'source of truth' for physics X
    self.y = posY -- This is now the 'source of truth' for physics Y
    self.width = 10
    self.height = 12
    self.facingDirection = 1
    self.xVel = 0
    self.yVel = 0
    self.maxSpeed = 100
    self.acceleration = 4000
    self.friction = 2000

    self.waterContacts = 0

    self.normalGravity = 1300
    self.waterGravity = 460
    self.gravity = self.normalGravity

    self.waterFallSpeed = 200
    self.normalFallSpeed = 600
    self.maxFallSpeed = self.normalFallSpeed

    self.jumpForce = -300
    self.jumpTime = 0.1

    self.graceTime = 0
    self.graceDuration = 0.05

    -- === GROUND/CEILING VARIABLES ===
    self.grounded = false
    self.wasGroundedLastFrame = false -- For detecting landing
    function Player:getGroundCheckInset()
        return self.width * 1
    end
    self.groundL = false
    self.groundM = false
    self.groundR = false
    self.isTouchingCeiling = false
    self.ceilingL = false
    self.ceilingM = false
    self.ceilingR = false

    -- === WALL VARIABLES ===
    function Player:getWallCheckInset()
        return self.height * 1
    end
    self.isTouchingLeft = false
    self.isTouchingRight = false

    self.currentState = PLAYERSTATE.IDLE

    self.pendingReset = false

    self:loadAssets()

    -- Create the collider, but it will be used as a SENSOR
    self.collider = world:newRectangleCollider(self.x, self.y, self.width, self.height)
    self.collider:setBullet(true)
    self.collider:setFriction(0)
    self.collider:setType("dynamic")
    self.collider:setFixedRotation(true)
    self.collider:setCollisionClass("Player")
    self.collider:setUserData("Player")
    -- self.collider:setSensor(true)
    self.collider:setGravityScale(0)
end

function Player:loadAssets()
    self.spriteSheet = love.graphics.newImage("sprites/player/megaman_sheet.png") 
    self.grid = anim8.newGrid(20, 20, self.spriteSheet:getWidth(), self.spriteSheet:getHeight())

    -- vfx loadAssets
    -- water_splash
    self.splashes = {}
    self.splashSpriteSheet = love.graphics.newImage("sprites/player/water_splash.png")
    self.splashGrid = anim8.newGrid(16, 32, self.splashSpriteSheet:getWidth(), self.splashSpriteSheet:getHeight())

    -- setup animations
    self.animations = {}

    -- idle
    self.animations.idle = anim8.newAnimation(self.grid("1-2", 1), {math.random(1, 3), 0.1})

    -- walk
    local f1 = self.grid(1, 3)[1]
    local f2 = self.grid(1, 4)[1]
    local f3 = self.grid(1, 5)[1]

    local frames = { f1, f2, f3, f2 }

    self.animations.walk = anim8.newAnimation(frames, 0.1)

    -- jump
    self.animations.jump = anim8.newAnimation(self.grid(1, 6), 1)

    self.anim = self.animations.idle
end

function Player:setRandomIdleDuration()
    idleDuration = math.random(1, 3) -- random duration

    self.animations.idle = anim8.newAnimation(self.grid("1-2", 1), {idleDuration, 0.05})
end

-- *** UPDATE ORDER (Unchanged, this order is correct) ***
function Player:update(dt)
    -- (1) Calculate velocity based on input and gravity
    self:move(dt) -- Calculates self.xVel
    self:applyGravity(dt) -- Calculates self.yVel (based on *last frame's* grounded state)

    -- (2) Handle jump boost timer
    if self.jumpTimer and self.jumpTimer > 0 then
        self.jumpTimer = self.jumpTimer - dt
        self.yVel = self.yVel + self.jumpForce * dt
    end

    -- (3) Resolve movement & collisions using Continuous Collision Detection (CCD)
    self:resolveVerticalMovement(dt)   -- Sets self.y, self.yVel, self.grounded, self.isTouchingCeiling
    self:resolveHorizontalMovement(dt) -- Sets self.x, self.xVel, self.isTouchingLeft, self.isTouchingRight

    -- (4) Handle landing logic
    if self.grounded and not self.wasGroundedLastFrame then
        self:land()
    end
    self.wasGroundedLastFrame = self.grounded

    -- (5) Update states, animations, and timers
    self:setState()
    self:setDirection()
    self.anim:update(dt)
    self:decreaseGraceTime(dt)
    
    -- (6) Sync the sensor collider to our new manual position
    self:syncPhysics()

    -- (7) Update visual effects
    for i = #self.splashes, 1, -1 do
        local splash = self.splashes[i]
        splash:update(dt)

        if splash.isDone then
            table.remove(self.splashes, i)
        end
    end

    -- (8) Handle reset
    if self.pendingReset then
        self:resetPos()
        self.pendingReset = false
    end
end

-- Now sets L/M/R flags for ground and ceiling
function Player:resolveVerticalMovement(dt)
    -- Reset ALL vertical flags
    self.grounded = false
    self.isTouchingCeiling = false
    self.groundL, self.groundM, self.groundR = false, false, false
    self.ceilingL, self.ceilingM, self.ceilingR = false, false, false
    
    local dy = self.yVel * dt
    local px, py = self.x, self.y 
    local halfWidth = self.width / 2
    local halfHeight = self.height / 2

    -- X-positions for the 3 rays
    local inset = self:getGroundCheckInset()
    local left_x = px - halfWidth + inset
    local mid_x = px
    local right_x = px + halfWidth - inset 

    local groundFilter = function(fixture) return fixture:getUserData() == "Ground" end
    local closestHit = nil
    
    local buffer = 1 

    if dy >= 0 then -- === MOVING DOWN or STATIONARY ===
        local bottom_y = py + halfHeight
        local checkDistance = (dy > 0) and (dy + buffer) or buffer
        
        -- Cast Left Ray
        world:rayCast(left_x, bottom_y, left_x, bottom_y + checkDistance, function(f, x, y, xn, yn, frac)
            if groundFilter(f) then
                self.groundL = true -- Set L flag
                if not closestHit or frac < closestHit.frac then
                    closestHit = {x = x, y = y, frac = frac}
                end
                return frac
            end
            return 1
        end)
        
        -- Cast Middle Ray
        world:rayCast(mid_x, bottom_y, mid_x, bottom_y + checkDistance, function(f, x, y, xn, yn, frac)
            if groundFilter(f) then
                self.groundM = true -- Set M flag
                if not closestHit or frac < closestHit.frac then
                    closestHit = {x = x, y = y, frac = frac}
                end
                return frac
            end
            return 1
        end)

        -- Cast Right Ray
        world:rayCast(right_x, bottom_y, right_x, bottom_y + checkDistance, function(f, x, y, xn, yn, frac)
            if groundFilter(f) then
                self.groundR = true -- Set R flag
                if not closestHit or frac < closestHit.frac then
                    closestHit = {x = x, y = y, frac = frac}
                end
                return frac
            end
            return 1
        end)

        -- Set main grounded flag based on L/M/R
        self.grounded = self.groundL or self.groundM or self.groundR

        if closestHit then
            self.y = closestHit.y - halfHeight - 0.01 -- SNAP to hit position
            self.yVel = 0
        elseif dy > 0 then
            self.y = self.y + dy -- No collision, AND we were moving, so move freely
        end
        
    else -- === MOVING UP (dy < 0) ===
        local top_y = py - halfHeight
        local checkDistance = dy - buffer

        -- Cast Left Ray
        world:rayCast(left_x, top_y, left_x, top_y + checkDistance, function(f, x, y, xn, yn, frac)
            if groundFilter(f) then
                self.ceilingL = true -- Set L flag
                if not closestHit or frac < closestHit.frac then
                    closestHit = {x = x, y = y, frac = frac}
                end
                return frac
            end
            return 1
        end)

        -- Cast Middle Ray
        world:rayCast(mid_x, top_y, mid_x, top_y + checkDistance, function(f, x, y, xn, yn, frac)
            if groundFilter(f) then
                self.ceilingM = true -- Set M flag
                if not closestHit or frac < closestHit.frac then
                    closestHit = {x = x, y = y, frac = frac}
                end
                return frac
            end
            return 1
        end)

        -- Cast Right Ray
        world:rayCast(right_x, top_y, right_x, top_y + checkDistance, function(f, x, y, xn, yn, frac)
            if groundFilter(f) then
                self.ceilingR = true -- Set R flag
                if not closestHit or frac < closestHit.frac then
                    closestHit = {x = x, y = y, frac = frac}
                end
                return frac
            end
            return 1
        end)

        -- Set main ceiling flag based on L/M/R
        self.isTouchingCeiling = self.ceilingL or self.ceilingM or self.ceilingR

        if closestHit then
            self.y = closestHit.y + halfHeight + 0.01 -- SNAP to hit position
            self.yVel = 0
            if self.jumpTimer then self.jumpTimer = 0 end 
        else
            self.y = self.y + dy -- No collision, move freely
        end
    end
end

-- *** UPDATED/FIXED FUNCTION ***
function Player:resolveHorizontalMovement(dt)
    -- Assume no wall collision until a raycast proves otherwise
    self.isTouchingLeft = false
    self.isTouchingRight = false

    local dx = self.xVel * dt
    local px, py = self.x, self.y 
    local halfWidth = self.width / 2
    local halfHeight = self.height / 2

    -- Y-positions for the 3 rays
    local inset = self:getWallCheckInset()
    local top_y = py - halfHeight + inset
    local mid_y = py
    local bottom_y = py + halfHeight - inset

    local groundFilter = function(fixture) return fixture:getUserData() == "Ground" end
    local closestHit = nil

    -- Safety buffer for raycast
    local buffer = 1

    if dx > 0 then -- === MOVING RIGHT or STATIONARY (dx == 0) ===
        local right_x = px + halfWidth
        
        -- If stationary (dx==0), check 'buffer' distance. If moving, check 'dx + buffer'.
        local checkDistance = (dx > 0) and (dx + buffer) or buffer
        
        local rays = {top_y, mid_y, bottom_y}
        for _, ry in ipairs(rays) do
            world:rayCast(right_x, ry, right_x + checkDistance, ry, function(f, x, y, xn, yn, frac)
                if groundFilter(f) then
                    if not closestHit or frac < closestHit.frac then
                        closestHit = {x = x, y = y, frac = frac}
                    end
                    return frac
                end
                return 1
            end)
        end

        if closestHit then
            self.x = closestHit.x - halfWidth - 0.01 -- SNAP to hit position
            self.xVel = 0
            self.isTouchingRight = true
        elseif dx > 0 then
            self.x = self.x + dx -- No collision, AND we were moving, so move freely
        end
        
    elseif dx < 0 then -- === MOVING LEFT ===
        local left_x = px - halfWidth
        
        -- Check full 'dx - buffer' distance (dx is negative)
        local checkDistance = dx - buffer

        local rays = {top_y, mid_y, bottom_y}
        for _, ry in ipairs(rays) do
            world:rayCast(left_x, ry, left_x + checkDistance, ry, function(f, x, y, xn, yn, frac)
                if groundFilter(f) then
                    if not closestHit or frac < closestHit.frac then
                        closestHit = {x = x, y = y, frac = frac}
                    end
                    return frac
                end
                return 1
            end)
        end

        if closestHit then
            self.x = closestHit.x + halfWidth + 0.01 -- SNAP to hit position
            self.xVel = 0
            self.isTouchingLeft = true
        else
            self.x = self.x + dx -- No collision, move freely
        end
    end
end

function Player:setState()
    -- This function now runs *after* collisions are resolved,
    -- so self.grounded is 100% accurate for the current frame.
    if not self.grounded then
       self.currentState = PLAYERSTATE.AIR
       self.anim = self.animations.jump
    elseif self.xVel == 0 then
       self.currentState = PLAYERSTATE.IDLE
       Player:setRandomIdleDuration()
       self.anim = self.animations.idle
    else
       self.currentState = PLAYERSTATE.RUN
       self.anim = self.animations.walk
    end
end

function Player:setDirection()
    if self.xVel < 0 then
       self.facingDirection = -1
    elseif self.xVel > 0 then
       self.facingDirection = 1
    end
end

function Player:decreaseGraceTime(dt)
    -- We use wasGroundedLastFrame here to allow grace time
    -- just as the player *leaves* a ledge.
    if not self.wasGroundedLastFrame then
       self.graceTime = self.graceTime - dt
    end
end

function Player:applyGravity(dt)
    -- Gravity is applied based on the grounded state from the *start* of the frame
    -- This is correct, as resolveVerticalMovement will cancel it if we hit ground
    if not self.grounded then
        if self.yVel < self.maxFallSpeed then
            self.yVel = self.yVel + self.gravity * dt
        else
            self.yVel = self.maxFallSpeed
        end
    end
end

function Player:move(dt)
    local moveInput = 0

    -- Keyboard
    if love.keyboard.isDown("d") then
        moveInput = moveInput + 1
    end
    if love.keyboard.isDown("a") then
        moveInput = moveInput - 1
    end
    -- Controller (left stick X-axis)
    local joysticks = love.joystick.getJoysticks()
    if joysticks[1] and joysticks[1]:isGamepad() then
        local lx = joysticks[1]:getGamepadAxis("leftx")
        -- Deadzone to prevent drift
        if math.abs(lx) > 0.2 then
            moveInput = lx
        end
    end
    
    -- Apply input
    -- The isTouching flags are from the *previous* frame,
    -- but resolveHorizontalMovement will stop it anyway.
    if (moveInput > 0 and not self.isTouchingRight) or (moveInput < 0 and not self.isTouchingLeft) then
        self.xVel = math.max(-self.maxSpeed, math.min(self.maxSpeed, self.xVel + self.acceleration * moveInput * dt))
    -- Stop if moving into a wall
    elseif (moveInput > 0 and self.isTouchingRight) or (moveInput < 0 and self.isTouchingLeft) then
        self.xVel = 0
    end
    
    -- Apply friction if no input
    if moveInput == 0 then
        -- Using your 'stop on a dime' logic
        self.xVel = 0 
    end
end

function Player:land()
    self.yVel = 0
    self.hasDoubleJump = false
    self.graceTime = self.graceDuration
    sounds.sfx.land:play()

    if (self.callbacks.onLand) then
        self.callbacks.onLand()
    end
end

function love.gamepadpressed(joystick, button)
    if button == "b" then
        Player:jump(button)
    end
end

function love.gamepadreleased(joystick, button)
    if button == "b" then
        Player:stopJump(button)
    end
end

-- Jump press
function Player:jump(key)
    if key == "space" or key == "b" then
        -- Check graceTime OR if we are *actually* grounded
        if self.grounded or self.graceTime > 0 then
            self.yVel = self.jumpForce -- Set initial velocity
            self.graceTime = 0
            self.jumpTimer = self.jumpTime -- Start the boost timer
        elseif self.hasDoubleJump then
            self.hasDoubleJump = false
            self.yVel = self.jumpForce * 1.3
            self.jumpTimer = self.jumpTime
        end
    end
end

function Player:stopJump(key)
    if (key == "space" or key == "b") and self.yVel < self.jumpForce * 0.2 then
        self.yVel = self.jumpForce * 0.2
    end
end

function Player:applyFriction(dt)
    if self.xVel > 0 then
        if self.xVel - self.friction * dt > 0 then
            self.xVel = self.xVel - self.friction * dt
        else
            self.xVel = 0
        end
    elseif self.xVel < 0 then
        if self.xVel + self.friction * dt < 0 then
            self.xVel = self.xVel + self.friction * dt
        else
            self.xVel = 0
        end
    end
end

function Player:syncPhysics()
    -- We manually update the sensor's position
    self.collider:setPosition(self.x, self.y)
end

-- On Collision Enter
-- This will STILL WORK because the collider is now a sensor
function Player:beginContact(a, b, collision)
    if a:getUserData() == "Water" or b:getUserData() == "Water" then
        if self.waterContacts == 0 then
            local splash = WaterSplash.new(self.x + 6, self.y - 3, self.splashSpriteSheet, self.splashGrid)
            table.insert(self.splashes, splash)

            sounds.sfx.water_splash:play()
        end

        self.waterContacts = self.waterContacts + 1
        self.gravity = self.waterGravity
        self.maxFallSpeed = self.waterFallSpeed
    end

    if a:getUserData() == "Death" then
        self.pendingReset = true
    end
end

-- This will STILL WORK
function Player:endContact(a, b, collision)
    if a:getUserData() == "Water" or b:getUserData() == "Water" then
        self.waterContacts = self.waterContacts - 1
        if self.waterContacts <= 0 then
            self.gravity = self.normalGravity
            self.maxFallSpeed = self.normalFallSpeed
            self.waterContacts = 0
        end
    end
end

function Player:reset(key)
    if (key == "tab") then
        self:resetPos()
    end
end

-- *** UPDATED FUNCTION ***
-- Resets our manual physics state
function Player:resetPos()
    self.x = self.initialX
    self.y = self.initialY
    self.xVel = 0
    self.yVel = 0
    -- Also reset the sensor's position
    self.collider:setPosition(self.initialX, self.initialY)
end

-- *** UPDATED FUNCTION ***
-- Adds the draw offset that used to be in syncPhysics
function Player:draw()
    -- Draw the player at the physics position (self.x, self.y)
    -- We add 3 to the y-pos to match the offset from your old syncPhysics
    self.anim:draw(self.spriteSheet, self.x, self.y + 3, nil, self.facingDirection, 1, 8, 16)

    for _, splash in ipairs(self.splashes) do
        splash:draw()
    end
end

-- Gizmos now draw as points based on L/M/R flags
function Player:drawGizmos()
    -- Use our manual physics position
    local px, py = self.x, self.y
    local halfWidth = self.width / 2
    local halfHeight = self.height / 2
    
    -- Get the inset values from your Player variables
    -- Note: If you set groundCheckInset = (self.width / 2) * 2, g_inset will be 10.
    -- If you meant 2 pixels, you should change it in Player:load.
    local g_inset = self:getGroundCheckInset()
    local w_inset = self:getWallCheckInset()

    love.graphics.push()
    
    local gColorR = {1, 0, 0, 1} -- Red (No collision)
    local gColorG = {0, 1, 0, 1} -- Green (Collision)

    -- Set point size to be visible
    love.graphics.setPointSize(1)

    -- === Ground Check Points ===
    -- Calculate the x-positions based on the inset
    local g_left_x = px - halfWidth + g_inset
    local g_mid_x = px
    local g_right_x = px + halfWidth - g_inset
    local bottom_y = py + halfHeight

    -- === Ceiling Check Points ===
    local top_y = py - halfHeight

    -- === Wall Check Points ===
    -- Calculate the y-positions based on the inset
    local w_top_y = py - halfHeight + w_inset
    local w_mid_y = py
    local w_bottom_y = py + halfHeight - w_inset

    -- Left Wall (Draws 3 points, all colored by the single isTouchingLeft flag)
    local left_x = px - halfWidth
    love.graphics.setColor(self.isTouchingLeft and gColorG or gColorR)
    love.graphics.points(left_x, w_mid_y)
    love.graphics.points(left_x, w_bottom_y)

    -- Right Wall (Draws 3 points, all colored by the single isTouchingRight flag)
    local right_x = px + halfWidth
    love.graphics.setColor(self.isTouchingRight and gColorG or gColorR)
    love.graphics.points(right_x, w_top_y)
    love.graphics.points(right_x, w_mid_y)
    love.graphics.points(right_x, w_bottom_y)

    -- Draw the 3 ground points, coloring them individually
    love.graphics.setColor(self.groundL and gColorG or gColorR)
    love.graphics.points(g_left_x, bottom_y)

    love.graphics.setColor(self.groundM and gColorG or gColorR)
    love.graphics.points(g_mid_x, bottom_y)

    love.graphics.setColor(self.groundR and gColorG or gColorR)
    love.graphics.points(g_right_x, bottom_y)

    -- Draw the 3 ceiling points, coloring them individually
    love.graphics.setColor(self.ceilingL and gColorG or gColorR)
    love.graphics.points(g_left_x, top_y)

    love.graphics.setColor(self.ceilingM and gColorG or gColorR)
    love.graphics.points(g_mid_x, top_y)

    love.graphics.setColor(self.ceilingR and gColorG or gColorR)
    love.graphics.points(g_right_x, top_y)

    love.graphics.pop()
end