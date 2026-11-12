-- ---------------------------------------------------------------------------
-- duo_board.lua -- Double Agents: Code Words for two readers (pure Lua).
--
-- Two players, one reader each, playing together. Both readers deal the same
-- 25 words from the game code (common/duo.lua) and the same two keys, one per
-- player; each reader shows only its own player's key. A key marks 9 agents
-- and 3 assassins; the keys overlap: 15 agents in all, 3 of them on both keys.
--
--   card kinds (key 1 / key 2)    count
--   agent / agent                     3
--   agent / bystander                 5
--   bystander / agent                 5
--   agent / assassin                  1
--   assassin / agent                  1
--   assassin / assassin               1
--   assassin / bystander              1
--   bystander / assassin              1
--   bystander / bystander             7
--
-- Turns: one player gives a clue for the agents of their own key; the other
-- guesses. Both players tap the guessed word on their own reader, so the two
-- readers stay in step; each judges it against the clue giver's key:
--   agent      found (for both keys), keep guessing
--   bystander  the turn ends; the card is known as a bystander for that key
--   assassin   the game is lost
-- A turn also ends with End turn. The givers alternate, except that a player
-- whose agents are all found gives no more clues. Find all 15 agents within
-- the turns allowed.
--
-- Everything is rebuilt from the log of entries (as both readers enter the
-- same ones, they agree), so Undo drops the last entry.
-- ---------------------------------------------------------------------------

local Duo = require("duo")

local DuoBoard = {}
DuoBoard.__index = DuoBoard

DuoBoard.SIZE = 25
DuoBoard.LANGS = { "fr", "en" }
DuoBoard.TURNS = { 11, 9 }    -- relaxed, standard
DuoBoard.NVARIANTS = #DuoBoard.LANGS * #DuoBoard.TURNS

-- { key 1, key 2, count }; "a" agent, "b" bystander, "x" assassin.
DuoBoard.KINDS = {
    { "a", "a", 3 }, { "a", "b", 5 }, { "b", "a", 5 }, { "a", "x", 1 }, { "x", "a", 1 },
    { "x", "x", 1 }, { "x", "b", 1 }, { "b", "x", 1 }, { "b", "b", 7 },
}

-- Variant 1..4 <-> language and number of turns.
function DuoBoard.variantOf(lang, turns_index)
    local li = lang == "en" and 2 or 1
    return (turns_index - 1) * #DuoBoard.LANGS + li
end

function DuoBoard.splitVariant(v)
    local li = (v - 1) % #DuoBoard.LANGS + 1
    local ti = math.floor((v - 1) / #DuoBoard.LANGS) + 1
    return DuoBoard.LANGS[li], DuoBoard.TURNS[ti], ti
end

-- words: the full word list of the variant's language, in a fixed order
-- (both readers must load the same list). Duplicates are dropped here.
function DuoBoard.new(o, words)
    local self = setmetatable({}, DuoBoard)
    self.seed    = o.seed or 0
    self.variant = o.variant or 1
    self.role    = o.role == 2 and 2 or 1
    self.code    = o.code
    self.log     = o.log or {}
    self.lang, self.turns = DuoBoard.splitVariant(self.variant)

    local rng = Duo.rng(self.seed, "doubleagents")
    local pool, seen = {}, {}
    for _i, w in ipairs(words) do
        if not seen[w] then
            seen[w] = true
            pool[#pool + 1] = w
        end
    end
    assert(#pool >= DuoBoard.SIZE, "need at least 25 words")
    -- Partial Fisher-Yates: the first 25 of a shuffled copy.
    for i = 1, DuoBoard.SIZE do
        local j = rng:random(i, #pool)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local kinds = {}
    for _i, k in ipairs(DuoBoard.KINDS) do
        for _j = 1, k[3] do kinds[#kinds + 1] = { k[1], k[2] } end
    end
    rng:shuffle(kinds)
    self.cards = {}
    for i = 1, DuoBoard.SIZE do
        self.cards[i] = { word = pool[i], key = { kinds[i][1], kinds[i][2] } }
    end
    self:replay()
    return self
end

function DuoBoard:serialize()
    return { seed = self.seed, variant = self.variant, role = self.role, code = self.code, log = self.log }
end

function DuoBoard.valid(t)
    return type(t) == "table" and type(t.seed) == "number" and type(t.variant) == "number"
        and t.variant >= 1 and t.variant <= DuoBoard.NVARIANTS and type(t.log) == "table"
end

-- What card i is on player p's key: "a", "b" or "x".
function DuoBoard:keyOf(i, p)
    return self.cards[i].key[p]
end

function DuoBoard:agentsTotal()
    local n = 0
    for _i, c in ipairs(self.cards) do
        if c.key[1] == "a" or c.key[2] == "a" then n = n + 1 end
    end
    return n
end

-- Agents of player p's key still to find.
function DuoBoard:agentsLeft(p)
    local n = 0
    for i, c in ipairs(self.cards) do
        if c.key[p] == "a" and not self.found[i] then n = n + 1 end
    end
    return n
end

function DuoBoard:replay()
    self.found = {}           -- i -> true
    self.bystander = { {}, {} }  -- [p][i]: known bystander on p's key
    self.turn = 1             -- turns started
    self.giver = 1            -- player giving the clue this turn
    self.result = nil         -- nil | "won" | "assassin" | "turns"
    self.last = nil
    for _i, ev in ipairs(self.log) do
        if self.result then break end
        if ev.kind == "reveal" then
            self:_reveal(ev.i)
        elseif ev.kind == "pass" then
            self:_endTurn()
        end
    end
end

function DuoBoard:_nextGiver()
    local other = 3 - self.giver
    -- Nothing left to clue for on the other key: the same player goes on.
    if self:agentsLeft(other) == 0 then return self.giver end
    if self:agentsLeft(self.giver) == 0 then return other end
    return other
end

function DuoBoard:_endTurn()
    if self.turn >= self.turns then
        self.result = "turns"
        return
    end
    self.turn = self.turn + 1
    self.giver = self:_nextGiver()
end

function DuoBoard:_reveal(i)
    local k = self:keyOf(i, self.giver)
    self.last = { i = i, kind = k, giver = self.giver }
    if k == "x" then
        self.result = "assassin"
    elseif k == "a" then
        self.found[i] = true
        if self:agentsLeft(1) + self:agentsLeft(2) == 0 then
            self.result = "won"
        elseif self:agentsLeft(self.giver) == 0 then
            -- Nothing left to guess on this key: the turn is over.
            self:_endTurn()
        end
    else
        self.bystander[self.giver][i] = true
        self:_endTurn()
    end
end

function DuoBoard:isOver()
    return self.result ~= nil
end

-- Can card i be guessed this turn?
function DuoBoard:canReveal(i)
    if self:isOver() or not self.cards[i] then return false end
    if self.found[i] then return false end
    if self.bystander[self.giver][i] then return false end
    return true
end

-- The guess is i: returns what it was on the giver's key ("a", "b", "x"),
-- or nil when it cannot be guessed.
function DuoBoard:reveal(i)
    if not self:canReveal(i) then return nil end
    self.log[#self.log + 1] = { kind = "reveal", i = i }
    self:replay()
    return self.last.kind
end

function DuoBoard:pass()
    if self:isOver() then return false end
    self.log[#self.log + 1] = { kind = "pass" }
    self:replay()
    return true
end

function DuoBoard:undo()
    if #self.log == 0 then return false end
    table.remove(self.log)
    self:replay()
    return true
end

function DuoBoard:foundCount()
    local n = 0
    for _i in pairs(self.found) do n = n + 1 end
    return n
end

function DuoBoard:myClue()
    return self.giver == self.role
end

return DuoBoard
