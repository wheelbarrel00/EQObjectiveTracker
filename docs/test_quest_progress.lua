-- luacheck: globals GetQuestProgressBarPercent C_TaskQuest issecretvalue
--
-- Unit tests for the quest progress bar percentage, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_quest_progress.lua
--
-- Two halves, because the feature is two halves. Data/QuestProgress.lua loads whole - it
-- touches no frame - and the emission stanza is SLICED out of each provider by text anchor,
-- the way docs/test_row_blocks.lua slices UI/Row.lua.
--
-- The cases that earn this file:
--
--   1. Both sources are tried IN ORDER and the first is a bare global. Nothing here may reach
--      an API this client does not have, because Core/Compat.lua probes the two separately and
--      a client can answer yes to one and no to the other.
--   2. ZERO is a valid percentage. It is also the measured case - quest 92149 read 0 of 1 - so
--      anything treating 0 as "no answer" breaks the exact quest this was written for.
--   3. The percentage is carried BESIDE current and required, never over them. Overwriting
--      them draws the bar correctly and silently rewrites what a bars-OFF row prints, which
--      trades the bug being fixed for a different one.
--   4. The three providers must not drift apart. They carried one identical five-line stanza
--      each before this, and the whole reason the bar was missing in three places at once is
--      that the stanza was copied rather than shared.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local function readFile(rel)
    local fh = assert(io.open(repoFile(rel), "r"))
    local s = fh:read("*a")
    fh:close()
    return s
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

-- A real Midnight secret value reports type "number" and then errors on arithmetic, and no Lua
-- 5.1 stub can reproduce that: a table is refused by the type check whether or not the
-- issecretvalue probe ever runs, which would be an assertion that cannot fail. So a build marks
-- an ordinary IN-RANGE number secret instead. That is the only shape where the probe, its
-- answer and its ORDER ahead of the range test are all load-bearing.
local secretValue
_G.issecretvalue = function(v) return secretValue ~= nil and v == secretValue end

local LINE = {
    OBJECTIVE = "objective", PROGRESSBAR = "progressbar",
    NOTE = "note", WEIGHTED = "weighted",
}

-- ------------------------------------------------------------------ Data/QuestProgress.lua

-- calls records which source was REACHED, not merely which answered. A guard that is deleted
-- shows up here as a call on a client that has no such API, which is the failure the ns.Has
-- flags exist to prevent and which a nil-return check alone would miss.
local calls
local function build(opts)
    opts = opts or {}
    calls = { global = 0, task = 0 }
    secretValue = opts.secret
    local mods = {}

    _G.GetQuestProgressBarPercent = nil
    _G.C_TaskQuest = {}
    if opts.globalAnswers ~= nil then
        _G.GetQuestProgressBarPercent = function(id)
            calls.global = calls.global + 1
            return opts.globalAnswers(id)
        end
    end
    if opts.taskAnswers ~= nil then
        _G.C_TaskQuest.GetQuestProgressBarInfo = function(id)
            calls.task = calls.task + 1
            return opts.taskAnswers(id)
        end
    end

    local ns = {
        Has = {
            -- Deliberately NOT derived from whether the stub above exists. These are the two
            -- flags Core/Compat.lua sets, and a case has to be able to set a flag false while
            -- the API is present, which is what proves the guard rather than the absence.
            QuestProgressBar     = opts.hasGlobal ~= false and opts.globalAnswers ~= nil,
            TaskQuestProgressBar = opts.hasTask   ~= false and opts.taskAnswers   ~= nil,
        },
    }
    if opts.hasGlobal ~= nil then ns.Has.QuestProgressBar     = opts.hasGlobal end
    if opts.hasTask   ~= nil then ns.Has.TaskQuestProgressBar = opts.hasTask end

    function ns:RegisterModule(n, t) mods[n] = t return t end
    function ns:GetModule(n) return mods[n] end
    function ns:IsModuleDisabled(n) return opts.disabled == n end

    -- Captured at chunk load, so it has to be gone BEFORE the file is read. issecretvalue is a
    -- Midnight global and this file ships in both Classic TOCs, where C_TaskQuest is present as
    -- a stub - so usable() is reachable there and an unguarded _issecret(v) would raise.
    local realSecret = _G.issecretvalue
    if opts.noSecretApi then _G.issecretvalue = nil end
    assert(loadfile(repoFile("Data/QuestProgress.lua")))("EQObjectiveTracker", ns)
    _G.issecretvalue = realSecret
    return mods.QuestProgress, ns
end

local function line(QP, needle)
    local okCall, text = pcall(QP.DebugLine, QP)
    if not okCall then return "<DebugLine raised: " .. tostring(text) .. ">" end
    for l in (text .. "\n"):gmatch("([^\n]*)\n") do
        if l:find(needle, 1, true) then return l end
    end
    return ""
end
local function has(l, s) return l:find(s, 1, true) ~= nil end

-- pcall'd, so a mutant that RAISES fails an assertion here rather than aborting the file. An
-- aborted file has no summary line for the mutation battery to read, and it would be reported
-- as a crash it cannot classify rather than as the caught mutant it is.
local function percent(QP, id)
    local okCall, v = pcall(QP.Percent, QP, id)
    if not okCall then return "<raised: " .. tostring(v) .. ">" end
    return v
end

-- The bare global answers, and it is asked first.
local QP = build({ globalAnswers = function() return 42 end,
                   taskAnswers   = function() return 7 end })
ok(percent(QP, 92149) == 42, "the bare global answers first")
ok(calls.global == 1 and calls.task == 0, "and the second source is not asked once it has")
ok(has(line(QP, "asked"), "asked 1, 1 by global, 0 by task quest, 0 refused"),
   "the counters say which answered: " .. line(QP, "asked"))
ok(has(line(QP, "last:"), "42% for 92149, from GetQuestProgressBarPercent"),
   "and the last read is named: " .. line(QP, "last:"))

-- ZERO is a real percentage, and it is the measured case. Lua's only falsy values are nil and
-- false, so 0 survives every `if pct then` on the way to a row - but a range check written as
-- `v > 0` or a source answering 0 treated as silence would both break exactly quest 92149.
QP = build({ globalAnswers = function() return 0 end })
ok(percent(QP, 92149) == 0, "zero is an answer, not a refusal")
ok(has(line(QP, "asked"), "1 by global"), "and is counted as one: " .. line(QP, "asked"))

-- The task quest source, reached only when the global has nothing.
QP = build({ globalAnswers = function() return nil end,
             taskAnswers   = function() return 63 end })
ok(percent(QP, 92149) == 63, "the task quest source answers when the global does not")
ok(calls.global == 1 and calls.task == 1, "and both were asked, in that order")
ok(has(line(QP, "asked"), "asked 1, 0 by global, 1 by task quest, 0 refused"),
   "the counters name the second source: " .. line(QP, "asked"))

-- The capability guards. The API is PRESENT in both builds below and the flag is false, so a
-- deleted guard shows up as a call rather than as a wrong answer.
QP = build({ hasGlobal = false, globalAnswers = function() return 42 end,
             taskAnswers = function() return 63 end })
ok(percent(QP, 92149) == 63, "a client whose flag says no global falls through to the second")
ok(calls.global == 0, "and never calls the global it was told it does not have")

QP = build({ globalAnswers = function() return nil end,
             hasTask = false, taskAnswers = function() return 63 end })
ok(percent(QP, 92149) == nil, "a client with neither flag answers nil")
ok(calls.task == 0, "and never calls the task quest source it was told it does not have")
ok(has(line(QP, "asked"), "0 by global, 0 by task quest, 1 refused"),
   "the refusal is counted: " .. line(QP, "asked"))
ok(has(line(QP, "last:"), "neither source answered for 92149"),
   "and named, so an empty bar and an absent API do not read alike: " .. line(QP, "last:"))
ok(has(line(QP, "api"), "C_TaskQuest false"),
   "the status prints the flags themselves: " .. line(QP, "api"))

-- A client with no sources at all, which is every Classic flavor.
QP = build({})
ok(percent(QP, 92149) == nil, "a client with no source at all answers nil")
ok(pcall(QP.DebugLine, QP), "and the status line reports rather than raising")

-- Anything unusable is refused and falls through, rather than reaching a row.
for _, bad in ipairs({ { v = -1, why = "a negative percentage" },
                       { v = 101, why = "a percentage over 100" },
                       { v = "40", why = "a string" },
                       { v = true, why = "a boolean" } }) do
    QP = build({ globalAnswers = function() return bad.v end,
                 taskAnswers   = function() return 63 end })
    ok(percent(QP, 92149) == 63, bad.why .. " is refused and the second source is tried")
end

-- 55 is a perfectly ordinary percentage that this build has marked secret, so only the
-- issecretvalue probe can tell it apart from any other reading.
QP = build({ secret = 55, globalAnswers = function() return 55 end,
             taskAnswers   = function() return 63 end })
ok(percent(QP, 92149) == 63, "a secret percentage is refused and the second source answers")

-- The guard's EXISTENCE is provable here and its ORDER is not, and that limit is recorded
-- rather than papered over. In game the probe has to run ahead of the range comparison, because
-- a real secret value reports type "number" and RAISES the moment anything compares it. No Lua
-- 5.1 value does that: measured, the VM answers number-versus-number primitively and never
-- consults an __lt installed with debug.setmetatable, so an attempt at it here passed whichever
-- order production was in - an assertion that cannot fail, dressed up as a strong one.
-- docs/mutate_quest_progress.py therefore carries no reordering mutant. If it ever grows one it
-- will read SURVIVED, and that will be this limit rather than a new hole.

-- The bisection axis. This module makes two quest API calls from inside Tracker:Render, and a
-- taint report in this family is answered by switching halves off - so a disable that still
-- reached an API would be worse than none, because it would report the module off while it went
-- on calling. The check therefore sits ahead of BOTH reads.
--
-- The stub answers for ns:IsModuleDisabled("QuestProgress"), which in game is what safe mode
-- makes true: this module has no OnEnable, so its NAME is not in ns:SkippableModules and cannot
-- be typed at /eqot disable. `/eqot disable all` is what reaches it.
QP = build({ disabled = "QuestProgress",
             globalAnswers = function() return 42 end,
             taskAnswers   = function() return 63 end })
ok(percent(QP, 92149) == nil, "safe mode answers nil")
ok(calls.global == 0 and calls.task == 0,
   "and reaches neither source, global " .. calls.global .. ", task " .. calls.task)
ok(has(line(QP, "last:"), "switched off, safe mode"),
   "and says so, rather than reading like a client with no API: " .. line(QP, "last:"))

-- A different module being disabled must not silence this one, which is what asking
-- IsModuleDisabled by the wrong name would do.
QP = build({ disabled = "Widgets", globalAnswers = function() return 42 end })
ok(percent(QP, 92149) == 42, "another module's disable does not reach it")

QP = build({ globalAnswers = function() return 42 end })
ok(percent(QP, nil) == nil, "no quest id is not a question")
ok(has(line(QP, "asked"), "asked 0"), "and is not counted as one: " .. line(QP, "asked"))

-- ------------------------------------------------------- the shipped emission, per provider

-- Sliced from the `if o.type == "progressbar" then` line to the `end` at the SAME indentation.
-- Indentation is the structure here, which is why a fixed line count or a bare "end" anchor
-- would rot on the first edit. A failure names the file rather than dropping the case.
local PROVIDERS = {
    "Data/Providers/Quests.lua",
    "Data/Providers/QuestsClassic.lua",
    "Data/Providers/WorldQuests.lua",
}
-- Deliberately short of the trailing `then`: a change that WIDENS this condition is one of the
-- defects worth catching, and an anchor carrying the whole line would be destroyed by it and
-- report as a crash the battery cannot classify rather than as the caught mutant it is.
local ANCHOR = 'if o.type == "progressbar"'

local function stanza(path)
    local src = readFile(path)
    local at = src:find(ANCHOR, 1, true)
    assert(at, "anchor not found in " .. path .. ": " .. ANCHOR)
    local lineStart = (src:sub(1, at - 1):find("\n[^\n]*$") or 0) + 1
    local indent    = src:sub(lineStart, at - 1)
    assert(indent:match("^%s*$"), "the anchor is not at the start of its line in " .. path)

    local out, closing = {}, indent .. "end"
    for l in src:sub(lineStart):gmatch("([^\n]*)\n") do
        out[#out + 1] = l
        if l == closing then
            return table.concat(out, "\n"), indent
        end
    end
    error("no closing end at the anchor's indentation in " .. path)
end

-- The three carried one identical stanza each, and a bar missing from three places at once is
-- what copying rather than sharing buys. Compared with the id name and the indentation
-- normalized away, since those are all a provider is allowed to differ by.
local function normalize(body, indent)
    local out = {}
    for l in (body .. "\n"):gmatch("([^\n]*)\n") do
        out[#out + 1] = (l:sub(1, #indent) == indent) and l:sub(#indent + 1) or l
    end
    return (table.concat(out, "\n"):gsub("questID", "id"))
end

local canonical
for _, path in ipairs(PROVIDERS) do
    local norm = normalize(stanza(path))
    if not canonical then
        canonical = norm
    else
        ok(norm == canonical,
           path .. " emits the same stanza as " .. PROVIDERS[1] .. ", not a drifted copy")
    end
end

-- Run the sliced stanza against a controlled percentage source. Both id names are declared
-- because the providers spell it differently, and normalizing that away above is a text
-- comparison rather than a license to rewrite what runs here.
local function emit(path, o, pct, hasSource)
    local body = stanza(path)
    local fn = assert(loadstring(
        "local o, ln, LINE, ns, id, questID = ...\n" .. body .. "\nreturn ln"))
    local asked = 0
    local QPStub = { Percent = function()
        asked = asked + 1
        if not hasSource then return nil end
        return pct
    end }
    local nsStub = { GetModule = function(_, n)
        assert(n == "QuestProgress", "the stanza asked for module " .. tostring(n))
        return QPStub
    end }
    local ln = { text = o.text or "", completed = false,
                 current = o.numFulfilled, required = o.numRequired }
    fn(o, ln, LINE, nsStub, 92149, 92149)
    return ln, asked
end

for _, path in ipairs(PROVIDERS) do
    local who = path:match("([^/]+)%.lua$") .. ": "

    -- The measured case. Quest 92149 Death to Twilight reads 0 of 1, which the bar gate refuses
    -- as a yes or no, and the real fill is in neither number.
    local ln, asked = emit(path, { type = "progressbar", text = "Camp destroyed",
                                   numFulfilled = 0, numRequired = 1 }, 30, true)
    ok(ln.percent == 30, who .. "a 0 of 1 progressbar carries the percentage, got "
       .. tostring(ln.percent))
    ok(ln.kind == LINE.PROGRESSBAR, who .. "and keeps its own kind")
    -- The property that makes "Show progress bars" a real off switch. Overwriting these turned
    -- `0/1 Camp destroyed` into `0/100 Camp destroyed` for anyone with bars switched off.
    ok(ln.current == 0 and ln.required == 1,
       who .. "with its own numbers untouched, got "
       .. tostring(ln.current) .. "/" .. tostring(ln.required))
    ok(asked == 1, who .. "asked for once, got " .. asked)

    -- Zero again, at the layer that has to pass it on. `if pct then` is safe in Lua and would
    -- not be in most languages, so it is worth a case rather than a comment.
    ln = emit(path, { type = "progressbar", numFulfilled = 0, numRequired = 1 }, 0, true)
    ok(ln.percent == 0,
       who .. "a percentage of zero is carried, not dropped, got " .. tostring(ln.percent))

    -- A denominator of 100 already IS the percentage. It is left exactly as it was, and no
    -- source is consulted for it - this half was measured working long before the fix.
    ln, asked = emit(path, { type = "progressbar", numFulfilled = 43, numRequired = 100 },
                     30, true)
    ok(ln.kind == LINE.WEIGHTED, who .. "a denominator of 100 is WEIGHTED as it always was")
    ok(ln.current == 43, who .. "keeping its own number, got " .. tostring(ln.current))
    ok(ln.percent == nil, who .. "and carrying no percentage of its own")
    ok(asked == 0, who .. "and no source is asked for it, got " .. asked)

    -- Neither source answered. Strictly no worse than before the fix: it stays the count it was.
    ln = emit(path, { type = "progressbar", numFulfilled = 0, numRequired = 1 }, nil, false)
    ok(ln.kind == LINE.PROGRESSBAR, who .. "an unanswered percentage stays a count")
    ok(ln.percent == nil, who .. "carrying no percentage")
    ok(ln.current == 0 and ln.required == 1, who .. "with its own numbers untouched")

    -- Anything that is not a progressbar is not touched, and must not spend a read either.
    local before = { type = "monster", numFulfilled = 3, numRequired = 5 }
    ln, asked = emit(path, before, 30, true)
    ok(ln.kind == nil, who .. "an ordinary objective keeps its kind")
    ok(ln.percent == nil, who .. "and gets no percentage")
    ok(ln.current == 3 and ln.required == 5, who .. "and its numbers")
    ok(asked == 0, who .. "and asks no source at all, got " .. asked)
end

-- A client with no issecretvalue at all, which is every Classic flavor.
QP = build({ noSecretApi = true, globalAnswers = function() return 42 end })
ok(percent(QP, 92149) == 42,
   "a client with no issecretvalue still answers rather than raising, got "
   .. tostring(percent(QP, 92149)))
ok(pcall(QP.DebugLine, QP), "and its status line reports rather than raising")

-- ------------------------------------------------- the pooled line contract

-- Lines are POOLED, and Entry.PushLine's reset list is the whole defense. A field added to a
-- line without being added there carries a previous quest's value onto the next row that
-- reuses the table - and percent is the newest field in that list. Neither the block builder
-- nor the emission slice can see this, because both hand-build their line tables.
_G.wipe = _G.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local emods = {}
local ens = {}
function ens:RegisterModule(n, t) emods[n] = t return t end
function ens:GetModule(n) return emods[n] end
assert(loadfile(repoFile("Data/Entry.lua")))("EQObjectiveTracker", ens)
local Entry = emods.Entry

local st = Entry.NewStore({ groupID = "quests" })
st:Begin()
local first = st:Acquire(92149)
Entry.BeginLines(first)
local lineA = Entry.PushLine(first)
lineA.percent = 40
Entry.EndLines(first)
st:Finish()

st:Begin()
local again = st:Acquire(92149)
Entry.BeginLines(again)
local lineB = Entry.PushLine(again)
Entry.EndLines(again)
st:Finish()

ok(lineA == lineB, "the store really does reuse the line table, or the case below proves nothing")
ok(lineB.percent == nil,
   "and a reused line carries no percentage from the pass before, got " .. tostring(lineB.percent))

print(string.format("test_quest_progress: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
