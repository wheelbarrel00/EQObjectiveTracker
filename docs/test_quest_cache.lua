-- luacheck: globals GetTime wipe issecretvalue
--
-- Unit tests for Data/QuestCache.lua, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_quest_cache.lua
--
-- Data/QuestCache.lua loads WHOLE here. It creates no frame and calls no quest API - GetTime,
-- wipe and one Events subscription are its entire surface - so a table with RegisterModule and
-- GetModule on it is a complete stand-in.
--
-- THE TWO CASES THAT EARN THIS FILE, because both are hangs rather than wrong answers and
-- neither shows up as a failure anywhere else:
--   * A decrease OUTSIDE the window has to be ACCEPTED and has to advance the baseline. Refuse
--     it and the baseline stays pinned at the old value, every read after it regresses against
--     it, and a player who banked a quest item is refused for as long as it stays banked.
--   * The window has to LAPSE. Everything this gates - the first-seen stamps, the NEW tag
--     baseline, the tracked-set prune, the objectives chime - has to keep working on a client
--     that never confirms, or the gate is worse than the guesswork it replaced.
--
-- THE LAST BLOCK IS GREPS RATHER THAN ASSERTIONS, and it is not optional. Everything above it
-- drives the module directly, so all of it passes with the module wired to nothing at all: the
-- Note calls, the Begin/Finish pair, the three gates and the quest sound hold live in four
-- other files and only a grep can see them from here.
--
-- OUT OF SCOPE BY CONSTRUCTION: whether the client really does hand back a leading space, and
-- whether one skipped QUEST_LOG_UPDATE is the right count at a cold login. Both are claims
-- about Blizzard, neither is measured on this client, and the window bounds a wrong answer to
-- a few seconds either way.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local function eq(got, want, msg)
    ok(got == want, ("%s (got %s, wanted %s)"):format(msg, tostring(got), tostring(want)))
end

local now = 1000
GetTime = function() return now end
wipe    = function(t) for k in pairs(t) do t[k] = nil end return t end

local SECRET = "a secret value reports type string"

-- The literals below are written out rather than read back off the module, because an
-- assertion that takes its expected value from the constant under test passes at every value of
-- it. The source is grepped for each one instead, so changing one fails by name here.
local SETTLE_MAX_S = 10
local LOGIN_SKIP   = 1
local RELOAD_SKIP  = 0

local SRC = repoFile("Data/QuestCache.lua")

-- A fresh module per block. Every piece of state in that file is a file-local, so loading it
-- again is the only honest way to get a clean one - and it is also how the two _issecret
-- states are reached, since that upvalue is bound at load.
local function fresh(opts)
    opts = opts or {}
    now = 1000
    -- The strict stub RAISES on nil rather than answering false. Whether the real call tolerates
    -- one is unmeasured, and an objective with no numFulfilled hands it a nil on every walk, so
    -- the harness models the direction that costs a render rather than the forgiving one.
    issecretvalue = opts.secret and function(v)
        if v == nil and opts.secret == "strict" then error("issecretvalue got a nil", 0) end
        return v == SECRET
    end or nil

    local QC
    local handlers = {}
    local ns = {
        RegisterModule = function(_, _, t) QC = t return t end,
        GetModule = function(_, name)
            if name ~= "Events" then return nil end
            return { On = function(_, ev, fn)
                handlers[ev] = handlers[ev] or {}
                handlers[ev][#handlers[ev] + 1] = fn
            end }
        end,
    }
    assert(loadfile(SRC))("QuestCache", ns)
    assert(QC, "Data/QuestCache.lua never registered its module")

    local drive = {}

    function drive.enable()
        local okCall, err = pcall(QC.OnEnable, QC)
        ok(okCall, "OnEnable does not raise" .. (okCall and "" or (" - " .. tostring(err))))
    end

    function drive.fire(ev, ...)
        local list = handlers[ev]
        ok(list and #list > 0, "a handler is registered for " .. ev)
        for i = 1, (list and #list or 0) do
            local okCall, err = pcall(list[i], ev, ...)
            ok(okCall, ev .. " handler does not raise" .. (okCall and "" or (" - " .. tostring(err))))
        end
    end

    function drive.login()   drive.fire("PLAYER_ENTERING_WORLD", true, false)  end
    function drive.reload()  drive.fire("PLAYER_ENTERING_WORLD", false, true)  end
    function drive.zone()    drive.fire("PLAYER_ENTERING_WORLD", false, false) end
    function drive.logUpdate(n)
        for _ = 1, (n or 1) do drive.fire("QUEST_LOG_UPDATE") end
    end

    return QC, drive
end

local function obj(text, fulfilled)
    return { text = text, numFulfilled = fulfilled or 0, numRequired = 5 }
end

-- Returns the boolean Finish handed back, or the string "RAISED". Never nil: a helper that
-- substitutes nil here would make every `not ready` assertion pass on a crash.
local function walk(QC, quests)
    local okCall, res = pcall(function()
        QC:Begin()
        for i = 1, #quests do
            local q = quests[i]
            QC:Note(q.id, q.objs, q.done)
        end
        return QC:Finish()
    end)
    if not okCall then
        ok(false, "walk does not raise - " .. tostring(res))
        return "RAISED"
    end
    pass = pass + 1
    return res
end

local function line(QC)
    local okCall, res = pcall(QC.DebugLine, QC)
    ok(okCall, "DebugLine does not raise" .. (okCall and "" or (" - " .. tostring(res))))
    return okCall and res or ""
end

local function says(QC, needle, msg)
    local text = line(QC)
    ok(text:find(needle, 1, true) ~= nil, ("%s - line read %q"):format(msg, text))
end

local function ready(QC)
    local okCall, res = pcall(QC.IsReady, QC)
    if not okCall then
        ok(false, "IsReady does not raise - " .. tostring(res))
        return "RAISED"
    end
    pass = pass + 1
    return res
end

-- One streamed quest, five fulfilled, incomplete. The everyday healthy read.
local function healthy(id, fulfilled, done)
    return { { id = id or 1, objs = { obj("Kill 5 boars", fulfilled or 5) }, done = done } }
end

-- ------------------------------------------------------------------- no opinion until armed

do
    local QC = fresh()
    eq(ready(QC), true, "an unarmed module answers ready")
    -- The whole safe-mode floor: with the module disabled its OnEnable never runs, so it never
    -- sees a world event, so every consumer must behave exactly as it did before it existed.
    eq(walk(QC, { { id = 1, objs = { obj(" not streamed yet", 0) } } }), true,
       "an unarmed module answers ready even through a walk it would otherwise refuse")
    eq(ready(QC), true, "an unarmed module stays ready after a dirty walk")
    says(QC, "no opinion", "DebugLine names the unarmed state")
end

-- --------------------------------------------------------------------------- the login skip

do
    local QC, d = fresh()
    d.enable()
    d.login()
    eq(ready(QC), false, "a cold login is not ready before anything has confirmed")

    d.logUpdate(LOGIN_SKIP)
    eq(walk(QC, healthy()), false,
       "a clean walk on the skipped QUEST_LOG_UPDATE of a cold login does NOT confirm")
    eq(ready(QC), false, "still not ready after the skipped update")

    d.logUpdate(1)
    eq(walk(QC, healthy()), true, "a clean walk on the next update confirms")
    says(QC, "confirmed by a clean walk", "DebugLine names the confirmation")
end

do
    local QC, d = fresh()
    d.enable()
    d.reload()
    eq(ready(QC), false, "a reload is not ready before anything has confirmed")
    -- RELOAD_SKIP is 0, so the very first update is enough. Written as the literal rather than
    -- derived, so raising the reload skip fails here rather than silently widening the gate.
    d.logUpdate(RELOAD_SKIP + 1)
    eq(walk(QC, healthy()), true, "a reload confirms on its first QUEST_LOG_UPDATE")
    says(QC, "confirmed by a clean walk", "DebugLine names the confirmation after a reload")
end

do
    local QC, d = fresh()
    d.enable()
    d.reload()
    eq(walk(QC, healthy()), false,
       "a walk before ANY QUEST_LOG_UPDATE cannot confirm, even on a reload")
end

-- --------------------------------------------------- the log is still streaming (byte 32)

local function armedAndPast()
    local QC, d = fresh()
    d.enable()
    d.reload()
    d.logUpdate(1)
    return QC, d
end

do
    local QC = armedAndPast()
    eq(walk(QC, { { id = 1, objs = { obj(" Kill 5 boars", 0) } } }), false,
       "an objective whose text starts with a space refuses the walk")
    says(QC, "1 streaming", "DebugLine counts the refusal")
    eq(walk(QC, healthy()), true, "the walk after it, with the text arrived, confirms")
end

do
    local QC = armedAndPast()
    eq(walk(QC, { { id = 1, objs = { obj("", 0) } } }), false, "an empty objective text refuses")
end

do
    local QC = armedAndPast()
    eq(walk(QC, { { id = 1, objs = { { numFulfilled = 0, numRequired = 5 } } } }), false,
       "an objective with no text at all refuses")
end

do
    local QC = armedAndPast()
    -- One bad objective among good ones still refuses the whole walk, and one bad quest among
    -- good quests does too. A per-quest verdict would let a half-streamed log confirm.
    eq(walk(QC, { { id = 1, objs = { obj("Kill 5 boars", 1), obj(" Loot 3 hides", 0) } } }), false,
       "one unstreamed objective among streamed ones refuses")
    eq(walk(QC, { healthy(1)[1], { id = 2, objs = { obj(" streaming", 0) } } }), false,
       "one unstreamed quest among streamed ones refuses")
end

do
    local QC = armedAndPast()
    eq(walk(QC, { { id = 1, objs = {} } }), true,
       "a quest with no objectives at all is not a refusal")
end

do
    local QC = armedAndPast()
    eq(walk(QC, {}), false, "a walk that saw no quests at all does not confirm")
    -- An empty log and a log that has not arrived are the same reading, which is exactly why
    -- the emptiness test the providers already had could never be the whole answer.
    says(QC, "NOT READY", "an empty walk leaves the gate closed")
end

-- --------------------------------------------------------------- regressions in the window

-- Confirms once, then opens a fresh window with a zone change. The baseline is whatever the
-- confirming walk saw.
local function baselined(quests)
    local QC, d = fresh()
    d.enable()
    d.reload()
    d.logUpdate(1)
    eq(walk(QC, quests), true, "the baseline walk confirms")
    d.zone()
    eq(ready(QC), false, "a zone change reopens the window")
    return QC, d
end

do
    -- The dropped objective carries ZERO fulfilled, so the sum is identical across the two
    -- reads and only the COUNT moved. With a nonzero one the sum falls too and the fulfilled
    -- clause catches it on its own, which left this reading as an assertion about that clause
    -- wearing this one's name - and both count mutants survived a green file because of it.
    local QC = baselined({ { id = 1, objs = { obj("Kill 5 boars", 5), obj("Loot 3 hides", 0) } } })
    eq(walk(QC, { { id = 1, objs = { obj("Kill 5 boars", 5) } } }), false,
       "an objective COUNT that went down inside the window refuses, with the sum unchanged")
    says(QC, "1 regressed", "DebugLine counts the regression")
end

do
    local QC = baselined({ { id = 1, objs = { obj("Kill 5 boars", 5) } } })
    eq(walk(QC, { { id = 1, objs = { obj("Kill 5 boars", 5), obj("Loot 3 hides", 0) } } }), true,
       "an objective count that went UP with the sum unchanged is not a regression")
end

do
    local QC = baselined(healthy(1, 5))
    eq(walk(QC, healthy(1, 2)), false,
       "a fulfilled count that went down inside the window refuses")
end

do
    local QC = baselined(healthy(1, 5))
    eq(walk(QC, healthy(1, 5)), true, "an unchanged read inside the window confirms")
end

do
    local QC = baselined(healthy(1, 5))
    eq(walk(QC, healthy(1, 9)), true, "a fulfilled count that went UP inside the window confirms")
end

do
    local QC = baselined({ { id = 1, objs = { obj("Kill 5 boars", 5) }, done = true } })
    -- The one that makes the quest sound hold worth having: this is the read that would
    -- otherwise be written in and then chime as a fresh completion on the pass after it.
    eq(walk(QC, { { id = 1, objs = { obj("Kill 5 boars", 5) }, done = false } }), false,
       "a complete quest reading incomplete inside the window refuses")
end

do
    local QC = baselined({ { id = 1, objs = { obj("Kill 5 boars", 5) }, done = false } })
    eq(walk(QC, { { id = 1, objs = { obj("Kill 5 boars", 5) }, done = true } }), true,
       "an incomplete quest reading complete inside the window is a real change, not a regression")
end

do
    local QC = baselined(healthy(1, 5))
    -- A refused read must not become the new baseline, or the second walk of a rebuild reads
    -- as recovery and the window closes on data that is still wrong.
    eq(walk(QC, healthy(1, 2)), false, "the first regressed walk refuses")
    eq(walk(QC, healthy(1, 2)), false, "the second refuses too, so the baseline never moved")
end

do
    local QC = baselined(healthy(1, 5))
    eq(walk(QC, { { id = 2, objs = { obj("Kill 5 boars", 0) } } }), true,
       "a quest with no baseline of its own cannot regress")
end

do
    local QC = baselined(healthy(1, 5))
    eq(walk(QC, { { id = 1, objs = { obj(" Kill 5 boars", 0) } } }), false,
       "a still-streaming read refuses")
    eq(walk(QC, healthy(1, 2)), false,
       "and the regression on the pass after it is still caught")
end

do
    -- The same refusal read where it can actually FAIL. Above, a quest that already has a
    -- baseline is protected twice over - the streaming guard refuses it, and if that guard
    -- stopped returning, the regression guard one block below refuses it anyway - so the outer
    -- one is invisible through the outcome and survived a green file. It has to be measured on
    -- a quest with NO baseline, where nothing downstream is watching.
    --
    -- The harm is the interesting half: a half-read taken as truth makes the CORRECT values
    -- that follow look like a regression, so the gate then refuses a healthy log for the rest
    -- of the window on the strength of a number it had already thrown away.
    local QC, d = fresh()
    d.enable()
    d.reload()
    d.logUpdate(1)
    eq(walk(QC, { { id = 1, objs = { obj(" Kill 9 boars", 9) } } }), false,
       "a still-streaming read of a quest with no baseline refuses")
    eq(walk(QC, { { id = 1, objs = { obj("Kill 9 boars", 3) } } }), true,
       "and recorded nothing, so the real values that follow are not measured against it")
end

-- ------------------------------------------------------- the two hangs this must not have

do
    -- A decrease OUTSIDE the window is the ordinary thing it looks like, and has to advance the
    -- baseline. If it does not, the second walk here regresses 2 against a stale 5 and the
    -- player is refused for as long as the item stays banked.
    local QC, d = fresh()
    d.enable()
    d.reload()
    d.logUpdate(1)
    eq(walk(QC, healthy(1, 5)), true, "baseline of five confirms")
    now = now + SETTLE_MAX_S + 1
    walk(QC, healthy(1, 2))
    -- Read through the baseline rather than through Finish, which answers the latched
    -- confirmation here and so cannot fail. These two are what discriminate: the first says the
    -- decrease was taken, the second says it was taken EXACTLY and the guard still works.
    d.zone()
    eq(walk(QC, healthy(1, 2)), true,
       "a decrease outside the window advanced the baseline to two")
    d.zone()
    eq(walk(QC, healthy(1, 1)), false,
       "and it advanced no further than two, so a real regression is still caught")
end

do
    -- The window LAPSES. Read at both sides of the boundary, because an assertion that only
    -- reads the far side passes just as well against a gate that is never closed at all.
    local QC, d = fresh()
    d.enable()
    d.login()
    now = now + SETTLE_MAX_S - 0.1
    eq(ready(QC), false, "still closed a tenth of a second before the window ends")
    -- The settling branch of the status line, which no assertion reached: it can be made to
    -- claim a confirmation it never had, on the one line a user is asked to paste.
    says(QC, "NOT READY", "and the status line says so rather than reporting ready")
    says(QC, "settling", "and names the window it is still inside")
    now = now + 0.2
    eq(ready(QC), true, "open again once the window has passed")
    says(QC, "window lapsed", "DebugLine names the lapse rather than claiming a confirmation")
end

do
    -- The comparison is `>=`, and both sides of it were read while neither was AT it. Exactly
    -- ON the deadline the window is OPEN, so a `>` would hold the gate shut for one more frame
    -- and nothing above could tell.
    local QC, d = fresh()
    d.enable()
    d.login()
    now = now + SETTLE_MAX_S
    eq(ready(QC), true, "the window is open at exactly its deadline, not one frame later")
end

do
    -- The settling figure counts DOWN, so a constant expression passes every reading of it.
    local QC, d = fresh()
    d.enable()
    d.login()
    now = now + 2
    local far = tonumber(line(QC):match("settling, ([%d%.]+)s left"))
    now = now + 5
    local near = tonumber(line(QC):match("settling, ([%d%.]+)s left"))
    ok(far and near and far > near,
       ("the seconds left fall as the window runs out (read %s then %s)")
       :format(tostring(far), tostring(near)))
    ok(near and near > 0, "and are still positive while the window is genuinely open")
end

-- ------------------------------------------------------- a confirmation that arrived late

-- A walk that confirms AFTER the window expired guarded nothing: the gate had already fallen
-- open on the timeout. The author's own Classic reading is what asked for this - the first
-- rebuild there landed 7.9s into a 10s window, so the margin is about two seconds and a slower
-- login would spend it. Both states say "confirmed by a clean walk", so only this count
-- separates a guard that is working from one that only ever expires.
local function lateCount(QC)
    return tonumber(line(QC):match("(%d+) late")) or -1
end

do
    local QC, d = fresh()
    d.enable()
    d.login()
    d.logUpdate(LOGIN_SKIP + 1)
    eq(walk(QC, healthy()), true, "a walk inside the window confirms")
    eq(lateCount(QC), 0, "and is not counted as late")
end

do
    local QC, d = fresh()
    d.enable()
    d.login()
    d.logUpdate(LOGIN_SKIP + 1)
    now = now + SETTLE_MAX_S + 1
    eq(ready(QC), true, "the window lapsed before anything confirmed")
    eq(walk(QC, healthy()), true, "the walk that follows still confirms")
    eq(lateCount(QC), 1, "and is counted as late, because it guarded nothing")
end

do
    -- The late test is a second `>=` against the same deadline, and it was read on both sides
    -- and never at it. A confirmation landing exactly ON the deadline already guarded nothing -
    -- IsReady answers open at that instant - so it has to count as late, and a `>` here would
    -- report the guard as having worked when it had already fallen open.
    local QC, d = fresh()
    d.enable()
    d.login()
    d.logUpdate(LOGIN_SKIP + 1)
    now = now + SETTLE_MAX_S
    eq(walk(QC, healthy()), true, "a walk exactly on the deadline still confirms")
    eq(lateCount(QC), 1, "and is counted late, because the gate was already open when it landed")
end

do
    -- Counted per window rather than per walk, so a quiet session cannot inflate it.
    local QC, d = fresh()
    d.enable()
    d.login()
    d.logUpdate(LOGIN_SKIP + 1)
    now = now + SETTLE_MAX_S + 1
    eq(walk(QC, healthy()), true, "the first late walk confirms")
    eq(walk(QC, healthy()), true, "and so does the one after it")
    eq(lateCount(QC), 1, "but only one late confirmation is counted")
end

do
    -- The same bound, reached the hard way: a client that never streams its objectives.
    local QC, d = fresh()
    d.enable()
    d.login()
    d.logUpdate(4)
    for _ = 1, 3 do
        eq(walk(QC, { { id = 1, objs = { obj(" never arrives", 0) } } }), false,
           "a walk that never streams keeps refusing")
    end
    now = now + SETTLE_MAX_S + 1
    eq(ready(QC), true, "and it still lapses, so nothing it gates can be starved")
end

-- ------------------------------------------------- the rest of the numbers on that line

-- Four of the six figures on the status line were read by no assertion at all, and they are
-- exactly the reading the next session is being sent in game to take. Any of them could be
-- pinned to a literal, or wired to the wrong counter, and every harness in this tree would
-- stay green while the paste that comes back said nothing.
local function figure(QC, pattern)
    return tonumber(line(QC):match(pattern)) or -1
end

local function windows(QC)  return figure(QC, "(%d+) window%(s%)") end
local function confirms(QC) return figure(QC, "(%d+) confirmed") end
local function skip(QC)     return figure(QC, "skip (%d+)") end
local function updates(QC)  return figure(QC, "(%d+) log updates") end
local function walks(QC)    return figure(QC, "(%d+) walk%(s%)") end
local function judged(QC)   return figure(QC, "last judged (%d+)") end
local function atUpdate(QC) return figure(QC, "last judged %d+ at update (%d+)") end

do
    local QC, d = fresh()
    eq(windows(QC), 0, "a module that has seen no world event has opened no window")
    eq(confirms(QC), 0, "and confirmed nothing")
    eq(updates(QC), 0, "and seen no quest log update")

    d.enable()
    d.login()
    eq(windows(QC), 1, "a login opens one window")
    -- Read at more than one value, or the literal satisfies the assertion.
    d.zone()
    eq(windows(QC), 2, "and every later loading screen opens another")
    d.zone()
    eq(windows(QC), 3, "which is what makes a nonzero regressed count worth reading")

    eq(confirms(QC), 0, "nothing has confirmed yet")
    d.logUpdate(LOGIN_SKIP + 1)
    eq(walk(QC, healthy()), true, "a clean walk confirms")
    eq(confirms(QC), 1, "and is counted")

    -- Confirmations are counted per WINDOW, never per walk: the confirm is latched, so a second
    -- clean walk inside the same window must not move it.
    eq(walk(QC, healthy()), true, "a second clean walk still answers ready")
    eq(confirms(QC), 1, "but is not counted a second time inside the same window")
    d.zone()
    d.logUpdate(1)
    eq(walk(QC, healthy()), true, "a walk in the NEXT window confirms too")
    eq(confirms(QC), 2, "and that one is counted")
end

do
    -- skip is the cheapest thing in the whole dump to check by hand: 1 on a cold login and 0
    -- after a reload, and that difference IS the login skip working.
    local QC, d = fresh()
    d.enable()
    d.login()
    eq(skip(QC), LOGIN_SKIP, "a cold login reports the login skip")
end

do
    local QC, d = fresh()
    d.enable()
    d.reload()
    eq(skip(QC), RELOAD_SKIP, "and a reload reports none, which is the pair that discriminates")
end

do
    -- The log update counter is what the skip is measured against, so a frozen one silently
    -- holds the gate shut for the whole window.
    local QC, d = fresh()
    d.enable()
    d.login()
    eq(updates(QC), 0, "no quest log update has arrived yet")
    d.logUpdate(1)
    eq(updates(QC), 1, "one is counted")
    d.logUpdate(4)
    eq(updates(QC), 5, "and they accumulate rather than latching at one")
    -- The count is NOT reset by a later loading screen, or the skip would have to be paid again
    -- and nothing could confirm for two more events.
    d.zone()
    eq(updates(QC), 5, "a zone change does not reset the count")
    eq(skip(QC), LOGIN_SKIP, "nor re-arm the skip")
end

-- ------------------------------------------- the walk count, and the pair that goes beside it

-- This trio exists because a retail dump read `9 log updates` with `0 confirmed` and nothing on
-- the line could say whether a rebuild had run after the log arrived. It has to count FULL
-- REBUILDS rather than renders, and the pair has to describe the LAST walk rather than any
-- earlier one, or it answers a different question from the one it is printed for.
do
    local QC, d = fresh()
    eq(walks(QC), 0, "a module nothing has walked reports no walks")
    eq(judged(QC), 0, "and has judged nothing")
    eq(atUpdate(QC), 0, "at no update")

    d.enable()
    d.login()
    -- Finish answers IsReady, never "this walk was clean", so a walk inside an unconfirmed
    -- window correctly answers false. It is still a walk and must still be counted.
    eq(walk(QC, healthy()), false, "an early walk is refused the confirm")
    eq(walks(QC), 1, "but is still counted as a walk")
    -- Read at more than one value, or a literal 1 satisfies the assertion.
    eq(walk(QC, healthy()), false, "a second walk is refused too")
    eq(walks(QC), 2, "and the count accumulates rather than latching")
    eq(walk(QC, healthy()), false, "and a third")
    eq(walks(QC), 3, "and keeps accumulating")

    -- The count must survive a loading screen. Reset there, it could never show that rebuilds
    -- stopped arriving, which is the whole reason it is printed.
    d.zone()
    eq(walks(QC), 3, "a zone change does not reset the walk count")
end

do
    -- The pair has to survive a loading screen too, and for a sharper reason than the count:
    -- reset on a window that has not been walked yet, it reads `last judged 0`, which is
    -- exactly the "a walk ran and read nothing" shape this trio exists to tell apart. Left
    -- alone it keeps describing the last walk that really happened, whenever that was.
    local QC, d = fresh()
    d.enable()
    d.login()
    d.logUpdate(LOGIN_SKIP + 1)
    eq(walk(QC, { healthy(1)[1], healthy(2)[1] }), true, "a walk confirms in the first window")
    eq(judged(QC), 2, "and records two judged")
    eq(atUpdate(QC), LOGIN_SKIP + 1, "at the update it landed on")

    d.zone()
    eq(judged(QC), 2, "a zone change leaves the last walk's judged count standing")
    eq(atUpdate(QC), LOGIN_SKIP + 1, "and the update it landed at, rather than reading as an empty walk")
end

do
    -- The judged figure is the one that separates "no rebuild ran" from "one ran and read
    -- nothing" - the two shapes a bare walk count cannot tell apart.
    local QC, d = fresh()
    d.enable()
    d.login()

    eq(walk(QC, {}), false, "an empty walk cannot confirm")
    eq(walks(QC), 1, "but is still counted as a walk")
    eq(judged(QC), 0, "and judged nothing, which is why it could not confirm")
    eq(confirms(QC), 0, "and nothing confirmed")

    eq(walk(QC, { healthy(1)[1], healthy(2)[1] }), false, "a walk over two quests runs")
    eq(judged(QC), 2, "and reports both as judged")
    eq(walk(QC, { healthy(1)[1], healthy(2)[1], healthy(3)[1] }), false, "a walk over three runs")
    eq(judged(QC), 3, "and reports three, so the figure tracks the last walk rather than a total")

    -- It describes the LAST walk, so a shorter walk after a longer one must fall rather than
    -- hold the high-water mark.
    eq(walk(QC, healthy()), false, "a one-quest walk follows")
    eq(judged(QC), 1, "and the figure falls to one rather than keeping the previous walk's three")
end

do
    -- `at update N` is the half that proves a walk landed AFTER the skip was paid. Without it a
    -- walk count read against `log updates` still cannot tell a burst of early rebuilds from
    -- rebuilds that kept coming, and those are the two shapes under diagnosis.
    local QC, d = fresh()
    d.enable()
    d.login()

    eq(walk(QC, healthy()), false, "a walk before any log update cannot confirm")
    eq(atUpdate(QC), 0, "and records that it landed at update 0, at or below the skip")
    eq(confirms(QC), 0, "which is why it did not confirm")

    d.logUpdate(LOGIN_SKIP + 1)
    eq(walk(QC, healthy()), true, "a walk after the skip is paid confirms")
    eq(atUpdate(QC), LOGIN_SKIP + 1, "and records the update it landed at")
    eq(confirms(QC), 1, "and is counted")

    d.logUpdate(3)
    eq(walk(QC, healthy()), true, "a later walk runs")
    eq(atUpdate(QC), LOGIN_SKIP + 4, "and the figure moves with the count rather than latching")
end

do
    -- The aborted walk, and the only state that separates the two halves of the field.
    -- stats.walks counts rebuilds STARTED, in Begin. The pair records rebuilds FINISHED, in
    -- Finish. That is deliberate - a rebuild that raised still ran, and the line exists to say
    -- whether one ran - and fullRebuild is unprotected while Data/Feed.lua calls GetEntries
    -- bare, so the state is reachable. Without this case the increment can be moved into
    -- Finish, and lastJudged deleted in favour of the live walkJudged, both with the file green.
    local QC, d = fresh()
    d.enable()
    d.login()
    d.logUpdate(LOGIN_SKIP + 1)
    eq(walk(QC, healthy()), true, "a complete walk confirms")
    eq(walks(QC), 1, "one walk is counted")
    eq(judged(QC), 1, "and it judged one quest")

    ok(pcall(function()
        QC:Begin()
        QC:Note(2, { obj("Kill 5 boars", 5) }, false)
        QC:Note(3, { obj("Kill 5 boars", 5) }, false)
    end), "a walk that opens and never closes raises nothing on the way in")

    eq(walks(QC), 2, "the aborted rebuild is still counted, because it did run")
    eq(judged(QC), 1, "while the pair keeps describing the last walk that FINISHED")
    eq(atUpdate(QC), LOGIN_SKIP + 1, "including the update that one landed at")
end

do
    -- The reading this instrument was written to explain, reproduced: quests judged, nothing
    -- refused, and no confirmation - because every walk ran before the skip was paid and none
    -- came back afterwards. The pair names that outright where the old line could not.
    local QC, d = fresh()
    d.enable()
    d.login()
    eq(walk(QC, { healthy(1)[1], healthy(2)[1] }), false, "a walk lands early and cannot confirm")
    d.logUpdate(8)

    eq(updates(QC), 8, "eight log updates then arrive")
    eq(walks(QC), 1, "but only one walk ever ran")
    eq(judged(QC), 2, "it judged quests, so it was not an empty walk")
    eq(atUpdate(QC), 0, "and it landed at update 0, before the skip was paid")
    eq(confirms(QC), 0, "which is exactly why nothing confirmed")
    eq(figure(QC, "refused (%d+) streaming"), 0, "with nothing refused as unstreamed")
    eq(figure(QC, "(%d+) regressed"), 0, "and nothing refused as regressed")
end

-- --------------------------------------------------------------- a zone change is not a login

do
    local QC, d = fresh()
    d.enable()
    d.login()
    d.logUpdate(LOGIN_SKIP + 1)
    eq(walk(QC, healthy()), true, "the cold login confirms")

    d.zone()
    eq(ready(QC), false, "a zone change reopens the window")
    -- No further QUEST_LOG_UPDATE. The skip is a login question and its count is chosen once,
    -- so re-arming it here would demand two more events after every loading screen.
    eq(walk(QC, healthy()), true, "and one clean walk reconfirms with no new update needed")
end

-- ---------------------------------------------------------------------------- secret values

local function refusals(QC)
    local text = line(QC)
    return tonumber(text:match("refused (%d+) streaming")) or -1,
           tonumber(text:match("(%d+) regressed")) or -1
end

local function secretly()
    local QC, d = fresh({ secret = true })
    d.enable()
    d.reload()
    d.logUpdate(1)
    return QC, d
end

do
    -- SKIPPED, not refused, and the counters are what tell those apart: a secret value is a
    -- reading we cannot take, never a reading that says the log is mid-stream. Counting it as a
    -- refusal would let one secret value hold the gate shut for the whole window.
    local QC = secretly()
    walk(QC, { { id = 1, objs = { obj(SECRET, 0) } } })
    local streaming, regressed = refusals(QC)
    eq(streaming, 0, "a secret objective text is not counted as a streaming refusal")
    eq(regressed, 0, "nor as a regression")
end

do
    local QC = secretly()
    walk(QC, { { id = 1, objs = { { text = "Kill 5 boars", numFulfilled = SECRET } } } })
    eq((refusals(QC)), 0, "a secret fulfilled count is not counted as a refusal either")
end

do
    -- An objective with no numFulfilled at all is ordinary, and it hands the client's own
    -- secret test a nil on every walk. This client raises on one, which is the direction that
    -- costs a whole render: Data/Feed.lua calls GetEntries bare.
    local QC, d = fresh({ secret = "strict" })
    d.enable()
    d.reload()
    d.logUpdate(1)
    eq(walk(QC, { { id = 1, objs = { { text = "Kill 5 boars" } } } }), true,
       "a missing fulfilled count does not reach a client that raises on nil")
    eq((refusals(QC)), 0, "and is judged normally rather than refused")
end

do
    -- The case that actually reaches a player: one secret quest beside readable ones. The walk
    -- has to confirm on what it COULD read rather than being poisoned by what it could not.
    local QC = secretly()
    eq(walk(QC, { { id = 1, objs = { obj(SECRET, 0) } }, healthy(2)[1] }), true,
       "a secret quest beside a readable one does not stop the walk confirming")
end

do
    -- A walk that judged NOTHING is no evidence the log arrived, so it may not confirm - and
    -- because refusing only ever costs the window, that stays bounded.
    local QC, d = secretly()
    eq(walk(QC, { { id = 1, objs = { obj(SECRET, 0) } } }), false,
       "a log of nothing but unjudgeable quests does not confirm")
    now = now + SETTLE_MAX_S + 1
    eq(ready(QC), true, "and lapses anyway rather than holding the gate shut")
    ok(d ~= nil, "the drive handle is returned alongside the module")
end

do
    local QC, d = secretly()
    eq(walk(QC, healthy(1, 5)), true, "baseline of five confirms")
    d.zone()
    walk(QC, { { id = 1, objs = { obj(SECRET, 0) } } })
    -- Skipped in BOTH directions: the secret read must not have written itself in as the new
    -- baseline, or the real regression below would compare against a zero and be accepted.
    d.zone()
    eq(walk(QC, healthy(1, 2)), false,
       "so the baseline is still five and a real regression is still caught")
end

-- ----------------------------------------------------------------------------- the baseline

local function baselines(QC)
    local text = line(QC)
    return tonumber(text:match("(%d+) baselines")) or -1
end

do
    local QC, d = fresh()
    d.enable()
    d.reload()
    d.logUpdate(1)
    eq(walk(QC, { healthy(1)[1], healthy(2)[1], healthy(3)[1] }), true, "three quests confirm")
    eq(baselines(QC), 3, "three baselines are held")

    eq(walk(QC, { healthy(1)[1] }), true, "a walk with one of them confirms")
    eq(baselines(QC), 1, "and the two that left the log are pruned")
end

do
    -- The prune must not run INSIDE the window. A quest missing from a partial walk there is
    -- missing because it has not arrived, and dropping its baseline is the one thing that lets
    -- it come back reading zero objectives with nothing left to judge it against - at which
    -- point nothing refuses it and the gate confirms on a half-read log.
    local QC, d = fresh()
    d.enable()
    d.reload()
    d.logUpdate(1)
    eq(walk(QC, { healthy(1)[1], healthy(2)[1] }), true, "two quests confirm")
    eq(baselines(QC), 2, "and both hold a baseline")

    d.zone()
    -- Quest 2 is absent and quest 3 has not streamed in, so this walk cannot confirm and the
    -- log is still not trusted.
    eq(walk(QC, { healthy(1)[1], { id = 3, objs = { obj(" streaming", 0) } } }), false,
       "a partial walk inside the window does not confirm")
    eq(baselines(QC), 2, "and the absent quest keeps the baseline it is about to need")

    -- It returns reading zero objectives. Against an intact baseline that is a count
    -- regression and is refused. Against a pruned one there is nothing left to compare.
    eq(walk(QC, { healthy(1)[1], { id = 2, objs = {} } }), false,
       "so the quest returning with no objectives is still refused as a regression")
end

do
    local QC, d = fresh()
    d.enable()
    d.reload()
    d.logUpdate(1)
    eq(walk(QC, { healthy(1)[1], healthy(2)[1] }), true, "two quests confirm")
    -- Reopened first, or the walk below answers the LATCHED confirmation rather than its own
    -- reading and the assertion cannot fail.
    d.zone()
    eq(walk(QC, {}), false, "an empty walk does not confirm")
    -- Nothing is pruned against a walk that saw nothing, the same rule the quest providers
    -- already apply to the stamps. A cold log reads empty and is not.
    eq(baselines(QC), 2, "and it prunes nothing")
end

do
    local QC, d = fresh()
    d.enable()
    d.reload()
    d.logUpdate(1)
    local okCall = pcall(QC.Note, QC, 1, { obj("Kill 5 boars", 5) }, false)
    ok(okCall, "Note outside a walk does not raise")
    eq(baselines(QC), 0, "and records nothing")

    -- Again AFTER a walk, which is the reading that discriminates: before one, walkOpen has
    -- never been true and a Finish that forgets to clear it looks identical to one that does.
    eq(walk(QC, healthy(1)), true, "a walk confirms")
    eq(baselines(QC), 1, "and leaves one baseline")
    ok(pcall(QC.Note, QC, 2, { obj("Loot 3 hides", 3) }, false),
       "a Note after that walk closed does not raise")
    eq(baselines(QC), 1, "and is still refused, so Finish really did close the walk")
end

do
    local QC, d = fresh()
    d.enable()
    d.reload()
    d.logUpdate(1)
    local okCall, res = pcall(QC.Finish, QC)
    ok(okCall, "Finish with no walk open does not raise")
    eq(res, false, "and answers the live verdict rather than confirming on nothing")
    eq(baselines(QC), 0, "and records nothing")
end

do
    -- The same guard, read where it can actually fail: with a walk's accumulators still holding
    -- last time's clean result, a Finish that does not refuse confirms the new window shut
    -- without anything having looked at the quest log at all.
    local QC, d = fresh()
    d.enable()
    d.reload()
    d.logUpdate(1)
    eq(walk(QC, { healthy(1)[1], healthy(2)[1] }), true, "a clean walk confirms")
    d.zone()
    eq(ready(QC), false, "the zone change reopens the window")
    local okCall, res = pcall(QC.Finish, QC)
    ok(okCall, "a bare Finish does not raise")
    eq(res, false, "and refuses to confirm on the previous walk's accumulators")
    eq(ready(QC), false, "so the window is still open")
end

do
    local QC = armedAndPast()
    eq(walk(QC, { { id = "not a number", objs = { obj("Kill 5 boars", 5) } } }), false,
       "a quest id that is not a number is ignored rather than counted as a quest")
    eq(baselines(QC), 0, "and records nothing")
end

-- A module of its own for each, because Finish answers IsReady rather than "this walk was
-- clean" - so once anything has confirmed, every later walk in the same module answers true
-- whatever it saw, and a second assertion sharing one module cannot fail.
do
    local QC = armedAndPast()
    eq(walk(QC, { { id = 1, objs = "not a table" } }), true,
       "objectives that are not a table read as a quest with none")
end

do
    -- Unjudgeable rather than unready, the same as a secret value: it must not raise and it
    -- must not be counted as a refusal, but it is no evidence the log arrived either.
    local QC = armedAndPast()
    eq(walk(QC, { { id = 1, objs = { "not a table either" } } }), false,
       "an objective that is not a table is skipped rather than raising")
    eq(walk(QC, { { id = 1, objs = { "still not a table" } }, healthy(2)[1] }), true,
       "and a readable quest beside it still confirms the walk")
end

-- ------------------------------------------------------------------- the constants assumed

do
    local f = assert(io.open(SRC, "r"))
    local src = f:read("*a")
    f:close()

    ok(src:find("local SETTLE_MAX_S = " .. SETTLE_MAX_S, 1, true) ~= nil,
       "the shipped window is still the " .. SETTLE_MAX_S .. " seconds every case above assumes")
    ok(src:find("local LOGIN_SKIP  = " .. LOGIN_SKIP, 1, true) ~= nil,
       "a cold login still skips " .. LOGIN_SKIP)
    ok(src:find("local RELOAD_SKIP = " .. RELOAD_SKIP, 1, true) ~= nil,
       "a reload still skips " .. RELOAD_SKIP)
    -- PLAYER_ENTERING_WORLD is the only writer of the window. A second one anywhere would let a
    -- walk extend its own suspicion, which is the loop the whole design is shaped to avoid.
    local writers = select(2, src:gsub("settleUntil%s*=%s*GetTime", ""))
    eq(writers, 1, "the window has exactly one writer")
end

-- ------------------------------------------------------------------------------- the seams

local function source(rel)
    local f = assert(io.open(repoFile(rel), "r"), rel .. " is missing")
    local src = f:read("*a")
    f:close()
    return src
end

local function wired(rel, needle, msg)
    ok(source(rel):find(needle, 1, true) ~= nil, ("%s [%s]"):format(msg, rel))
end

for _, rel in ipairs({ "Data/Providers/Quests.lua", "Data/Providers/QuestsClassic.lua" }) do
    wired(rel, 'ns:GetModule("QuestCache")', "the provider holds the module")
    -- Anchored on the WHOLE call including the closing paren. Stopping at the comma is a
    -- prefix match, and the third argument is what feeds the complete-reading-incomplete
    -- clause, so corrupting it to a literal satisfied the grep and disarmed that clause.
    wired(rel, "QuestCache:Note(id, objs, e.state == STATE.COMPLETE)",
          "its walk feeds the objectives it already read, and the state it read them with")
    wired(rel, "QuestCache:Begin()", "its rebuild opens a walk")
    wired(rel, "local cacheReady = QuestCache:Finish()", "its rebuild closes one")
    -- Anchored on the whole condition, never on the call: a rebuild that asks for the verdict
    -- and then prunes regardless is the exact shape this is here to stop.
    wired(rel, "if cacheReady and next(store:Out()) ~= nil then",
          "and the stamp prune waits for both halves")

    -- Presence is not enough, and neither is "Begin comes before Finish" - moving Begin to sit
    -- just above Finish satisfies that and still breaks everything, because Note no-ops outside
    -- an open walk. walkJudged then stays zero, the gate can never confirm, and it degrades to
    -- waiting the full window on every login and every loading screen, silently. What the code
    -- needs is the walk OPEN before anything is walked, and both providers say so by pairing
    -- the two Begins. Note itself is defined in fillLines, textually ABOVE fullRebuild, so a
    -- source-order test against it would fail the correct build.
    local src = source(rel)
    ok(src:find("store:Begin()\n    QuestCache:Begin()", 1, true) ~= nil,
       ("the cache walk opens beside the store's, ahead of the log walk [%s]"):format(rel))
    local fin = src:find("local cacheReady = QuestCache:Finish()", 1, true)
    -- Both sides guarded. A missing store:Finish() makes the find nil, and nil < number
    -- aborts the file before its summary line, which every battery reads as a survivor.
    local sfin = src:find("store:Finish()", 1, true)
    ok(fin and sfin and sfin < fin,
       ("and closes after it [%s]"):format(rel))

    -- COUNTED, because the walk figure on the status line means FULL REBUILDS only while this
    -- is the sole caller in the file. A second Begin on the cheap path would still satisfy
    -- every presence grep above while quietly turning that number into a render count - and it
    -- is read against `log updates` to decide whether rebuilds kept coming, so a render count
    -- there does not read as wrong, it reads as the opposite answer.
    -- Whole-line comments are stripped first. QuestCache's own note invites a matching one in
    -- the provider, and counting that would fail a build nothing is wrong with.
    local code   = src:gsub("\n[ \t]*%-%-[^\n]*", "\n")
    local begins = select(2, code:gsub("QuestCache:Begin%(%)", ""))
    eq(begins, 1, ("the provider opens exactly one cache walk [%s]"):format(rel))
end

do
    -- COUNTED on both flavors, where retail was only ever presence-checked. Retail has one
    -- gated prune and Classic has two, and a second ungated one appearing on either is exactly
    -- the edit this is here to catch - presence cannot see an addition.
    local src = source("Data/Providers/Quests.lua")
    local gates = select(2, src:gsub("if cacheReady and next%(store:Out%(%)%) ~= nil then", ""))
    eq(gates, 1, "retail gates its one prune, the first-seen stamps")
    local ungated = select(2, src:gsub("\n    if next%(store:Out%(%)%) ~= nil then", ""))
    eq(ungated, 0, "and leaves no ungated prune behind")
end

do
    local src = source("Data/Providers/QuestsClassic.lua")
    local gates = select(2, src:gsub("if cacheReady and next%(store:Out%(%)%) ~= nil then", ""))
    eq(gates, 2, "Classic gates BOTH of its prunes, the stamps and the tracked set")
    -- Anchored on the start of the line. Without the newline and indent this is a SUBSTRING of
    -- the gated form, so it matched the correct build and failed it.
    ok(src:find("\n    if next(store:Out()) ~= nil then\n        TrackedSet:Prune", 1, true) == nil,
       "and no ungated tracked-set prune is left behind")
end

do
    local src = source("Data/QuestSound.lua")
    ok(src:find('ns:GetModule("QuestCache")', 1, true) ~= nil,
       "the quest sound holds the module [Data/QuestSound.lua]")
    ok(src:find("if not now and lastComplete[id] and not QuestCache:IsReady() then", 1, true) ~= nil,
       "and holds a complete quest's state across a loading screen [Data/QuestSound.lua]")
end

do
    -- Listed in all four, and it has to be: both quest providers take it at file scope, so a
    -- flavor that loads a provider without it fails at load rather than degrading.
    local listed = 0
    for _, toc in ipairs({ "EQObjectiveTracker.toc", "EQObjectiveTracker_Mainline.toc",
                           "EQObjectiveTracker_TBC.toc", "EQObjectiveTracker_Vanilla.toc" }) do
        local src = source(toc)
        if src:find("Data\\QuestCache.lua", 1, true) then listed = listed + 1 end
        -- Load order is the contract: a provider reading ns:GetModule("QuestCache") at file
        -- scope gets nil if this line sits below it.
        local mine  = src:find("Data\\QuestCache.lua", 1, true)
        local users = src:find("Data\\Providers\\Quests", 1, true)
        ok(mine and users and mine < users, "QuestCache loads before the providers [" .. toc .. "]")
        local sound = src:find("Data\\QuestSound.lua", 1, true)
        ok(mine and sound and mine < sound, "QuestCache loads before the quest sound [" .. toc .. "]")
    end
    eq(listed, 4, "QuestCache is listed in all four TOCs")
end

do
    wired("UI/Commands.lua", 'debugLine("QuestCache")', "/eqot status reports the gate")
end

print(("test_quest_cache: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
