local BAR_SLOTS = 12
local MAX_EXTRAS = 4
local SIZE, GAP = 38, 5
local WIDTH = BAR_SLOTS * (SIZE + GAP) - GAP
local HEIGHT = MAX_EXTRAS * (SIZE + GAP) - GAP
local DEFAULT_Y = 220

local db, bar, editor, bindingOwner
local columns = {}
local bindingSignature = ""
local bindingRefreshQueued = false

-- Only the order saved before combat is available to these secure handlers.
local selectSpell = [[
    local size = self:GetAttribute("stack-size") or 0
    if down or size == 0 then
        return
    end
    local step = self:GetAttribute("stack-step")
    if step == 1 then
        -- Follow the actual Action Bar 1 page even when a stance changes in combat.
        local page = control:GetFrameRef("mainbar"):GetAttribute("actionpage") or 1
        local slot = self:GetAttribute("stack-column")
        self:SetAttribute("type", "action")
        self:SetAttribute("action", (page - 1) * self:GetAttribute("stack-bar-slots") + slot)
    else
        self:SetAttribute("type", "spell")
        self:SetAttribute("spell", self:GetAttribute("stack-spell-" .. (step - 1)))
    end
    return nil, "advance"
]]

-- These are temporary overrides owned only by Stack Bar. Special bars keep their keys.
local refreshSecureBindings = [[
    if self:GetAttribute("stack-has-bindings") then
        self:ClearBindings()
        self:SetAttribute("stack-has-bindings", nil)
    end
    local suspended = self:GetAttribute("state-stacksuspended") == "yes"
    local display = self:GetFrameRef("display")
    if not self:GetAttribute("stack-enabled") or suspended then
        display:Hide()
        return
    end
    display:Show()
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

local advanceStep = [[
    local step = self:GetAttribute("stack-step") + 1
    if step > self:GetAttribute("stack-size") then
        step = 1
    end
    self:SetAttribute("stack-step", step)
]]

local function say(message)
    print("|cffe4bd75Stack Bar Forever|r " .. message)
end

local function updateNext(column)
    local step = column.action:GetAttribute("stack-step")
    if step == 1 then
        column.action.keyLabel:SetTextColor(1, 0.77, 0.33)
    else
        column.action.keyLabel:SetTextColor(1, 1, 1)
    end
    for index, slot in ipairs(column.slots) do
        slot.nextMark:SetShown(slot.spellID ~= nil and index + 1 == step)
    end
end

local function updateCooldown(slot)
    local duration = C_Spell.GetSpellCooldownDuration(slot.spellID)
    if duration then
        slot.cooldown:SetCooldownFromDurationObject(duration, true)
    else
        slot.cooldown:Clear()
    end
end

local function updateSpellDisplays(refreshIcons)
    for _, column in ipairs(columns) do
        for _, slot in ipairs(column.slots) do
            if slot.spellID then
                if refreshIcons then
                    slot.icon:SetTexture(C_Spell.GetSpellTexture(slot.spellID))
                end
                updateCooldown(slot)
            end
        end
    end
end

local function showTooltip(frame, spellID)
    if spellID then
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(spellID)
        GameTooltip:Show()
    end
end

local function setBorder(frame, rgba)
    local left = frame:CreateTexture(nil, "BORDER")
    local right = frame:CreateTexture(nil, "BORDER")
    local top = frame:CreateTexture(nil, "BORDER")
    local bottom = frame:CreateTexture(nil, "BORDER")
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, 0)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 0)
    left:SetWidth(1)
    right:SetWidth(1)
    top:SetHeight(1)
    bottom:SetHeight(1)
    for _, edge in ipairs({ left, right, top, bottom }) do
        edge:SetColorTexture(unpack(rgba))
    end
end

local function positionSlot(slot, parent, columnIndex, rowIndex)
    slot:SetSize(SIZE, SIZE)
    slot:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT",
        (columnIndex - 1) * (SIZE + GAP), (rowIndex - 1) * (SIZE + GAP))
end

local function makeSlot(parent, columnIndex, rowIndex)
    local slot
    if rowIndex == 1 then
        slot = CreateFrame("Button", "StackBarForeverButton" .. columnIndex, parent, "SecureActionButtonTemplate")
        slot:RegisterForClicks("AnyUp", "AnyDown")
        slot:SetAttribute("useOnKeyDown", false)
        slot:SetAttribute("checkselfcast", true)
        slot:SetAttribute("checkfocuscast", true)
        slot:SetAttribute("checkmouseovercast", true)
        slot:SetAttribute("stack-column", columnIndex)
        slot:SetAttribute("stack-bar-slots", BAR_SLOTS)
    else
        slot = CreateFrame("Frame", nil, parent)
    end
    positionSlot(slot, parent, columnIndex, rowIndex)
    slot:EnableMouse(true)
    slot:SetScript("OnEnter", function(self)
        showTooltip(self, self.spellID)
    end)
    slot:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local backing = slot:CreateTexture(nil, "BACKGROUND")
    backing:SetAllPoints()
    backing:SetColorTexture(0.09, 0.08, 0.07, 0.98)
    setBorder(slot, { 0.43, 0.36, 0.24, 1 })

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 2, -2)
    slot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    slot.cooldown = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    slot.cooldown:SetAllPoints(slot.icon)
    slot.cooldown:SetDrawEdge(false)
    slot.cooldown:EnableMouse(false)

    local overlay = CreateFrame("Frame", nil, slot)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(slot.cooldown:GetFrameLevel() + 1)
    slot.nextMark = overlay:CreateTexture(nil, "OVERLAY")
    slot.nextMark:SetPoint("BOTTOMLEFT", 2, 2)
    slot.nextMark:SetPoint("BOTTOMRIGHT", -2, 2)
    slot.nextMark:SetHeight(2)
    slot.nextMark:SetColorTexture(1, 0.77, 0.33, 1)

    if rowIndex == 1 then
        local label = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        label:SetPoint("TOPRIGHT", -3, -3)
        label:SetWidth(SIZE - 5)
        label:SetJustifyH("RIGHT")
        slot.keyLabel = label
    end

    slot:Hide()
    return slot
end

local function applyColumn(columnIndex)
    local column = columns[columnIndex]
    local spells = db.stacks[columnIndex]
    local size = #spells
    local action = column.action
    action:SetAttribute("type", nil)
    action:SetAttribute("stack-size", size > 0 and size + 1 or 0)
    action:SetAttribute("stack-step", 1)

    for rowIndex, slot in ipairs(column.slots) do
        local spellID = spells[rowIndex]
        action:SetAttribute("stack-spell-" .. rowIndex, spellID)
        slot.spellID = spellID
        slot.icon:SetTexture(spellID and C_Spell.GetSpellTexture(spellID))
        slot:SetShown(spellID ~= nil)
        if spellID then
            updateCooldown(slot)
        else
            slot.cooldown:Clear()
        end
    end
    updateNext(column)
end

local function appendKeys(keys, ...)
    for _, key in ipairs({ ... }) do
        keys[#keys + 1] = key
    end
end

local function applyBindings()
    if not bar or InCombatLockdown() then
        return
    end
    local keysToBind, targets, signatureParts = {}, {}, {}
    for columnIndex, column in ipairs(columns) do
        local keys = { GetBindingKey("ACTIONBUTTON" .. columnIndex) }
        appendKeys(keys, GetBindingKey("CLICK ActionButton" .. columnIndex .. ":LeftButton"))
        local label = keys[1] and GetBindingText(keys[1], "KEY_", true)
        column.action.keyLabel:SetText(label or "")
        column.targets[1].label:SetText(label or tostring(columnIndex))

        if db.enabled and #db.stacks[columnIndex] > 0 then
            local target = column.action:GetName()
            for _, key in ipairs(keys) do
                keysToBind[#keysToBind + 1] = key
                targets[#targets + 1] = target
                signatureParts[#signatureParts + 1] = key .. ":" .. columnIndex
            end
        end
    end

    -- Setting overrides can itself fire UPDATE_BINDINGS.
    local signature = table.concat(signatureParts, ";")
    local enabledChanged = bindingOwner:GetAttribute("stack-enabled") ~= db.enabled
    if signature == bindingSignature and not enabledChanged then
        return
    end
    bindingSignature = signature
    bindingOwner:SetAttribute("stack-enabled", db.enabled)
    local previousCount = bindingOwner:GetAttribute("stack-binding-count") or 0
    bindingOwner:SetAttribute("stack-binding-count", #keysToBind)
    for i = 1, math.max(previousCount, #keysToBind) do
        bindingOwner:SetAttribute("stack-binding-key-" .. i, keysToBind[i])
        bindingOwner:SetAttribute("stack-binding-target-" .. i, targets[i])
    end
    bindingOwner:Execute(refreshSecureBindings)
end

local function queueBindingRefresh()
    if bindingRefreshQueued then
        return
    end
    bindingRefreshQueued = true
    C_Timer.After(0, function()
        bindingRefreshQueued = false
        applyBindings()
    end)
end

local function updateEditor()
    for columnIndex, column in ipairs(columns) do
        local spells = db.stacks[columnIndex]
        for rowIndex, target in ipairs(column.targets) do
            local filled = spells[rowIndex] ~= nil
            target.placeholder:SetShown(not filled)
        end
    end
end

local function editSlot(columnIndex, rowIndex, mouseButton)
    if InCombatLockdown() then
        return
    end
    local spells = db.stacks[columnIndex]
    local kind, _, _, spellID, baseSpellID = GetCursorInfo()
    if kind == "spell" then
        if type(baseSpellID) == "number" and baseSpellID > 0 then
            spellID = baseSpellID
        end
        if type(spellID) ~= "number" or spellID <= 0 or not C_Spell.GetSpellInfo(spellID) then
            say("Drag a spell from your spellbook.")
            return
        end
        spells[math.min(rowIndex, #spells + 1)] = spellID
        ClearCursor()
    elseif not kind and mouseButton == "RightButton" and spells[rowIndex] then
        table.remove(spells, rowIndex)
    else
        return
    end
    GameTooltip:Hide()
    applyColumn(columnIndex)
    applyBindings()
    updateEditor()
end

local function makeTarget(columnIndex, rowIndex)
    local target = CreateFrame("Button", nil, editor)
    positionSlot(target, editor, columnIndex, rowIndex)
    target:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    target:SetScript("OnReceiveDrag", function()
        editSlot(columnIndex, rowIndex)
    end)
    target:SetScript("OnClick", function(_, mouseButton)
        editSlot(columnIndex, rowIndex, mouseButton)
    end)
    target:SetScript("OnEnter", function(self)
        showTooltip(self, db.stacks[columnIndex][rowIndex])
    end)
    target:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local placeholder = CreateFrame("Frame", nil, target)
    placeholder:SetAllPoints()
    local fill = placeholder:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.08, 0.07, 0.06, 0.9)
    setBorder(placeholder, { 0.34, 0.29, 0.21, 1 })

    local label = placeholder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetTextColor(0.57, 0.49, 0.36)
    label:SetText(rowIndex == 1 and tostring(columnIndex) or "+")
    target.placeholder = placeholder
    target.label = label
    return target
end

local function placeFrames()
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOM", UIParent, "BOTTOM", db.x, db.y)
    editor:ClearAllPoints()
    editor:SetPoint("BOTTOM", UIParent, "BOTTOM", db.x, db.y)
end

local function makeEditor()
    editor = CreateFrame("Frame", nil, UIParent)
    editor:SetSize(WIDTH, HEIGHT + 32)
    editor:SetFrameStrata("HIGH")
    editor:SetMovable(true)
    editor:SetClampedToScreen(true)

    local grip = CreateFrame("Frame", nil, editor)
    grip:SetPoint("TOPLEFT")
    grip:SetPoint("TOPRIGHT", -56, 0)
    grip:SetHeight(26)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function()
        if not InCombatLockdown() then
            editor:StartMoving()
        end
    end)
    grip:SetScript("OnDragStop", function()
        editor:StopMovingOrSizing()
        if not InCombatLockdown() then
            db.x = editor:GetCenter() - UIParent:GetCenter()
            db.y = editor:GetBottom() - UIParent:GetBottom()
            placeFrames()
        end
    end)
    local hint = grip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("LEFT", 2, 0)
    hint:SetText("Drop extra spells above their bar slot  ·  Right-click to remove  ·  Drag here to move")

    local done = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    done:SetSize(52, 24)
    done:SetPoint("TOPRIGHT")
    done:SetText(DONE)
    done:SetScript("OnClick", function()
        editor:Hide()
    end)
    editor:Hide()
end

local function migrateColumn(columnIndex)
    -- Versions before 0.2 stored full sequences under the old default number keys.
    local oldKey = columnIndex <= 10 and tostring(columnIndex % 10)
    local legacy = oldKey and db.stacks[oldKey]
    if not db.stacks[columnIndex] and legacy then
        local page = MainActionBar:GetAttribute("actionpage") or 1
        local actionType, spellID = GetActionInfo((page - 1) * BAR_SLOTS + columnIndex)
        if actionType == "spell" and spellID == legacy[1] then
            table.remove(legacy, 1)
        end
        db.stacks[columnIndex] = legacy
        db.stacks[oldKey] = nil
    end
    db.stacks[columnIndex] = db.stacks[columnIndex] or {}
end

local function initialize()
    StackBarForeverDB = StackBarForeverDB or {}
    db = StackBarForeverDB
    db.stacks = db.stacks or {}
    db.x = db.x or 0
    db.y = db.y or DEFAULT_Y
    if db.enabled == nil then
        db.enabled = true
    end

    bar = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    bar:SetSize(WIDTH, HEIGHT)
    bindingOwner = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    bindingOwner:SetFrameRef("mainbar", MainActionBar)
    bindingOwner:SetFrameRef("display", bar)
    bindingOwner:SetAttribute("stack-enabled", db.enabled)
    bindingOwner:SetAttribute("_onstate-stacksuspended", refreshSecureBindings)
    RegisterStateDriver(bindingOwner, "stacksuspended", "[vehicleui][overridebar][possessbar][petbattle] yes; no")
    makeEditor()
    placeFrames()

    for columnIndex = 1, BAR_SLOTS do
        migrateColumn(columnIndex)
        local column = { slots = {}, targets = {} }
        columns[columnIndex] = column
        for rowIndex = 1, MAX_EXTRAS do
            column.slots[rowIndex] = makeSlot(bar, columnIndex, rowIndex)
            column.targets[rowIndex] = makeTarget(columnIndex, rowIndex)
        end
        column.action = column.slots[1]
        bindingOwner:WrapScript(column.action, "OnClick", selectSpell, advanceStep)
        column.action:HookScript("PostClick", function(_, _, down)
            if not down then
                updateNext(column)
            end
        end)
        applyColumn(columnIndex)
    end
    updateEditor()
    applyBindings()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UPDATE_BINDINGS")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterEvent("SPELL_UPDATE_CHARGES")
events:RegisterEvent("SPELLS_CHANGED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" then
        if not bar and not InCombatLockdown() then
            initialize()
        elseif bar then
            queueBindingRefresh()
        end
    elseif event == "UPDATE_BINDINGS" or event == "PLAYER_ENTERING_WORLD" then
        queueBindingRefresh()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if editor and editor:IsShown() then
            editor:StopMovingOrSizing()
            editor:Hide()
        end
    elseif bar and db.enabled then
        updateSpellDisplays(event == "SPELLS_CHANGED")
    end
end)

SLASH_STACKBARFOREVER1 = "/stackbar"
SlashCmdList.STACKBARFOREVER = function(message)
    if not bar or InCombatLockdown() then
        say("Change your stacks out of combat.")
        return
    end
    local command = message:lower():match("^%s*(%S*)")
    if command == "off" or command == "on" then
        db.enabled = command == "on"
        editor:Hide()
        applyBindings()
        if db.enabled then
            updateSpellDisplays(true)
        end
        say(db.enabled and "Stacks enabled." or "Stacks paused. Your usual keybinds are active.")
    elseif command == "" then
        if not db.enabled then
            say("Use /stackbar on to enable the bar before editing.")
            return
        end
        placeFrames()
        editor:SetShown(not editor:IsShown())
    else
        say("/stackbar to edit  ·  /stackbar off to pause  ·  /stackbar on to resume")
    end
end
