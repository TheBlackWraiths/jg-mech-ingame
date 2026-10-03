Ser = {}

local function isIdent(s)
    return type(s) == 'string' and s:match('^[%a_][%w_]*$') ~= nil
end

local reserved = {}
for w in ('and break do else elseif end false for function goto if in local nil not or repeat return then true until while'):gmatch('%a+') do
    reserved[w] = true
end

local order = {}
for i, k in ipairs({
    'name', 'type', 'job', 'jobManagementRanks', 'logo', 'commission', 'locations', 'coords', 'id', 'size', 'color', 'scale',
    'showBlip', 'employeeOnly', 'blip', 'x', 'y', 'z', 'r', 'g', 'b', 'a', 'mods',
    'repair', 'performance', 'cosmetics', 'stance', 'respray', 'wheels', 'neonLights', 'headlights', 'tyreSmoke', 'bulletproofTyres', 'extras',
    'tuning', 'engineSwaps', 'drivetrains', 'turbocharging', 'tyres', 'brakes', 'driftTuning', 'gearboxes',
    'carLifts', 'shops', 'stashes', 'usePed', 'pedModel', 'marker', 'bobUpAndDown', 'faceCamera', 'rotate', 'drawOnEnts',
    'items', 'label', 'enabled', 'price', 'percentVehVal', 'priceMult', 'requiresItem', 'slots', 'weight',
    'LOG', 'EVENT', 'SECURITY', 'destinations',
}) do order[k] = i end

local function keyLess(a, b)
    local oa, ob = order[a] or 1000, order[b] or 1000
    if oa ~= ob then return oa < ob end
    return tostring(a) < tostring(b)
end

local function isArray(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    if n == 0 then return false end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true
end

local function isObj(v)
    return type(v) == 'table' and not v.__vec and not v.__fn and next(v) ~= nil and not isArray(v)
end

local function round2(n) return math.floor(n * 100 + 0.5) / 100 end


function Ser.toJson(v, skipped)
    local tv = type(v)
    if tv == 'function' or tv == 'userdata' or tv == 'thread' then
        skipped.n = skipped.n + 1
        return { __fn = true }
    elseif tv == 'vector2' then return { __vec = { round2(v.x), round2(v.y) } }
    elseif tv == 'vector3' then return { __vec = { round2(v.x), round2(v.y), round2(v.z) } }
    elseif tv == 'vector4' then return { __vec = { round2(v.x), round2(v.y), round2(v.z), round2(v.w) } }
    elseif tv == 'table' then
        local out = {}
        if isArray(v) then
            for i = 1, #v do out[i] = Ser.toJson(v[i], skipped) end
        else
            for k, val in pairs(v) do out[tostring(k)] = Ser.toJson(val, skipped) end
        end
        return out
    end
    return v
end


local function quote(s)
    return (string.format('%q', s):gsub('\\\n', '\\n'))
end

local function num(n)
    if n ~= n or n == math.huge or n == -math.huge then return '0' end
    if n == math.floor(n) and math.abs(n) < 1e15 then return string.format('%d', n) end
    return string.format('%.14g', n)
end

local function keyText(k)
    return (isIdent(k) and not reserved[k]) and k or ('[' .. quote(tostring(k)) .. ']')
end

local function scalarish(x)
    local t = type(x)
    return t == 'string' or t == 'number' or t == 'boolean' or (t == 'table' and type(x.__vec) == 'table')
end

local INLINE_MAX = 100

function Ser.toLua(v, indent)
    indent = indent or 0
    local pad = string.rep('\t', indent)
    local pad1 = string.rep('\t', indent + 1)
    local tv = type(v)

    if tv == 'string' then return quote(v)
    elseif tv == 'number' then return num(v)
    elseif tv == 'boolean' then return tostring(v)
    elseif tv == 'table' then
        if v.__fn then return nil end
        if type(v.__vec) == 'table' then
            local parts = {}
            for i, n in ipairs(v.__vec) do parts[i] = num(tonumber(n) or 0) end
            return ('vec%d(%s)'):format(#parts, table.concat(parts, ', '))
        end

        local arr = isArray(v)
        local keys = {}
        if arr then
            for i = 1, #v do keys[i] = i end
        else
            for k in pairs(v) do keys[#keys + 1] = k end
            table.sort(keys, keyLess)
        end

        local items, simple = {}, true
        for _, k in ipairs(keys) do
            local s = Ser.toLua(v[k], indent + 1)
            if s then
                items[#items + 1] = arr and s or (keyText(k) .. ' = ' .. s)
                if not scalarish(v[k]) then simple = false end
            end
        end
        if #items == 0 then return '{}' end

        if simple then
            local inline = '{ ' .. table.concat(items, ', ') .. ' }'
            if #inline <= INLINE_MAX then return inline end
        end

        local lines = {}
        for i, it in ipairs(items) do lines[i] = pad1 .. it .. ',' end
        return '{\n' .. table.concat(lines, '\n') .. '\n' .. pad .. '}'
    end
    return nil
end


local function scanBraces(src, open)
    local i, depth, len = open + 1, 1, #src
    while i <= len and depth > 0 do
        local c = src:sub(i, i)
        if c == '-' and src:sub(i, i + 1) == '--' then
            local lb = src:match('^%-%-%[(=*)%[', i)
            if lb then
                local _, ce = src:find(']' .. lb .. ']', i, true)
                i = (ce or len) + 1
            else
                local nl = src:find('\n', i, true)
                i = (nl or len) + 1
            end
        elseif c == '"' or c == "'" then
            i = i + 1
            while i <= len do
                local d = src:sub(i, i)
                if d == '\\' then i = i + 2
                elseif d == c then i = i + 1 break
                else i = i + 1 end
            end
        elseif c == '[' and src:match('^%[=*%[', i) then
            local eq = src:match('^%[(=*)%[', i)
            local _, ce = src:find(']' .. eq .. ']', i, true)
            i = (ce or len) + 1
        else
            if c == '{' then depth = depth + 1 elseif c == '}' then depth = depth - 1 end
            i = i + 1
        end
    end
    if depth ~= 0 then return nil end
    return i - 1
end

local function tableEntries(src, open, positional)
    local entries, cur = {}, nil
    local i, depth, paren, len = open + 1, 1, 0, #src
    local last = open

    while i <= len do
        local c = src:sub(i, i)
        local step = 1

        if positional and not cur and depth == 1 and paren == 0 and not c:match('[%s,}]')
            and not (c == '-' and src:sub(i, i + 1) == '--') then
            cur = { vs = i }
        end

        if c == '-' and src:sub(i, i + 1) == '--' then
            local lb = src:match('^%-%-%[(=*)%[', i)
            if lb then
                local _, ce = src:find(']' .. lb .. ']', i, true)
                step = (ce or len) + 1 - i
            else
                local nl = src:find('\n', i, true)
                step = (nl or len) + 1 - i
            end
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= len do
                local d = src:sub(j, j)
                if d == '\\' then j = j + 2
                elseif d == c then break
                else j = j + 1 end
            end
            last = j
            step = j + 1 - i
        elseif c == '[' then
            local eq = src:match('^%[(=*)%[', i)
            if eq then
                local _, ce = src:find(']' .. eq .. ']', i, true)
                last = ce or len
                step = (ce or len) + 1 - i
            elseif not positional and depth == 1 and paren == 0 and not cur then
                return nil
            else
                last = i
            end
        elseif not positional and depth == 1 and paren == 0 and not cur and c:match('[%a_]') then
            local name = src:match('^[%a_][%w_]*', i)
            local eqpos = src:match('^%s*=()', i + #name)
            if eqpos and src:sub(eqpos, eqpos) ~= '=' then
                local vs = src:find('%S', eqpos)
                if not vs then return nil end
                cur = { key = name, ks = i, vs = vs }
                step = vs - i
            else
                last = i + #name - 1
                step = #name
            end
        else
            if c == '{' then
                depth = depth + 1
            elseif c == '}' then
                depth = depth - 1
                if depth == 0 then
                    if cur then cur.ve = last; entries[#entries + 1] = cur end
                    return entries, i
                end
            elseif c == '(' then
                paren = paren + 1
            elseif c == ')' then
                paren = paren - 1
            end

            if c == ',' and depth == 1 and paren == 0 then
                if cur then cur.ve = last; entries[#entries + 1] = cur; cur = nil end
            elseif not c:match('%s') then
                last = i
            end
        end
        i = i + step
    end
    return nil
end

local function lineStartOf(src, idx)
    local s = idx
    while s > 1 and src:sub(s - 1, s - 1) ~= '\n' do s = s - 1 end
    return s
end

function Ser.findStatement(src, globalName, name)
    local pattern = globalName .. '%.' .. name .. '%s*='
    local from = 1
    local len = #src

    while true do
        local pos, pe = src:find(pattern, from)
        if not pos then return nil end
        local lineStart = src:sub(1, pos - 1):match('[^\n]*$')
        if lineStart:match('^%s*$') and src:sub(pe + 1, pe + 1) ~= '=' then
            local vs = src:find('%S', pe + 1)
            if not vs then return nil end

            if src:sub(vs, vs) == '{' then
                local close = scanBraces(src, vs)
                if not close then return nil end
                return pos, close, vs
            end

            local j, last = vs, vs
            while j <= len do
                local ch = src:sub(j, j)
                if ch == '\n' then break end
                if ch == '"' or ch == "'" then
                    j = j + 1
                    while j <= len do
                        local d = src:sub(j, j)
                        if d == '\\' then j = j + 2
                        elseif d == ch then break
                        else j = j + 1 end
                    end
                    last = j
                elseif ch == '-' and src:sub(j, j + 1) == '--' then
                    break
                elseif ch ~= ' ' and ch ~= '\t' and ch ~= '\r' then
                    last = j
                end
                j = j + 1
            end
            return pos, last, vs
        end
        from = pos + 1
    end
end

function Ser.findBlock(src, globalName, name)
    return Ser.findStatement(src, globalName, name)
end

function Ser.equal(a, b)
    local ta = type(a)
    if ta ~= type(b) then return false end
    if ta == 'number' then return math.abs(a - b) < 1e-9 end
    if ta ~= 'table' then return a == b end
    for k, v in pairs(a) do
        if not Ser.equal(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end


function Ser.evaluate(raw, globalName)
    local env = setmetatable({ [globalName] = {} }, { __index = _G })
    local fn, err = load(raw, '@config', 't', env)
    if not fn then return nil, err end
    local ok, perr = pcall(fn)
    if not ok then return nil, perr end

    local skipped = { n = 0 }
    return Ser.toJson(env[globalName], skipped), nil, skipped.n
end

local renderValue
local function isList(v)
    return type(v) == 'table' and not v.__vec and not v.__fn and isArray(v)
end

local function applyEdits(src, edits, vs, ve)
    table.sort(edits, function(a, b)
        if a[1] ~= b[1] then return a[1] > b[1] end
        return a[2] > b[2]
    end)
    local out = src
    for _, e in ipairs(edits) do
        out = out:sub(1, e[1] - 1) .. e[3] .. out:sub(e[2] + 1)
    end
    return out:sub(vs, ve + (#out - #src))
end

local function deleteLines(src, startIdx, endIdx)
    local ls = lineStartOf(src, startIdx)
    local nl = src:find('\n', endIdx, true)
    if not nl or not src:sub(ls, startIdx - 1):match('^%s*$') then return nil end
    local rest = src:sub(endIdx + 1, nl - 1):gsub('%-%-.*$', '')
    if not rest:match('^[%s,]*$') then return nil end
    return { ls, nl, '' }
end

local function patchList(src, vs, ve, old, new, indent, fine)
    local els, close = tableEntries(src, vs, true)
    if not els or close ~= ve or #els ~= #old then return nil end

    local nOld, nNew = #old, #new
    local multiline = src:sub(lineStartOf(src, close), close - 1):match('^%s*$') ~= nil
    local pad1 = string.rep('\t', indent + 1)
    local edits = {}

    if nOld == nNew then
        for i = 1, nOld do
            if not Ser.equal(old[i], new[i]) then
                local text = renderValue(src, els[i].vs, els[i].ve, old[i], new[i], indent + 1, fine)
                if not text then return nil end
                edits[#edits + 1] = { els[i].vs, els[i].ve, text }
            end
        end
        return applyEdits(src, edits, vs, ve)
    end

    if not multiline then return nil end

    if nNew == nOld + 1 then
        for i = 1, nOld do
            if not Ser.equal(old[i], new[i]) then return nil end
        end
        local text = Ser.toLua(new[nNew], indent + 1)
        if not text then return nil end
        local last = els[nOld]
        if last and not src:sub(last.ve + 1, close):match('^[ \t]*,') then
            edits[#edits + 1] = { last.ve + 1, last.ve, ',' }
        end
        local ls = lineStartOf(src, close)
        edits[#edits + 1] = { ls, ls - 1, pad1 .. text .. ',\n' }
        return applyEdits(src, edits, vs, ve)
    end

    if nNew == nOld - 1 then
        local at = nOld
        for i = 1, nNew do
            if not Ser.equal(old[i], new[i]) then at = i break end
        end
        for j = at, nNew do
            if not Ser.equal(old[j + 1], new[j]) then return nil end
        end
        local del = deleteLines(src, els[at].vs, els[at].ve)
        if not del then return nil end
        edits[#edits + 1] = del
        return applyEdits(src, edits, vs, ve)
    end

    return nil
end

function renderValue(src, vs, ve, old, new, indent, fine)
    if Ser.equal(old, new) then return src:sub(vs, ve) end
    local whole = Ser.toLua(new, indent)
    if not fine or src:sub(vs, vs) ~= '{' then return whole end

    if isList(old) and isList(new) then
        return patchList(src, vs, ve, old, new, indent, fine) or whole
    end
    if not (isObj(old) and isObj(new)) then return whole end

    local entries, close = tableEntries(src, vs)
    if not entries or close ~= ve or #entries == 0 then return whole end

    local edits, byKey = {}, {}
    for _, en in ipairs(entries) do
        byKey[en.key] = en
        local nv = new[en.key]
        if nv == nil then
            local del = deleteLines(src, en.ks, en.ve)
            if not del then return whole end
            edits[#edits + 1] = del
        elseif not Ser.equal(old[en.key], nv) then
            local text = renderValue(src, en.vs, en.ve, old[en.key], nv, indent + 1, fine)
            if not text then return whole end
            edits[#edits + 1] = { en.vs, en.ve, text }
        end
    end

    local added = {}
    for k, v in pairs(new) do
        if not byKey[k] and Ser.toLua(v, 0) then added[#added + 1] = k end
    end
    if #added > 0 then
        table.sort(added, keyLess)
        local ls = lineStartOf(src, close)
        if not src:sub(ls, close - 1):match('^%s*$') then return whole end

        local pad1 = string.rep('\t', indent + 1)
        local lines = {}
        for _, k in ipairs(added) do
            lines[#lines + 1] = pad1 .. keyText(k) .. ' = ' .. Ser.toLua(new[k], indent + 1) .. ','
        end

        local lastEntry = entries[#entries]
        if not src:sub(lastEntry.ve + 1, close):match('^[ \t]*,') then
            edits[#edits + 1] = { lastEntry.ve + 1, lastEntry.ve, ',' }
        end
        edits[#edits + 1] = { ls, ls - 1, table.concat(lines, '\n') .. '\n' }
    end

    return applyEdits(src, edits, vs, ve)
end

local function applyChanges(raw, globalName, data, orig, names, fine)
    local out, changed = raw, {}
    for _, name in ipairs(names) do
        if not Ser.equal(orig[name], data[name]) then
            local s, e, vs = Ser.findStatement(out, globalName, name)
            if s then
                local text = renderValue(out, vs, e, orig[name], data[name], 0, fine)
                if text then
                    out = out:sub(1, vs - 1) .. text .. out:sub(e + 1)
                    changed[#changed + 1] = name
                end
            else
                local text = Ser.toLua(data[name], 0)
                if text then
                    out = out .. (out:sub(-1) == '\n' and '' or '\n') .. ('%s.%s = %s'):format(globalName, name, text) .. '\n'
                    changed[#changed + 1] = name
                end
            end
        end
    end
    return out, changed
end

local function matches(text, globalName, data, names)
    local back, err = Ser.evaluate(text, globalName)
    if not back then return false, err end
    for _, name in ipairs(names) do
        if not Ser.equal(back[name], data[name]) then return false, name end
    end
    return true
end

function Ser.patch(raw, globalName, data)
    local orig, err = Ser.evaluate(raw, globalName)
    if not orig then return nil, 'The current file does not load: ' .. tostring(err) end

    local names = {}
    for name in pairs(data) do names[#names + 1] = name end
    table.sort(names)

    for _, fine in ipairs({ true, false }) do
        local out, changed = applyChanges(raw, globalName, data, orig, names, fine)
        local ok, why = matches(out, globalName, data, names)
        if ok then return out, changed end
        if not fine then
            return nil, ('"%s" could not be written back exactly, so nothing was saved'):format(tostring(why))
        end
    end
end
