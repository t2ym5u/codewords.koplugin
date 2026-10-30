-- ---------------------------------------------------------------------------
-- Code Words -- game logic (pure Lua, no UI, so the specs can drive it)
--
-- 25 cards on a 5×5 grid. A hidden key gives each card a role: 9 agents for
-- the starting team, 8 for the other, 7 neutral bystanders and 1 assassin.
-- The team whose turn it is reveals cards one at a time:
--   own agent   -> keeps guessing (up to clue number + 1)
--   other agent -> turn passes
--   neutral     -> turn passes
--   assassin    -> that team loses at once
-- A team wins when its last agent is revealed, even by the other team.
-- ---------------------------------------------------------------------------

local Board = {}
Board.__index = Board

Board.SIZE      = 25
Board.COLS      = 5
Board.FIRST_N   = 9
Board.SECOND_N  = 8
Board.NEUTRAL_N = 7

local function other(team)
    return team == "red" and "blue" or "red"
end
Board.other = other

-- opts.rng(n) -> integer in 1..n (defaults to math.random)
-- opts.first  -> "red" | "blue" (random when nil)
function Board.new(words, opts)
    opts = opts or {}
    local rng = opts.rng or math.random
    assert(type(words) == "table" and #words >= Board.SIZE, "need at least 25 words")

    -- Pick 25 distinct words: partial Fisher-Yates over a copy.
    local pool = {}
    for i, w in ipairs(words) do pool[i] = w end
    local picked, seen = {}, {}
    local n = #pool
    while #picked < Board.SIZE and n > 0 do
        local j = rng(n)
        local w = pool[j]
        pool[j], pool[n] = pool[n], pool[j]
        n = n - 1
        if not seen[w] then
            seen[w] = true
            picked[#picked + 1] = w
        end
    end
    assert(#picked == Board.SIZE, "need at least 25 distinct words")

    local first = opts.first or (rng(2) == 1 and "red" or "blue")
    local roles = {}
    for _ = 1, Board.FIRST_N   do roles[#roles + 1] = first end
    for _ = 1, Board.SECOND_N  do roles[#roles + 1] = other(first) end
    for _ = 1, Board.NEUTRAL_N do roles[#roles + 1] = "neutral" end
    roles[#roles + 1] = "assassin"
    for i = #roles, 2, -1 do
        local j = rng(i)
        roles[i], roles[j] = roles[j], roles[i]
    end

    local self = setmetatable({}, Board)
    self.cards = {}
    for i = 1, Board.SIZE do
        self.cards[i] = { word = picked[i], role = roles[i], revealed = false }
    end
    self.first   = first
    self.turn    = first
    self.clue    = nil      -- { word = "ocean", number = 2 } (number nil = unlimited)
    self.guesses = 0        -- cards revealed this turn
    self.winner  = nil
    self.reason  = nil      -- "agents" | "assassin"
    self.last    = nil      -- index of the last card revealed
    return self
end

function Board:remaining(team)
    local n = 0
    for _, c in ipairs(self.cards) do
        if c.role == team and not c.revealed then n = n + 1 end
    end
    return n
end

function Board:isOver()
    return self.winner ~= nil
end

function Board:setClue(word, number)
    if self:isOver() then return false end
    if not word or word == "" then
        self.clue = nil
    else
        self.clue = { word = word, number = number }
    end
    return true
end

-- Guesses the team may still make this turn, nil when unlimited.
function Board:guessesLeft()
    local c = self.clue
    if not c or not c.number or c.number <= 0 then return nil end
    return math.max(0, c.number + 1 - self.guesses)
end

function Board:endTurn()
    if self:isOver() then return false end
    self.turn    = other(self.turn)
    self.clue    = nil
    self.guesses = 0
    return true
end

-- Returns nil when the card can't be revealed, else a result table:
--   { role = ..., team = <team that guessed>, turn_ended = bool,
--     winner = "red"|"blue"|nil, reason = "agents"|"assassin"|nil,
--     limit = true when the turn ended because the clue number was used up }
function Board:reveal(i)
    local card = self.cards[i]
    if not card or card.revealed or self:isOver() then return nil end
    card.revealed = true
    self.last     = i
    self.guesses  = self.guesses + 1
    local team = self.turn
    local res  = { role = card.role, team = team, turn_ended = false }

    if card.role == "assassin" then
        self.winner, self.reason = other(team), "assassin"
    elseif self:remaining("red") == 0 then
        self.winner, self.reason = "red", "agents"
    elseif self:remaining("blue") == 0 then
        self.winner, self.reason = "blue", "agents"
    elseif card.role ~= team then
        self:endTurn()
        res.turn_ended = true
    elseif self:guessesLeft() == 0 then
        self:endTurn()
        res.turn_ended = true
        res.limit      = true
    end
    res.winner, res.reason = self.winner, self.reason
    return res
end

-- "ocean 2" -> "ocean", 2 ; "ocean" -> "ocean", nil ; "big apple 3" -> "big apple", 3
-- "ocean 0" / "ocean ∞" -> "ocean", nil (unlimited guesses)
function Board.parseClue(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    local word, num = text:match("^(.-)%s+(%d+)$")
    if word and word ~= "" then
        num = tonumber(num)
        if num == 0 then num = nil end
        return word, num
    end
    word = text:match("^(.-)%s+∞$")
    if word and word ~= "" then return word, nil end
    return text, nil
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function Board:serialize()
    local cards = {}
    for i, c in ipairs(self.cards) do
        cards[i] = { word = c.word, role = c.role, revealed = c.revealed }
    end
    return {
        cards   = cards,
        first   = self.first,
        turn    = self.turn,
        clue    = self.clue and { word = self.clue.word, number = self.clue.number } or nil,
        guesses = self.guesses,
        winner  = self.winner,
        reason  = self.reason,
        last    = self.last,
    }
end

function Board.deserialize(t)
    if type(t) ~= "table" or type(t.cards) ~= "table" or #t.cards ~= Board.SIZE then
        return nil
    end
    local self = setmetatable({}, Board)
    self.cards = {}
    for i, c in ipairs(t.cards) do
        if type(c) ~= "table" or type(c.word) ~= "string" then return nil end
        self.cards[i] = { word = c.word, role = c.role, revealed = c.revealed and true or false }
    end
    self.first   = t.first == "blue" and "blue" or "red"
    self.turn    = t.turn == "blue" and "blue" or "red"
    self.clue    = type(t.clue) == "table" and t.clue.word and
                   { word = t.clue.word, number = tonumber(t.clue.number) } or nil
    self.guesses = tonumber(t.guesses) or 0
    self.winner  = t.winner
    self.reason  = t.reason
    self.last    = t.last
    return self
end

return Board
