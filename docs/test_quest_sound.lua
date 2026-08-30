-- luacheck: globals wipe GetTime issecretvalue C_QuestLog GetQuestLogTitle GetNumQuestLogEntries
--
-- Unit tests for the quest sound module, run against the SHIPPED source rather than a copy.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_quest_sound.lua
--
-- Data/QuestSound.lua loads whole here, because it touches no frame. What it needs is a stubbed
-- quest log, a stubbed Events module whose Debounce runs its function straight away, and a Media
-- module that records the file name instead of playing it.
--
-- TWO OF THOSE STUBS USED TO LIE, and a stub that lies is worse than a missing case: it reports
-- a working build broken, or a broken one working, with nothing on screen to say which. Both
-- were measured before they were fixed. Media:Play recorded the "NONE" token as a played sound
-- where production is silent, so the everyday "I picked None" setting could not be expressed at
-- all - the case FAILED against correct production. And Debounce threw the KEY away, so
-- production could be changed to debounce on "eqot.render", the tracker's own repaint key, and
-- this file still read 89 passed, 0 failed while one silently canceled the other.
--
-- THE FLAVOR LOOP RUNS ITS WHOLE BLOCK TWICE, once against each quest log surface, and that is
-- the point of the file. The module used to read C_QuestLog.GetNumQuestLogEntries, GetInfo and
-- IsComplete, none of which exist on Classic, so its scan returned at its first line on every
-- pass there and the sound was left to a chat message that arrives at the quest giver. It
-- shipped that way and no harness could have caught it, because there was no Classic case to
-- fail. There is now.
-- The sections BELOW that loop are single-surface, and the split is deliberate rather than an
-- oversight: each one drops a capability or an API to build a client that is not either shipped
-- surface. Measured, so nobody has to re-count: retail-only 82, classic-only 85. Do not read
-- the loop's promise as covering the whole file.
--
-- The other cases that earn this file:
--
--   1. Blizzard's own complete flag is not the only signal. A quest whose objectives all read
--      finished counts as done even when the flag is silent, which is why the fix works on a
--      client whose own flag never flips.
--   2. The first scan of a session must PRIME rather than fire, and switching the option off
--      re-primes, or a backlog sounds all at once.
--   3. The objectives sound and the turn in sound are separate switches on separate events, and
--      neither may reach for the other's file name.
--   4. DebugLine reports rather than raises. It is read from /eqot status behind a pcall that
--      would swallow the whole line, so a secret quest title is neutralized on the way in.
--   5. ns.Has is a CAPABILITY probe and Core/Compat.lua asks QuestLog, QuestIsComplete and
--      QuestObjectives as three SEPARATE questions, so a client can answer yes to one and no to
--      the next. Each guard has a build that removes the global as well as the flag, so a
--      deleted guard raises instead of quietly finding a stub that should not be there.
--   6. Silence is a setting. "None" heads all three sound pickers and stores the token "NONE".

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local NOW    = 1000
local SECRET = setmetatable({}, { __tostring = function() return "!!secret!!" end })

_G.wipe          = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.GetTime       = function() return NOW end
_G.issecretvalue = function(v) return v == SECRET end

-- Every live debounce key in the tree, read off Core/Events.lua's callers. The bus is keyed and
-- a second arrival on an armed key REPLACES the first function, so two modules sharing one key
-- means whichever fires second silently cancels the other. Listed as literals because a Lua
-- harness cannot grep: if a key is added or renamed, this list moves with it.
local OTHER_DEBOUNCE_KEYS = { "eqot.render", "eqot.scenariobonus", "widgets" }

-- Each build gets its own copy of the module, because every counter in it is a file-local and
-- the two surfaces have to start from the same clean slate to be comparable.
--
-- opts drops one capability at a time. ns.Has is a CAPABILITY probe and Core/Compat.lua asks for
-- each of these separately, so a client can answer yes to one and no to the next - which is the
-- whole reason the guards exist. Each option removes the GLOBAL as well as the flag, so a
-- deleted guard calls a nil value rather than quietly reading a stub that should not be there.
local function build(classic, opts)
    opts = opts or {}
    local qlog, played, handlers, mods = {}, {}, {}, {}
    local taskQuests, debounces = {}, {}

    local function find(id)
        for _, q in ipairs(qlog) do if q.id == id then return q end end
    end

    _G.C_QuestLog = {
        IsWorldQuest = function(id)
            local q = find(id)
            return q and q.worldQuest
        end,
        IsQuestTask = function(id) return taskQuests[id] == true end,
    }
    if not opts.noObjectives then
        _G.C_QuestLog.GetQuestObjectives = function(id)
            local q = find(id)
            return q and q.objs
        end
    end
    -- Present on Classic and under-reports there, so anything that bounded a walk by it would
    -- stop short. Set low on purpose: the Classic walk must ignore it.
    _G.GetNumQuestLogEntries = function() return classic and 2 or #qlog end
    _G.GetQuestLogTitle = nil

    if classic then
        -- 1 title, 4 isHeader, 6 isComplete, 8 questID. Slot 6 is -1 for a failed quest.
        --
        -- An incomplete quest answers NIL on 1.15.9, not 0. Production tests
        -- `isComplete and isComplete ~= 0 and isComplete ~= -1`, and the two spellings reach the
        -- same answer by DIFFERENT halves of it - nil short-circuits at the first `and` while 0
        -- is caught by the second. This stub returned 0 for every incomplete quest, so the
        -- everyday client answer was the one path never run. A quest can still ask for 0 with
        -- zeroComplete, which is what keeps the `~= 0` half exercised.
        _G.GetQuestLogTitle = function(i)
            local q = qlog[i]
            if not q then return nil end
            local complete
            if q.failed then complete = -1
            elseif q.complete then complete = 1
            elseif q.zeroComplete then complete = 0 end
            return q.title, q.level or 1, nil, q.isHeader, nil, complete, 1, q.id
        end
    else
        _G.C_QuestLog.GetNumQuestLogEntries = function() return #qlog end
        _G.C_QuestLog.GetInfo = function(i)
            local q = qlog[i]
            if not q then return nil end
            return { isHeader = q.isHeader, questID = q.id, title = q.title }
        end
        if not opts.noIsComplete then
            _G.C_QuestLog.IsComplete = function(id)
                local q = find(id)
                return q and q.complete
            end
        end
        _G.C_QuestLog.IsFailed = function(id)
            local q = find(id)
            return q and q.failed
        end
    end

    if opts.noQuestLogAtAll then
        _G.C_QuestLog.GetNumQuestLogEntries = nil
        _G.C_QuestLog.GetInfo = nil
        _G.GetQuestLogTitle = nil
    end

    local ns = {
        Has = {
            QuestLog        = not classic and not opts.noQuestLogAtAll,
            QuestIsComplete = not classic and not opts.noIsComplete,
            QuestIsFailed   = not classic,
            QuestObjectives = not opts.noObjectives,
        },
    }
    function ns:RegisterModule(n, t) mods[n] = t return t end
    function ns:GetModule(n) return mods[n] end

    local cfg = {
        questSoundEnabled       = true,
        questCompleteSound      = "EQ: Work Complete",
        questAcceptSoundEnabled = false,
        questAcceptSound        = "EQ: Quest Ding",
        questTurnInSoundEnabled = false,
        questTurnInSound        = "EQ: Raid Warning",
    }
    mods.DB    = { Tracker = function() return cfg end }
    -- Core/Media.lua's Play returns at its first line on nil and on the "NONE" token, which is
    -- what the sound picker STORES when a player chooses None - the first entry in all three
    -- dropdowns. A stub that recorded either as a played sound could not express the everyday
    -- silence those two produce: it reported a correctly silent build as a working one, and
    -- would have reported a mutant routing a sound to None as caught when the player hears
    -- nothing. Measured before this was fixed, the None case failed against correct production.
    mods.Media = { Play = function(_, name)
        if not name or name == "NONE" then return end
        played[#played + 1] = name
    end }
    mods.Events = {
        On = function(_, e, fn) handlers[e] = fn end,
        -- The real one coalesces a burst. Running straight through is what lets a case say
        -- "this quest log update, this many sounds" without a timer in the way.
        --
        -- The KEY is recorded rather than discarded, and that is not bookkeeping. The bus is
        -- keyed and a second arrival on an armed key REPLACES the first function, so a module
        -- reaching for another module's key silently cancels it. Measured: with the key thrown
        -- away, production could be changed to debounce on "eqot.render" - the tracker's own
        -- repaint key - and this file still read 89 passed, 0 failed.
        Debounce = function(_, key, delay, fn)
            debounces[#debounces + 1] = { key = key, delay = delay }
            fn()
        end,
    }

    -- Captured at chunk load, so it has to be gone BEFORE the file is read. issecretvalue is a
    -- Midnight global and this file ships in both Classic TOCs, so the guard around it is doing
    -- real work on exactly the flavor this module was rewritten for.
    local realSecret = _G.issecretvalue
    if opts.noSecretApi then _G.issecretvalue = nil end
    assert(loadfile(repoFile("Data/QuestSound.lua")))("EQObjectiveTracker", ns)
    _G.issecretvalue = realSecret
    local QS = mods.QuestSound
    QS:OnEnable()

    -- events is handed out so a case can swap Debounce for a keyed, coalescing one. The module
    -- calls it as Events:Debounce off an upvalue holding this table, so replacing the field
    -- reaches the already-registered handler.
    local B = { QS = QS, qlog = qlog, played = played, cfg = cfg, handlers = handlers,
                taskQuests = taskQuests, debounces = debounces, events = mods.Events }
    function B.logUpdate() handlers.QUEST_LOG_UPDATE() end
    function B.accept(a, b) handlers.QUEST_ACCEPTED(nil, a, b) end
    function B.turnIn(id)
        if handlers.QUEST_TURNED_IN then handlers.QUEST_TURNED_IN(nil, id) end
    end
    -- DebugLine is called through pcall so a raise FAILS the assertion that wanted the line
    -- rather than aborting the whole file. That is not politeness: an unprotected call here made
    -- the mutation battery report a crashing mutant as "caught", which is a false pass in the one
    -- tool whose job is to find false passes.
    function B.line(name)
        local okCall, text = pcall(QS.DebugLine, QS)
        if not okCall then return "<DebugLine raised: " .. tostring(text) .. ">" end
        for l in (text .. "\n"):gmatch("([^\n]*)\n") do
            if l:find(name, 1, true) then return l end
        end
        return ""
    end
    return B
end

local function has(l, s) return l:find(s, 1, true) ~= nil end

-- A substring assertion matches a whole class of wrong numbers - "2 quests walked" also matches
-- "22 quests walked" - so a counter is PARSED out and compared as an integer.
local function num(l, pat) return tonumber(l:match(pat)) end

-- ------------------------------------------------------------------ both surfaces, same cases

for _, flavor in ipairs({ "retail", "classic" }) do
    local classic = flavor == "classic"
    local function tag(m) return flavor .. ": " .. m end

    local b = build(classic)
    local q = b.qlog

    q[1] = { id = 0, title = "Some Zone", isHeader = true }
    q[2] = { id = 1, title = "Old Quest", complete = true,  objs = { { finished = true } } }
    q[3] = { id = 2, title = "Rats",      complete = false, objs = { { finished = false } } }

    b.logUpdate()
    ok(#b.played == 0, tag("the first scan primes and must not fire, played " .. #b.played))
    ok(has(b.line("armed"), "armed yes"), tag("and reports itself armed afterwards"))
    ok(has(b.line("quests walked"), ", 2 quests walked,"),
       tag("a header is not a quest: " .. b.line("quests walked")))
    ok(has(b.line("log via"), classic and "log via GetQuestLogTitle" or "log via C_QuestLog"),
       tag("the surface it walked is named: " .. b.line("log via")))

    -- stats.done is on the status line and was asserted nowhere, so it could have read anything
    -- - the walked count, a constant, zero - and every case still passed. One of these two
    -- quests is finished, which is what makes it distinguishable from `walked` at all.
    ok(num(b.line("read done"), "(%d+) read done") == 1,
       tag("one of the two quests reads done: " .. b.line("read done")))
    ok(num(b.line("read done"), "(%d+) quests walked") == 2,
       tag("and it is not simply the walked count: " .. b.line("read done")))

    -- The bus is keyed and coalescing, so this is the name that decides whether the scan
    -- cancels somebody else's queued work. See the Debounce stub.
    ok(#b.debounces == 1, tag("one quest log update debounces once, saw " .. #b.debounces))
    ok(b.debounces[1].key == "eqot.questsound",
       tag("under its own key, got " .. tostring(b.debounces[1].key)))
    for _, other in ipairs(OTHER_DEBOUNCE_KEYS) do
        ok(b.debounces[1].key ~= other,
           tag("which is not " .. other .. ", whose owner it would silently cancel"))
    end
    -- The value is deliberately not pinned - the interval itself is not worth a test - but a
    -- delay that went missing would reach C_Timer.After as nil and raise in game, where this
    -- stub runs the function regardless and would never notice.
    ok(type(b.debounces[1].delay) == "number" and b.debounces[1].delay > 0,
       tag("with a real delay, got " .. tostring(b.debounces[1].delay)))

    -- The bug this file exists for. A scan that found no quest log at all used to report
    -- identically to one that read a log with nothing finished in it.
    ok(b.line("log via") ~= "" and not has(b.line("log via"), "log via none"),
       tag("the line exists AND names a real surface: " .. b.line("log via")))

    NOW = NOW + 10
    q[3].complete = true
    q[3].objs[1].finished = true
    b.logUpdate()
    ok(#b.played == 1, tag("the scan fires once on false -> true, played " .. #b.played))
    ok(b.played[1] == "EQ: Work Complete", tag("and plays the objectives sound"))
    ok(num(b.line("scan saw"), "scan saw (%d+)") == 1
       and num(b.line("scan saw"), "played (%d+)") == 1,
       tag("the counters record it: " .. b.line("scan saw")))
    ok(num(b.line("read done"), "(%d+) read done") == 2,
       tag("and the done count moves with the log: " .. b.line("read done")))

    b.logUpdate()
    ok(#b.played == 1, tag("a repeat scan with nothing changed is silent"))

    -- Mid-session, so the priming flag is no help. What keeps it quiet is lastComplete[id]
    -- reading nil rather than false: "already finished when we first looked" is not a
    -- transition.
    q[#q + 1] = { id = 9, title = "Instantly Done", complete = true, objs = {} }
    b.logUpdate()
    ok(#b.played == 1, tag("a quest that arrives already complete is not a transition"))

    -- ------------------------------------------------- the objectives beating Blizzard's flag

    NOW = NOW + 10
    local stubborn = { id = 3, title = "Stubborn Flag", complete = false,
                       objs = { { finished = false }, { finished = false } } }
    q[#q + 1] = stubborn
    b.logUpdate()
    ok(#b.played == 1, tag("an unfinished quest does not fire"))

    stubborn.objs[1].finished = true
    b.logUpdate()
    ok(#b.played == 1, tag("nor does one with only some objectives finished"))

    stubborn.objs[2].finished = true
    b.logUpdate()
    ok(#b.played == 2, tag("all objectives finished fires even while Blizzard's flag says no"))
    ok(has(b.line("read done"), "(1 of them from the objectives)"),
       tag("and the status says the flag was not what answered: " .. b.line("read done")))
    ok(has(b.line("not by Blizzard's flag"), '"Stubborn Flag" (3)'),
       tag("the walk names it: " .. b.line("not by Blizzard's flag")))

    -- A quest with no objectives at all cannot be all-objectives-done. One whose objectives have
    -- not streamed in is indistinguishable from one that never had any, and Blizzard empties a
    -- list it had already answered, so an emptied list is not a finished one.
    -- Recorded unfinished FIRST, or the quest is new to the table and could not fire regardless.
    local before = #b.played
    local streaming = { id = 5, title = "Not Streamed In", complete = false,
                        objs = { { finished = false } } }
    q[#q + 1] = streaming
    b.logUpdate()
    ok(#b.played == before, tag("an unfinished quest with objectives does not fire"))
    streaming.objs = {}
    b.logUpdate()
    ok(#b.played == before, tag("and its list going empty is not it finishing"))

    -- A FAILED quest reads not complete on both surfaces, and the derived answer then asked
    -- objectivesDone anyway - which says true for a failed escort whose objectives all read
    -- finished. That is the ONE state where the flag and the derived answer disagree, and the
    -- case below this one never builds it: it leaves its objectives unfinished, so the guard
    -- could be deleted with the whole file still green.
    local doomed = { id = 21, title = "Doomed Escort", complete = false,
                     objs = { { finished = false } } }
    q[#q + 1] = doomed
    b.logUpdate()
    doomed.failed = true
    doomed.objs[1].finished = true
    b.logUpdate()
    ok(#b.played == before,
       tag("a failed quest whose objectives all read finished is refused the derived answer"))
    ok(num(b.line("read failed"), "(%d+) read failed") == 1,
       tag("and the refusal is named rather than silent: " .. b.line("read failed")))

    if classic then
        local escort = { id = 6, title = "Failed Escort", complete = false,
                         objs = { { finished = false } } }
        q[#q + 1] = escort
        b.logUpdate()
        escort.failed = true
        b.logUpdate()
        ok(#b.played == before, tag("a failed quest reads -1 in slot 6 and is not complete"))

        -- The everyday incomplete answer on 1.15.9 is NIL, which every case above now uses.
        -- The `isComplete ~= 0` half of the guard is defensive rather than measured, so it needs
        -- a quest that actually answers 0 or nothing exercises it and it could be deleted with
        -- the file still green.
        --
        -- It has to be recorded incomplete FIRST and only then answer 0. A quest whose very
        -- first sighting reads 0 is nil in lastComplete either way, so it cannot be a
        -- transition and the case would pass with the guard deleted - an assertion that cannot
        -- fail, which is the trap this project keeps paying for.
        local zero = { id = 12, title = "Reads Zero", objs = { { finished = false } } }
        q[#q + 1] = zero
        b.logUpdate()
        zero.zeroComplete = true
        b.logUpdate()
        ok(#b.played == before, tag("a quest whose slot 6 reads 0 is not complete either"))
        zero.zeroComplete, zero.complete = nil, true
        zero.objs[1].finished = true
        b.logUpdate()
        ok(#b.played == before + 1, tag("and it still fires when it genuinely finishes"))
    end

    -- ------------------------------------------------------------------ the option going off

    -- Recorded as unfinished while the option is still ON, or there is no stored false to
    -- transition away from and the re-prime has nothing to prove.
    before = #b.played
    q[2].complete = false
    q[2].objs[1].finished = false
    b.logUpdate()
    b.cfg.questSoundEnabled = false
    q[2].complete = true
    b.logUpdate()
    ok(#b.played == before, tag("nothing sounds while the option is off"))

    b.cfg.questSoundEnabled = true
    b.logUpdate()
    ok(#b.played == before, tag("the pass that re-primes must not fire the backlog it found"))
    q[2].complete = false
    b.logUpdate()
    q[2].complete = true
    b.logUpdate()
    ok(#b.played == before + 1, tag("a real transition after the re-prime still fires"))

    -- ------------------------------------------------------------------ the turn in

    before = #b.played
    b.turnIn(2)
    ok(#b.played == before, tag("the turn in sound stays silent while its own switch is off"))
    ok(has(b.line("recent:"), 'turnin/switched off "2"'),
       tag("and says so: " .. b.line("recent:")))

    NOW = NOW + 10
    b.cfg.questTurnInSoundEnabled = true
    b.turnIn(2)
    ok(#b.played == before + 1, tag("it plays once switched on"))
    ok(b.played[#b.played] == "EQ: Raid Warning",
       tag("its own sound, never the objectives one"))

    b.turnIn(2)
    ok(#b.played == before + 1, tag("a doubled hand in event does not double the sound"))
    ok(num(b.line("turn ins seen"), "turn ins seen (%d+)") == 3,
       tag("every hand in is counted, switched off and deduped alike: "
           .. b.line("turn ins seen")))

    -- The same two gates the accept path spends. A world quest or a bonus objective hands
    -- itself in where it completes, with no quest giver in it, and this option's wording
    -- promises the hand in - so without these one chimes in a field, and twice over while the
    -- objectives sound is on, which it is by default.
    NOW = NOW + 10
    local at = #b.played
    q[#q + 1] = { id = 401, title = "Field WQ", complete = false, objs = {}, worldQuest = true }
    b.turnIn(401)
    ok(#b.played == at, tag("a world quest handing itself in does not chime"))
    ok(has(b.line("recent:"), "turnin/skipped, world quest"),
       tag("and says which gate took it: " .. b.line("recent:")))

    q[#q + 1] = { id = 402, title = "Field Bonus", complete = false, objs = {} }
    b.taskQuests[402] = true
    b.turnIn(402)
    ok(#b.played == at, tag("nor does a bonus objective"))
    ok(has(b.line("recent:"), "turnin/skipped, task quest"),
       tag("and the task gate is named, not the world quest one"))

    b.turnIn(403)
    ok(#b.played == at + 1, tag("an ordinary hand in still plays"))

    -- ------------------------------------------------------------------ the accept path

    before = #b.played
    b.accept(18, 126)
    ok(#b.played == before, tag("the accept sound stays silent while its own switch is off"))
    ok(has(b.line("last accept payload"), "(18,126) -> id 126"),
       tag("the id is read off the LAST slot even when the sound is off: "
           .. b.line("last accept payload")))

    b.cfg.questAcceptSoundEnabled = true
    q[#q + 1] = { id = 7, title = "A World Quest", complete = false, objs = {}, worldQuest = true }
    b.accept(nil, 7)
    ok(#b.played == before, tag("walking into a world quest accepts one and must not sound"))
    ok(has(b.line("last accept payload"), "skipped, world quest"),
       tag("and says which gate took it"))

    -- The twin of the world quest gate above. Its sibling was covered and this one was not,
    -- while the source comment says both are asked because neither implies the other.
    q[#q + 1] = { id = 11, title = "A Bonus Objective", complete = false, objs = {} }
    b.taskQuests[11] = true
    b.accept(nil, 11)
    ok(#b.played == before, tag("a task quest accepts itself and must not sound"))
    ok(has(b.line("last accept payload"), "skipped, task quest"),
       tag("and the task gate is named, not the world quest one"))

    NOW = NOW + 10
    b.accept(18, 126)
    ok(#b.played == before + 1, tag("an ordinary accept plays"))
    ok(b.played[#b.played] == "EQ: Quest Ding", tag("the accept sound, not the other two"))

    -- An auto-completing quest passes through accept and hand in inside one dedup window, and
    -- both are keyed on the quest id.
    b.turnIn(126)
    ok(#b.played == before + 2, tag("the hand in is not swallowed by the accept it followed"))

    -- ------------------------------------------------------------------ housekeeping

    ok(b.handlers.CHAT_MSG_SYSTEM == nil,
       tag("no system message hook: the chat line fired at the quest giver, not the objective"))
    ok(b.handlers.QUEST_TURNED_IN ~= nil, tag("the hand in is listened for"))

    NOW = NOW + 60
    q[#q + 1] = { id = 8, title = SECRET, complete = false, objs = { { finished = false } } }
    b.logUpdate()
    q[#q].complete = true
    ok(pcall(b.logUpdate), tag("a secret quest title does not take the scan down"))
    ok(pcall(b.QS.DebugLine, b.QS), tag("nor the status line that reports it"))
    ok(has(b.line("recent:"), "<secret>"),
       tag("and it is neutralized rather than handed to string.format"))

    local n = 1
    for _ in b.line("recent:"):gmatch(" | ") do n = n + 1 end
    ok(n == 6, tag("the recent list is bounded at six, counted " .. n))

    -- LAST in the block, and it has to be: build() installs the stubbed quest log globals, so a
    -- second build inside this scope leaves the first one reading the second one's empty log.
    -- The option simply being off must not read like the defect above, or the next person to
    -- open a status line goes hunting a bug that is a ticked box.
    local offB = build(classic)
    offB.cfg.questSoundEnabled = false
    offB.logUpdate()
    ok(has(offB.line("log via"), "log via no scan yet"),
       tag("switched off reads as not scanned, never as no quest log: " .. offB.line("log via")))
end

-- ------------------------------------------------------------------ the absent setting

-- questSoundEnabled reads `~= false`, so an ABSENT key means ON. That is the everyday state on a
-- fresh profile and after DB:ResetAll, which clears these keys to nil rather than to a value -
-- and every case above sets the key explicitly, so the default mechanism itself was never run.
local ab = build(false)
ab.cfg.questSoundEnabled = nil
ab.qlog[1] = { id = 1, title = "Rats", complete = false, objs = { { finished = false } } }
ab.logUpdate()
ab.qlog[1].complete = true
ab.qlog[1].objs[1].finished = true
ab.logUpdate()
ok(#ab.played == 1, "an absent questSoundEnabled means ON, played " .. #ab.played)

-- ------------------------------------------------------------------ the transient empty log

-- A cold login can present an EMPTY quest log, which this project has recorded as a real state
-- rather than a hypothetical. A quest recorded unfinished, one pass that reads nothing, then the
-- same quest back and complete, must stay SILENT: it did not finish while we were not looking,
-- we simply could not see it for a moment.
--
-- What holds that line is the prune of quests the walk no longer visits. Without it the stale
-- `false` survives the empty pass and the next sighting reads as a false -> true transition.
-- That prune was argued to be a pure memory bound and marked EQUIVALENT in the mutation battery
-- on that reasoning; the reasoning was wrong, and this case is what says so.
local tb = build(false)
tb.qlog[1] = { id = 5, title = "Rats", complete = false, objs = { { finished = false } } }
tb.logUpdate()
tb.qlog[1] = nil
tb.logUpdate()
tb.qlog[1] = { id = 5, title = "Rats", complete = true, objs = { { finished = true } } }
tb.logUpdate()
ok(#tb.played == 0,
   "a quest that vanishes for one pass and returns complete is not a transition, played "
   .. #tb.played)

-- ------------------------------------------------------ the None token, and an unset name

-- "None" heads all three sound dropdowns and the value it STORES is the bare token "NONE"
-- (Core/Media.lua's GetSoundList), which Play returns at its first line on. So choosing None is
-- silence, and that is an everyday setting rather than an edge.
--
-- This case could not be written at all until the Media stub above stopped recording the token
-- as a played sound: measured against correct production it read "played 1" and FAILED, which
-- is a false pass in its strongest form - the harness calling a working build broken. It is
-- also what makes the identity of a sound testable at the silent end, so a mutant that
-- hardcodes a name instead of reading the player's pick has somewhere to be caught.
--
-- An unset name is the sibling, and it is what playFile's own comment promises: three paths
-- share that helper, so a fallback there would mean "if the turn in sound is unset, play the
-- objectives one".
local SILENT = { { label = "the None token", value = "NONE" },
                 { label = "an unset name" } }
for _, s in ipairs(SILENT) do
    local b = build(false)
    b.cfg.questAcceptSoundEnabled = true
    b.cfg.questTurnInSoundEnabled = true
    b.cfg.questCompleteSound = s.value
    b.cfg.questAcceptSound   = s.value
    b.cfg.questTurnInSound   = s.value
    b.qlog[1] = { id = 1, title = "Rats", complete = false, objs = { { finished = false } } }
    b.logUpdate()
    b.qlog[1].complete = true
    b.qlog[1].objs[1].finished = true
    b.logUpdate()
    ok(#b.played == 0,
       s.label .. " on the objectives sound is silence, played " .. #b.played)
    b.accept(nil, 40)
    ok(#b.played == 0, s.label .. " on the accept sound is silence too, played " .. #b.played)
    b.turnIn(41)
    ok(#b.played == 0, s.label .. " on the hand in sound is silence too, played " .. #b.played)

    -- The scan still RAN and the status line still says so. Someone whose sound reads None and
    -- whose status reads "played 1" is looking at a ticked box, not a bug, and that line is
    -- what they will paste.
    ok(num(b.line("scan saw"), "scan saw (%d+)") == 1
       and num(b.line("scan saw"), "played (%d+)") == 1,
       s.label .. ": the scan still counts itself: " .. b.line("scan saw"))
end

-- ------------------------------------------------------------------ the capability guards

-- ns.Has is a CAPABILITY probe, and Core/Compat.lua asks for QuestLog, QuestIsComplete and
-- QuestObjectives as three SEPARATE questions, so a client can answer yes to one and no to the
-- next. Each guard in this module stands between a missing API and a call on a nil value, and
-- deleting one is silent on every flavor that happens to have the API - which is the shape of
-- the defect this whole file was written for. Each build below removes the GLOBAL as well as
-- the flag, so a deleted guard raises rather than quietly finding a stub that should not exist.

local noObj = build(false, { noObjectives = true })
noObj.qlog[1] = { id = 1, title = "Flag Quest", complete = false,
                  objs = { { finished = false } } }
noObj.qlog[2] = { id = 2, title = "Objectives Only", complete = false,
                  objs = { { finished = false } } }
ok(pcall(noObj.logUpdate), "a client with no GetQuestObjectives primes without raising")
noObj.qlog[1].complete = true
ok(pcall(noObj.logUpdate), "and walks without raising")
ok(#noObj.played == 1, "Blizzard's own flag still fires there, played " .. #noObj.played)
noObj.qlog[2].objs[1].finished = true
ok(pcall(noObj.logUpdate), "an all-objectives-done quest does not raise on that client")
ok(#noObj.played == 1, "nor fires, because nothing there can read an objective")
ok(pcall(noObj.QS.DebugLine, noObj.QS), "and the status line reports rather than raising")

-- The pairing Core/Compat.lua allows and nothing else here builds: the retail quest log walk is
-- present while the complete flag is not, so every answer has to come from the objectives.
local noFlag = build(false, { noIsComplete = true })
noFlag.qlog[1] = { id = 1, title = "Derived Only", complete = false,
                   objs = { { finished = false } } }
ok(pcall(noFlag.logUpdate), "a client with no IsComplete primes without raising")
ok(has(noFlag.line("IsComplete api"), "IsComplete api false"),
   "and says the flag is unavailable: " .. noFlag.line("IsComplete api"))
noFlag.qlog[1].objs[1].finished = true
ok(pcall(noFlag.logUpdate), "and derives the answer from the objectives without raising")
ok(#noFlag.played == 1, "which is enough to fire on its own, played " .. #noFlag.played)
ok(num(noFlag.line("read done"), "%((%d+) of them from the objectives%)") == 1,
   "and the status names what answered: " .. noFlag.line("read done"))

-- Neither surface. Not hypothetical - it is what the shipped Classic defect looked like from
-- the inside, and the module has to report it rather than raise or read as an empty log.
local noLog = build(false, { noQuestLogAtAll = true })
noLog.qlog[1] = { id = 1, title = "Unreachable", complete = true, objs = { { finished = true } } }
ok(pcall(noLog.logUpdate), "a client with no quest log api at all does not raise")
ok(#noLog.played == 0, "and plays nothing, played " .. #noLog.played)
ok(has(noLog.line("log via"), "log via none, no quest log api"),
   "and names the reason: " .. noLog.line("log via"))
ok(has(noLog.line("armed"), "armed no"),
   "and never arms, so a log that arrives later primes rather than firing: "
   .. noLog.line("armed"))

-- --------------------------------------------------- what the debounce key actually buys

-- The per-flavor block above names the key. This says what naming it wrongly would COST, using
-- a bus built to Core/Events.lua's own rule: a second arrival on an ARMED key replaces the
-- first function and returns false, so exactly one of the two ever runs.
local function newBus()
    local bus = { armed = {}, fns = {} }
    function bus:Debounce(key, _, fn)
        if self.armed[key] then self.fns[key] = fn return false end
        self.armed[key], self.fns[key] = true, fn
        return true
    end
    -- Keys are snapshotted first, because a function this flush runs may arm another one.
    function bus:flush()
        local keys = {}
        for key in pairs(self.fns) do keys[#keys + 1] = key end
        for _, key in ipairs(keys) do
            local fn = self.fns[key]
            self.armed[key], self.fns[key] = nil, nil
            if fn then fn() end
        end
    end
    return bus
end

local function keyedRun(repaintFirst)
    local bus = newBus()
    local b = build(false)
    b.events.Debounce = function(_, key, delay, fn) return bus:Debounce(key, delay, fn) end
    b.qlog[1] = { id = 1, title = "Rats", complete = false, objs = { { finished = false } } }
    b.logUpdate()
    bus:flush()
    b.qlog[1].complete = true
    b.qlog[1].objs[1].finished = true

    local repaints = 0
    local function repaint() repaints = repaints + 1 end
    if repaintFirst then
        bus:Debounce("eqot.render", 0.25, repaint)
        b.logUpdate()
    else
        b.logUpdate()
        bus:Debounce("eqot.render", 0.25, repaint)
    end
    bus:flush()
    return repaints, #b.played
end

local repaints, sounds = keyedRun(true)
ok(repaints == 1, "a repaint queued BEFORE the scan still runs, repaints " .. repaints)
ok(sounds == 1, "and the scan runs too, sounds " .. sounds)
repaints, sounds = keyedRun(false)
ok(repaints == 1, "a repaint queued AFTER the scan still runs, repaints " .. repaints)
ok(sounds == 1, "and the scan is not the one canceled, sounds " .. sounds)

-- ------------------------------------------------- a client with no issecretvalue

-- Every Classic flavor. The module ships in both Classic TOCs and the probe is a Midnight
-- global, so `_issecret and` is the whole reason the walk does not raise there.
local ns2 = build(true, { noSecretApi = true })
ns2.qlog[1] = { id = 1, title = "Rats", complete = false, objs = { { finished = false } } }
ok(pcall(ns2.logUpdate), "a client with no issecretvalue scans without raising")
ns2.qlog[1].complete = true
ns2.qlog[1].objs[1].finished = true
ok(pcall(ns2.logUpdate), "and fires without raising")
ok(#ns2.played == 1, "and the sound still plays, played " .. #ns2.played)
ok(pcall(ns2.QS.DebugLine, ns2.QS), "and the status line reports rather than raising")

-- ------------------------------------------------------------------ the surfaces agree

-- Not a formality. The whole defect was one surface answering and the other silently not, so the
-- two are made to run the same script and hand back the same sounds.
local function script(classic)
    local b = build(classic)
    b.qlog[1] = { id = 1, title = "A Baying of Gnolls", complete = false,
                  objs = { { finished = false }, { finished = false } } }
    b.logUpdate()
    b.qlog[1].objs[1].finished = true
    b.logUpdate()
    b.qlog[1].objs[2].finished = true
    b.logUpdate()
    b.turnIn(1)
    return table.concat(b.played, ",")
end
ok(script(false) == script(true),
   "both surfaces produce the same sounds for the same run: retail "
   .. script(false) .. " vs classic " .. script(true))
ok(script(true) == "EQ: Work Complete",
   "and the sound lands on the last objective, not at the quest giver: " .. script(true))

print(string.format("test_quest_sound: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
