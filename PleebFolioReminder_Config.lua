local _, ns = ...

local CreateFrame = _G.CreateFrame
local GetPhysicalScreenSize = _G.GetPhysicalScreenSize
local UIParent = _G.UIParent
local ipairs = ipairs
local max = math.max

local COLORS = {
  background = { 0.12, 0.12, 0.16, 0.92 },
  panel = { 0.070, 0.070, 0.090, 0.96 },
  border = { 0.20, 0.20, 0.24, 1 },
  control = { 0.070, 0.070, 0.090, 0.96 },
  accent = { 0.20, 0.65, 1.00, 1 },
  text = { 0.96, 0.96, 0.96, 1 },
  muted = { 0.96, 0.96, 0.96, 0.72 },
}

local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local pixelSize
local pixelBackdrops = {}
local optionsFrame
local reminderFrame
local selectedSpecID
local selectedLoadoutID
local RefreshOptionsFrame

local function RefreshPixelContext()
  local _, physicalHeight = GetPhysicalScreenSize()
  local newPixelSize = (768 / physicalHeight) / UIParent:GetEffectiveScale()
  if newPixelSize == pixelSize then
    return false
  end

  pixelSize = newPixelSize
  return true
end

local function RoundToPixel(value)
  local quotient = value / pixelSize
  if quotient >= 0 then
    quotient = math.floor(quotient + 0.5)
  else
    quotient = math.ceil(quotient - 0.5)
  end
  return quotient * pixelSize
end

local function PixelPoint(object, point, relativeTo, relativePoint, offsetX, offsetY)
  object:SetPoint(
    point,
    relativeTo,
    relativePoint,
    RoundToPixel(offsetX or 0),
    RoundToPixel(offsetY or 0)
  )
end

local function PixelSize(object, width, height)
  object:SetSize(RoundToPixel(width), RoundToPixel(height or width))
end

local function PixelWidth(object, width)
  object:SetWidth(RoundToPixel(width))
end

local function PixelHeight(object, height)
  object:SetHeight(RoundToPixel(height))
end

local function CreatePixelTexture(parent, layer, subLevel)
  local texture = parent:CreateTexture(nil, layer, nil, subLevel)
  texture:SetTexture(WHITE8)
  texture:SetSnapToPixelGrid(false)
  texture:SetTexelSnappingBias(0)
  return texture
end

local function EnsurePixelBackdrop(frame)
  if frame._folioPixelBackdrop then
    return frame._folioPixelBackdrop
  end

  local backdrop = {
    background = CreatePixelTexture(frame, "BACKGROUND", -8),
    top = CreatePixelTexture(frame, "BACKGROUND", -7),
    bottom = CreatePixelTexture(frame, "BACKGROUND", -7),
    left = CreatePixelTexture(frame, "BACKGROUND", -7),
    right = CreatePixelTexture(frame, "BACKGROUND", -7),
  }

  frame._folioPixelBackdrop = backdrop
  pixelBackdrops[#pixelBackdrops + 1] = frame
  return backdrop
end

local function LayoutPixelBackdrop(frame)
  local backdrop = EnsurePixelBackdrop(frame)

  backdrop.background:ClearAllPoints()
  backdrop.background:SetAllPoints(frame)

  backdrop.top:ClearAllPoints()
  PixelPoint(backdrop.top, "TOPLEFT", frame, "TOPLEFT", 0, 0)
  PixelPoint(backdrop.top, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  PixelHeight(backdrop.top, pixelSize)

  backdrop.bottom:ClearAllPoints()
  PixelPoint(backdrop.bottom, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  PixelPoint(backdrop.bottom, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  PixelHeight(backdrop.bottom, pixelSize)

  backdrop.left:ClearAllPoints()
  PixelPoint(backdrop.left, "TOPLEFT", frame, "TOPLEFT", 0, 0)
  PixelPoint(backdrop.left, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  PixelWidth(backdrop.left, pixelSize)

  backdrop.right:ClearAllPoints()
  PixelPoint(backdrop.right, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  PixelPoint(backdrop.right, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  PixelWidth(backdrop.right, pixelSize)
end

local function SetBorderColor(frame, color)
  local backdrop = EnsurePixelBackdrop(frame)
  backdrop.top:SetVertexColor(color[1], color[2], color[3], color[4])
  backdrop.bottom:SetVertexColor(color[1], color[2], color[3], color[4])
  backdrop.left:SetVertexColor(color[1], color[2], color[3], color[4])
  backdrop.right:SetVertexColor(color[1], color[2], color[3], color[4])
end

local function SetBackdrop(frame, color, border)
  local backdrop = EnsurePixelBackdrop(frame)
  LayoutPixelBackdrop(frame)
  backdrop.background:SetVertexColor(color[1], color[2], color[3], color[4])
  SetBorderColor(frame, border)
end

local function RefreshPixelLayout()
  if not RefreshPixelContext() then
    return
  end

  for _, frame in ipairs(pixelBackdrops) do
    LayoutPixelBackdrop(frame)
  end
end

RefreshPixelContext()

local function CreateLabel(parent, text, size, color)
  local label = parent:CreateFontString(nil, "OVERLAY")
  color = color or COLORS.text
  label:SetFont(_G.STANDARD_TEXT_FONT, size or 12, "")
  label:SetText(text or "")
  label:SetTextColor(color[1], color[2], color[3], color[4])
  label:SetJustifyH("LEFT")
  return label
end

local function CreateButton(parent, text)
  local button = CreateFrame("Button", nil, parent)
  PixelHeight(button, 28)
  SetBackdrop(button, COLORS.control, COLORS.border)

  local label = CreateLabel(button, text, 11, COLORS.text)
  label:SetPoint("LEFT", button, "LEFT", 7, 0)
  label:SetPoint("RIGHT", button, "RIGHT", -7, 0)
  label:SetJustifyH("CENTER")
  button.Text = label

  button:SetScript("OnEnter", function(self)
    if self:IsEnabled() then
      SetBorderColor(self, COLORS.accent)
    end
  end)
  button:SetScript("OnLeave", function(self)
    SetBorderColor(self, self._selected and COLORS.accent or COLORS.border)
  end)

  return button
end

local function SetButtonSelected(button, selected)
  button._selected = selected
  SetBorderColor(button, selected and COLORS.accent or COLORS.border)
end

local function CreateCheckButton(parent, text)
  local check = CreateFrame("CheckButton", nil, parent)
  PixelSize(check, 18, 18)
  SetBackdrop(check, COLORS.control, COLORS.border)

  local mark = CreatePixelTexture(check, "ARTWORK")
  PixelPoint(mark, "TOPLEFT", check, "TOPLEFT", 4, -4)
  PixelPoint(mark, "BOTTOMRIGHT", check, "BOTTOMRIGHT", -4, 4)
  mark:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], COLORS.accent[4])
  check.Mark = mark

  local label = CreateLabel(check, text, 12, COLORS.text)
  label:SetPoint("LEFT", check, "RIGHT", 8, 0)
  check.Label = label

  return check
end

local function SetCheckValue(check, checked)
  check:SetChecked(checked)
  check.Mark:SetShown(checked)
end

local function CreateOverlay(frame, scroll, frameLevel, borderColor)
  local overlay = CreateFrame("Frame", nil, frame)
  PixelPoint(overlay, "TOPLEFT", frame.Header, "BOTTOMLEFT", 14, -12)
  PixelPoint(overlay, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
  overlay:SetFrameLevel(scroll:GetFrameLevel() + frameLevel)
  overlay:EnableMouse(true)

  if borderColor then
    SetBackdrop(overlay, COLORS.panel, borderColor)
  end

  overlay:Hide()
  return overlay
end

local function EnsureReminderFrame()
  if reminderFrame then
    return reminderFrame
  end

  reminderFrame = CreateFrame("Frame", nil, UIParent)
  PixelSize(reminderFrame, 520, 44)
  PixelPoint(reminderFrame, "CENTER", UIParent, "CENTER", 0, 180)
  reminderFrame:SetFrameStrata("DIALOG")
  reminderFrame:SetFrameLevel(100)
  SetBackdrop(reminderFrame, COLORS.panel, COLORS.accent)
  reminderFrame:EnableMouse(true)
  reminderFrame:Hide()

  local text = CreateLabel(reminderFrame, "", 12, COLORS.text)
  text:SetPoint("LEFT", reminderFrame, "LEFT", 12, 0)
  text:SetPoint("RIGHT", reminderFrame, "RIGHT", -48, 0)
  text:SetJustifyH("CENTER")
  reminderFrame.Text = text

  local close = CreateButton(reminderFrame, "X")
  PixelSize(close, 28, 28)
  PixelPoint(close, "RIGHT", reminderFrame, "RIGHT", -8, 0)
  close:SetScript("OnClick", function()
    reminderFrame:Hide()
  end)
  return reminderFrame
end

function ns.ShowReminder(text)
  RefreshPixelLayout()
  local frame = EnsureReminderFrame()
  frame.Text:SetText(text)
  frame:Show()
end

function ns.HideReminder()
  if reminderFrame then
    reminderFrame:Hide()
  end
end

local function CreateOptionsFrame()
  local frame = CreateFrame("Frame", "PleebFolioReminderOptions", UIParent)
  PixelSize(frame, 560, 680)
  frame._standaloneWidth = frame:GetWidth()
  frame._standaloneHeight = frame:GetHeight()
  PixelPoint(frame, "CENTER", UIParent, "CENTER", 0, 0)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetResizeBounds(520, 420)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if self._standalone then
      self:StartMoving()
    end
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
  end)
  SetBackdrop(frame, COLORS.background, COLORS.border)

  local header = CreateFrame("Frame", nil, frame)
  PixelPoint(header, "TOPLEFT", frame, "TOPLEFT", 1, -1)
  PixelPoint(header, "TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  PixelHeight(header, 70)
  SetBackdrop(header, COLORS.panel, COLORS.border)
  frame.Header = header

  local title = CreateLabel(header, "PleebFolio Reminder", 20, COLORS.text)
  PixelPoint(title, "TOPLEFT", header, "TOPLEFT", 18, -13)

  local subtitle = CreateLabel(
    header,
    "Omnium Folio choices by specialization and talent loadout",
    11,
    COLORS.muted
  )
  PixelPoint(subtitle, "TOPLEFT", title, "BOTTOMLEFT", 0, -6)

  local close = CreateButton(header, "X")
  PixelSize(close, 28, 28)
  PixelPoint(close, "TOPRIGHT", header, "TOPRIGHT", -12, -12)
  close:SetScript("OnClick", function()
    frame:Hide()
  end)
  frame.CloseButton = close

  local resize = CreateFrame("Button", nil, frame)
  PixelSize(resize, 16, 16)
  PixelPoint(resize, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
  resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  resize:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" and frame._standalone then
      frame:StartSizing("BOTTOMRIGHT")
    end
  end)
  resize:SetScript("OnMouseUp", function()
    if frame._standalone then
      frame:StopMovingOrSizing()
      frame._standaloneWidth = RoundToPixel(frame:GetWidth())
      frame._standaloneHeight = RoundToPixel(frame:GetHeight())
      PixelSize(frame, frame._standaloneWidth, frame._standaloneHeight)
      ns.RefreshOptions()
    end
  end)
  resize:Hide()
  frame.ResizeButton = resize

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  PixelPoint(scroll, "TOPLEFT", header, "BOTTOMLEFT", 14, -12)
  PixelPoint(scroll, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 14)
  local content = CreateFrame("Frame", nil, scroll)
  PixelSize(content, 492, 1)
  scroll:SetScrollChild(content)
  frame.Content = content

  scroll:SetScript("OnSizeChanged", function(_, width)
    PixelWidth(content, max(1, width - 4))
  end)

  local enabled = CreateCheckButton(content, "Enable PleebFolio Reminder")
  PixelPoint(enabled, "TOPLEFT", content, "TOPLEFT", 4, -4)
  enabled:SetScript("OnClick", function(self)
    ns.SetEnabled(self:GetChecked())
  end)
  frame.EnabledCheck = enabled

  local autoApply = CreateCheckButton(content, "Apply saved Folio choices automatically")
  PixelPoint(autoApply, "TOPLEFT", enabled, "BOTTOMLEFT", 0, -16)
  autoApply:SetScript("OnClick", function(self)
    ns.SetAutoApply(self:GetChecked())
  end)
  frame.AutoApplyCheck = autoApply

  local help = CreateLabel(
    content,
    "Specialization rules are defaults. Loadout rules override only the Folio choices you set for that loadout.",
    11,
    COLORS.muted
  )
  PixelPoint(help, "TOPLEFT", autoApply, "BOTTOMLEFT", 0, -16)
  PixelPoint(help, "RIGHT", content, "RIGHT", -6, 0)
  help:SetWordWrap(true)
  local specTitle = CreateLabel(content, "Specialization", 13, COLORS.text)
  PixelPoint(specTitle, "TOPLEFT", help, "BOTTOMLEFT", 0, -20)
  frame.SpecTitle = specTitle

  frame.SpecButtons = {}
  frame.ScopeButtons = {}
  frame.NodeRows = {}

  frame.ScopeTitle = CreateLabel(content, "Rule", 13, COLORS.text)

  local scopeHint = CreateLabel(content, "", 11, COLORS.muted)
  scopeHint:SetWordWrap(true)
  frame.ScopeHint = scopeHint

  local copyButton = CreateButton(content, "Copy current Folio")
  PixelWidth(copyButton, 160)
  copyButton:SetScript("OnClick", function()
    ns.CopyCurrentToScope(selectedSpecID, selectedLoadoutID)
  end)
  frame.CopyButton = copyButton

  local clearButton = CreateButton(content, "Clear this rule")
  PixelWidth(clearButton, 130)
  clearButton:SetScript("OnClick", function()
    ns.ClearScope(selectedSpecID, selectedLoadoutID)
  end)
  frame.ClearButton = clearButton

  local lockOverlay = CreateOverlay(frame, scroll, 40, COLORS.accent)
  local lockText = CreateLabel(lockOverlay, "", 13, COLORS.text)
  lockText:SetPoint("CENTER")
  lockText:SetJustifyH("CENTER")
  frame.LockOverlay = lockOverlay
  frame.LockText = lockText

  local changeOverlay = CreateOverlay(frame, scroll, 30)
  local changePrompt = CreateFrame("Frame", nil, changeOverlay)
  PixelSize(changePrompt, 480, 220)
  PixelPoint(changePrompt, "CENTER", changeOverlay, "CENTER", 0, 0)
  SetBackdrop(changePrompt, COLORS.panel, COLORS.accent)

  local changeTitle = CreateLabel(changePrompt, "Folio choice changed", 15, COLORS.text)
  PixelPoint(changeTitle, "TOPLEFT", changePrompt, "TOPLEFT", 16, -16)

  local changeText = CreateLabel(changePrompt, "", 12, COLORS.muted)
  PixelPoint(changeText, "TOPLEFT", changeTitle, "BOTTOMLEFT", 0, -10)
  PixelPoint(changeText, "RIGHT", changePrompt, "RIGHT", -16, 0)
  changeText:SetWordWrap(true)
  changePrompt.Text = changeText

  changePrompt.Buttons = {}
  for index = 1, 4 do
    local button = CreateButton(changePrompt, "")
    PixelHeight(button, 30)
    button:Hide()
    changePrompt.Buttons[index] = button
  end

  frame.ChangePromptOverlay = changeOverlay
  frame.ChangePrompt = changePrompt

  frame:SetScript("OnShow", function(self)
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("CHALLENGE_MODE_START")
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    self:RegisterEvent("CHALLENGE_MODE_RESET")
    self:RegisterEvent("DISPLAY_SIZE_CHANGED")
    self:RegisterEvent("UI_SCALE_CHANGED")
    RefreshOptionsFrame(self)
  end)
  frame:SetScript("OnHide", function(self)
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("CHALLENGE_MODE_START")
    self:UnregisterEvent("CHALLENGE_MODE_COMPLETED")
    self:UnregisterEvent("CHALLENGE_MODE_RESET")
    self:UnregisterEvent("DISPLAY_SIZE_CHANGED")
    self:UnregisterEvent("UI_SCALE_CHANGED")
    self:StopMovingOrSizing()

    if self.ChangePromptOverlay:IsShown() then
      ns.ResolveManualChange("temporary")
    end
  end)
  frame:SetScript("OnEvent", function(self, event)
    if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
      RefreshPixelLayout()
    end
    RefreshOptionsFrame(self)
  end)

  frame:Hide()
  return frame
end

local function EnsureOptionsFrame()
  if not optionsFrame then
    optionsFrame = CreateOptionsFrame()
  end
  return optionsFrame
end

local function EnsureButton(pool, parent, index)
  if not pool[index] then
    pool[index] = CreateButton(parent, "")
  end
  return pool[index]
end

local function CreateNodeRow(frame)
  local row = CreateFrame("Frame", nil, frame.Content)
  PixelHeight(row, 92)
  SetBackdrop(row, COLORS.panel, COLORS.border)

  local title = CreateLabel(row, "", 12, COLORS.text)
  PixelPoint(title, "TOPLEFT", row, "TOPLEFT", 10, -9)
  row.Title = title

  local status = CreateLabel(row, "", 10, COLORS.muted)
  PixelPoint(status, "TOPRIGHT", row, "TOPRIGHT", -10, -10)
  status:SetJustifyH("RIGHT")
  row.Status = status

  local message = CreateLabel(row, "", 11, COLORS.muted)
  PixelPoint(message, "TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  PixelPoint(message, "RIGHT", row, "RIGHT", -10, 0)
  message:Hide()
  row.Message = message

  row.Buttons = {}
  return row
end

local function EnsureNodeRow(frame, index)
  if not frame.NodeRows[index] then
    frame.NodeRows[index] = CreateNodeRow(frame)
  end
  return frame.NodeRows[index]
end

local function HideUnused(pool, used)
  for index = used + 1, #pool do
    pool[index]:Hide()
  end
end

local function LayoutButtonGrid(buttons, count, anchor, width, columns)
  local spacing = RoundToPixel(6)
  local buttonWidth = RoundToPixel((width - spacing * (columns - 1)) / columns)
  local rows = math.ceil(count / columns)

  for index = 1, count do
    local button = buttons[index]
    local column = (index - 1) % columns
    local row = math.floor((index - 1) / columns)
    button:ClearAllPoints()
    PixelWidth(button, buttonWidth)
    PixelPoint(
      button,
      "TOPLEFT",
      anchor,
      "BOTTOMLEFT",
      column * (buttonWidth + spacing),
      -10 - row * 34
    )
  end

  return rows * 34
end

local function LayoutChoiceButtons(row, count, width)
  local spacing = RoundToPixel(5)
  local buttonWidth = RoundToPixel((width - 20 - spacing * (count - 1)) / count)

  for index = 1, count do
    local button = row.Buttons[index]
    button:ClearAllPoints()
    PixelWidth(button, buttonWidth)
    PixelPoint(
      button,
      "BOTTOMLEFT",
      row,
      "BOTTOMLEFT",
      10 + (index - 1) * (buttonWidth + spacing),
      10
    )
  end
end

local function ContainsID(items, id)
  for _, item in ipairs(items) do
    if item.id == id then
      return true
    end
  end
  return false
end

RefreshOptionsFrame = function(frame)
  if not frame:IsShown() then
    return
  end

  local lockReason = ns.GetFolioLockReason()
  if lockReason then
    frame.ChangePromptOverlay:Hide()
    frame.LockText:SetText(
      lockReason == "keystone"
        and "PleebFolio settings are unavailable during an active Mythic+ run."
        or "PleebFolio settings are unavailable during combat."
    )
    frame.LockOverlay:Show()
    return
  end

  frame.LockOverlay:Hide()
  SetCheckValue(frame.EnabledCheck, ns.db.enabled)
  SetCheckValue(frame.AutoApplyCheck, ns.db.autoApply)
  frame.AutoApplyCheck:SetEnabled(ns.db.enabled)
  frame.AutoApplyCheck.Label:SetAlpha(ns.db.enabled and 1 or 0.45)

  local specs = ns.GetSpecs()
  if #specs == 0 then
    return
  end

  if not selectedSpecID or not ContainsID(specs, selectedSpecID) then
    local currentSpecID = ns.GetCurrentSpecID()
    selectedSpecID = ContainsID(specs, currentSpecID) and currentSpecID or specs[1].id
    selectedLoadoutID = nil
  end

  local content = frame.Content
  local width = content:GetWidth() - 10
  local y = -150

  for index, spec in ipairs(specs) do
    local specID = spec.id
    local button = EnsureButton(frame.SpecButtons, content, index)
    button.Text:SetText(spec.name)
    button:SetScript("OnClick", function()
      selectedSpecID = specID
      selectedLoadoutID = nil
      RefreshOptionsFrame(frame)
    end)
    SetButtonSelected(button, specID == selectedSpecID)
    button:Show()
  end
  HideUnused(frame.SpecButtons, #specs)

  y = y - LayoutButtonGrid(
    frame.SpecButtons,
    #specs,
    frame.SpecTitle,
    width,
    math.min(4, #specs)
  )

  frame.ScopeTitle:ClearAllPoints()
  PixelPoint(frame.ScopeTitle, "TOPLEFT", content, "TOPLEFT", 4, y - 10)

  local loadouts = ns.GetLoadoutsForSpec(selectedSpecID)
  if selectedLoadoutID and not ContainsID(loadouts, selectedLoadoutID) then
    selectedLoadoutID = nil
  end

  local defaultButton = EnsureButton(frame.ScopeButtons, content, 1)
  defaultButton.Text:SetText("Spec default")
  defaultButton:SetScript("OnClick", function()
    selectedLoadoutID = nil
    RefreshOptionsFrame(frame)
  end)
  SetButtonSelected(defaultButton, not selectedLoadoutID)
  defaultButton:Show()

  for index, loadout in ipairs(loadouts) do
    local loadoutID = loadout.id
    local button = EnsureButton(frame.ScopeButtons, content, index + 1)
    button.Text:SetText(loadout.name)
    button:SetScript("OnClick", function()
      selectedLoadoutID = loadoutID
      RefreshOptionsFrame(frame)
    end)
    SetButtonSelected(button, selectedLoadoutID == loadoutID)
    button:Show()
  end

  local scopeCount = #loadouts + 1
  HideUnused(frame.ScopeButtons, scopeCount)
  y = y - LayoutButtonGrid(frame.ScopeButtons, scopeCount, frame.ScopeTitle, width, 3) - 52

  frame.ScopeHint:ClearAllPoints()
  PixelPoint(frame.ScopeHint, "TOPLEFT", content, "TOPLEFT", 4, y)
  PixelPoint(frame.ScopeHint, "RIGHT", content, "RIGHT", -6, 0)
  if selectedLoadoutID then
    frame.ScopeHint:SetText(
      "Only choices set here override the " .. ns.GetSpecName(selectedSpecID) .. " default."
    )
  else
    frame.ScopeHint:SetText(
      "Used by every " .. ns.GetSpecName(selectedSpecID) .. " loadout unless that loadout has its own choice."
    )
  end

  frame.CopyButton:ClearAllPoints()
  PixelPoint(frame.CopyButton, "TOPLEFT", frame.ScopeHint, "BOTTOMLEFT", 0, -12)
  frame.ClearButton:ClearAllPoints()
  PixelPoint(frame.ClearButton, "LEFT", frame.CopyButton, "RIGHT", 8, 0)
  y = y - 82

  local choiceNodes = ns.GetFolioChoiceNodes()
  if #choiceNodes == 0 then
    local row = EnsureNodeRow(frame, 1)
    row:ClearAllPoints()
    PixelPoint(row, "TOPLEFT", content, "TOPLEFT", 4, y)
    PixelPoint(row, "RIGHT", content, "RIGHT", -4, 0)
    PixelHeight(row, 64)
    row.Title:SetText("Omnium Folio")
    row.Status:SetText("")
    row.Message:SetText("No Folio choice nodes are currently available on this character.")
    row.Message:Show()
    HideUnused(row.Buttons, 0)
    row:Show()
    HideUnused(frame.NodeRows, 1)
    PixelHeight(content, -y + 90)
    return
  end

  for index, node in ipairs(choiceNodes) do
    local nodeID = node.id
    local row = EnsureNodeRow(frame, index)
    row:ClearAllPoints()
    PixelPoint(row, "TOPLEFT", content, "TOPLEFT", 4, y)
    PixelPoint(row, "RIGHT", content, "RIGHT", -4, 0)
    PixelHeight(row, 92)
    row.Title:SetText("Folio choice " .. index)
    row.Message:Hide()
    row.Status:SetText(node.owned and ("Current: " .. (node.currentName or "Unknown")) or "Not unlocked")

    local storedEntryID = ns.GetStoredRule(selectedSpecID, selectedLoadoutID, nodeID)
    local buttonCount = #node.entries + 1

    for buttonIndex = 1, buttonCount do
      local button = EnsureButton(row.Buttons, row, buttonIndex)
      local entry = node.entries[buttonIndex - 1]
      local entryID = entry and entry.id or nil

      button.Text:SetText(entry and entry.name or (selectedLoadoutID and "Spec default" or "No rule"))
      button:SetEnabled(not entry or (node.owned and entry.available))
      button:SetAlpha(button:IsEnabled() and 1 or 0.45)
      SetButtonSelected(button, storedEntryID == entryID)
      button:SetScript("OnClick", function()
        ns.SetRule(selectedSpecID, selectedLoadoutID, nodeID, entryID)
      end)
      button:Show()
    end

    HideUnused(row.Buttons, buttonCount)
    LayoutChoiceButtons(row, buttonCount, width)
    row:Show()
    y = y - 102
  end

  HideUnused(frame.NodeRows, #choiceNodes)
  PixelHeight(content, -y + 20)
end

local function ShowOptionsFrame(frame)
  if frame:IsShown() then
    RefreshOptionsFrame(frame)
  else
    frame:Show()
  end
end

local function PrepareOptionsFrame(frame, parent, standalone)
  RefreshPixelLayout()
  frame._standalone = standalone
  frame:SetParent(parent)
  frame:ClearAllPoints()
  frame:SetResizable(standalone)
  frame.CloseButton:SetShown(standalone)
  frame.ResizeButton:SetShown(standalone)
end

function ns.RefreshOptions()
  if optionsFrame and optionsFrame:IsShown() then
    RefreshOptionsFrame(optionsFrame)
  end
end

function ns.OpenOptions(anchorFrame)
  local frame = EnsureOptionsFrame()
  PrepareOptionsFrame(frame, UIParent, true)

  if anchorFrame then
    PixelPoint(frame, "LEFT", anchorFrame, "RIGHT", 12, 0)
  else
    PixelPoint(frame, "CENTER", UIParent, "CENTER", 0, 0)
  end

  PixelSize(frame, frame._standaloneWidth, frame._standaloneHeight)
  ShowOptionsFrame(frame)
end

function ns.OpenOptionsForCurrentContext(anchorFrame)
  if not ns.GetFolioLockReason() then
    selectedSpecID = ns.GetCurrentSpecID()
    selectedLoadoutID = selectedSpecID and ns.GetCurrentLoadoutID(selectedSpecID) or nil
  end

  ns.OpenOptions(anchorFrame)
end

function ns.HideManualChangePrompt()
  if optionsFrame then
    optionsFrame.ChangePromptOverlay:Hide()
  end
end

function ns.ShowManualChangePrompt(change)
  selectedSpecID = change.specID
  selectedLoadoutID = change.loadoutID

  local frame = EnsureOptionsFrame()
  if not frame:IsShown() then
    ns.OpenOptions()
  end

  local prompt = frame.ChangePrompt
  local actions

  if change.loadoutID and change.source == "spec" then
    prompt.Text:SetText(
      change.currentName
        .. " is now selected. "
        .. change.loadoutName
        .. " inherits the "
        .. change.specName
        .. " default: "
        .. change.savedName
        .. "."
    )
    actions = {
      { text = "Save for this loadout", action = "save_loadout" },
      { text = "Change spec default", action = "save_spec" },
      { text = "Keep temporarily", action = "temporary" },
      { text = "Restore " .. change.savedName, action = "restore" },
    }
  else
    local scopeName = change.source == "loadout" and change.loadoutName or change.specName
    prompt.Text:SetText(
      change.currentName
        .. " is now selected instead of the saved "
        .. change.savedName
        .. " choice for "
        .. scopeName
        .. "."
    )
    actions = {
      {
        text = "Save " .. change.currentName,
        action = change.source == "loadout" and "save_loadout" or "save_spec",
      },
      { text = "Keep temporarily", action = "temporary" },
      { text = "Restore " .. change.savedName, action = "restore" },
    }
  end

  local spacing = RoundToPixel(8)
  local buttonWidth = RoundToPixel((448 - spacing) / 2)

  for index, button in ipairs(prompt.Buttons) do
    local action = actions[index]
    button:ClearAllPoints()

    if action then
      local column = (index - 1) % 2
      local row = math.floor((index - 1) / 2)
      button.Text:SetText(action.text)
      PixelWidth(button, buttonWidth)
      PixelPoint(
        button,
        "BOTTOMLEFT",
        prompt,
        "BOTTOMLEFT",
        16 + column * (buttonWidth + spacing),
        16 + (1 - row) * 38
      )
      button:SetScript("OnClick", function()
        ns.ResolveManualChange(action.action)
      end)
      button:Show()
    else
      button:Hide()
    end
  end

  frame.ChangePromptOverlay:Show()
end

function ns.MountPleebUIOptions(host)
  local frame = EnsureOptionsFrame()
  PrepareOptionsFrame(frame, host, false)
  frame:SetAllPoints(host)
  ShowOptionsFrame(frame)
  return frame
end
