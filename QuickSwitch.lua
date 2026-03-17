--[[
    QuickSwitch v1.3.0
    One draggable specialization bar with a talent dropdown on the active spec.

    /qs         -> show/hide the bar
    /qs lock    -> lock/unlock the bar position
    /qs reset   -> reset the bar position
    /qs config  -> open the settings panel
--]]

local ADDON_NAME = "QuickSwitch"
local DB_KEY = "QuickSwitchDB"
local ADDON_LOGO = "Interface\\AddOns\\QuickSwitch\\qs-logo.png"

local C = {
    BG = { 0.08, 0.08, 0.08, 0.95 },
    BORDER = { 0.22, 0.22, 0.22, 1.00 },
    TEXT = { 0.82, 0.82, 0.82, 1.00 },
    TEXT_HOV = { 1.00, 1.00, 1.00, 1.00 },
}

local BLANK = "Interface/Buttons/WHITE8x8"
local FONT = "Fonts/FRIZQT__.TTF"
local FONT_SZ = 11
local BTN_H = 30
local BTN_PAD = 10
local BTN_MIN_W = 70
local ICON_SZ = 16
local ICON_PAD = 4

local DEFAULTS = {
    specPos = { point = "CENTER", x = 0, y = 80 },
    scale = 1,
    orientation = "VERTICAL",
    verticalMenuSide = "RIGHT",
    horizontalMenuSide = "BOTTOM",
    locked = false,
    hidden = false,
    showMsg = true,
    noSpam = true,
    showOnHover = false,
    hideWhenSingleChoice = false,
    showStarterBuild = false,
    useClassColor = true,
    accentColor = { r = 59 / 255, g = 210 / 255, b = 237 / 255 },
}

local function DB()
    return _G[DB_KEY]
end

local function CopyTableDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = target[key] or {}
            CopyTableDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function InitDB()
    _G[DB_KEY] = _G[DB_KEY] or {}
    CopyTableDefaults(DB(), DEFAULTS)
end

local function Print(msg)
    print("|cFF3BD2ED[QuickSwitch]|r " .. tostring(msg))
end

local qs
local ApplyVisibility
local RebuildBars

local function GetAccentColor()
    local db = DB()
    if db.useClassColor then
        local _, class = UnitClass("player")
        local color = class and RAID_CLASS_COLORS[class]
        if color then
            return color.r, color.g, color.b
        end
    end

    local custom = db.accentColor or DEFAULTS.accentColor
    return custom.r, custom.g, custom.b
end

local function GetOrientation()
    local orientation = tostring(DB().orientation or "VERTICAL"):upper()
    if orientation ~= "HORIZONTAL" then
        orientation = "VERTICAL"
    end
    return orientation
end

local function GetMenuSide()
    if GetOrientation() == "HORIZONTAL" then
        local side = tostring(DB().horizontalMenuSide or "BOTTOM"):upper()
        return side == "TOP" and "TOP" or "BOTTOM"
    end

    local side = tostring(DB().verticalMenuSide or "RIGHT"):upper()
    return side == "LEFT" and "LEFT" or "RIGHT"
end

local function GetMenuArrowGlyph(isOpen)
    local side = GetMenuSide()
    if isOpen then
        if side == "LEFT" then
            return "<"
        elseif side == "RIGHT" then
            return ">"
        elseif side == "TOP" then
            return "^"
        end
        return "v"
    end

    if side == "LEFT" then
        return "<"
    elseif side == "RIGHT" then
        return ">"
    elseif side == "TOP" then
        return "^"
    end
    return "v"
end

local function IsMenuArrowOnLeft()
    return GetMenuSide() == "LEFT"
end

local function RefreshHoverState()
    if not qs.specBar or not qs.specBar.frame then
        return
    end

    local frame = qs.specBar.frame
    local trigger = qs.hoverTrigger
    local menuShown = qs.talentMenu and qs.talentMenu:IsShown()
    local hovered = frame:IsMouseOver()
        or (trigger and trigger:IsMouseOver())
        or (menuShown and qs.talentMenu.frame and qs.talentMenu.frame:IsMouseOver())

    if DB().hidden then
        frame:Hide()
        if trigger then
            trigger:Hide()
        end
        return
    end

    if DB().showOnHover then
        if trigger then
            trigger:ClearAllPoints()
            trigger:SetPoint("CENTER", frame, "CENTER", 0, 0)
            trigger:SetSize(math.max(frame:GetWidth() * frame:GetScale(), 140), math.max(frame:GetHeight() * frame:GetScale(), 34))
            trigger:Show()
        end
        frame:Show()
        frame:SetAlpha(hovered and 1 or 0)
        frame:EnableMouse(hovered)
    else
        if trigger then
            trigger:Hide()
        end
        frame:Show()
        frame:SetAlpha(1)
        frame:EnableMouse(true)
    end
end

local function GetBarScale()
    local scale = tonumber(DB().scale) or 1
    if scale < 0.7 then
        scale = 0.7
    elseif scale > 1.6 then
        scale = 1.6
    end
    return scale
end

local function ApplyBarScale()
    local scale = GetBarScale()
    if qs.specBar and qs.specBar.frame then
        qs.specBar.frame:SetScale(scale)
    end
    if qs.talentMenu and qs.talentMenu.frame then
        qs.talentMenu.frame:SetScale(scale)
    end
    RefreshHoverState()
end

local function ApplyTheme()
    local r, g, b = GetAccentColor()

    if qs.specBar then
        qs.specBar.accent = { r = r, g = g, b = b }
        qs.specBar:Rebuild()
    end

    if qs.talentMenu then
        qs.talentMenu.accent = { r = r, g = g, b = b }
        qs.talentMenu:Rebuild()
    end

    if qs.configFrame then
        qs.configFrame.title:SetTextColor(r, g, b, 1)
        if qs.configFrame.colorSwatch then
            qs.configFrame.colorSwatch:SetBackdropColor(r, g, b, 1)
        end
    end

    ApplyVisibility()
end

qs = {
    specBar = nil,
    talentMenu = nil,
    hoverTrigger = nil,
    specIndex = nil,
    specID = nil,
    specName = nil,
    specIcon = nil,
    talentID = nil,
    talentName = nil,
    configFrame = nil,
    _flight = false,
}

local function RefreshSpec()
    qs.specIndex = GetSpecialization()
    if not qs.specIndex then
        return
    end

    local id, name, _, icon = GetSpecializationInfo(qs.specIndex)
    qs.specID = id
    qs.specName = name or "?"
    qs.specIcon = icon
end

local function RefreshTalent()
    qs.specIndex = GetSpecialization()
    if not qs.specIndex then
        return
    end

    qs.specID = select(1, GetSpecializationInfo(qs.specIndex))
    if not qs.specID then
        return
    end

    local isStarter = C_ClassTalents.GetStarterBuildActive and C_ClassTalents.GetStarterBuildActive() or false
    if isStarter then
        qs.talentID = nil
        qs.talentName = "Starter Build"
        return
    end

    qs.talentID = C_ClassTalents.GetLastSelectedSavedConfigID(qs.specID)
    if qs.talentID then
        local info = C_Traits.GetConfigInfo(qs.talentID)
        qs.talentName = info and info.name or "Unknown"
    else
        qs.talentName = nil
    end
end

local function GetSpecList()
    local list = {}
    for i = 1, (GetNumSpecializations() or 0) do
        local _, name, _, icon = GetSpecializationInfo(i)
        if name then
            list[#list + 1] = {
                index = i,
                name = name,
                icon = icon,
                active = i == qs.specIndex,
            }
        end
    end
    return list
end

local function GetTalentList()
    local list = {}
    if not qs.specID then
        return list
    end

    local isStarter = C_ClassTalents.GetStarterBuildActive and C_ClassTalents.GetStarterBuildActive() or false
    if DB().showStarterBuild and C_ClassTalents.SetStarterBuildActive then
        list[#list + 1] = {
            configID = nil,
            name = "Starter Build",
            active = isStarter,
            isStarter = true,
        }
    end

    local ids = C_ClassTalents.GetConfigIDsBySpecID(qs.specID)
    if not ids then
        return list
    end

    for _, id in ipairs(ids) do
        local info = C_Traits.GetConfigInfo(id)
        list[#list + 1] = {
            configID = id,
            name = info and info.name or "Unknown",
            active = (not isStarter) and id == qs.talentID,
        }
    end

    return list
end

local function ShouldShowTalentMenu()
    if DB().hidden then
        return false
    end
    if not DB().hideWhenSingleChoice then
        return true
    end
    return #GetTalentList() > 1
end

ApplyVisibility = function()
    if qs.specBar then
        if DB().hidden then
            qs.specBar.frame:Hide()
        else
            qs.specBar.frame:Show()
        end
    end

    if qs.talentMenu and DB().hidden then
        qs.talentMenu:Hide()
    end

    RefreshHoverState()
end

RebuildBars = function()
    RefreshSpec()
    RefreshTalent()

    if qs.specBar then
        qs.specBar:Rebuild()
    end
    if qs.talentMenu and qs.talentMenu:IsShown() then
        qs.talentMenu:Rebuild()
    end

    ApplyVisibility()
end

local function SwitchSpec(specIndex)
    if InCombatLockdown() or UnitAffectingCombat("player") then
        Print("Cannot change specialization during combat.")
        return
    end

    C_SpecializationInfo.SetSpecialization(specIndex)
    if DB().showMsg then
        local _, name = GetSpecializationInfo(specIndex)
        if name then
            Print("Switching to " .. name .. ".")
        end
    end

    C_Timer.After(0.4, RebuildBars)
end

local function SwitchTalent(configID)
    if qs._flight then
        return
    end
    if UnitAffectingCombat("player") then
        Print("Cannot change talents while in combat.")
        return
    end
    if C_ClassTalents.HasUnspentTalentPoints and C_ClassTalents.HasUnspentTalentPoints() then
        Print("Unspent talent points - spend them first.")
        return
    end
    if C_ClassTalents.HasUnspentHeroTalentPoints and C_ClassTalents.HasUnspentHeroTalentPoints() then
        Print("Unspent Hero Talent points - spend them first.")
        return
    end
    if C_ClassTalents.CanChangeTalents then
        local ok, reason = C_ClassTalents.CanChangeTalents()
        if not ok then
            Print(type(reason) == "string" and reason ~= "" and reason or "Cannot change talents right now.")
            return
        end
    end

    local wantsStarter = configID == nil
    local starterActive = C_ClassTalents.GetStarterBuildActive and C_ClassTalents.GetStarterBuildActive() or false

    if wantsStarter and starterActive then
        return
    end
    if not wantsStarter and configID == qs.talentID and not starterActive then
        return
    end

    if wantsStarter then
        if not C_ClassTalents.SetStarterBuildActive then
            Print("Starter Build is not available for this specialization.")
            return
        end

        local ok = pcall(C_ClassTalents.SetStarterBuildActive, true)
        if not ok then
            Print("Could not enable Starter Build.")
            return
        end

        qs.talentID = nil
        qs.talentName = "Starter Build"
        if DB().showMsg then
            Print("Switched to: Starter Build")
        end
        if qs.talentMenu and qs.talentMenu:IsShown() then
            qs.talentMenu:Rebuild()
        end
        ApplyVisibility()
        return
    end

    if starterActive and C_ClassTalents.SetStarterBuildActive then
        pcall(C_ClassTalents.SetStarterBuildActive, false)
    end

    qs._flight = true
    C_Timer.After(3, function()
        qs._flight = false
    end)

    local ok = C_ClassTalents.LoadConfig(configID, true)
    if not ok then
        qs._flight = false
        return
    end

    if qs.specID then
        C_ClassTalents.UpdateLastSelectedSavedConfigID(qs.specID, configID)
    end

    qs.talentID = configID
    local info = C_Traits.GetConfigInfo(configID)
    qs.talentName = info and info.name or "Unknown"
    if DB().showMsg then
        Print("Switched to: " .. (qs.talentName or "?"))
    end
    if qs.talentMenu and qs.talentMenu:IsShown() then
        qs.talentMenu:Rebuild()
    end
    ApplyVisibility()
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
    local db = _G[DB_KEY]
    if db and db.noSpam then
        if msg:match("^You have learned") or msg:match("^You have unlearned") then
            return true
        end
    end
end)

local function CreateBar(cfg)
    local bar = {}

    local frame = CreateFrame("Frame", cfg.name, UIParent, "BackdropTemplate")
    frame:SetHeight(BTN_H)
    frame:SetWidth(200)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(10)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = BLANK,
        edgeFile = BLANK,
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    frame:SetBackdropColor(C.BG[1], C.BG[2], C.BG[3], C.BG[4])
    frame:SetBackdropBorderColor(C.BORDER[1], C.BORDER[2], C.BORDER[3], C.BORDER[4])
    frame:SetScript("OnEnter", RefreshHoverState)
    frame:SetScript("OnLeave", function()
        C_Timer.After(0, RefreshHoverState)
    end)

    local topLine = frame:CreateTexture(nil, "OVERLAY")
    topLine:SetHeight(1)
    topLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    topLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    bar.topLine = topLine

    frame:SetScript("OnDragStart", function(self)
        if not DB().locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        local pos = DB()[cfg.posKey]
        pos.point = point or "CENTER"
        pos.x = x or 0
        pos.y = y or 0
    end)

    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(14, 14)
    resize:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    resize:RegisterForDrag("LeftButton")
    resize:EnableMouse(true)
    resize.bg = resize:CreateTexture(nil, "BACKGROUND")
    resize.bg:SetAllPoints()
    resize.bg:SetColorTexture(0, 0, 0, 0)
    resize.lineA = resize:CreateTexture(nil, "OVERLAY")
    resize.lineA:SetSize(8, 1)
    resize.lineA:SetPoint("BOTTOMRIGHT", resize, "BOTTOMRIGHT", -2, 4)
    resize.lineB = resize:CreateTexture(nil, "OVERLAY")
    resize.lineB:SetSize(5, 1)
    resize.lineB:SetPoint("BOTTOMRIGHT", resize, "BOTTOMRIGHT", -2, 8)
    resize.lineC = resize:CreateTexture(nil, "OVERLAY")
    resize.lineC:SetSize(1, 8)
    resize.lineC:SetPoint("BOTTOMRIGHT", resize, "BOTTOMRIGHT", -4, 2)
    resize.lineD = resize:CreateTexture(nil, "OVERLAY")
    resize.lineD:SetSize(1, 5)
    resize.lineD:SetPoint("BOTTOMRIGHT", resize, "BOTTOMRIGHT", -8, 2)
    resize:SetScript("OnEnter", function(self)
        local r, g, b = GetAccentColor()
        self.bg:SetColorTexture(r, g, b, 0.10)
    end)
    resize:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(0, 0, 0, 0)
    end)
    resize:SetScript("OnDragStart", function(self)
        if DB().locked then
            return
        end

        local parent = self:GetParent()
        parent._qsResizeStartX = GetCursorPosition()
        parent._qsResizeStartScale = GetBarScale()
        self:SetScript("OnUpdate", function()
            local currentX = GetCursorPosition()
            local delta = (currentX - parent._qsResizeStartX) / 300
            DB().scale = math.max(0.7, math.min(1.6, parent._qsResizeStartScale + delta))
            ApplyBarScale()
            if qs.configFrame and qs.configFrame.scaleSlider and not qs.configFrame.isRefreshingScale then
                qs.configFrame.isRefreshingScale = true
                qs.configFrame.scaleSlider:SetValue(math.floor(GetBarScale() * 100 + 0.5))
                qs.configFrame.isRefreshingScale = false
            end
        end)
    end)
    resize:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    bar.frame = frame
    bar.cfg = cfg
    bar.buttons = {}
    bar.resizeHandle = resize

    function bar:LoadPos()
        local pos = DB()[cfg.posKey]
        self.frame:ClearAllPoints()
        self.frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    end

    function bar:Rebuild()
        local accentR, accentG, accentB = GetAccentColor()
        local orientation = GetOrientation()
        self.resizeHandle.lineA:SetColorTexture(accentR, accentG, accentB, 0.95)
        self.resizeHandle.lineB:SetColorTexture(accentR, accentG, accentB, 0.70)
        self.resizeHandle.lineC:SetColorTexture(accentR, accentG, accentB, 0.95)
        self.resizeHandle.lineD:SetColorTexture(accentR, accentG, accentB, 0.70)
        self.resizeHandle:SetShown(not DB().locked)

        for _, btn in ipairs(self.buttons) do
            btn:Hide()
        end

        local items = cfg.getItems()
        local totalWidth = 0
        local totalHeight = 0
        local offset = 0
        local maxWidth = 0

        while #self.buttons < #items do
            local btn = CreateFrame("Button", nil, frame)
            btn:SetHeight(BTN_H)

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0)
            btn.bg = bg

            local div = btn:CreateTexture(nil, "OVERLAY")
            div:SetColorTexture(C.BORDER[1], C.BORDER[2], C.BORDER[3], 0.6)
            btn.div = div

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetSize(ICON_SZ, ICON_SZ)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            btn.ico = icon

            local label = btn:CreateFontString(nil, "OVERLAY")
            label:SetFont(FONT, FONT_SZ, "")
            label:SetJustifyH("LEFT")
            label:SetJustifyV("MIDDLE")
            label:SetWordWrap(false)
            btn.lbl = label

            local arrow = CreateFrame("Button", nil, btn)
            arrow:SetSize(22, BTN_H - 6)
            arrow:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            arrow.bg = arrow:CreateTexture(nil, "BACKGROUND")
            arrow.bg:SetAllPoints()
            arrow.bg:SetColorTexture(0, 0, 0, 0)
            arrow.txt = arrow:CreateFontString(nil, "OVERLAY")
            arrow.txt:SetFont(FONT, 12, "")
            arrow.txt:SetPoint("CENTER")
            arrow.txt:SetText(">")
            arrow:Hide()
            btn.arrow = arrow

            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function()
                if not DB().locked then
                    frame:StartMoving()
                end
            end)
            btn:SetScript("OnDragStop", function()
                frame:StopMovingOrSizing()
                local point, _, _, x, y = frame:GetPoint()
                local pos = DB()[cfg.posKey]
                pos.point = point or "CENTER"
                pos.x = x or 0
                pos.y = y or 0
            end)

            btn:SetScript("OnEnter", function(self)
                RefreshHoverState()
                if not self.isActive then
                    self.bg:SetColorTexture(accentR, accentG, accentB, 0.10)
                    self.lbl:SetTextColor(C.TEXT_HOV[1], C.TEXT_HOV[2], C.TEXT_HOV[3], C.TEXT_HOV[4])
                end
                if self.tooltipText then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true)
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                if not self.isActive then
                    self.bg:SetColorTexture(0, 0, 0, 0)
                    self.lbl:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
                end
                C_Timer.After(0, RefreshHoverState)
            end)

            self.buttons[#self.buttons + 1] = btn
        end

        for index, item in ipairs(items) do
            local btn = self.buttons[index]
            btn.isActive = item.active

            if item.icon then
                btn.ico:SetTexture(item.icon)
                btn.ico:SetPoint("LEFT", btn, "LEFT", BTN_PAD, 0)
                btn.ico:Show()
                btn.lbl:ClearAllPoints()
            else
                btn.ico:Hide()
                btn.lbl:ClearAllPoints()
            end

            if item.hasMenu then
                btn.arrow:Show()
                if IsMenuArrowOnLeft() then
                    btn.arrow:ClearAllPoints()
                    btn.arrow:SetPoint("LEFT", btn, "LEFT", 4, 0)
                    if item.icon then
                        btn.ico:ClearAllPoints()
                        btn.ico:SetPoint("LEFT", btn.arrow, "RIGHT", 6, 0)
                        btn.lbl:SetPoint("LEFT", btn.ico, "RIGHT", ICON_PAD, 0)
                    else
                        btn.lbl:SetPoint("LEFT", btn.arrow, "RIGHT", 6, 0)
                    end
                    btn.lbl:SetPoint("RIGHT", btn, "RIGHT", -BTN_PAD, 0)
                else
                    btn.arrow:ClearAllPoints()
                    btn.arrow:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                    if item.icon then
                        btn.ico:ClearAllPoints()
                        btn.ico:SetPoint("LEFT", btn, "LEFT", BTN_PAD, 0)
                        btn.lbl:SetPoint("LEFT", btn.ico, "RIGHT", ICON_PAD, 0)
                    else
                        btn.lbl:SetPoint("LEFT", btn, "LEFT", BTN_PAD, 0)
                    end
                    btn.lbl:SetPoint("RIGHT", btn.arrow, "LEFT", -6, 0)
                end
            else
                btn.arrow:Hide()
                btn.arrow:ClearAllPoints()
                btn.arrow:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                if item.icon then
                    btn.ico:ClearAllPoints()
                    btn.ico:SetPoint("LEFT", btn, "LEFT", BTN_PAD, 0)
                    btn.lbl:SetPoint("LEFT", btn.ico, "RIGHT", ICON_PAD, 0)
                else
                    btn.lbl:SetPoint("LEFT", btn, "LEFT", BTN_PAD, 0)
                end
                btn.lbl:SetPoint("RIGHT", btn, "RIGHT", -BTN_PAD, 0)
            end

            btn.lbl:SetText(item.name)
            btn.lbl:SetWidth(0)

            local textWidth = btn.lbl:GetStringWidth()
            local iconWidth = item.icon and (ICON_SZ + ICON_PAD) or 0
            local menuWidth = item.hasMenu and 26 or 0
            local buttonWidth = math.max(BTN_MIN_W, textWidth + iconWidth + BTN_PAD * 2 + menuWidth)

            btn:SetWidth(buttonWidth)
            btn:SetHeight(BTN_H)
            btn:ClearAllPoints()
            if orientation == "HORIZONTAL" then
                btn:SetPoint("LEFT", frame, "LEFT", offset, 0)
            else
                btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -offset)
            end

            btn.div:ClearAllPoints()
            if orientation == "HORIZONTAL" then
                btn.div:SetHeight(0)
                btn.div:SetWidth(1)
                btn.div:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, -1)
                btn.div:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 1)
            else
                btn.div:SetWidth(0)
                btn.div:SetHeight(1)
                btn.div:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 0)
                btn.div:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 0)
            end

            if item.active then
                btn.bg:SetColorTexture(accentR, accentG, accentB, 0.18)
                btn.lbl:SetTextColor(accentR, accentG, accentB, 1)
                if btn.ico:IsShown() then
                    btn.ico:SetVertexColor(accentR, accentG, accentB)
                end
            else
                btn.bg:SetColorTexture(0, 0, 0, 0)
                btn.lbl:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
                if btn.ico:IsShown() then
                    btn.ico:SetVertexColor(1, 1, 1, 0.75)
                end
            end

            if item.hasMenu then
                btn.arrow.bg:SetColorTexture(0, 0, 0, 0)
                btn.arrow.txt:SetText(GetMenuArrowGlyph(qs.talentMenu and qs.talentMenu:IsShown() and qs.talentMenu.anchorButton == btn))
                if item.active then
                    btn.arrow.txt:SetTextColor(accentR, accentG, accentB, 1)
                else
                    btn.arrow.txt:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
                end
                btn.arrow:SetScript("OnEnter", function(self)
                    RefreshHoverState()
                    self.bg:SetColorTexture(accentR, accentG, accentB, 0.10)
                    self.txt:SetTextColor(C.TEXT_HOV[1], C.TEXT_HOV[2], C.TEXT_HOV[3], C.TEXT_HOV[4])
                end)
                btn.arrow:SetScript("OnLeave", function(self)
                    self.bg:SetColorTexture(0, 0, 0, 0)
                    if item.active then
                        self.txt:SetTextColor(accentR, accentG, accentB, 1)
                    else
                        self.txt:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
                    end
                    C_Timer.After(0, RefreshHoverState)
                end)
                btn.arrow:SetScript("OnClick", function()
                    if qs.talentMenu then
                        qs.talentMenu:Toggle(btn)
                    end
                end)
            else
                btn.arrow:SetScript("OnClick", nil)
                btn.arrow:SetScript("OnEnter", nil)
                btn.arrow:SetScript("OnLeave", nil)
            end

            if index == #items then
                btn.div:Hide()
            else
                btn.div:Show()
            end

            btn.tooltipText = item.tooltip
            btn:SetScript("OnClick", item.active and nil or function()
                cfg.onClick(item)
            end)
            btn:SetScript("OnEnter", function(self)
                if not self.isActive then
                    self.bg:SetColorTexture(accentR, accentG, accentB, 0.10)
                    self.lbl:SetTextColor(C.TEXT_HOV[1], C.TEXT_HOV[2], C.TEXT_HOV[3], C.TEXT_HOV[4])
                end
                if self.tooltipText then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true)
                    GameTooltip:Show()
                end
            end)
            btn:EnableMouse(not item.active)
            btn:Show()

            if orientation == "HORIZONTAL" then
                offset = offset + buttonWidth
                totalWidth = offset
                maxWidth = math.max(maxWidth, buttonWidth)
            else
                offset = offset + BTN_H
                totalHeight = offset
                maxWidth = math.max(maxWidth, buttonWidth)
            end
        end

        if orientation == "HORIZONTAL" then
            frame:SetWidth(totalWidth > 0 and totalWidth or 100)
            frame:SetHeight(BTN_H)
        else
            frame:SetWidth(maxWidth > 0 and maxWidth or 100)
            frame:SetHeight(totalHeight > 0 and totalHeight or BTN_H)
            for index = 1, #items do
                self.buttons[index]:SetWidth(maxWidth)
            end
        end
        self.topLine:SetColorTexture(accentR, accentG, accentB, 1)
    end

    return bar
end

local function CreateHoverTrigger()
    local trigger = CreateFrame("Frame", "QuickSwitchHoverTrigger", UIParent)
    trigger:SetFrameStrata("MEDIUM")
    trigger:SetFrameLevel(9)
    trigger:EnableMouse(true)
    trigger:SetClampedToScreen(true)
    trigger:Hide()
    trigger:SetScript("OnEnter", RefreshHoverState)
    trigger:SetScript("OnLeave", function()
        C_Timer.After(0, RefreshHoverState)
    end)
    return trigger
end

local function CreateTalentMenu()
    local menu = {}
    local frame = CreateFrame("Frame", "QuickSwitchTalentMenu", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(20)
    frame:SetClampedToScreen(true)
    frame:Hide()
    frame:SetBackdrop({
        bgFile = BLANK,
        edgeFile = BLANK,
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    frame:SetBackdropColor(C.BG[1], C.BG[2], C.BG[3], 0.98)
    frame:SetBackdropBorderColor(C.BORDER[1], C.BORDER[2], C.BORDER[3], C.BORDER[4])
    frame:SetScript("OnEnter", RefreshHoverState)
    frame:SetScript("OnLeave", function()
        C_Timer.After(0, RefreshHoverState)
    end)

    local topLine = frame:CreateTexture(nil, "OVERLAY")
    topLine:SetHeight(1)
    topLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    topLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    menu.frame = frame
    menu.topLine = topLine
    menu.buttons = {}
    menu.anchorButton = nil

    function menu:IsShown()
        return self.frame:IsShown()
    end

    function menu:Hide()
        self.anchorButton = nil
        self.frame:Hide()
        if qs.specBar then
            qs.specBar:Rebuild()
        end
    end

    function menu:Rebuild(anchorButton)
        if anchorButton then
            self.anchorButton = anchorButton
        end
        if not self.anchorButton or not ShouldShowTalentMenu() then
            self:Hide()
            return
        end

        local accentR, accentG, accentB = GetAccentColor()
        local items = GetTalentList()
        local width = 180
        local height = 8

        for _, btn in ipairs(self.buttons) do
            btn:Hide()
        end

        while #self.buttons < #items do
            local btn = CreateFrame("Button", nil, frame)
            btn:SetHeight(BTN_H - 4)

            btn.bg = btn:CreateTexture(nil, "BACKGROUND")
            btn.bg:SetAllPoints()
            btn.bg:SetColorTexture(0, 0, 0, 0)

            btn.lbl = btn:CreateFontString(nil, "OVERLAY")
            btn.lbl:SetFont(FONT, FONT_SZ, "")
            btn.lbl:SetPoint("LEFT", btn, "LEFT", 12, 0)
            btn.lbl:SetPoint("RIGHT", btn, "RIGHT", -12, 0)
            btn.lbl:SetJustifyH("LEFT")
            btn.lbl:SetWordWrap(false)

            self.buttons[#self.buttons + 1] = btn
        end

        for index, item in ipairs(items) do
            local btn = self.buttons[index]
            btn.item = item
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -height)
            btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -height)
            btn.lbl:SetText(item.name)
            btn.lbl:SetWidth(0)
            width = math.max(width, btn.lbl:GetStringWidth() + 24)

            if item.active then
                btn.bg:SetColorTexture(accentR, accentG, accentB, 0.18)
                btn.lbl:SetTextColor(accentR, accentG, accentB, 1)
            else
                btn.bg:SetColorTexture(0, 0, 0, 0)
                btn.lbl:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
            end

            btn.tooltipText = item.active and ("Active loadout: " .. item.name) or (item.isStarter and "Switch to Starter Build" or ("Switch to " .. item.name))
            btn:SetScript("OnEnter", function(self)
                RefreshHoverState()
                if not self.item.active then
                    self.bg:SetColorTexture(accentR, accentG, accentB, 0.10)
                    self.lbl:SetTextColor(C.TEXT_HOV[1], C.TEXT_HOV[2], C.TEXT_HOV[3], C.TEXT_HOV[4])
                end
                if self.tooltipText then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true)
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                if self.item.active then
                    self.bg:SetColorTexture(accentR, accentG, accentB, 0.18)
                    self.lbl:SetTextColor(accentR, accentG, accentB, 1)
                else
                    self.bg:SetColorTexture(0, 0, 0, 0)
                    self.lbl:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
                end
                C_Timer.After(0, RefreshHoverState)
            end)
            btn:SetScript("OnClick", function(self)
                SwitchTalent(self.item.configID)
                menu:Hide()
            end)
            btn:EnableMouse(not item.active)
            btn:Show()

            height = height + (BTN_H - 4)
        end

        frame:SetWidth(width)
        frame:SetHeight(height + 8)
        for _, btn in ipairs(self.buttons) do
            btn:SetWidth(width)
        end

        frame:ClearAllPoints()
        local side = GetMenuSide()
        if side == "LEFT" then
            frame:SetPoint("TOPRIGHT", self.anchorButton, "TOPLEFT", -6, 0)
        elseif side == "RIGHT" then
            frame:SetPoint("TOPLEFT", self.anchorButton, "TOPRIGHT", 6, 0)
        elseif side == "TOP" then
            frame:SetPoint("BOTTOMLEFT", self.anchorButton, "TOPLEFT", 0, 6)
        else
            frame:SetPoint("TOPLEFT", self.anchorButton, "BOTTOMLEFT", 0, -6)
        end
        self.topLine:SetColorTexture(accentR, accentG, accentB, 1)
        frame:Show()
    end

    function menu:Toggle(anchorButton)
        if self:IsShown() and self.anchorButton == anchorButton then
            self:Hide()
            return
        end
        self:Rebuild(anchorButton)
        if qs.specBar then
            qs.specBar:Rebuild()
        end
    end

    frame:SetScript("OnHide", function()
        if qs.specBar then
            qs.specBar:Rebuild()
        end
        RefreshHoverState()
    end)

    return menu
end

local function BuildBars()
    qs.specBar = CreateBar({
        name = "QuickSwitchSpecBar",
        posKey = "specPos",
        getItems = function()
            local items = GetSpecList()
            for _, item in ipairs(items) do
                item.tooltip = item.active and ("Current specialization: " .. item.name) or ("Switch to " .. item.name)
                item.hasMenu = item.active and ShouldShowTalentMenu()
            end
            return items
        end,
        onClick = function(item)
            SwitchSpec(item.index)
        end,
    })
    qs.specBar:LoadPos()
    qs.specBar:Rebuild()
    qs.hoverTrigger = CreateHoverTrigger()
    qs.talentMenu = CreateTalentMenu()
    ApplyBarScale()

    ApplyVisibility()
end

local function ToggleVisible()
    DB().hidden = not DB().hidden
    ApplyVisibility()
    Print(DB().hidden and "Bar hidden." or "Bar shown.")
end

local function ToggleLock()
    DB().locked = not DB().locked
    if qs.specBar and qs.specBar.resizeHandle then
        qs.specBar.resizeHandle:SetShown(not DB().locked)
    end
    Print("Bar " .. (DB().locked and "|cFF3BD2EDlocked|r." or "unlocked."))
end

local function ResetPos()
    if qs.specBar then
        DB().specPos = { point = "CENTER", x = 0, y = 80 }
        qs.specBar:LoadPos()
    end
    DB().scale = 1
    ApplyBarScale()
    Print("Positions reset.")
end

local function CreateCheckButton(parent, label, anchor, relativeTo, relativePoint, x, y, onClick)
    local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    button:SetPoint(anchor, relativeTo, relativePoint, x, y)
    button.text:SetText(label)
    button:SetScript("OnClick", function(self)
        onClick(self:GetChecked())
    end)
    return button
end

local function ToggleConfig()
    if qs.configFrame and qs.configFrame:IsShown() then
        qs.configFrame:Hide()
        return
    end

    if not qs.configFrame then
        local frame = CreateFrame("Frame", "QuickSwitchConfigFrame", UIParent, "BackdropTemplate")
        frame:SetSize(720, 520)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetBackdrop({
            bgFile = BLANK,
            edgeFile = BLANK,
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        frame:SetBackdropColor(C.BG[1], C.BG[2], C.BG[3], 0.98)
        frame:SetBackdropBorderColor(C.BORDER[1], C.BORDER[2], C.BORDER[3], C.BORDER[4])

        local logo = frame:CreateTexture(nil, "ARTWORK")
        logo:SetSize(28, 28)
        logo:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -10)
        logo:SetTexture(ADDON_LOGO)
        frame.logo = logo

        local title = frame:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 13, "")
        local accentR, accentG, accentB = GetAccentColor()
        title:SetTextColor(accentR, accentG, accentB, 1)
        title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
        title:SetText("QuickSwitch Settings")
        frame.title = title

        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

        local tabs = {}
        local controlsByTab = {
            general = {},
            layout = {},
            appearance = {},
        }
        local selectedTab = "general"

        local function addToTab(tabName, control)
            controlsByTab[tabName][#controlsByTab[tabName] + 1] = control
        end

        local function setTab(tabName)
            selectedTab = tabName
            local accentR2, accentG2, accentB2 = GetAccentColor()
            for name, list in pairs(controlsByTab) do
                local visible = name == tabName
                for _, control in ipairs(list) do
                    if visible then
                        control:Show()
                    else
                        control:Hide()
                    end
                end
            end

            for name, button in pairs(tabs) do
                if name == tabName then
                    button:SetBackdropColor(accentR2, accentG2, accentB2, 0.18)
                    button.label:SetTextColor(accentR2, accentG2, accentB2, 1)
                else
                    button:SetBackdropColor(0, 0, 0, 0)
                    button.label:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
                end
            end
        end

        local function setChoiceButtonState(button, selected)
            if not button then
                return
            end
            local text = button.GetFontString and button:GetFontString()
            if selected then
                button:SetAlpha(1)
                if text then
                    text:SetTextColor(GetAccentColor())
                end
            else
                button:SetAlpha(0.85)
                if text then
                    text:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
                end
            end
        end

        local function createTab(name, text, anchorTo, xOffset)
            local button = CreateFrame("Button", nil, frame, "BackdropTemplate")
            button:SetSize(100, 24)
            if anchorTo then
                button:SetPoint("LEFT", anchorTo, "RIGHT", xOffset or 6, 0)
            else
                button:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -42)
            end
            button:SetBackdrop({
                bgFile = BLANK,
                edgeFile = BLANK,
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            button:SetBackdropBorderColor(C.BORDER[1], C.BORDER[2], C.BORDER[3], C.BORDER[4])
            button:SetBackdropColor(0, 0, 0, 0)

            local label = button:CreateFontString(nil, "OVERLAY")
            label:SetFont(FONT, FONT_SZ, "")
            label:SetPoint("CENTER")
            label:SetText(text)
            label:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
            button.label = label
            button:SetScript("OnClick", function()
                setTab(name)
            end)
            tabs[name] = button
            return button
        end

        local tabGeneral = createTab("general", "General")
        local tabLayout = createTab("layout", "Layout", tabGeneral)
        local tabAppearance = createTab("appearance", "Appearance", tabLayout)

        frame.locked = CreateCheckButton(frame, "Lock bar position", "TOPLEFT", tabGeneral, "BOTTOMLEFT", -4, -16, function(checked)
            DB().locked = checked
        end)
        addToTab("general", frame.locked)
        frame.messages = CreateCheckButton(frame, "Show chat messages", "TOPLEFT", frame.locked, "BOTTOMLEFT", 0, -8, function(checked)
            DB().showMsg = checked
        end)
        addToTab("general", frame.messages)
        frame.noSpam = CreateCheckButton(frame, "Filter talent learn/unlearn system spam", "TOPLEFT", frame.messages, "BOTTOMLEFT", 0, -8, function(checked)
            DB().noSpam = checked
        end)
        addToTab("general", frame.noSpam)
        frame.mouseover = CreateCheckButton(frame, "Hide bar until mouseover", "TOPLEFT", frame.noSpam, "BOTTOMLEFT", 0, -8, function(checked)
            DB().showOnHover = checked
            RefreshHoverState()
        end)
        addToTab("general", frame.mouseover)
        frame.showStarter = CreateCheckButton(frame, "Show Starter Build in talent dropdown", "TOPLEFT", frame.mouseover, "BOTTOMLEFT", 0, -8, function(checked)
            DB().showStarterBuild = checked
            RebuildBars()
        end)
        addToTab("general", frame.showStarter)
        frame.hideSingle = CreateCheckButton(frame, "Hide talent dropdown when only one choice exists", "TOPLEFT", frame.showStarter, "BOTTOMLEFT", 0, -8, function(checked)
            DB().hideWhenSingleChoice = checked
            ApplyVisibility()
            RebuildBars()
        end)
        addToTab("general", frame.hideSingle)

        local layoutHeader = frame:CreateFontString(nil, "OVERLAY")
        layoutHeader:SetFont(FONT, 13, "")
        layoutHeader:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
        layoutHeader:SetPoint("TOPLEFT", tabLayout, "BOTTOMLEFT", 0, -18)
        layoutHeader:SetText("Bar Layout")
        addToTab("layout", layoutHeader)

        frame.verticalButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.verticalButton:SetSize(110, 24)
        frame.verticalButton:SetPoint("TOPLEFT", layoutHeader, "BOTTOMLEFT", 0, -10)
        frame.verticalButton:SetText("Vertical")
        frame.verticalButton:SetScript("OnClick", function()
            DB().orientation = "VERTICAL"
            RebuildBars()
            setTab(selectedTab)
        end)
        addToTab("layout", frame.verticalButton)

        frame.horizontalButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.horizontalButton:SetSize(110, 24)
        frame.horizontalButton:SetPoint("LEFT", frame.verticalButton, "RIGHT", 8, 0)
        frame.horizontalButton:SetText("Horizontal")
        frame.horizontalButton:SetScript("OnClick", function()
            DB().orientation = "HORIZONTAL"
            RebuildBars()
            setTab(selectedTab)
        end)
        addToTab("layout", frame.horizontalButton)

        frame.verticalSideLabel = frame:CreateFontString(nil, "OVERLAY")
        frame.verticalSideLabel:SetFont(FONT, FONT_SZ, "")
        frame.verticalSideLabel:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
        frame.verticalSideLabel:SetPoint("TOPLEFT", frame.verticalButton, "BOTTOMLEFT", 0, -18)
        frame.verticalSideLabel:SetText("Vertical dropdown side")
        addToTab("layout", frame.verticalSideLabel)

        frame.verticalLeftButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.verticalLeftButton:SetSize(90, 24)
        frame.verticalLeftButton:SetPoint("TOPLEFT", frame.verticalSideLabel, "BOTTOMLEFT", 0, -10)
        frame.verticalLeftButton:SetText("Left")
        frame.verticalLeftButton:SetScript("OnClick", function()
            DB().verticalMenuSide = "LEFT"
            RebuildBars()
            setTab(selectedTab)
        end)
        addToTab("layout", frame.verticalLeftButton)

        frame.verticalRightButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.verticalRightButton:SetSize(90, 24)
        frame.verticalRightButton:SetPoint("LEFT", frame.verticalLeftButton, "RIGHT", 8, 0)
        frame.verticalRightButton:SetText("Right")
        frame.verticalRightButton:SetScript("OnClick", function()
            DB().verticalMenuSide = "RIGHT"
            RebuildBars()
            setTab(selectedTab)
        end)
        addToTab("layout", frame.verticalRightButton)

        frame.horizontalSideLabel = frame:CreateFontString(nil, "OVERLAY")
        frame.horizontalSideLabel:SetFont(FONT, FONT_SZ, "")
        frame.horizontalSideLabel:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
        frame.horizontalSideLabel:SetPoint("TOPLEFT", frame.verticalLeftButton, "BOTTOMLEFT", 0, -18)
        frame.horizontalSideLabel:SetText("Horizontal dropdown side")
        addToTab("layout", frame.horizontalSideLabel)

        frame.horizontalTopButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.horizontalTopButton:SetSize(90, 24)
        frame.horizontalTopButton:SetPoint("TOPLEFT", frame.horizontalSideLabel, "BOTTOMLEFT", 0, -10)
        frame.horizontalTopButton:SetText("Top")
        frame.horizontalTopButton:SetScript("OnClick", function()
            DB().horizontalMenuSide = "TOP"
            RebuildBars()
            setTab(selectedTab)
        end)
        addToTab("layout", frame.horizontalTopButton)

        frame.horizontalBottomButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.horizontalBottomButton:SetSize(90, 24)
        frame.horizontalBottomButton:SetPoint("LEFT", frame.horizontalTopButton, "RIGHT", 8, 0)
        frame.horizontalBottomButton:SetText("Bottom")
        frame.horizontalBottomButton:SetScript("OnClick", function()
            DB().horizontalMenuSide = "BOTTOM"
            RebuildBars()
            setTab(selectedTab)
        end)
        addToTab("layout", frame.horizontalBottomButton)

        local scaleLabel = frame:CreateFontString(nil, "OVERLAY")
        scaleLabel:SetFont(FONT, FONT_SZ, "")
        scaleLabel:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
        scaleLabel:SetPoint("TOPLEFT", frame.horizontalTopButton, "BOTTOMLEFT", 0, -22)
        scaleLabel:SetText("Bar Scale")
        addToTab("layout", scaleLabel)

        local scaleValue = frame:CreateFontString(nil, "OVERLAY")
        scaleValue:SetFont(FONT, FONT_SZ, "")
        scaleValue:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
        scaleValue:SetPoint("LEFT", scaleLabel, "RIGHT", 8, 0)
        addToTab("layout", scaleValue)

        local scaleSlider = CreateFrame("Slider", "QuickSwitchScaleSlider", frame, "OptionsSliderTemplate")
        scaleSlider:SetWidth(220)
        scaleSlider:SetPoint("TOPLEFT", scaleLabel, "BOTTOMLEFT", 0, -12)
        scaleSlider:SetMinMaxValues(70, 160)
        scaleSlider:SetValueStep(1)
        scaleSlider:SetObeyStepOnDrag(true)
        _G.QuickSwitchScaleSliderLow:SetText("70%")
        _G.QuickSwitchScaleSliderHigh:SetText("160%")
        _G.QuickSwitchScaleSliderText:SetText("")
        scaleSlider.valueText = scaleValue
        scaleSlider:SetScript("OnValueChanged", function(self, value)
            local rounded = math.floor(value + 0.5)
            self.valueText:SetText(rounded .. "%")
            if frame.isRefreshingScale then
                return
            end
            DB().scale = rounded / 100
            ApplyBarScale()
        end)
        frame.scaleSlider = scaleSlider
        addToTab("layout", scaleSlider)

        frame.useClassColor = CreateCheckButton(frame, "Use class color for accents", "TOPLEFT", tabAppearance, "BOTTOMLEFT", -4, -16, function(checked)
            DB().useClassColor = checked
            ApplyTheme()
        end)
        addToTab("appearance", frame.useClassColor)

        local rightHeader = frame:CreateFontString(nil, "OVERLAY")
        rightHeader:SetFont(FONT, 13, "")
        rightHeader:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
        rightHeader:SetPoint("TOPLEFT", frame.useClassColor, "BOTTOMLEFT", 4, -18)
        rightHeader:SetText("Accent Color")
        addToTab("appearance", rightHeader)

        local colorLabel = frame:CreateFontString(nil, "OVERLAY")
        colorLabel:SetFont(FONT, FONT_SZ, "")
        colorLabel:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
        colorLabel:SetPoint("TOPLEFT", rightHeader, "BOTTOMLEFT", 0, -14)
        colorLabel:SetText("Custom accent color")
        addToTab("appearance", colorLabel)

        local colorSwatch = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        colorSwatch:SetSize(18, 18)
        colorSwatch:SetPoint("LEFT", colorLabel, "RIGHT", 10, 0)
        colorSwatch:SetBackdrop({
            bgFile = BLANK,
            edgeFile = BLANK,
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        colorSwatch:SetBackdropBorderColor(C.BORDER[1], C.BORDER[2], C.BORDER[3], C.BORDER[4])
        frame.colorSwatch = colorSwatch
        addToTab("appearance", colorSwatch)

        local function createColorSlider(name, labelText, anchor, relativeTo, relativePoint, x, y)
            local label = frame:CreateFontString(nil, "OVERLAY")
            label:SetFont(FONT, FONT_SZ, "")
            label:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
            label:SetPoint(anchor, relativeTo, relativePoint, x, y)
            label:SetText(labelText)

            local valueText = frame:CreateFontString(nil, "OVERLAY")
            valueText:SetFont(FONT, FONT_SZ, "")
            valueText:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
            valueText:SetPoint("LEFT", label, "RIGHT", 8, 0)

            local slider = CreateFrame("Slider", name, frame, "OptionsSliderTemplate")
            slider:SetWidth(220)
            slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -12)
            slider:SetMinMaxValues(0, 255)
            slider:SetValueStep(1)
            slider:SetObeyStepOnDrag(true)
            _G[name .. "Low"]:SetText("0")
            _G[name .. "High"]:SetText("255")
            _G[name .. "Text"]:SetText("")

            slider.valueText = valueText
            addToTab("appearance", label)
            addToTab("appearance", valueText)
            addToTab("appearance", slider)
            return slider, label
        end

        local function applyCustomColorFromSliders()
            local db = DB()
            if not frame.redSlider or not frame.greenSlider or not frame.blueSlider then
                return
            end

            local r = frame.redSlider:GetValue() / 255
            local g = frame.greenSlider:GetValue() / 255
            local b = frame.blueSlider:GetValue() / 255
            db.accentColor = { r = r, g = g, b = b }
            db.useClassColor = false
            frame.useClassColor:SetChecked(false)
            ApplyTheme()
        end

        frame.redSlider = createColorSlider("QuickSwitchRedSlider", "Red", "TOPLEFT", colorLabel, "BOTTOMLEFT", 0, -18)
        frame.greenSlider = createColorSlider("QuickSwitchGreenSlider", "Green", "TOPLEFT", frame.redSlider, "BOTTOMLEFT", 0, -26)
        frame.blueSlider = createColorSlider("QuickSwitchBlueSlider", "Blue", "TOPLEFT", frame.greenSlider, "BOTTOMLEFT", 0, -26)

        frame.redSlider:SetScript("OnValueChanged", function(self, value)
            local rounded = math.floor(value + 0.5)
            self.valueText:SetText(tostring(rounded))
            if frame.isRefreshing then
                return
            end
            applyCustomColorFromSliders()
        end)
        frame.greenSlider:SetScript("OnValueChanged", function(self, value)
            local rounded = math.floor(value + 0.5)
            self.valueText:SetText(tostring(rounded))
            if frame.isRefreshing then
                return
            end
            applyCustomColorFromSliders()
        end)
        frame.blueSlider:SetScript("OnValueChanged", function(self, value)
            local rounded = math.floor(value + 0.5)
            self.valueText:SetText(tostring(rounded))
            if frame.isRefreshing then
                return
            end
            applyCustomColorFromSliders()
        end)

        local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        reset:SetSize(140, 24)
        reset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 20)
        reset:SetText("Reset Positions")
        reset:SetScript("OnClick", ResetPos)

        local help = frame:CreateFontString(nil, "OVERLAY")
        help:SetFont(FONT, FONT_SZ, "")
        help:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3], C.TEXT[4])
        help:SetPoint("BOTTOMLEFT", reset, "TOPLEFT", 0, 26)
        help:SetWidth(650)
        help:SetJustifyH("LEFT")
        help:SetJustifyV("TOP")
        help:SetSpacing(4)
        help:SetText(
            "/qs - toggles the bar\n" ..
            "/qs lock - locks or unlocks the bar position\n" ..
            "/qs reset - resets the bar position\n" ..
            "/qs config - opens the settings panel"
        )
        addToTab("general", reset)
        addToTab("general", help)

        frame.setTab = setTab
        setTab("general")
        qs.configFrame = frame
    end

    qs.configFrame.locked:SetChecked(DB().locked)
    qs.configFrame.messages:SetChecked(DB().showMsg)
    qs.configFrame.noSpam:SetChecked(DB().noSpam)
    qs.configFrame.mouseover:SetChecked(DB().showOnHover)
    qs.configFrame.showStarter:SetChecked(DB().showStarterBuild)
    qs.configFrame.hideSingle:SetChecked(DB().hideWhenSingleChoice)
    qs.configFrame.useClassColor:SetChecked(DB().useClassColor)
    do
        local orientation = GetOrientation()
        local side = GetMenuSide()

        setChoiceButtonState(qs.configFrame.verticalButton, orientation == "VERTICAL")
        setChoiceButtonState(qs.configFrame.horizontalButton, orientation == "HORIZONTAL")
        setChoiceButtonState(qs.configFrame.verticalLeftButton, side == "LEFT")
        setChoiceButtonState(qs.configFrame.verticalRightButton, side == "RIGHT")
        setChoiceButtonState(qs.configFrame.horizontalTopButton, side == "TOP")
        setChoiceButtonState(qs.configFrame.horizontalBottomButton, side == "BOTTOM")
    end
    qs.configFrame.isRefreshingScale = true
    qs.configFrame.scaleSlider:SetValue(math.floor(GetBarScale() * 100 + 0.5))
    qs.configFrame.isRefreshingScale = false
    do
        local custom = DB().accentColor or DEFAULTS.accentColor
        qs.configFrame.isRefreshing = true
        qs.configFrame.redSlider:SetValue(math.floor((custom.r or 0) * 255 + 0.5))
        qs.configFrame.greenSlider:SetValue(math.floor((custom.g or 0) * 255 + 0.5))
        qs.configFrame.blueSlider:SetValue(math.floor((custom.b or 0) * 255 + 0.5))
        qs.configFrame.isRefreshing = false
    end
    do
        local r, g, b = GetAccentColor()
        qs.configFrame.colorSwatch:SetBackdropColor(r, g, b, 1)
    end
    qs.configFrame.verticalSideLabel:SetShown(GetOrientation() == "VERTICAL")
    qs.configFrame.verticalLeftButton:SetShown(GetOrientation() == "VERTICAL")
    qs.configFrame.verticalRightButton:SetShown(GetOrientation() == "VERTICAL")
    qs.configFrame.horizontalSideLabel:SetShown(GetOrientation() == "HORIZONTAL")
    qs.configFrame.horizontalTopButton:SetShown(GetOrientation() == "HORIZONTAL")
    qs.configFrame.horizontalBottomButton:SetShown(GetOrientation() == "HORIZONTAL")
    qs.configFrame.setTab("general")
    qs.configFrame:Show()
end

local function RegisterSlash()
    SLASH_QUICKSWITCH1 = "/qs"
    SlashCmdList.QUICKSWITCH = function(msg)
        msg = (msg or ""):lower():match("^%s*(.-)%s*$") or ""
        if msg == "lock" then
            ToggleLock()
        elseif msg == "reset" then
            ResetPos()
        elseif msg == "config" then
            ToggleConfig()
        else
            ToggleVisible()
        end
    end

    SLASH_QUICKSWITCHLOCK1 = "/qslock"
    SlashCmdList.QUICKSWITCHLOCK = ToggleLock

    SLASH_QUICKSWITCHRESET1 = "/qsreset"
    SlashCmdList.QUICKSWITCHRESET = ResetPos
end

local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ef:RegisterEvent("TRAIT_CONFIG_UPDATED")
ef:RegisterEvent("TRAIT_CONFIG_LIST_UPDATED")
ef:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")

ef:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if (...) ~= ADDON_NAME then
            return
        end

        InitDB()
        RegisterSlash()

        C_Timer.After(1.5, function()
            RefreshSpec()
            RefreshTalent()
            BuildBars()
            ApplyTheme()
            ApplyBarScale()
            RefreshHoverState()
            if DB().showMsg then
                Print("v1.3.0 - /qs to show or hide, /qs config for settings.")
            end
        end)
        self:UnregisterEvent("ADDON_LOADED")
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.2, RebuildBars)
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        local function tryUpdate(attempt)
            attempt = attempt or 0
            if not GetSpecialization() then
                if attempt < 8 then
                    C_Timer.After(0.25, function()
                        tryUpdate(attempt + 1)
                    end)
                end
                return
            end
            RebuildBars()
        end

        C_Timer.After(0.2, tryUpdate)
        return
    end

    if event == "TRAIT_CONFIG_UPDATED" or event == "TRAIT_CONFIG_LIST_UPDATED" then
        C_Timer.After(0.2, RebuildBars)
        return
    end

    if event == "ACTIVE_COMBAT_CONFIG_CHANGED" then
        local _, newID = ...
        qs._flight = false

        local isStarter = C_ClassTalents.GetStarterBuildActive and C_ClassTalents.GetStarterBuildActive() or false
        if isStarter then
            qs.talentID = nil
            qs.talentName = "Starter Build"
        elseif newID and newID ~= 0 then
            qs.talentID = newID
            local info = C_Traits.GetConfigInfo(newID)
            qs.talentName = info and info.name or "Unknown"
        end

        if qs.talentMenu and qs.talentMenu:IsShown() then
            qs.talentMenu:Rebuild()
        end
        ApplyVisibility()
    end
end)

local talentHook = CreateFrame("Frame")
talentHook:RegisterEvent("ADDON_LOADED")
talentHook:SetScript("OnEvent", function(self, _, name)
    if name ~= "Blizzard_PlayerSpells" then
        return
    end

    local container = ClassTalentFrame or (PlayerSpellsFrame and (PlayerSpellsFrame.TalentsFrame or PlayerSpellsFrame))
    if container and not container._qsHooked then
        container:HookScript("OnShow", function()
            C_Timer.After(0.1, RebuildBars)
        end)
        container:HookScript("OnHide", function()
            if qs.talentMenu then
                qs.talentMenu:Hide()
            end
        end)
        container._qsHooked = true
    end

    self:UnregisterEvent("ADDON_LOADED")
end)
