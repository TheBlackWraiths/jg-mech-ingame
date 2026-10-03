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

local found

local function metaFiles(res)
    local files, seen = {}, {}
    local function add(f)
        if f and not f:find('*', 1, true) and f:sub(1, 1) ~= '@' and not seen[f] then
            seen[f] = true
            files[#files + 1] = f
        end
    end
    for _, key in ipairs({ 'shared_script', 'client_script', 'server_script', 'file' }) do
        for i = 0, (GetNumResourceMetadata(res, key) or 0) - 1 do
            add(GetResourceMetadata(res, key, i))
        end
    end
    for _, f in ipairs({ 'config/config.lua', 'config.lua', 'config/shared.lua', 'shared/config.lua', 'config/locations.lua' }) do add(f) end
    return files
end

local function fileHasSection(res, file)
    local raw = LoadResourceFile(res, file)
    if raw and #raw < 5 * 1024 * 1024 and Ser.findBlock(raw, G, Cfg.section) then return true end
    return false
end

local function candidateResources()
    local self = GetCurrentResourceName()
    local strict, loose = {}, {}
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        local l = name and name:lower()
        if name and name ~= self then
            if l:find('^jg[-_]?mech') then strict[#strict + 1] = name
            elseif l:find('jg') and l:find('mech') then loose[#loose + 1] = name end
        end
    end
    for _, n in ipairs(loose) do strict[#strict + 1] = n end
    return strict
end

local function locate()
    if found and fileHasSection(found.resource, found.file) then return found end
    found = nil

    if Cfg.targetResource and Cfg.targetResource ~= '' and Cfg.configFile and Cfg.configFile ~= '' then
        found = { resource = Cfg.targetResource, file = Cfg.configFile }
        return found
    end

    local resources = (Cfg.targetResource and Cfg.targetResource ~= '') and { Cfg.targetResource } or candidateResources()
    for _, res in ipairs(resources) do
        for _, file in ipairs(metaFiles(res)) do
            if fileHasSection(res, file) then
                found = { resource = res, file = file }
                print(('[jg-mech-ingame] Found Config.%s in %s/%s'):format(Cfg.section, res, file))
                return found
            end
        end
    end
    return nil, ('Could not find a resource defining Config.%s. Looked at: %s. Set targetResource/configFile in jg-mech-ingame/config.lua.')
        :format(Cfg.section, #resources > 0 and table.concat(resources, ', ') or 'no resource with "jg" and "mech" in its name')
end

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
    local loc, lerr = locate()
    if not loc then return nil, lerr end

    local raw = LoadResourceFile(loc.resource, loc.file)
    if not raw then return nil, ('Cannot read %s/%s'):format(loc.resource, loc.file) end

    local data, err, skipped = Ser.evaluate(raw, G)
    if not data then return nil, ('%s/%s does not load: %s'):format(loc.resource, loc.file, tostring(err)) end
    if not data[Cfg.section] then return nil, ('Config.%s not found in %s/%s'):format(Cfg.section, loc.resource, loc.file) end

    return data, nil, skipped, loc
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

    local loc, lerr = locate()
    if not loc then return false, lerr end
    local res, file = loc.resource, loc.file

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
