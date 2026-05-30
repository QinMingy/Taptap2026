-- ============================================================================
-- gameplay.lua - 玩法系统
-- 管理玩法特定逻辑（金币生成/拾取/结算等）
-- 新增玩法时只需在此模块添加对应规则即可
-- ============================================================================

local Cfg = require("config")
local GAMEPLAY_DATA = Cfg.GAMEPLAY_DATA
local MAP_DATA = Cfg.MAP_DATA
local CONFIG = Cfg.CONFIG

local M = {}

-- ============================================================================
-- 金币系统状态
-- ============================================================================
local coins_ = {}         -- 场上金币列表 { {x, y, collected} }
local playerCoins_ = {}   -- 每个玩家本轮收集的金币数

-- ============================================================================
-- 解锁系统
-- ============================================================================

--- 获取胜利所需分数: 单队人数 × 20
function M.GetWinScore()
    local teamSize = #Cfg.PLAYERS / 2
    return teamSize * 20
end

--- 计算当前解锁值: 领先队总分 / 该队人数
function M.GetUnlockValue(teams)
    local maxAvg = 0
    for t = 1, 2 do
        local teamSize = #teams[t].members
        if teamSize > 0 then
            local avg = teams[t].score / teamSize
            if avg > maxAvg then
                maxAvg = avg
            end
        end
    end
    return maxAvg
end

--- 根据解锁值获取应使用的地图等级 (1/2/3)
function M.GetMapLevelForUnlockValue(unlockValue)
    local level = 1
    for _, entry in ipairs(Cfg.UNLOCK_CONFIG.maps) do
        if unlockValue >= entry.threshold then
            level = entry.mapIndex
        end
    end
    return level
end

--- 获取当前已解锁的玩法索引列表
function M.GetUnlockedGameplays(unlockValue)
    local unlocked = {}
    for i, gp in ipairs(GAMEPLAY_DATA) do
        if unlockValue >= gp.unlockThreshold then
            table.insert(unlocked, i)
        end
    end
    return unlocked
end

--- 按权重随机选择一个玩法
function M.SelectGameplayByWeight(unlockedIndices)
    local totalWeight = 0
    for _, idx in ipairs(unlockedIndices) do
        totalWeight = totalWeight + GAMEPLAY_DATA[idx].weight
    end

    local roll = math.random() * totalWeight
    local cumulative = 0
    for _, idx in ipairs(unlockedIndices) do
        cumulative = cumulative + GAMEPLAY_DATA[idx].weight
        if roll <= cumulative then
            return idx
        end
    end
    return unlockedIndices[#unlockedIndices]
end

-- ============================================================================
-- 金币玩法
-- ============================================================================

--- 生成金币（在平台上方和空中随机位置）
function M.SpawnCoins(currentMapLevel)
    coins_ = {}
    for i = 1, #Cfg.PLAYERS do
        playerCoins_[i] = 0
    end

    local mapData = MAP_DATA[currentMapLevel]
    local platList = mapData and mapData.platforms or {}

    for c = 1, Cfg.COIN_COUNT do
        local x, y
        if #platList > 0 and math.random() < 0.7 then
            local plat = platList[math.random(1, #platList)]
            x = plat.x + (math.random() - 0.5) * plat.width * 0.8
            y = plat.y + plat.height / 2 + 0.5 + math.random() * 1.5
        else
            x = (math.random() - 0.5) * 14
            y = CONFIG.GroundY + 1 + math.random() * 7
        end
        table.insert(coins_, { x = x, y = y, collected = false })
    end
    print(string.format("[Coins] 生成 %d 个金币", Cfg.COIN_COUNT))
end

--- 清除场上所有金币和玩家金币计数
function M.ClearCoins()
    coins_ = {}
    for i = 1, #Cfg.PLAYERS do
        playerCoins_[i] = 0
    end
end

--- 更新金币拾取检测（每帧调用）
function M.UpdateCoinCollection(players, currentGameplayIndex)
    local gp = GAMEPLAY_DATA[currentGameplayIndex]
    if gp.scoringRule ~= "coin_top3" then return end

    for i, p in ipairs(players) do
        local px, py = p.node.position2D.x, p.node.position2D.y
        for _, coin in ipairs(coins_) do
            if not coin.collected then
                local dx = px - coin.x
                local dy = py - coin.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < Cfg.COIN_COLLECT_DIST then
                    coin.collected = true
                    playerCoins_[i] = (playerCoins_[i] or 0) + 1
                end
            end
        end
    end
end

--- 获取金币列表（渲染用）
function M.GetCoins()
    return coins_
end

--- 获取玩家金币计数表（渲染用）
function M.GetPlayerCoins()
    return playerCoins_
end

-- ============================================================================
-- 结算规则
-- ============================================================================

--- 根据结算规则计算得分玩家列表
--- @param playersInZone table 在拍照区域内的玩家索引列表
--- @param currentGameplayIndex number 当前玩法索引
--- @return table scorers 得分玩家索引列表
function M.CalculateScorers(playersInZone, currentGameplayIndex)
    local gp = GAMEPLAY_DATA[currentGameplayIndex]

    if gp.scoringRule == "coin_top3" then
        local zoneWithCoins = {}
        for _, idx in ipairs(playersInZone) do
            table.insert(zoneWithCoins, { playerIdx = idx, coins = playerCoins_[idx] or 0 })
        end
        table.sort(zoneWithCoins, function(a, b) return a.coins > b.coins end)
        local top = math.min(3, #zoneWithCoins)
        local scorers = {}
        for rank = 1, top do
            if zoneWithCoins[rank].coins > 0 then
                table.insert(scorers, zoneWithCoins[rank].playerIdx)
            end
        end
        return scorers
    else
        -- "normal" 规则: 区域内所有玩家得分
        return playersInZone
    end
end

--- 玩法在准备阶段开始时的初始化（由状态机调用）
function M.OnPrepStart(currentGameplayIndex, currentMapLevel)
    local gp = GAMEPLAY_DATA[currentGameplayIndex]
    if gp.scoringRule == "coin_top3" then
        M.SpawnCoins(currentMapLevel)
    end
end

--- 轮次结束时的清理（由状态机调用）
function M.OnRoundEnd()
    M.ClearCoins()
end

return M
