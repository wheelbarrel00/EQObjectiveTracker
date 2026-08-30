local _, ns = ...

local Util = ns:RegisterModule("Util", {})

local function progressRepl(have, need)
    local h, n = tonumber(have), tonumber(need)
    if not (h and n) then return have .. "/" .. need end
    local color
    if h == 0    then color = "|cffff5050"
    elseif h < n then color = "|cffeeaa00"
    else              color = "|cff44ff44"
    end
    return color .. have .. "/" .. need .. "|r"
end

function Util.ColorizeProgress(text)
    if not text or text == "" then return text end
    return (text:gsub("(%d+)%s*/%s*(%d+)", progressRepl))
end

function Util.StripLeadingCount(text)
    if not text then return "" end
    return (text:gsub("^%s*%d+%s*/%s*%d+%s*", ""))
end

-- requirementText arrives pre-bulleted and with padded fractions, like "- 1 / 15 Quests
-- completed". Both are presentation the renderer owns, so they are stripped before the string
-- becomes an objective line. The bullet must be followed by whitespace or the pattern eats the
-- minus sign off a requirement that opens with a negative number.
--
-- Shared because the Traveler's Log and the neighborhood initiative hand back the identical
-- shape, measured on both, and two copies of a pattern this fiddly would drift.
function Util.CleanRequirement(text)
    text = (text or ""):gsub("^%s*%-%s+", "")
    return (text:gsub("(%d+)%s*/%s*(%d+)", "%1/%2"))
end

function Util.Hex(r, g, b)
    return ("%02x%02x%02x"):format(
        math.floor((r or 0) * 255 + 0.5),
        math.floor((g or 0) * 255 + 0.5),
        math.floor((b or 0) * 255 + 0.5))
end

function Util.FmtDuration(secs)
    secs = math.max(0, math.floor(secs or 0))
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return ("%dh %dm"):format(h, m) end
    if m > 0 then return ("%dm"):format(m) end
    return ("%ds"):format(secs)
end

function Util.TimeShort(mins)
    if not mins or mins <= 0 then return "" end
    if mins < 60   then return ("%dm"):format(mins) end
    if mins < 1440 then return ("%dh"):format(math.floor(mins / 60)) end
    return ("%dd"):format(math.floor(mins / 1440))
end

function Util.TimeColor(mins)
    if not mins or mins <= 0 then return 1.00, 0.10, 0.10 end
    if mins < 30   then return 1.00, 0.25, 0.25 end
    if mins < 120  then return 1.00, 0.65, 0.10 end
    if mins < 720  then return 1.00, 1.00, 0.40 end
    return 0.50, 1.00, 0.50
end

local playerClassColor
function Util.GetPlayerClassColor()
    if playerClassColor == nil then
        local classFile = UnitClass and select(2, UnitClass("player"))
        local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        playerClassColor = c and { c.r, c.g, c.b } or false
    end
    if playerClassColor then
        return playerClassColor[1], playerClassColor[2], playerClassColor[3]
    end
end

-- Returns nothing when neither source is set, which is what lets callers fall through to
-- difficulty coloring. Class color deliberately beats the explicit override.
function Util.EffectiveTitleColor(cfg)
    if cfg and cfg.titleColorUseClass then
        local r, g, b = Util.GetPlayerClassColor()
        if r then return r, g, b end
    end
    local ov = cfg and cfg.titleColorOverride
    if ov and ov.r then return ov.r, ov.g, ov.b end
end

-- Only a TRUE is memoized. GetAtlasInfo answers nil for art that has not streamed in yet, so
-- caching that would answer nil for the rest of the session and leave the atlas blank until
-- the next reload.
local _atlasOK = {}
function Util.AtlasExists(atlas)
    if not atlas or atlas == "" then return false end
    if not ns.Has.Atlas then return false end
    if _atlasOK[atlas] then return true end
    local ok = C_Texture.GetAtlasInfo(atlas) and true or false
    if ok then _atlasOK[atlas] = true end
    return ok
end

-- Texcoords are cleared first: SetAtlas was measured leaving an earlier SetTexCoord in place,
-- so a pooled row that last drew a world quest rendered its POI face through the ring's crop.
function Util.SafeSetAtlas(tex, atlas, useAtlasSize)
    tex:SetTexCoord(0, 1, 0, 1)
    if Util.AtlasExists(atlas) then
        tex:SetAtlas(atlas, useAtlasSize and true or false)
        return true
    end
    tex:SetTexture(nil)
    return false
end

-- Never the shared GameTooltip. Taint left on that singleton was reported killing Blizzard's
-- next AreaPOI hover with a secret-value error.
local _tooltip
function Util.Tooltip()
    if not _tooltip then
        _tooltip = CreateFrame("GameTooltip", "EQOTTooltip", UIParent, "GameTooltipTemplate")
        -- Nothing skins a private tooltip and the inherited fill reads through to the panel.
        _tooltip.eqotBG = _tooltip:CreateTexture(nil, "BACKGROUND", nil, -8)
        _tooltip.eqotBG:SetAllPoints()
        _tooltip.eqotBG:SetColorTexture(0, 0, 0, 0.94)
    end
    return _tooltip
end

ns.Util = Util
