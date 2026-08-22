-- luacheck: globals C_Scenario C_ScenarioInfo GetInstanceInfo wipe CopyTable issecretvalue
-- luacheck: globals InCombatLockdown CreateFrame tremove
--
-- Unit tests for the scenario spell button, run against the SHIPPED source of both halves
-- rather than a copy. Run from the repo root with the game's own Lua:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_scenario_spells.lua
--
-- Data/Providers/Scenarios.lua: the two cases that earn it are the SHRINK case - the array is
-- reused and bounded by a count rather than by #, so a shorter read must not leave a longer
-- one's tail reachable - and REFUSAL, because accepting a guessed key would bind the button to
-- the wrong spell.
--
-- UI/ScenarioSpells.lua: the frames are stubs and what is under test is the combat state
-- machine, because a secure button placed or rebound in combat is a blocked action and one
-- left inert forever is a mechanic the player cannot cast.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
local mods = {}
function ns:RegisterModule(n, t) mods[n] = t return t end
function ns:GetModule(n) return mods[n] end

wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
local function copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = (type(v) == "table") and copy(v) or v end
    return o
end
CopyTable = copy

local SECRETS = {}
issecretvalue = function(v) return SECRETS[v] == true end

local STEP = { title = "The Ring of Glory", widgetSetID = 842 }
local CRITERIA = {}
local ACTIVE = true

C_Scenario = {
    GetInfo = function()
        if not ACTIVE then return nil end
        return "The Ring of Glory", 1, 1, nil, nil, nil, nil, nil, nil, 8, nil, "delves-scenario"
    end,
    GetStepInfo = function()
        return "The Ring of Glory", nil, #CRITERIA, nil, nil, nil, nil, nil, nil, nil, nil, 842
    end,
}
C_ScenarioInfo = {
    GetCriteriaInfo     = function(i) return CRITERIA[i] end,
    GetScenarioStepInfo = function() return STEP end,
}
GetInstanceInfo = function() return "The Ring of Glory", "scenario", 0 end

assert(loadfile(repoFile("Data/Entry.lua")))("EQObjectiveTracker", ns)

-- The provider registers itself and is never put in ns.modules, so this is how it escapes
local provider
mods.Registry = { Register = function(_, p) provider = p end }

assert(loadfile(repoFile("Data/Providers/Scenarios.lua")))("EQObjectiveTracker", ns)
assert(provider, "Data/Providers/Scenarios.lua did not register a provider")

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local function read(spellList)
    STEP.spells = spellList
    provider:GetEntries()
    return provider:GetBanner(), provider:DebugLine()
end

local function has(line, want)
    return line:find(want, 1, true) ~= nil
end

-- 1. The measured shape. One entry of exactly { icon, name, spellID }, read in The Ring of
-- Glory on 2026-08-21.
local b, line = read({ { icon = 237559, name = "Foul Ball", spellID = 1295317 } })
ok(b ~= nil, "an active scenario returns banner facts")
ok(b.spellsN == 1, "the measured shape resolves to one spell, got " .. tostring(b.spellsN))
ok(b.spells[1].spellID == 1295317, "spellID survives")
ok(b.spells[1].name == "Foul Ball", "name survives")
ok(b.spells[1].icon == 237559, "icon survives")
ok(has(line, "spells 1/1 Foul Ball"), "the status line names the spell, got: " .. line)
ok(not has(line, "unread:"), "nothing is reported unread, got: " .. line)

-- 2. An entry carrying no numeric spellID is refused, counted, and names its own field keys.
-- A spell bound off a guessed key would cast the wrong thing.
b, line = read({ { icon = 5, name = "Mystery", spell = 42 } })
ok(b.spellsN == 0, "an entry with no spellID is refused, got " .. tostring(b.spellsN))
ok(has(line, "spells 0/1"), "the refusal is still counted as seen, got: " .. line)
ok(has(line, "unread: icon,name,spell"), "the field keys are named, got: " .. line)

-- 3. A spellID that is a secret value is refused the same way.
local secret = {}
SECRETS[secret] = true
b, line = read({ { name = "Secret", spellID = secret } })
ok(b.spellsN == 0, "a secret spellID is refused, got " .. tostring(b.spellsN))
ok(has(line, "spells 0/1"), "a secret spellID is counted as seen, got: " .. line)

-- 4. An ABSENT field is the only silent case. Every other way of coming back with no spells
-- names itself, or a secret value reads exactly like a scenario that grants no spell.
b, line = read(nil)
ok(b.spellsN == 0, "an absent spells field reads as none")
ok(not has(line, "spells "), "and is the one case that says nothing, got: " .. line)
b, line = read(7)
ok(b.spellsN == 0, "a non-table spells field reads as none")
ok(has(line, "spells number"), "and names what it found instead, got: " .. line)

local secretList = {}
SECRETS[secretList] = true
b, line = read(secretList)
ok(b.spellsN == 0, "a secret spells table reads as none")
ok(has(line, "spells secret"), "and says the value was secret, got: " .. line)

-- 5. The cap. Everything over it is still counted, so the status line says a cap was hit.
b, line = read({
    { spellID = 11 }, { spellID = 12 }, { spellID = 13 },
    { spellID = 14 }, { spellID = 15 }, { spellID = 16 },
})
ok(b.spellsN == 4, "six entries cap at four, got " .. tostring(b.spellsN))
ok(has(line, "spells 4/6"), "the count over the cap is reported, got: " .. line)

-- 6. THE SHRINK CASE. The array is reused, so a short read must not leave a long read's tail
-- reachable, and a reused ROW must not keep a previous entry's name or icon.
read({
    { spellID = 21, name = "One",   icon = 101 },
    { spellID = 22, name = "Two",   icon = 102 },
    { spellID = 23, name = "Three", icon = 103 },
})
b, line = read({ { spellID = 99 } })
ok(b.spellsN == 1, "a shorter read reports one, got " .. tostring(b.spellsN))
ok(b.spells[1].spellID == 99, "the surviving row is the new one")
ok(b.spells[1].name == nil, "a reused row drops the previous name")
ok(b.spells[1].icon == nil, "a reused row drops the previous icon")
ok(#b.spells == b.spellsN, "the view has no tail, got #" .. tostring(#b.spells))
ok(has(line, "spells 1/1"), "the shorter read is reported as one, got: " .. line)

-- The pool still owns the row tables, which is the half the view split must not cost.
local rowOne = b.spells[1]
b = read({ { spellID = 77 }, { spellID = 78 } })
ok(b.spells[1] == rowOne, "the row table is reused across reads")
ok(#b.spells == 2, "and the view grows back, got #" .. tostring(#b.spells))

-- 6b. The unread report is sorted BEFORE it is capped, so it never depends on hash order.
local wide = {}
for i = 1, 25 do wide["k" .. string.format("%02d", i)] = i end
b, line = read({ wide })
ok(b.spellsN == 0, "a row of twenty five keys and no spellID is still refused")
ok(has(line, "unread: k01,k02,k03"), "the keys come out sorted, got: " .. line)
ok(has(line, ",..."), "and say when the cap dropped some, got: " .. line)
ok(not has(line, "k21"), "the cap takes the tail of the SORTED list, got: " .. line)

-- 7. Leaving the scenario resets everything, including the unread report.
read({ { spellID = 31, name = "Gone" }, { spell = 1 } })
ACTIVE = false
provider:GetEntries()
ok(provider:GetBanner() == nil, "no banner without an active scenario")
ok(provider:DebugLine() == "no active scenario", "the status line says so")

ACTIVE = true
b, line = read(nil)
ok(b.spellsN == 0, "the count is cleared by the inactive pass")
ok(not has(line, "unread:"), "the unread report is cleared too, got: " .. line)

--------------------------------------------------------------------------------------------
-- UI/ScenarioSpells.lua. The frames are stubs, so what is under test is the state machine:
-- which calls are made in combat and which are refused, and whether a refused one is ever
-- forgotten. A secure button placed or rebound in combat is a blocked action, and one left
-- inert forever is a mechanic the player cannot cast.
--------------------------------------------------------------------------------------------

local IN_COMBAT = false
InCombatLockdown = function() return IN_COMBAT end
tremove = table.remove

local PROTECTED = 0
local function region()
    local r = {}
    function r:SetAllPoints() end
    function r:SetTexCoord() end
    function r:SetTexture(t) self.texture = t end
    function r:SetJustifyH() end
    function r:SetWordWrap() end
    function r:SetWidth() end
    function r:SetText(t) self.text = t end
    function r:SetPoint() end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    return r
end

CreateFrame = function(_, _, parent)
    local f = { parent = parent, attrs = {}, shown = false, alpha = 1, mouse = true, x = nil, y = nil }
    function f:SetSize() end
    function f:RegisterForClicks() end
    function f:SetHighlightTexture() end
    function f:SetHitRectInsets(_, r) self.hitRight = r end
    function f:SetAttribute(k, v) PROTECTED = PROTECTED + 1 self.attrs[k] = v end
    function f:CreateTexture() return region() end
    function f:CreateFontString() return region() end
    function f:GetParent() return self.parent end
    function f:SetParent(p) PROTECTED = PROTECTED + 1 self.parent = p end
    function f:ClearAllPoints() PROTECTED = PROTECTED + 1 self.x, self.y = nil, nil end
    function f:SetPoint(_, _, _, x, y) PROTECTED = PROTECTED + 1 self.x, self.y = x, y end
    function f:Show() PROTECTED = PROTECTED + 1 self.shown = true end
    function f:Hide() PROTECTED = PROTECTED + 1 self.shown = false end
    function f:SetAlpha(a) self.alpha = a end
    function f:EnableMouse(v) self.mouse = v end
    function f:GetWidth() return 280 end
    return f
end

local built = {}
local adoptedCount, armedFlag = 0, false
local deferredKey
mods.ItemButtons = {
    Adopt = function(_, button)
        adoptedCount = adoptedCount + 1
        armedFlag = true
        built[#built + 1] = button
        button:EnableMouse(true)
    end,
    MouseSuspended    = function() return false end,
    HasSecureButtons  = function() return armedFlag end,
}
mods.Media   = { ApplyFont = function() end }
mods.Tracker = { Render = function() end }
mods.Events  = { RunWhenOutOfCombat = function(_, key) deferredKey = key end }
function ns:IsModuleDisabled() return false end

assert(loadfile(repoFile("UI/ScenarioSpells.lua")))("EQObjectiveTracker", ns)
local SS = mods.ScenarioSpells
assert(SS, "UI/ScenarioSpells.lua did not register a ScenarioSpells module")

local container = { GetWidth = function() return 280 end }
local function place(spellList, y)
    local banner = read(spellList)
    return SS:Place(container, banner, y or 100)
end

-- The button is built, bound and placed out of combat, and it arms the shared latch.
local h = place({ { icon = 237559, name = "Foul Ball", spellID = 1295317 } })
ok(h == 32, "one spell reserves the button plus its top gap, got " .. tostring(h))
ok(adoptedCount == 1, "the button registered with ItemButtons, got " .. tostring(adoptedCount))
ok(armedFlag, "building a secure button arms the latch")
ok(has(SS:DebugLine(), "wanted 1, live 1, pooled 0"), "status: " .. SS:DebugLine())
ok(has(SS:DebugLine(), "Foul Ball"), "the status line names the spell")
ok(built[1].attrs.type == "spell" and built[1].attrs.spell == 1295317,
   "the ID is bound straight to the secure spell attribute")
-- The label is the readable half of the control, so the hit rect has to reach across it.
ok(built[1].hitRight == -222,
   "the hit rect covers the label, got " .. tostring(built[1].hitRight))

-- Nothing repeats a protected call when nothing moved.
PROTECTED = 0
place({ { icon = 237559, name = "Foul Ball", spellID = 1295317 } })
ok(PROTECTED == 0, "an unchanged render makes no protected call, got " .. tostring(PROTECTED))

-- Moving it is a protected call, and it is taken out of combat.
PROTECTED = 0
place({ { icon = 237559, name = "Foul Ball", spellID = 1295317 } }, 140)
ok(PROTECTED > 0, "a moved button is re-anchored out of combat")

-- IN COMBAT, a button whose spell has NOT changed only moves, so it is left castable where it
-- is rather than blocked into silence.
IN_COMBAT, PROTECTED, deferredKey = true, 0, nil
h = place({ { icon = 237559, name = "Foul Ball", spellID = 1295317 } }, 200)
ok(PROTECTED == 0, "no protected call in combat, got " .. tostring(PROTECTED))
ok(deferredKey == "eqot.deferredRender", "the relayout rides Tracker's own key, got "
   .. tostring(deferredKey))
ok(h == 32, "the height is reserved from the data, not from what could be placed")

-- IN COMBAT, a button whose spell HAS changed cannot be rebound, so it gives up its mouse
-- rather than casting the wrong spell.
IN_COMBAT = false
place({ { name = "Foul Ball", spellID = 1295317 } }, 300)
local btn = built[1]
ok(btn ~= nil and btn.alpha == 1 and btn.mouse, "the button starts live")

IN_COMBAT, PROTECTED, deferredKey = true, 0, nil
place({ { name = "Other", spellID = 4242 } }, 300)
ok(PROTECTED == 0, "rebinding is refused in combat, got " .. tostring(PROTECTED))
ok(deferredKey == "eqot.deferredRender", "the rebind is queued for combat end")
ok(btn.alpha == 0 and btn.mouse == false, "a button that cannot be rebound gives up its mouse")
ok(btn.attrs.spell == 1295317, "and is still bound to what it was")

-- THE SPELL COMING BACK IN THE SAME FIGHT. y has not moved and the binding matches again, so
-- the inert flag is the only thing that can force another look - and blanking without an
-- inverse left the button invisible and dead for the rest of the fight, still bound and still
-- anchored, for no reason. Alpha and mouse are unprotected, so the revival costs nothing.
PROTECTED = 0
place({ { name = "Foul Ball", spellID = 1295317 } }, 300)
ok(btn.alpha == 1 and btn.mouse, "the spell coming back mid fight makes it castable again")
ok(PROTECTED == 0, "and does it with no protected call, got " .. tostring(PROTECTED))
ok(btn.attrs.spell == 1295317, "on the binding it never lost")

-- The whole sequence, in one combat: present, gone, back.
PROTECTED = 0
place(nil, 300)
ok(btn.alpha == 0 and btn.mouse == false, "the list emptying blanks it")
place({ { name = "Foul Ball", spellID = 1295317 } }, 300)
ok(btn.alpha == 1 and btn.mouse, "and the list refilling brings it back")
ok(PROTECTED == 0, "neither half is a protected call, got " .. tostring(PROTECTED))

IN_COMBAT, PROTECTED = false, 0
place({ { name = "Foul Ball", spellID = 1295317 } }, 300)
ok(PROTECTED == 0, "combat ending has nothing left to relayout, got " .. tostring(PROTECTED))
ok(btn.alpha == 1 and btn.mouse and btn.shown, "and the button is still the live one")

-- The ordinary rebind lands too.
IN_COMBAT = true
place({ { name = "Other", spellID = 4242 } }, 300)
IN_COMBAT = false
place({ { name = "Other", spellID = 4242 } }, 300)
ok(btn.attrs.spell == 4242, "the deferred rebind lands once combat ends")
ok(btn.alpha == 1 and btn.mouse, "and the button is castable again")
ok(has(SS:DebugLine(), "Other"), "status: " .. SS:DebugLine())

-- Shrinking retires the surplus rather than leaving a second castable button on screen.
place({ { spellID = 1 }, { spellID = 2 } }, 100)
ok(has(SS:DebugLine(), "wanted 2, live 2"), "two spells draw two, status: " .. SS:DebugLine())
local btn2 = built[2]
h = place({ { spellID = 1 } }, 100)
ok(h == 32, "the shorter run reserves one row, got " .. tostring(h))
ok(has(SS:DebugLine(), "wanted 1, live 1, pooled 1"),
   "the surplus button is pooled, status: " .. SS:DebugLine())
ok(btn2.alpha == 0 and btn2.shown, "retiring blanks rather than hides, so it stays reclaimable")
ok(btn2.attrs.spell == 2, "and keeps its binding")

-- A RETIRED SPELL COMING BACK MID FIGHT. Nothing can be shown or anchored in combat, so the
-- only button that can serve is one already sitting in that slot with that binding.
IN_COMBAT, PROTECTED = true, 0
place({ { spellID = 1 }, { spellID = 2 } }, 100)
ok(PROTECTED == 0, "reclaiming makes no protected call, got " .. tostring(PROTECTED))
ok(btn2.alpha == 1 and btn2.mouse, "the pooled button is castable again")
ok(has(SS:DebugLine(), "wanted 2, live 2, pooled 0"),
   "and is back in the live set, status: " .. SS:DebugLine())

-- AN EMPTY LIST AND AN ABSENT FIELD ARE THE SAME ANSWER, and both are silent on purpose: a
-- scenario that grants no spell must not read like one whose payload could not be handled.
local _, emptyLine = read({})
local _, absentLine = read(nil)
ok(not has(emptyLine, "spells"), "an empty spells list says nothing, status: " .. emptyLine)
ok(emptyLine == absentLine, "and reads exactly as an absent field does")

-- THE ANCHOR GUARD, which is what stops a reclaim putting a button back at the wrong row.
-- Pool one, move the run while out of combat, then ask for it back mid fight. Anchoring is
-- protected, so the only honest answer is to refuse it and wait.
IN_COMBAT = false
place({ { spellID = 1 } }, 100)
place({ { spellID = 1 } }, 400)
IN_COMBAT, PROTECTED = true, 0
place({ { spellID = 1 }, { spellID = 2 } }, 400)
ok(PROTECTED == 0, "refusing a stale pooled button costs no protected call, got " .. tostring(PROTECTED))
ok(has(SS:DebugLine(), "wanted 2, live 1, pooled 1"),
   "a button parked at another row is refused rather than moved, status: " .. SS:DebugLine())

-- Clear has no combat branch, and the reason it needs none is that retiring makes no protected
-- call. Assert that rather than the shape of the code.
IN_COMBAT, PROTECTED = true, 0
SS:Clear()
ok(PROTECTED == 0, "Clear in combat makes no protected call, got " .. tostring(PROTECTED))

-- The scenario ending takes them all, and nothing is reserved.
IN_COMBAT = false
h = place(nil, 100)
ok(h == 0, "no spells reserves no height, got " .. tostring(h))
SS:Clear()
ok(has(SS:DebugLine(), "wanted 0, live 0, pooled 2"), "Clear pools them, status: " .. SS:DebugLine())

print(string.format("test_scenario_spells: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
