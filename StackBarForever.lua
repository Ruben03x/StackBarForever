local BAR_SLOTS, MAX_EXTRAS = 12, 4
local SIZE, GAP = 38, 5
local WIDTH = BAR_SLOTS * (SIZE + GAP) - GAP
local HEIGHT = MAX_EXTRAS * (SIZE + GAP) - GAP
local BARS = {
    { frame = "MainActionBar", button = "ActionButton", binding = "ACTIONBUTTON", eui = "MainBar" },
    { frame = "MultiBarBottomLeft", binding = "MULTIACTIONBAR1BUTTON", page = 6 },
    { frame = "MultiBarBottomRight", binding = "MULTIACTIONBAR2BUTTON", page = 5 },
    { frame = "MultiBarRight", binding = "MULTIACTIONBAR3BUTTON", page = 3 },
    { frame = "MultiBarLeft", binding = "MULTIACTIONBAR4BUTTON", page = 4 },
    { frame = "MultiBar5", binding = "MULTIACTIONBAR5BUTTON", page = 13 },
    { frame = "MultiBar6", binding = "MULTIACTIONBAR6BUTTON", page = 14 },
    { frame = "MultiBar7", binding = "MULTIACTIONBAR7BUTTON", page = 15 },
    { binding = "EUI_BAR9_BUTTON", page = 2 },
    { binding = "EUI_BAR10_BUTTON", page = 10 },
}

local db, editor, bindingOwner
local columns, editorCells = {}, {}
local selectedBar = 1
local bindingSignature = ""
local refreshQueued = false
local hookedEAB

-- One attempt per release. The base action follows the original bar's live page.
local selectSpell = [[
    if down then
        return
    end
    local step = self:GetAttribute("stack-step")
    if step == 1 then
        local action = self:GetAttribute("base-action")
        if self:GetAttribute("main-bar") then
            local page = control:GetFrameRef("mainbar"):GetAttribute("actionpage") or 1
            action = action + (page - 1) * self:GetAttribute("bar-slots")
        elseif self:GetAttribute("ellesmere-bar") then
            action = self:GetFrameRef("source"):GetAttribute("action") or action
        end
        self:SetAttribute("type", "action")
        self:SetAttribute("action", action)
    else
        self:SetAttribute("type", "spell")
        self:SetAttribute("spell", self:GetAttribute("stack-spell-" .. (step - 1)))
    end
    return nil, "advance"
]]

local advanceStep = [[
    local step = self:GetAttribute("stack-step") + 1
    if step > self:GetAttribute("stack-size") then
        step = 1
    end
    self:SetAttribute("stack-step", step)
]]

local refreshSecureBindings = [[
    if self:GetAttribute("stack-has-bindings") then
        self:ClearBindings()
        self:SetAttribute("stack-has-bindings", nil)
    end
    if self:GetAttribute("state-stacksuspended") == "yes" then
        return
    end
    local count = self:GetAttribute("stack-binding-count") or 0
    for i = 1, count do
        local key = self:GetAttribute("stack-binding-key-" .. i)
        local target = self:GetAttribute("stack-binding-target-" .. i)
        self:SetBindingClick(true, key, target, "LeftButton")
    end
    if count > 0 then
        self:SetAttribute("stack-has-bindings", true)
    end
]]

local function say(message)
    print("|cffe4bd75Stack Bar Forever|r " .. message)
end

local function getEllesmere()
    local registry = EllesmereUI and EllesmereUI._ModuleNS
    return registry and registry.EllesmereUIActionBars
end

local function getBar(index, eui)
    local info = BARS[index]
    local euiKey = info.eui or "Bar" .. index
    local euiFrame = _G["EABBar_" .. euiKey]
    if euiFrame and eui and eui.barButtons then
        local profile = eui.EAB and eui.EAB.db and eui.EAB.db.profile
        local config = profile and profile.bars and profile.bars[euiKey]
        local visibility = config and EllesmereUI.VisOverrideValue and EllesmereUI.VisOverrideValue(config)
        if config and (config.enabled == false or (visibility or config.barVisibility) == "never"
            or (not visibility and config.alwaysHidden)) then
            return
        end
        return euiFrame, eui.barButtons[euiKey]
    end

    local frame = info.frame and _G[info.frame]
    if frame and (index == 1 or Settings.GetValue("PROXY_SHOW_ACTIONBAR_" .. index)) then
        return frame
    end
end

local function getSource(index, slot, frame, euiButtons)
    if euiButtons then
        return euiButtons[slot]
    end
    local info = BARS[index]
    if not frame or not info.frame or frame ~= _G[info.frame] then
        return
    end
    return frame.actionButtons and frame.actionButtons[slot]
        or _G[(info.button or info.frame .. "Button") .. slot]
end

local function makeIcon(parent)
    local cell = CreateFrame("Frame", nil, parent)
    local border = cell:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.41, 0.34, 0.23, 1)
    local background = cell:CreateTexture(nil, "BORDER")
    background:SetPoint("TOPLEFT", 1, -1)
    background:SetPoint("BOTTOMRIGHT", -1, 1)
    background:SetColorTexture(0.09, 0.08, 0.07, 0.96)

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetPoint("TOPLEFT", 2, -2)
    cell.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    cell.cooldown = CreateFrame("Cooldown", nil, cell, "CooldownFrameTemplate")
    cell.cooldown:SetAllPoints(cell.icon)
    cell.cooldown:SetDrawEdge(false)
    cell.cooldown:EnableMouse(false)

    local overlay = CreateFrame("Frame", nil, cell)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(cell.cooldown:GetFrameLevel() + 1)
    cell.mark = overlay:CreateTexture(nil, "OVERLAY")
    cell.mark:SetPoint("BOTTOMLEFT", 2, 2)
    cell.mark:SetPoint("BOTTOMRIGHT", -2, 2)
    cell.mark:SetHeight(2)
    cell.mark:SetColorTexture(1, 0.77, 0.33, 1)
    cell.mark:Hide()

    cell.label = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    cell.label:SetPoint("TOPRIGHT", -3, -3)
    cell.label:SetPoint("TOPLEFT", 3, -3)
    cell.label:SetJustifyH("RIGHT")
    return cell
end

local function updateIcon(cell, spellID, key)
    cell.spellID = spellID
    cell.icon:SetTexture(spellID and C_Spell.GetSpellTexture(spellID))
    cell.label:SetText(key or "")
end

local function updateCooldown(cell)
    if not cell.spellID then
        return
    end
    local duration = C_Spell.GetSpellCooldownDuration(cell.spellID)
    if duration then
        cell.cooldown:SetCooldownFromDurationObject(duration, true)
    else
        cell.cooldown:Clear()
    end
end

local function updateNext(column)
    local step = column.action:GetAttribute("stack-step")
    for row, icon in ipairs(column.icons) do
        icon.mark:SetShown(icon.spellID ~= nil and row + 1 == step)
    end
    if step == 1 then
        column.icons[1].label:SetTextColor(1, 0.77, 0.33)
    else
        column.icons[1].label:SetTextColor(1, 1, 1)
    end
end

local function placeIcons(column, bar, euiButtons)
    local source = column.source
    local adjacent = getSource(column.bar, column.slot == 1 and 2 or column.slot - 1, bar, euiButtons)
    local x, y = source:GetCenter()
    local nextX, nextY
    if adjacent then
        nextX, nextY = adjacent:GetCenter()
    end
    local vertical = x and nextX and math.abs(nextY - y) > math.abs(nextX - x)
    local growLeft = vertical and x * source:GetEffectiveScale() > UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2
    local size = math.max(1, math.min(source:GetWidth(), source:GetHeight()) * 0.8)
    for row, icon in ipairs(column.icons) do
        icon:ClearAllPoints()
        icon:SetSize(size, size)
        local offset = GAP + (row - 1) * (size + GAP)
        if growLeft then
            icon:SetPoint("RIGHT", source, "LEFT", -offset, 0)
        elseif vertical then
            icon:SetPoint("LEFT", source, "RIGHT", offset, 0)
        else
            icon:SetPoint("BOTTOM", source, "TOP", 0, offset)
        end
    end
end

local function createColumn(index, slot)
    local id = (index - 1) * BAR_SLOTS + slot
    local action = CreateFrame("Button", "StackBarForeverButton" .. id, UIParent,
        "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    action:SetSize(1, 1)
    action:SetPoint("BOTTOMLEFT", UIParent, "TOPRIGHT", 1, 1)
    action:EnableMouse(false)
    action:RegisterForClicks("AnyUp", "AnyDown")
    action:SetAttribute("useOnKeyDown", false)
    action:SetAttribute("checkselfcast", true)
    action:SetAttribute("checkfocuscast", true)
    action:SetAttribute("checkmouseovercast", true)
    action:SetAttribute("bar-slots", BAR_SLOTS)
    local column = { bar = index, slot = slot, action = action, icons = {} }
    bindingOwner:WrapScript(action, "OnClick", selectSpell, advanceStep)
    action:HookScript("PostClick", function(_, _, down)
        if not down then
            updateNext(column)
        end
    end)
    columns[id] = column
    return column
end

local function applyColumn(column, source, bar, euiButtons, key)
    if source ~= column.source then
        column.source = source
        column.action:SetFrameRef("source", source)
        column.action:SetAttribute("main-bar", column.bar == 1 and not euiButtons)
        column.action:SetAttribute("ellesmere-bar", euiButtons ~= nil)
        local page = BARS[column.bar].page or 1
        column.action:SetAttribute("base-action", (page - 1) * BAR_SLOTS + column.slot)
        for row = 1, MAX_EXTRAS do
            if column.icons[row] then
                column.icons[row]:SetParent(source)
            else
                column.icons[row] = makeIcon(source)
                column.icons[row]:SetFrameStrata("HIGH")
            end
        end
    end

    local spells = db.bars[column.bar][column.slot]
    local action = column.action
    local size = #spells + 1
    local step = action:GetAttribute("stack-step")
    if not step or step > size then
        action:SetAttribute("stack-step", 1)
    end
    action:SetAttribute("stack-size", size)
    placeIcons(column, bar, euiButtons)
    for row, icon in ipairs(column.icons) do
        local spell = spells[row]
        action:SetAttribute("stack-spell-" .. row, spell)
        updateIcon(icon, spell, row == 1 and key)
        icon:SetShown(spell ~= nil and db.enabled)
        if spell then
            updateCooldown(icon)
        end
    end
    updateNext(column)
end

local function getKeys(index, slot, source)
    local info = BARS[index]
    local keys = { GetBindingKey(info.binding .. slot) }
    local frameName = source and source:GetName()
    if frameName then
        for _, key in ipairs({ GetBindingKey("CLICK " .. frameName .. ":LeftButton") }) do
            keys[#keys + 1] = key
        end
    end
    local stockName = info.frame and (info.button or info.frame .. "Button") .. slot
    if stockName and stockName ~= frameName then
        for _, key in ipairs({ GetBindingKey("CLICK " .. stockName .. ":LeftButton") }) do
            keys[#keys + 1] = key
        end
    end
    return keys
end

local function formatKey(key)
    return key and GetBindingText(key, "KEY_", true)
end

local function refreshEditor()
    if not editor:IsShown() then
        return
    end
    local eui = getEllesmere()
    local frame, euiButtons = getBar(selectedBar, eui)
    if not frame then
        selectedBar = 1
        frame, euiButtons = getBar(1, eui)
    end
    editor.picker:SetText("Action Bar " .. selectedBar)
    for slot, rowCells in ipairs(editorCells) do
        local source = getSource(selectedBar, slot, frame, euiButtons)
        local keys = getKeys(selectedBar, slot, source)
        local spells = db.bars[selectedBar][slot]
        for row, cell in ipairs(rowCells) do
            updateIcon(cell, spells[row], row == 1 and (formatKey(keys[1]) or tostring(slot)) or nil)
            cell:SetShown(source ~= nil)
            cell.add:SetShown(spells[row] == nil)
        end
    end
end

local queueRefresh
local function refresh()
    if not db or InCombatLockdown() then
        return
    end

    local eui = getEllesmere()
    local owner = eui and eui.EAB
    if owner and owner ~= hookedEAB and type(owner.ApplyAll) == "function" then
        hooksecurefunc(owner, "ApplyAll", queueRefresh)
        if type(owner.ApplyCombatVisibility) == "function" then
            hooksecurefunc(owner, "ApplyCombatVisibility", queueRefresh)
        end
        hookedEAB = owner
    end
    local keysToBind, targets, signatureParts, active, claimed = {}, {}, {}, {}, {}
    for index = 1, #BARS do
        local frame, euiButtons = getBar(index, eui)
        if frame then
            for slot, spells in ipairs(db.bars[index]) do
                local source = #spells > 0 and getSource(index, slot, frame, euiButtons)
                if source then
                    local id = (index - 1) * BAR_SLOTS + slot
                    local column = columns[id] or createColumn(index, slot)
                    local keys = getKeys(index, slot, source)
                    applyColumn(column, source, frame, euiButtons, formatKey(keys[1]))
                    active[id] = true
                    if db.enabled then
                        for _, key in ipairs(keys) do
                            if not claimed[key] then
                                claimed[key] = true
                                keysToBind[#keysToBind + 1] = key
                                targets[#targets + 1] = column.action:GetName()
                                signatureParts[#signatureParts + 1] = key .. ":" .. id
                            end
                        end
                    end
                end
            end
        end
    end
    for id, column in pairs(columns) do
        if not active[id] then
            column.action:SetAttribute("stack-step", nil)
            for _, icon in ipairs(column.icons) do
                icon:Hide()
            end
        end
    end

    -- Override writes can emit UPDATE_BINDINGS. Ignore identical results.
    local signature = table.concat(signatureParts, ";")
    if signature ~= bindingSignature then
        bindingSignature = signature
        local previousCount = bindingOwner:GetAttribute("stack-binding-count") or 0
        bindingOwner:SetAttribute("stack-binding-count", #keysToBind)
        for i = 1, math.max(previousCount, #keysToBind) do
            bindingOwner:SetAttribute("stack-binding-key-" .. i, keysToBind[i])
            bindingOwner:SetAttribute("stack-binding-target-" .. i, targets[i])
        end
        bindingOwner:Execute(refreshSecureBindings)
    end
    refreshEditor()
end

queueRefresh = function()
    if refreshQueued then
        return
    end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        refresh()
    end)
end

local function editSlot(slot, row, button)
    if InCombatLockdown() then
        return
    end
    local spells = db.bars[selectedBar][slot]
    local kind, _, _, spell, base = GetCursorInfo()
    if kind == "spell" then
        if type(base) == "number" and base > 0 then
            spell = base
        end
        if type(spell) ~= "number" or spell <= 0 or not C_Spell.GetSpellInfo(spell) then
            say("Drag a spell from your spellbook.")
            return
        end
        spells[math.min(row, #spells + 1)] = spell
        ClearCursor()
    elseif not kind and button == "RightButton" and spells[row] then
        table.remove(spells, row)
    else
        return
    end
    GameTooltip:Hide()
    local column = columns[(selectedBar - 1) * BAR_SLOTS + slot]
    if column then
        column.action:SetAttribute("stack-step", 1)
    end
    refresh()
end

local function makeEditor()
    editor = CreateFrame("Frame", nil, UIParent)
    editor:SetSize(WIDTH + 20, HEIGHT + 52)
    editor:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    editor:SetFrameStrata("DIALOG")
    editor:SetMovable(true)
    editor:SetClampedToScreen(true)
    editor:EnableMouse(true)
    editor:RegisterForDrag("LeftButton")
    editor:SetScript("OnDragStart", editor.StartMoving)
    editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
    local background = editor:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.07, 0.06, 0.05, 0.96)

    local picker = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    picker:SetSize(122, 24)
    picker:SetPoint("TOPLEFT", 9, -8)
    picker:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, menu)
            local eui = getEllesmere()
            for index = 1, #BARS do
                if getBar(index, eui) then
                    local barIndex = index
                    menu:CreateButton("Action Bar " .. barIndex, function()
                        selectedBar = barIndex
                        refreshEditor()
                    end)
                end
            end
        end)
    end)
    editor.picker = picker

    local hint = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("LEFT", picker, "RIGHT", 8, 0)
    hint:SetText("Drop a spell  ·  Right-click to remove")

    local done = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    done:SetSize(54, 24)
    done:SetPoint("TOPRIGHT", -9, -8)
    done:SetText(DONE)
    done:SetScript("OnClick", function()
        editor:Hide()
    end)

    for slot = 1, BAR_SLOTS do
        editorCells[slot] = {}
        for row = 1, MAX_EXTRAS do
            local slotIndex, rowIndex = slot, row
            local cell = makeIcon(editor)
            cell:SetSize(SIZE, SIZE)
            cell:SetPoint("BOTTOMLEFT", 10 + (slot - 1) * (SIZE + GAP), 10 + (row - 1) * (SIZE + GAP))
            cell.add = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            cell.add:SetPoint("CENTER")
            cell.add:SetText("+")
            local target = CreateFrame("Button", nil, cell)
            target:SetAllPoints()
            target:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            target:SetScript("OnReceiveDrag", function()
                editSlot(slotIndex, rowIndex)
            end)
            target:SetScript("OnClick", function(_, button)
                editSlot(slotIndex, rowIndex, button)
            end)
            target:SetScript("OnEnter", function(self)
                if cell.spellID then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetSpellByID(cell.spellID)
                    GameTooltip:Show()
                end
            end)
            target:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            editorCells[slot][row] = cell
        end
    end
    editor:Hide()
end

local function initialize()
    StackBarForeverDB = StackBarForeverDB or {}
    db = StackBarForeverDB
    db.bars = db.bars or {}
    if db.enabled == nil then
        db.enabled = true
    end
    for index = 1, #BARS do
        db.bars[index] = db.bars[index] or {}
        for slot = 1, BAR_SLOTS do
            if index == 1 and not db.bars[index][slot] and db.stacks then
                local legacy = slot <= 10 and db.stacks[tostring(slot % 10)]
                local prior = db.stacks[slot] or legacy
                if prior and not db.stacks[slot] then
                    local page = MainActionBar:GetAttribute("actionpage") or 1
                    local kind, spell = GetActionInfo((page - 1) * BAR_SLOTS + slot)
                    if kind == "spell" and spell == prior[1] then
                        table.remove(prior, 1)
                    end
                end
                db.bars[index][slot] = prior
            end
            db.bars[index][slot] = db.bars[index][slot] or {}
        end
    end
    db.stacks = nil

    bindingOwner = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    bindingOwner:SetFrameRef("mainbar", MainActionBar)
    bindingOwner:SetAttribute("_onstate-stacksuspended", refreshSecureBindings)
    RegisterStateDriver(bindingOwner, "stacksuspended", "[vehicleui][overridebar][possessbar][petbattle] yes; no")
    makeEditor()
    EventRegistry:RegisterCallback("ActionBarShownSettingUpdated", queueRefresh, bindingOwner)
    refresh()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("UPDATE_BINDINGS")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterEvent("SPELL_UPDATE_CHARGES")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:RegisterEvent("UI_SCALE_CHANGED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" then
        if not db and not InCombatLockdown() then
            initialize()
        else
            queueRefresh()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if editor then
            editor:StopMovingOrSizing()
            editor:Hide()
        end
    elseif event == "UPDATE_BINDINGS" or event == "PLAYER_ENTERING_WORLD"
        or event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        queueRefresh()
    elseif db and db.enabled then
        for _, column in pairs(columns) do
            for _, icon in ipairs(column.icons) do
                if icon:IsShown() then
                    if event == "SPELLS_CHANGED" then
                        icon.icon:SetTexture(C_Spell.GetSpellTexture(icon.spellID))
                    end
                    updateCooldown(icon)
                end
            end
        end
    end
end)

SlashCmdList.STACKBARFOREVER = function(message)
    if not db or InCombatLockdown() then
        say("Change your stacks out of combat.")
        return
    end
    local command = message:lower():match("^%s*(%S*)")
    if command == "off" or command == "on" then
        db.enabled = command == "on"
        editor:Hide()
        refresh()
        say(db.enabled and "Stacks enabled." or "Stacks paused. Your usual keybinds are active.")
    elseif command == "" then
        editor:SetShown(not editor:IsShown())
        refresh()
    else
        say("/stackbar to edit  ·  /stackbar off to pause  ·  /stackbar on to resume")
    end
end
SLASH_STACKBARFOREVER1 = "/stackbar"
