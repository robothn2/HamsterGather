--[[
	This addon designed to be as lightweight as possible.
	It will only track Mine, Herbal resources.
]]
local HamsterGather = LibStub("AceAddon-3.0"):NewAddon("HamsterGather", "AceEvent-3.0", "AceConsole-3.0", "AceComm-3.0", "AceSerializer-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("HamsterGather", false)

local HG_PREFIX = "HamsterGather" -- addon 消息前缀
-- all register events list below  
local registerEvents = {
  --"UNIT_SPELLCAST_START",
  --"UNIT_SPELLCAST_CHANNEL_START",
  "UNIT_SPELLCAST_CHANNEL_STOP",
  --"UNIT_SPELLCAST_FAILED",
  --"UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_SUCCEEDED",
  --"LOOT_OPENED",
  --"LOOT_READY",
  --"LOOT_CLOSED",
  "CHAT_MSG_LOOT",
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
    conflictSeconds=500,  -- 两个资源点都采集到了资源，当采集时间间隔在此数值以内，视为组冲突，即：两者必定从属不同资源分组
    respawnSeconds={default=900},   -- 经过实际蹲点统计，枯叶草/火焰花的刷新时间约为 15min(900秒)
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
  },
  {
    abbr="mine", profession=L["Mining"], spells={10248},
    lootTimeout=2, posShiftFacing=1, sameDistancePower2=1,
    conflictSeconds=500,
    respawnSeconds={default=900},
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
    respawnSeconds={
      default = 3600, -- 黑口鱼/火鳞鳝鱼 鱼群刷新时间为 1hour
      [13422] = 5400, -- 石鳞鳗 鱼群刷新时间为 1.5hour
    },
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
      resources = {},       -- 方便UI显示的采集数据，格式：{[resCategory] = {[mapId] = { [resId] = { show = true, respawns = {{x,y, gatherTime, gatherCharName, groupId}, ...}}}}}
      histories = {},       -- 采集历史数据，格式：{mapId, x, y, resId, resCount, gatherTime, gatherCharName}
      historyMaxCount = 100,-- 保留的采集历史记录最大条数，超过时会移除前面的记录
      groupResources = { -- 分组计算资源设置
        [13465] = {[1423]=true},-- 山鼠草 - 东瘟疫之地
        [13466] = {[1423]=true},-- 瘟疫花 - 东瘟疫之地
        [4625] = {[1427]=true}, -- 火焰花 - 灼热峡谷
        [3369] = {[1431]=true}, -- 墓地苔 - 暮色森林
        [3818] = {}, -- 枯叶草 - 所有区域
      },
      persistGroupConflicts = {}, -- 持久化存储分组计算的冲突矩阵，格式：{[mapId] = {[resId] = {[respawnId1] = {[respawnId2] = true, ...}, ...}}}
      historyProcessedTs = 0,  -- 上次分组计算时已经处理的历史数据的最新时间戳
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
  self:RegisterComm(HG_PREFIX, "OnCommReceived")
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

  -- 历史采集数据的分组计算
  self:ComputeAllGroups()

  -- 历史采集数据清理
  local histories = self.db.profile.histories
  local historyMaxCount = self.db.profile.historyMaxCount
  if #histories > historyMaxCount then
    local count = #histories
    local offset = count - historyMaxCount
    for i = 1, historyMaxCount do
      histories[i] = histories[i + offset]
    end
    for i = historyMaxCount + 1, count do
      histories[i] = nil
    end
  end

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
  -- /dump C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"), "player"):GetXY()
  local normX, normY, mapId = self.HBD:GetPlayerZonePosition()
  if not normX or not mapId then return end
  if not distanceYard or distanceYard == 0 then
    return normX, normY, mapId
  end

  local width, height = self.HBD:GetZoneSize(mapId)
  if not width or width <= 0 then return end

  local facing = GetPlayerFacing() 
  if facing == nil then return end

  local dx = math.sin(facing + math.pi) * distanceYard
  local dy = math.cos(facing + math.pi) * distanceYard
  return normX + (dx / width), normY + (dy / height), mapId
end

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
    -- /dump GetServerTime()
    local resCat = self.current.resCat
    local x, y, mapId = self:getPosFrontOfPlayerFacing(resCat.posShiftFacing)
    local data = {
      ts = GetServerTime(), sender = self.playerName, resId = tonumber(itemId), resCount = count, cat = resCat.abbr,
      -- 返回的 x,y 是归一化坐标，需要乘 100，保留 2 位小数，最后一位小数四舍五入
      map = mapId, x = math.floor(x * 10000 + 0.5) / 100, y = math.floor(y * 10000 + 0.5) / 100,
    }
    self:Debug(data.ts, data.sender, data.cat, data.resId, data.resCount, data.map, data.x, data.y)

    self:updateResDB(resCat, data)
    self:sendResourceGatherToOthers(data)
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

function HamsterGather:sendResourceGatherToOthers(data)
  -- /dump IsInGroup(),IsInRaid()
  if not IsInGroup() then return end
  local channel = IsInRaid() and "RAID" or "PARTY"
  local msg = self:Serialize(data)
  -- priority: "ALERT", "NORMAL", "BULK"
  self:SendCommMessage(HG_PREFIX, msg, channel, nil, "NORMAL")
end

function HamsterGather:OnCommReceived(prefix, message, channel, sender)
  -- self:Debug(sender, message)
  if prefix ~= HG_PREFIX or sender == self.playerName then return end
  local success, data = self:Deserialize(message)
  if success then
    self:Debug(data.ts, data.sender, data.cat, data.resId, data.resCount, data.map, data.x, data.y)
    local resCat = self.resCatsByProfAbbr[data.cat]
    self:updateResDB(resCat, data)
  end
end

function HamsterGather:updateResDB(resCat, data)
  -- 仅支持固定的资源 id，忽略伴生草药、挖矿石头、钓鱼宝箱
  if not resCat or not resCat.ids[data.resId] then return end

  local histories = self.db.profile.histories
  -- 当捡取可堆叠资源时，如果加上捡取的资源会超过整组，会被拆分为两条消息，这里把它们合并为一条
  -- 例如：堆叠数当前为 18，最大 20，捡取3个时会拆分成 2 和 1 两条
  local prevHistory = histories[#histories]
  if prevHistory then
    if data.ts == prevHistory[1] and data.resId == prevHistory[5] then
      self:Debug("Combined history", data.resId, prevHistory[6], "->", prevHistory[6] + data.resCount)
      prevHistory[6] = prevHistory[6] + data.resCount
    end
  end
  -- 增加采集历史记录
  table.insert(histories, {data.ts, data.map, data.x, data.y, data.resId, data.resCount, data.sender})

  local resCategoryData = self.db.profile.resources[resCat.abbr].data
  -- [map_id] = { [herbal_id] = {{x,y, gather_time, gather_char_name, group_id, respawn_time}, ...}}}
  resCategoryData[data.map] = resCategoryData[data.map] or {}
  resCategoryData[data.map][data.resId] = resCategoryData[data.map][data.resId] or {show=true, respawns={}}
  local mapResRespawns = resCategoryData[data.map][data.resId].respawns

  -- 增加资源采集点(respawn)
  local respawn, respawnId = self:FindRespawn(mapResRespawns, data.x, data.y, resCat)
  if respawn then
    respawn[3] = data.ts
    respawn[4] = data.sender
  else
    respawn = {data.x, data.y, data.ts, data.sender}
    table.insert(mapResRespawns, respawn)
    respawnId = #mapResRespawns
  end

  self:markRespawnConflicts(resCat, mapResRespawns, data, respawnId)

  respawn[6] = self:calcRespawnTime(resCat, data)

  self:updateMinimap()
  if data.map == WorldMapFrame.mapID then
    HGWorldMapDataProvider:RefreshAllData()
  end
end

function HamsterGather:calcRespawnTime(resCat, newData)
  local respawnSeconds = resCat.respawnSeconds or {default=900}
  local incSeconds = respawnSeconds[newData.resId] or respawnSeconds['default']
  return newData.ts + incSeconds
end

function HamsterGather:markRespawnConflicts(resCat, mapResRespawns, newData, newRespawnId)
  local gres = self.db.profile.groupResources
  if not gres or not gres[newData.resId] then return end
  if next(gres[newData.resId]) ~= nil and not gres[newData.resId][newData.map] then return end

  local allConflicts = self.db.profile.persistGroupConflicts or {}
  self.db.profile.persistGroupConflicts = allConflicts
  allConflicts[newData.map] = allConflicts[newData.map] or {}
  allConflicts[newData.map][newData.resId] = allConflicts[newData.map][newData.resId] or {}
  local conflicts = allConflicts[newData.map][newData.resId]
  
  local timestampBegin = newData.ts - (resCat.conflictSeconds or 500)
  local histories = self.db.profile.histories
  --self:Debug("Check history begin:", timestampBegin, #histories)

  for i = #histories - 1, 1, -1 do
    local r = histories[i]
    --self:Debug("history:", i, r[1], r[2], r[5])
    -- format: {timestamp, mapId, x, y, resId, resCount, self.playerName}
    if r[1] < timestampBegin then break end
    if r[2] == newData.map and r[5] == newData.resId then
      --self:Debug("found history:", r[3], r[4])
      local _, respawnId = self:FindRespawn(mapResRespawns, r[3], r[4], resCat)
      if respawnId ~= nil then -- 有可能不存在
        self:markConflict(#mapResRespawns, conflicts, newRespawnId, respawnId)
      end
    end
  end
end

function HamsterGather:markConflict(respawnCnt, conflicts, respawnId1, respawnId2)
  if respawnId2 ~= respawnId1 then
    local u, v = respawnId1, respawnId2
    if u > v then u,v = v,u end -- conflicts 表有下标顺序要求，小的在前
    local line = conflicts[u] or string.rep("0", respawnCnt - u)
    if u + #line < respawnCnt then
      line = line .. string.rep("0", respawnCnt - u - #line)
    end
    local shift = v - u
    if line:sub(shift, shift) == '0' then
      line = string.sub(line, 1, shift - 1) .. '1' .. string.sub(line, shift + 1)
      self:Debug("mark conflict:", u, v)
      --self:Debug(conflicts[u], "->", line)
    end
    assert(u + #line == respawnCnt)
    conflicts[u] = line
  end
end

function HamsterGather:FindRespawn(mapResRespawns, x, y, resCat)
  for i, respawn in ipairs(mapResRespawns) do
    local distancePower2 = (x - respawn[1]) * (x - respawn[1]) + (y - respawn[2]) * (y - respawn[2])
    if distancePower2 < resCat.sameDistancePower2 then
      return respawn, i
    end
  end
end

--- 核心分组计算函数
-- @param mapId 地图ID
-- @param resId 资源ID
-- @return table groups 分组结果: { [1] = {respawnId1, respawnId2}, [2] = {...} }
function HamsterGather:ComputeGroupsInternal(mapId, resId)
  local MAX_GROUP_SIZE = 6     -- 每组最多 6 个点
  local MAX_NEIGHBOR_DISTANCE = 800 -- 最大允许 x,y 各 20 点差值

  local resCat
  -- 通过 resId 获取资源分类信息
  for _, res in ipairs(resourceCategories) do
    if res.ids[resId] then
      resCat = res
      break
    end
  end

  local ROUND_MAX_GAP = resCat.conflictSeconds or 500    -- 冲突判定时间窗口
  local resCategoryData = self.db.profile.resources[resCat.abbr].data
  if next(resCategoryData) == nil then return end
  if resCategoryData[mapId] == nil or resCategoryData[mapId][resId] == nil then return end
  local mapResRespawns = resCategoryData[mapId][resId].respawns
  local historyProcessedTs = self.db.profile.historyProcessedTs
  local histories = {}
  for _, r in ipairs(self.db.profile.histories) do
    -- {now, mapId, x, y, resId, resCount, self.playerName}
    if historyProcessedTs < r[1] then -- 忽略上次计算分组时已经处理的数据
      if r[2] == mapId and r[5] == resId then
        local respawn, respawnId = self:FindRespawn(mapResRespawns, r[3], r[4], resCat)
        if respawn ~= nil then -- 有可能不存在
          table.insert(histories, {ts = r[1], id = respawnId})
        end
      end
    end
  end
  if #histories == 0 then return end
  self:Debug(string.format("Map(%d) res(%d) has %d new records", mapId, resId, #histories))

  -- 按时间顺序排序采集记录
  table.sort(histories, function(a, b) return a.ts < b.ts end)

  -- 计算两资源点间的二维欧氏距离平方
  local function calcRespawnDistance(r1, r2)
    local dx = r1[1] - r2[1]
    local dy = r1[2] - r2[2]
    return dx * dx + dy * dy
  end
  local function calcDistance(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return dx * dx + dy * dy
  end
  local function lookupDistance(respawns, respawnId1, respawnId2)
    if respawnId1 > respawnId2 then respawnId1, respawnId2 = respawnId2, respawnId1 end
    return respawns[respawnId1][respawnId2].distance
  end

  -- 资源点缓存表
  local respawns = {}
  for respawnId, respawn in ipairs(mapResRespawns) do
    local respawnInfo = { x = respawn[1], y = respawn[2],
      cornerDistances = { -- 资源点与四个角的距离
        topleft = calcDistance(respawn[1], respawn[2], 0, 0),
        bottomleft = calcDistance(respawn[1], respawn[2], 0, 100),
        bottomright = calcDistance(respawn[1], respawn[2], 100, 100),
        topright = calcDistance(respawn[1], respawn[2], 100, 0),
      },
    }
    for anotherId = respawnId + 1, #mapResRespawns do
      respawnInfo[anotherId] = {distance = calcRespawnDistance(respawn, mapResRespawns[anotherId]), conflict = false}
    end
    respawns[respawnId] = respawnInfo
  end

  -- 从持久化存储的冲突矩阵中恢复分组互斥标记
  -- 冲突矩阵格式：{[mapId] = {[resId] = {[respawnId1] = {[respawnId2] = true, ...}, ...}}}
  self.db.profile.persistGroupConflicts = self.db.profile.persistGroupConflicts or {}
  local persistGroupConflicts = self.db.profile.persistGroupConflicts
  persistGroupConflicts[mapId] = persistGroupConflicts[mapId] or {}
  persistGroupConflicts[mapId][resId] = persistGroupConflicts[mapId][resId] or {}
  local persistConflicts = persistGroupConflicts[mapId][resId]
  for respawnId1, conflictLine in pairs(persistConflicts) do
    -- 这里如果上次发现了新的资源点，两者之和与资源点总数量是不一致的，可以部分恢复
    --assert(respawnId1 + #conflictLine == #respawns)
    for i = 1, #conflictLine do
      local respawnId2 = respawnId1 + i
      if conflictLine:sub(i, i) == '1' then
        respawns[respawnId1][respawnId2].conflict = true
      end
    end
  end

  -- 处理采集历史记录，根据时间间隔更新资源点分组互斥标记 respawns[respawnId A][respawnId B].conflict
  local n = #histories
  for i = 1, n do
    for j = i + 1, n do
      if (histories[j].ts - histories[i].ts) > ROUND_MAX_GAP then
        break
      end
      local u, v = histories[i].id, histories[j].id
      if u ~= v then
        if u == nil or v == nil then
          self:Debug(string.format("%d(%d) %d(%d)", i, histories[i].ts, j, histories[j].ts), u, v)
        end
        if u > v then u,v = v,u end -- respawns 表是有下标顺序要求的，小的在前
        if not respawns[u][v].conflict then
          respawns[u][v].conflict = true
          self:Debug("mark conflict:", u, v)
        end
      end
    end
  end

  -- 持久化冲突矩阵
  for respawnId1, others in pairs(respawns) do
    local slice = {unpack(others, respawnId1 + 1, #respawns)} -- 注意 others 还有 x, y, cornerDistances 等属性
    local conflictLine = {}
    for i, item in ipairs(slice) do
      conflictLine[i] = item.conflict and "1" or "0"
    end
    persistConflicts[respawnId1] = table.concat(conflictLine)
    --self:Debug(respawnId1, persistConflicts[respawnId1])
  end

  -- 辅助函数：检查资源节点是否与当前组 groupMembers 中的任何节点冲突
  local function hasConflictWithGroup(respawnId, groupMembers)
    for _, memberId in ipairs(groupMembers) do
      if respawnId < memberId then
        if respawns[respawnId][memberId].conflict then return true end
      else
        if respawns[memberId][respawnId].conflict then return true end
      end
    end
    return false
  end

  -- 未分配资源节点集合: unassigned[respawnId] = true
  local unassigned = {}
  local totalUnassignedCount = 0
  for respawnId, _ in ipairs(mapResRespawns) do
    unassigned[respawnId] = true
    totalUnassignedCount = totalUnassignedCount + 1
  end
  
  -- 按地图4个角的顺序选择一个角，选择最接近当前角的一个未分配组的资源点
  -- 以灼热平原的火焰花为例，正上方只有一个资源组，且经常被卡在一个无法采集的点，一般从左上角逆时针或者右上角顺时针采集，所以选取角的顺序要跟着地图走
  local corners = {'topleft', 'bottomleft', 'bottomright', 'bottomright'}
  local function getCornerRespawn(unassignedRespawns, corner)
    if #unassignedRespawns == 0 then return nil end
    local res = {}
    for respawnId, _ in pairs(unassignedRespawns) do
      table.insert(res, respawnId)
    end
    --self:Debug(corner, " has unassigned respawns:", table.concat(res, ','))
    table.sort(res, function(a, b) return respawns[a].cornerDistances[corner] < respawns[b].cornerDistances[corner] end)
    --self:Debug("unassigned respawns sorted by corner distance:", table.concat(res, ','))
    return res[1]
  end

  local groups = {}
  local cornerIndex = 1
  while totalUnassignedCount > 0 do
    -- 按角顺序选择新组起始资源点
    local curRespawnId = getCornerRespawn(unassigned, corners[cornerIndex])
    if not curRespawnId then break end
    cornerIndex = cornerIndex + 1
    if cornerIndex > #corners then cornerIndex = 1 end

    local curGroup = { curRespawnId }
    table.insert(groups, curGroup)
    local respawnInGroupIndex = 1
    unassigned[curRespawnId] = nil
    totalUnassignedCount = totalUnassignedCount - 1

    -- 如果组还没满并且当前组内被选定资源点索引未超限，按距离从近到远寻找符合条件的节点
    while #curGroup < MAX_GROUP_SIZE and respawnInGroupIndex <= #curGroup do
      curRespawnId = curGroup[respawnInGroupIndex]
      -- 将剩余所有未分配节点按到 curRespawnId 的距离升序排列
      local candidates = {}
      for respawnId, _ in pairs(unassigned) do
        local distance = lookupDistance(respawns, curRespawnId, respawnId)
        if distance < MAX_NEIGHBOR_DISTANCE then
          table.insert(candidates, {id = respawnId, dist = distance})
        end
      end
      table.sort(candidates, function(a, b) return a.dist < b.dist end)

      -- 依次尝试放入最近且不冲突的节点
      for _, cand in ipairs(candidates) do
        if #curGroup >= MAX_GROUP_SIZE then break end

        -- 判定互斥：不与组内现有的任何节点冲突
        if not hasConflictWithGroup(cand.id, curGroup) then
          table.insert(curGroup, cand.id)
          unassigned[cand.id] = nil
          totalUnassignedCount = totalUnassignedCount - 1
        end
      end
      respawnInGroupIndex = respawnInGroupIndex + 1
    end
  end

  -- 更新 respawns 内的各资源点的组 ID，并刷新 world map
  for groupId, group in ipairs(groups) do
    for _, respawnId in ipairs(group) do
      mapResRespawns[respawnId][5] = groupId
    end
  end

  return groups
end

function HamsterGather:ComputeAllGroups()
  local ret = {}
  local historyProcessedTs = self.db.profile.historyProcessedTs
  -- 历史数据的分组计算
  if self.db.profile.groupResources then
    for resId, mapIds in pairs(self.db.profile.groupResources) do
      for mapId, enabled in pairs(mapIds) do
        if enabled then
          ret[mapId] = ret[mapId] or {}
          ret[mapId][resId] = self:ComputeGroupsInternal(mapId, resId)
        end
      end
    end
  end
  -- 更新历史数据已处理时间戳
  self.db.profile.historyProcessedTs = GetServerTime()
  self:Print(string.format("History processed timestamp: %d -> %d", historyProcessedTs, self.db.profile.historyProcessedTs))
  
  HGWorldMapDataProvider:RefreshAllData()
  return ret
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
    local allGroups = self:ComputeAllGroups()
    if allGroups[mapId] and allGroups[mapId][resId] then
      for i, group in ipairs(allGroups[mapId][resId]) do
        self:Print("Group", i, ": {", table.concat(group, ","), "}")
      end
    end
  else
    self:Print("Unknown command:", msg)
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
      -- [map_id] = { [herbal_id] = {show=true, respawns={x,y, gather_time, gather_char_name}, ...}}}}
      if resInMap then
        for resId, resShowData in pairs(resInMap) do
          if resShowData.show then
            for _, respawn in ipairs(resShowData.respawns) do
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
                self.HBDPins:AddMinimapIconMap("HamsterGatherMiniPin", pin, mapId, respawn[1]/100.0, respawn[2]/100.0, false, false)
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

function HGWorldMapDataProvider:RefreshAllData()
	self:RemoveAllData()

	local mapId = WorldMapFrame.mapID
	if not mapId then return end

  local now = GetServerTime()
  local map = self:GetMap()
	for resCat, resData in pairs(self.db.profile.resources) do
    -- check if player has resource category skill/profession
    if self.resCatsByProfAbbr[resCat].rank then
      local respawnSeconds = 900
      local resInMap = resData.data[mapId]
      -- [map_id] = { [herbal_id] = {show=true, respawns={{x,y, gather_time, gather_char_name, group_id, respawn_time}, ...}}}}
      if resInMap then
        for resId, resShowData in pairs(resInMap) do
          if resShowData.show then
            for respawnId, respawn in ipairs(resShowData.respawns) do
              local pin = map:AcquirePin("HamsterGatherMapPinTemplate", respawn[1]/100.0, respawn[2]/100.0, resId)
              table.insert(worldmapPins, pin)
             	pin:SetAlpha(0.6)
             	pin:EnableMouse(true)
              pin.mapId = mapId
              pin.resId = resId
              pin.groupId = respawn[5]
              if respawn[6] and now < respawn[6] then
                local elapsed = now - respawn[3]
                pin:StartCooldown(GetTime() - elapsed, respawnSeconds)
              end
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
	self:SetAlpha(0.8)
  local iconPath = string.format("Interface\\AddOns\\HamsterGather\\Icons\\%d.tga", resId)
	self.texture:SetTexture(iconPath)
	self.texture:SetTexCoord(0, 1, 0, 1)
	self.texture:SetVertexColor(1, 1, 1, 1)
  self.cooldown:Hide()
end

function HamsterGatherWorldMapPinMixin:OnMouseEnter()
	if not self.groupId then return end
  
  local cnt = 0
  for _, pin in ipairs(worldmapPins) do
    if pin.resId == self.resId and pin.groupId == self.groupId then
      pin:SetAlpha(1.0)
      cnt = cnt + 1
    end
  end
  --print("Group:", self.groupId, " Count:", cnt)
  --[[
  local x, y = self:GetCenter()
  local parentX, parentY = UIParent:GetCenter()
  if ( x > parentX ) then
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  else
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  end
  GameTooltip:SetText(text)
  GameTooltip:Show()
  ]]
end

function HamsterGatherWorldMapPinMixin:OnMouseLeave()
  for _, pin in ipairs(worldmapPins) do
    pin:SetAlpha(0.6)
  end

	--GameTooltip:Hide()
end

function HamsterGatherWorldMapPinMixin:StartCooldown(startTime, duration)
  if not self.cooldown then return end

  self.cooldown:SetCooldown(startTime, duration)
  self.cooldown:Show()
  self.cooldown:SetHideCountdownNumbers(false)
  self.cooldown:SetSwipeColor(0, 0, 0, 0.7)
end
