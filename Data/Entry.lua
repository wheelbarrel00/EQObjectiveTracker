local _, ns = ...

local Entry = ns:RegisterModule("Entry", {})

Entry.STATE = {
    ACTIVE   = "active",
    COMPLETE = "complete",
    FAILED   = "failed",
}

Entry.LINE = {
    OBJECTIVE   = "objective",
    PROGRESSBAR = "progressbar",
    NOTE        = "note",
    -- Distinct from PROGRESSBAR: current is already a percentage rather than a count,
    -- which is what lets a renderer fill a fixed 0-100 bar from it.
    WEIGHTED    = "weighted",
}

Entry.ICON = {
    NONE     = "none",
    TEXTURE  = "texture",
    QUESTPOI = "questPOI",
    -- Two layers, a POI ring plus the quest-type atlas, so a plain TEXTURE cannot
    -- express it. The ring also reacts to isFocused.
    WORLDQUEST = "worldQuest",
}

local VALID_STATE, VALID_LINE, VALID_ICON = {}, {}, {}
for _, v in pairs(Entry.STATE) do VALID_STATE[v] = true end
for _, v in pairs(Entry.LINE)  do VALID_LINE[v]  = true end
for _, v in pairs(Entry.ICON)  do VALID_ICON[v]  = true end

-- Getting the prune wrong leaks entries, and getting the line trim wrong leaves a
-- previous quest's objectives visible under the current one.
local Store = {}
Store.__index = Store

function Entry.NewStore(defaults)
    return setmetatable({ _by = {}, _out = {}, _seen = {}, _n = 0, _defaults = defaults }, Store)
end

function Store:Begin()
    wipe(self._seen)
    self._n = 0
end

function Store:Acquire(id)
    self._seen[id] = true
    local e = self._by[id]
    if not e then
        e = { id = id, lines = {} }
        for k, v in pairs(self._defaults or {}) do
            e[k] = (type(v) == "table") and CopyTable(v) or v
        end
        self._by[id] = e
    end
    self._n = self._n + 1
    self._out[self._n] = e
    return e
end

function Store:Finish()
    for id in pairs(self._by) do
        if not self._seen[id] then self._by[id] = nil end
    end
    for i = #self._out, self._n + 1, -1 do self._out[i] = nil end
    return self._out
end

function Store:Out()
    return self._out
end

function Store:Get(id)
    return self._by[id]
end

function Store:Each()
    return pairs(self._by)
end

function Entry.BeginLines(e)
    e._nlines = 0
end

function Entry.PushLine(e)
    local n = (e._nlines or 0) + 1
    e._nlines = n
    local ln = e.lines[n]
    if not ln then ln = {}; e.lines[n] = ln end
    ln.text, ln.completed  = "", false
    ln.current, ln.required = nil, nil
    ln.kind, ln.richText    = Entry.LINE.OBJECTIVE, false
    -- Lines are pooled and this list is the whole reset, so a field added above and not cleared
    -- here carries a previous quest's value onto the next row that reuses the table.
    ln.percent = nil
    return ln
end

function Entry.EndLines(e)
    local n = e._nlines or 0
    for i = #e.lines, n + 1, -1 do e.lines[i] = nil end
    e._nlines = nil
end

-- Only ever called under ns.DEBUG. Providers are trusted in the render path.
function Entry:Validate(e, provider)
    if type(e) ~= "table" then return false, "entry is not a table" end
    if e.id == nil then return false, "entry.id is nil" end
    local t = type(e.id)
    if t ~= "number" and t ~= "string" then return false, "entry.id must be number or string" end
    if type(e.title) ~= "string" or e.title == "" then
        return false, ("entry %s has no title"):format(tostring(e.id))
    end
    if e.providerID ~= nil and e.providerID ~= provider.id then
        return false, ("entry %s set providerID itself"):format(tostring(e.id))
    end
    if not provider._groupSet[e.groupID or ""] then
        return false, ("entry %s uses undeclared groupID %q"):format(tostring(e.id), tostring(e.groupID))
    end
    if e.state ~= nil and not VALID_STATE[e.state] then
        return false, ("entry %s has bad state %q"):format(tostring(e.id), tostring(e.state))
    end
    if e.icon ~= nil then
        if type(e.icon) ~= "table" then return false, "entry.icon must be a table" end
        if e.icon.kind ~= nil and not VALID_ICON[e.icon.kind] then
            return false, ("entry %s has bad icon.kind %q"):format(tostring(e.id), tostring(e.icon.kind))
        end
    end
    if e.tags ~= nil then
        for tag in pairs(e.tags) do
            if not provider._tagSet[tag] then
                return false, ("entry %s uses undeclared tag %q"):format(tostring(e.id), tostring(tag))
            end
        end
    end
    if e.lines ~= nil then
        if type(e.lines) ~= "table" then return false, "entry.lines must be a table" end
        for i = 1, #e.lines do
            local ln = e.lines[i]
            if type(ln) ~= "table" then
                return false, ("entry %s line %d is not a table"):format(tostring(e.id), i)
            end
            if ln.kind ~= nil and not VALID_LINE[ln.kind] then
                return false, ("entry %s line %d has bad kind %q"):format(tostring(e.id), i, tostring(ln.kind))
            end
            if type(ln.text) ~= "string" then
                return false, ("entry %s line %d has no text"):format(tostring(e.id), i)
            end
        end
    end
    return true
end
