--[[
  Saronite Loot — WeakAura for the loot master (WotLK Classic)

  SETUP (once):
    1. Type /wa, click "New", choose "Text".
    2. Display tab: clear the "Display Text" box (the aura itself shows nothing).
    3. Trigger tab: leave the default trigger.
    4. Load tab: leave everything unticked so it is always loaded.
    5. Actions tab: under "On Init", tick "Custom" and paste this whole file.
    6. Name the aura "Saronite Loot", close /wa and type /reload.

  USE:
    A small "Saronite" bar appears (drag it anywhere, click "Saronite" to fold it):
      Load      paste the string from the site ("Copy for WeakAura")
      Export    copy the in-game loot log back to the site
      Undo      remove the last recorded award
      Announce  toggle raid-chat announcements when you open loot
    Hover "Saronite" to see what is loaded.
]]

local env = aura_env
env.saved = env.saved or {}
local S = env.saved
S.log = S.log or {}
if S.announce == nil then S.announce = true end

local BOARD_PREFIX = "SARONITE:1"
local LOG_PREFIX = "SARONITE-LOG:1"

-- Shared holder so hooks/frames are only created once, even when the aura is edited.
_G.SaroniteLoot = _G.SaroniteLoot or {}
local H = _G.SaroniteLoot

local function out(msg)
  print("|cff9b7bd8Saronite|r: " .. msg)
end

local function norm(name)
  if not name then return "" end
  name = name:gsub("%-.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
  return name:lower()
end

local function split(text, sep)
  local parts, start = {}, 1
  while true do
    local i = text:find(sep, start, true)
    if not i then parts[#parts + 1] = text:sub(start); break end
    parts[#parts + 1] = text:sub(start, i - 1)
    start = i + #sep
  end
  return parts
end

local function itemIdFromLink(link)
  return link and tonumber(link:match("item:(%d+)"))
end

---------------------------------------------------------------------------
-- Board parsing and priority rules (same rules as the website)
---------------------------------------------------------------------------

local function parseBoard(text)
  text = (text or ""):gsub("[\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  local records = split(text, ";")
  if records[1] ~= BOARD_PREFIX then
    return nil, "this is not a Saronite board string. Use \"Copy for WeakAura\" on the loot page."
  end
  local board = { items = {}, received = {}, round = 1, version = 0, guild = "", count = 0 }
  for i = 2, #records do
    local key, value = records[i]:match("^(%a):(.*)$")
    if key == "v" then
      board.version = tonumber(value) or 0
    elseif key == "r" then
      board.round = tonumber(value) or 1
    elseif key == "g" then
      board.guild = value
    elseif key == "x" then
      for _, name in ipairs(split(value, "/")) do
        if name ~= "" then board.received[norm(name)] = true end
      end
    elseif key == "i" then
      local id, copies, awarded, list = value:match("^(%d+),(%d+),(%d+),(.*)$")
      id = tonumber(id)
      if id and not board.items[id] then
        local item = { copies = tonumber(copies) or 1, awarded = tonumber(awarded) or 0, cands = {} }
        for _, entry in ipairs(split(list, "/")) do
          local name, prio, status = entry:match("^(.-):(%d+):(%a)$")
          if name and name ~= "" then
            item.cands[#item.cands + 1] = { name = name, key = norm(name), prio = tonumber(prio), passed = status == "p" }
          end
        end
        table.sort(item.cands, function(a, b) return a.prio < b.prio end)
        board.items[id] = item
        board.count = board.count + 1
      end
    end
  end
  return board
end

local function isOpen(item)
  return item.awarded < item.copies
end

-- Players in the best priority group who are still eligible this round.
local function topGroup(item)
  local best, group = nil, {}
  for _, c in ipairs(item.cands) do
    if not c.passed and not S.board.received[c.key] then
      best = best or c.prio
      if c.prio == best then group[#group + 1] = c end
    end
  end
  return group
end

local function names(group)
  local list = {}
  for _, c in ipairs(group) do list[#list + 1] = c.name end
  return table.concat(list, ", ")
end

local function chat(msg)
  if IsInRaid() then
    SendChatMessage(msg, "RAID")
  elseif IsInGroup() then
    SendChatMessage(msg, "PARTY")
  else
    out(msg)
  end
end

-- Start a new round when nobody is eligible on any item that still has copies left.
local function maybeAdvanceRound()
  local waiting = false
  for _, item in pairs(S.board.items) do
    if isOpen(item) then
      if #topGroup(item) > 0 then return false end
      for _, c in ipairs(item.cands) do
        if not c.passed then waiting = true end
      end
    end
  end
  if not waiting then return false end
  S.board.round = S.board.round + 1
  wipe(S.board.received)
  chat("Saronite: round " .. S.board.round .. " starts, everyone is eligible again.")
  return true
end

local function copySet(set)
  local copy = {}
  for k, v in pairs(set) do copy[k] = v end
  return copy
end

local function recordAward(itemId, playerName, link)
  if not S.board then return end
  local item = S.board.items[itemId]
  if not item then return end
  local key = norm(playerName)

  local inTop = false
  for _, c in ipairs(topGroup(item)) do
    if c.key == key then inTop = true end
  end

  local entry = {
    id = itemId,
    name = playerName:gsub("%-.*$", ""),
    round = S.board.round,
    override = not inTop or not isOpen(item),
    roundBefore = S.board.round,
    receivedBefore = copySet(S.board.received),
    link = link,
  }
  item.awarded = item.awarded + 1
  S.board.received[key] = true
  S.log[#S.log + 1] = entry
  S.exported = false

  out(string.format("recorded %s → %s (round %d)%s", link or ("item " .. itemId), entry.name, entry.round,
    entry.override and " |cffff9933[override]|r" or ""))
  maybeAdvanceRound()
end

local function undo()
  local entry = table.remove(S.log)
  if not entry then out("nothing to undo.") return end
  local item = S.board and S.board.items[entry.id]
  if item then item.awarded = math.max(0, item.awarded - 1) end
  if S.board then
    S.board.round = entry.roundBefore
    S.board.received = entry.receivedBefore
  end
  out("removed " .. (entry.link or ("item " .. entry.id)) .. " → " .. entry.name .. ".")
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------

function H.onTooltip(tooltip)
  if not S.board or not tooltip.GetItem then return end
  local _, link = tooltip:GetItem()
  local item = S.board.items[itemIdFromLink(link) or 0]
  if not item then return end

  tooltip:AddLine(" ")
  tooltip:AddDoubleLine("|cff9b7bd8Saronite|r priority", item.awarded .. "/" .. item.copies .. " awarded", 1, 1, 1, 0.6, 0.6, 0.6)
  if not isOpen(item) then
    tooltip:AddLine("All copies awarded", 0.4, 0.8, 0.4)
  else
    local group = topGroup(item)
    if #group == 1 then
      tooltip:AddLine("Next: " .. group[1].name, 0.4, 1, 0.4)
    elseif #group > 1 then
      tooltip:AddLine("Roll: " .. names(group), 1, 0.8, 0.2, true)
    else
      tooltip:AddLine("No eligible player this round", 0.6, 0.6, 0.6)
    end
  end
  local parts = {}
  for _, c in ipairs(item.cands) do
    local text = c.prio .. ". " .. c.name
    if c.passed then
      text = "|cff777777" .. text .. " (passed)|r"
    elseif S.board.received[c.key] then
      text = "|cff777777" .. text .. " (looted)|r"
    end
    parts[#parts + 1] = text
  end
  if #parts > 0 then tooltip:AddLine(table.concat(parts, "   "), 0.85, 0.85, 0.85, true) end
  tooltip:Show()
end

if not H.tooltipHooked then
  H.tooltipHooked = true
  if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
      if H.onTooltip then H.onTooltip(tooltip) end
    end)
  else
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
      tooltip:HookScript("OnTooltipSetItem", function(self)
        if H.onTooltip then H.onTooltip(self) end
      end)
    end
  end
end

---------------------------------------------------------------------------
-- Loot window announce and loot detection
---------------------------------------------------------------------------

local function canAnnounce()
  if not IsInGroup() then return false end
  local getMethod = GetLootMethod or (C_PartyInfo and C_PartyInfo.GetLootMethod)
  if not getMethod then return UnitIsGroupLeader("player") end
  local method, partyMaster, raidMaster = getMethod()
  if method == "master" then
    if partyMaster == 0 then return true end
    if raidMaster and UnitIsUnit("raid" .. raidMaster, "player") then return true end
    return false
  end
  return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

H.announced = H.announced or {}

local function announceLoot()
  if not S.board or not S.announce or not canAnnounce() then return end
  local now = GetTime()
  for slot = 1, GetNumLootItems() do
    local link = GetLootSlotLink(slot)
    local id = itemIdFromLink(link)
    local item = id and S.board.items[id]
    if item and isOpen(item) then
      local source = GetLootSourceInfo and GetLootSourceInfo(slot) or "?"
      local key = tostring(source) .. ":" .. slot .. ":" .. id
      if not H.announced[key] or now - H.announced[key] > 600 then
        H.announced[key] = now
        local group = topGroup(item)
        if #group == 1 then
          chat(link .. " → " .. group[1].name .. " (prio " .. group[1].prio .. ")")
        elseif #group > 1 then
          chat(link .. " → roll: " .. names(group) .. " (prio " .. group[1].prio .. ")")
        else
          chat(link .. " → nobody eligible this round")
        end
      end
    end
  end
end

local function toPattern(format)
  format = format:gsub("%%%d%$", "%%")
  format = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  format = format:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
  return "^" .. format .. "$"
end

local selfPatterns = {}
for _, global in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF" }) do
  if _G[global] then selfPatterns[#selfPatterns + 1] = toPattern(_G[global]) end
end
local otherPatterns = {}
for _, global in ipairs({ "LOOT_ITEM_MULTIPLE", "LOOT_ITEM", "LOOT_ITEM_PUSHED_MULTIPLE", "LOOT_ITEM_PUSHED" }) do
  if _G[global] then otherPatterns[#otherPatterns + 1] = toPattern(_G[global]) end
end

local function onLootMessage(msg)
  if not S.board then return end
  for _, pattern in ipairs(selfPatterns) do
    local link = msg:match(pattern)
    if link then
      local id = itemIdFromLink(link)
      if id and S.board.items[id] then recordAward(id, UnitName("player"), link) end
      return
    end
  end
  for _, pattern in ipairs(otherPatterns) do
    local name, link = msg:match(pattern)
    if name and link then
      local id = itemIdFromLink(link)
      if id and S.board.items[id] then recordAward(id, name, link) end
      return
    end
  end
end

function H.onEvent(_, event, ...)
  if event == "LOOT_OPENED" then
    announceLoot()
  elseif event == "CHAT_MSG_LOOT" then
    onLootMessage(...)
  end
end

if not H.frame then
  H.frame = CreateFrame("Frame")
  H.frame:RegisterEvent("LOOT_OPENED")
  H.frame:RegisterEvent("CHAT_MSG_LOOT")
  H.frame:SetScript("OnEvent", function(...) if H.onEvent then H.onEvent(...) end end)
end

---------------------------------------------------------------------------
-- Copy / paste window
---------------------------------------------------------------------------

local function buildExport()
  local records = { LOG_PREFIX, "v:" .. (S.board and S.board.version or 0), "r:" .. (S.board and S.board.round or 0) }
  for _, entry in ipairs(S.log) do
    records[#records + 1] = string.format("a:%d,%s,%d,%d", entry.id, entry.name, entry.round, entry.override and 1 or 0)
  end
  return table.concat(records, ";")
end

local function getWindow()
  if H.window then return H.window end
  local f = CreateFrame("Frame", "SaroniteLootWindow", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(520, 260)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  tinsert(UISpecialFrames, "SaroniteLootWindow")

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("TOP", 0, -5)

  f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.hint:SetPoint("TOPLEFT", 14, -32)
  f.hint:SetPoint("TOPRIGHT", -14, -32)
  f.hint:SetJustifyH("LEFT")

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -52)
  scroll:SetPoint("BOTTOMRIGHT", -34, 44)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(true)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(460)
  edit:SetMaxLetters(0)
  edit:SetScript("OnEscapePressed", function() f:Hide() end)
  scroll:SetScrollChild(edit)
  f.edit = edit

  local button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  button:SetSize(170, 24)
  button:SetPoint("BOTTOMRIGHT", -12, 12)
  f.button = button

  H.window = f
  return f
end

local function openLoadWindow()
  local f = getWindow()
  f.title:SetText("Saronite: load board")
  f.hint:SetText("Paste the text from \"Copy for WeakAura\" on the loot page (Ctrl+V), then click Load.")
  f.edit:SetText("")
  f.confirmReplace = false
  f.button:SetText("Load board")
  f.button:SetScript("OnClick", function()
    local board, err = parseBoard(f.edit:GetText())
    if not board then out(err) return end
    if #S.log > 0 and not S.exported and not f.confirmReplace then
      f.confirmReplace = true
      f.button:SetText("Discard " .. #S.log .. " unexported?")
      out("you have " .. #S.log .. " awards not exported yet. Click again to discard them, or click Export first.")
      return
    end
    S.board = board
    S.log = {}
    S.exported = false
    f:Hide()
    out(string.format("board loaded: %d items, round %d.", board.count, board.round))
  end)
  f:Show()
  f.edit:SetFocus()
end

local function openExportWindow()
  local f = getWindow()
  f.title:SetText("Saronite: export loot log")
  f.hint:SetText(#S.log .. " award(s). Press Ctrl+C to copy, then paste it into \"Import what was looted in game\" on the site.")
  f.edit:SetText(buildExport())
  f.edit:HighlightText()
  f.button:SetText("Done")
  f.button:SetScript("OnClick", function()
    S.exported = true
    f:Hide()
  end)
  f:Show()
  f.edit:SetFocus()
  f.edit:HighlightText()
end

---------------------------------------------------------------------------
-- Control bar (WeakAuras does not allow slash commands)
---------------------------------------------------------------------------

local function statusText()
  if not S.board then return "No board loaded. Click Load." end
  return string.format("%s: %d items, round %d\n%d award(s) recorded in game%s\nAnnounce: %s",
    S.board.guild ~= "" and S.board.guild or "Guild", S.board.count, S.board.round, #S.log,
    (#S.log > 0 and not S.exported) and " (not exported)" or "",
    S.announce and "on" or "off")
end

function H.refreshBar()
  local bar = H.bar
  if not bar then return end
  bar.announce:SetText(S.announce and "Announce: on" or "Announce: off")
  for _, button in ipairs(bar.buttons) do button:SetShown(not S.collapsed) end
  bar:SetWidth(S.collapsed and 90 or 390)
end

H.actions = {
  load = function() openLoadWindow() end,
  export = function() openExportWindow() end,
  undo = function() undo() end,
  announce = function()
    S.announce = not S.announce
    out("loot announcements " .. (S.announce and "on" or "off") .. ".")
  end,
  toggle = function() S.collapsed = not S.collapsed end,
  moved = function(point, x, y) S.pos = { point, x, y } end,
  status = statusText,
}

if not H.bar then
  local bar = CreateFrame("Frame", "SaroniteLootBar", UIParent, "BackdropTemplate")
  bar:SetHeight(28)
  bar:SetFrameStrata("MEDIUM")
  bar:SetMovable(true)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetClampedToScreen(true)
  if bar.SetBackdrop then
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    bar:SetBackdropColor(0.05, 0.08, 0.11, 0.9)
    bar:SetBackdropBorderColor(0.6, 0.48, 0.85, 0.8)
  end
  bar:SetScript("OnDragStart", bar.StartMoving)
  bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    H.actions.moved(point, x, y)
  end)

  local function makeButton(text, width, action)
    local button = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    button:SetSize(width, 20)
    button:SetText(text)
    button:SetScript("OnClick", function()
      H.actions[action]()
      H.refreshBar()
    end)
    return button
  end

  local title = makeButton("Saronite", 80, "toggle")
  title:SetPoint("LEFT", 5, 0)
  title:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Saronite Loot")
    GameTooltip:AddLine(H.actions.status(), 1, 1, 1, true)
    GameTooltip:AddLine("Click to fold/unfold. Drag the bar to move it.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  title:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local load = makeButton("Load", 54, "load")
  load:SetPoint("LEFT", title, "RIGHT", 4, 0)
  local export = makeButton("Export", 60, "export")
  export:SetPoint("LEFT", load, "RIGHT", 4, 0)
  local undoButton = makeButton("Undo", 54, "undo")
  undoButton:SetPoint("LEFT", export, "RIGHT", 4, 0)
  local announce = makeButton("Announce: on", 110, "announce")
  announce:SetPoint("LEFT", undoButton, "RIGHT", 4, 0)

  bar.announce = announce
  bar.buttons = { load, export, undoButton, announce }
  H.bar = bar
end

H.bar:ClearAllPoints()
if S.pos then
  H.bar:SetPoint(S.pos[1], UIParent, S.pos[1], S.pos[2], S.pos[3])
else
  H.bar:SetPoint("TOP", UIParent, "TOP", 0, -120)
end
H.bar:Show()
H.refreshBar()
