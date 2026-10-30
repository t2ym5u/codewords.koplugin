-- ---------------------------------------------------------------------------
-- CodeGrid -- the 5×5 word grid
--
-- E-ink has no colour, so the two teams are told apart by pattern:
--   red      solid black card, white word
--   blue     diagonal stripes and a thick border, word on a white plate
--   neutral  light grey card, grey word
--   assassin black card crossed by a white X, word on a black plate
-- A face-down card is plain white with a thin border. In the key view (and
-- once the game is over) every card shows its role, and a corner notch marks
-- the ones already revealed.
-- ---------------------------------------------------------------------------

local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local GestureRange   = require("ui/gesturerange")
local Geom           = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")

local Screen = Device.screen
local DPI_SCALE = Screen:scaleBySize(1000) / 1000

local COLS = 5

local CodeGrid = InputContainer:extend{
    board    = nil,
    width    = nil,
    height   = nil,
    show_key = false,     -- paint every card's role
    on_tap   = nil,       -- function(index)
}

function CodeGrid:init()
    self.gap    = math.max(2, math.floor(self.width / 120))
    self.cell_w = math.floor((self.width - (COLS - 1) * self.gap) / COLS)
    -- Cards are a little wider than tall, like real ones, but never taller
    -- than the room allows.
    local max_h = math.floor((self.height - (COLS - 1) * self.gap) / COLS)
    self.cell_h = math.min(max_h, math.floor(self.cell_w * 0.9))
    self.dimen  = Geom:new{
        x = 0, y = 0,
        w = COLS * self.cell_w + (COLS - 1) * self.gap,
        h = COLS * self.cell_h + (COLS - 1) * self.gap,
    }
    self.font_cache = {}
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function CodeGrid:getSize()
    return Geom:new{ w = self.dimen.w, h = self.dimen.h }
end

function CodeGrid:getCellRect(i)
    local r = math.floor((i - 1) / COLS)
    local c = (i - 1) % COLS
    return {
        x = self.dimen.x + c * (self.cell_w + self.gap),
        y = self.dimen.y + r * (self.cell_h + self.gap),
        w = self.cell_w,
        h = self.cell_h,
    }
end

function CodeGrid:indexAt(x, y)
    local lx, ly = x - self.dimen.x, y - self.dimen.y
    if lx < 0 or ly < 0 or lx >= self.dimen.w or ly >= self.dimen.h then return nil end
    local c = math.floor(lx / (self.cell_w + self.gap))
    local r = math.floor(ly / (self.cell_h + self.gap))
    if c >= COLS or r >= COLS then return nil end
    return r * COLS + c + 1
end

function CodeGrid:onTap(_, ges)
    if not (ges and ges.pos) then return false end
    local i = self:indexAt(ges.pos.x, ges.pos.y)
    if i and self.on_tap then self.on_tap(i) end
    return true
end

-- ---------------------------------------------------------------------------
-- Word fitting: largest size (down to a floor) where the word fits the card
-- on one line, or on two when it has a space or a hyphen to break at.
-- ---------------------------------------------------------------------------

local function face(px)
    return Font:getFace("cfont", math.max(6, math.floor(px / DPI_SCALE)))
end

local function textWidth(f, text)
    return RenderText:sizeUtf8Text(0, Screen:getWidth() * 4, f, text, true, true).x
end

-- Split "Jeanne d'Arc" / "Mont-Saint-Michel" into the two most even halves.
local function splitTwo(text)
    local best, best_diff
    local i = 1
    while true do
        local s, e = text:find("[ %-]", i)
        if not s then break end
        local a = text:sub(1, text:sub(s, s) == "-" and s or s - 1)
        local b = text:sub(e + 1)
        if #a > 0 and #b > 0 then
            local diff = math.abs(#a - #b)
            if not best_diff or diff < best_diff then best, best_diff = { a, b }, diff end
        end
        i = e + 1
    end
    return best
end

function CodeGrid:fitWord(text, max_w, max_h)
    local key = text .. "\0" .. max_w
    local hit = self.font_cache[key]
    if hit then return hit end
    local base = math.min(max_h * 0.42, max_w * 0.24)
    local floor_px = math.max(9, base * 0.45)
    local two = splitTwo(text)
    local px = base
    local res
    while true do
        local f = face(px)
        if textWidth(f, text) <= max_w then
            res = { lines = { text }, face = f, px = px }
            break
        end
        if two and px * 2.3 <= max_h
           and textWidth(f, two[1]) <= max_w and textWidth(f, two[2]) <= max_w then
            res = { lines = two, face = f, px = px }
            break
        end
        if px <= floor_px then
            -- Last resort: smallest size, two lines if possible, clipped by max_width.
            res = { lines = two or { text }, face = f, px = px }
            break
        end
        px = px * 0.92
    end
    self.font_cache[key] = res
    return res
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local LIGHT = Blitbuffer.COLOR_LIGHT_GRAY
local GRAY  = Blitbuffer.COLOR_GRAY
local DARK  = Blitbuffer.COLOR_DARK_GRAY

local function frame(bb, x, y, w, h, t, color)
    bb:paintRect(x, y, w, t, color)
    bb:paintRect(x, y + h - t, w, t, color)
    bb:paintRect(x, y, t, h, color)
    bb:paintRect(x + w - t, y, t, h, color)
end

-- Stripes going up to the right, `step` px apart, `t` px thick.
local function hatch(bb, x, y, w, h, step, t, color)
    for k = -h, w, step do
        for j = 0, h - 1 do
            local px = x + k + (h - 1 - j)
            if px >= x and px + t <= x + w then
                bb:paintRect(px, y + j, t, 1, color)
            end
        end
    end
end

-- A thick X corner to corner.
local function cross(bb, x, y, w, h, t, color)
    local n = math.max(w, h)
    for s = 0, n do
        local px = x + math.floor(s * (w - t) / n)
        local py1 = y + math.floor(s * (h - t) / n)
        local py2 = y + h - t - math.floor(s * (h - t) / n)
        bb:paintRect(px, py1, t, t, color)
        bb:paintRect(px, py2, t, t, color)
    end
end

function CodeGrid:paintWord(bb, rect, text, color, plate)
    local pad = math.max(3, math.floor(rect.w * 0.05))
    local fit = self:fitWord(text, rect.w - 2 * pad, rect.h - 2 * pad)
    local metrics = {}
    local line_h = math.floor(fit.px * 1.15)
    local total_h = line_h * #fit.lines
    local top = rect.y + math.floor((rect.h - total_h) / 2)
    if plate then
        local pw = 0
        for i, l in ipairs(fit.lines) do
            metrics[i] = textWidth(fit.face, l)
            pw = math.max(pw, metrics[i])
        end
        local pp = math.max(2, math.floor(fit.px * 0.2))
        local plw = math.min(rect.w - 4, pw + 2 * pp)
        local plh = math.min(rect.h - 4, total_h + pp)
        bb:paintRect(rect.x + math.floor((rect.w - plw) / 2), rect.y + math.floor((rect.h - plh) / 2),
            plw, plh, plate)
    end
    for i, l in ipairs(fit.lines) do
        local w = metrics[i] or textWidth(fit.face, l)
        w = math.min(w, rect.w - 2 * pad)
        -- Centre on a fixed reference ("Hx"), not on each word's own ink:
        -- otherwise "Apple" and "Cable" sit at different heights.
        local m = RenderText:sizeUtf8Text(0, rect.w, fit.face, "Hx", true, true)
        local cy = top + (i - 1) * line_h + math.floor(line_h / 2)
        local baseline = cy + math.floor((m.y_top - m.y_bottom) / 2)
        RenderText:renderUtf8Text(bb, rect.x + math.floor((rect.w - w) / 2), baseline,
            fit.face, l, true, true, color, rect.w - 2 * pad)
    end
end

function CodeGrid:paintCard(bb, i, rect)
    local card = self.board.cards[i]
    local show = card.revealed or self.show_key
    local x, y, w, h = rect.x, rect.y, rect.w, rect.h
    local thin  = math.max(1, math.floor(w / 90))
    local thick = math.max(3, math.floor(w / 22))
    if not show then
        bb:paintRect(x, y, w, h, WHITE)
        frame(bb, x, y, w, h, thin * 2, BLACK)
        self:paintWord(bb, rect, card.word, BLACK)
        return
    end
    local role = card.role
    if role == "red" then
        bb:paintRect(x, y, w, h, BLACK)
        self:paintWord(bb, rect, card.word, WHITE)
    elseif role == "blue" then
        bb:paintRect(x, y, w, h, WHITE)
        hatch(bb, x, y, w, h, math.max(6, math.floor(w / 9)), math.max(2, math.floor(w / 36)), DARK)
        frame(bb, x, y, w, h, thick, BLACK)
        self:paintWord(bb, rect, card.word, BLACK, WHITE)
    elseif role == "neutral" then
        bb:paintRect(x, y, w, h, LIGHT)
        frame(bb, x, y, w, h, thin, GRAY)
        self:paintWord(bb, rect, card.word, DARK)
    else -- assassin
        bb:paintRect(x, y, w, h, BLACK)
        cross(bb, x + thick, y + thick, w - 2 * thick, h - 2 * thick, thick, WHITE)
        self:paintWord(bb, rect, card.word, WHITE, BLACK)
    end
    -- Key view: notch in the top-left corner of the cards already revealed.
    if self.show_key and card.revealed then
        local s = math.floor(math.min(w, h) * 0.28)
        local dark_card = role == "red" or role == "assassin"
        local c = dark_card and WHITE or BLACK
        for j = 0, s - 1 do
            bb:paintRect(x, y + j, s - j, 1, c)
        end
    end
end

function CodeGrid:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    for i = 1, #self.board.cards do
        self:paintCard(bb, i, self:getCellRect(i))
    end
end

return CodeGrid
