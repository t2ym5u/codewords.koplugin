local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local InputDialog     = require("ui/widget/inputdialog")
local RenderText      = require("ui/rendertext")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Widget          = require("ui/widget/widget")
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper = require("menu_helper")
local ScreenBase = require("screen_base")
local SeenHistory = require("seen_history")
local Board      = lrequire("board")
local CodeGrid   = lrequire("grid")

local DeviceScreen = Device.screen
local DPI_SCALE = DeviceScreen:scaleBySize(1000) / 1000

local function pxFace(px, name)
    return Font:getFace(name or "cfont", math.max(8, math.floor(px / DPI_SCALE)))
end

-- One line of text at up to `px` pixels, shrunk until it fits `max_w`.
local function fitLine(text, px, max_w, bold)
    local face = pxFace(px)
    while px > 12 do
        local m = RenderText:sizeUtf8Text(0, max_w * 10, face, text, true, bold)
        if m.x <= max_w then break end
        px   = math.floor(px * 0.9)
        face = pxFace(px)
    end
    return TextWidget:new{ text = text, face = face, max_width = max_w, bold = bold }
end

local function wrapText(text, face, width)
    return TextBoxWidget:new{ text = text, face = face, width = width, alignment = "center" }
end

-- ---------------------------------------------------------------------------
-- TapBox -- a fixed-size area that runs `callback` when tapped (the
-- spymaster hand-over screen is one big tap target).
-- ---------------------------------------------------------------------------

local TapBox = InputContainer:extend{
    width = nil, height = nil, callback = nil,
    align = "center", vertical_align = "center",
}

function TapBox:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function TapBox:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function TapBox:onTap()
    if self.callback then self.callback() end
    return true
end

-- ---------------------------------------------------------------------------
-- Swatch -- the small team pattern shown next to each team's count.
-- ---------------------------------------------------------------------------

local Swatch = Widget:extend{ size = 20, role = "red" }

function Swatch:getSize()
    return Geom:new{ w = self.size, h = self.size }
end

function Swatch:paintTo(bb, x, y)
    local s = self.size
    local t = math.max(2, math.floor(s / 8))
    if self.role == "red" then
        bb:paintRect(x, y, s, s, Blitbuffer.COLOR_BLACK)
    else
        bb:paintRect(x, y, s, s, Blitbuffer.COLOR_WHITE)
        for k = -s, s, math.max(4, math.floor(s / 3)) do
            for j = 0, s - 1 do
                local px = x + k + (s - 1 - j)
                if px >= x and px + t <= x + s then
                    bb:paintRect(px, y + j, t, 1, Blitbuffer.COLOR_DARK_GRAY)
                end
            end
        end
        bb:paintRect(x, y, s, t, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x, y + s - t, s, t, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x, y, t, s, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x + s - t, y, t, s, Blitbuffer.COLOR_BLACK)
    end
end

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = [[
Code Words — Rules

Two teams, Red and Blue. Each team picks one spymaster; everybody else is a field operative.

The grid holds 25 words. A secret key says which words are Red agents, which are Blue agents, which are neutral bystanders, and which one is the assassin. The starting team has 9 agents, the other 8.

Only the spymasters may see the key: tap "Show key", make sure operatives look away, then tap the screen. Any tap hides the key again.

On its turn, a team's spymaster gives a one-word clue and a number ("ocean 2"), linking that many of their team's words. Tap "Clue" to show it in the status line. Operatives then tap words to reveal them:
• their own agent: they may keep guessing, up to the number + 1;
• a neutral word or an enemy agent: the turn ends;
• the assassin: their team loses at once.
"End turn" stops guessing early.

A team wins when all its agents are revealed — even if the other team revealed the last one.

How cards look once revealed:
• Red agent: solid black card.
• Blue agent: striped card with a thick border.
• Neutral: light grey card.
• Assassin: black card with a white X.
In the key view, a notch in the corner marks words already revealed.
]]

local GAME_RULES_FR = [[
Mots de code — Règles

Deux équipes, Rouge et Bleue. Chaque équipe désigne un maître-espion ; les autres sont les agents de terrain.

La grille contient 25 mots. Une carte clé secrète indique quels mots sont des agents rouges, des agents bleus, des passants neutres, et lequel est l'assassin. L'équipe qui commence a 9 agents, l'autre 8.

Seuls les maîtres-espions voient la clé : touchez « Voir la clé », vérifiez que les agents détournent les yeux, puis touchez l'écran. Une nouvelle touche cache la clé.

À son tour, le maître-espion donne un indice d'un seul mot et un nombre (« océan 2 ») qui relie autant de mots de son équipe. Touchez « Indice » pour l'afficher dans la ligne d'état. Les agents touchent ensuite des mots pour les révéler :
• un agent de leur équipe : ils peuvent continuer, jusqu'au nombre + 1 ;
• un passant ou un agent adverse : le tour s'arrête ;
• l'assassin : leur équipe perd immédiatement.
« Fin du tour » arrête les propositions plus tôt.

Une équipe gagne quand tous ses agents sont révélés — même si c'est l'autre équipe qui révèle le dernier.

Aspect des cartes révélées :
• agent rouge : carte noire pleine ;
• agent bleu : carte rayée à bord épais ;
• passant : carte gris clair ;
• assassin : carte noire barrée d'un X blanc.
Dans la vue de la clé, une encoche dans le coin marque les mots déjà révélés.
]]

-- ---------------------------------------------------------------------------
-- CodeWordsScreen
--
-- phase "play": the operatives' grid (and the end of the game);
--       "gate": hand-over before the key is shown;
--       "key":  the key, hidden again by any tap.
-- ---------------------------------------------------------------------------

local CodeWordsScreen = ScreenBase:extend{}

-- Word packs: words/<lang>/<id>.lua, loaded only when a grid is dealt (or
-- counted for the menu).
local PACK_ORDER = { "classic", "history", "geography", "pop", "science", "food", "kids" }

local function packLabel(id)
    local labels = {
        classic   = _("Classic words"),
        history   = _("History & famous people"),
        geography = _("Geography & monuments"),
        pop       = _("Pop culture"),
        science   = _("Science & nature"),
        food      = _("Food"),
        kids      = _("Kids"),
    }
    return labels[id] or id
end

-- Whole sentences per team rather than "%1's turn" templates: French needs
-- the article and the agreement ("l'équipe rouge"), which a team-name
-- placeholder can't carry.
local function turnSentence(team)
    return team == "red" and _("Red team's turn.") or _("Blue team's turn.")
end

local function turnTitle(team)
    return team == "red" and _("Red team's turn") or _("Blue team's turn")
end

local function winTitle(team)
    return team == "red" and _("Red team wins!") or _("Blue team wins!")
end

function CodeWordsScreen:init()
    local default_lang = _.lang() == "fr" and "fr" or "en"
    self.lang  = self.plugin:getSetting("lang", default_lang)
    self.wins  = self.plugin:getSetting("wins", { red = 0, blue = 0 })
    self.packs = self:_loadPackSelection()
    self.phase = "play"
    self.message = nil

    local saved = self.plugin:loadState()
    self.board = saved and Board.deserialize(saved.board)
    if not self.board then self:_newBoard() end
    ScreenBase.init(self)
end

function CodeWordsScreen:_loadPack(id, lang)
    local chunk = loadfile(_dir .. "words/" .. (lang or self.lang) .. "/" .. id .. ".lua")
    if not chunk then return nil end
    local ok, list = pcall(chunk)
    if ok and type(list) == "table" then return list end
end

-- Words of the selected packs (every pack when none is selected, or when the
-- selection is too small for a grid). Board.new drops duplicates.
function CodeWordsScreen:_words(packs)
    local list = {}
    for _i, id in ipairs(PACK_ORDER) do
        if packs == nil or packs[id] then
            for _j, w in ipairs(self:_loadPack(id) or self:_loadPack(id, "en") or {}) do
                list[#list + 1] = w
            end
        end
    end
    if packs ~= nil and #list < 40 then return self:_words(nil) end
    return list
end

function CodeWordsScreen:_loadPackSelection()
    local saved = self.plugin:getSetting("packs", "")
    if not saved or saved == "" then return nil end
    local sel = {}
    for id in saved:gmatch("[^,]+") do sel[id] = true end
    return sel
end

function CodeWordsScreen:_savePackSelection()
    local parts = {}
    for id in pairs(self.packs or {}) do parts[#parts + 1] = id end
    table.sort(parts)
    self.plugin:saveSetting("packs", self.packs and table.concat(parts, ",") or "")
end

function CodeWordsScreen:_packsText()
    if self.packs == nil then return _("Packs: all") end
    local n, last = 0, nil
    for _i, id in ipairs(PACK_ORDER) do
        if self.packs[id] then n = n + 1; last = id end
    end
    if n == 1 then return T(_("Packs: %1"), packLabel(last)) end
    return T(_("Packs: %1"), n .. "/" .. #PACK_ORDER)
end

-- Multi-select, re-opened after each toggle. The new packs apply to the next
-- grid, so a game in progress isn't dealt again under the players' feet.
function CodeWordsScreen:openPacksMenu()
    if not self._counts or self._counts_lang ~= self.lang then
        self._counts, self._counts_lang = {}, self.lang
        for _i, id in ipairs(PACK_ORDER) do
            local list = self:_loadPack(id)
            self._counts[id] = list and #list or 0
        end
        collectgarbage()
    end
    local all = self.packs == nil
    local items = { { id = "__all__", text = (all and "★ " or "  ") .. _("All packs") } }
    for _i, id in ipairs(PACK_ORDER) do
        local on = all or self.packs[id]
        items[#items + 1] = {
            id   = id,
            text = (on and "✓ " or "○ ") .. packLabel(id) .. string.format("  (%d)", self._counts[id]),
        }
    end
    MenuHelper.openPickerMenu{
        title     = _("Packs"),
        items     = items,
        parent    = self,
        on_select = function(id)
            if id == "__all__" then
                self.packs = nil
            elseif self.packs == nil then
                self.packs = { [id] = true }
            else
                self.packs[id] = not self.packs[id] or nil
                local n = 0
                for _j in pairs(self.packs) do n = n + 1 end
                if n == 0 or n == #PACK_ORDER then self.packs = nil end
            end
            self:_savePackSelection()
            local b = self.board
            local fresh = true
            for _j, c in ipairs(b.cards) do if c.revealed then fresh = false end end
            -- Nothing played yet: deal from the new packs right away.
            if fresh or b:isOver() then self:_newBoard(); self:_save() end
            self:_redraw()
            self:openPacksMenu()
        end,
    }
end

-- Words already dealt, per language (game-common seen_history.lua): a new
-- grid takes words not seen yet, so they only come back once the selected
-- packs have all been dealt. Above every language's word count.
local SEEN_MAX = 3000

function CodeWordsScreen:_newBoard()
    local seen = SeenHistory.open(self.plugin, "words_" .. self.lang, { max = SEEN_MAX })
    self.board   = Board.new(Board.dealWords(self:_words(self.packs), seen))
    collectgarbage()
    self.message = nil
    self.phase   = "play"
end

function CodeWordsScreen:serializeState()
    return { board = self.board:serialize() }
end

function CodeWordsScreen:_save()
    self.plugin:saveState(self:serializeState())
end

function CodeWordsScreen:isRoundOver()
    return self.board ~= nil and self.board:isOver()
end

function CodeWordsScreen:_redraw(mode)
    self:buildLayout()
    UIManager:setDirty(self, function() return mode or "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function CodeWordsScreen:onNewGame()
    self:_newBoard()
    self:_save()
    self:_redraw("full")
end

function CodeWordsScreen:onCardTap(i)
    if self.phase == "key" then
        return self:onHideKey()
    end
    if self.phase ~= "play" then return end
    local b = self.board
    local res = b:reveal(i)
    if not res then return end
    local word = b.cards[i].word
    if res.winner then
        self.wins[res.winner] = (self.wins[res.winner] or 0) + 1
        self.plugin:saveSetting("wins", self.wins)
        self.message = nil
    elseif res.role == res.team then
        local left = b:guessesLeft()
        self.message = left and T(_("%1: agent found! Guesses left: %2"), word, left)
                             or T(_("%1: agent found!"), word)
        if res.limit then
            self.message = T(_("%1: agent found! No guesses left."), word) .. " " .. turnSentence(b.turn)
        end
    elseif res.role == "neutral" then
        self.message = T(_("%1: bystander."), word) .. " " .. turnSentence(b.turn)
    else
        self.message = T(_("%1: enemy agent!"), word) .. " " .. turnSentence(b.turn)
    end
    self:_save()
    self:_redraw()
end

function CodeWordsScreen:onEndTurn()
    if self.board:endTurn() then
        self.message = turnSentence(self.board.turn)
        self:_save()
        self:_redraw()
    end
end

function CodeWordsScreen:onClue()
    local dialog
    local cur = self.board.clue
    dialog = InputDialog:new{
        title      = self.board.turn == "red" and _("Clue for the Red team") or _("Clue for the Blue team"),
        input      = cur and (cur.word .. (cur.number and (" " .. cur.number) or "")) or "",
        input_hint = _("word and number, e.g. ocean 2"),
        buttons    = {
            {
                {
                    text     = _("Cancel"),
                    id       = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("OK"),
                    is_enter_default = true,
                    callback = function()
                        local word, num = Board.parseClue(dialog:getInputText())
                        UIManager:close(dialog)
                        self.board:setClue(word, num)
                        self.message = nil
                        self:_save()
                        self:_redraw()
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function CodeWordsScreen:onShowKeyGate()
    self.phase = "gate"
    self:_redraw("full")
end

function CodeWordsScreen:onShowKey()
    self.phase = "key"
    self:_redraw("full")
end

function CodeWordsScreen:onHideKey()
    self.phase = "play"
    -- A full refresh, so no ghost of the key lingers on the e-ink panel.
    self:_redraw("full")
end

function CodeWordsScreen:onResetScores()
    self.wins = { red = 0, blue = 0 }
    self.plugin:saveSetting("wins", self.wins)
    self:_redraw()
end

function CodeWordsScreen:openLangMenu()
    MenuHelper.openPickerMenu{
        title      = _("Language"),
        items      = { { id = "fr", text = "Français" }, { id = "en", text = "English" } },
        current_id = self.lang,
        parent     = self,
        on_select  = function(lang)
            if lang == self.lang then return end
            self.lang = lang
            self.plugin:saveSetting("lang", lang)
            -- The words on the grid are the old language's: deal a new grid.
            self:onNewGame()
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function CodeWordsScreen:_titleBar()
    return self:buildTitleBar(_("Code Words"), function()
        return {
            { text = _("New game"), callback = function() self:onNewGame() end },
            { text = T(_("Language: %1"), self.lang:upper()), callback = function() self:openLangMenu() end },
            { text = self:_packsText(), callback = function() self:openPacksMenu() end },
            { text = _("Reset scores"), callback = function() self:onResetScores() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)
end

function CodeWordsScreen:_buildControls(rows)
    self.status_text:setMaxWidth(self:getControlsWidth())
    return VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar(rows),
    }
end

function CodeWordsScreen:_controlRows()
    if self.phase == "gate" then
        return {
            { text = _("Cancel"),   callback = function() self:onHideKey() end },
            { text = _("Show key"), callback = function() self:onShowKey() end },
        }
    elseif self.phase == "key" then
        return { { text = _("Hide key"), callback = function() self:onHideKey() end } }
    end
    local row = {
        { text = _("Clue"),     callback = function() self:onClue() end },
        { text = _("Show key"), callback = function() self:onShowKeyGate() end },
        { text = _("End turn"), callback = function() self:onEndTurn() end },
    }
    -- The landscape side panel is too narrow for three labels side by side.
    if self:isLandscape() then
        return { { row[1] }, { row[2] }, { row[3] } }
    end
    return row
end

-- "Red team's turn" / "Red team wins!" / "Key — tap to hide"
function CodeWordsScreen:_bannerText()
    local b = self.board
    if b:isOver() then
        if b.reason == "assassin" then
            return _("Assassin!") .. " " .. winTitle(b.winner)
        end
        return winTitle(b.winner)
    end
    if self.phase == "key" then return _("Key — tap to hide") end
    return turnTitle(b.turn)
end

function CodeWordsScreen:_countsRow(width, px)
    local b = self.board
    local face = pxFace(px)
    local sw = math.floor(px * 1.1)
    local function part(team)
        local label = T(team == "red" and _("Red: %1 to find") or _("Blue: %1 to find"), b:remaining(team))
        return HorizontalGroup:new{
            align = "center",
            Swatch:new{ size = sw, role = team },
            HorizontalSpan:new{ width = math.floor(px * 0.4) },
            TextWidget:new{ text = label, face = face, bold = (b.turn == team and not b:isOver()) },
        }
    end
    return HorizontalGroup:new{
        align = "center",
        part("red"),
        HorizontalSpan:new{ width = math.floor(px * 2) },
        part("blue"),
    }
end

function CodeWordsScreen:buildLayout()
    local title_bar = self:_titleBar()
    local controls  = self:_buildControls(self:_controlRows())
    local bw, bh    = self:getBoardBudget(title_bar, controls)
    local vs        = Size.span.vertical_default
    local short     = math.min(bw, bh)

    local banner_px = math.floor(math.min(short * 0.075, bw * 0.07))
    local counts_px = math.floor(banner_px * 0.6)
    local banner = fitLine(self:_bannerText(), banner_px, bw, true)
    local counts = self:_countsRow(bw, counts_px)
    local head_h = banner:getSize().h + vs + counts:getSize().h + 2 * vs

    local body
    if self.phase == "gate" then
        local gw, gh = bw, bh - head_h
        local inner_w = gw - 4 * Size.padding.large
        body = TapBox:new{
            width = gw, height = gh,
            callback = function() self:onShowKey() end,
            FrameContainer:new{
                bordersize = Size.border.thick,
                padding    = Size.padding.large,
                radius     = Size.radius.window,
                CenterContainer:new{
                    dimen = Geom:new{
                        w = gw - 2 * (Size.padding.large + Size.border.thick),
                        h = gh - 2 * (Size.padding.large + Size.border.thick),
                    },
                    VerticalGroup:new{
                        align = "center",
                        wrapText(_("Spymasters only"), pxFace(short * 0.085), inner_w),
                        VerticalSpan:new{ width = vs * 3 },
                        wrapText(_("Operatives, look away!"), pxFace(short * 0.05), inner_w),
                        VerticalSpan:new{ width = vs * 3 },
                        wrapText(_("Tap here to show the key.\nAny tap hides it again."),
                            pxFace(short * 0.04), inner_w),
                    },
                },
            },
        }
        banner = fitLine(turnTitle(self.board.turn), banner_px, bw, true)
    else
        self.grid = CodeGrid:new{
            board    = self.board,
            width    = bw,
            height   = bh - head_h,
            show_key = self.phase == "key" or self.board:isOver(),
            on_tap   = function(i) self:onCardTap(i) end,
        }
        body = self.grid
    end

    local content = VerticalGroup:new{
        align = "center",
        banner,
        VerticalSpan:new{ width = vs },
        counts,
        VerticalSpan:new{ width = vs * 2 },
        body,
    }

    if self:isLandscape() then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            content,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, content,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self[1] = self.layout
    self:updateStatus()
end

function CodeWordsScreen:updateStatus(msg)
    if msg then return ScreenBase.updateStatus(self, msg) end
    local b = self.board
    local clue
    if b.clue and not b:isOver() then
        clue = b.clue.number and T(_("Clue: %1 (%2)"), b.clue.word, b.clue.number)
                              or T(_("Clue: %1"), b.clue.word)
    end
    local wins = T(_("Wins: Red %1 – Blue %2"), self.wins.red or 0, self.wins.blue or 0)
    if self.phase == "gate" then
        return ScreenBase.updateStatus(self, wins)
    end
    ScreenBase.updateStatus(self, self:joinStatus(self.message or clue, wins))
end

return CodeWordsScreen
