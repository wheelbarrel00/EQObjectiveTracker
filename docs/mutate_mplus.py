"""Prove docs/test_mplus.lua actually discriminates, by breaking production on purpose one change
at a time and checking the harness notices.

    python docs/mutate_mplus.py        (run from the repo root)

Why this exists: the Mythic+ key panel (reported missing by Hermonii, 2026-10-11) shipped without
ever being seen in a real key, because no session and not the author can run one. This battery is
the evidence its reads, its clock and its layout do what they claim. Every mutation reintroduces a
defect the harness is supposed to stand guard over: a timer that never starts or never stops, a
clock that runs backwards or freezes, +2 and +3 swapped, a depleted marker on every key, a panel
that keeps the banner under it, a switch that cannot switch it off, a secret value reaching a
comparison. Any that still reports "0 failed" is an assertion that does not discriminate, and the
run exits 1 naming it.

The pre-release scans of 2026-10-11 hand-broke this code and most of the first scan's breaks
passed a green suite. The battery grew out of their lists, each mutant under the section of the
file it breaks.

A mutant marked EQUIVALENT is expected to survive and fails the run if caught. The ones left as
such: the clock's 0.1 second throttle (only how often the same text is set), and the per-second
repaint skip in _Tick (the same).

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run still
puts the file back, and it verifies the restore and re-checks the baseline before reporting. This
checkout is junctioned into AddOns, so run it from a scratch copy while the game is open.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_mplus.lua"

K = "Data/Keystone.lua"
P = "Data/Providers/Scenarios.lua"
M = "UI/MythicPlus.lua"
S = "UI/Scenario.lua"
C = "UI/Commands.lua"
D = "Core/DB.lua"
T = "Options/TabTracker.lua"
CO = "Core/Compat.lua"
TM = "EQObjectiveTracker_Mainline.toc"
TV = "EQObjectiveTracker_Vanilla.toc"
BS = chr(92)

MUTANTS = [
    # ------------------------------------------------------------------- Data/Keystone.lua
    ("the enum is ignored and type 1 hard-coded", [
        (K, "    return (E and num(E.ChallengeMode)) or CHALLENGE_TIMER\n", "    return CHALLENGE_TIMER\n")]),
    ("with no enum the fallback is the proving grounds type", [
        (K, "local CHALLENGE_TIMER = 1\n", "local CHALLENGE_TIMER = 2\n")]),
    ("+2 and +3 shares swapped", [
        (K, "local PLUS_TWO, PLUS_THREE = 0.8, 0.6\n", "local PLUS_TWO, PLUS_THREE = 0.6, 0.8\n")]),
    ("+3 share nudged", [
        (K, "local PLUS_TWO, PLUS_THREE = 0.8, 0.6\n", "local PLUS_TWO, PLUS_THREE = 0.8, 0.65\n")]),
    ("+2 share nudged", [
        (K, "local PLUS_TWO, PLUS_THREE = 0.8, 0.6\n", "local PLUS_TWO, PLUS_THREE = 0.75, 0.6\n")]),
    ("five affixes allowed", [
        (K, "local MAX_AFFIXES = 4\n", "local MAX_AFFIXES = 5\n")]),
    ("a secret is not refused", [
        (K, "    if _issecret and _issecret(v) then\n", "    if false then\n")]),
    ("the secret named is the last one met, not the first", [
        (K, "        secretField = secretField or field\n", "        secretField = field\n")]),
    ("anything plain passes as a number", [
        (K, '    return type(v) == "number" and v or nil\n', "    return v\n")]),
    ("a secret number is named and still handed back", [
        (K, "    v = plain(v, field)\n", "    plain(v, field)\n")]),
    ("the walk stops after the first timer", [
        (K, "    return scanTimers(want, true, ...)\n", "    return nil\n")]),
    ("a stopped timer ends the walk", [
        (K, "    if id and not stopped[id] then\n",
            "    if id and stopped[id] then return nil end\n    if id then\n")]),
    ("the stopped list is ignored", [
        (K, "    if id and not stopped[id] then\n", "    if id then\n")]),
    ("a secret timer id is used", [
        (K, '    id = num(id, "timer id")\n', "")]),
    ("any timer type is taken", [
        (K, '        if okT and num(kind, "timer type") == want and elapsed then return id, elapsed end\n',
            "        if okT and elapsed then return id, elapsed end\n")]),
    ("a secret timer type is compared", [
        (K, '        if okT and num(kind, "timer type") == want and elapsed then return id, elapsed end\n',
            "        if okT and kind == want and elapsed then return id, elapsed end\n")]),
    ("the elapsed read is not pcalled", [
        (K, "        local okT, _, elapsed, kind = pcall(GetWorldElapsedTime, id)\n",
            "        local okT, _, elapsed, kind = true, GetWorldElapsedTime(id)\n")]),
    ("a secret elapsed figure is used", [
        (K, '        elapsed = okT and num(elapsed, "elapsed") or nil\n', "        elapsed = okT and elapsed or nil\n")]),
    ("an unnamed affix is cached for good", [
        (K, '    if type(name) ~= "string" then return nil end\n',
            '    if type(name) ~= "string" then affixInfo[id] = { id = id } return affixInfo[id] end\n')]),
    ("a raising affix read is cached with the error as its name", [
        (K, "    local ok, name, description, icon = pcall(C_ChallengeMode.GetAffixInfo, id)\n    if not ok then return nil end\n",
            "    local ok, name, description, icon = pcall(C_ChallengeMode.GetAffixInfo, id)\n")]),
    ("a secret affix name is used", [
        (K, '    name = plain(name, "affix name")\n', "")]),
    ("a secret affix name is named and still used", [
        (K, '    name = plain(name, "affix name")\n', '    plain(name, "affix name")\n')]),
    ("a secret affix icon is used", [
        (K, '    icon = plain(icon, "affix icon")\n', "")]),
    ("a secret affix icon is named and still used", [
        (K, '    icon = plain(icon, "affix icon")\n', '    plain(icon, "affix icon")\n')]),
    ("a secret affix description is used", [
        (K, '    description = plain(description, "affix description")\n', "")]),
    ("a secret affix description is named and still used", [
        (K, '    description = plain(description, "affix description")\n',
            '    plain(description, "affix description")\n')]),
    ("any icon value is kept", [
        (K, '        icon        = (type(icon) == "number" or type(icon) == "string") and icon or nil,\n',
            "        icon        = icon,\n")]),
    ("every affix is asked again on every read", [
        (K, "    local a = affixInfo[id]\n    if a then return a end\n", "    local a\n")]),
    ("a shorter affix list keeps the longer one's tail", [
        (K, "    for i = #key.affixes, 1, -1 do key.affixes[i] = nil end\n", "")]),
    ("the affix count is not reset", [
        (K, '    key.affixN = 0\n    list = plain(list, "affixes")\n', '    list = plain(list, "affixes")\n')]),
    ("a secret affix list is read", [
        (K, '    list = plain(list, "affixes")\n', "")]),
    ("a secret affix id is used", [
        (K, '        local id = num(list[i], "affix id")\n', "        local id = list[i]\n")]),
    ("the affix cap is not checked", [
        (K, "        if a and key.affixN < MAX_AFFIXES then\n", "        if a then\n")]),
    ("affix description and icon read from each other's place", [
        (K, "    local ok, name, description, icon = pcall(C_ChallengeMode.GetAffixInfo, id)\n",
            "    local ok, name, icon, description = pcall(C_ChallengeMode.GetAffixInfo, id)\n")]),
    ("the time limit read from GetMapUIInfo's second value", [
        (K, "    local ok, name, _, limit = pcall(C_ChallengeMode.GetMapUIInfo, mapID)\n",
            "    local ok, name, limit = pcall(C_ChallengeMode.GetMapUIInfo, mapID)\n")]),
    ("the map info read is not pcalled", [
        (K, "    local ok, name, _, limit = pcall(C_ChallengeMode.GetMapUIInfo, mapID)\n",
            "    local ok, name, _, limit = true, C_ChallengeMode.GetMapUIInfo(mapID)\n")]),
    ("a raising map info read hands on the error as the name", [
        (K, "    if not ok then return nil, nil end\n", "")]),
    ("a secret map name is used", [
        (K, '    name = plain(name, "map name")\n', "")]),
    ("a secret map name is named and still used", [
        (K, '    name = plain(name, "map name")\n', '    plain(name, "map name")\n')]),
    ("a secret time limit is used", [
        (K, '    return type(name) == "string" and name or nil, num(limit, "time limit")\n',
            '    return type(name) == "string" and name or nil, limit\n')]),
    ("the time limit is screened for a secret but not for a number", [
        (K, '    return type(name) == "string" and name or nil, num(limit, "time limit")\n',
            '    return type(name) == "string" and name or nil, (plain(limit, "time limit") and limit)\n')]),
    ("restamped on every read, so a repaint sets the clock back", [
        (K, "    if timerID ~= lastTimerID or elapsed ~= lastElapsed then\n", "    if true then\n")]),
    ("not restamped for a different timer at the same figure", [
        (K, "    if timerID ~= lastTimerID or elapsed ~= lastElapsed then\n", "    if elapsed ~= lastElapsed then\n")]),
    ("never restamped once stamped", [
        (K, "    if timerID ~= lastTimerID or elapsed ~= lastElapsed then\n", "    if lastStamp == nil then\n")]),
    ("no capability check", [
        (K, "    if not ns.Has.ChallengeTimer then\n        note = \"not on this client\"\n",
            "    if false then\n        note = \"not on this client\"\n")]),
    ("the map read is not pcalled", [
        (K, "    local okMap, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)\n",
            "    local okMap, mapID = true, C_ChallengeMode.GetActiveChallengeMapID()\n")]),
    ("a raising map read is reported as no key", [
        (K, '        note = okMap and "no key running" or "map read raised"\n', '        note = "no key running"\n')]),
    ("a secret map id is used", [
        (K, '    mapID = okMap and num(mapID, "map id") or nil\n', "    mapID = okMap and mapID or nil\n")]),
    ("the timer list is not pcalled", [
        (K, "    local timerID, elapsed = scanTimers(timerType(), pcall(GetWorldElapsedTimers))\n",
            "    local timerID, elapsed = scanTimers(timerType(), true, GetWorldElapsedTimers())\n")]),
    ("a zero time limit is accepted", [
        (K, "    if not (limit and limit > 0) then\n", "    if not limit then\n")]),
    ("a secret level is used", [
        (K, '    key.level = okKey and num(level, "level") or nil\n', "    key.level = okKey and level or nil\n")]),
    ("anything but true reads as depleted", [
        (K, '    key.depleted = okKey and plain(energized, "energized") == false or false\n',
            '    key.depleted = okKey and not plain(energized, "energized") or false\n')]),
    ("the keystone read is not pcalled", [
        (K, "    local okKey, level, affixes, energized = pcall(C_ChallengeMode.GetActiveKeystoneInfo)\n",
            "    local okKey, level, affixes, energized = true, C_ChallengeMode.GetActiveKeystoneInfo()\n")]),
    ("the death read is not pcalled", [
        (K, "    local okD, deaths, lost = pcall(C_ChallengeMode.GetDeathCount)\n",
            "    local okD, deaths, lost = true, C_ChallengeMode.GetDeathCount()\n")]),
    ("deaths and time lost swapped", [
        (K, '    key.deaths   = okD and num(deaths, "deaths") or 0\n    key.timeLost = okD and num(lost, "time lost") or 0\n',
            '    key.deaths   = okD and num(lost, "time lost") or 0\n    key.timeLost = okD and num(deaths, "deaths") or 0\n')]),
    ("a secret death count is used", [
        (K, '    key.deaths   = okD and num(deaths, "deaths") or 0\n', "    key.deaths   = okD and deaths or 0\n")]),
    ("a secret time lost is used", [
        (K, '    key.timeLost = okD and num(lost, "time lost") or 0\n', "    key.timeLost = okD and lost or 0\n")]),
    ("a real key is never marked active", [
        (K, "    stamp(timerID, elapsed)\n    key.active = true\n", "    stamp(timerID, elapsed)\n")]),
    ("a read keeps the last read's active flag", [
        (K, "    key.active, key.test, note, secretField = false, nil, nil, nil\n",
            "    key.test, note, secretField = nil, nil, nil\n")]),
    ("a read keeps the last read's secret", [
        (K, "    key.active, key.test, note, secretField = false, nil, nil, nil\n",
            "    key.active, key.test, note = false, nil, nil\n")]),
    ("idle keeps the last key active", [
        (K, "    key.active, key.test, note, secretField = false, nil, why, nil\n",
            "    note, secretField = why, nil\n")]),
    ("idle keeps the last secret", [
        (K, "    key.active, key.test, note, secretField = false, nil, why, nil\n",
            "    key.active, key.test, note = false, nil, why\n")]),
    ("the test key is not marked", [
        (K, "    key.active, key.test, note, secretField = false, test, nil, nil\n",
            "    key.active, key.test, note, secretField = false, nil, nil, nil\n")]),
    ("the sample keeps a real read's secret on the line", [
        (K, "    key.active, key.test, note, secretField = false, test, nil, nil\n",
            "    key.active, key.test, note = false, test, nil\n")]),
    ("a secret first map is the sample's dungeon", [
        (K, "    if type(maps) == \"table\" then mapID = num(maps[1]) end\n",
            "    if type(maps) == \"table\" then mapID = maps[1] end\n")]),
    ("the sample keeps the real key's map id", [
        (K, "    key.mapID, key.mapName, key.level = mapID, mapName, TEST_LEVEL\n",
            "    key.mapID, key.mapName, key.level = key.mapID or mapID, mapName, TEST_LEVEL\n")]),
    ("the sample reads the map table outside a pcall", [
        (K, "    local okMaps, maps = pcall(CM and CM.GetMapTable)\n",
            "    local okMaps, maps = true, CM.GetMapTable()\n")]),
    ("a secret map table is read", [
        (K, "    maps = okMaps and plain(maps) or nil\n", "    maps = okMaps and maps or nil\n")]),
    ("a listed map with no limit is used as is", [
        (K, "    limit = (limit and limit > 0) and limit or TEST_LIMIT\n", "    limit = limit or TEST_LIMIT\n")]),
    ("the test start moves on every read", [
        (K, "    if not test.start then\n", "    if true then\n")]),
    ("late starts where test does", [
        (K, "        test.start = test.late and (limit - TEST_LATE_LEAD) or (key.plusThree - TEST_LEAD)\n",
            "        test.start = key.plusThree - TEST_LEAD\n")]),
    ("the test leads +3 by the wrong amount", [
        (K, "local TEST_LEAD, TEST_LATE_LEAD = 20, 15\n", "local TEST_LEAD, TEST_LATE_LEAD = 30, 15\n")]),
    ("late is never depleted", [
        (K, "    key.depleted = test.late\n", "    key.depleted = false\n")]),
    ("test after late stays depleted", [
        (K, "    key.depleted = test.late\n", "    key.depleted = key.depleted or test.late\n")]),
    ("current affixes read as ids when they are tables", [
        (K, '            ids[#ids + 1] = type(c) == "table" and c.id or c\n', "            ids[#ids + 1] = c\n")]),
    ("a secret current-affix list is read", [
        (K, "    current = okA and plain(current) or nil\n", "    current = okA and current or nil\n")]),
    ("the test limit without a map", [
        (K, "local TEST_LIMIT, TEST_LEVEL = 1800, 12\n", "local TEST_LIMIT, TEST_LEVEL = 1900, 12\n")]),
    ("no C_MythicPlus table raises", [
        (K, "    local okA, current = pcall(C_MythicPlus and C_MythicPlus.GetCurrentAffixes)\n",
            "    local okA, current = pcall(C_MythicPlus.GetCurrentAffixes)\n")]),
    ("the fallback affixes are wrong", [
        (K, "local TEST_AFFIXES = { 9, 10 }\n", "local TEST_AFFIXES = { 10, 9 }\n")]),
    ("any mode turns the test on", [
        (K, '    if mode == "test" or mode == "late" then\n', "    if mode then\n")]),
    ("turning the sample on restarts every stopped timer", [
        (K, '        test = { late = (mode == "late") }\n',
            '        wipe(stopped)\n        test = { late = (mode == "late") }\n')]),
    ("the test mode is reported the wrong way round", [
        (K, '    return test.late and "late" or "test"\n', '    return test.late and "test" or "late"\n')]),
    ("a timer starting does not clear its stop", [
        (K, "    if id then stopped[id] = nil end\n", "")]),
    ("a timer start does not rebase the clock", [
        (K, "    if id then stopped[id] = nil end\n    lastElapsed = nil\n",
            "    if id then stopped[id] = nil end\n")]),
    ("a timer stopping is not recorded", [
        (K, "    if id then stopped[id] = true end\n", "")]),
    ("a secret start id is used as it came", [
        (K, "    id = num(id)\n    if id then stopped[id] = nil end\n", "    if id then stopped[id] = nil end\n")]),
    ("a secret stop id is used as it came", [
        (K, "    id = num(id)\n    if id then stopped[id] = true end\n", "    if id then stopped[id] = true end\n")]),
    ("a start with no usable id does not rebase the clock", [
        (K, "    if id then stopped[id] = nil end\n    lastElapsed = nil\n",
            "    if id then\n        stopped[id] = nil\n        lastElapsed = nil\n    end\n")]),
    ("a start forgets the timer instead of the reading", [
        (K, "    if id then stopped[id] = nil end\n    lastElapsed = nil\n",
            "    if id then stopped[id] = nil end\n    lastTimerID = nil\n")]),
    ("a stop also rebases the clock", [
        (K, "    id = num(id)\n    if id then stopped[id] = true end\n",
            "    id = num(id)\n    if id then stopped[id] = true end\n    lastElapsed = nil\n")]),
    ("a new key keeps the old stops", [
        (K, "    wipe(stopped)\n", "")]),
    ("a new key does not rebase the clock", [
        (K, "    wipe(stopped)\n    lastElapsed = nil\n", "    wipe(stopped)\n")]),
    ("a new key forgets the timer last read", [
        (K, "    wipe(stopped)\n    lastElapsed = nil\n", "    wipe(stopped)\n    lastElapsed, lastTimerID = nil, nil\n")]),
    ("a finished run keeps counting", [
        (K, "    if lastTimerID then stopped[lastTimerID] = true end\n", "")]),
    ("a finished run forgets the timer it stopped", [
        (K, "    if lastTimerID then stopped[lastTimerID] = true end\n",
            "    if lastTimerID then stopped[lastTimerID] = true end\n    lastTimerID = nil\n")]),
    ("the status line reads a key on a client with no API", [
        (K, '    if not ns.Has.ChallengeTimer then return "mythic+: not on this client" end\n', "")]),
    ("the status line hides a secret", [
        (K, '            secretField and (" | secret: " .. secretField) or "")\n    end\n', '            "")\n    end\n')]),
    ("the status line swaps elapsed and limit", [
        (K, "        math.floor(elapsed), key.timeLimit or 0,\n",
            "        key.timeLimit or 0, math.floor(elapsed),\n")]),
    ("the status line prints the reading, not the clock", [
        (K, "    if key.elapsedAt then elapsed = elapsed + (GetTime() - key.elapsedAt) end\n", "")]),
    ("the status line counts from the last real stamp, not the sample's", [
        (K, "    if key.elapsedAt then elapsed = elapsed + (GetTime() - key.elapsedAt) end\n",
            "    if key.elapsedAt then elapsed = elapsed + (GetTime() - (lastStamp or key.elapsedAt)) end\n")]),
    ("the status line stops at the time limit", [
        (K, "    if key.elapsedAt then elapsed = elapsed + (GetTime() - key.elapsedAt) end\n",
            "    if key.elapsedAt then elapsed = math.min(elapsed + (GetTime() - key.elapsedAt), key.timeLimit or 0) end\n")]),
    ("the status line names the last real timer during a test", [
        (K, '        tostring(key.mapID), key.test and "none" or tostring(lastTimerID),\n',
            "        tostring(key.mapID), tostring(lastTimerID),\n")]),
    ("the status line swaps +2 and +3", [
        (K, "        math.floor(key.plusTwo or 0), math.floor(key.plusThree or 0),\n",
            "        math.floor(key.plusThree or 0), math.floor(key.plusTwo or 0),\n")]),
    ("the status line says none for affixes it has", [
        (K, '        key.affixN > 0 and table.concat(ids, ",") or "none",\n', '        "none",\n')]),
    ("the status line claims no key before the first read", [
        (K, 'local note = "not read yet"\n', "local note\n")]),

    # ------------------------------------------------------- Data/Providers/Scenarios.lua
    ("the switch is ignored by the reads", [
        (P, '    facts.keystone     = timerWanted() and Keystone:Read() or Keystone:Idle("switched off")\n',
            "    facts.keystone     = Keystone:Read()\n")]),
    ("a real scenario never reads the key", [
        (P, '    facts.keystone     = timerWanted() and Keystone:Read() or Keystone:Idle("switched off")\n',
            '    facts.keystone     = Keystone:Idle("switched off")\n')]),
    ("the switch is read inverted", [
        (P, "    return not (cfg and cfg.showMythicPlusTimer == false)\n",
            "    return cfg and cfg.showMythicPlusTimer == false\n")]),
    ("an unset switch reads off in the provider", [
        (P, "    return not (cfg and cfg.showMythicPlusTimer == false)\n",
            "    return cfg and cfg.showMythicPlusTimer\n")]),
    ("the switch read with a dot call", [
        (P, "    local cfg = DB and DB:Tracker()\n    return not", "    local cfg = DB and DB.Tracker()\n    return not")]),
    ("no scenario leaves the last key on the status line", [
        (P, '        Keystone:Idle("no scenario running")\n', "")]),
    ("a real scenario does not end a test", [
        (P, "    if Keystone:IsTesting() then Keystone:SetTest(nil) end\n", "")]),
    ("the banner carries an inactive key", [
        (P, "    banner.keystone     = (key and key.active) and key or nil\n", "    banner.keystone     = key\n")]),
    ("the banner never carries the key", [
        (P, "    banner.keystone     = (key and key.active) and key or nil\n", "    banner.keystone     = nil\n")]),
    ("no test branch", [
        (P, "        if Keystone:IsTesting() then return fillTest() end\n", "")]),
    ("the test bar carries a word to translate", [
        (P, '    ln.text, ln.completed = "", false\n', '    ln.text, ln.completed = "Enemy Forces", false\n')]),
    ("the test bar is a count", [
        (P, "    ln.kind, ln.current, ln.required = LINE.WEIGHTED, TEST_FORCES, 100\n",
            "    ln.kind, ln.current, ln.required = LINE.PROGRESSBAR, TEST_FORCES, 100\n")]),
    ("the test entry reads finished", [
        (P, "    Entry.EndLines(e)\n    e.state = STATE.ACTIVE\n\n    clearStepSpells()\n",
            "    Entry.EndLines(e)\n    e.state = STATE.COMPLETE\n\n    clearStepSpells()\n")]),
    ("the test keeps the last scenario's spells", [
        (P, "    e.state = STATE.ACTIVE\n\n    clearStepSpells()\n", "    e.state = STATE.ACTIVE\n\n")]),
    ("the test keeps the last scenario's widget set", [
        (P, "    facts.widgetSetID  = nil\n", "")]),
    ("the test keeps the last scenario's texture kit", [
        (P, "    facts.textureKit   = nil\n", "")]),
    ("the test has no title without a map", [
        (P, '    e.title = key.mapName or L["Mythic+"]\n', "    e.title = key.mapName\n")]),
    ("the test category is not Mythic+", [
        (P, '    facts.category     = L["Mythic+"]\n', '    facts.category     = L["Scenario"]\n')]),
    ("the test panel carries no key", [
        (P, "    facts.keystone     = key\n", "")]),
    ("the test panel has two stages", [
        (P, "    facts.numStages    = 1\n", "    facts.numStages    = 2\n")]),
    ("the test panel is stage 0", [
        (P, "    facts.stage        = 1\n", "    facts.stage        = 0\n")]),
    ("the toggle never clears", [
        (P, "    local on = Keystone:IsTesting() and Keystone:TestMode() == mode\n", "    local on = false\n")]),
    ("the toggle clears whichever mode is asked", [
        (P, "    local on = Keystone:IsTesting() and Keystone:TestMode() == mode\n",
            "    local on = Keystone:IsTesting()\n")]),
    ("the toggle asks for no repaint", [
        (P, "    self._notifyDirty()\n    if now and not timerWanted()", "    if now and not timerWanted()")]),
    ("the toggle runs on a provider never enabled", [
        (P, '    if not self._notifyDirty then return false, "off" end\n', "")]),
    ("the toggle turns a test on inside a real scenario", [
        (P, '    if running(readScenario()) then\n        Keystone:SetTest(nil)\n        return false, "scenario"\n    end\n',
            "")]),
    ("the toggle leaves a test on inside a real scenario", [
        (P, '        Keystone:SetTest(nil)\n        return false, "scenario"\n', '        return false, "scenario"\n')]),
    ("the toggle ends only a late sample it finds", [
        (P, '        Keystone:SetTest(nil)\n        return false, "scenario"\n',
            '        if Keystone:TestMode() == "late" then Keystone:SetTest(nil) end\n        return false, "scenario"\n')]),
    ("the events end only a test-mode sample, so a late one survives", [
        (P, "    if Keystone:IsTesting() and running(readScenario()) then Keystone:SetTest(nil) end\n",
            '    if Keystone:TestMode() == "test" and running(readScenario()) then Keystone:SetTest(nil) end\n')]),
    ("the events end a test only with the box on", [
        (P, "    if Keystone:IsTesting() and running(readScenario()) then Keystone:SetTest(nil) end\n",
            "    if Keystone:IsTesting() and running(readScenario()) and timerWanted() then Keystone:SetTest(nil) end\n")]),
    ("the events end a test with no scenario", [
        (P, "    if Keystone:IsTesting() and running(readScenario()) then Keystone:SetTest(nil) end\n",
            "    if Keystone:IsTesting() then Keystone:SetTest(nil) end\n")]),
    ("the events never end a test", [
        (P, "    if Keystone:IsTesting() and running(readScenario()) then Keystone:SetTest(nil) end\n", "")]),
    ("a scenario update does not end a test", [
        (P, '    Events:On("SCENARIO_UPDATE", function()\n        endTest()\n',
            '    Events:On("SCENARIO_UPDATE", function()\n')]),
    ("a scenario update asks for no repaint", [
        (P, '    Events:On("SCENARIO_UPDATE", function()\n        endTest()\n        notifyDirty()\n',
            '    Events:On("SCENARIO_UPDATE", function()\n        endTest()\n')]),
    ("the scenario update event misnamed", [
        (P, '    Events:On("SCENARIO_UPDATE", function()\n', '    Events:On("SCENARIO_UPDATED", function()\n')]),
    ("a loading screen does not end a test", [
        (P, '    Events:On("PLAYER_ENTERING_WORLD", function()\n        Keystone:Started()\n        endTest()\n',
            '    Events:On("PLAYER_ENTERING_WORLD", function()\n        Keystone:Started()\n')]),
    ("a key start does not end a test", [
        (P, '    Events:On("CHALLENGE_MODE_START", function()\n        Keystone:Started()\n        endTest()\n',
            '    Events:On("CHALLENGE_MODE_START", function()\n        Keystone:Started()\n')]),
    ("the toggle never says the box is off", [
        (P, '    if now and not timerWanted() then return true, "switched off" end\n', "")]),
    ("a timer stop is not recorded", [
        (P, "        Keystone:TimerStopped(id)\n", "")]),
    ("a timer start is not recorded", [
        (P, "        Keystone:TimerStarted(id)\n", "")]),
    ("a key start keeps the old stops", [
        (P, '    Events:On("CHALLENGE_MODE_START", function()\n        Keystone:Started()\n',
            '    Events:On("CHALLENGE_MODE_START", function()\n')]),
    ("a loading screen keeps the old stops", [
        (P, '    Events:On("PLAYER_ENTERING_WORLD", function()\n        Keystone:Started()\n',
            '    Events:On("PLAYER_ENTERING_WORLD", function()\n')]),
    ("completion is not wired", [
        (P, '    Events:On("CHALLENGE_MODE_COMPLETED",           finished)\n', "")]),
    ("a reset is not wired", [
        (P, '    Events:On("CHALLENGE_MODE_RESET",               finished)\n', "")]),
    ("a death is not wired", [
        (P, '    Events:On("CHALLENGE_MODE_DEATH_COUNT_UPDATED", notifyDirty)\n', "")]),
    ("a timer stop asks for no repaint", [
        (P, "        Keystone:TimerStopped(id)\n        notifyDirty()\n", "        Keystone:TimerStopped(id)\n")]),
    ("a finished run is not stopped", [
        (P, "        Keystone:Finished()\n", "")]),
    ("the stop event misnamed", [
        (P, '    Events:On("WORLD_STATE_TIMER_STOP", function(_, id)\n',
            '    Events:On("WORLD_STATE_TIMER_STOPPED", function(_, id)\n')]),
    ("running() is just a name", [
        (P, "    return name and numStages and numStages > 0 and stage and stage > 0\n", "    return name\n")]),
    ("running() ignores the stage", [
        (P, "    return name and numStages and numStages > 0 and stage and stage > 0\n",
            "    return name and numStages and numStages > 0\n")]),
    ("running() takes zero stages", [
        (P, "    return name and numStages and numStages > 0 and stage and stage > 0\n",
            "    return name and numStages and numStages >= 0 and stage and stage > 0\n")]),
    ("running() needs no name", [
        (P, "    return name and numStages and numStages > 0 and stage and stage > 0\n",
            "    return numStages and numStages > 0 and stage and stage > 0\n")]),
    ("the sample's stage line is empty", [
        (P, "    facts.stageName    = key.mapName\n", "    facts.stageName    = nil\n")]),
    ("the sample's stage line is an empty string", [
        (P, "    facts.stageName    = key.mapName\n", '    facts.stageName    = ""\n')]),
    ("the sample is not typed Mythic+", [
        (P, "    facts.scenarioType = MYTHIC_PLUS_TYPE\n", "    facts.scenarioType = nil\n")]),
    ("the sample keeps the last scenario's type", [
        (P, "    facts.scenarioType = MYTHIC_PLUS_TYPE\n", "")]),
    ("the sample counts no criteria", [
        (P, "    facts.criteria     = 1\n", "    facts.criteria     = 0\n")]),
    ("the sample is not a party instance", [
        (P, '    facts.instType     = "party"\n', "    facts.instType     = nil\n")]),
    ("the sample keeps the last scenario's difficulty", [
        (P, "    facts.diffID       = nil\n    facts.keystone     = key\n", "    facts.keystone     = key\n")]),
    ("the sample keeps the last scenario's stage", [
        (P, "    facts.stage        = 1\n", "")]),
    ("the sample's banner names the entry's title rather than the map", [
        (P, "    facts.name         = key.mapName\n", "    facts.name         = e.title\n")]),
    ("any timer start wipes every stop", [
        (P, "        Keystone:TimerStarted(id)\n", "        Keystone:Started()\n")]),
    ("a loading screen asks for no repaint", [
        (P, '    Events:On("PLAYER_ENTERING_WORLD", function()\n        Keystone:Started()\n        endTest()\n        notifyDirty()\n',
            '    Events:On("PLAYER_ENTERING_WORLD", function()\n        Keystone:Started()\n        endTest()\n')]),
    ("a key start asks for no repaint", [
        (P, '    Events:On("CHALLENGE_MODE_START", function()\n        Keystone:Started()\n        endTest()\n        notifyDirty()\n',
            '    Events:On("CHALLENGE_MODE_START", function()\n        Keystone:Started()\n        endTest()\n')]),
    ("with the box off a real scenario's render does not end the test", [
        (P, "    if Keystone:IsTesting() then Keystone:SetTest(nil) end\n",
            "    if Keystone:IsTesting() and timerWanted() then Keystone:SetTest(nil) end\n")]),
    ("the death event rebases the clock", [
        (P, '    Events:On("CHALLENGE_MODE_DEATH_COUNT_UPDATED", notifyDirty)\n',
            '    Events:On("CHALLENGE_MODE_DEATH_COUNT_UPDATED", function() Keystone:TimerStarted(nil) notifyDirty() end)\n')]),
    ("a key start also starts a test", [
        (P, '    Events:On("CHALLENGE_MODE_START", function()\n        Keystone:Started()\n',
            '    Events:On("CHALLENGE_MODE_START", function()\n        Keystone:Started()\n        Keystone:SetTest("test")\n')]),
    ("criteria updates are not wired", [
        (P, '    Events:On("SCENARIO_CRITERIA_UPDATE",            notifyDirty)\n', "")]),
    ("a delve's data update is not wired", [
        (P, '    Events:On("ACTIVE_DELVE_DATA_UPDATE",            notifyDirty)\n', "")]),
    ("scenario completion is registered twice", [
        (P, '    Events:On("SCENARIO_COMPLETED",                  notifyDirty)\n',
            '    Events:On("SCENARIO_COMPLETED",                  notifyDirty)\n'
            '    Events:On("SCENARIO_COMPLETED",                  notifyDirty)\n')]),
    ("available without the criteria read", [
        (P, "    return ns.Has.Scenario and ns.Has.ScenarioCriteria\n", "    return ns.Has.Scenario\n")]),
    ("the Registry never hands the provider its repaint, so the toggle always says off", [
        ("Data/Registry.lua", "            p._notifyDirty = notify\n", "")]),
    ("the Registry enables a provider /eqot disable switched off", [
        ("Data/Registry.lua", "        if ns:IsProviderDisabled(p.id) then\n", "        if false then\n")]),
    ("the Registry enables a provider the client cannot run", [
        ("Data/Registry.lua", '            p._available = (type(p.IsAvailable) ~= "function") or (p:IsAvailable() and true or false)\n',
                              "            p._available = true\n")]),
    ("the Registry's repaint names no provider", [
        ("Data/Registry.lua", "            local notify = function() fireDirty(p.id) end\n",
                              "            local notify = function() fireDirty(nil) end\n")]),

    # -------------------------------------------------------------------- UI/MythicPlus.lua
    ("a retail table read at load, which raises on Classic", [
        (M, "local Util       = ns.Util\n", "local Util       = ns.Util\nlocal _ = C_MythicPlus.GetCurrentAffixes\n")]),
    ("block width", [(M, "local BLOCK_W, BLOCK_H     = 251, 87\n", "local BLOCK_W, BLOCK_H     = 250, 87\n")]),
    ("block height", [(M, "local BLOCK_W, BLOCK_H     = 251, 87\n", "local BLOCK_W, BLOCK_H     = 251, 86\n")]),
    ("level inset", [(M, "local LEVEL_X, LEVEL_Y     = 28, -18\n", "local LEVEL_X, LEVEL_Y     = 26, -18\n")]),
    ("level drop", [(M, "local LEVEL_X, LEVEL_Y     = 28, -18\n", "local LEVEL_X, LEVEL_Y     = 28, -16\n")]),
    ("time gap", [(M, "local TIME_GAP             = 8\n", "local TIME_GAP             = 6\n")]),
    ("marker size", [(M, "local MARK_W, MARK_H       = 19, 20\n", "local MARK_W, MARK_H       = 20, 20\n")]),
    ("marker gap", [(M, "local MARK_GAP             = 4\n", "local MARK_GAP             = 2\n")]),
    ("affix size", [(M, "local AFFIX_SIZE           = 22\n", "local AFFIX_SIZE           = 24\n")]),
    ("affix icon size", [(M, "local AFFIX_ICON           = 20\n", "local AFFIX_ICON           = 22\n")]),
    ("affix gap", [(M, "local AFFIX_GAP            = 4\n", "local AFFIX_GAP            = 3\n")]),
    ("affix right inset", [(M, "local AFFIX_RIGHT, AFFIX_Y = 28, -18\n", "local AFFIX_RIGHT, AFFIX_Y = 26, -18\n")]),
    ("affix drop", [(M, "local AFFIX_RIGHT, AFFIX_Y = 28, -18\n", "local AFFIX_RIGHT, AFFIX_Y = 28, -16\n")]),
    ("death count place", [(M, "local DEATH_X, DEATH_Y     = -47, 43\n", "local DEATH_X, DEATH_Y     = -45, 43\n")]),
    ("death count size", [(M, "local DEATH_W, DEATH_H     = 20, 16\n", "local DEATH_W, DEATH_H     = 20, 14\n")]),
    ("bar width", [(M, "local BAR_W, BAR_H, BAR_Y  = 207, 13, 10\n", "local BAR_W, BAR_H, BAR_Y  = 200, 13, 10\n")]),
    ("bar height", [(M, "local BAR_W, BAR_H, BAR_Y  = 207, 13, 10\n", "local BAR_W, BAR_H, BAR_Y  = 207, 12, 10\n")]),
    ("bar lift", [(M, "local BAR_W, BAR_H, BAR_Y  = 207, 13, 10\n", "local BAR_W, BAR_H, BAR_Y  = 207, 13, 9\n")]),
    ("bar frame lift", [(M, "local BAR_BG_Y             = 13\n", "local BAR_BG_Y             = 12\n")]),
    ("chest gap", [(M, "local CHEST_GAP, CHEST_SPLIT, CHEST_MIN_H = 2, 8, 14\n", "local CHEST_GAP, CHEST_SPLIT, CHEST_MIN_H = 3, 8, 14\n")]),
    ("chest split", [(M, "local CHEST_GAP, CHEST_SPLIT, CHEST_MIN_H = 2, 8, 14\n", "local CHEST_GAP, CHEST_SPLIT, CHEST_MIN_H = 2, 6, 14\n")]),
    ("chest floor", [(M, "local CHEST_GAP, CHEST_SPLIT, CHEST_MIN_H = 2, 8, 14\n", "local CHEST_GAP, CHEST_SPLIT, CHEST_MIN_H = 2, 8, 12\n")]),
    ("EQUIVALENT: the clock ticks every frame instead of every tenth of a second", [
        (M, "    if f._clock < TICK then return end\n", "")]),
    ("EQUIVALENT: _Tick repaints every call rather than once a second", [
        (M, "    if not force and elapsed == self._shownAt then return end\n", "")]),
    ("frame time is not added up, so the clock freezes at a real frame rate", [
        (M, "    f._clock = (f._clock or 0) + elapsed\n", "    f._clock = elapsed\n")]),
    ("the frame art", [(M, 'local ART      = "challengemode-timer"\n', 'local ART      = "challengemode-timer-x"\n')]),
    ("the fill atlas", [(M, 'local BAR_FILL = "ChallengeMode-TimerFill"\n', 'local BAR_FILL = "ChallengeMode-TimerFillX"\n')]),
    ("the affix ring", [(M, 'local RING     = "ChallengeMode-AffixRing-Sm"\n', 'local RING     = "ChallengeMode-AffixRing"\n')]),
    ("the graveyard icon", [(M, 'local GRAVE    = "poi-graveyard-neutral"\n', 'local GRAVE    = "poi-graveyard"\n')]),
    ("time's up is not red", [(M, "local RED   = { 1, 0.1, 0.1 }\n", "local RED   = { 1, 1, 1 }\n")]),
    ("a missed chest is not gray", [(M, "local MISSED = { 0.5, 0.5, 0.5 }\n", "local MISSED = { 1, 1, 1 }\n")]),
    ("the fallback fill color", [(M, "local FILL_FALLBACK = { 0.95, 0.75, 0.2 }\n", "local FILL_FALLBACK = { 0.26, 0.42, 1 }\n")]),
    ("the clock rounds up", [(M, "    s = math.max(0, math.floor(s or 0))\n", "    s = math.max(0, math.ceil(s or 0))\n")]),
    ("the clock never shows hours", [
        (M, '    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s % 60) end\n', "")]),
    ("minutes without a leading zero", [
        (M, '    return ("%02d:%02d"):format(m, s % 60)\n', '    return ("%d:%02d"):format(m, s % 60)\n')]),
    ("the client's strings are never used", [
        (M, '    return type(v) == "string" and v or nil\n', "    return nil\n")]),
    ("tooltips show while the tracker is click-through", [
        (M, "    if clickThrough() or not title then return end\n", "    if not title then return end\n")]),
    ("the tooltip anchor is ignored", [
        (M, "    tip:SetOwner(owner, anchor)\n", '    tip:SetOwner(owner, "ANCHOR_RIGHT")\n')]),
    ("the tooltip title loses its color and wrap", [
        (M, "    tip:SetText(title, 1, 1, 1, 1, true)\n", "    tip:SetText(title)\n")]),
    ("tooltip lines do not wrap", [
        (M, "        if line then tip:AddLine(line, nil, nil, nil, true) end\n", "        if line then tip:AddLine(line) end\n")]),
    ("tooltip lines are dropped", [
        (M, "        if line then tip:AddLine(line, nil, nil, nil, true) end\n", "")]),
    ("the tooltip is never shown", [
        (M, "    tip:Show()\nend\n", "end\n")]),
    ("the tooltip is never hidden", [
        (M, "    Util.Tooltip():Hide()\n", "")]),
    ("a missing font object is used anyway", [
        (M, "    return _G[name] and name or fallback\n", "    return name\n")]),
    ("the chest icon at no size", [
        (M, "    Util.SafeSetAtlas(m.Chest, CHEST, true)\n", "    Util.SafeSetAtlas(m.Chest, CHEST, false)\n")]),
    ("the red line at no size", [
        (M, "    Util.SafeSetAtlas(m.Line, REDLINE, true)\n", "    Util.SafeSetAtlas(m.Line, REDLINE, false)\n")]),
    ("the red line under the chest", [
        (M, '    m.Line = m:CreateTexture(nil, "ARTWORK", nil, 1)\n', '    m.Line = m:CreateTexture(nil, "ARTWORK")\n')]),
    ("markers keep a tooltip after the mouse leaves", [
        (M, '    m:SetScript("OnLeave", hideTip)\n', "")]),
    ("affix tooltips lose their description", [
        (M, '    showTip(a, "ANCHOR_RIGHT", a._name, a._description)\n', '    showTip(a, "ANCHOR_RIGHT", a._name)\n')]),
    ("affix tooltips anchored left", [
        (M, '    showTip(a, "ANCHOR_RIGHT", a._name, a._description)\n', '    showTip(a, "ANCHOR_LEFT", a._name, a._description)\n')]),
    ("the affix icon unanchored", [
        (M, '    a.Portrait:SetPoint("CENTER")\n', "")]),
    ("the affix ring not stretched", [
        (M, "    a.Border:SetAllPoints()\n", "")]),
    ("the affix ring under the icon", [
        (M, '    a.Border = a:CreateTexture(nil, "OVERLAY")\n', '    a.Border = a:CreateTexture(nil, "BACKGROUND")\n')]),
    ("the affix ring at its atlas size", [
        (M, "    Util.SafeSetAtlas(a.Border, RING, false)\n", "    Util.SafeSetAtlas(a.Border, RING, true)\n")]),
    ("affixes do not take the mouse", [
        (M, "    a:EnableMouse(true)\n", "    a:EnableMouse(false)\n")]),
    ("markers do not take the mouse", [
        (M, "    m:EnableMouse(true)\n", "    m:EnableMouse(false)\n")]),
    ("affixes keep a tooltip after the mouse leaves", [
        (M, '    a:SetScript("OnLeave", hideTip)\n', "")]),
    ("the clock never ticks", [
        (M, "    f._clock = 0\n    MythicPlus:_Tick()\n", "    f._clock = 0\n")]),
    ("the block stays on its old container", [
        (M, "        if self.frame:GetParent() ~= container then self.frame:SetParent(container) end\n", "")]),
    ("the bar's back at no size", [
        (M, "    Util.SafeSetAtlas(f.BarBack, BAR_BACK, true)\n", "    Util.SafeSetAtlas(f.BarBack, BAR_BACK, false)\n")]),
    ("the bar's frame at no size", [
        (M, "    Util.SafeSetAtlas(f.BarBG, BAR_BG, true)\n", "    Util.SafeSetAtlas(f.BarBG, BAR_BG, false)\n")]),
    ("the bar's frame not lifted", [
        (M, '    f.BarBG:SetPoint("BOTTOM", f, "BOTTOM", 0, BAR_BG_Y)\n', "")]),
    ("the fill starts at the block's left edge", [
        (M, '    f.Fill:SetPoint("BOTTOMLEFT", f, "BOTTOM", -BAR_W / 2, BAR_Y)\n',
            '    f.Fill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, BAR_Y)\n')]),
    ("the fill on the art's layer", [
        (M, '    f.Fill = f:CreateTexture(nil, "BORDER")\n', '    f.Fill = f:CreateTexture(nil, "OVERLAY")\n')]),
    ("the chest marks under the bar", [
        (M, '    f.MarkThree = f:CreateTexture(nil, "ARTWORK")\n', '    f.MarkThree = f:CreateTexture(nil, "BACKGROUND")\n')]),
    ("the chest marks shorter than the bar", [
        (M, "        t:SetSize(1, BAR_H)\n", "        t:SetSize(1, 10)\n")]),
    ("the chest marks solid", [
        (M, "        t:SetColorTexture(1, 1, 1, 0.7)\n", "        t:SetColorTexture(1, 1, 1, 1)\n")]),
    ("the art under the bar", [
        (M, '    f.Art = f:CreateTexture(nil, "OVERLAY")\n', '    f.Art = f:CreateTexture(nil, "BACKGROUND")\n')]),
    ("the art not stretched over the block", [
        (M, "    f.Art:SetAllPoints()\n", "")]),
    ("the art at its atlas size", [
        (M, "    Util.SafeSetAtlas(f.Art, ART, false)\n", "    Util.SafeSetAtlas(f.Art, ART, true)\n")]),
    ("the level in the plain font", [
        (M, 'fontObject("GameFontNormalMed2", "GameFontNormal")', '"GameFontNormal"')]),
    ("the time in the large font", [
        (M, '        fontObject("GameFontHighlightHuge", "GameFontHighlightLarge"))\n', '        "GameFontHighlightLarge")\n')]),
    ("the time above the level", [
        (M, '    f.TimeLeft:SetPoint("TOPLEFT", f.Level, "BOTTOMLEFT", 0, -TIME_GAP)\n',
            '    f.TimeLeft:SetPoint("TOPLEFT", f.Level, "BOTTOMLEFT", 0, TIME_GAP)\n')]),
    ("the depleted tooltip loses its line", [
        (M, '            gs("CHALLENGE_MODE_KEYSTONE_DEPLETED_AT_START"))\n', "            nil)\n")]),
    ("the depleted tooltip anchored left", [
        (M, '        showTip(m, "ANCHOR_RIGHT", gs("CHALLENGE_MODE_DEPLETED_KEYSTONE"),\n',
            '        showTip(m, "ANCHOR_LEFT", gs("CHALLENGE_MODE_DEPLETED_KEYSTONE"),\n')]),
    ("time's up says no loot on a full key", [
        (M, "        if not self._depleted then\n", "        if self._depleted then\n")]),
    ("the leader never gets their line", [
        (M, '        elseif UnitIsGroupLeader and UnitIsGroupLeader("player") then\n', "        elseif false then\n")]),
    ("the death icon unanchored", [
        (M, '    f.Death.Icon:SetPoint("LEFT")\n', "")]),
    ("the death icon at no size", [
        (M, "    Util.SafeSetAtlas(f.Death.Icon, GRAVE, true)\n", "    Util.SafeSetAtlas(f.Death.Icon, GRAVE, false)\n")]),
    ("the death count unanchored", [
        (M, '    f.Death.Count:SetPoint("LEFT", f.Death.Icon, "RIGHT", 1, 0)\n', "")]),
    ("the death count anchored right", [
        (M, '        showTip(d, "ANCHOR_LEFT", title and title:format(self._deaths or 0),\n',
            '        showTip(d, "ANCHOR_RIGHT", title and title:format(self._deaths or 0),\n')]),
    ("the death title counts the seconds lost", [
        (M, "title and title:format(self._deaths or 0)", "title and title:format(self._timeLost or 0)")]),
    ("the time lost shows the deaths", [
        (M, "            desc and desc:format(clock(self._timeLost)))\n", "            desc and desc:format(clock(self._deaths)))\n")]),
    ("the death count keeps its tooltip after the mouse leaves", [
        (M, '    f.Death:SetScript("OnLeave", hideTip)\n', "")]),
    ("+3 grows the wrong way", [
        (M, '    f.Plus3:SetPoint("TOPRIGHT", f, "BOTTOM", -CHEST_SPLIT, -CHEST_GAP)\n',
            '    f.Plus3:SetPoint("TOPLEFT", f, "BOTTOM", -CHEST_SPLIT, -CHEST_GAP)\n')]),
    ("+2 on the wrong side", [
        (M, '    f.Plus2:SetPoint("TOPLEFT", f, "BOTTOM", CHEST_SPLIT, -CHEST_GAP)\n',
            '    f.Plus2:SetPoint("TOPLEFT", f, "BOTTOM", -CHEST_SPLIT, -CHEST_GAP)\n')]),
    ("no criteria font on the chest line", [
        (M, "    Media:ApplyScenarioCriteriaFont(fs)\n", "")]),
    ("no text shadow on the chest line", [
        (M, "    Media:ApplyTextShadow(fs)\n", "")]),
    ("the level loses the banner shadow", [
        (M, "    Media:ApplyScenarioShadow(f.Level)\n", "")]),
    ("the time loses the banner shadow", [
        (M, "    Media:ApplyScenarioShadow(f.TimeLeft)\n", "")]),
    ("the death count loses the banner shadow", [
        (M, "    Media:ApplyScenarioShadow(f.Death.Count)\n", "")]),
    ("Banner Text Size grows the clock inside the block", [
        (M, "    Media:ApplyScenarioShadow(f.TimeLeft)\n",
            "    Media:ApplyScenarioShadow(f.TimeLeft)\n    Media:ApplyScenarioFont(f.TimeLeft, { f.TimeLeft:GetFont() })\n")]),
    ("+2 unstyled", [
        (M, "    criteriaFont(Media, f.Plus2)\n", "")]),
    ("an empty bar keeps its fill", [
        (M, "    if frac <= 0 then\n        fill:Hide()\n        return\n    end\n", "")]),
    ("the fill hides with time still left", [
        (M, "    if frac <= 0 then\n", "    if frac <= 0.01 then\n")]),
    ("an atlas named by path is not used", [
        (M, "        if info and (info.file or info.filename) then\n", "        if info and info.file then\n")]),
    ("the fill is not cropped", [
        (M, "        fill:SetTexCoord(l, l + (r - l) * frac, info.topTexCoord or 0, info.bottomTexCoord or 1)\n",
            "        fill:SetTexCoord(l, r, info.topTexCoord or 0, info.bottomTexCoord or 1)\n")]),
    ("the fill is always full width", [
        (M, "    fill:SetWidth(BAR_W * frac)\n", "    fill:SetWidth(BAR_W)\n")]),
    ("the fill is never shown again", [
        (M, "    fill:SetWidth(BAR_W * frac)\n    fill:Show()\n", "    fill:SetWidth(BAR_W * frac)\n")]),
    ("no fill while the atlas streams in", [
        (M, "        fill:SetColorTexture(FILL_FALLBACK[1], FILL_FALLBACK[2], FILL_FALLBACK[3])\n", "")]),
    ("the art keeps the fallback tint", [
        (M, "            fill:SetVertexColor(1, 1, 1)\n", "")]),
    ("the atlas file ignored", [
        (M, "            fill:SetTexture(info.file or info.filename)\n", "")]),
    ("a chest still reachable reads gray", [
        (M, "    local c = remain > 0 and WHITE or MISSED\n", "    local c = remain > 1 and WHITE or MISSED\n")]),
    ("a chest with nothing left reads reachable", [
        (M, "    local c = remain > 0 and WHITE or MISSED\n", "    local c = remain >= 0 and WHITE or MISSED\n")]),
    ("time left can go negative", [
        (M, "    local left = math.max(0, limit - elapsed)\n", "    local left = limit - elapsed\n")]),
    ("time's up never turns red", [
        (M, "        f.TimeLeft:SetTextColor(RED[1], RED[2], RED[3])\n", "")]),
    ("the depleted marker stays over time's up", [
        (M, "        f.Depleted:Hide()\n        f.TimesUp:Show()\n", "        f.TimesUp:Show()\n")]),
    ("no time's up marker", [
        (M, "        f.Depleted:Hide()\n        f.TimesUp:Show()\n", "        f.Depleted:Hide()\n")]),
    ("time's up always says no loot", [
        (M, "        f.TimesUp.Line:SetShown(self._depleted and true or false)\n", "        f.TimesUp.Line:SetShown(true)\n")]),
    ("time's up is not hidden again", [
        (M, "        f.TimesUp:Hide()\n        f.Depleted:SetShown", "        f.Depleted:SetShown")]),
    ("every key with time left reads depleted", [
        (M, "        f.Depleted:SetShown(self._depleted and true or false)\n", "        f.Depleted:SetShown(true)\n")]),
    ("the fill follows elapsed, not time left", [
        (M, "    self:_SetFill(left / limit)\n", "    self:_SetFill(elapsed / limit)\n")]),
    ("+3 and +2 labels swapped", [
        (M, '    chest(f.Plus3, "+3", (self._three or 0) - elapsed)\n    chest(f.Plus2, "+2", (self._two or 0) - elapsed)\n',
            '    chest(f.Plus3, "+3", (self._two or 0) - elapsed)\n    chest(f.Plus2, "+2", (self._three or 0) - elapsed)\n')]),
    ("affixes placed from a wrong offset", [
        (M, "    local left = AFFIX_RIGHT + AFFIX_GAP * (n - 1) + AFFIX_SIZE * n\n",
            "    local left = AFFIX_RIGHT + AFFIX_SIZE * n\n")]),
    ("a shrunk affix list leaves the old ones up", [
        (M, "    for i = 1, math.max(n, #pool) do\n", "    for i = 1, n do\n")]),
    ("affix name and description swapped", [
        (M, "            a._name, a._description = info.name, info.description\n",
            "            a._name, a._description = info.description, info.name\n")]),
    ("a reused affix keeps its old description", [
        (M, "            a._name, a._description = info.name, info.description\n",
            "            a._name = info.name\n            a._description = a._description or info.description\n")]),
    ("a reused affix keeps its old icon", [
        (M, "            a.Portrait:SetTexture(info.icon)\n", "")]),
    ("a hidden affix keeps its tooltip", [
        (M, "            a:Hide()\n            a._name, a._description = nil, nil\n", "            a:Hide()\n")]),
    ("the second affix anchored to the block", [
        (M, '                a:SetPoint("LEFT", pool[i - 1], "RIGHT", AFFIX_GAP, 0)\n',
            '                a:SetPoint("LEFT", f, "RIGHT", AFFIX_GAP, 0)\n')]),
    ("the clock holds the provider's table", [
        (M, "    self._limit = key.timeLimit\n", "    self._limit = key.timeLimit\n    self._key = key\n"),
        (M, "    local limit = self._limit\n", "    local limit = self._key and self._key.timeLimit or self._limit\n")]),
    ("the clock starts from the draw, not the reading's stamp", [
        (M, "    self._elapsed, self._at = key.elapsed or 0, key.elapsedAt or GetTime()\n",
            "    self._elapsed, self._at = key.elapsed or 0, GetTime()\n")]),
    ("Left and Right alignment swapped", [
        (M, '    local point = (align == "LEFT" and "TOPLEFT") or (align == "RIGHT" and "TOPRIGHT") or "TOP"\n',
            '    local point = (align == "LEFT" and "TOPRIGHT") or (align == "RIGHT" and "TOPLEFT") or "TOP"\n')]),
    ("anchored above the offset", [
        (M, "    f:SetPoint(point, container, point, 0, -(top or 0))\n", "    f:SetPoint(point, container, point, 0, top or 0)\n")]),
    ("old anchors kept", [
        (M, "    f:ClearAllPoints()\n    f:SetPoint(point", "    f:SetPoint(point")]),
    ("no level fallback", [
        (M, '    local fmt = gs("CHALLENGE_MODE_POWER_LEVEL") or "+%d"\n', '    local fmt = gs("CHALLENGE_MODE_POWER_LEVEL") or "%d"\n')]),
    ("a missing level printed as 0", [
        (M, '    f.Level:SetText(key.level and fmt:format(key.level) or "")\n', "    f.Level:SetText(fmt:format(key.level or 0))\n")]),
    ("the level shows the map id", [
        (M, '    f.Level:SetText(key.level and fmt:format(key.level) or "")\n',
            '    f.Level:SetText(key.level and fmt:format(key.mapID or key.level) or "")\n')]),
    ("deaths shown before they cost time", [
        (M, "    if self._deaths > 0 and self._timeLost > 0 then\n", "    if self._deaths > 0 then\n")]),
    ("the death count text not set", [
        (M, "        f.Death.Count:SetText(tostring(self._deaths))\n", "")]),
    ("the death count never hidden", [
        (M, "    else\n        f.Death:Hide()\n    end\n", "    end\n")]),
    ("the +2 mark never shown", [
        (M, "    f.MarkTwo:SetShown(limit > 0)\n", "    f.MarkTwo:SetShown(false)\n")]),
    ("+3 mark from the wrong end", [
        (M, "            x0 + BAR_W * (1 - (self._three or 0) / limit), BAR_Y)\n",
            "            x0 + BAR_W * ((self._three or 0) / limit), BAR_Y)\n")]),
    ("+2 mark from the wrong end", [
        (M, "            x0 + BAR_W * (1 - (self._two or 0) / limit), BAR_Y)\n",
            "            x0 + BAR_W * ((self._two or 0) / limit), BAR_Y)\n")]),
    ("the +2 mark off the bar", [
        (M, "            x0 + BAR_W * (1 - (self._two or 0) / limit), BAR_Y)\n",
            "            x0 + BAR_W * (1 - (self._two or 0) / limit), 0)\n")]),
    ("marks from the block's edge, not the bar's", [
        (M, "        local x0 = (BLOCK_W - BAR_W) / 2\n", "        local x0 = 0\n")]),
    ("fonts never applied", [
        (M, "    self:_ApplyFonts()\n", "")]),
    ("no first paint", [
        (M, "    self:_Tick(true)\n", "")]),
    ("the clock never started", [
        (M, '    f:SetScript("OnUpdate", onUpdate)\n', "")]),
    ("the block never shown", [
        (M, "    f:SetScript(\"OnUpdate\", onUpdate)\n    f:Show()\n", "    f:SetScript(\"OnUpdate\", onUpdate)\n")]),
    ("the chest line not measured", [
        (M, "    local chestH = math.max(CHEST_MIN_H, f.Plus3:GetStringHeight() or 0)\n", "    local chestH = CHEST_MIN_H\n")]),
    ("the height leaves out the gap", [
        (M, "    self._height = BLOCK_H + CHEST_GAP + chestH\n", "    self._height = BLOCK_H + chestH\n")]),
    ("clearing leaves the clock running", [
        (M, "    f:SetScript(\"OnUpdate\", nil)\n    f:Hide()\n", "    f:Hide()\n")]),
    ("clearing leaves the block up", [
        (M, "    f:SetScript(\"OnUpdate\", nil)\n    f:Hide()\n", "    f:SetScript(\"OnUpdate\", nil)\n")]),
    ("clearing leaves the affixes up", [
        (M, "    for _, a in ipairs(self.affixes) do\n        a:Hide()\n", "    for _, a in ipairs(self.affixes) do\n")]),
    ("clearing keeps the affix tooltips", [
        (M, "        a:Hide()\n        a._name, a._description = nil, nil\n    end\nend\n", "        a:Hide()\n    end\nend\n")]),
    ("clearing keeps the limit, so a late tick repaints", [
        (M, "    self._limit, self._height = nil, nil\n", "")]),
    ("clearing forgets why", [
        (M, "    self._why = why\n", "")]),
    ("the clock in the criteria font", [
        (M, "    Media:ApplyScenarioShadow(f.TimeLeft)\n",
            "    Media:ApplyScenarioShadow(f.TimeLeft)\n    Media:ApplyScenarioCriteriaFont(f.TimeLeft)\n")]),
    ("the death count in the criteria font", [
        (M, "    Media:ApplyScenarioShadow(f.Death.Count)\n",
            "    Media:ApplyScenarioShadow(f.Death.Count)\n    Media:ApplyScenarioCriteriaFont(f.Death.Count)\n")]),
    ("the level in the tracker's own font", [
        (M, "    Media:ApplyScenarioShadow(f.Level)\n", "    Media:ApplyScenarioShadow(f.Level)\n    Media:ApplyFont(f.Level)\n")]),
    ("the level tinted", [
        (M, '    f.Level:SetJustifyH("LEFT")\n', '    f.Level:SetJustifyH("LEFT")\n    f.Level:SetTextColor(1, 1, 1)\n')]),
    ("the block shifted sideways", [
        (M, "    f:SetPoint(point, container, point, 0, -(top or 0))\n", "    f:SetPoint(point, container, point, 8, -(top or 0))\n")]),
    ("the depleted mark touching the level", [
        (M, '    f.Depleted:SetPoint("LEFT", f.Level, "RIGHT", MARK_GAP, 0)\n',
            '    f.Depleted:SetPoint("LEFT", f.Level, "RIGHT", 0, 0)\n')]),
    ("the depleted mark hung from its top left", [
        (M, '    f.Depleted:SetPoint("LEFT", f.Level, "RIGHT", MARK_GAP, 0)\n',
            '    f.Depleted:SetPoint("TOPLEFT", f.Level, "RIGHT", MARK_GAP, 0)\n')]),
    ("the time's up mark lifted", [
        (M, '    f.TimesUp:SetPoint("LEFT", f.TimeLeft, "RIGHT", MARK_GAP, 0)\n',
            '    f.TimesUp:SetPoint("LEFT", f.TimeLeft, "RIGHT", MARK_GAP, 6)\n')]),
    ("the chest off the mark's center", [
        (M, '    m.Chest:SetPoint("CENTER")\n', '    m.Chest:SetPoint("LEFT")\n')]),
    ("the level centered", [
        (M, '    f.Level:SetJustifyH("LEFT")\n', '    f.Level:SetJustifyH("CENTER")\n')]),
    ("the time right-justified", [
        (M, '    f.TimeLeft:SetJustifyH("LEFT")\n', '    f.TimeLeft:SetJustifyH("RIGHT")\n')]),
    ("+3 left-justified", [
        (M, '    f.Plus3:SetJustifyH("RIGHT")\n', '    f.Plus3:SetJustifyH("LEFT")\n')]),
    ("the death count anchored to the container", [
        (M, '    f.Death:SetPoint("TOPLEFT", f, "BOTTOMRIGHT", DEATH_X, DEATH_Y)\n',
            '    f.Death:SetPoint("TOPLEFT", container, "BOTTOMRIGHT", DEATH_X, DEATH_Y)\n')]),
    ("the time indented", [
        (M, '    f.TimeLeft:SetPoint("TOPLEFT", f.Level, "BOTTOMLEFT", 0, -TIME_GAP)\n',
            '    f.TimeLeft:SetPoint("TOPLEFT", f.Level, "BOTTOMLEFT", 6, -TIME_GAP)\n')]),
    ("the time from the level's bottom center", [
        (M, '    f.TimeLeft:SetPoint("TOPLEFT", f.Level, "BOTTOMLEFT", 0, -TIME_GAP)\n',
            '    f.TimeLeft:SetPoint("TOPLEFT", f.Level, "BOTTOM", 0, -TIME_GAP)\n')]),
    ("the level from the block's top center", [
        (M, '    f.Level:SetPoint("TOPLEFT", f, "TOPLEFT", LEVEL_X, LEVEL_Y)\n',
            '    f.Level:SetPoint("TOPLEFT", f, "TOP", LEVEL_X, LEVEL_Y)\n')]),
    ("the level placed from the container", [
        (M, '    f.Level:SetPoint("TOPLEFT", f, "TOPLEFT", LEVEL_X, LEVEL_Y)\n',
            '    f.Level:SetPoint("TOPLEFT", container, "TOPLEFT", LEVEL_X, LEVEL_Y)\n')]),
    ("the +3 mark measured from the block's bottom center", [
        (M, '        f.MarkThree:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT",\n'
            "            x0 + BAR_W * (1 - (self._three or 0) / limit), BAR_Y)\n",
            '        f.MarkThree:SetPoint("BOTTOMLEFT", f, "BOTTOM",\n'
            "            x0 + BAR_W * (1 - (self._three or 0) / limit), BAR_Y)\n")]),
    ("the +3 mark placed from the container", [
        (M, '        f.MarkThree:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT",\n'
            "            x0 + BAR_W * (1 - (self._three or 0) / limit), BAR_Y)\n",
            '        f.MarkThree:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT",\n'
            "            x0 + BAR_W * (1 - (self._three or 0) / limit), BAR_Y)\n")]),
    ("the +2 mark centered on its point", [
        (M, '        f.MarkTwo:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT",\n'
            "            x0 + BAR_W * (1 - (self._two or 0) / limit), BAR_Y)\n",
            '        f.MarkTwo:SetPoint("BOTTOM", f, "BOTTOMLEFT",\n'
            "            x0 + BAR_W * (1 - (self._two or 0) / limit), BAR_Y)\n")]),
    ("the bar back from the block's bottom left", [
        (M, '    f.BarBack:SetPoint("BOTTOM", f, "BOTTOM", 0, BAR_BG_Y)\n',
            '    f.BarBack:SetPoint("BOTTOM", f, "BOTTOMLEFT", 0, BAR_BG_Y)\n')]),
    ("the bar back sideways", [
        (M, '    f.BarBack:SetPoint("BOTTOM", f, "BOTTOM", 0, BAR_BG_Y)\n',
            '    f.BarBack:SetPoint("BOTTOM", f, "BOTTOM", 6, BAR_BG_Y)\n')]),
    ("the bar frame from the container", [
        (M, '    f.BarBG:SetPoint("BOTTOM", f, "BOTTOM", 0, BAR_BG_Y)\n',
            '    f.BarBG:SetPoint("BOTTOM", container, "BOTTOM", 0, BAR_BG_Y)\n')]),
    ("the fill drawn from the container's bottom", [
        (M, '    f.Fill:SetPoint("BOTTOMLEFT", f, "BOTTOM", -BAR_W / 2, BAR_Y)\n',
            '    f.Fill:SetPoint("BOTTOMLEFT", container, "BOTTOM", -BAR_W / 2, BAR_Y)\n')]),
    ("the art stretched over the container", [
        (M, "    f.Art:SetAllPoints()\n", "    f.Art:SetAllPoints(container)\n")]),
    ("the affix icon taller than wide", [
        (M, "    a.Portrait:SetSize(AFFIX_ICON, AFFIX_ICON)\n", "    a.Portrait:SetSize(AFFIX_ICON, AFFIX_SIZE)\n")]),
    ("the affix frame shorter than wide", [
        (M, "    a:SetSize(AFFIX_SIZE, AFFIX_SIZE)\n", "    a:SetSize(AFFIX_SIZE, AFFIX_ICON)\n")]),
    ("the affix ring stretched over the block", [
        (M, "    a.Border:SetAllPoints()\n", "    a.Border:SetAllPoints(parent)\n")]),
    ("the affix ring tinted", [
        (M, "    Util.SafeSetAtlas(a.Border, RING, false)\n",
            "    Util.SafeSetAtlas(a.Border, RING, false)\n    a.Border:SetVertexColor(1, 0, 0)\n")]),
    ("the chest marks red", [
        (M, "        t:SetColorTexture(1, 1, 1, 0.7)\n", "        t:SetColorTexture(1, 0.2, 0.2, 0.7)\n")]),
    ("the death number lifted off the icon line", [
        (M, '    f.Death.Count:SetPoint("LEFT", f.Death.Icon, "RIGHT", 1, 0)\n',
            '    f.Death.Count:SetPoint("LEFT", f.Death.Icon, "RIGHT", 1, 4)\n')]),
    ("the +2 line not under the block", [
        (M, '    f.Plus2:SetPoint("TOPLEFT", f, "BOTTOM", CHEST_SPLIT, -CHEST_GAP)\n',
            '    f.Plus2:SetPoint("TOPLEFT", f, "BOTTOM", CHEST_SPLIT, 0)\n')]),
    ("the +2 line anchored to the container", [
        (M, '    f.Plus2:SetPoint("TOPLEFT", f, "BOTTOM", CHEST_SPLIT, -CHEST_GAP)\n',
            '    f.Plus2:SetPoint("TOPLEFT", container, "BOTTOM", CHEST_SPLIT, -CHEST_GAP)\n')]),
    ("the fallback fill's blue taken from its red", [
        (M, "        fill:SetColorTexture(FILL_FALLBACK[1], FILL_FALLBACK[2], FILL_FALLBACK[3])\n",
            "        fill:SetColorTexture(FILL_FALLBACK[1], FILL_FALLBACK[2], FILL_FALLBACK[1])\n")]),
    ("tooltip titles gold, not white", [
        (M, "    tip:SetText(title, 1, 1, 1, 1, true)\n", "    tip:SetText(title, 1, 0.82, 0, 1, true)\n")]),
    ("time's up magenta", [(M, "local RED   = { 1, 0.1, 0.1 }\n", "local RED   = { 1, 0.1, 1 }\n")]),
    ("a missed chest blue-gray", [(M, "local MISSED = { 0.5, 0.5, 0.5 }\n", "local MISSED = { 0.5, 0.5, 1 }\n")]),
    ("the clock rebased from the floored second on every tick", [
        (M, "    self._shownAt = elapsed\n", "    self._shownAt = elapsed\n    self._at, self._elapsed = GetTime(), elapsed\n")]),

    # ---------------------------------------------------------------------- UI/Scenario.lua
    ("the key block never replaces the banner", [
        (S, "    if key and MP and not off then\n", "    if false then\n")]),
    ("the switch is ignored", [
        (S, "    if key and MP and not off then\n", "    if key and MP then\n")]),
    ("an unset switch reads as off", [
        (S, "    local off = cfg and cfg.showMythicPlusTimer == false\n",
            "    local off = not (cfg and cfg.showMythicPlusTimer)\n")]),
    ("the banner stays up under the block", [
        (S, "        self.banner:Hide()\n        self.headH = MP:Render", "        self.headH = MP:Render")]),
    ("the block drawn on the hidden banner", [
        (S, "        self.headH = MP:Render(container, cfg, key, headTop)\n",
            "        self.headH = MP:Render(self.banner, cfg, key, headTop)\n")]),
    ("the block drawn without the alignment", [
        (S, "        self.headH = MP:Render(container, cfg, key, headTop)\n",
            "        self.headH = MP:Render(container, nil, key, headTop)\n")]),
    ("the banner is not shown again", [
        (S, "        self.banner:Show()\n        self:_DrawBanner(info, cfg)\n", "        self:_DrawBanner(info, cfg)\n")]),
    ("the block is not cleared when switched off", [
        (S, '        if MP then MP:Clear(off and "switched off" or nil) end\n', "")]),
    ("switched off gives no reason", [
        (S, '        if MP then MP:Clear(off and "switched off" or nil) end\n', "        if MP then MP:Clear(nil) end\n")]),
    ("switched off says why only with a key in hand", [
        (S, '        if MP then MP:Clear(off and "switched off" or nil) end\n',
            '        if MP then MP:Clear(key and "switched off" or nil) end\n')]),
    ("the panel keeps the banner's height under the block", [
        (S, "        self.headH = MP:Render(container, cfg, key, headTop)\n",
            "        MP:Render(container, cfg, key, headTop)\n        self.headH = BANNER_H\n")]),
    ("the block sits on the sub-header", [
        (S, "    local headTop = (self.topOffset or 0) + (self.subHeaderH or SUBHEADER_H) + BANNER_GAP\n",
            "    local headTop = (self.topOffset or 0) + (self.subHeaderH or SUBHEADER_H)\n")]),
    ("the widgets start under the banner's height", [
        (S, "    self.widgetH = WB and WB:RenderScenario(container, cfg, headTop + self.headH) or 0\n",
            "    self.widgetH = WB and WB:RenderScenario(container, cfg, headTop + BANNER_H) or 0\n")]),
    ("the panel height counts the banner", [
        (S, "    local h = (self.subHeaderH or SUBHEADER_H) + BANNER_GAP + self.headH + self.widgetH\n",
            "    local h = (self.subHeaderH or SUBHEADER_H) + BANNER_GAP + BANNER_H + self.widgetH\n")]),
    ("the criteria start under the banner's height", [
        (S, "                      + BANNER_GAP + (self.headH or BANNER_H) + (self.widgetH or 0)\n",
            "                      + BANNER_GAP + BANNER_H + (self.widgetH or 0)\n")]),
    ("the spells placed off the panel's height", [
        (S, "    local spellH = SS and SS:Place(container, info, (self.topOffset or 0) + h) or 0\n",
            "    local spellH = SS and SS:Place(container, info, (self.topOffset or 0) + h - self.headH + BANNER_H) or 0\n")]),
    ("a scenario ending leaves the block up", [
        (S, "    if MP then MP:Clear() end\n    self.headH = BANNER_H\n", "    self.headH = BANNER_H\n")]),
    ("a scenario ending keeps the block's height", [
        (S, "    if MP then MP:Clear() end\n    self.headH = BANNER_H\n", "    if MP then MP:Clear() end\n")]),
    ("a scenario ending says the block was switched off", [
        (S, "    if MP then MP:Clear() end\n    self.headH = BANNER_H\n",
            '    if MP then MP:Clear("switched off") end\n    self.headH = BANNER_H\n')]),
    ("the key block also redraws the hidden banner", [
        (S, "        self.banner:Hide()\n        self.headH = MP:Render(container, cfg, key, headTop)\n",
            "        self:_DrawBanner(info, cfg)\n        self.banner:Hide()\n"
            "        self.headH = MP:Render(container, cfg, key, headTop)\n")]),

    # ---------------------------------------------------------------------- UI/Commands.lua
    ("late is not a test", [
        (C, '            elseif arg == "test" or arg == "late" then\n', '            elseif arg == "test" then\n')]),
    ("any word toggles the test", [
        (C, '            elseif arg == "test" or arg == "late" then\n', '            elseif arg ~= "" then\n')]),
    ("the argument's case matters", [
        (C, '            local SC  = ns:GetModule("Registry"):Get("scenarios")\n            local arg = strtrim(rest or ""):lower()\n',
            '            local SC  = ns:GetModule("Registry"):Get("scenarios")\n            local arg = strtrim(rest or "")\n')]),
    ("the test runs under Blizzard's tracker", [
        (C, "            elseif ns:UsesBlizzardTracker() then\n                ns:Print(\"mythic+: off, Blizzard's tracker in use\")\n",
            "            elseif false then\n                ns:Print(\"mythic+: off, Blizzard's tracker in use\")\n")]),
    ("no capability check on the command", [
        (C, "            if not (SC and SC.ToggleKeystoneTest and ns.Has.ChallengeTimer) then\n",
            "            if not (SC and SC.ToggleKeystoneTest) then\n")]),
    ("the clear hint always names test", [
        (C, '                        .. "Type /eqot mplus %s again to clear it."):format(arg, arg)\n',
            '                        .. "Type /eqot mplus %s again to clear it."):format(arg, "test")\n')]),
    ("the box-off note is never said", [
        (C, '                        .. (why == "switched off" and " Show the Mythic+ timer is off, so the "\n',
            '                        .. (false and " Show the Mythic+ timer is off, so the "\n')]),
    ("a provider that is off reads as on", [
        (C, '                if why == "off" then\n                    ns:Print("mythic+: the scenarios provider',
            '                if false then\n                    ns:Print("mythic+: the scenarios provider')]),
    ("a scenario running reads as on", [
        (C, '                elseif why == "scenario" then\n', '                elseif false then\n')]),
    ("off always names test", [
        (C, '                    ns:Print(("mythic+ %s: off."):format(arg))\n', '                    ns:Print("mythic+ test: off.")\n')]),
    ("off is never said", [
        (C, '                    ns:Print(("mythic+ %s: off."):format(arg))\n', "")]),
    ("plain mplus prints the last paint", [
        (C, '                tracker():Render()\n                ns:GetModule("Feed"):Build()\n                debugLine("Keystone")\n',
            '                debugLine("Keystone")\n')]),
    ("plain mplus skips the build a hidden tracker needs", [
        (C, '                ns:GetModule("Feed"):Build()\n                debugLine("Keystone")\n',
            '                debugLine("Keystone")\n')]),
    ("plain mplus builds before it repaints", [
        (C, '                tracker():Render()\n                ns:GetModule("Feed"):Build()\n                debugLine("Keystone")\n',
            '                ns:GetModule("Feed"):Build()\n                tracker():Render()\n                debugLine("Keystone")\n')]),
    ("plain mplus leaves out the block", [
        (C, '                debugLine("Keystone")\n                debugLine("MythicPlus")\n                debugLine("Visibility")\n',
            '                debugLine("Keystone")\n                debugLine("Visibility")\n')]),
    ("plain mplus leaves out the visibility line", [
        (C, '                debugLine("MythicPlus")\n                debugLine("Visibility")\n',
            '                debugLine("MythicPlus")\n')]),
    ("/eqot status leaves out the key read", [
        (C, '    if Registry:Get("scenarios") then\n        debugLine("Keystone")\n',
            '    if Registry:Get("scenarios") then\n')]),
    ("/eqot status leaves out the block", [
        (C, '        debugLine("Keystone")\n        debugLine("MythicPlus")\n    end\n',
            '        debugLine("Keystone")\n    end\n')]),
    ("/eqot status prints them on Classic too", [
        (C, '    if Registry:Get("scenarios") then\n', "    if true then\n")]),
    ("under Blizzard's tracker the key read prints as if live", [
        (C, "                      Keystone = true, MythicPlus = true }\n", "                      MythicPlus = true }\n")]),
    ("under Blizzard's tracker the block prints as if live", [
        (C, "                      Keystone = true, MythicPlus = true }\n", "                      Keystone = true }\n")]),
    ("the usage line leaves it out", [
        (C, '"bonushud [test], mplus [test|late], popup [test], timer [test], importeq',
            '"bonushud [test], popup [test], timer [test], importeq')]),
    ("plain mplus under Blizzard's tracker builds the feed and prints the two module lines", [
        (C, "            elseif ns:UsesBlizzardTracker() then\n                ns:Print(\"mythic+: off, Blizzard's tracker in use\")\n",
            "            elseif ns:UsesBlizzardTracker() and arg ~= \"\" then\n                ns:Print(\"mythic+: off, Blizzard's tracker in use\")\n")]),
    ("the command toggles the test with a dot call", [
        (C, "                local on, why = SC:ToggleKeystoneTest(arg)\n",
            "                local on, why = SC.ToggleKeystoneTest(arg)\n")]),

    # --------------------------------------------------------------- default, box, flag, TOCs
    ("the switch ships off", [
        (D, "            showMythicPlusTimer  = true,\n", "            showMythicPlusTimer  = false,\n")]),
    ("the default set twice", [
        (D, "            showMythicPlusTimer  = true,\n", "            showMythicPlusTimer  = true,\n            showMythicPlusTimer  = false,\n")]),
    ("the default overridden under a second spelling a grep cannot see", [
        (D, "            showMythicPlusTimer  = true,\n",
            '            showMythicPlusTimer  = true,\n            ["showMythicPlusTimer"] = false,\n')]),
    ("the default moved out of the tracker block", [
        (D, "            showMythicPlusTimer  = true,\n", ""),
        (D, "            hideInMythicPlus = false,\n", "            hideInMythicPlus = false,\n            showMythicPlusTimer = true,\n")]),
    ("the box reads unset as off", [
        (T, '                rowSetting("showMythicPlusTimer", true))\n', '                rowSetting("showMythicPlusTimer"))\n')]),
    ("the box built with no provider", [
        (T, '        if ns.Has.ChallengeTimer and ns:GetModule("Registry"):Get("scenarios") then\n',
            "        if ns.Has.ChallengeTimer then\n")]),
    ("the capability never set", [
        (CO, "Has.ChallengeTimer      = method(C_ChallengeMode, \"GetActiveChallengeMapID\")\n",
             "Has.ChallengeTimer      = false and method(C_ChallengeMode, \"GetActiveChallengeMapID\")\n")]),
    ("the capability overridden later", [
        (CO, 'Has.AddOns              = method(C_AddOns, "IsAddOnLoaded")\n',
             'Has.AddOns              = method(C_AddOns, "IsAddOnLoaded")\nHas.ChallengeTimer = nil\n')]),
    ("the capability asks for a read that does not exist", [
        (CO, '                          and global("GetWorldElapsedTimers") and global("GetWorldElapsedTime")\n',
             '                          and global("GetWorldElapsedTimers") and global("GetWorldElapsedTime")\n'
             '                          and global("GetWorldElapsedTimeInfo")\n')]),
    ("the capability inverted on one read", [
        (CO, '                          and method(C_ChallengeMode, "GetMapUIInfo")\n',
             '                          and not method(C_ChallengeMode, "GetMapUIInfo")\n')]),
    ("the capability ignores the keystone read", [
        (CO, '                          and method(C_ChallengeMode, "GetActiveKeystoneInfo")\n', "")]),
    ("the capability ignores the world timer", [
        (CO, '                          and global("GetWorldElapsedTimers") and global("GetWorldElapsedTime")\n',
             '                          and global("GetWorldElapsedTimers")\n')]),
    ("the key read loads after the provider", [
        (TM, "Data" + BS + "QuestLink.lua\nData" + BS + "Keystone.lua\n", "Data" + BS + "QuestLink.lua\n"),
        (TM, "Data" + BS + "Providers" + BS + "Scenarios.lua\n",
             "Data" + BS + "Providers" + BS + "Scenarios.lua\nData" + BS + "Keystone.lua\n")]),
    ("Vanilla leaves out the key read", [
        (TV, "Data" + BS + "QuestLink.lua\nData" + BS + "Keystone.lua\n", "Data" + BS + "QuestLink.lua\n")]),
    ("Vanilla does not load the block", [
        (TV, "UI" + BS + "Scenario.lua\nUI" + BS + "MythicPlus.lua\n", "UI" + BS + "Scenario.lua\n")]),
    ("TBC leaves out the key read", [
        ("EQObjectiveTracker_TBC.toc", "Data" + BS + "QuestLink.lua\nData" + BS + "Keystone.lua\n",
                                       "Data" + BS + "QuestLink.lua\n")]),
    ("TBC does not load the block", [
        ("EQObjectiveTracker_TBC.toc", "UI" + BS + "Scenario.lua\nUI" + BS + "MythicPlus.lua\n", "UI" + BS + "Scenario.lua\n")]),
    ("TBC loads the block before the banner", [
        ("EQObjectiveTracker_TBC.toc", "UI" + BS + "Scenario.lua\nUI" + BS + "MythicPlus.lua\n",
                                       "UI" + BS + "MythicPlus.lua\nUI" + BS + "Scenario.lua\n")]),
    ("Camelot leaves out the key read", [
        ("EQObjectiveTracker_Camelot.toc", "Data" + BS + "QuestLink.lua\nData" + BS + "Keystone.lua\n",
                                           "Data" + BS + "QuestLink.lua\n")]),
    ("Camelot does not load the block", [
        ("EQObjectiveTracker_Camelot.toc", "UI" + BS + "Scenario.lua\nUI" + BS + "MythicPlus.lua\n", "UI" + BS + "Scenario.lua\n")]),
    ("Camelot loads the key read after the provider", [
        ("EQObjectiveTracker_Camelot.toc", "Data" + BS + "QuestLink.lua\nData" + BS + "Keystone.lua\n",
                                           "Data" + BS + "QuestLink.lua\n"),
        ("EQObjectiveTracker_Camelot.toc", "Data" + BS + "Providers" + BS + "Scenarios.lua\n",
                                           "Data" + BS + "Providers" + BS + "Scenarios.lua\nData" + BS + "Keystone.lua\n")]),
    ("the plain TOC leaves out the key read", [
        ("EQObjectiveTracker.toc", "Data" + BS + "QuestLink.lua\nData" + BS + "Keystone.lua\n",
                                   "Data" + BS + "QuestLink.lua\n")]),
    ("the plain TOC does not load the block", [
        ("EQObjectiveTracker.toc", "UI" + BS + "Scenario.lua\nUI" + BS + "MythicPlus.lua\n", "UI" + BS + "Scenario.lua\n")]),
    ("the plain TOC loads the key read after the provider", [
        ("EQObjectiveTracker.toc", "Data" + BS + "QuestLink.lua\nData" + BS + "Keystone.lua\n",
                                   "Data" + BS + "QuestLink.lua\n"),
        ("EQObjectiveTracker.toc", "Data" + BS + "Providers" + BS + "Scenarios.lua\n",
                                   "Data" + BS + "Providers" + BS + "Scenarios.lua\nData" + BS + "Keystone.lua\n")]),
    ("the plain TOC lists the block twice", [
        ("EQObjectiveTracker.toc", "UI" + BS + "Scenario.lua\nUI" + BS + "MythicPlus.lua\n",
                                   "UI" + BS + "Scenario.lua\nUI" + BS + "MythicPlus.lua\nUI" + BS + "MythicPlus.lua\n")]),
]

SUMMARY = re.compile(r"^test_mplus: (\d+) passed, (\d+) failed$")


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    A nonzero exit is NOT evidence that an assertion discriminated - a mutant that does not parse
    exits nonzero too - so the harness's own summary line is matched rather than its exit code,
    and a run that never got that far is its own verdict.
    """
    r = subprocess.run([LUA, HARNESS], capture_output=True, text=True)
    for line in reversed([l for l in r.stdout.splitlines() if l.strip()]):
        m = SUMMARY.match(line.strip())
        if m:
            return ("failed" if int(m.group(2)) else "green"), line.strip()
    err = (r.stderr.strip().splitlines() or r.stdout.strip().splitlines() or ["no output"])
    return "crashed", err[0][:90]


FILES = sorted({f for _, hunks in MUTANTS for f, _, _ in hunks})
original = {f: io.open(f, encoding="utf-8", newline="").read() for f in FILES}


def fit(f, s):
    """Anchors are written with LF, so each is fitted to its own file's line endings."""
    crlf = "\r\n" in original[f]
    s = s.replace("\r\n", "\n")
    return s.replace("\n", "\r\n") if crlf else s


def restore():
    for f, text in original.items():
        io.open(f, "w", encoding="utf-8", newline="").write(text)


verdict, last = run()
print("baseline: %s\n" % last)
if verdict != "green":
    print("BASELINE IS NOT GREEN - stopping")
    sys.exit(1)

failures = []
for name, hunks in MUTANTS:
    edited, broken = {}, False
    for f, old, new in hunks:
        old, new = fit(f, old), fit(f, new)
        cur = edited.get(f, original[f])
        # Asserted rather than assumed: applying a mutant to a file that still holds the last one
        # is a silent no-op, and the run would report the previous mutant's result under this name.
        if cur.count(old) != 1:
            print("SKIPPED (anchor matched %d times in %s): %s" % (cur.count(old), f, name))
            broken = True
            break
        edited[f] = cur.replace(old, new, 1)
    if broken:
        failures.append(("SKIPPED", name))
        continue
    try:
        for f, text in edited.items():
            io.open(f, "w", encoding="utf-8", newline="").write(text)
        verdict, last = run()
    finally:
        restore()
    expected_equivalent = name.startswith("EQUIVALENT:")
    if verdict == "crashed":
        print("CRASHED    %-73s %s" % (name, last))
        failures.append(("CRASHED", name))
    elif verdict == "green" and not expected_equivalent:
        print("SURVIVED   %-73s %s" % (name, last))
        failures.append(("SURVIVED", name))
    elif verdict != "green" and expected_equivalent:
        print("UNEXPECTED %-73s %s" % (name, last))
        failures.append(("UNEXPECTED", name))
    elif expected_equivalent:
        print("equivalent %-73s %s" % (name, last))
    else:
        print("caught     %-73s %s" % (name, last))

for f in FILES:
    if io.open(f, encoding="utf-8", newline="").read() != original[f]:
        print("\nTHE TREE WAS NOT RESTORED - %s still holds a mutant" % f)
        sys.exit(1)
verdict, last = run()
if verdict != "green":
    print("\nBASELINE IS NOT GREEN AFTER THE RUN - %s" % last)
    sys.exit(1)

print("\n%d mutants" % len(MUTANTS))
if failures:
    for kind, label in (
            ("SURVIVED",   "mutant(s) survived - those assertions do not discriminate"),
            ("UNEXPECTED", "EQUIVALENT mutant(s) were caught - the equivalence claim is wrong"),
            ("CRASHED",    "mutant(s) aborted the harness rather than failing it"),
            ("SKIPPED",    "anchor(s) rotted - fix the anchor, never drop the mutant")):
        named = [name for verdict, name in failures if verdict == kind]
        if named:
            print("%d %s:" % (len(named), label))
            for name in named:
                print("  - " + name)
    sys.exit(1)
print("every mutant behaved as expected")
