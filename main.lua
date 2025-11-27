sti = require("lib.sti")
push = require("lib.push")
wf = require("lib.windfield")
require("player")

local mapCollisionLoader = require("maps.mapCollisions")

local GAMESTATE = {
    PLAYING = 1,
    PAUSED = 2,
    GAMEOVER = 3
}
local currentGameState = GAMESTATE.PLAYING

WINDOW_WIDTH, WINDOW_HEIGHT = love.window.getDesktopDimensions()
-- WINDOW_WIDTH, WINDOW_HEIGHT = 1280, 720
VIRTUAL_WIDTH, VIRTUAL_HEIGHT = 256 , 240

local fullscreen = false

local accumulator = 0
local TARGET_FPS = 60
local fixed_dt = 1/TARGET_FPS

function love.load()
    -- settings
    love.graphics.setDefaultFilter("nearest", "nearest")

    push:setupScreen(VIRTUAL_WIDTH, VIRTUAL_HEIGHT, WINDOW_WIDTH, WINDOW_HEIGHT,
    {   fullscreen = fullscreen,
        resizable = false,
        vsync = true,
        pixelperfect = true,
        canvas = true
    })

    -- map
    gameMap = sti("maps/bubbleman/stage_bubbleman.lua")

    world = wf.newWorld(0, 0, true)
    world:setCallbacks(beginContact, endContact)
    world:addCollisionClass("Ground")
    world:addCollisionClass("Water")
    world:addCollisionClass("Death")
    world:addCollisionClass("Player", {ignores = {"Water"}})

    ground = gameMap.layers["Collision"].objects
    death = gameMap.layers["Death"].objects
    water = gameMap.layers["Water"].objects
    room = gameMap.layers["Room"].objects
    entityLayer = gameMap.layers["Entities"].objects

    -- load collision
    mapCollisionLoader.loadCollisionMap(world, ground, "static", "Ground")
    mapCollisionLoader.loadCollisionMap(world, death, "static", "Death", true, 2, -2, -4, -4)
    mapCollisionLoader.loadCollisionMap(world, water, "static", "Water")

    -- load rooms
    rooms = mapCollisionLoader.extractRooms(room)

    -- sound
    sounds = {}

    sounds.music = {
        stage_bubbleman = love.audio.newSource("sounds/music/bubbleman.flac", "stream")
    }

    sounds.sfx = {
        land = love.audio.newSource("sounds/sfx/land.wav", "static"),
        water_splash = love.audio.newSource("sounds/sfx/water_splash.wav", "static")
    }

    currentSong = sounds.music.stage_bubbleman
    currentSong:setLooping(true)
    currentSong:play()

    -- player
    -- This code is correct, even if Tiled says "Class" in the editor
    -- STI reads Tiled's "Class" field into 'object.type'
    for i, object in ipairs(entityLayer) do
        if object.type == "Player" then
            Player:load(object.x, object.y)
        end
    end

    -- register player callbacks
    Player:registerCallbacks({
        onLand = function()
            -- currentGameState = GAMESTATE.PAUSED
        end
    })
end

function love.update(dt)
    if (currentGameState ~= GAMESTATE.PLAYING) then
        return
    end

    accumulator = accumulator + dt
    while accumulator >= fixed_dt do
        world:update(fixed_dt)
        Player:update(fixed_dt)
        accumulator = accumulator - fixed_dt
    end

    gameMap:update(dt)
    cameraMovement(dt)
end

function cameraMovement(dt)
    local targetX = Player.x - VIRTUAL_WIDTH / 2
    local targetY = Player.y - VIRTUAL_HEIGHT / 2

    cameraX = Player.x
    cameraY = Player.y

    cameraX = lerp(cameraX, targetX, 1000 * dt)
    cameraY = lerp(cameraY, targetY, 1000 * dt)

    local room = getCurrentRoom(Player.x, Player.y)
    if room then
        cameraX = math.max(room.x, math.min(cameraX, room.x + room.width - VIRTUAL_WIDTH))
        cameraY = math.max(room.y, math.min(cameraY, room.y + room.height - VIRTUAL_HEIGHT))
    end
end

function love.resize(w,h)
    push:resize(w,h)
end

function love.draw()
    -- clear screen every frame to black before drawing anything
    love.graphics.clear(0 / 255, 0 / 255, 0 / 255)

    -- debugging
    love.graphics.print("Pos X = " .. Player.x, 0, 0, 0, 1, 1)
    love.graphics.print("Pos Y = " .. Player.y, 0, 12, 0, 1, 1)
    love.graphics.print("Vel X = " .. Player.xVel, 0, 24, 0, 1, 1)
    love.graphics.print("Vel Y = " .. Player.yVel, 0, 36, 0, 1, 1)
    love.graphics.print("Player State: " .. Player.currentState, 0, 48, 0, 1, 1)
    love.graphics.print("Grounded: " .. tostring(Player.grounded), 0, 60, 0, 1, 1)
    love.graphics.print("Player Width: " .. Player.width, 0, 72, 0, 1, 1)
    love.graphics.print("Player Height: " .. Player.height, 0, 84, 0, 1, 1)
    love.graphics.print("Player Ground Inset: " .. Player:getGroundCheckInset(), 0, 96, 0, 1, 1)
    love.graphics.print("Player Wall Inset: " .. Player:getWallCheckInset(), 0, 108, 0, 1, 1)
    love.graphics.print("Accumulator: " .. accumulator, 0, WINDOW_HEIGHT - 48, 0, 2, 2)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 0, WINDOW_HEIGHT - 24, 0, 2, 2)

    push:start()
        -- game Background
        love.graphics.clear(0, 112 / 255, 236 / 255)
        love.graphics.push()
        -- move world to camera view
        love.graphics.translate(-cameraX, -cameraY)
        -- Draw Background layer (behind player)
        local bgLayer = gameMap.layers["Background"]
        if bgLayer and bgLayer.visible then
            gameMap:drawLayer(bgLayer)
        end
        local deathLayer = gameMap.layers["Death"]
        if deathLayer and deathLayer.visible then
            gameMap:drawLayer(deathLayer)
        end
        -- Draw Player
        Player:draw()
        -- Draw Ground layer (in front of player)
        local groundLayer = gameMap.layers["Ground"]
        if groundLayer and groundLayer.visible then
            gameMap:drawLayer(groundLayer)
        end
        -- draw collisions
        world:draw(0.1)
        -- debug gizmos
        Player:drawGizmos()
        love.graphics.pop()
    push:finish()
end

-- input callbacks
function love.keypressed(key)
	Player:jump(key)
    Player:reset(key)

    if key == "escape" then
        if currentGameState == GAMESTATE.PLAYING then
            currentGameState = GAMESTATE.PAUSED
            currentSong:pause()
        elseif currentGameState == GAMESTATE.PAUSED then
            currentGameState = GAMESTATE.PLAYING
            currentSong:play()
        end
    end

    if key == "right" then
        Player.width = Player.width + 1
    elseif key == "left" then
        Player.width = Player.width - 1
    end

    if key == "up" then
        Player.height = Player.height + 1
    elseif key == "down" then
        Player.height = Player.height - 1
    end
end

function love.keyreleased(key)
    Player:stopJump(key)
end

-- collision callbacks
function beginContact(a, b, col)
    Player:beginContact(a, b, col)
end

function endContact(a, b, collision)
    Player:endContact(a, b, collision)
end

-- utilities
function lerp(a, b, t)
    return a + (b - a) * math.min(t, 1)
end

function getCurrentRoom(px, py)
    for _, room in ipairs(rooms) do
        if px >= room.x and px <= room.x + room.width and
           py >= room.y and py <= room.y + room.height then
            return room
        end
    end
    return nil
end