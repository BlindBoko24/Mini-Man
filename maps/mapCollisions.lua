local mapCollisionLoader = {}

-- Load map collision from object layer with optional shift (dx, dy) and size adjustment (dw, dh)
function mapCollisionLoader.loadCollisionMap(world, objects, type, class, adjust, dx, dy, dw, dh, solid)
    dx = dx or 0
    dy = dy or 0
    dw = dw or 0
    dh = dh or 0

    for _, obj in ipairs(objects) do
        local x = obj.x + dx
        local y = obj.y + dy
        local w = obj.width + dw
        local h = obj.height + dh

        if w > 0 and h > 0 then
            local collider = world:newRectangleCollider(x, y, w, h)
            collider:setType(type or "static")

            if class and class ~= "" then
                collider:setCollisionClass(class)
                collider:setUserData(class)
            end

            if adjust then
                collider:setY(y - h / 2)
            end
        else
            print("Skipped invalid collider:", obj.name or "unnamed", w, h)
        end
    end
end

function mapCollisionLoader.extractRooms(room)
    local rooms = {}

    for _, obj in pairs(room) do
        table.insert(rooms, {
            x = obj.x,
            y = obj.y,
            width = obj.width,
            height = obj.height
        })
    end

    return rooms
end


return mapCollisionLoader