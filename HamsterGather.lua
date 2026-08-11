--[[
	This addon designed to be as lightweight as possible.
	It will only track Mine, Herbal resources.
]]
local HamsterGather = LibStub("AceAddon-3.0"):NewAddon("HamsterGather", "AceEvent-3.0")

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
  --"CHAT_MSG_MONSTER_EMOTE",
  --"PLAYER_REGEN_DISABLED",
  --"PLAYER_REGEN_ENABLED",
  --"UNIT_INVENTORY_CHANGED",
  --"UNIT_AURA",
  --"GET_ITEM_INFO_RECEIVED",
  --"PLAYER_MOUNT_DISPLAY_CHANGED",
  --"MOUNT_JOURNAL_USABILITY_CHANGED",
  "ZONE_CHANGED_NEW_AREA",
}

local spellCategories = {
  [2366] =  { cat="herb", lootTimeout=2 },
  [10248] = { cat="mine", lootTimeout=2 },
  [18248] = { cat="fish", lootTimeout=2 },
}

function HamsterGather:OnInitialize()
  -- do init tasks here, like loading the Saved Variables, 
  -- or setting up slash commands.
  local default_config = {
    profile = {
      resources = {
        herb = {
          show = true,
          sameDistancePower2 = 2, -- 认定为同一刷新点的距离
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
          data = {
            -- [map_id] = { [herbal_id] = { show = true, records = {{x,y, gather_time, gather_char_name}, ...}}}},
          },
        },
        mine = {
          show = true,
          sameDistancePower2 = 3,
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
          data = {
            -- [map_id] = { [mineral_id] = {show = true, records = {{x,y, gather_time, gather_char_name}, ...}}}},
          },
        },
        fish = {
          show = true,
          sameDistancePower2 = 5,
          ids = {
            [6358] = true, -- 黑口鱼
            [6359] = true, -- 火鳞鳝鱼
            [13422] = true, -- 石鳞鳗
          },
          data = {
            -- [map_id] = { [fish_id] = {show = true, records = {{x,y, gather_time, gather_char_name}, ...}}}},
          },
        },
      },
    },
  }
  self.db = LibStub("AceDB-3.0"):New("HamsterGatherDB", default_config, true)
  self.pinPool = {}
  self.pinCounter = 0
end

function HamsterGather:OnEnable()
  -- Do more initialization here, that really enables the use of your addon.
  -- Register Events, Hook functions, Create Frames, Get information from the game that wasn't available in OnInitialize
  self.playerName, self.playerRealm = UnitFullName("player")
  self.current = { spellId=nil, spellCat=nil }
  for _, event in ipairs(registerEvents) do
    self:RegisterEvent(event, "OnEvent")
  end

  HGWorldMapDataProvider.db = self.db
  WorldMapFrame:AddDataProvider(HGWorldMapDataProvider)
end

function HamsterGather:OnDisable()
  -- Unhook, Unregister Events, Hide frames that you created.
  -- You would probably only use an OnDisable if you want to 
  -- build a "standby" mode, or be able to toggle modules on/off.
  for _, event in ipairs(registerEvents) do
    self:UnregisterEvent(event)
  end
end

-- info / print / debug
function HamsterGather:Info(...)
  print("|cFF00FF00[HamsterGather]|r ", ...)
end

function HamsterGather:Print(...)
  print("|cFF00FF00[HamsterGather]|r ", ...)
end

function HamsterGather:Debug(...)
  if self.db and self.db.debugMode then
    print("|cFFFFAA00[HamsterGather]|r ", ...)
  end
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
	--self:Print(event, ...)
  if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
    -- reset loot timer after message for fishing
    local caster, _, spellId = ...
    if caster ~= 'player' then return end
    local spellCat = spellCategories[spellId]
    if not spellCat then return end
    self.current.spellCat = spellCat
    self.current.spellId = spellId
    self:resetLootTimer(spellCat)
  elseif event == "CHAT_MSG_LOOT" then
    if not self.current.spellCat then return end -- 忽略没有采集施法的战利品拾取
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
    self:handleResourceGathered(self.current.spellCat, tonumber(itemId), count)
  end
end

function HamsterGather:resetLootTimer(spellCat)
  if self.lootTimer then
    self.lootTimer:Cancel()
  end
  self.lootTimer = C_Timer.NewTimer(spellCat.lootTimeout, function()
    if self.current.spellCat then
      self.current.spellCat = nil
    end
  end)
end

function HamsterGather:handleResourceGathered(spellCat, resId, resCount)
  if not spellCat then return end
  local mapId = C_Map.GetBestMapForUnit("player")
  local position = C_Map.GetPlayerMapPosition(mapId, "player")
  -- /dump C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"), "player"):GetXY()
  -- todo: 钓鱼时，玩家站立点(0.34473, 0.33951) 鱼群(0.34358, 0.34194)
  if not position then return end
  local x, y = position:GetXY()
  -- /dump GetServerTime()
  -- /dump UnitFullName("player")
  local now = GetServerTime()
  self:Print(now, mapId, spellCat.cat, resId, resCount, x, y)
  -- 返回的 x,y 是归一化坐标，需要乘 100，保留 2 位小数
  self:updateResDBPosition(spellCat, resId, mapId, math.floor(x * 10000) / 100, math.floor(y * 10000) / 100, now)
end

function HamsterGather:updateResDBPosition(spellCat, resId, mapId, x, y, now)
  local resCat = self.db.profile.resources[spellCat.cat]
  -- 仅支持固定的资源 id，忽略伴生草药、挖矿石头、钓鱼宝箱
  if not resCat or not resCat.ids[resId] then return end
  local data = resCat.data
  -- [map_id] = { [herbal_id] = {{x,y, gather_time, gather_char_name}, ...}}}
  data[mapId] = data[mapId] or {}
  data[mapId][resId] = data[mapId][resId] or {show=true, records={}}

  local updated = false
  for _, event in ipairs(data[mapId][resId].records) do
    local distancePower2 = (x - event[1]) * (x - event[1]) + (y - event[2]) * (y - event[2])
    if distancePower2 < resCat.sameDistancePower2 then
      event[3] = now
      event[4] = self.playerName
      updated = true
      self:Print(string.format("map[%d] res[%d] pos[%f,%f] updated to:", mapId, resId, x, y), now, self.playerName)
      break
    end
  end
  if not updated then
    table.insert(data[mapId][resId].records, {x, y, now, self.playerName})
  end
end

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
    -- todo: check if player has resource category skill

    -- [map_id] = { [herbal_id] = {show=true, records={x,y, gather_time, gather_char_name}, ...}}}}
    local resInMap = resData.data[mapId]
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

-- modified from HandyNotes
HamsterGatherWorldMapPinMixin = CreateFromMixins(MapCanvasPinMixin)
function HamsterGatherWorldMapPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	--self:SetScalingLimits(1, 1.0, 1.2);
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
