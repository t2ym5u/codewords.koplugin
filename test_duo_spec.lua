package.path = "./?.lua;./common/?.lua;" .. package.path
local DuoBoard = dofile("duo_board.lua")

local function words(lang)
    local list = {}
    for _, id in ipairs({ "classic", "history", "geography", "pop", "science", "food", "kids" }) do
        for _, w in ipairs(dofile("words/" .. lang .. "/" .. id .. ".lua")) do list[#list + 1] = w end
    end
    return list
end

local function cardsOf(b, k1, k2)
    local t = {}
    for i, c in ipairs(b.cards) do
        if c.key[1] == k1 and (k2 == nil or c.key[2] == k2) then t[#t + 1] = i end
    end
    return t
end

describe("Double Agents deal", function()
    it("deals the same words and keys on both readers, with the right mix", function()
        local list = words("fr")
        for seed = 0, 20 do
            local p1 = DuoBoard.new({ seed = seed, variant = 1, role = 1 }, list)
            local p2 = DuoBoard.new({ seed = seed, variant = 1, role = 2 }, list)
            assert.same(p1.cards, p2.cards)
            local seen = {}
            for _, c in ipairs(p1.cards) do
                assert.is_nil(seen[c.word])
                seen[c.word] = true
            end
            assert.equals(15, p1:agentsTotal())
            for p = 1, 2 do
                local agents, assassins = 0, 0
                for _, c in ipairs(p1.cards) do
                    if c.key[p] == "a" then agents = agents + 1 end
                    if c.key[p] == "x" then assassins = assassins + 1 end
                end
                assert.equals(9, agents)
                assert.equals(3, assassins)
            end
            assert.equals(3, #cardsOf(p1, "a", "a"))
        end
    end)

    it("reads language and turns from the variant", function()
        for v = 1, DuoBoard.NVARIANTS do
            local lang, turns, ti = DuoBoard.splitVariant(v)
            assert.equals(v, DuoBoard.variantOf(lang, ti))
            assert.is_true(turns == 9 or turns == 11)
        end
        assert.equals("en", (DuoBoard.splitVariant(DuoBoard.variantOf("en", 2))))
    end)
end)

describe("Double Agents play", function()
    local list = words("en")

    it("wins when all 15 agents are found", function()
        local b = DuoBoard.new({ seed = 3, variant = 2, role = 1 }, list)
        local guard = 0
        while not b:isOver() and guard < 100 do
            guard = guard + 1
            local g = b.giver
            local target
            for i, c in ipairs(b.cards) do
                if c.key[g] == "a" and b:canReveal(i) then target = i break end
            end
            assert.is_number(target)
            assert.equals("a", b:reveal(target))
        end
        assert.equals("won", b.result)
        assert.is_true(b.turn <= 2)
    end)

    it("ends the turn on a bystander and loses on an assassin", function()
        local b = DuoBoard.new({ seed = 4, variant = 1, role = 2 }, list)
        local by = cardsOf(b, "b")[1]
        assert.equals("b", b:reveal(by))
        assert.equals(2, b.turn)
        assert.equals(2, b.giver)
        assert.is_true(b.bystander[1][by])
        -- The same card can still be guessed on the other key's turn.
        if b.cards[by].key[2] ~= "a" then assert.is_true(b:canReveal(by) or b.cards[by].key[2] == "b") end
        local x = cardsOf(b, nil)[1]
        for i, c in ipairs(b.cards) do if c.key[2] == "x" then x = i break end end
        assert.equals("x", b:reveal(x))
        assert.equals("assassin", b.result)
        assert.is_true(b:undo())
        assert.is_nil(b.result)
    end)

    it("loses when the turns run out", function()
        local b = DuoBoard.new({ seed = 5, variant = 3, role = 1 }, list)
        assert.equals(9, b.turns)
        for _ = 1, 9 do b:pass() end
        assert.equals("turns", b.result)
        assert.is_false(b:pass())
    end)

    it("keeps both readers in step when they enter the same guesses", function()
        local p1 = DuoBoard.new({ seed = 6, variant = 1, role = 1 }, list)
        local p2 = DuoBoard.new({ seed = 6, variant = 1, role = 2 }, list)
        local entries = { { "reveal", 1 }, { "reveal", 7 }, { "pass" }, { "reveal", 12 }, { "reveal", 3 } }
        for _, e in ipairs(entries) do
            if e[1] == "pass" then p1:pass(); p2:pass() else p1:reveal(e[2]); p2:reveal(e[2]) end
        end
        assert.same(p1.found, p2.found)
        assert.equals(p1.turn, p2.turn)
        assert.equals(p1.giver, p2.giver)
        assert.equals(p1:myClue(), not p2:myClue())
    end)

    it("saves its log and rebuilds the same game", function()
        local b = DuoBoard.new({ seed = 7, variant = 2, role = 1, code = "12345" }, list)
        b:reveal(2)
        b:pass()
        local t = b:serialize()
        assert.is_true(DuoBoard.valid(t))
        local b2 = DuoBoard.new(t, list)
        assert.same(b.found, b2.found)
        assert.equals(b.turn, b2.turn)
        assert.is_false(DuoBoard.valid({ seed = 1, variant = 9, log = {} }))
    end)
end)
