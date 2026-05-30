-- ============================================================================
-- config.lua - 游戏配置数据
-- 包含: CONFIG, PLAYERS, MAP_DATA, GAMEPLAY_DATA, UNLOCK_CONFIG, PHOTO_PRESETS
-- ============================================================================

local M = {}

-- ============================================================================
-- 游戏配置
-- ============================================================================
M.CONFIG = {
    Title = "Photo Rush - 团队抓拍",
    Gravity = 20.0,
    OrthoSize = 10.8,     -- 固定正交尺寸(匹配1920x1080设计)

    -- 地图(16:9 → 宽19.2, 高10.8)
    MapWidth = 19.2,      -- 地图宽度(物理单位)
    MapHeight = 10.8,     -- 地图高度
    GroundY = -5.0,       -- 地面中心Y(高度0.8, 底部=-5.4=屏幕底)

    -- 玩家
    PlayerRadius = 0.4,
    PlayerSpeed = 6.0,
    PlayerJumpSpeed = 11.0,
    JumpCutMultiplier = 0.4,  -- 松开跳跃键时，上升速度乘以此系数

    -- 拍照区域
    PhotoWidth = 4.0,
    PhotoHeight = 2.25,
    CountdownTime = 5.0,
    IntervalTime = 3.0,

    -- 分数
    ScorePerPhoto = 1,
}

-- ============================================================================
-- 玩家定义
-- ============================================================================
M.PLAYERS = {
    {
        name = "P1",
        color = {220, 60, 60, 255},
        keys = {left = KEY_Q, jump = KEY_W, right = KEY_E},
        spawnX = -6,
        skinIndex = 1,
    },
    {
        name = "P2",
        color = {60, 200, 60, 255},
        keys = {left = KEY_A, jump = KEY_S, right = KEY_D},
        spawnX = -2,
        skinIndex = 1,
    },
    {
        name = "P3",
        color = {60, 100, 220, 255},
        keys = {left = KEY_Z, jump = KEY_X, right = KEY_C},
        spawnX = 2,
        skinIndex = 2,
    },
    {
        name = "P4",
        color = {220, 160, 40, 255},
        keys = {left = KEY_U, jump = KEY_I, right = KEY_O},
        spawnX = 6,
        skinIndex = 2,
    },
}

-- ============================================================================
-- 解锁系统配置
-- ============================================================================
M.UNLOCK_CONFIG = {
    maps = {
        { threshold = 0,  mapIndex = 1 },
        { threshold = 6,  mapIndex = 2 },
        { threshold = 12, mapIndex = 3 },
    },
}

-- ============================================================================
-- 玩法定义
-- 每个玩法的完整属性表：
--   name, weight, description, unlockThreshold,
--   resetPosition, prepTime, photoZone, rushTime, scoringRule
-- ============================================================================
M.GAMEPLAY_DATA = {
    {
        name = "常规拍照",
        weight = 10,
        description = "跑进📷拍照区域，倒计时结束时入镜得分！",
        unlockThreshold = 0,
        resetPosition = false,
        prepTime = 1.0,
        photoZone = nil,
        rushTime = 5.0,
        scoringRule = "normal",
    },
    {
        name = "吃金币",
        weight = 20,
        description = "收集场上金币💰，拍照时区域内金币最多的前3名得分！",
        unlockThreshold = 3,
        resetPosition = false,
        prepTime = 1.0,
        photoZone = nil,
        rushTime = 5.0,
        scoringRule = "coin_top3",
    },
}

-- ============================================================================
-- 地图数据（平台布局）
-- ============================================================================
local DEFAULT_PLATFORMS = {
    {x = -5.93, y = -3.22, width = 2.60, height = 0.32},
    {x = -3.93, y = -0.80, width = 2.40, height = 0.35},
    {x = -0.96, y = -1.97, width = 2.40, height = 0.35},
    {x =  0.79, y =  0.75, width = 2.80, height = 0.35},
    {x =  3.45, y = -2.87, width = 2.80, height = 0.32},
    {x =  4.40, y = -0.10, width = 1.92, height = 0.42},
    {x =  6.61, y = -1.71, width = 3.00, height = 0.35},
    {x =  4.01, y =  2.97, width = 1.51, height = 0.35},
}

local DEFAULT_SPAWNS = {
    {x = -6, y = -3.5},
    {x = -2, y = -3.5},
    {x =  2, y = -3.5},
    {x =  6, y = -3.5},
}

M.MAP_DATA = {
    { name = "草原",  platforms = DEFAULT_PLATFORMS, spawnPoints = DEFAULT_SPAWNS },
    { name = "高原",  platforms = DEFAULT_PLATFORMS, spawnPoints = DEFAULT_SPAWNS },
    { name = "峡谷",  platforms = DEFAULT_PLATFORMS, spawnPoints = DEFAULT_SPAWNS },
}

-- ============================================================================
-- 拍照预设位置
-- ============================================================================
M.PHOTO_PRESETS = {
    { x = -4.8, y = 0.4,  name = "常规" },
    { x = 0.0,  y = 2.5,  name = "高度" },
    { x = 5.8,  y = 2.0,  name = "多路径" },
    { x = 3.0,  y = -2.7, name = "底部略高" },
    { x = 5.8,  y = -3.8, name = "角落" },
    { x = 2.5,  y = 1.0,  name = "常规2" },
}

-- ============================================================================
-- 金币系统配置
-- ============================================================================
M.COIN_RADIUS = 0.25
M.COIN_COLLECT_DIST = 0.6
M.COIN_COUNT = 15

return M
