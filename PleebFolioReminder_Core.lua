local ADDON_NAME, ns = ...

local CreateFrame = _G.CreateFrame
local GetNumSpecializations = _G.GetNumSpecializations
local GetSpecializationInfoByID = _G.GetSpecializationInfoByID
local hooksecurefunc = _G.hooksecurefunc
local InCombatLockdown = _G.InCombatLockdown
local ipairs = ipairs
local pairs = pairs
local remove = table.remove
local sort = table.sort

local OMNIUM_SYSTEM_ID = 48
local OMNIUM_TREE_ID = 1186

local eventFrame = CreateFrame("Frame")
local runtimeEnabled = false
local pendingCommitConfigID
local manualChange
local temporaryContext
local RefreshRuntime

local RUNTIME_EVENTS = {
  "PLAYER_ENTERING_WORLD",
  "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
  "SELECTED_LOADOUT_CHANGED",
  "ACTIVE_COMBAT_CONFIG_CHANGED",
  "TRAIT_CONFIG_CREATED",
  "TRAIT_CONFIG_DELETED",
  "TRAIT_CONFIG_LIST_UPDATED",
  "TRAIT_CONFIG_UPDATED",
  "CONFIG_COMMIT_FAILED",
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
  "CHALLENGE_MODE_START",
  "CHALLENGE_MODE_COMPLETED",
  "CHALLENGE_MODE_RESET",
}

local CONTEXT_EVENTS = {
  ACTIVE_PLAYER_SPECIALIZATION_CHANGED = true,
  SELECTED_LOADOUT_CHANGED = true,
  ACTIVE_COMBAT_CONFIG_CHANGED = true,
}

local function InitializeDB()
  if not _G.PleebFolioReminderDB then
    _G.PleebFolioReminderDB = {
      enabled = true,
      autoApply = true,
      specs = {},
      loadouts = {},
    }
  end

  ns.db = _G.PleebFolioReminderDB
end

local function GetOmniumConfigID()
  return C_Traits.GetConfigIDBySystemID(OMNIUM_SYSTEM_ID)
end

function ns.GetFolioLockReason()
  if InCombatLockdown() then
    return "combat"
  end

  if C_ChallengeMode.IsChallengeModeActive() then
    return "keystone"
  end
end

function ns.GetCurrentSpecID()
  local specIndex = C_SpecializationInfo.GetSpecialization()
  local specID = specIndex and C_SpecializationInfo.GetSpecializationInfo(specIndex) or nil
  if specID == 0 then
    return nil
  end

  return specID
end

function ns.GetSpecs()
  local specs = {}

  for index = 1, GetNumSpecializations() do
    local specID, name = C_SpecializationInfo.GetSpecializationInfo(index)
    specs[#specs + 1] = {
      id = specID,
      name = name,
    }
  end

  return specs
end

function ns.GetSpecName(specID)
  local _, name = GetSpecializationInfoByID(specID)
  return name
end

local function GetLoadoutConfigIDs(specID)
  return C_ClassTalents.GetConfigIDsBySpecID(specID)
end

local function IsSavedLoadoutForSpec(configID, specID)
  for _, candidateID in ipairs(GetLoadoutConfigIDs(specID)) do
    if candidateID == configID then
      return C_Traits.GetConfigInfo(configID).name ~= ""
    end
  end

  return false
end

function ns.GetLoadoutsForSpec(specID)
  local loadouts = {}

  for _, configID in ipairs(GetLoadoutConfigIDs(specID)) do
    local info = C_Traits.GetConfigInfo(configID)
    if info.name ~= "" then
      loadouts[#loadouts + 1] = {
        id = configID,
        name = info.name,
      }
    end
  end

  sort(loadouts, function(a, b)
    if a.name == b.name then
      return a.id < b.id
    end
    return a.name < b.name
  end)

  return loadouts
end

function ns.GetCurrentLoadoutID(specID)
  specID = specID or ns.GetCurrentSpecID()
  if not specID or C_ClassTalents.GetStarterBuildActive() then
    return nil
  end

  local activeConfigID = C_ClassTalents.GetActiveConfigID()
  if IsSavedLoadoutForSpec(activeConfigID, specID) then
    return activeConfigID
  end

  local selectedConfigID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
  if IsSavedLoadoutForSpec(selectedConfigID, specID) then
    return selectedConfigID
  end

  return nil
end

local function GetLoadoutName(configID)
  local info = C_Traits.GetConfigInfo(configID)
  return info and info.name or nil
end

local function GetEntryLabel(configID, entryID)
  local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
  if not entryInfo or not entryInfo.definitionID then
    return nil
  end

  local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
  if not definitionInfo then
    return nil
  end

  local name
  if definitionInfo.overrideName and definitionInfo.overrideName ~= "" then
    name = definitionInfo.overrideName
  elseif definitionInfo.spellID then
    local spellInfo = C_Spell.GetSpellInfo(definitionInfo.spellID)
    name = spellInfo and spellInfo.name or nil
  end

  if name then
    name = name:gsub("^Rune of ", "")
  end

  return name
end

local function IsSelectionNode(nodeInfo)
  return nodeInfo.type == Enum.TraitNodeType.Selection
    or nodeInfo.type == Enum.TraitNodeType.SubTreeSelection
end

local function GetCommittedEntryID(nodeInfo)
  return nodeInfo.entryIDsWithCommittedRanks[1]
end

function ns.GetFolioChoiceNodes()
  local configID = GetOmniumConfigID()
  if not configID then
    return {}
  end

  local nodes = {}

  for _, nodeID in ipairs(C_Traits.GetTreeNodes(OMNIUM_TREE_ID)) do
    local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
    if nodeInfo
      and IsSelectionNode(nodeInfo)
      and nodeInfo.isVisible
      and #nodeInfo.entryIDs > 1
    then
      local entries = {}
      local currentEntryID = GetCommittedEntryID(nodeInfo)
      local currentName

      for _, entryID in ipairs(nodeInfo.entryIDs) do
        local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
        if entryInfo then
          local name = GetEntryLabel(configID, entryID) or ("Entry " .. entryID)
          entries[#entries + 1] = {
            id = entryID,
            name = name,
            available = entryInfo.isAvailable,
          }

          if entryID == currentEntryID then
            currentName = name
          end
        end
      end

      if #entries > 1 then
        nodes[#nodes + 1] = {
          id = nodeID,
          posX = nodeInfo.posX,
          posY = nodeInfo.posY,
          owned = nodeInfo.ranksPurchased > 0 and currentEntryID ~= nil,
          currentEntryID = currentEntryID,
          currentName = currentName,
          entries = entries,
        }
      end
    end
  end

  sort(nodes, function(a, b)
    if a.posY == b.posY then
      if a.posX == b.posX then
        return a.id < b.id
      end
      return a.posX < b.posX
    end
    return a.posY < b.posY
  end)

  return nodes
end

function ns.GetStoredRule(specID, loadoutID, nodeID)
  if loadoutID then
    local loadoutRule = ns.db.loadouts[loadoutID]
    return loadoutRule and loadoutRule.choices[nodeID] or nil
  end

  local specRules = ns.db.specs[specID]
  return specRules and specRules[nodeID] or nil
end

local function ClearManualChange()
  manualChange = nil
  ns.HideManualChangePrompt()
end

local function ClearTemporaryOverrides()
  temporaryContext = nil
end

local function ClearTemporaryOverride(specID, loadoutID, nodeID)
  if not temporaryContext
    or temporaryContext.specID ~= specID
    or temporaryContext.loadoutID ~= loadoutID
  then
    return
  end

  temporaryContext.choices[nodeID] = nil
  if not next(temporaryContext.choices) then
    temporaryContext = nil
  end
end

local function SetTemporaryOverride(specID, loadoutID, nodeID, entryID)
  if not temporaryContext
    or temporaryContext.specID ~= specID
    or temporaryContext.loadoutID ~= loadoutID
  then
    temporaryContext = {
      specID = specID,
      loadoutID = loadoutID,
      choices = {},
    }
  end

  temporaryContext.choices[nodeID] = entryID
end

local function IsTemporaryOverride(specID, loadoutID, nodeID, currentEntryID)
  if not temporaryContext
    or temporaryContext.specID ~= specID
    or temporaryContext.loadoutID ~= loadoutID
  then
    return false
  end

  local temporaryEntryID = temporaryContext.choices[nodeID]
  if temporaryEntryID == currentEntryID then
    return true
  end

  if temporaryEntryID then
    ClearTemporaryOverride(specID, loadoutID, nodeID)
  end

  return false
end

local function SetSpecRuleValue(specID, nodeID, entryID)
  local choices = ns.db.specs[specID]

  if entryID then
    if not choices then
      choices = {}
      ns.db.specs[specID] = choices
    end
    choices[nodeID] = entryID
  elseif choices then
    choices[nodeID] = nil
    if not next(choices) then
      ns.db.specs[specID] = nil
    end
  end
end

local function SetLoadoutRuleValue(configID, specID, nodeID, entryID)
  local rule = ns.db.loadouts[configID]

  if entryID then
    if not rule then
      rule = {
        specID = specID,
        choices = {},
      }
      ns.db.loadouts[configID] = rule
    end
    rule.specID = specID
    rule.choices[nodeID] = entryID
  elseif rule then
    rule.choices[nodeID] = nil
    if not next(rule.choices) then
      ns.db.loadouts[configID] = nil
    end
  end
end

local function RefreshAll()
  RefreshRuntime()
  ns.RefreshOptions()
end

function ns.SetRule(specID, loadoutID, nodeID, entryID)
  if ns.GetFolioLockReason() then
    return
  end

  ClearManualChange()
  ClearTemporaryOverrides()

  if loadoutID then
    SetLoadoutRuleValue(loadoutID, specID, nodeID, entryID)
  else
    SetSpecRuleValue(specID, nodeID, entryID)
  end

  RefreshAll()
end

function ns.ClearScope(specID, loadoutID)
  if ns.GetFolioLockReason() then
    return
  end

  ClearManualChange()
  ClearTemporaryOverrides()

  if loadoutID then
    ns.db.loadouts[loadoutID] = nil
  else
    ns.db.specs[specID] = nil
  end

  RefreshAll()
end

function ns.CopyCurrentToScope(specID, loadoutID)
  if ns.GetFolioLockReason() then
    return
  end

  ClearManualChange()
  ClearTemporaryOverrides()

  local choices = {}
  for _, node in ipairs(ns.GetFolioChoiceNodes()) do
    if node.owned and node.currentEntryID then
      choices[node.id] = node.currentEntryID
    end
  end

  if loadoutID then
    ns.db.loadouts[loadoutID] = next(choices) and {
      specID = specID,
      choices = choices,
    } or nil
  else
    ns.db.specs[specID] = next(choices) and choices or nil
  end

  RefreshAll()
end

local function BuildEffectiveRules(specID, loadoutID)
  local rules = {}
  local specRules = ns.db.specs[specID]

  if specRules then
    for nodeID, entryID in pairs(specRules) do
      rules[nodeID] = entryID
    end
  end

  local loadoutRule = loadoutID and ns.db.loadouts[loadoutID]
  if loadoutRule and loadoutRule.specID == specID then
    for nodeID, entryID in pairs(loadoutRule.choices) do
      rules[nodeID] = entryID
    end
  end

  return rules
end

local function GetEffectiveRule(specID, loadoutID, nodeID)
  local loadoutRule = loadoutID and ns.db.loadouts[loadoutID]
  if loadoutRule and loadoutRule.specID == specID and loadoutRule.choices[nodeID] then
    return loadoutRule.choices[nodeID], "loadout"
  end

  local specRules = ns.db.specs[specID]
  if specRules and specRules[nodeID] then
    return specRules[nodeID], "spec"
  end
end

local function GetCurrentContext()
  local specID = ns.GetCurrentSpecID()
  if not specID then
    return nil, nil
  end

  return specID, ns.GetCurrentLoadoutID(specID)
end

local function DescribeChanges(changes)
  local parts = {}
  for _, change in ipairs(changes) do
    parts[#parts + 1] = change.currentName
      and (change.currentName .. " to " .. change.desiredName)
      or change.desiredName
  end
  return table.concat(parts, ", ")
end

local function CollectChanges(configID, rules)
  local changes = {}
  local blocked = false

  for nodeID, desiredEntryID in pairs(rules) do
    local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
    local desiredEntryInfo

    if nodeInfo and IsSelectionNode(nodeInfo) then
      for _, entryID in ipairs(nodeInfo.entryIDs) do
        if entryID == desiredEntryID then
          desiredEntryInfo = C_Traits.GetEntryInfo(configID, entryID)
          break
        end
      end
    end

    local currentEntryID = nodeInfo and GetCommittedEntryID(nodeInfo) or nil
    if not desiredEntryInfo
      or not desiredEntryInfo.isAvailable
      or not nodeInfo
      or nodeInfo.ranksPurchased == 0
      or not currentEntryID
    then
      blocked = true
    elseif currentEntryID ~= desiredEntryID then
      changes[#changes + 1] = {
        nodeID = nodeID,
        entryID = desiredEntryID,
        currentEntryID = currentEntryID,
        currentName = GetEntryLabel(configID, currentEntryID),
        desiredName = GetEntryLabel(configID, desiredEntryID) or ("Entry " .. desiredEntryID),
      }
    end
  end

  sort(changes, function(a, b)
    return a.nodeID < b.nodeID
  end)

  return changes, blocked
end

local function RemoveTemporaryChanges(changes, specID, loadoutID)
  for index = #changes, 1, -1 do
    local change = changes[index]
    if IsTemporaryOverride(specID, loadoutID, change.nodeID, change.currentEntryID) then
      remove(changes, index)
    end
  end
end

local function GetApplyState(configID)
  if not C_Traits.CanEditConfig(configID) then
    return "unavailable"
  end

  if C_Traits.ConfigHasStagedChanges(configID) or not C_Traits.IsReadyForCommit() then
    return "busy"
  end

  return "ready"
end

local function RollbackApply(configID)
  pendingCommitConfigID = nil
  C_Traits.RollbackConfig(configID)
  return false
end

local function ApplyChanges(configID, changes)
  if ns.GetFolioLockReason() then
    return false
  end

  pendingCommitConfigID = configID

  for _, change in ipairs(changes) do
    if not C_Traits.SetSelection(configID, change.nodeID, change.entryID) then
      return RollbackApply(configID)
    end
  end

  if not C_Traits.IsReadyForCommit() then
    return RollbackApply(configID)
  end

  if not C_Traits.CommitConfig(configID) then
    return RollbackApply(configID)
  end

  return true
end

local function ShowManualChange(configID, specID, loadoutID, change)
  local savedEntryID, source = GetEffectiveRule(specID, loadoutID, change.nodeID)

  manualChange = {
    configID = configID,
    specID = specID,
    loadoutID = loadoutID,
    nodeID = change.nodeID,
    currentEntryID = change.currentEntryID,
    currentName = change.currentName or ("Entry " .. change.currentEntryID),
    savedEntryID = savedEntryID,
    savedName = change.desiredName,
    source = source,
    specName = ns.GetSpecName(specID),
    loadoutName = loadoutID and GetLoadoutName(loadoutID) or nil,
  }

  ns.HideReminder()
  ns.ShowManualChangePrompt(manualChange)
end

local function HandleExternalFolioChange(configID)
  if ns.GetFolioLockReason() then
    return
  end

  if C_Traits.ConfigHasStagedChanges(configID) then
    return
  end

  local specID, loadoutID = GetCurrentContext()
  if not specID then
    ClearManualChange()
    ns.HideReminder()
    return
  end

  local rules = BuildEffectiveRules(specID, loadoutID)
  if not next(rules) then
    ClearManualChange()
    ns.HideReminder()
    return
  end

  local changes, blocked = CollectChanges(configID, rules)
  RemoveTemporaryChanges(changes, specID, loadoutID)

  if blocked then
    ClearManualChange()
    ns.ShowReminder("Omnium Folio: a saved choice is not unlocked or is no longer available.")
  elseif #changes == 0 then
    ClearManualChange()
    ns.HideReminder()
  else
    ShowManualChange(configID, specID, loadoutID, changes[1])
  end
end

RefreshRuntime = function()
  if not ns.db.enabled or ns.GetFolioLockReason() or manualChange then
    ns.HideReminder()
    return
  end

  if pendingCommitConfigID then
    ns.ShowReminder("Omnium Folio: applying saved choices...")
    return
  end

  local configID = GetOmniumConfigID()
  local specID, loadoutID = GetCurrentContext()
  if not configID or not specID then
    ns.HideReminder()
    return
  end

  local rules = BuildEffectiveRules(specID, loadoutID)
  if not next(rules) then
    ns.HideReminder()
    return
  end

  local changes, blocked = CollectChanges(configID, rules)
  RemoveTemporaryChanges(changes, specID, loadoutID)

  if blocked then
    ns.ShowReminder("Omnium Folio: a saved choice is not unlocked or is no longer available.")
    return
  end

  if #changes == 0 then
    ns.HideReminder()
    return
  end

  local description = DescribeChanges(changes)
  if not ns.db.autoApply then
    ns.ShowReminder("Omnium Folio: " .. description)
    return
  end

  local applyState = GetApplyState(configID)
  if applyState == "unavailable" then
    ns.ShowReminder("Omnium Folio: " .. description .. " - currently unavailable")
    return
  end

  if applyState == "busy" then
    ns.ShowReminder("Omnium Folio: " .. description .. " - waiting for the Folio")
    return
  end

  if ApplyChanges(configID, changes) then
    ns.HideReminder()
  else
    ns.ShowReminder("Omnium Folio: saved choices could not be applied.")
  end
end

function ns.ResolveManualChange(action)
  if ns.GetFolioLockReason() then
    return
  end

  local change = manualChange
  local specID, loadoutID = GetCurrentContext()

  if specID ~= change.specID or loadoutID ~= change.loadoutID then
    ClearManualChange()
    ClearTemporaryOverrides()
    RefreshAll()
    return
  end

  if action == "save_loadout" then
    ClearManualChange()
    ClearTemporaryOverride(specID, loadoutID, change.nodeID)
    SetLoadoutRuleValue(loadoutID, specID, change.nodeID, change.currentEntryID)
    HandleExternalFolioChange(change.configID)
  elseif action == "save_spec" then
    ClearManualChange()
    ClearTemporaryOverride(specID, loadoutID, change.nodeID)
    SetSpecRuleValue(specID, change.nodeID, change.currentEntryID)
    HandleExternalFolioChange(change.configID)
  elseif action == "temporary" then
    SetTemporaryOverride(specID, loadoutID, change.nodeID, change.currentEntryID)
    ClearManualChange()
    ns.HideReminder()
    HandleExternalFolioChange(change.configID)
  elseif action == "restore" then
    local changes, blocked = CollectChanges(change.configID, {
      [change.nodeID] = change.savedEntryID,
    })

    if blocked then
      ns.ShowReminder("Omnium Folio: the saved choice is not unlocked or is no longer available.")
      return
    end

    if #changes == 0 then
      ClearManualChange()
      ClearTemporaryOverride(specID, loadoutID, change.nodeID)
      HandleExternalFolioChange(change.configID)
      ns.RefreshOptions()
      return
    end

    if GetApplyState(change.configID) ~= "ready" then
      ns.ShowReminder("Omnium Folio: the saved choice is currently unavailable.")
      return
    end

    ClearManualChange()
    ClearTemporaryOverride(specID, loadoutID, change.nodeID)

    if ApplyChanges(change.configID, changes) then
      ns.HideReminder()
    else
      ns.ShowReminder("Omnium Folio: the saved choice could not be restored.")
    end
  end

  ns.RefreshOptions()
end

local function SetRuntimeEnabled(enabled)
  if runtimeEnabled == enabled then
    return
  end

  runtimeEnabled = enabled

  if enabled then
    for _, event in ipairs(RUNTIME_EVENTS) do
      eventFrame:RegisterEvent(event)
    end
    RefreshRuntime()
    return
  end

  for _, event in ipairs(RUNTIME_EVENTS) do
    eventFrame:UnregisterEvent(event)
  end

  pendingCommitConfigID = nil
  ClearManualChange()
  ClearTemporaryOverrides()
  ns.HideReminder()
end

function ns.SetEnabled(enabled)
  ns.db.enabled = enabled
  SetRuntimeEnabled(enabled)
  ns.RefreshOptions()
end

function ns.SetAutoApply(enabled)
  ns.db.autoApply = enabled
  RefreshAll()
end

local function OpenPleebFolioForBlizzardFolio(folioFrame)
  if ns.db.enabled then
    ns.OpenOptionsForCurrentContext(folioFrame)
  end
end

local function HookBlizzardFolioFrame(folioFrame)
  folioFrame:HookScript("OnShow", OpenPleebFolioForBlizzardFolio)

  if folioFrame:IsShown() then
    OpenPleebFolioForBlizzardFolio(folioFrame)
  end
end

local function InstallBlizzardFolioHook()
  local overlay = ExpansionLandingPage.Overlay.MidnightLandingOverlay

  if overlay and overlay.RunesOfPowerFrame then
    HookBlizzardFolioFrame(overlay.RunesOfPowerFrame)
    return
  end

  hooksecurefunc(RunesOfPowerMixin, "OnLoad", HookBlizzardFolioFrame)
end

local function RegisterPleebUIPlugin()
  local API = _G.PleebUIAPI
  if not API then
    return
  end

  local plugin = API:RegisterPlugin("PleebFolioReminder", {
    name = "PleebFolio Reminder",
    order = 21,
    navDescription = "Omnium Folio choices by spec and talent loadout.",
    navGlyph = "OF",
  })

  plugin:RegisterOptionsPage("general", {
    name = "General",
    order = 10,
    buildPage = ns.MountPleebUIOptions,
    customPageOwnsHeader = true,
  })
end

local function HandleRuntimeEvent(event, ...)
  if event == "PLAYER_REGEN_DISABLED" or event == "CHALLENGE_MODE_START" then
    ns.HideReminder()
    return
  end

  if event == "PLAYER_REGEN_ENABLED"
    or event == "CHALLENGE_MODE_COMPLETED"
    or event == "CHALLENGE_MODE_RESET"
  then
    if ns.GetFolioLockReason() then
      return
    end

    if manualChange then
      ns.ShowManualChangePrompt(manualChange)
    else
      RefreshRuntime()
    end
    return
  end

  if CONTEXT_EVENTS[event] then
    ClearManualChange()
    ClearTemporaryOverrides()

    if ns.GetFolioLockReason() then
      ns.HideReminder()
    else
      RefreshRuntime()
    end

    ns.RefreshOptions()
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    RefreshAll()
    return
  end

  if event == "TRAIT_CONFIG_DELETED" then
    ns.db.loadouts[...] = nil
  elseif event == "CONFIG_COMMIT_FAILED" then
    local configID = ...
    if configID == pendingCommitConfigID then
      pendingCommitConfigID = nil
      ns.ShowReminder("Omnium Folio: saved choices could not be applied.")
    end
  elseif event == "TRAIT_CONFIG_UPDATED" and not ns.GetFolioLockReason() then
    local configID = ...
    local omniumConfigID = GetOmniumConfigID()

    if configID == omniumConfigID then
      if configID == pendingCommitConfigID then
        if not C_Traits.ConfigHasStagedChanges(configID) then
          pendingCommitConfigID = nil
          ns.HideReminder()
          HandleExternalFolioChange(configID)
        end
      else
        HandleExternalFolioChange(configID)
      end
    end
  end

  ns.RefreshOptions()
end

local function InitializeAddon()
  InitializeDB()
  RegisterPleebUIPlugin()
  SetRuntimeEnabled(ns.db.enabled)
  EventUtil.ContinueOnAddOnLoaded("Blizzard_ExpansionLandingPage", InstallBlizzardFolioHook)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  HandleRuntimeEvent(event, ...)
end)

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, InitializeAddon)

_G.SLASH_PLEEBFOLIO1 = "/pleebfolio"
_G.SLASH_PLEEBFOLIO2 = "/pfolio"
_G.SlashCmdList.PLEEBFOLIO = function()
  ns.OpenOptions()
end
