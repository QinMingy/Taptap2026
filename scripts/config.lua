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
        spawnX = -7,
        skinIndex = 1,
    },
    {
        name = "P2",
        color = {60, 200, 60, 255},
        keys = {left = KEY_A, jump = KEY_S, right = KEY_D},
        spawnX = -5,
        skinIndex = 2,
    },
    {
        name = "P3",
        color = {60, 100, 220, 255},
        keys = {left = KEY_Z, jump = KEY_X, right = KEY_C},
        spawnX = -3,
        skinIndex = 3,
    },
    {
        name = "P4",
        color = {220, 160, 40, 255},
        keys = {left = KEY_U, jump = KEY_I, right = KEY_O},
        spawnX = -1,
        skinIndex = 4,
    },
    {
        name = "P5",
        color = {180, 60, 220, 255},
        keys = {left = KEY_J, jump = KEY_K, right = KEY_L},
        spawnX = 1,
        skinIndex = 1,
    },
    {
        name = "P6",
        color = {60, 200, 200, 255},
        keys = {left = KEY_N, jump = KEY_M, right = KEY_COMMA},
        spawnX = 3,
        skinIndex = 2,
    },
    {
        name = "P7",
        color = {220, 120, 180, 255},
        keys = {left = KEY_7, jump = KEY_8, right = KEY_9},
        spawnX = 5,
        skinIndex = 3,
    },
    {
        name = "P8",
        color = {140, 220, 80, 255},
        keys = {left = KEY_4, jump = KEY_5, right = KEY_6},
        spawnX = 7,
        skinIndex = 4,
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
        description = "常规拍照",
        unlockThreshold = 0,
        resetPosition = false,
        prepTime = 1.0,
        photoZone = nil,
        rushTime = 5.0,
        scoringRule = "normal",
    },
    {
        name = "拾取金币",
        weight = 20,
        description = "照片内金币最高的3名玩家得分",
        unlockThreshold = 3,
        resetPosition = false,
        prepTime = 1.0,
        prepText = "抢金币",
        photoZone = nil,
        rushTime = 5.0,
        scoringRule = "coin_top3",
    },
    {
        name = "异形拍照",
        weight = 20,
        description = "注意拍照区域",
        unlockThreshold = 4,
        resetPosition = false,
        prepTime = 1.0,
        prepText = "精准站位",
        photoZone = {
            width = 0.64,   -- 默认宽（竖条: 64px）
            height = 7.2,   -- 默认高（竖条: 720px）
            presets = {
                -- 竖条 (64×720)
                { x = -6.5, y = -0.5, name = "左侧竖条" },
                { x = -0.5, y = -0.5, name = "中间竖条" },
                { x =  7.0, y = -0.5, name = "右侧竖条" },
                -- 横条 (720×64)
                { x = -5.5, y = -3.2, width = 7.2, height = 0.64, name = "左下横条" },
                { x = -1.0, y =  1.8, width = 7.2, height = 0.64, name = "上方横条" },
                { x =  4.5, y = -0.8, width = 7.2, height = 0.64, name = "右中横条" },
            },
        },
        rushTime = 5.0,
        scoringRule = "normal",
    },
    {
        name = "镜头翻转",
        weight = 20,
        description = "在镜头翻转后仍然找到拍照区域",
        unlockThreshold = 5,
        resetPosition = false,
        prepTime = 3.0,
        prepText = "视角颠倒",
        photoZone = nil,
        rushTime = 5.0,
        scoringRule = "normal",
        cameraFlip = true,  -- 标记：该玩法启用镜头翻转
    },
    {
        name = "疯狂点击",
        weight = 20,
        description = "疯狂敲击键盘，次数更多的队伍得分",
        unlockThreshold = 6,
        resetPosition = true,
        prepTime = 3.0,
        prepText = "疯狂点击！",
        rushTime = 5.0,
        scoringRule = "tug_of_war",
        disableMovement = true,   -- 禁用移动和跳跃
        dualCamera = true,        -- 双镜头模式
        photoZone = {
            width = 4.0,
            height = 2.25,
            presets = {
                { x = -4.8, y = -3.0, name = "左镜头" },
            },
        },
        -- 右镜头通过对称计算
        dualPhotoZone = {
            left  = { x = -4.8, y = -3.5, width = 4.0, height = 2.25 },
            right = { x =  4.8, y = -3.5, width = 4.0, height = 2.25 },
        },
    },
    {
        name = "真假相框",
        weight = 20,
        description = "同时出现两个拍照区域，只有一个是真的拍照区域",
        unlockThreshold = 7,
        resetPosition = false,
        prepTime = 1.0,
        photoZone = nil,        -- 使用默认尺寸和 PHOTO_PRESETS
        rushTime = 5.0,
        scoringRule = "normal",
        dualFrame = true,       -- 标记：该玩法启用真假双相框
    },
    {
        name = "地图倾斜",
        weight = 20,
        description = "倾斜地形下找到拍照区域",
        unlockThreshold = 5,
        resetPosition = false,
        prepTime = 3.0,
        photoZone = nil,
        rushTime = 5.0,
        scoringRule = "normal",
        mapTilt = true,         -- 标记：该玩法启用地图倾斜
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
