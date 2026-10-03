local open = false

local function setOpen(state)
    open = state
    SetNuiFocus(state, state)
    SendNUIMessage({ action = state and 'open' or 'close' })
end

RegisterCommand(Cfg.command, function()
    if open then return end
    if not lib.callback.await('jgmech:canOpen', false) then
        return lib.notify({ type = 'error', description = 'No permission' })
    end
    setOpen(true)
end, false)

RegisterNUICallback('close', function(_, cb) setOpen(false) cb({}) end)

RegisterNUICallback('getCoords', function(_, cb)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    cb({ x = c.x, y = c.y, z = c.z, w = GetEntityHeading(ped) })
end)

local function camRaycast()
    local pos = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local n = math.abs(math.cos(x))
    local dir = vec3(-math.sin(z) * n, math.cos(z) * n, math.sin(x))
    local to = pos + dir * 80.0
    local handle = StartExpensiveSynchronousShapeTestLosProbe(pos.x, pos.y, pos.z, to.x, to.y, to.z, 511, PlayerPedId(), 4)
    local _, hit, endCoords = GetShapeTestResult(handle)
    return hit == 1, endCoords
end

local PLACE_DISABLED = { 14, 15, 16, 17, 24, 25, 37, 38, 44, 140, 141, 142, 257, 263, 264 }

local function placeWithRaycast(opts)
    local hasSize = tonumber(opts.size) ~= nil
    local size = tonumber(opts.size) or 1.5
    local useHeading = opts.heading and true or false
    local heading = GetEntityHeading(PlayerPedId()) + 0.0
    local result

    SetNuiFocus(false, false)
    lib.showTextUI(useHeading
        and '[Q / E] Rotate  \n[Enter / LMB] Place  \n[Backspace] Cancel'
        or '[Scroll] Size  \n[Enter / LMB] Place  \n[Backspace] Cancel')

    while true do
        Wait(0)
        for i = 1, #PLACE_DISABLED do DisableControlAction(0, PLACE_DISABLED[i], true) end

        local hit, c = camRaycast()
        if hit then
            DrawMarker(1, c.x, c.y, c.z - 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size * 2.0, size * 2.0, 0.3, 255, 255, 255, 70, false, false, 2, false, nil, nil, false)
            DrawMarker(25, c.x, c.y, c.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size * 2.0, size * 2.0, 1.0, 255, 255, 255, 200, false, false, 2, false, nil, nil, false)
            if useHeading then
                local r = math.rad(heading)
                DrawLine(c.x, c.y, c.z + 0.4, c.x - math.sin(r) * 2.0, c.y + math.cos(r) * 2.0, c.z + 0.4, 255, 200, 0, 255)
            end
        end

        if hasSize then
            if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 241) then size = math.min(50.0, size + 0.25) end
            if IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 242) then size = math.max(0.5, size - 0.25) end
        end
        if useHeading then
            if IsDisabledControlPressed(0, 44) then heading = (heading + 2.0) % 360.0 end
            if IsDisabledControlPressed(0, 38) then heading = (heading - 2.0) % 360.0 end
        end

        if hit and (IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 24)) then
            result = { x = c.x, y = c.y, z = c.z, w = heading, size = size }
            break
        end
        if IsControlJustPressed(0, 177) then break end
    end

    lib.hideTextUI()
    Wait(150)
    SetNuiFocus(true, true)
    return result
end

RegisterNUICallback('place', function(body, cb)
    if not open then return cb({ ok = false, error = 'cancelled' }) end
    local r = placeWithRaycast(body or {})
    if r then cb({ ok = true, result = r }) else cb({ ok = false, error = 'cancelled' }) end
end)

RegisterNUICallback('teleport', function(body, cb)
    if open and body and tonumber(body.x) and tonumber(body.y) then
        local ped = PlayerPedId()
        local z = tonumber(body.z) or 0.0
        RequestCollisionAtCoord(body.x + 0.0, body.y + 0.0, z + 0.0)
        SetEntityCoords(ped, body.x + 0.0, body.y + 0.0, z + 0.0, false, false, false, false)
    end
    cb({ ok = true, result = true })
end)

local routes = {
    list      = { 'jgmech:list', function() return end },
    jobs      = { 'jgmech:jobs', function() return end },
    get       = { 'jgmech:get', function(b) return b.id end },
    save      = { 'jgmech:save', function(b) return b.name, b.data end },
    delete    = { 'jgmech:delete', function(b) return b.id end },
    pullFile  = { 'jgmech:pullFile', function() return end },
    writeFile = { 'jgmech:writeFile', function(b) return b.data end },
}

for nui, route in pairs(routes) do
    RegisterNUICallback(nui, function(body, cb)
        local result, err = lib.callback.await(route[1], false, route[2](body or {}))
        if result then
            cb({ ok = true, result = result })
        else
            cb({ ok = false, error = err or 'Failed' })
        end
    end)
end
