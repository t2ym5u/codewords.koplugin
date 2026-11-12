local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer      = require("ffi/blitbuffer")
local ButtonDialog    = require("ui/widget/buttondialog")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local Duo        = require("duo")
local ScreenBase = require("screen_base")
local DuoBoard   = lrequire("duo_board")
local CodeGrid   = lrequire("grid")

local RULES_EN = [[
Double Agents — Code Words for two readers

Two players, one reader each, playing together. Both readers show the same 25 words. Each one also shows its own player's secret key: 9 of the words are your agents (black cards) and 3 are assassins (crossed out). The two keys are different but overlap: 15 agents to find in all.

Starting
• One player taps New game → Start a game and reads the code aloud. The other taps New game → Join a game and types it. One is player 1, the other player 2. The code carries the language of the words and the number of turns.
• Both readers need the same version of the game, so that they deal the same words.

A turn
• Player 1 gives the first clue: one word and a number ("ocean 2"), to point at agents of their own key. The other player guesses, one word at a time.
• Both players tap the guessed word on their own reader (tap twice to confirm), so both readers stay in step. The guess is judged on the key of the player who gave the clue:
  – an agent: found! Keep guessing if you like;
  – a bystander: the turn is over;
  – an assassin: the game is lost.
• End turn (on both readers) stops guessing. Then the other player gives a clue.
• A small triangle in a card's corner means the other player's key says bystander there.

Find all 15 agents before the turns run out (11 or 9). Undo takes back the last entry — on both readers.
]]

local RULES_FR = [[
Agents doubles — Mots de code à deux liseuses

Deux joueurs, une liseuse chacun, dans la même équipe. Les deux liseuses affichent les mêmes 25 mots. Chacune montre aussi la clé secrète de son joueur : 9 mots sont vos agents (cartes noires) et 3 sont des assassins (barrés). Les deux clés sont différentes mais se recoupent : 15 agents à trouver en tout.

Pour commencer
• Un joueur touche Nouvelle partie → Lancer une partie et lit le code à voix haute. L'autre touche Nouvelle partie → Rejoindre une partie et le saisit. L'un est le joueur 1, l'autre le joueur 2. Le code porte la langue des mots et le nombre de tours.
• Les deux liseuses doivent avoir la même version du jeu, pour tirer les mêmes mots.

Un tour
• Le joueur 1 donne le premier indice : un mot et un nombre (« océan 2 »), pour désigner des agents de sa clé. L'autre joueur devine, un mot à la fois.
• Les deux joueurs touchent le mot proposé sur leur liseuse (deux fois pour confirmer), pour que les deux liseuses restent synchronisées. La proposition est jugée sur la clé de celui qui a donné l'indice :
  – un agent : trouvé ! Continuez si vous voulez ;
  – un passant : le tour est fini ;
  – un assassin : la partie est perdue.
• Fin du tour (sur les deux liseuses) arrête les propositions. L'autre joueur donne alors un indice.
• Un petit triangle dans le coin d'une carte signifie que la clé de l'autre joueur y voit un passant.

Trouvez les 15 agents avant la fin des tours (11 ou 9). Annuler reprend la dernière saisie — sur les deux liseuses.
]]

local PACK_ORDER = { "classic", "history", "geography", "pop", "science", "food", "kids" }
local TURN_NAMES = { "11 turns (relaxed)", "9 turns (standard)" }

-- Every word of a language, in a fixed order: both readers must build the
-- same list to deal the same grid.
local function loadWords(lang)
    local list = {}
    for _i, id in ipairs(PACK_ORDER) do
        local chunk = loadfile(_dir .. "words/" .. lang .. "/" .. id .. ".lua")
        local ok, words = pcall(chunk or error)
        if ok and type(words) == "table" then
            for _j, w in ipairs(words) do list[#list + 1] = w end
        end
    end
    return list
end

-- ---------------------------------------------------------------------------
-- DuoGrid -- the 25 words with this player's key and what has been found.
-- ---------------------------------------------------------------------------

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local DARK  = Blitbuffer.COLOR_DARK_GRAY
local GRAY  = Blitbuffer.COLOR_GRAY

local function frame(bb, x, y, w, h, t, color)
    bb:paintRect(x, y, w, t, color)
    bb:paintRect(x, y + h - t, w, t, color)
    bb:paintRect(x, y, t, h, color)
    bb:paintRect(x + w - t, y, t, h, color)
end

local DuoGrid = CodeGrid:extend{
    duo      = nil,     -- the DuoBoard
    selected = nil,     -- function() -> card index waiting for a second tap
}

function DuoGrid:paintCard(bb, i, rect)
    local b = self.duo
    local card = b.cards[i]
    local mine = card.key[b.role]
    local x, y, w, h = rect.x, rect.y, rect.w, rect.h
    local thin  = math.max(1, math.floor(w / 90))
    local thick = math.max(3, math.floor(w / 22))
    if b.found[i] then
        -- Found: covered, like a card with a token on it.
        bb:paintRect(x, y, w, h, GRAY)
        self:paintWord(bb, rect, card.word, WHITE)
    elseif mine == "a" then
        bb:paintRect(x, y, w, h, BLACK)
        self:paintWord(bb, rect, card.word, WHITE)
    elseif mine == "x" then
        bb:paintRect(x, y, w, h, BLACK)
        local n = math.max(w, h)
        for s = 0, n do
            local px = x + thick + math.floor(s * (w - 3 * thick) / n)
            bb:paintRect(px, y + thick + math.floor(s * (h - 3 * thick) / n), thick, thick, WHITE)
            bb:paintRect(px, y + h - 2 * thick - math.floor(s * (h - 3 * thick) / n), thick, thick, WHITE)
        end
        self:paintWord(bb, rect, card.word, WHITE, BLACK)
    else
        bb:paintRect(x, y, w, h, WHITE)
        frame(bb, x, y, w, h, thin * 2, BLACK)
        self:paintWord(bb, rect, card.word, BLACK)
    end
    -- The other player's key says bystander here: a corner triangle.
    if not b.found[i] and b.bystander[3 - b.role][i] then
        local s = math.floor(math.min(w, h) * 0.26)
        local c = (mine == "a" or mine == "x") and WHITE or DARK
        for j = 0, s - 1 do bb:paintRect(x, y + j, s - j, 1, c) end
    end
    if self.selected and self.selected() == i then
        frame(bb, x, y, w, h, thick, DARK)
        frame(bb, x + thick, y + thick, w - 2 * thick, h - 2 * thick, math.max(1, math.floor(thick / 2)), WHITE)
    end
end

-- ---------------------------------------------------------------------------
-- DuoScreen
-- ---------------------------------------------------------------------------

local DuoScreen = ScreenBase:extend{}

local STATE_KEY = "duo_state"

function DuoScreen:init()
    local saved = self.plugin:loadState(STATE_KEY)
    if DuoBoard.valid(saved) then
        local lang = DuoBoard.splitVariant(saved.variant)
        self.board = DuoBoard.new(saved, loadWords(lang))
        collectgarbage()
    end
    ScreenBase.init(self)
end

function DuoScreen:save()
    self.plugin:saveState(self.board and self.board:serialize() or nil, STATE_KEY)
end

-- The solo game's save stays under the default key: ScreenBase's
-- closeScreen would write this mode's state over it.
function DuoScreen:closeScreen()
    self:save()
    self.plugin:onScreenClosed()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
end

function DuoScreen:isRoundOver()
    return not self.board or self.board:isOver()
end

function DuoScreen:rebuild()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function DuoScreen:buildLayout()
    local title_bar = self:buildTitleBar(_("Double Agents"), function()
        local items = {
            { text = _("New game"), callback = function() self:onNewGame() end },
            { text = T(_("Turns: %1"), _(TURN_NAMES[self.plugin:getSetting("duo_turns", 2)])),
              callback = function() self:openTurnsMenu() end },
        }
        if self.board then
            items[#items + 1] = { text = _("Show the game code"), callback = function() self:showCode() end }
        end
        items[#items + 1] = self:makeRulesButtonConfig(RULES_EN, RULES_FR)
        return items
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local rows = {}
    if self.board then
        rows = { {
            { text = _("End turn"), callback = function() self:onEndTurn() end },
            { text = _("Undo"),     callback = function() self:onUndo() end },
        } }
    end
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar(rows),
    }
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local content
    if self.board then
        self.grid = DuoGrid:new{
            board    = self.board,     -- CodeGrid reads board.cards for its size
            duo      = self.board,
            width    = bw,
            height   = bh,
            selected = function() return self.pending end,
            on_tap   = function(i) self:onCardTap(i) end,
        }
        content = self.grid
    else
        self.grid = nil
        content = TextBoxWidget:new{
            text = _("Each player needs a reader with this game. One starts a game and reads the code aloud; the other joins with that code."),
            face = Font:getFace("infofont"),
            width = math.min(bw, Device.screen:scaleBySize(500)),
            alignment = "center",
        }
    end
    local frame_w = FrameContainer:new{ padding = 0, margin = 0, bordersize = 0, content }
    if self:isLandscape() then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center", frame_w, HorizontalSpan:new{ width = self:getGutter() }, controls,
        })
    else
        self:buildPortraitLayout(title_bar, frame_w,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

function DuoScreen:updateStatus(message)
    local b = self.board
    local status = message
    if not status then
        if not b then
            status = _("Start or join a game.")
        elseif b.result == "won" then
            status = T(_("All 15 agents found in %1 turns. You win together!"), b.turn)
        elseif b.result == "assassin" then
            status = _("An assassin! The game is lost.")
        elseif b.result == "turns" then
            status = T(_("Out of turns: %1 agents still hidden."), b:agentsTotal() - b:foundCount())
        else
            status = self:joinStatus(
                T(_("Turn %1/%2"), b.turn, b.turns),
                b:myClue() and _("Your clue") or _("Your partner's clue: guess"),
                T(_("Agents: %1/%2"), b:foundCount(), b:agentsTotal()))
        end
    end
    ScreenBase.updateStatus(self, status)
end

function DuoScreen:onCardTap(i)
    local b = self.board
    if b:isOver() then return end
    if not b:canReveal(i) then
        self.pending = nil
        self:rebuild()
        self:updateStatus(T(_("%1 cannot be guessed this turn."), b.cards[i].word))
        return
    end
    if self.pending ~= i then
        self.pending = i
        self:rebuild()
        self:updateStatus(T(_("Tap %1 again to guess it."), b.cards[i].word))
        return
    end
    self.pending = nil
    local word = b.cards[i].word
    local kind = b:reveal(i)
    self:save()
    self:rebuild()
    self:refreshActionBar()
    if kind == "a" then
        if not b:isOver() then self:updateStatus(T(_("%1: an agent! Keep guessing or end the turn."), word)) end
    elseif kind == "b" then
        self:showMessage(T(_("%1: a bystander. The turn is over."), word), 3)
    elseif kind == "x" then
        self:showMessage(T(_("%1: an assassin! The game is lost."), word), 5)
    end
    if b.result == "won" then self:showMessage(_("All 15 agents found. You win together!"), 5) end
    if b.result == "turns" then self:showMessage(_("Out of turns: the game is lost."), 5) end
end

function DuoScreen:onEndTurn()
    local b = self.board
    if not b:pass() then return end
    self.pending = nil
    self:save()
    self:rebuild()
    self:refreshActionBar()
    if b.result == "turns" then self:showMessage(_("Out of turns: the game is lost."), 5) end
end

function DuoScreen:onUndo()
    if not self.board:undo() then
        self:updateStatus(_("Nothing to undo."))
        return
    end
    self.pending = nil
    self:save()
    self:rebuild()
    self:refreshActionBar()
end

function DuoScreen:onNewGame()
    local lang = self.plugin:getLang({ "fr", "en" })
    Duo.newGameDialog{
        title     = _("Double Agents"),
        nvariants = DuoBoard.NVARIANTS,
        variant   = DuoBoard.variantOf(lang, self.plugin:getSetting("duo_turns", 2)),
        variant_text = function(v)
            local l, _turns, ti = DuoBoard.splitVariant(v)
            return self:joinStatus(l == "fr" and "Français" or "English", _(TURN_NAMES[ti]))
        end,
        roles = {
            { id = 1, text = T(_("Player %1"), 1) },
            { id = 2, text = T(_("Player %1"), 2) },
        },
        on_start = function(game)
            local l = DuoBoard.splitVariant(game.variant)
            self.board = DuoBoard.new({ seed = game.seed, variant = game.variant, role = game.role,
                code = game.code }, loadWords(l))
            collectgarbage()
            self.pending = nil
            self:save()
            self:rebuild()
        end,
    }
end

function DuoScreen:showCode()
    local b = self.board
    local _l, _turns, ti = DuoBoard.splitVariant(b.variant)
    self:showMessage(T(_("Game code: %1"), Duo.format(b.code)) .. "\n"
        .. self:joinStatus(b.lang == "fr" and "Français" or "English", _(TURN_NAMES[ti])), 6)
end

function DuoScreen:openTurnsMenu()
    local dlg
    local buttons = {}
    for i, name in ipairs(TURN_NAMES) do
        buttons[#buttons + 1] = { {
            text = _(name),
            callback = function()
                UIManager:close(dlg)
                self.plugin:saveSetting("duo_turns", i)
            end,
        } }
    end
    dlg = ButtonDialog:new{ title = _("Turns of the games you start"), buttons = buttons }
    UIManager:show(dlg)
end

return DuoScreen
