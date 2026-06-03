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
local coinTime_ = 0       -- 金币动画计时器
local coinParticles_ = {} -- 金币拾取粒子 { {x, y, vx, vy, life, maxLife, size, color} }

-- ============================================================================
-- 放大药丸系统状态
-- ============================================================================
local pills_ = {}             -- 场上药丸 { {x, y, collected} }
local pillTime_ = 0           -- 药丸动画计时器
local pillParticles_ = {}     -- 药丸拾取粒子

-- ============================================================================
-- 拔河系统状态
-- ============================================================================
local tugTeamClicks_ = { 0, 0 }       -- 各队总点击数 [1]=左队(team1), [2]=右队(team2)
local tugPlayerClicks_ = {}            -- 各玩家个人点击数
local tugPlayerPressed_ = {}           -- 玩家按键是否处于按下状态（防长按）

-- ============================================================================
-- 解锁系统
-- ============================================================================

--- 获取胜利所需分数: 单队人数 × 10
function M.GetWinScore()
    local teamSize = #Cfg.PLAYERS / 2
    return teamSize * 10
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

--- 按权重随机选择一个玩法（不重复上次，除非只解锁了一个）
---@param unlockedIndices integer[]
---@param lastGameplayIndex integer|nil 上一轮的玩法索引
function M.SelectGameplayByWeight(unlockedIndices, lastGameplayIndex)
    -- 构建候选列表：排除上次玩法（除非只有一个可选）
    local candidates = unlockedIndices
    if lastGameplayIndex and #unlockedIndices > 1 then
        candidates = {}
        for _, idx in ipairs(unlockedIndices) do
            if idx ~= lastGameplayIndex then
                table.insert(candidates, idx)
            end
        end
    end

    local totalWeight = 0
    for _, idx in ipairs(candidates) do
        totalWeight = totalWeight + GAMEPLAY_DATA[idx].weight
    end

    local roll = math.random() * totalWeight
    local cumulative = 0
    for _, idx in ipairs(candidates) do
        cumulative = cumulative + GAMEPLAY_DATA[idx].weight
        if roll <= cumulative then
            return idx
        end
    end
    return candidates[#candidates]
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

--- 生成金币拾取粒子
local function SpawnCoinParticles(cx, cy)
    local count = 8
    for i = 1, count do
        local angle = (i / count) * math.pi * 2 + math.random() * 0.5
        local speed = 1.5 + math.random() * 2.0
        table.insert(coinParticles_, {
            x = cx, y = cy,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed + 1.5,
            life = 0.5 + math.random() * 0.3,
            maxLife = 0.5 + math.random() * 0.3,
            size = 0.08 + math.random() * 0.06,
        })
    end
end

--- 更新金币动画时间和粒子（每帧调用）
function M.UpdateCoinTime(dt)
    coinTime_ = coinTime_ + dt
    -- 更新粒子
    local i = 1
    while i <= #coinParticles_ do
        local p = coinParticles_[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(coinParticles_, i)
        else
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.vy = p.vy - 5.0 * dt  -- 重力
            i = i + 1
        end
    end
end

--- 获取金币动画时间
function M.GetCoinTime()
    return coinTime_
end

--- 获取金币粒子列表（渲染用）
function M.GetCoinParticles()
    return coinParticles_
end

--- 更新金币拾取检测（每帧调用）
--- @return boolean collected 本帧是否有金币被拾取
function M.UpdateCoinCollection(players, currentGameplayIndex)
    local gp = GAMEPLAY_DATA[currentGameplayIndex]
    if gp.scoringRule ~= "coin_top3" then return false end

    local collected = false
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
                    SpawnCoinParticles(coin.x, coin.y)
                    collected = true
                end
            end
        end
    end
    return collected
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
-- 放大药丸玩法
-- ============================================================================

--- 生成药丸（在平台上方随机位置）
function M.SpawnPills(currentMapLevel, playerCount)
    pills_ = {}
    local mapData = MAP_DATA[currentMapLevel]
    local platList = mapData and mapData.platforms or {}

    -- 药丸数量 = 玩家人数 / 2（向下取整，最少1个）
    local pillCount = math.max(1, math.floor((playerCount or 2) / 2))

    for c = 1, pillCount do
        local x, y
        if #platList > 0 and math.random() < 0.7 then
            local plat = platList[math.random(1, #platList)]
            x = plat.x + (math.random() - 0.5) * plat.width * 0.6
            y = plat.y + plat.height / 2 + 0.6 + math.random() * 1.0
        else
            x = (math.random() - 0.5) * 12
            y = CONFIG.GroundY + 1.5 + math.random() * 5
        end
        table.insert(pills_, { x = x, y = y, collected = false })
    end
    print(string.format("[Pills] 生成 %d 个放大药丸（玩家数: %d）", pillCount, playerCount or 0))
end

--- 清除场上所有药丸
function M.ClearPills()
    pills_ = {}
    pillParticles_ = {}
end

--- 生成药丸拾取粒子
local function SpawnPillParticles(cx, cy)
    local count = 12
    for i = 1, count do
        local angle = (i / count) * math.pi * 2 + math.random() * 0.4
        local speed = 2.0 + math.random() * 2.5
        table.insert(pillParticles_, {
            x = cx, y = cy,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed + 2.0,
            life = 0.6 + math.random() * 0.3,
            maxLife = 0.6 + math.random() * 0.3,
            size = 0.1 + math.random() * 0.08,
        })
    end
end

--- 更新药丸动画时间和粒子（每帧调用）
function M.UpdatePillTime(dt)
    pillTime_ = pillTime_ + dt
    -- 更新粒子
    local i = 1
    while i <= #pillParticles_ do
        local p = pillParticles_[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(pillParticles_, i)
        else
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.vy = p.vy - 6.0 * dt
            i = i + 1
        end
    end
end

--- 更新药丸拾取检测（每帧调用）
--- @param players table 玩家列表
--- @param currentGameplayIndex number 当前玩法索引
--- @return number|nil collectorIndex 本帧拾取药丸的玩家索引（nil 表示无拾取）
function M.UpdatePillCollection(players, currentGameplayIndex)
    local gp = GAMEPLAY_DATA[currentGameplayIndex]
    if not gp.enlargePill then return nil end

    for i, p in ipairs(players) do
        -- 每人最多只能吃一个放大药丸
        if (p.pillScale or 1.0) > 1.0 or (p.pillScaleDuration or 0) > 0 then
            goto continue_player
        end
        local px, py = p.node.position2D.x, p.node.position2D.y
        for _, pill in ipairs(pills_) do
            if not pill.collected then
                local dx = px - pill.x
                local dy = py - pill.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < Cfg.PILL_COLLECT_DIST then
                    pill.collected = true
                    SpawnPillParticles(pill.x, pill.y)
                    return i  -- 返回拾取者索引
                end
            end
        end
        ::continue_player::
    end
    return nil
end

--- 获取药丸列表（渲染用）
function M.GetPills()
    return pills_
end

--- 获取药丸动画时间
function M.GetPillTime()
    return pillTime_
end

--- 获取药丸粒子列表
function M.GetPillParticles()
    return pillParticles_
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
        -- 规则：拾取金币达到3个且在拍照区域内即可得分
        local scorers = {}
        for _, idx in ipairs(playersInZone) do
            if (playerCoins_[idx] or 0) >= 3 then
                table.insert(scorers, idx)
            end
        end
        return scorers
    else
        -- "normal" 规则: 区域内所有玩家得分
        return playersInZone
    end
end

-- ============================================================================
-- 拔河玩法
-- ============================================================================

--- 初始化拔河系统
function M.InitTugOfWar(players, playerTeam)
    tugTeamClicks_ = { 0, 0 }
    tugPlayerClicks_ = {}
    tugPlayerPressed_ = {}
    for i = 1, #players do
        tugPlayerClicks_[i] = 0
        tugPlayerPressed_[i] = false
    end
end

--- 更新拔河点击检测（每帧调用）
--- @param players table 玩家列表
--- @param playerTeam table 玩家→队伍映射
function M.UpdateTugOfWar(players, playerTeam)
    for i, p in ipairs(players) do
        local teamIdx = playerTeam[i]
        if teamIdx then
            -- 三个键都可以按，每个键独立计数
            local keys = { p.config.keys.left, p.config.keys.right, p.config.keys.jump }
            if not tugPlayerPressed_[i] then tugPlayerPressed_[i] = {} end

            for _, key in ipairs(keys) do
                local isDown = input:GetKeyDown(key)
                if isDown and not tugPlayerPressed_[i][key] then
                    tugTeamClicks_[teamIdx] = tugTeamClicks_[teamIdx] + 1
                    tugPlayerClicks_[i] = (tugPlayerClicks_[i] or 0) + 1
                    tugPlayerPressed_[i][key] = true
                elseif not isDown then
                    tugPlayerPressed_[i][key] = false
                end
            end
        end
    end
end

--- 获取各队点击数（渲染用）
function M.GetTugTeamClicks()
    return tugTeamClicks_
end

--- 获取各玩家个人点击数（渲染用）
function M.GetTugPlayerClicks()
    return tugPlayerClicks_
end

--- 拔河结算：返回获胜队伍索引（1或2），平局返回0
function M.GetTugWinner()
    if tugTeamClicks_[1] > tugTeamClicks_[2] then
        return 1
    elseif tugTeamClicks_[2] > tugTeamClicks_[1] then
        return 2
    else
        return 0  -- 平局
    end
end

-- ============================================================================
-- 子弹躲避系统
-- ============================================================================
local bullets_ = {}               -- 子弹列表 { {x, y, vx, vy} }
local bulletDestroyedPlayers_ = {} -- 被子弹击中的玩家索引集合
local bulletFlashTimers_ = {}     -- 玩家被击中后的闪烁计时器
local bulletTime_ = 0             -- 子弹动画时间

--- 生成子弹（从屏幕顶部随机位置向下发射，带随机角度）
function M.SpawnBullets()
    bullets_ = {}
    bulletDestroyedPlayers_ = {}
    bulletFlashTimers_ = {}
    bulletTime_ = 0

    local mapW = CONFIG.MapWidth
    local mapH = CONFIG.MapHeight
    local speed = Cfg.BULLET_SPEED

    for i = 1, Cfg.BULLET_COUNT do
        -- 从顶部随机X位置生成
        local x = (math.random() - 0.5) * mapW * 0.7
        local topY = mapH / 2 - 0.1  -- 接近顶边

        -- 随机向下的角度（-60° ~ -120°，即大致朝下）
        local angle = math.rad(-60 - math.random() * 60)
        local vx = math.cos(angle) * speed
        local vy = math.sin(angle) * speed

        table.insert(bullets_, { x = x, y = topY, vx = vx, vy = vy })
    end
    print(string.format("[Bullets] 生成 %d 颗子弹", Cfg.BULLET_COUNT))
end

--- 更新子弹（移动 + 墙壁反弹 + 玩家碰撞检测）
--- @param dt number 帧时间
--- @param players table 玩家列表
--- @return number|nil hitPlayerIndex 本帧被击中的玩家索引
function M.UpdateBullets(dt, players)
    local mapW = CONFIG.MapWidth
    local mapH = CONFIG.MapHeight
    local halfW = mapW / 2
    local halfH = mapH / 2
    local bRadius = Cfg.BULLET_RADIUS
    local hitDist = Cfg.BULLET_HIT_DIST

    bulletTime_ = bulletTime_ + dt

    -- 更新闪烁计时器
    for idx, timer in pairs(bulletFlashTimers_) do
        bulletFlashTimers_[idx] = timer - dt
        if bulletFlashTimers_[idx] <= 0 then
            bulletFlashTimers_[idx] = nil
        end
    end

    local hitPlayer = nil

    for _, b in ipairs(bullets_) do
        -- 移动
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt

        -- 左右墙壁反弹
        if b.x - bRadius < -halfW then
            b.x = -halfW + bRadius
            b.vx = -b.vx
        elseif b.x + bRadius > halfW then
            b.x = halfW - bRadius
            b.vx = -b.vx
        end

        -- 顶部反弹
        if b.y + bRadius > halfH then
            b.y = halfH - bRadius
            b.vy = -b.vy
        end

        -- 底部反弹（地面以上区域）
        local bottomBound = CONFIG.GroundY - 0.2
        if b.y - bRadius < bottomBound then
            b.y = bottomBound + bRadius
            b.vy = -b.vy
        end

        -- 玩家碰撞检测
        if players then
            for i, p in ipairs(players) do
                -- 已被击中的玩家不再检测
                if not bulletDestroyedPlayers_[i] then
                    local px = p.node.position2D.x
                    local py = p.node.position2D.y
                    local dx = b.x - px
                    local dy = b.y - py
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < hitDist then
                        bulletDestroyedPlayers_[i] = true
                        bulletFlashTimers_[i] = Cfg.BULLET_FLASH_DURATION
                        hitPlayer = i
                        print(string.format("[Bullets] %s 被子弹击中！", p.config.name))
                    end
                end
            end
        end
    end

    return hitPlayer
end

--- 清除子弹系统状态
function M.ClearBullets()
    bullets_ = {}
    bulletDestroyedPlayers_ = {}
    bulletFlashTimers_ = {}
    bulletTime_ = 0
end

--- 获取子弹列表（渲染用）
function M.GetBullets()
    return bullets_
end

--- 获取子弹动画时间
function M.GetBulletTime()
    return bulletTime_
end

--- 获取被子弹击中的玩家集合
function M.GetBulletDestroyedPlayers()
    return bulletDestroyedPlayers_
end

--- 获取玩家闪烁计时器（渲染用）
function M.GetBulletFlashTimers()
    return bulletFlashTimers_
end

--- 玩家是否被子弹摧毁
function M.IsPlayerBulletDestroyed(playerIndex)
    return bulletDestroyedPlayers_[playerIndex] == true
end

-- ============================================================================
-- 生命周期
-- ============================================================================

--- 玩法在准备阶段开始时的初始化（由状态机调用）
function M.OnPrepStart(currentGameplayIndex, currentMapLevel, players, playerTeam)
    local gp = GAMEPLAY_DATA[currentGameplayIndex]
    if gp.scoringRule == "coin_top3" then
        M.SpawnCoins(currentMapLevel)
    elseif gp.scoringRule == "tug_of_war" then
        M.InitTugOfWar(players or {}, playerTeam or {})
    end
    if gp.enlargePill then
        M.SpawnPills(currentMapLevel, players and #players or 2)
    end
    if gp.dodgeBullet then
        M.SpawnBullets()
    end
end

--- 轮次结束时的清理（由状态机调用）
function M.OnRoundEnd()
    M.ClearCoins()
    M.ClearPills()
    M.ClearBullets()
    tugTeamClicks_ = { 0, 0 }
    tugPlayerClicks_ = {}
    tugPlayerPressed_ = {}
end

return M
