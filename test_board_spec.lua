local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

local Board = dofile(DIR .. "board.lua")

-- Deterministic rng: a simple LCG returning 1..n.
local function lcg(seed)
    local s = seed
    return function(n)
        s = (s * 1103515245 + 12345) % 2147483648
        return (s % n) + 1
    end
end

local function words(n)
    local t = {}
    for i = 1, n do t[i] = "w" .. i end
    return t
end

local function countRoles(b)
    local c = { red = 0, blue = 0, neutral = 0, assassin = 0 }
    for _, card in ipairs(b.cards) do c[card.role] = c[card.role] + 1 end
    return c
end

local function find(b, role, revealed)
    for i, card in ipairs(b.cards) do
        if card.role == role and (revealed == nil or card.revealed == revealed) then return i end
    end
end

describe("codewords board", function()
    it("deals 25 distinct words with a 9/8/7/1 key", function()
        for seed = 1, 50 do
            local b = Board.new(words(100), { rng = lcg(seed) })
            assert.are.equal(25, #b.cards)
            local seen = {}
            for _, c in ipairs(b.cards) do
                assert.is_nil(seen[c.word]); seen[c.word] = true
                assert.is_false(c.revealed)
            end
            local c = countRoles(b)
            assert.are.equal(9, c[b.first])
            assert.are.equal(8, c[Board.other(b.first)])
            assert.are.equal(7, c.neutral)
            assert.are.equal(1, c.assassin)
            assert.are.equal(b.first, b.turn)
        end
    end)

    it("ignores duplicate words in the list", function()
        local list = words(30)
        for i = 1, 30 do list[#list + 1] = "w" .. i end
        local b = Board.new(list, { rng = lcg(3) })
        local seen = {}
        for _, c in ipairs(b.cards) do assert.is_nil(seen[c.word]); seen[c.word] = true end
    end)

    it("keeps the turn on an own agent and passes it otherwise", function()
        local b = Board.new(words(40), { rng = lcg(5), first = "red" })
        local res = b:reveal(find(b, "red"))
        assert.are.equal("red", res.role)
        assert.is_false(res.turn_ended)
        assert.are.equal("red", b.turn)
        res = b:reveal(find(b, "neutral"))
        assert.is_true(res.turn_ended)
        assert.are.equal("blue", b.turn)
        res = b:reveal(find(b, "red", false))
        assert.is_true(res.turn_ended)
        assert.are.equal("red", b.turn)
        assert.is_nil(b:reveal(find(b, "red", true)), "a revealed card can't be revealed again")
    end)

    it("loses on the assassin", function()
        local b = Board.new(words(40), { rng = lcg(9), first = "blue" })
        local res = b:reveal(find(b, "assassin"))
        assert.are.equal("red", res.winner)
        assert.are.equal("assassin", res.reason)
        assert.is_true(b:isOver())
        assert.is_nil(b:reveal(find(b, "neutral")), "no move after the end")
        assert.is_false(b:endTurn())
    end)

    it("wins when the last agent is revealed, even by the other team", function()
        local b = Board.new(words(40), { rng = lcg(11), first = "red" })
        -- Red reveals 8 of its 9, then Blue's turn reveals red's last one.
        for _ = 1, 8 do b:reveal(find(b, "red", false)); b.turn = "red" end
        b:endTurn()
        assert.are.equal("blue", b.turn)
        local res = b:reveal(find(b, "red", false))
        assert.are.equal("red", res.winner)
        assert.are.equal("agents", res.reason)
    end)

    it("ends the turn after clue number + 1 guesses", function()
        local b = Board.new(words(40), { rng = lcg(13), first = "red" })
        b:setClue("ocean", 1)
        assert.are.equal(2, b:guessesLeft())
        b:reveal(find(b, "red", false))
        assert.are.equal(1, b:guessesLeft())
        local res = b:reveal(find(b, "red", false))
        assert.is_true(res.turn_ended)
        assert.is_true(res.limit)
        assert.are.equal("blue", b.turn)
        assert.is_nil(b.clue, "the clue is cleared at the turn change")
    end)

    it("parses clues", function()
        assert.are.same({ "ocean", 2 }, { Board.parseClue("ocean 2") })
        assert.are.same({ "big apple", 3 }, { Board.parseClue("  big apple 3 ") })
        assert.are.same({ "ocean" }, { Board.parseClue("ocean") })
        assert.are.same({ "ocean" }, { Board.parseClue("ocean 0") })
        assert.are.same({ "ocean" }, { Board.parseClue("ocean ∞") })
        assert.is_nil(Board.parseClue("   "))
    end)

    it("round-trips through serialize", function()
        local b = Board.new(words(40), { rng = lcg(17) })
        b:setClue("x", 2)
        b:reveal(find(b, b.turn))
        local c = Board.deserialize(b:serialize())
        assert.are.same(b:serialize(), c:serialize())
        assert.is_nil(Board.deserialize({ cards = {} }))
        assert.is_nil(Board.deserialize(nil))
    end)
end)

-- Packs are files words/<lang>/<pack>.lua. A word may sit in two packs (the
-- Kids pack is self-contained); Board.new drops duplicates when packs mix.
local PACKS = { classic = 400, history = 200, geography = 200, pop = 200, science = 200, food = 200, kids = 200 }
local EXCLUDED = { "hitler", "staline", "stalin", "pol pot", "laden", "mussolini", "robespierre", "lénine", "lenin",
    "pinochet", "kadhafi", "gaddafi", "saddam", "capone", "escobar", "caligula", "néron" }

describe("codewords word packs", function()
    for _, lang in ipairs({ "en", "fr" }) do
        it(lang .. ": every pack big enough, short, no duplicates, 1500+ distinct words", function()
            local all, distinct = {}, 0
            for pack, min in pairs(PACKS) do
                local list = dofile(DIR .. "words/" .. lang .. "/" .. pack .. ".lua")
                assert.is_true(#list >= min, lang .. "/" .. pack .. ": only " .. #list)
                local seen = {}
                for _, w in ipairs(list) do
                    assert.is_string(w)
                    local k = w:lower()
                    assert.is_nil(seen[k], lang .. "/" .. pack .. " duplicate: " .. w)
                    seen[k] = true
                    -- byte length, so accented letters count double: a loose cap
                    assert.is_true(#w <= 20, lang .. " too long: " .. w)
                    for _, bad in ipairs(EXCLUDED) do
                        assert.is_nil(k:find(bad, 1, true), lang .. " excluded: " .. w)
                    end
                    if not all[k] then all[k] = true; distinct = distinct + 1 end
                end
            end
            assert.is_true(distinct >= 1500, lang .. ": only " .. distinct .. " distinct words")
        end)
    end

    it("deals a valid grid from any single pack", function()
        for pack in pairs(PACKS) do
            for _, lang in ipairs({ "en", "fr" }) do
                local b = Board.new(dofile(DIR .. "words/" .. lang .. "/" .. pack .. ".lua"), { rng = lcg(1) })
                assert.are.equal(25, #b.cards)
            end
        end
    end)
end)
