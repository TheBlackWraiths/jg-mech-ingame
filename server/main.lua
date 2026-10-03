local TABLE = 'jg_mech_ingame_configs'
local G = 'Config'

MySQL.ready(function()
    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `name` VARCHAR(64) NOT NULL UNIQUE,
            `data` LONGTEXT NOT NULL,
            `updated_by` VARCHAR(80) NULL,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
    ]]):format(TABLE))
end)

local function allowed(src) return IsPlayerAceAllowed(src, Cfg.ace) end
local function who(src) return GetPlayerName(src) or tostring(src) end

local TARGET = { resource = 'jg-mechanic', file = 'config/config.lua' }

local function writeResourceFile(res, file, content)
    local function landed() return LoadResourceFile(res, file) == content end

    local base = GetResourcePath(res)
    if not base or base == '' then return false, 'could not find the resource folder on disk' end
    local path = (base:gsub('\\', '/'):gsub('//+', '/')) .. '/' .. file

    local okCall, r = pcall(function() return exports[GetCurrentResourceName()]:writeFile(path, content) end)
    if okCall and type(r) == 'table' then
        if r.ok then return true end
        SaveResourceFile(res, file, content, -1)
        if landed() then return true end
        return false, ('%s  [%s]'):format(tostring(r.err), path)
    end

    SaveResourceFile(res, file, content, -1)
    if landed() then return true end
    return false, 'server/fs.js did not load (restart jg-mech-ingame after updating) and SaveResourceFile was refused'
end

local function readConfig()
    local raw = LoadResourceFile(TARGET.resource, TARGET.file)
    if not raw then return nil, ('Cannot read %s/%s. Is %s installed?'):format(TARGET.resource, TARGET.file, TARGET.resource) end

    local data, err, skipped = Ser.evaluate(raw, G)
    if not data then return nil, ('%s/%s does not load: %s'):format(TARGET.resource, TARGET.file, tostring(err)) end
    if not data.MechanicLocations then return nil, ('Config.MechanicLocations not found in %s/%s'):format(TARGET.resource, TARGET.file) end

    return data, nil, skipped, TARGET
end

lib.callback.register('jgmech:canOpen', function(src) return allowed(src) end)

lib.callback.register('jgmech:jobs', function(src)
    if not allowed(src) then return false end

    local jobs
    local ok, res = pcall(function() return exports.qbx_core:GetJobs() end)
    if ok and type(res) == 'table' then
        jobs = res
    else
        ok, res = pcall(function() return exports['qb-core']:GetCoreObject().Shared.Jobs end)
        if ok and type(res) == 'table' then jobs = res end
    end

    local out = {}
    for name, job in pairs(jobs or {}) do
        local grades = {}
        for g, info in pairs(job.grades or {}) do
            grades[#grades + 1] = { grade = tonumber(g) or 0, name = type(info) == 'table' and (info.name or info.label) or tostring(g) }
        end
        table.sort(grades, function(a, b) return a.grade < b.grade end)
        out[name] = { label = job.label or name, grades = grades }
    end
    return out
end)

lib.callback.register('jgmech:list', function(src)
    if not allowed(src) then return false end
    return MySQL.query.await(('SELECT id, name, updated_by, UNIX_TIMESTAMP(updated_at) AS updated_at FROM `%s` ORDER BY name'):format(TABLE))
end)

lib.callback.register('jgmech:get', function(src, id)
    if not allowed(src) then return false end
    local row = MySQL.single.await(('SELECT name, data FROM `%s` WHERE id = ?'):format(TABLE), { id })
    if not row then return false, 'Not found' end
    return { name = row.name, data = json.decode(row.data) }
end)

lib.callback.register('jgmech:save', function(src, name, data)
    if not allowed(src) then return false, 'No permission' end
    if type(name) ~= 'string' or #name < 1 or #name > 64 or type(data) ~= 'table' then
        return false, 'Invalid name or data'
    end
    MySQL.insert.await(
        ('INSERT INTO `%s` (name, data, updated_by) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data), updated_by = VALUES(updated_by)'):format(TABLE),
        { name, json.encode(data), who(src) })
    local row = MySQL.single.await(('SELECT id FROM `%s` WHERE name = ?'):format(TABLE), { name })
    return row and row.id or false
end)

lib.callback.register('jgmech:delete', function(src, id)
    if not allowed(src) then return false end
    MySQL.update.await(('DELETE FROM `%s` WHERE id = ?'):format(TABLE), { id })
    return true
end)

lib.callback.register('jgmech:pullFile', function(src)
    if not allowed(src) then return false, 'No permission' end
    local data, err, skipped, loc = readConfig()
    if not data then return false, err end
    return { data = data, skipped = skipped, target = loc.resource, file = loc.file }
end)

lib.callback.register('jgmech:writeFile', function(src, data)
    if not allowed(src) then return false, 'No permission' end
    if type(data) ~= 'table' then return false, 'Invalid data' end

    local res, file = TARGET.resource, TARGET.file

    local old = LoadResourceFile(res, file)
    if not old then return false, ('Cannot read %s/%s'):format(res, file) end

    local new, changed = Ser.patch(old, G, data)
    if not new then return false, tostring(changed) end
    if #changed == 0 then return { warning = 'Nothing to save: the file already matches.' } end
    print(('[jg-mech-ingame] %s changed: %s'):format(who(src), table.concat(changed, ', ')))

    if Cfg.backupBeforeWrite then
        local bok, berr = writeResourceFile(res, ('%s.bak-%d'):format(file, os.time()), old)
        if not bok then print(('[jg-mech-ingame] Warning: could not write a backup of %s/%s: %s'):format(res, file, tostring(berr))) end
    end

    local wok, werr = writeResourceFile(res, file, new)
    if not wok then
        print(('[jg-mech-ingame] Write failed for %s/%s: %s'):format(res, file, tostring(werr)))
        return false, ('Could not write %s/%s (%s)'):format(res, file, tostring(werr))
    end

    local state = GetResourceState(res)
    print(('[jg-mech-ingame] %s wrote %s/%s, ensuring %s (was %s)'):format(who(src), res, file, res, state))
    ExecuteCommand('ensure ' .. res)

    if state ~= 'started' then
        return { warning = ('Saved, but %s was not running (%s). Check the server console: it may be missing a dependency such as jg-vehiclemileage.'):format(res, state) }
    end
    return true
end)
