local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local Blitbuffer = require("ffi/blitbuffer")
local Geometry = require("ui/geometry")
local Size = require("ui/size")
local CenterContainer = require("ui/widget/container/centercontainer")
local InputDialog = require("ui/widget/inputdialog")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ButtonWidget = require("ui/widget/button")
local FrameContainer = require("ui/widget/container/framecontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ConfirmBox = require("ui/widget/confirmbox")

local _ = require("gettext")

local BACKGROUND_COLOR = Blitbuffer.COLOR_WHITE

local InterfaceWidget = {}
InterfaceWidget.__index = InterfaceWidget

function InterfaceWidget:new(opts)
    assert(opts.parent, "parent is required")
    assert(opts.onSave, "onSave callback is required")

    local init = opts.initial or {}
    
    return setmetatable({
        parent = opts.parent,
        onSave = opts.onSave,
        dialog = nil,
        changes = {
            show_selected = init.show_selected ~= false,
            learning_mode = init.learning_mode == true,
            previous_move_hints = init.previous_move_hints == true,
            opponent_hints = init.opponent_hints == true,
            check_hints = init.check_hints == true,
            rotate_top_pieces = init.rotate_top_pieces == true,
            thinking_indicator = init.thinking_indicator ~= false,
            color_board_light = init.color_board_light or "#f5d478",
            color_board_dark  = init.color_board_dark or "#7a5a01",
        },
    }, InterfaceWidget)
end

function InterfaceWidget:show()
    local dlg = InputDialog:new{
        title = _("Interface"),
        save_callback = function() self:saveAndClose() end,
        dismiss_callback = function() UIManager:close(self.dialog) end,
    }
    dlg.element_width = math.floor(dlg.width * 0.8)
    self.dialog = dlg

    self:buildOptions()
    self:assembleContent()

    dlg:refocusWidget()
    UIManager:show(dlg)
end

function InterfaceWidget:markDirty()
    if self.dialog._buttons_edit_callback then
        self.dialog:_buttons_edit_callback(true)
    end
    UIManager:setDirty(self.parent, "ui")
end

local COLORS = {"#f5d478", "#FFFFFF", "#D3D3D3", "#7a5a01", "#000000"}

function InterfaceWidget:cycleColor(key)
    local current = self.changes[key]
    local idx = 1
    for i, c in ipairs(COLORS) do
        if c == current then
            idx = i
            break
        end
    end
    idx = (idx % #COLORS) + 1
    local new_color = COLORS[idx]

    self.changes[key] = new_color

    if self.parent and self.parent.board then
        self.parent.board[key] = new_color
        if self.parent.board.applySquareColors then
            self.parent.board:applySquareColors()
        end
        self.parent.board:updateBoard()
    end

    self:assembleContent()
    self.dialog:init()
    UIManager:setDirty(self.parent, "ui")
end


function InterfaceWidget:buildColorOptions()
    local w = self.dialog.element_width
    local gap = VerticalSpan:new{ width = Size.padding.small }

    local function colorButton(key, label)
        local _self = self
        return ButtonWidget:new{
            text = label,
            width = w,
            callback = function()
                local input = InputDialog:new{
                    title = label,
                    input = _self.changes[key] or "#FFFFFF",
                    save_callback = function(text)
                        _self.changes[key] = text
                        if _self.parent and _self.parent.board then
                            _self.parent.board[key] = text
                            if _self.parent.board.applySquareColors then
                                _self.parent.board:applySquareColors()
                            end
                            _self.parent.board:updateBoard()
                        end
                        _self:markDirty()
                        UIManager:setDirty(_self.parent, "ui")
                    end,
                }
                UIManager:show(input)
            end,
        }
    end

    self.colorOptionsGroup = VerticalGroup:new{
        align = "left",
        colorButton("color_board_light", _("Board Light")),
        gap,
        colorButton("color_board_dark", _("Board Dark")),
    }
end

function InterfaceWidget:buttonLabel(key, label_text)
    return (self.changes[key] and "☑ " or "☐ ") .. label_text
end

function InterfaceWidget:makeToggle(key, label_text)
    local btn
    btn = ButtonWidget:new{
        text = self:buttonLabel(key, label_text),
        width = self.dialog.element_width,
        radius = Size.radius.button,
        padding = Size.padding.small,
        align = "left",
        callback = function()
            self.changes[key] = not self.changes[key]
            btn.text = self:buttonLabel(key, label_text)
            btn:init()
            self:applyPreview()
            self:markDirty()
        end,
    }
    return btn
end

function InterfaceWidget:buildOptions()
    local gap = VerticalSpan:new{ width = Size.padding.small }
    self.optionsGroup = VerticalGroup:new{
        width = self.dialog.element_width,
        self:makeToggle("thinking_indicator", _("Thinking Indicator")),
        gap,
        self:makeToggle("show_selected", _("Highlight Selected")),
        VerticalSpan:new{ width = Size.padding.small },
        self:makeToggle("learning_mode", _("Player Hints")),
        VerticalSpan:new{ width = Size.padding.small },
        self:makeToggle("opponent_hints", _("Opponent Hints")),
        VerticalSpan:new{ width = Size.padding.small },
        self:makeToggle("previous_move_hints", _("Previous Move Hints")),
        VerticalSpan:new{ width = Size.padding.small },
        self:makeToggle("check_hints", _("Check Hints")),
        VerticalSpan:new{ width = Size.padding.small },
        self:makeToggle("rotate_top_pieces", _("Invert Opponent Pieces")),
    }
end

function InterfaceWidget:applyPreview()
    local board = self.parent and self.parent.board
    if not board then return end

    board.show_selected = self.changes.show_selected
    board.learning_mode = self.changes.learning_mode
    board.previous_move_hints = self.changes.previous_move_hints
    board.opponent_hints = self.changes.opponent_hints
    board.check_hints = self.changes.check_hints
    board:setRotateTopPieces(self.changes.rotate_top_pieces)

    if not board.learning_mode then
        board:clearValidMoves()
        board:clearPreviousMoveHints()
        board:clearCheckHint()
    end
    if board.learning_mode and board.check_hints then
        board:markCheckHint()
    else
        board:clearCheckHint()
    end
    if not board.show_selected and board.selected then
        board:unmarkSelected(board.selected)
    end
end

function InterfaceWidget:assembleContent()
    local D = self.dialog
    
    -- Safe initialization
    if not self.optionsGroup then self:buildOptions() end
    if not self.colorOptionsGroup then self:buildColorOptions() end

    local content = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        background = BACKGROUND_COLOR,
        padding = 0,
        margin = 0,

        VerticalGroup:new{
            align = "left",
            D.title_bar,

            VerticalSpan:new{ width = Size.padding.large },

            CenterContainer:new{
                dimen = Geometry:new{ w = D.width, h = self.optionsGroup:getSize().h },
                self.optionsGroup,
            },

            VerticalSpan:new{ width = Size.padding.large },

            CenterContainer:new{
                dimen = Geometry:new{ w = D.width, h = self.colorOptionsGroup:getSize().h },
                self.colorOptionsGroup,
            },

            VerticalSpan:new{ width = Size.padding.large },

            CenterContainer:new{
                dimen = Geometry:new{
                    w = D.title_bar:getSize().w,
                    h = D.button_table:getSize().h,
                },
                D.button_table,
            },

            VerticalSpan:new{ width = Size.padding.small },

            CenterContainer:new{
                dimen = Geometry:new{
                    w = D.title_bar:getSize().w,
                    h = Screen:scaleBySize(32),
                },
                ButtonWidget:new{
                    text = _("Reset to Defaults"),
                    radius = Size.radius.button,
                    padding = Size.padding.small,
                    width = math.floor(D.width * 0.8),
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Reset interface settings to defaults?"),
                            ok_text = _("Reset"),
                            ok_callback = function() self:resetToDefaults() end,
                        })
                    end,
                },
            },
        },
    }

    D.movable = MovableContainer:new{ content }
    D[1] = CenterContainer:new{ dimen = Screen:getSize(), D.movable }
end

function InterfaceWidget:resetToDefaults()
    self.changes.show_selected = true
    self.changes.learning_mode = false
    self.changes.previous_move_hints = false
    self.changes.opponent_hints = false
    self.changes.check_hints = false
    self.changes.rotate_top_pieces = false
    self.changes.thinking_indicator = true
    self.changes.color_board_light = "#f5d478"
    self.changes.color_board_dark  = "#7a5a01"
    self:saveAndClose()
end

function InterfaceWidget:saveAndClose()
    self:applyPreview()
    self.onSave(self.changes)
    UIManager:close(self.dialog)
end

return InterfaceWidget
