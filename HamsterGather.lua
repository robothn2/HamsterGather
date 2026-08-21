--[[
	This addon designed to be as lightweight as possible.
	It will only track Mine, Herbal resources.
]]
local HamsterGather = LibStub("AceAddon-3.0"):NewAddon("HamsterGather", "AceEvent-3.0", "AceConsole-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("HamsterGather", false)

-- all register events list below  
local registerEvents = {
  --"CURSOR_CHANGED",
  --"UNIT_SPELLCAST_START",
  --"UNIT_SPELLCAST_CHANNEL_START",
  "UNIT_SPELLCAST_CHANNEL_STOP",
  --"UNIT_SPELLCAST_FAILED",
  --"UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_SUCCEEDED",
  --"PLAYER_SOFT_INTERACT_CHANGED",
  --"UI_ERROR_MESSAGE",
  --"LOOT_OPENED",
  --"LOOT_READY",
  --"LOOT_CLOSED",
  "CHAT_MSG_LOOT",
  --"UNIT_INVENTORY_CHANGED",
  "ZONE_CHANGED_NEW_AREA",
  "SKILL_LINES_CHANGED",
}

local resourceCategories = {
  {
    abbr="herb",
    profession=L["Herbalism"], -- 用来分析采集资源需要的技能是否具备
    spells={2366},          -- 草药学的采集技能ID列表
    lootTimeout=2,        -- 采集资源的施法完成后，超时时间之外获取的战利品都会被忽略
    posShiftFacing=1,     -- 采集成功后玩家位置和资源点的距离，按玩家面对方向往前计算码数
    sameDistancePower2=1, -- 认定为同一刷新点的距离
    ids = {
      [765] = true,  -- 银叶草
      [785] = true,  -- 魔皇草
      [2447] = true, -- 宁神花
      [2449] = true, -- 地根草
      [2450] = true, -- 石楠草
      [2453] = true, -- 跌打草
      [3355] = true, -- 野钢花
      [3356] = true, -- 皇血草
      [3357] = true, -- 活根草
      [3358] = true, -- 卡德加的胡须
      [3369] = true, -- 墓地苔
      [3818] = true, -- 枯叶草
      [3820] = true, -- 荆棘藻
      [3821] = true, -- 金棘草
      [4625] = true, -- 火焰花
      [8831] = true, -- 紫莲花
      [8836] = true, -- 阿尔萨斯之泪
      [8838] = true, -- 太阳草
      [8839] = true, -- 盲目草
      [8845] = true, -- 幽灵菇
      [8846] = true, -- 格罗姆之血
      [13463] = true, -- 梦叶草
      [13464] = true, -- 黄金参
      [13465] = true, -- 山鼠草
      [13466] = true, -- 瘟疫花
      [13468] = true, -- 黑莲花
    },
    ids2Analyze = { -- 需要分析的资源点，用于分析资源点的分组
      [3818] = true, -- 枯叶草
      [4625] = true, -- 火焰花
      [13463] = true, -- 梦叶草
      [13465] = true, -- 山鼠草
      [13466] = true, -- 瘟疫花
    },
  },
  {
    abbr="mine", profession=L["Mining"], spells={10248},
    lootTimeout=2, posShiftFacing=1, sameDistancePower2=1,
    ids = {
      [2770] = true,  -- 铜矿石
      [2771] = true,  -- 锡矿石
      [2772] = true,  -- 铁矿石
      [2775] = true,  -- 银矿石
      [2776] = true,  -- 金矿石
      [3858] = true,  -- 秘银矿石
      [7911] = true,  -- 真银矿石
      [10620] = true,  -- 瑟银矿石
      [11370] = true,  -- 黑铁矿石
    },
  },
  {
    abbr="fish", profession=L["Fishing"], spells={18248},
    lootTimeout=2, posShiftFacing=15, sameDistancePower2=1,
    ids = {
      [6358] = true, -- 黑口鱼
      [6359] = true, -- 火鳞鳝鱼
      [13422] = true, -- 石鳞鳗
    },
  },
}

function HamsterGather:OnInitialize()
  -- do init tasks here, like loading the Saved Variables, 
  -- or setting up slash commands.
  self.resCatsBySpellId, self.resCatsByProfAbbr = {}, {}
  for _, res in ipairs(resourceCategories) do
    self.resCatsByProfAbbr[res.abbr] = res

    for _, spell in ipairs(res.spells) do
      self.resCatsBySpellId[spell] = res
    end
  end

  self.printPrefix = string.format("|cFF00FF00[%s]|r ", L["HamsterGather"])
  self.debugPrefix = string.format("|cFFFFAA00[%s]|r ", L["HamsterGather"])

  local default_db = {
    profile = {
      debug = false,
      resources = {}, -- 方便UI显示的采集数据，格式：[map_id] = { [res_id] = { show = true, records = {{x,y, gather_time, gather_char_name}, ...}}}}
      maxRecordCount = 100, -- 保留的采集历史记录最大条数，超过时会移除前面的一半记录
      records = {},         -- 滚动的采集历史记录，格式：{map_id, x, y, res_id, res_count, gather_time, gather_char_name}
      records2Analyze = {}, -- 用于分析资源点分组的采集历史记录
    },
  }
  for _, res in ipairs(resourceCategories) do
    default_db.profile.resources[res.abbr] = { show = true, data = {} }
  end
  self.db = LibStub("AceDB-3.0"):New("HamsterGatherDB", default_db, true)
  self.HBD = LibStub("HereBeDragons-2.0")
  self.HBDPins = LibStub("HereBeDragons-Pins-2.0")

  self.pinPool = {}
  self.minimapPins = {}

  self:RegisterChatCommand("hg", "HandleSlash")
end

function HamsterGather:OnEnable()
  -- Do more initialization here, that really enables the use of your addon.
  -- Register Events, Hook functions, Create Frames, Get information from the game that wasn't available in OnInitialize
  self.playerName, self.playerRealm = UnitFullName("player")
  self.current = { spellId=nil, resCat=nil }
  for _, event in ipairs(registerEvents) do
    self:RegisterEvent(event, "OnEvent")
  end

  -- share data to HGWorldMapDataProvider
  HGWorldMapDataProvider.db = self.db
  HGWorldMapDataProvider.resCatsByProfAbbr = self.resCatsByProfAbbr
  WorldMapFrame:AddDataProvider(HGWorldMapDataProvider)

  self:SKILL_LINES_CHANGED()

	self.HBD.RegisterCallback(self, "PlayerZoneChanged", "updateMinimap")
  self:Print(L["HamsterGather"], "loaded.")
end

function HamsterGather:OnDisable()
  -- Unhook, Unregister Events, Hide frames that you created.
  -- You would probably only use an OnDisable if you want to 
  -- build a "standby" mode, or be able to toggle modules on/off.
  for _, event in ipairs(registerEvents) do
    self:UnregisterEvent(event)
  end

  self.HBDPins:RemoveAllMinimapIcons("HamsterGatherMiniPin")
  self:clearPins()
  WorldMapFrame:RemoveDataProvider(HGWorldMapDataProvider)
	self.HBD.UnregisterCallback(self, "PlayerZoneChanged")
end

-- output to chat: print / debug
function HamsterGather:Print(...)
  print(self.printPrefix, ...)
end

function HamsterGather:Debug(...)
  if self.db.profile.debug then
    print(self.debugPrefix, ...)
  end
end

-- get player info
function HamsterGather:SKILL_LINES_CHANGED()
  -- cleanup
  for _, cat in pairs(self.resCatsByProfAbbr) do
    cat.rank = nil
  end

	for i = 1, GetNumSkillLines() do
    --[[
    self:Debug(GetSkillLineInfo(i))
    ...
    专业 1 1 0 0 0 0 nil nil nil 0 0
    草药学 nil nil 300 0 0 300 1 nil nil 0 0 高级的草药学技能使你可以采集高级的草药。如果你不能采集某种草药，请先在较低等级的地区采集低等级草药，以此提高你的草药学技能。
    附魔 nil nil 60 0 0 150 1 nil nil 0 0 高级的附魔技能使你可以学习高级的附魔公式。你可以在训练师那里学习新的公式，也可以通过完成任务或杀死怪物获得新的公式。
    ...
    ]]
    local skillName, _, _, skillRank = GetSkillLineInfo(i)
    for _, cat in pairs(self.resCatsByProfAbbr) do
      if cat.profession == skillName then
        self:Debug(skillName, " rank ", skillRank)
        cat.rank = skillRank
        break
      end
    end
	end
end

function HamsterGather:getPosFrontOfPlayerFacing(distanceYard)
  local normX, normY, mapId = self.HBD:GetPlayerZonePosition()
  if not normX or not mapId then return nil, nil, nil end
  if not distanceYard or distanceYard == 0 then
    return normX, normY, mapId
  end

  local width, height = self.HBD:GetZoneSize(mapId)
  if not width or width <= 0 then return nil, nil, nil end

  local facing = GetPlayerFacing() 
  if facing == nil then return nil, nil, nil end

  local dx = math.sin(facing + math.pi) * distanceYard
  local dy = math.cos(facing + math.pi) * distanceYard
  return normX + (dx / width), normY + (dy / height), mapId
end

--[[ event flow & handlers
1.herbal gather flow：
[19:26:03] CURSOR_CHANGED true 0 0 0
[19:26:03] UNIT_SPELLCAST_START player Cast-3-5343-0-41-2366-0000F1CC4B 2366 4
[19:26:08] UNIT_SPELLCAST_SUCCEEDED player Cast-3-5343-0-41-2366-0000F1CC4B 2366 4
[19:26:08] LOOT_READY true
[19:26:08] CURSOR_CHANGED true 0 0 0
[19:26:08] LOOT_OPENED true
[19:26:08] LOOT_READY true
[19:26:08] CURSOR_CHANGED true 0 0 0
[19:26:09] LOOT_CLOSED
[19:26:09] LOOT_CLOSED
[19:26:09] 你得到了物品：[梦叶草]x2。
[19:26:09] CHAT_MSG_LOOT 你得到了物品：[梦叶草]x2。    Demi  0 0  0 1090 nil 0 false false false false
[19:26:09] CURSOR_CHANGED true 0 0 0

2.mining flow:
[19:21:21] CURSOR_CHANGED true 0 0 0
[19:21:21] UNIT_SPELLCAST_START player Cast-3-5343-0-41-10248-000071CAF5 10248 2
[19:21:25] UNIT_SPELLCAST_SUCCEEDED player Cast-3-5343-0-41-10248-000071CAF5 10248 2
[19:21:25] LOOT_READY true
[19:21:25] CURSOR_CHANGED true 0 0 0
[19:21:25] LOOT_OPENED true
[19:21:25] LOOT_READY true
[19:21:25] CURSOR_CHANGED true 0 0 0
[19:21:25] 你获得了物品：[瑟银矿石]。
[19:21:25] CHAT_MSG_LOOT 你获得了物品：[瑟银矿石]。    Demi  0 0  0 1078 nil 0 false false false false
[19:21:25] LOOT_CLOSED
[19:21:25] LOOT_CLOSED
[19:21:25] 你获得了物品：[厚重的石头]。
[19:21:25] CHAT_MSG_LOOT 你获得了物品：[厚重的石头]。    Demi  0 0  0 1079 nil 0 false false false false
[19:21:25] CURSOR_CHANGED true 0 0 0
[19:21:25] UNIT_INVENTORY_CHANGED player

3.fishing flow:
[18:11:41] CURSOR_CHANGED true 0 0 0
[18:11:42] UNIT_SPELLCAST_CHANNEL_START player nil 18248 8
[18:11:42] UNIT_SPELLCAST_SUCCEEDED player Cast-3-5343-1-15-18248-000071BADE 18248 nil
[18:11:43] CURSOR_CHANGED true 0 0 0
[18:11:05] CURSOR_CHANGED true 0 0 0
[18:11:05] CURSOR_CHANGED true 0 0 0
[18:11:06] UNIT_SPELLCAST_CHANNEL_STOP player nil 18248 nil 8
[18:11:06] CURSOR_CHANGED true 0 0 0
[18:11:06] LOOT_READY true
[18:11:06] LOOT_OPENED true
[18:11:06] LOOT_READY true
[18:11:06] LOOT_CLOSED
[18:11:06] LOOT_CLOSED
[18:11:06] 你获得了物品：[火鳞鳝鱼]。
[18:11:06] CHAT_MSG_LOOT 你获得了物品：[火鳞鳝鱼]。    Papaya  0 0  0 488 nil 0 false false false false
[18:11:07] UNIT_INVENTORY_CHANGED player
]]

function HamsterGather:OnEvent(event, ...)
	--self:Debug(event, ...)
  if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
    -- reset loot timer after message for fishing
    local caster, _, spellId = ...
    if caster ~= 'player' then return end
    local resCat = self.resCatsBySpellId[spellId]
    if not resCat then return end
    self.current.resCat = resCat
    self.current.spellId = spellId
    self:resetLootTimer(resCat)
  elseif event == "CHAT_MSG_LOOT" then
    if not self.current.resCat then return end -- 忽略没有采集施法的战利品拾取
    local message, _, _, _, looter = ...
    if looter ~= self.playerName then return end -- 忽略其他人的战利品拾取
    -- /dump string.match("你获得了物品：|cffffffff|Hitem:6359::::::::60::::::::::|h[火鳞鳝鱼]|h|r。", "%[(.+)%]")
    -- extract item id from link
    local itemId = string.match(message, "item:(%d+)")
    if not itemId then return end
    -- extract item count, set to 1 if not exist
    local count = string.match(message, "x(%d+)")
    if count then
      count = tonumber(count)
    else
      count = 1
    end
    self:handleResourceGathered(self.current.resCat, tonumber(itemId), count)
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    self:updateMinimap()
  end
end

function HamsterGather:resetLootTimer(resCat)
  if self.lootTimer then
    self.lootTimer:Cancel()
  end
  self.lootTimer = C_Timer.NewTimer(resCat.lootTimeout, function()
    if self.current.resCat then
      self.current.resCat = nil
    end
  end)
end

function HamsterGather:handleResourceGathered(resCat, resId, resCount)
  if not resCat then return end
  local x, y, mapId = self:getPosFrontOfPlayerFacing(resCat.posShiftFacing)
  -- /dump C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"), "player"):GetXY()
  -- /dump GetServerTime()
  local now = GetServerTime()
  self:Debug(now, mapId, resCat.abbr, resId, resCount, x, y)
  -- 返回的 x,y 是归一化坐标，需要乘 100，保留 2 位小数
  self:updateResDBPosition(resCat, resId, resCount, mapId, math.floor(x * 10000 + 0.5) / 100, math.floor(y * 10000 + 0.5) / 100, now)
end

function HamsterGather:updateResDBPosition(resCat, resId, resCount, mapId, x, y, now)
  -- 仅支持固定的资源 id，忽略伴生草药、挖矿石头、钓鱼宝箱
  if not resCat or not resCat.ids[resId] then return end

  -- 增加采集历史记录
  local records = self.db.profile.records
  table.insert(records, {now, mapId, x, y, resId, resCount, self.playerName})
  -- 检查采集历史记录最大条数，超过时会移除前面的一半记录
  if #records > self.db.profile.maxRecordCount then
    local count = #records
    local half = math.floor(count / 2)
    for i = 1, half do
      records[i] = records[i + half]
    end
    for i = half + 1, count do
      records[i] = nil
    end
  end
  if resCat.ids2Analyze and resCat.ids2Analyze[resId] then
    table.insert(self.db.profile.records2Analyze, {now, mapId, x, y, resId, self.playerName})
  end

  local data = self.db.profile.resources[resCat.abbr].data
  -- [map_id] = { [herbal_id] = {{x,y, gather_time, gather_char_name}, ...}}}
  data[mapId] = data[mapId] or {}
  data[mapId][resId] = data[mapId][resId] or {show=true, records={}}
  local mapResRespawns = data[mapId][resId].records

  local respawn = self:FindSameRespawn(mapResRespawns, x, y, resCat)
  if respawn then
    respawn[3] = now
    respawn[4] = self.playerName
    self:Debug(string.format("map[%d] res[%d] pos[%f,%f] updated to:", mapId, resId, x, y), now, self.playerName)
  else
    table.insert(mapResRespawns, {x, y, now, self.playerName})
    self:updateMinimap()
  end
end

function HamsterGather:FindSameRespawn(mapResRespawns, x, y, resCat)
  for _, respawn in ipairs(mapResRespawns) do
    local distancePower2 = (x - respawn[1]) * (x - respawn[1]) + (y - respawn[2]) * (y - respawn[2])
    if distancePower2 < resCat.sameDistancePower2 then
      return respawn
    end
  end
end

-- 支持斜线开始的命令
function HamsterGather:HandleSlash(msg)
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  if not cmd then
    return
  end

  cmd = cmd:lower()
  if cmd == "group" then
    local mapId = C_Map.GetBestMapForUnit("player")
    local resId = tonumber(rest)
    --local groups = self:ComputeGroupsByConflicts(mapId, resId)
    --self:Print("当前分组计算完成，共有组数：" .. #groups)
  else
    self:Print(msg)
  end
end

---------------------------------------------------------
-- mini map
function HamsterGather:updateMinimap()
	self.HBDPins:RemoveAllMinimapIcons("HamsterGatherMiniPin")
  self:clearPins()

	local mapId = self.HBD:GetPlayerZone()
	if not mapId then return end

	local frameLevel = Minimap:GetFrameLevel() + 5
	local frameStrata = Minimap:GetFrameStrata()

  for resCat, resData in pairs(self.db.profile.resources) do
    -- check if player has resource category skill/profession
    if self.resCatsByProfAbbr[resCat].rank then
      local resInMap = resData.data[mapId]
      -- [map_id] = { [herbal_id] = {show=true, records={x,y, gather_time, gather_char_name}, ...}}}}
      if resInMap then
        for resId, resShowData in pairs(resInMap) do
          if resShowData.show then
            for _, record in ipairs(resShowData.records) do
              local pin = self:getNewPin()
              if pin then -- maybe nil
                pin:SetFrameStrata(frameStrata)
                pin:SetFrameLevel(frameLevel)
                pin:SetAlpha(0.6)
                pin:SetWidth(12)
                pin:SetHeight(12)
                local t = pin.texture
                t:SetTexture(string.format("Interface\\AddOns\\HamsterGather\\Icons\\%d.tga", resId))
                t:SetTexCoord(0, 1, 0, 1)
                t:SetAllPoints(pin)
                --pin:SetScript("OnClick", nil)
                self.HBDPins:AddMinimapIconMap("HamsterGatherMiniPin", pin, mapId, record[1]/100.0, record[2]/100.0, false, false)
                self.minimapPins[pin] = pin
              end
            end
          end
        end
      end
    end
  end
end

function HamsterGather:clearPins()
	for key, pin in pairs(self.minimapPins) do
		pin:Hide()
    table.insert(self.pinPool, pin)
	end
  self.minimapPins = {}
end

function HamsterGather:getNewPin()
  local pin = nil
  if next(self.pinPool) then
    pin = table.remove(self.pinPool)
  else
    pin = CreateFrame("Button", nil, Minimap) -- 这里不要给名字，否则会被图标回收站自动收纳
    pin:SetFrameLevel(5)
    local texture = pin:CreateTexture(nil, "OVERLAY")
	  pin.texture = texture
	  texture:SetTexelSnappingBias(0)
	  texture:SetSnapToPixelGrid(false)
    texture:SetAllPoints(pin)
    pin:EnableMouse(false)
    --[[
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp");
    pin:SetScript("OnEnter", showPin)
    pin:SetScript("OnLeave", hidePin)
    pin:SetScript("OnClick", pinClick)
    ]]
  end
  return pin
end

---------------------------------------------------------
-- world map
HGWorldMapDataProvider = CreateFromMixins(MapCanvasDataProviderMixin)
local worldmapPins = {}
function HGWorldMapDataProvider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate("HamsterGatherMapPinTemplate")
	wipe(worldmapPins)
end

function HGWorldMapDataProvider:RefreshAllData(...)
	self:RemoveAllData()

	local mapId = WorldMapFrame.mapID
	if not mapId then return end

  local map = self:GetMap()
	for resCat, resData in pairs(self.db.profile.resources) do
    -- check if player has resource category skill/profession
    if self.resCatsByProfAbbr[resCat].rank then
      local resInMap = resData.data[mapId]
      -- [map_id] = { [herbal_id] = {show=true, records={x,y, gather_time, gather_char_name}, ...}}}}
      if resInMap then
        for resId, resShowData in pairs(resInMap) do
          if resShowData.show then
            for _, record in ipairs(resShowData.records) do
              local pin = map:AcquirePin("HamsterGatherMapPinTemplate", record[1]/100.0, record[2]/100.0, resId)
              table.insert(worldmapPins, pin)
            end
          end
        end
      end
    end
  end
end

-- modified from HandyNotes
HamsterGatherWorldMapPinMixin = CreateFromMixins(MapCanvasPinMixin)
function HamsterGatherWorldMapPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self:SetScalingLimits(1, 1.0, 1.2)
end

function HamsterGatherWorldMapPinMixin:OnAcquired(x, y, resId)
	self.title = string.format("HGWorldMapPin%d", #worldmapPins)
	self.resId = resId
	self:SetPosition(x, y)
	self:SetHeight(12)
	self:SetWidth(12)
	self:SetAlpha(1.0)
  local iconPath = string.format("Interface\\AddOns\\HamsterGather\\Icons\\%d.tga", resId)
	self.texture:SetTexture(iconPath)
	self.texture:SetTexCoord(0, 1, 0, 1)
	self.texture:SetVertexColor(1, 1, 1, 1)
	self:EnableMouse(false)
end
