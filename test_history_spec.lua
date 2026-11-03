-- Grid words are not repeated: each new grid draws its 25 words through a
-- per-language history kept in the plugin settings (game-common
-- seen_history.lua), so a word only comes back once the selected packs have
-- all been dealt. Also checks the word packs themselves.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. DIR .. "common/?.lua;" .. package.path

local Board       = dofile(DIR .. "board.lua")
local SeenHistory = require("seen_history")

local PACKS = { "classic", "history", "geography", "pop", "science", "food", "kids" }

local function packWords(lang, only)
    local list = {}
    for _i, id in ipairs(only or PACKS) do
        for _j, w in ipairs(dofile(DIR .. "words/" .. lang .. "/" .. id .. ".lua")) do
            list[#list + 1] = w
        end
    end
    return list
end

local function fakePlugin(store)
    store = store or {}
    return {
        store = store,
        getSetting  = function(_self, k, d) local v = store[k]; if v == nil then return d end; return v end,
        saveSetting = function(_self, k, v) store[k] = v end,
    }
end

local function deal(plugin, lang, words)
    local seen = SeenHistory.open(plugin, "words_" .. lang, { max = 3000 })
    return Board.new(Board.dealWords(words, seen))
end

describe("grid word history", function()
    for _i, lang in ipairs({ "en", "fr" }) do
        it(lang .. ": no word repeated across two sessions until the pool is used up", function()
            local words, distinct = packWords(lang), {}
            local n = 0
            for _j, w in ipairs(words) do
                if not distinct[w] then distinct[w] = true; n = n + 1 end
            end
            local grids = math.floor(n / Board.SIZE)
            local store, seen = {}, {}
            for session = 1, 2 do
                local plugin = fakePlugin(store)
                local first, last = session == 1 and 1 or math.floor(grids / 2) + 1, session == 1 and math.floor(grids / 2) or grids
                for _g = first, last do
                    local b = deal(plugin, lang, words)
                    for _k, c in ipairs(b.cards) do
                        assert.is_nil(seen[c.word], c.word)
                        seen[c.word] = true
                    end
                end
            end
            -- The pool is used up: the next grid still deals 25 distinct words.
            local b = deal(fakePlugin(store), lang, words)
            assert.are.equal(Board.SIZE, #b.cards)
        end)
    end

    it("a small pack selection cycles through its own words", function()
        local words = packWords("en", { "kids" })
        local plugin, seen = fakePlugin(), {}
        for _g = 1, math.floor(#words / Board.SIZE) do
            for _k, c in ipairs(deal(plugin, "en", words).cards) do
                assert.is_nil(seen[c.word], c.word)
                seen[c.word] = true
            end
        end
    end)
end)

describe("word packs", function()
    local EXCLUDED = { "hitler", "staline", "stalin", "mussolini", "pol pot", "ben laden", "bin laden",
                       "pinochet", "idi amin", "landru", "jack l'eventreur", "jack the ripper" }
    for _i, lang in ipairs({ "en", "fr" }) do
        it(lang .. ": no duplicate within a pack, no excluded figure", function()
            for _j, id in ipairs(PACKS) do
                local set = {}
                for _k, w in ipairs(packWords(lang, { id })) do
                    assert.is_nil(set[w], id .. ": " .. w)
                    set[w] = true
                    for _m, x in ipairs(EXCLUDED) do
                        assert.is_nil(w:lower():find(x, 1, true), w)
                    end
                end
            end
            assert.is_true(#packWords(lang) > 1700)
        end)
    end
end)
