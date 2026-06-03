-- ============================================================================
-- Photo Rush - 团队抓拍游戏 (模块化版本)
-- 玩法: 多人在同一地图上，随机刷新拍照区域，倒计时结束时在区域内的玩家获得分数
-- 操作:
--   玩家1 (红色): Q=左, W=跳跃, E=右
--   玩家2 (绿色): A=左, S=跳跃, D=右
--   玩家3 (蓝色): Z=左, X=跳跃, C=右
--   玩家4 (橙色): U=左, I=跳跃, O=右
-- ============================================================================

require "LuaScripts/Utilities/Sample"
local UI = require("urhox-libs/UI")

-- 模块引用
local tween = require("tween")
local Cfg = require("config")
local Gameplay = require("gameplay")
local Render = require("render")
local Editors = require("editors")
local TitleScreen = require("title_screen")

-- 快捷引用配置
local CONFIG = Cfg.CONFIG
local PLAYERS = Cfg.PLAYERS
local MAP_DATA = Cfg.MAP_DATA
local GAMEPLAY_DATA = Cfg.GAMEPLAY_DATA
local UNLOCK_CONFIG = Cfg.UNLOCK_CONFIG
local PHOTO_PRESETS = Cfg.PHOTO_PRESETS

-- ============================================================================
-- 皮肤系统
-- ============================================================================

--- 解析 "#RRGGBBAA" 或 "#RRGGBB" 格式的颜色字符串
local function ParseHexColor(hex)
    hex = hex:gsub("#", "")
    local r = tonumber(hex:sub(1, 2), 16) or 0
    local g = tonumber(hex:sub(3, 4), 16) or 0
    local b = tonumber(hex:sub(5, 6), 16) or 0
    local a = 255
    if #hex >= 8 then
        a = tonumber(hex:sub(7, 8), 16) or 255
    end
    return r, g, b, a
end

--- 皮肤身份信息
local function LoadSkinsConfig()
    return {
        {
            name = "Nekoark",
            headImage = "image/Charactor/Nekoark/head_neko.png",
            torsoImage = "image/Charactor/Nekoark/body_neko.png",
            armColor = "#FFFFFFFF",
            handColor = "#F5D2AAFF",
            legColor = "#32323CFF",
            shoeColor = "#50505AFF",
        },
        {
            name = "mgz2",
            headImage = "image/Charactor/mgz2/head_mgz2.png",
            torsoImage = "image/Charactor/mgz2/body_mgz2.png",
            armColor = "#2A2A30FF",
            handColor = "#F0CDA0FF",
            legColor = "#2A2A30FF",
            shoeColor = "#1A1A1EFF",
        },
        {
            name = "danding",
            headImage = "image/Charactor/danding/head_danding.png",
            torsoImage = "image/Charactor/danding/body_danding.png",
            armColor = "#7B3030FF",
            handColor = "#F0CDA0FF",
            legColor = "#2D2D35FF",
            shoeColor = "#1A1A20FF",
        },
        {
            name = "Vergil",
            headImage = "image/Charactor/Vergil/head_vergil.png",
            torsoImage = "image/Charactor/Vergil/body_vergil.png",
            armColor = "#2A3050FF",
            handColor = "#F5D2AAFF",
            legColor = "#1E1E28FF",
            shoeColor = "#141418FF",
        },
    }
end

--- 编辑器 Transform 数据（从 assets/docs/skin-editor.json 读取）
local function LoadSkinEditorConfig()
    local default = {
        playerScale = 1.0,
        capsuleRadius = 0.3,
        capsuleHeight = 1.0,
        headTransform = { scale = 1.0, offsetX = 0, offsetY = 0, rotation = 0 },
        torsoTransform = { scale = 1.0, offsetX = 0, offsetY = 0, rotation = 0 },
        armTransform = { offsetX = 0, offsetY = 0, spacing = 0 },
        legTransform = { offsetX = 0, offsetY = 0, spacing = 0 },
    }
    local jsonStr = nil
    local file = cache:GetFile("docs/skin-editor.json")
    if file then
        jsonStr = file:ReadString()
        file:Close()
        print("[SkinEditor] loaded docs/skin-editor.json, length=" .. (jsonStr and #jsonStr or 0))
    else
        print("[SkinEditor] ERROR: cannot find docs/skin-editor.json in assets")
        return default
    end
    if not jsonStr or #jsonStr == 0 then
        print("[SkinEditor] ERROR: file is empty")
        return default
    end
    local ok, data = pcall(cjson.decode, jsonStr)
    if not ok or not data then
        print("[SkinEditor] ERROR: cjson.decode failed: " .. tostring(data))
        return default
    end

    -- 应用 playerVisuals 到 Cfg.PLAYER_VISUALS（以 docs/skin-editor.json 为准）
    if data.playerVisuals then
        local pv = data.playerVisuals
        if pv.footEllipse then
            for k, v in pairs(pv.footEllipse) do
                Cfg.PLAYER_VISUALS.footEllipse[k] = v
            end
            print("[SkinEditor] footEllipse applied: offsetY=" .. tostring(Cfg.PLAYER_VISUALS.footEllipse.offsetY)
                .. " strokeWidth=" .. tostring(Cfg.PLAYER_VISUALS.footEllipse.strokeWidth))
        end
        if pv.nameLabel then
            for k, v in pairs(pv.nameLabel) do
                Cfg.PLAYER_VISUALS.nameLabel[k] = v
            end
            print("[SkinEditor] nameLabel applied: fontSize=" .. tostring(Cfg.PLAYER_VISUALS.nameLabel.fontSize)
                .. " offsetY=" .. tostring(Cfg.PLAYER_VISUALS.nameLabel.offsetY))
        end
    else
        print("[SkinEditor] WARNING: no playerVisuals in json data")
    end

    return {
        playerScale = data.playerScale or default.playerScale,
        capsuleRadius = data.capsuleRadius or default.capsuleRadius,
        capsuleHeight = data.capsuleHeight or default.capsuleHeight,
        headTransform = data.headTransform or default.headTransform,
        torsoTransform = data.torsoTransform or default.torsoTransform,
        armTransform = data.armTransform or default.armTransform,
        legTransform = data.legTransform or default.legTransform,
    }
end

-- 皮肤数据（运行时）
local skinsData_ = {}
local skinsRuntime_ = {}
local showCollisionDebug_ = false

-- 角色物理/缩放参数
local playerScale_ = 1.0
local capsuleRadius_ = 0.3
local capsuleHeight_ = 1.0

-- ============================================================================
-- 全局状态
-- ============================================================================
---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil
local physicsWorld_ = nil
local nvg_ = nil

-- 玩家状态
local players_ = {}

-- 队伍系统
local teams_ = {
    [1] = { name = "蓝队", color = {80, 140, 255, 255}, members = {}, score = 0 },
    [2] = { name = "红队", color = {255, 90, 80, 255}, members = {}, score = 0 },
}
local playerTeam_ = {}

-- 拍照区域状态
local photoZone_ = {
    active = false,
    x = 0, y = 0,
    width = CONFIG.PhotoWidth,
    height = CONFIG.PhotoHeight,
}

-- 游戏状态
local gameState_ = "lobby"
local countdown_ = 0
local prepTimer_ = 0
local flashTimer_ = 0
local showPhotoTimer_ = 0

local globalTime_ = 0  -- 全局累计时间（每帧累加dt，替代 os.clock()）
local roundResult_ = {}
local photoSnapshot_ = {}
local bulletSnapshot_ = {}  -- 拍照时子弹位置快照
local gameOver_ = false
local winner_ = ""

-- 大厅状态
local lobby_ = {
    slots = {
        { joined = false, skinIndex = 1, ready = false },
        { joined = false, skinIndex = 2, ready = false },
        { joined = false, skinIndex = 3, ready = false },
        { joined = false, skinIndex = 4, ready = false },
        { joined = false, skinIndex = 1, ready = false },
        { joined = false, skinIndex = 2, ready = false },
        { joined = false, skinIndex = 3, ready = false },
        { joined = false, skinIndex = 4, ready = false },
    },
    animTime = 0,
    -- 固定拍照区域（右侧偏下，塔前区域）
    photoZone = { x = 5.9, y = -1.6, width = CONFIG.PhotoWidth, height = CONFIG.PhotoHeight },
    -- 倒数计时
    countdown = 5.0,
    countdownActive = false,
    -- 子阶段: "select", "flash", "showPhoto"
    phase = "select",
    flashTimer = 0,
    showPhotoTimer = 0,
    photoSnapshot = {},
    -- 提示闪烁
    warningFlash = 0,
    -- 按键说明浮窗（UI.Button 控制）
    showKeyHelp = false,
}

-- 分队展示状态
local teamReveal_ = { timer = 0, duration = 3.5 }

-- 横幅状态
local teamBanner_ = { timer = 0, duration = 2.4 }

-- 公告板状态
local bulletin_ = {
    round = 1,
    confirmed = {},
    animPhase = "enter",
    animTimer = 0,
    enterDuration = 0.4,
    exitDuration = 0.35,
}

-- 解锁系统运行时状态
local unlock_ = {
    currentMapLevel = 1,
    currentGameplayIndex = 1,
}

-- 平台数据
local platforms_ = {}

-- 屏幕尺寸
local screenW_ = 1280
local screenH_ = 720

-- 音效
local shutterSound_ = nil
local coinPickupSound_ = nil
local pillPickupSound_ = nil
local jumpSound_ = nil
local landSound_ = nil
local readyConfirmSound_ = nil
local bgmNode_ = nil

-- 相机状态
local cameraNormalPos_ = Vector3(0, 0, -10)
local cameraNormalOrtho_ = CONFIG.OrthoSize
local cameraZoomed_ = false

-- 拔河玩法双区域
local tugPhotoZones_ = { left = nil, right = nil }

-- 真假相框玩法状态
local fakePhotoZone_ = { active = false, x = 0, y = 0, width = 0, height = 0 }
local fakeFrameReveal_ = { active = false, timer = 0, duration = 0.6 }  -- 揭晓动画

-- 去重：记录上一轮使用的 preset 索引（避免连续两次同位置）
local lastUsedPresetIndex_ = nil

-- 镜头翻转状态
local cameraFlipAngle_ = 0       -- 当前翻转角度（弧度，0=正常，π=180°）
local cameraFlipProxy_ = { angle = 0 }  -- tween 代理对象
local cameraFlipTween_ = nil     -- tween 实例

-- 地图倾斜状态
local mapTiltActive_ = false         -- 当前是否处于倾斜状态
local mapTiltProxy_ = { angle = 0 }  -- tween 代理（角度，度数，0→45）
local mapTiltTween_ = nil            -- tween 实例

-- ============================================================================
-- 共享游戏状态对象 G（传递给 render/editors 模块）
-- ============================================================================
local G = {}

local function SyncGameState()
    G.nvg = nvg_
    G.screenW = screenW_
    G.screenH = screenH_
    G.cameraNode = cameraNode_
    G.players = players_
    G.platforms = platforms_
    -- lobby 阶段使用 lobby 固定拍照区域
    if gameState_ == "lobby" then
        G.photoZone = {
            active = true,
            x = lobby_.photoZone.x,
            y = lobby_.photoZone.y,
            width = lobby_.photoZone.width,
            height = lobby_.photoZone.height,
        }
    else
        G.photoZone = photoZone_
    end
    G.lobby = lobby_
    G.gameState = gameState_
    G.bulletin = bulletin_
    G.unlock = unlock_
    G.teams = teams_
    G.playerTeam = playerTeam_
    G.roundResult = roundResult_
    G.photoSnapshot = photoSnapshot_
    G.bulletSnapshot = bulletSnapshot_
    -- 编辑器打开时，从 G 回写到局部变量（编辑器通过 G 修改这些值）
    if Editors.skinEditorOpen then
        playerScale_ = G.playerScale or playerScale_
        capsuleHeight_ = G.capsuleHeight or capsuleHeight_
        capsuleRadius_ = G.capsuleRadius or capsuleRadius_
        showCollisionDebug_ = G.showCollisionDebug
    else
        G.playerScale = playerScale_
        G.capsuleHeight = capsuleHeight_
        G.capsuleRadius = capsuleRadius_
        G.showCollisionDebug = showCollisionDebug_
    end
    G.skinsRuntime = skinsRuntime_
    G.skinEditorOpen = Editors.skinEditorOpen
    G.skinEditorAnimTime = Editors.skinEditorAnimTime
    G.gameOver = gameOver_
    G.winner = winner_
    G.prepTimer = prepTimer_
    G.countdown = countdown_
    G.flashTimer = flashTimer_
    G.showPhotoTimer = showPhotoTimer_
    G.cameraFlipAngle = cameraFlipAngle_
    G.tugPhotoZones = tugPhotoZones_
    G.fakePhotoZone = fakePhotoZone_
    G.fakeFrameReveal = fakeFrameReveal_
    G.mapTiltActive = mapTiltActive_
    G.tugTeamClicks = Gameplay.GetTugTeamClicks()
    G.tugPlayerClicks = Gameplay.GetTugPlayerClicks()
    G.tugWinner = Gameplay.GetTugWinner()
    G.bulletDestroyedPlayers = Gameplay.GetBulletDestroyedPlayers()
    G.bulletFlashTimers = Gameplay.GetBulletFlashTimers()
    G.bulletTime = Gameplay.GetBulletTime()
    G.getUnlockValue = function() return Gameplay.GetUnlockValue(teams_) end
    G.nextRoundPrepared = bulletin_.nextRoundPrepared or false
    G.globalTime = globalTime_
end

-- ============================================================================
-- 解锁系统逻辑（对接 Gameplay 模块）
-- ============================================================================

function GetWinScore()
    local teamSize = math.max(1, #players_ // 2)
    return teamSize * 12
end

function GetUnlockValue()
    return Gameplay.GetUnlockValue(teams_)
end

--- 切换地图
function SwitchMap(newMapLevel)
    local mapData = MAP_DATA[newMapLevel]
    if not mapData then return end

    -- 移除旧平台节点（保留地面 platforms_[1]）
    for i = #platforms_, 2, -1 do
        if platforms_[i].node then
            platforms_[i].node:Remove()
        end
        table.remove(platforms_, i)
    end

    -- 创建新平台
    for _, data in ipairs(mapData.platforms) do
        local node = scene_:CreateChild("Platform")
        node:SetPosition2D(data.x, data.y)
        node:AddTag("one_way_platform")
        local body = node:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = node:CreateComponent("CollisionBox2D")
        shape:SetSize(data.width, data.height)
        shape.friction = 0.3
        shape.restitution = 0.0
        shape.categoryBits = 1
        local platEntry = {x = data.x, y = data.y, width = data.width, height = data.height, node = node}
        table.insert(platforms_, platEntry)
    end

    -- 重置玩家位置
    for i, p in ipairs(players_) do
        local spawn = mapData.spawnPoints[i]
        if spawn then
            p.node:SetPosition2D(spawn.x, spawn.y)
        else
            p.node:SetPosition2D(0, CONFIG.GroundY + 2)
        end
        p.body.linearVelocity = Vector2(0, 0)
        p.body.awake = true
    end

    unlock_.currentMapLevel = newMapLevel
    print(string.format("[Unlock] 地图切换为: %s (等级 %d)", mapData.name, newMapLevel))
end

--- 每轮开始时的解锁检查
function CheckUnlockAndPrepareRound()
    local unlockValue = GetUnlockValue()
    print(string.format("[Unlock] 当前解锁值: %.1f", unlockValue))

    local targetMapLevel = Gameplay.GetMapLevelForUnlockValue(unlockValue)
    if targetMapLevel ~= unlock_.currentMapLevel then
        SwitchMap(targetMapLevel)
    end

    -- GM 强制玩法（无视解锁条件，仅生效一次）
    local selectedGameplay
    if Editors.gmForceGameplay then
        selectedGameplay = Editors.gmForceGameplay
        Editors.gmForceGameplay = nil  -- 消耗掉，仅一次
        print(string.format("[GM] 强制使用玩法: %s", GAMEPLAY_DATA[selectedGameplay].name))
    else
        local unlockedGameplays = Gameplay.GetUnlockedGameplays(unlockValue)
        selectedGameplay = Gameplay.SelectGameplayByWeight(unlockedGameplays, unlock_.currentGameplayIndex)
        local gp = GAMEPLAY_DATA[selectedGameplay]
        print(string.format("[Unlock] 本轮玩法: %s (权重 %d, 已解锁 %d 个玩法)", gp.name, gp.weight, #unlockedGameplays))
    end
    -- 玩法变化时重置去重索引（不同玩法有不同的 preset 列表）
    if selectedGameplay ~= unlock_.currentGameplayIndex then
        lastUsedPresetIndex_ = nil
    end
    unlock_.currentGameplayIndex = selectedGameplay
end

-- ============================================================================
-- Start
-- ============================================================================
function Start()
    SampleStart()
    graphics.windowTitle = CONFIG.Title

    nvg_ = nvgCreate(1)
    nvgCreateFont(nvg_, "sans", "Fonts/MiSans-Regular.ttf")

    -- 加载皮肤配置
    LoadSkins()

    -- 加载音效
    shutterSound_ = cache:GetResource("Sound", "audio/sfx/shutter.ogg")
    coinPickupSound_ = cache:GetResource("Sound", "audio/sfx/coin_pickup.ogg")
    pillPickupSound_ = cache:GetResource("Sound", "audio/sfx/pill_pickup.ogg")
    jumpSound_ = cache:GetResource("Sound", "audio/sfx/jump.ogg")
    landSound_ = cache:GetResource("Sound", "audio/sfx/land.ogg")
    readyConfirmSound_ = cache:GetResource("Sound", "audio/sfx/ready_confirm.ogg")

    CreateScene()

    -- 播放背景音乐（需在 CreateScene 之后）
    local bgmSound = cache:GetResource("Sound", "audio/music_1780146499986.ogg")
    if bgmSound then
        bgmSound.looped = true
        bgmNode_ = scene_:CreateChild("BGM")
        local bgmSource = bgmNode_:CreateComponent("SoundSource")
        bgmSource.soundType = SOUND_MUSIC
        bgmSource.gain = 0.5
        bgmSource:Play(bgmSound)
    end
    CreateWorld()
    CreateUI()

    -- 初始化模块
    SyncGameState()
    Render.Init(G)
    Editors.Init(G, Render)

    -- 创建编辑器 UI
    Editors.CreateSkinEditor()
    Editors.CreateTerrainEditor()
    Editors.CreateGameplayGM()
    Editors.CreateScoreGM()
    Editors.CreateEditorMenu()

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(nvg_, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleBeginContact")
    SubscribeToEvent("PhysicsEndContact2D", "HandleEndContact")
    SubscribeToEvent("PhysicsUpdateContact2D", "HandleUpdateContact")

    -- 显示主界面（标题屏幕）
    gameState_ = "title"
    local titleRoot = TitleScreen.Create(function()
        -- 主界面结束后进入大厅
        gameState_ = "lobby"
        SetLobbySelectUIVisible(true)
        print("=== Photo Rush 团队抓拍游戏启动 ===")
        print("按跳跃键加入: W / S / X / I / K / M / 8 / ↑")
        -- 播放淡入转场（竖条百叶窗收起）
        local uiRoot = UI.FindById("root")
        if uiRoot then
            TitleScreen.PlayFadeIn(uiRoot)
        end
    end)
    local uiRoot = UI.FindById("root")
    if uiRoot and titleRoot then
        uiRoot:AddChild(titleRoot)
    end
end

--- 解析 transform 字段
local function ParseTransform(t)
    if not t then return { scale = 1.0, offsetX = 0, offsetY = 0, rotation = 0 } end
    return {
        scale = t.scale or 1.0,
        offsetX = t.offsetX or 0,
        offsetY = t.offsetY or 0,
        rotation = t.rotation or 0,
    }
end

--- 加载皮肤并创建 NanoVG 图片句柄
function LoadSkins()
    skinsData_ = LoadSkinsConfig()
    local editorCfg = LoadSkinEditorConfig()
    skinsRuntime_ = {}

    playerScale_ = editorCfg.playerScale
    capsuleRadius_ = editorCfg.capsuleRadius
    capsuleHeight_ = editorCfg.capsuleHeight

    for _, skin in ipairs(skinsData_) do
        skin.headTransform = editorCfg.headTransform
        skin.torsoTransform = editorCfg.torsoTransform
        skin.armTransform = editorCfg.armTransform
        skin.legTransform = editorCfg.legTransform
    end

    for i, skin in ipairs(skinsData_) do
        local runtime = {
            name = skin.name,
            headImg = nvgCreateImage(nvg_, skin.headImage, 0),
            torsoImg = nvgCreateImage(nvg_, skin.torsoImage, 0),
            armColor = { ParseHexColor(skin.armColor) },
            handColor = { ParseHexColor(skin.handColor) },
            legColor = { ParseHexColor(skin.legColor) },
            shoeColor = { ParseHexColor(skin.shoeColor) },
            headTransform = ParseTransform(skin.headTransform),
            torsoTransform = ParseTransform(skin.torsoTransform),
            armTransform = skin.armTransform,
            legTransform = skin.legTransform,
        }
        table.insert(skinsRuntime_, runtime)
        print(string.format("[Skin] Loaded: %s (head=%d, torso=%d)", skin.name, runtime.headImg, runtime.torsoImg))
    end

    if #skinsRuntime_ == 0 then
        print("[Skin] WARNING: No skins loaded, will use fallback rendering")
    end
end

-- ============================================================================
-- 场景
-- ============================================================================
function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    physicsWorld_ = scene_:CreateComponent("PhysicsWorld2D")
    physicsWorld_.gravity = Vector2(0, -CONFIG.Gravity)

    cameraNode_ = scene_:CreateChild("Camera")
    local camera = cameraNode_:CreateComponent("Camera")
    camera.orthographic = true
    local ortho, camY = CalcContainOrthoSize()
    camera.orthoSize = ortho
    cameraNode_.position = Vector3(0, camY, -10)

    renderer:SetViewport(0, Viewport:new(scene_, camera))
end

function CalcContainOrthoSize()
    local sw = graphics:GetWidth()
    local sh = graphics:GetHeight()
    if sw <= 0 or sh <= 0 then return CONFIG.OrthoSize, 0 end

    local screenAspect = sw / sh
    local designAspect = CONFIG.MapWidth / CONFIG.MapHeight

    if screenAspect >= designAspect then
        return CONFIG.MapHeight, 0
    else
        local ortho = CONFIG.MapWidth / screenAspect
        local camY = ortho / 2 - CONFIG.MapHeight / 2
        return ortho, camY
    end
end

-- ============================================================================
-- 创建世界(地面+平台)
-- ============================================================================
function CreateWorld()
    local groundHeight = 0.63
    local groundNode = scene_:CreateChild("Ground")
    groundNode:SetPosition2D(0, -5.09)
    local groundBody = groundNode:CreateComponent("RigidBody2D")
    groundBody.bodyType = BT_STATIC
    local groundShape = groundNode:CreateComponent("CollisionBox2D")
    groundShape:SetSize(21.20, groundHeight)
    groundShape.friction = 0.3
    groundShape.restitution = 0.0
    groundShape.categoryBits = 1
    table.insert(platforms_, {x=0, y=-5.09, width=21.20, height=groundHeight, node=groundNode})

    local platformData = MAP_DATA[1].platforms
    for _, data in ipairs(platformData) do
        local node = scene_:CreateChild("Platform")
        node:SetPosition2D(data.x, data.y)
        node:AddTag("one_way_platform")
        local body = node:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = node:CreateComponent("CollisionBox2D")
        shape:SetSize(data.width, data.height)
        shape.friction = 0.3
        shape.restitution = 0.0
        shape.categoryBits = 1
        data.node = node
        table.insert(platforms_, data)
    end

    -- 左右墙壁
    local wallX = CONFIG.MapWidth / 2 + 0.8
    for _, wx in ipairs({-wallX, wallX}) do
        local wallNode = scene_:CreateChild("Wall")
        wallNode:SetPosition2D(wx, 0)
        local wallBody = wallNode:CreateComponent("RigidBody2D")
        wallBody.bodyType = BT_STATIC
        local wallShape = wallNode:CreateComponent("CollisionBox2D")
        wallShape:SetSize(1, CONFIG.MapHeight + 2)
        wallShape.categoryBits = 1
    end
end

-- ============================================================================
-- 创建玩家
-- ============================================================================
--- 创建单个玩家物理体并返回 player 对象
---@param pi number 玩家原始索引 (1-8)
---@param spawnX number 生成位置 X
---@param spawnY number 生成位置 Y
---@return table player 对象
function CreateSinglePlayer(pi, spawnX, spawnY)
    local pdata = PLAYERS[pi]
    pdata.skinIndex = lobby_.slots[pi].skinIndex

    local node = scene_:CreateChild("Player" .. pi)
    node:SetPosition2D(spawnX, spawnY)

    local body = node:CreateComponent("RigidBody2D")
    body.bodyType = BT_DYNAMIC
    body.fixedRotation = true
    body.linearDamping = 0.0
    body.gravityScale = 1.0

    local capR = capsuleRadius_ * playerScale_
    local capH = capsuleHeight_ * playerScale_
    local boxH = capH - capR * 2
    if boxH < 0.01 then boxH = 0.01 end

    local bodyBox = node:CreateComponent("CollisionBox2D")
    bodyBox.size = Vector2(capR * 2, boxH)
    bodyBox.center = Vector2(0, 0)
    bodyBox.density = 1.0
    bodyBox.friction = 0.0
    bodyBox.restitution = 0.0
    bodyBox.categoryBits = 2
    bodyBox.maskBits = 0xFFFF

    local topCap = node:CreateComponent("CollisionCircle2D")
    topCap.radius = capR
    topCap.center = Vector2(0, boxH / 2)
    topCap.density = 1.0
    topCap.friction = 0.0
    topCap.restitution = 0.0
    topCap.categoryBits = 2
    topCap.maskBits = 0xFFFF

    local bottomCap = node:CreateComponent("CollisionCircle2D")
    bottomCap.radius = capR
    bottomCap.center = Vector2(0, -boxH / 2)
    bottomCap.density = 1.0
    bottomCap.friction = 0.0
    bottomCap.restitution = 0.0
    bottomCap.categoryBits = 2
    bottomCap.maskBits = 0xFFFF

    local footSensor = node:CreateComponent("CollisionCircle2D")
    footSensor.radius = capR * 0.6
    footSensor.center = Vector2(0, -(capH / 2) * 0.9)
    footSensor.trigger = true
    footSensor.categoryBits = 4
    footSensor.maskBits = 1

    return {
        node = node,
        body = body,
        onGround = false,
        groundContacts = 0,
        score = 0,
        facing = 1,
        config = pdata,
        originalIndex = pi,
        animTime = 0,
        isMoving = false,
        velY = 0,
        jumping = false,
        scale = { x = 1.0, y = 1.0 },
        scaleTween = nil,
        wasOnGround = true,
        runDustTimer = 0,
        -- 放大药丸系统
        pillScale = 1.0,         -- 当前药丸放大倍率
        pillScaleTarget = 1.0,   -- 目标倍率
        pillScaleTimer = 0,      -- 放大进度计时器
        pillScaleDuration = 0,   -- 放大总时长
        pillScaleFrom = 1.0,     -- 放大起始值
        -- 碰撞体引用（用于药丸放大时同步尺寸）
        colliders = {
            bodyBox = bodyBox,
            topCap = topCap,
            bottomCap = bottomCap,
            footSensor = footSensor,
        },
    }
end

function CreatePlayers(activeIndices)
    players_ = {}
    local indicesToCreate = activeIndices or {}
    if #indicesToCreate == 0 then
        for i = 1, #PLAYERS do indicesToCreate[i] = i end
    end

    for seq, pi in ipairs(indicesToCreate) do
        players_[seq] = CreateSinglePlayer(pi, PLAYERS[pi].spawnX, CONFIG.GroundY + 2)
    end
end

-- ============================================================================
-- 队伍分配
-- ============================================================================
function AssignTeams()
    local indices = {}
    for i = 1, #players_ do indices[i] = i end
    for i = #indices, 2, -1 do
        local j = math.random(1, i)
        indices[i], indices[j] = indices[j], indices[i]
    end

    teams_[1].members = {}
    teams_[2].members = {}
    teams_[1].score = 0
    teams_[2].score = 0
    playerTeam_ = {}

    local half = math.floor(#players_ / 2)
    for idx = 1, #indices do
        local pi = indices[idx]
        local teamIdx = (idx <= half) and 1 or 2
        playerTeam_[pi] = teamIdx
        table.insert(teams_[teamIdx].members, pi)
    end

    for t = 1, 2 do
        local names = {}
        for _, pi in ipairs(teams_[t].members) do
            table.insert(names, players_[pi].config.name)
        end
        print(string.format("[Teams] %s: %s", teams_[t].name, table.concat(names, ", ")))
    end
end

-- ============================================================================
-- UI (分数显示)
-- ============================================================================
function CreateUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 初始化时只创建根节点，队伍 UI 在大厅结束后创建
    UI.SetRoot(UI.Panel {
        id = "root",
        width = "100%", height = "100%",
        pointerEvents = "box-none",
    })

    -- 左下角重新开始按钮
    CreateRestartButton()
    -- 左上角按键说明按钮 + 浮窗
    CreateKeyHelpUI()
    -- X 踢人按钮（覆盖在 NanoVG 槽位上方）
    CreateKickButtons()
    -- 游戏启动时处于 title 状态，隐藏选人界面专属 UI
    SetLobbySelectUIVisible(false)
end

--- 重新开始按钮（左下角）
function CreateRestartButton()
    local root = UI.FindById("root")
    if not root then return end

    local restartBtn = UI.Button {
        id = "restartBtn",
        text = "重新开始",
        fontSize = 14,
        position = "absolute",
        bottom = 16,
        left = 16,
        paddingLeft = 12,
        paddingRight = 12,
        paddingTop = 8,
        paddingBottom = 8,
        backgroundColor = {40, 40, 50, 200},
        borderWidth = 2,
        borderColor = {255, 220, 80, 200},
        borderRadius = 6,
        fontColor = {255, 220, 80, 255},
        onClick = function(self)
            ShowRestartConfirmDialog()
        end,
    }
    root:AddChild(restartBtn)
end

--- 左上角按键说明按钮 + 浮窗
function CreateKeyHelpUI()
    local root = UI.FindById("root")
    if not root then return end

    -- 构建玩家按键列表的子元素
    local keyRows = {}
    for i, pdata in ipairs(PLAYERS) do
        local c = pdata.color
        local keyStr = string.format("←%s  ↑%s  →%s",
            GetKeyName(pdata.keys.left),
            GetKeyName(pdata.keys.jump),
            GetKeyName(pdata.keys.right))
        table.insert(keyRows, UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            children = {
                UI.Label {
                    text = pdata.name,
                    fontSize = 12,
                    fontColor = {c[1], c[2], c[3], 255},
                    width = 30,
                },
                UI.Label {
                    text = keyStr,
                    fontSize = 12,
                    fontColor = {220, 220, 240, 230},
                },
            }
        })
    end

    -- 浮窗面板（默认隐藏，位置由 UpdateKickButtonLayout 每帧动态设置）
    local popup = UI.Panel {
        id = "keyHelpPopup",
        visible = false,
        position = "absolute",
        top = 230,
        left = 4,
        padding = 12,
        backgroundColor = {40, 20, 50, 235},
        borderWidth = 2,
        borderColor = {240, 100, 130, 200},
        borderRadius = 10,
        gap = 6,
        children = {
            UI.Label {
                text = "按键说明",
                fontSize = 13,
                fontColor = {255, 200, 220, 255},
                textAlign = "center",
                width = "100%",
                marginBottom = 4,
            },
            table.unpack(keyRows),
        },
    }

    -- 按钮（位置由 UpdateKickButtonLayout 每帧动态设置）
    local keyHelpBtn = UI.Button {
        id = "keyHelpBtn",
        text = "按键说明",
        fontSize = 13,
        position = "absolute",
        top = 200,
        left = 4,
        paddingLeft = 14,
        paddingRight = 14,
        paddingTop = 6,
        paddingBottom = 6,
        backgroundColor = {255, 245, 250, 220},
        borderWidth = 2,
        borderColor = {240, 100, 130, 180},
        borderRadius = 10,
        textColor = {30, 30, 30, 255},
        onClick = function(self)
            local pop = UI.FindById("keyHelpPopup")
            if not pop then return end
            lobby_.showKeyHelp = not lobby_.showKeyHelp
            pop:SetVisible(lobby_.showKeyHelp)
            -- 切换按钮样式
            if lobby_.showKeyHelp then
                self:SetStyle({
                    backgroundColor = {200, 80, 120, 230},
                    textColor = {255, 255, 255, 255},
                    borderColor = {160, 50, 90, 255},
                })
            else
                self:SetStyle({
                    backgroundColor = {255, 245, 250, 220},
                    textColor = {30, 30, 30, 255},
                    borderColor = {240, 100, 130, 180},
                })
            end
        end,
    }

    root:AddChild(keyHelpBtn)
    root:AddChild(popup)
end

--- X 踢人按钮（8个绝对定位 UI.Button，覆盖在 NanoVG 槽位上方）
function CreateKickButtons()
    local root = UI.FindById("root")
    if not root then return end

    lobby_.kickBtns = {}
    for i = 1, 8 do
        local idx = i  -- 闭包捕获
        local btn = UI.Button {
            id = "kickBtn" .. idx,
            text = "✕",
            fontSize = 12,
            position = "absolute",
            top = 0,
            left = 0,
            width = 22,
            height = 22,
            visible = false,
            paddingLeft = 0,
            paddingRight = 0,
            paddingTop = 0,
            paddingBottom = 0,
            backgroundColor = {240, 100, 130, 220},
            borderRadius = 11,
            borderWidth = 0,
            fontColor = {255, 255, 255, 250},
            onClick = function(self)
                local slot = lobby_.slots[idx]
                if slot and slot.joined then
                    -- 如果已准备（有物理角色），先移除角色
                    if slot.ready then
                        for pi, p in ipairs(players_) do
                            if p.originalIndex == idx then
                                p.node:Remove()
                                table.remove(players_, pi)
                                break
                            end
                        end
                    end
                    slot.ready = false
                    slot.joined = false
                    print(PLAYERS[idx].name .. " 被踢出大厅")
                end
            end,
        }
        root:AddChild(btn)
        lobby_.kickBtns[i] = btn
    end
end

--- 每帧更新 X 踢人按钮和按键说明按钮的位置（与 NanoVG 面板同步）
function UpdateKickButtonLayout()
    if not lobby_.kickBtns then return end
    local sw, sh = screenW_, screenH_
    local scale = UI.GetScale()  -- UI 坐标 = 物理像素 / scale

    -- NanoVG 物理像素坐标（与 DrawLobby 中 section 4 相同的计算）
    local slotW = sw * 0.065
    local slotH = sh * 0.13
    local gap = 8
    local panelPad = 12
    local nvgBtnSize = 18  -- NanoVG 中绘制的尺寸
    local panelH = 2 * slotH + gap + panelPad * 2

    for i = 1, 8 do
        local btn = lobby_.kickBtns[i]
        local slot = lobby_.slots[i]
        if slot.joined then
            local row = (i <= 4) and 0 or 1
            local col = ((i - 1) % 4)
            local sx = 4 + panelPad + col * (slotW + gap)
            local sy = 4 + panelPad + row * (slotH + gap)
            -- X按钮在槽位右上角
            local bx = sx + slotW - nvgBtnSize - 1
            local by = sy + 1
            -- 转换为 UI 坐标
            btn:SetStyle({ top = by / scale, left = bx / scale })
            btn:SetVisible(true)
        else
            btn:SetVisible(false)
        end
    end

    -- 按键说明按钮放在面板下方
    local keyHelpBtn = UI.FindById("keyHelpBtn")
    if keyHelpBtn then
        local btnTop = (4 + panelH + 6) / scale  -- 面板底部 + 6px 间距
        local btnLeft = 4 / scale
        keyHelpBtn:SetStyle({ top = btnTop, left = btnLeft })
    end
    -- 按键说明浮窗也跟着调整
    local popup = UI.FindById("keyHelpPopup")
    if popup then
        local popTop = (4 + panelH + 70) / scale  -- 按钮下方，留出足够间距不遮挡按钮
        local popLeft = 4 / scale
        popup:SetStyle({ top = popTop, left = popLeft })
    end
end

--- 隐藏/显示选人阶段专属 UI（按键说明 + X踢人按钮）
function SetLobbySelectUIVisible(visible)
    -- 按键说明按钮
    local keyHelpBtn = UI.FindById("keyHelpBtn")
    if keyHelpBtn then keyHelpBtn:SetVisible(visible) end
    -- 按键说明浮窗（隐藏时同时关闭）
    if not visible then
        local popup = UI.FindById("keyHelpPopup")
        if popup then popup:SetVisible(false) end
        lobby_.showKeyHelp = false
    end
    -- X 踢人按钮
    if lobby_.kickBtns then
        for i = 1, 8 do
            if not visible then
                lobby_.kickBtns[i]:SetVisible(false)
            end
        end
    end
end

--- 显示重新开始确认弹窗
function ShowRestartConfirmDialog()
    -- 防止重复打开
    local existing = UI.FindById("restartDialog")
    if existing then return end

    local root = UI.FindById("root")
    if not root then return end

    local dialog = UI.Panel {
        id = "restartDialog",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        width = "100%", height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = {0, 0, 0, 150},
        onClick = function(self)
            -- 点击遮罩关闭
        end,
        children = {
            UI.Panel {
                padding = 24,
                backgroundColor = {30, 35, 50, 240},
                borderWidth = 3,
                borderColor = {255, 220, 80, 220},
                borderRadius = 12,
                alignItems = "center",
                gap = 20,
                children = {
                    UI.Label {
                        text = "老大，要重新开始喵？",
                        fontSize = 20,
                        fontColor = {255, 255, 255, 255},
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 24,
                        children = {
                            UI.Button {
                                text = "取消",
                                fontSize = 16,
                                paddingLeft = 20,
                                paddingRight = 20,
                                paddingTop = 10,
                                paddingBottom = 10,
                                backgroundColor = {80, 80, 100, 220},
                                borderRadius = 6,
                                borderWidth = 2,
                                borderColor = {150, 150, 170, 200},
                                fontColor = {200, 200, 210, 255},
                                onClick = function(self)
                                    HideRestartConfirmDialog()
                                end,
                            },
                            UI.Button {
                                text = "确认",
                                fontSize = 16,
                                paddingLeft = 20,
                                paddingRight = 20,
                                paddingTop = 10,
                                paddingBottom = 10,
                                backgroundColor = {200, 60, 60, 220},
                                borderRadius = 6,
                                borderWidth = 2,
                                borderColor = {255, 100, 100, 200},
                                fontColor = {255, 255, 255, 255},
                                onClick = function(self)
                                    HideRestartConfirmDialog()
                                    RestartGame()
                                end,
                            },
                        }
                    },
                }
            },
        }
    }
    root:AddChild(dialog)
end

--- 关闭重新开始确认弹窗
function HideRestartConfirmDialog()
    local dialog = UI.FindById("restartDialog")
    if dialog then
        dialog:Remove()
    end
end

--- 大厅结束后创建队伍 UI（像素风格）
function CreateTeamUI()
    local root = UI.FindById("root")
    if not root then return end

    local winScore = GetWinScore()
    local t1c = teams_[1].color
    local t2c = teams_[2].color

    -- 构建左队成员（单行：色点+名字+分数 紧凑横排）
    local t1MemberItems = {}
    for _, pi in ipairs(teams_[1].members) do
        local pdata = PLAYERS[pi]
        table.insert(t1MemberItems, UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 3,
            children = {
                UI.Label { text = pdata.name, fontSize = 11, fontColor = {255, 255, 255, 230} },
                UI.Panel { width = 6, height = 6, borderRadius = 3, backgroundColor = pdata.color },
                UI.Label { id = "score" .. pi, text = "0", fontSize = 12, fontColor = {255, 255, 255, 255}, fontWeight = "bold" },
            }
        })
    end
    local t1MemberRow = UI.Panel {
        flexDirection = "row", gap = 6,
        children = t1MemberItems,
    }

    -- 构建右队成员（单行：色点+名字+分数 紧凑横排）
    local t2MemberItems = {}
    for _, pi in ipairs(teams_[2].members) do
        local pdata = PLAYERS[pi]
        table.insert(t2MemberItems, UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 3,
            children = {
                UI.Label { text = pdata.name, fontSize = 11, fontColor = {255, 255, 255, 230} },
                UI.Panel { width = 6, height = 6, borderRadius = 3, backgroundColor = pdata.color },
                UI.Label { id = "score" .. pi, text = "0", fontSize = 12, fontColor = {255, 255, 255, 255}, fontWeight = "bold" },
            }
        })
    end
    local t2MemberRow = UI.Panel {
        flexDirection = "row", gap = 6, justifyContent = "flex-end",
        children = t2MemberItems,
    }

    -- 左队面板（蓝/青色霓虹框 - 使用图片背景）
    local t1Panel = UI.Panel {
        id = "team1Panel",
        position = "absolute",
        top = 10, left = 10,
        width = 160, height = 70,
        borderRadius = 12,
        backgroundImage = "image/frame_blue.png",
        backgroundFit = "fill",
        pointerEvents = "none",
        justifyContent = "center",
        children = {
            -- 内容区域（叠加在图片上）
            UI.Panel {
                padding = 10, gap = 3,
                overflow = "hidden",
                children = {
                    -- 队伍标题行
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label {
                                id = "team1Score",
                                text = teams_[1].name .. " 0/" .. winScore,
                                fontSize = 15,
                                fontColor = {255, 255, 255, 255},
                                fontWeight = "bold",
                            },
                        }
                    },
                    t1MemberRow,
                }
            },
        }
    }

    -- 右队面板（粉色霓虹框 - 使用图片背景）
    local t2Panel = UI.Panel {
        id = "team2Panel",
        position = "absolute",
        top = 10, right = 10,
        width = 160, height = 70,
        borderRadius = 12,
        backgroundImage = "image/frame_pink.png",
        backgroundFit = "fill",
        pointerEvents = "none",
        justifyContent = "center",
        children = {
            -- 内容区域（叠加在图片上）
            UI.Panel {
                padding = 10, gap = 3,
                overflow = "hidden",
                alignItems = "flex-end",
                children = {
                    -- 队伍标题行
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label {
                                id = "team2Score",
                                text = teams_[2].name .. " 0/" .. winScore,
                                fontSize = 15,
                                fontColor = {255, 255, 255, 255},
                                fontWeight = "bold",
                            },
                        }
                    },
                    t2MemberRow,
                }
            },
        }
    }

    root:AddChild(t1Panel)
    root:AddChild(t2Panel)
end

-- ============================================================================
-- 物理碰撞检测
-- ============================================================================
local function GetPlayerIndex(node)
    for i, p in ipairs(players_) do
        if p.node == node then return i end
    end
    return nil
end

--- 通过 slot/原始玩家编号查找 players_ 中的索引和对象
local function GetPlayerBySlot(slotIndex)
    for i, p in ipairs(players_) do
        if p.originalIndex == slotIndex then return i, p end
    end
    return nil, nil
end

local function IsGround(node)
    if node == nil then return false end
    local name = node.name
    return name == "Ground" or name == "Platform"
end

function HandleBeginContact(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    local pi = GetPlayerIndex(nodeA) or GetPlayerIndex(nodeB)
    if pi then
        local otherNode = GetPlayerIndex(nodeA) and nodeB or nodeA
        if IsGround(otherNode) then
            players_[pi].groundContacts = players_[pi].groundContacts + 1
            players_[pi].onGround = true
        end
    end
end

function HandleEndContact(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    local pi = GetPlayerIndex(nodeA) or GetPlayerIndex(nodeB)
    if pi then
        local otherNode = GetPlayerIndex(nodeA) and nodeB or nodeA
        if IsGround(otherNode) then
            players_[pi].groundContacts = players_[pi].groundContacts - 1
            if players_[pi].groundContacts <= 0 then
                players_[pi].groundContacts = 0
                players_[pi].onGround = false
            end
        end
    end
end

function HandleUpdateContact(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")

    local platformNode, playerNode
    if nodeA:HasTag("one_way_platform") then
        platformNode, playerNode = nodeA, nodeB
    elseif nodeB:HasTag("one_way_platform") then
        platformNode, playerNode = nodeB, nodeA
    else
        return
    end

    local pi = GetPlayerIndex(playerNode)
    if not pi then return end

    -- 地图倾斜时，平台变为实心（不可穿透），跳过单向逻辑
    if mapTiltActive_ then
        return
    end

    local platPos = platformNode.position2D
    local platShape = platformNode:GetComponent("CollisionBox2D")
    local platHalfH = platShape:GetSize().y / 2
    local platTopY = platPos.y + platHalfH

    local playerPos = playerNode.position2D
    local p = players_[pi]
    local pillS = (p and p.pillScale) or 1.0
    local playerBottomY = playerPos.y - (capsuleHeight_ * playerScale_ * pillS) / 2

    if playerBottomY < platTopY - 0.05 then
        eventData["Enabled"] = Variant(false)
    end
end

-- ============================================================================
-- 游戏逻辑更新
-- ============================================================================
local frameDt_ = 0

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    frameDt_ = dt
    globalTime_ = globalTime_ + dt
    screenW_ = graphics:GetWidth()
    screenH_ = graphics:GetHeight()

    -- BGM 循环保险：检测停止后重新播放
    if bgmNode_ then
        local bgmSource = bgmNode_:GetComponent("SoundSource")
        if bgmSource and not bgmSource.playing then
            local bgmSound = cache:GetResource("Sound", "audio/music_1780146499986.ogg")
            if bgmSound then
                bgmSource:Play(bgmSound)
            end
        end
    end

    -- 主界面状态：仅处理输入（动画由 UI 内置系统自动驱动）
    if gameState_ == "title" then
        TitleScreen.HandleInput()
        return
    end

    -- Contain 策略
    if not cameraZoomed_ then
        local camera = cameraNode_:GetComponent("Camera")
        local ortho, camY = CalcContainOrthoSize()
        camera.orthoSize = ortho
        cameraNode_.position = Vector3(0, camY, -10)
    end

    -- Tab 切换编辑器
    if input:GetKeyPress(KEY_TAB) then
        Editors.ToggleEditorMenu()
    end



    -- 编辑器激活时暂停游戏
    if Editors.editorMenuOpen then
        return
    end
    if Editors.terrainEditorOpen then
        Editors.UpdateTerrainEditor(dt)
        return
    end
    if Editors.skinEditorOpen then
        Editors.skinEditorAnimTime = Editors.skinEditorAnimTime + dt * 4.0
        return
    end
    if Editors.gameplayGMOpen then
        return
    end
    if Editors.scoreGMOpen then
        return
    end

    -- 金币动画 & 粒子更新（所有状态都需要）
    Gameplay.UpdateCoinTime(dt)
    Gameplay.UpdatePillTime(dt)

    -- 大厅逻辑
    if gameState_ == "lobby" then
        UpdateLobby(dt)
        return
    end

    -- 分队展示
    if gameState_ == "team_reveal" then
        UpdateTeamReveal(dt)
        return
    end

    -- 横幅展示
    if gameState_ == "team_banner" then
        UpdateTeamBanner(dt)
        return
    end

    if gameOver_ then
        if input:GetKeyPress(KEY_R) then
            RestartGame()
        end
        return
    end

    -- prep 和 countdown 阶段
    if gameState_ == "prep" or gameState_ == "countdown" then
        local gp = GAMEPLAY_DATA[unlock_.currentGameplayIndex]
        if gp.disableMovement then
            -- 拔河玩法：不允许移动，只更新点击；锁定水平速度让重力正常工作
            Gameplay.UpdateTugOfWar(players_, playerTeam_)
            for _, p in ipairs(players_) do
                local vel = p.body.linearVelocity
                p.body.linearVelocity = Vector2(0, vel.y)
            end
        else
            UpdatePlayers(dt)
            local coinCollected = Gameplay.UpdateCoinCollection(players_, unlock_.currentGameplayIndex)
            if coinCollected and coinPickupSound_ then
                local sfxNode = scene_:CreateChild("CoinSFX")
                local sfxSource = sfxNode:CreateComponent("SoundSource")
                sfxSource:Play(coinPickupSound_)
                sfxSource.autoRemoveMode = REMOVE_NODE
            end
            -- 药丸拾取检测
            local pillCollector = Gameplay.UpdatePillCollection(players_, unlock_.currentGameplayIndex)
            if pillCollector then
                -- 启动放大效果
                local p = players_[pillCollector]
                p.pillScaleFrom = p.pillScale
                p.pillScaleTarget = Cfg.PILL_ENLARGE_SCALE
                p.pillScaleTimer = 0
                p.pillScaleDuration = Cfg.PILL_ENLARGE_DURATION
                -- 音效
                if pillPickupSound_ then
                    local sfxNode = scene_:CreateChild("PillSFX")
                    local sfxSource = sfxNode:CreateComponent("SoundSource")
                    sfxSource:Play(pillPickupSound_)
                    sfxSource.autoRemoveMode = REMOVE_NODE
                end
                print(string.format("[Pill] %s 拾取放大药丸！", p.config.name))
            end

            -- 子弹躲避更新
            local gp_bullet = GAMEPLAY_DATA[unlock_.currentGameplayIndex]
            if gp_bullet.dodgeBullet then
                Gameplay.UpdateBullets(dt, players_)
            end
        end
    end

    -- 更新药丸动画时间和粒子
    Gameplay.UpdatePillTime(dt)
    -- 更新药丸放大进度（所有状态都需要，确保动画流畅）
    UpdatePillScales(dt)

    -- 公告板确认
    if gameState_ == "bulletin" and bulletin_.animPhase == "stay" then
        UpdateBulletinConfirm()
    end

    UpdateGameState(dt)
end

-- ============================================================================
-- 大厅逻辑
-- ============================================================================

function UpdateLobby(dt)
    lobby_.animTime = lobby_.animTime + dt * 4.0
    lobby_.warningFlash = lobby_.warningFlash + dt

    -- 子阶段处理
    if lobby_.phase == "flash" then
        lobby_.flashTimer = lobby_.flashTimer - dt
        if lobby_.flashTimer <= 0 then
            lobby_.phase = "showPhoto"
            lobby_.showPhotoTimer = 2.0
        end
        return
    elseif lobby_.phase == "showPhoto" then
        lobby_.showPhotoTimer = lobby_.showPhotoTimer - dt
        if lobby_.showPhotoTimer <= 0 then
            -- 拍立得结束，进入正式游戏
            StartGameFromLobby()
        end
        return
    end

    -- === "select" 阶段 ===

    -- 更新 X 踢人按钮位置（UI 组件方式，点击由 UI.Button onClick 处理）
    UpdateKickButtonLayout()

    -- 按跳跃键加入/准备
    for i, slot in ipairs(lobby_.slots) do
        local keys = PLAYERS[i].keys
        if input:GetKeyPress(keys.jump) then
            if not slot.joined then
                -- 加入游戏
                slot.joined = true
                print(PLAYERS[i].name .. " 加入游戏")
            elseif not slot.ready then
                -- 确认准备：用共享创建函数，落入 players_[]
                slot.ready = true
                -- 计算落下起始位置：从槽位屏幕位置映射到世界坐标
                local cols = 4
                local slotW = screenW_ * 0.065
                local slotH = screenH_ * 0.13
                local gap = 8
                local panelPad = 12
                local row = (i <= 4) and 0 or 1
                local col = ((i - 1) % 4)
                local sx = panelPad + col * (slotW + gap) + slotW / 2
                local sy = panelPad + row * (slotH + gap) + slotH / 2
                local px, py = Render.ScreenToPhys(sx, sy)
                table.insert(players_, CreateSinglePlayer(i, px, py))
                print(PLAYERS[i].name .. " 确认并落下")
            end
        end
        -- 左右键切换皮肤（加入但未确认时）
        if slot.joined and not slot.ready then
            if input:GetKeyPress(keys.left) then
                slot.skinIndex = slot.skinIndex - 1
                if slot.skinIndex < 1 then slot.skinIndex = #skinsRuntime_ end
            elseif input:GetKeyPress(keys.right) then
                slot.skinIndex = slot.skinIndex + 1
                if slot.skinIndex > #skinsRuntime_ then slot.skinIndex = 1 end
            end
        end
    end

    -- 更新所有已落地玩家移动（复用局内逻辑，手感完全一致）
    UpdatePlayers(dt)

    -- 检查拍照区域逻辑
    local joinedCount = 0
    local readyCount = 0
    local allInZone = true
    local zone = lobby_.photoZone
    local halfW = zone.width / 2
    local halfH = zone.height / 2

    for i, slot in ipairs(lobby_.slots) do
        if slot.joined then
            joinedCount = joinedCount + 1
            if slot.ready then
                readyCount = readyCount + 1
                local _, p = GetPlayerBySlot(i)
                if p then
                    local pos = p.node.position2D
                    if not (pos.x >= zone.x - halfW and pos.x <= zone.x + halfW
                        and pos.y >= zone.y - halfH and pos.y <= zone.y + halfH) then
                        allInZone = false
                    end
                else
                    allInZone = false
                end
            else
                -- 有人加入但没确认，不算全在区域
                allInZone = false
            end
        end
    end

    -- 检测奇数玩家全到区域的情况
    lobby_.oddPlayerWarning = (joinedCount >= 1 and joinedCount % 2 ~= 0
        and joinedCount == readyCount and allInZone)

    -- 所有已加入玩家都确认且都在区域内
    if joinedCount >= 2 and joinedCount % 2 == 0 and joinedCount == readyCount and allInZone then
        -- 开始或继续倒数
        if not lobby_.countdownActive then
            lobby_.countdownActive = true
            lobby_.countdown = 5.0
            print("=== 倒数开始 ===")
        end
        lobby_.countdown = lobby_.countdown - dt
        if lobby_.countdown <= 0 then
            -- 倒数结束，拍照！
            LobbyTakePhoto()
        end
    else
        -- 条件不满足，停止倒数
        if lobby_.countdownActive then
            lobby_.countdownActive = false
            lobby_.countdown = 5.0
            print("=== 倒数中断 ===")
        end
    end
end

--- 大厅拍照：快门闪光 → 拍立得展示 → 正式游戏
function LobbyTakePhoto()
    lobby_.phase = "flash"
    lobby_.flashTimer = 0.35
    SetLobbySelectUIVisible(false)

    -- 记录快照（用于拍立得内渲染）
    lobby_.photoSnapshot = {}
    for i, slot in ipairs(lobby_.slots) do
        if slot.ready then
            local _, p = GetPlayerBySlot(i)
            if p then
                local pos = p.node.position2D
                table.insert(lobby_.photoSnapshot, {
                    playerIndex = i,
                    px = pos.x,
                    py = pos.y,
                    facing = p.facing,
                    skinIndex = slot.skinIndex,
                    animTime = p.animTime,
                    isMoving = p.isMoving,
                    onGround = p.onGround,
                    velY = p.velY,
                    scaleX = p.scale.x,
                    scaleY = p.scale.y,
                })
            end
        end
    end

    -- 播放快门音效
    if shutterSound_ then
        local sn = scene_:CreateChild("ShutterSfx")
        local src = sn:CreateComponent("SoundSource")
        src:Play(shutterSound_)
        src.autoRemoveMode = REMOVE_NODE
    end

    print("=== 大厅拍照！ ===")
end

function StartGameFromLobby()
    -- 隐藏选人阶段 UI
    SetLobbySelectUIVisible(false)
    -- 重置大厅子阶段
    lobby_.phase = "select"
    lobby_.countdownActive = false
    lobby_.countdown = 5.0

    -- 重定位已有 players_ 到游戏出生点（不销毁不重建）
    for _, p in ipairs(players_) do
        local spawnX = PLAYERS[p.originalIndex].spawnX
        local spawnY = CONFIG.GroundY + 2
        p.node:SetPosition2D(spawnX, spawnY)
        p.body.linearVelocity = Vector2(0, 0)
        p.body.awake = true
        p.onGround = false
        p.groundContacts = 0
        p.jumping = false
        p.score = 0
        p.scale.x = 1.0
        p.scale.y = 1.0
        p.scaleTween = nil
    end

    AssignTeams()
    CreateTeamUI()

    -- 进入分队展示界面
    teamReveal_.timer = 0
    gameState_ = "team_reveal"

    print("=== 进入分队展示 ===")
end

-- (鼠标点击处理已移至 UpdateLobby 中使用轮询方式，避免 UI 层拦截事件)

-- ============================================================================
-- 拔河玩法：玩家位置设置
-- ============================================================================
function SetupTugOfWarPositions()
    local gp = GAMEPLAY_DATA[unlock_.currentGameplayIndex]
    local dualZone = gp.dualPhotoZone
    if not dualZone then return end

    local leftZone = dualZone.left
    local rightZone = dualZone.right

    -- 左队(team1)：从左镜头右侧向左排列，面朝右
    local team1Members = teams_[1].members
    local team2Members = teams_[2].members

    local spacing = 1.2  -- 玩家之间间距

    for idx, pi in ipairs(team1Members) do
        local p = players_[pi]
        -- 从相框右侧开始向左排列
        local startX = leftZone.x + leftZone.width / 2 - 0.8
        local posX = startX - (idx - 1) * spacing
        -- 保持 BT_DYNAMIC 让重力自然落地，只设置 X 位置
        p.body.bodyType = BT_DYNAMIC
        p.node:SetPosition2D(posX, p.node.position2D.y)
        p.body.linearVelocity = Vector2(0, p.body.linearVelocity.y)
        p.facing = 1  -- 面朝右（朝向对方）
    end

    -- 右队(team2)：从右镜头左侧向右排列，面朝左
    for idx, pi in ipairs(team2Members) do
        local p = players_[pi]
        -- 从相框左侧开始向右排列
        local startX = rightZone.x - rightZone.width / 2 + 0.8
        local posX = startX + (idx - 1) * spacing
        p.body.bodyType = BT_DYNAMIC
        p.node:SetPosition2D(posX, p.node.position2D.y)
        p.body.linearVelocity = Vector2(0, p.body.linearVelocity.y)
        p.facing = -1  -- 面朝左（朝向对方）
    end
end

-- ============================================================================
-- 药丸放大进度更新
-- ============================================================================
function UpdatePillScales(dt)
    if not players_ then return end
    local baseCapR = capsuleRadius_ * playerScale_
    local baseCapH = capsuleHeight_ * playerScale_
    for _, p in ipairs(players_) do
        if p.pillScaleDuration > 0 then
            p.pillScaleTimer = p.pillScaleTimer + dt
            local t = math.min(p.pillScaleTimer / p.pillScaleDuration, 1.0)
            -- easeOutBack 缓动：有一点弹性超调效果
            local c1 = 1.70158
            local c3 = c1 + 1
            local ease = 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
            p.pillScale = p.pillScaleFrom + (p.pillScaleTarget - p.pillScaleFrom) * ease

            -- 动画完成
            if t >= 1.0 then
                p.pillScale = p.pillScaleTarget
                p.pillScaleDuration = 0
            end
        end

        -- 同步物理碰撞体尺寸（自然缩放，center 保持在 0 附近）
        -- Box2D 自然处理：放大后胶囊更高，node 中心自然被顶高，脚底仍着地
        local scale = p.pillScale
        if scale ~= 1.0 then
            local capR = baseCapR * scale
            local capH = baseCapH * scale
            local boxH = capH - capR * 2
            if boxH < 0.01 then boxH = 0.01 end

            local col = p.colliders
            col.bodyBox.size = Vector2(capR * 2, boxH)
            col.bodyBox.center = Vector2(0, 0)
            col.topCap.radius = capR
            col.topCap.center = Vector2(0, boxH / 2)
            col.bottomCap.radius = capR
            col.bottomCap.center = Vector2(0, -boxH / 2)
            col.footSensor.radius = capR * 0.6
            col.footSensor.center = Vector2(0, -(capH / 2) * 0.9)
        end
    end
end

-- ============================================================================
-- 玩家更新
-- ============================================================================
function UpdatePlayers(dt)
    for i, p in ipairs(players_) do
        local keys = p.config.keys
        local vel = p.body.linearVelocity
        local desiredVelX = 0

        if input:GetKeyDown(keys.left) then
            desiredVelX = -CONFIG.PlayerSpeed
            p.facing = -1
        elseif input:GetKeyDown(keys.right) then
            desiredVelX = CONFIG.PlayerSpeed
            p.facing = 1
        end

        p.body.linearVelocity = Vector2(desiredVelX, vel.y)

        -- 跳跃（可变高度）
        if p.onGround and input:GetKeyPress(keys.jump) then
            p.body.linearVelocity = Vector2(desiredVelX, CONFIG.PlayerJumpSpeed)
            p.body.awake = true
            p.jumping = true
            p.onGround = false
            p.groundContacts = 0
            -- 跳跃音效
            if jumpSound_ then
                local sfxNode = scene_:CreateChild("JumpSFX")
                local sfxSource = sfxNode:CreateComponent("SoundSource")
                sfxSource:Play(jumpSound_)
                sfxSource.autoRemoveMode = REMOVE_NODE
            end
            -- 起跳拉伸：X 收窄，Y 拉长
            p.scale.x = 1.0
            p.scale.y = 1.0
            p.scaleTween = tween.new(0.15, p.scale, { x = 0.8, y = 1.3 }, "outQuad")
            -- 起跳灰尘
            local pos = p.node.position2D
            local footY = pos.y - (capsuleHeight_ * playerScale_ / 2)
            Render.SpawnJumpDust(pos.x, footY)
        elseif p.jumping then
            if not input:GetKeyDown(keys.jump) then
                local vy = p.body.linearVelocity.y
                if vy > 0 then
                    p.body.linearVelocity = Vector2(p.body.linearVelocity.x, vy * CONFIG.JumpCutMultiplier)
                end
                p.jumping = false
            elseif p.body.linearVelocity.y <= 0 then
                p.jumping = false
            end
        elseif p.onGround and p.body.linearVelocity.y <= 0 then
            p.jumping = false
        end

        -- 落地检测：从空中 → 地面瞬间触发压扁
        if p.onGround and not p.wasOnGround then
            -- 落地音效
            if landSound_ then
                local sfxNode = scene_:CreateChild("LandSFX")
                local sfxSource = sfxNode:CreateComponent("SoundSource")
                sfxSource:Play(landSound_)
                sfxSource.autoRemoveMode = REMOVE_NODE
            end
            -- 落地压扁：X 拉宽，Y 压短，然后弹回
            p.scale.x = 1.0
            p.scale.y = 1.0
            p.scaleTween = tween.new(0.2, p.scale, { x = 1.25, y = 0.75 }, "outQuad")
            -- 用链式动画：压扁后弹回正常
            p._squashRecover = true
        end
        p.wasOnGround = p.onGround

        -- 更新缩放：空中根据 vy 动态拉伸，地面走 tween
        if not p.onGround and not p.scaleTween then
            -- 空中：根据 vy 绝对值做拉伸（速度越大越窄长）
            local vy = math.abs(p.body.linearVelocity.y)
            local maxVy = math.abs(CONFIG.PlayerJumpSpeed)  -- 用跳跃初速作为归一化基准
            local t = math.min(vy / maxVy, 1.0)  -- 0~1
            -- 拉伸幅度：t=0 → 1.0, t=1 → 0.8x / 1.3y
            p.scale.x = 1.0 - t * 0.2
            p.scale.y = 1.0 + t * 0.3
        elseif p.scaleTween then
            local done = p.scaleTween:update(dt)
            if done then
                if p._squashRecover then
                    -- 压扁完成，弹回正常
                    p._squashRecover = false
                    p.scaleTween = tween.new(0.15, p.scale, { x = 1.0, y = 1.0 }, "outBack")
                else
                    p.scaleTween = nil
                    p.scale.x = 1.0
                    p.scale.y = 1.0
                end
            end
        elseif p.onGround and not p.scaleTween then
            -- 地面静止时保持正常
            p.scale.x = 1.0
            p.scale.y = 1.0
        end

        p.isMoving = math.abs(desiredVelX) > 0.1
        p.velY = p.body.linearVelocity.y
        if p.isMoving then
            p.animTime = p.animTime + dt * 10
            -- 跑步灰尘：地面上移动时每隔一段时间喷一次
            if p.onGround then
                p.runDustTimer = p.runDustTimer + dt
                if p.runDustTimer >= 0.12 then
                    p.runDustTimer = 0
                    local pos = p.node.position2D
                    local footY = pos.y - (capsuleHeight_ * playerScale_ / 2)
                    Render.SpawnRunDust(pos.x, footY, p.facing)
                end
            else
                p.runDustTimer = 0
            end
        else
            p.animTime = 0
            p.runDustTimer = 0
        end
    end
end

-- ============================================================================
-- 游戏状态机
-- ============================================================================
function UpdateBulletinConfirm()
    for i, p in ipairs(players_) do
        if not bulletin_.confirmed[i] then
            if input:GetKeyPress(p.config.keys.jump) then
                bulletin_.confirmed[i] = true
                -- 准备确认音效
                if readyConfirmSound_ then
                    local sfxNode = scene_:CreateChild("ReadySFX")
                    local sfxSource = sfxNode:CreateComponent("SoundSource")
                    sfxSource:Play(readyConfirmSound_)
                    sfxSource.autoRemoveMode = REMOVE_NODE
                end
                print(p.config.name .. " 已确认准备")
            end
        end
    end

    local allConfirmed = true
    for i = 1, #players_ do
        if not bulletin_.confirmed[i] then
            allConfirmed = false
            break
        end
    end

    if allConfirmed then
        bulletin_.animPhase = "exit"
        bulletin_.animTimer = 0
    end
end

function UpdateGameState(dt)
    if gameState_ == "bulletin" then
        bulletin_.animTimer = bulletin_.animTimer + dt

        if bulletin_.animPhase == "enter" then
            if bulletin_.animTimer >= bulletin_.enterDuration then
                bulletin_.animPhase = "stay"
                bulletin_.animTimer = 0
            end
        elseif bulletin_.animPhase == "exit" then
            if bulletin_.animTimer >= bulletin_.exitDuration then
                local gp = GAMEPLAY_DATA[unlock_.currentGameplayIndex]
                for i, p in ipairs(players_) do
                    p.body.bodyType = BT_DYNAMIC
                    p.body.awake = true
                end

                if gp.resetPosition then
                    local mapData = MAP_DATA[unlock_.currentMapLevel]
                    for i, p in ipairs(players_) do
                        local spawn = mapData and mapData.spawnPoints[i]
                        if spawn then
                            p.node:SetPosition2D(spawn.x, spawn.y)
                        else
                            p.node:SetPosition2D(p.config.spawnX, CONFIG.GroundY + 2)
                        end
                        p.body.linearVelocity = Vector2(0, 0)
                    end
                end

                -- 拔河玩法：重置玩家位置到两侧
                if gp.scoringRule == "tug_of_war" then
                    SetupTugOfWarPositions()
                end

                -- 通知 gameplay 模块准备阶段开始
                Gameplay.OnPrepStart(unlock_.currentGameplayIndex, unlock_.currentMapLevel, players_, playerTeam_)

                -- 镜头翻转：创建 tween（前2秒 inOutSine 缓动 0→π）
                if gp.cameraFlip then
                    cameraFlipProxy_.angle = 0
                    cameraFlipAngle_ = 0
                    cameraFlipTween_ = tween.new(2.0, cameraFlipProxy_, { angle = math.pi }, "inOutCubic")
                else
                    cameraFlipTween_ = nil
                end

                -- 地图倾斜：创建 tween（前2秒 inOutCubic 缓动 0→45°）
                if gp.mapTilt then
                    mapTiltActive_ = true
                    mapTiltProxy_.angle = 0
                    mapTiltTween_ = tween.new(2.0, mapTiltProxy_, { angle = 45 }, "inOutCubic")
                else
                    mapTiltTween_ = nil
                end

                gameState_ = "prep"
                prepTimer_ = gp.prepTime
            end
        end

    elseif gameState_ == "prep" then
        prepTimer_ = prepTimer_ - dt

        -- 镜头翻转：tween 驱动
        local gp = GAMEPLAY_DATA[unlock_.currentGameplayIndex]
        if gp.cameraFlip and cameraFlipTween_ then
            cameraFlipTween_:update(dt)
            cameraFlipAngle_ = cameraFlipProxy_.angle
        end

        -- 地图倾斜：tween 驱动 + 应用旋转到平台节点
        if gp.mapTilt and mapTiltTween_ then
            local done = mapTiltTween_:update(dt)
            -- 应用旋转到所有非地面平台（platforms_[1] 是地面）
            for i = 2, #platforms_ do
                local plat = platforms_[i]
                if plat.node then
                    -- 物理正角度=逆时针（Y-up），顺时针需要取负
                    plat.node:SetRotation2D(-mapTiltProxy_.angle)
                end
            end
            if done then
                mapTiltTween_ = nil  -- 动画完成，停止更新
            end
        end

        if prepTimer_ <= 0 then
            SpawnPhotoZone()
            gameState_ = "countdown"
            countdown_ = gp.rushTime
        end

    elseif gameState_ == "countdown" then
        countdown_ = countdown_ - dt
        if countdown_ <= 0 then
            TakePhoto()
            cameraFlipAngle_ = 0  -- 拍完恢复正常
            cameraFlipTween_ = nil
            gameState_ = "flash"
            flashTimer_ = 0.3
        end

    elseif gameState_ == "flash" then
        flashTimer_ = flashTimer_ - dt
        -- 更新揭晓动画计时器（动画 0.6s + 停留 1s = 总计 1.6s）
        if fakeFrameReveal_.active then
            fakeFrameReveal_.timer = fakeFrameReveal_.timer + dt
            -- 动画视觉结束后隐藏假框
            if fakeFrameReveal_.timer >= fakeFrameReveal_.duration and fakePhotoZone_.active then
                fakePhotoZone_.active = false
            end
            -- 动画 + 停留全部结束
            local totalRevealTime = fakeFrameReveal_.duration + 1.0
            if fakeFrameReveal_.timer >= totalRevealTime then
                fakeFrameReveal_.timer = totalRevealTime
                fakeFrameReveal_.active = false
            end
        end
        if flashTimer_ <= 0 and not fakeFrameReveal_.active then
            gameState_ = "showPhoto"
            showPhotoTimer_ = 2.5
        end

    elseif gameState_ == "showPhoto" then
        showPhotoTimer_ = showPhotoTimer_ - dt

        -- showPhoto 阶段分两段：
        -- 前 1.5s: 纯拍立得展示
        -- 1.5s 后: 底部弹出下一关规则面板
        -- 规则面板出现后，玩家按跳跃键确认 → 进入下一轮 prep
        if showPhotoTimer_ <= 1.0 then
            -- 规则面板已展示，等待确认
            UpdateShowPhotoConfirm()
        end
    end
end

function StartNextBulletin()
    bulletin_.round = bulletin_.round + 1
    bulletin_.confirmed = {}
    for i = 1, #players_ do
        bulletin_.confirmed[i] = false
    end
    bulletin_.animPhase = "enter"
    bulletin_.animTimer = 0
    gameState_ = "bulletin"
    CheckUnlockAndPrepareRound()
end

-- ============================================================================
-- showPhoto 阶段的规则确认逻辑
-- ============================================================================
--- 在 showPhoto 的后半段（规则面板可见时），检测玩家按键确认
function UpdateShowPhotoConfirm()
    -- 规则面板出现后需要预先准备下一轮玩法（以显示正确的规则）
    if not bulletin_.nextRoundPrepared then
        bulletin_.nextRoundPrepared = true
        bulletin_.round = bulletin_.round + 1
        -- 重置确认状态
        bulletin_.confirmed = {}
        for i = 1, #players_ do
            bulletin_.confirmed[i] = false
        end
        -- 提前选好下一轮的玩法以展示规则
        CheckUnlockAndPrepareRound()
    end

    -- 检测玩家按键确认
    for i, p in ipairs(players_) do
        if not bulletin_.confirmed[i] then
            if input:GetKeyPress(p.config.keys.jump) then
                bulletin_.confirmed[i] = true
                -- 准备确认音效
                if readyConfirmSound_ then
                    local sfxNode = scene_:CreateChild("ReadySFX")
                    local sfxSource = sfxNode:CreateComponent("SoundSource")
                    sfxSource:Play(readyConfirmSound_)
                    sfxSource.autoRemoveMode = REMOVE_NODE
                end
                print(p.config.name .. " 已确认准备")
            end
        end
    end

    -- 所有玩家确认后进入下一轮 prep
    local allConfirmed = true
    for i = 1, #players_ do
        if not bulletin_.confirmed[i] then
            allConfirmed = false
            break
        end
    end

    if allConfirmed then
        -- 直接进入 prep 阶段（跳过 bulletin 动画）
        photoZone_.active = false
        Gameplay.OnRoundEnd()
        -- 重置所有玩家的药丸放大状态和碰撞体尺寸
        for _, p in ipairs(players_) do
            if p.pillScale ~= 1.0 then
                p.pillScale = 1.0
                p.pillScaleTarget = 1.0
                p.pillScaleTimer = 0
                p.pillScaleDuration = 0
                p.pillScaleFrom = 1.0
                -- 恢复碰撞体原始尺寸
                local capR = capsuleRadius_ * playerScale_
                local capH = capsuleHeight_ * playerScale_
                local boxH = capH - capR * 2
                if boxH < 0.01 then boxH = 0.01 end
                local col = p.colliders
                col.bodyBox.size = Vector2(capR * 2, boxH)
                col.bodyBox.center = Vector2(0, 0)
                col.topCap.radius = capR
                col.topCap.center = Vector2(0, boxH / 2)
                col.bottomCap.radius = capR
                col.bottomCap.center = Vector2(0, -boxH / 2)
                col.footSensor.radius = capR * 0.6
                col.footSensor.center = Vector2(0, -(capH / 2) * 0.9)
            end
        end
        bulletin_.nextRoundPrepared = false

        -- 恢复上一轮的地图倾斜状态
        if mapTiltActive_ then
            mapTiltActive_ = false
            mapTiltProxy_.angle = 0
            mapTiltTween_ = nil
            -- 恢复所有平台旋转为 0°
            for i = 2, #platforms_ do
                local plat = platforms_[i]
                if plat.node then
                    plat.node:SetRotation2D(0)
                end
            end
        end

        local gp = GAMEPLAY_DATA[unlock_.currentGameplayIndex]
        for i, p in ipairs(players_) do
            p.body.bodyType = BT_DYNAMIC
            p.body.awake = true
        end

        if gp.resetPosition then
            local mapData = MAP_DATA[unlock_.currentMapLevel]
            for i, p in ipairs(players_) do
                local spawn = mapData and mapData.spawnPoints[i]
                if spawn then
                    p.node:SetPosition2D(spawn.x, spawn.y)
                else
                    p.node:SetPosition2D(p.config.spawnX, CONFIG.GroundY + 2)
                end
                p.body.linearVelocity = Vector2(0, 0)
            end
        end

        if gp.scoringRule == "tug_of_war" then
            SetupTugOfWarPositions()
        end

        Gameplay.OnPrepStart(unlock_.currentGameplayIndex, unlock_.currentMapLevel, players_, playerTeam_)

        if gp.cameraFlip then
            cameraFlipProxy_.angle = 0
            cameraFlipAngle_ = 0
            cameraFlipTween_ = tween.new(2.0, cameraFlipProxy_, { angle = math.pi }, "inOutCubic")
        else
            cameraFlipTween_ = nil
        end

        -- 地图倾斜：创建 tween
        if gp.mapTilt then
            mapTiltActive_ = true
            mapTiltProxy_.angle = 0
            mapTiltTween_ = tween.new(2.0, mapTiltProxy_, { angle = 45 }, "inOutCubic")
        else
            mapTiltTween_ = nil
        end

        gameState_ = "prep"
        prepTimer_ = gp.prepTime
    end
end

-- ============================================================================
-- 拍照逻辑
-- ============================================================================

--- 从 presets 中选一个不与上一轮相同的位置
local function PickPresetAvoidLast(presets, excludeIndex)
    local available = {}
    for i = 1, #presets do
        if i ~= lastUsedPresetIndex_ and i ~= excludeIndex then
            available[#available + 1] = i
        end
    end
    -- 如果过滤后没有可用的（只有1-2个 preset），放宽限制
    if #available == 0 then
        for i = 1, #presets do
            if i ~= excludeIndex then
                available[#available + 1] = i
            end
        end
    end
    if #available == 0 then
        return 1  -- 极端情况回退
    end
    return available[math.random(#available)]
end

function SpawnPhotoZone()
    local gp = GAMEPLAY_DATA[unlock_.currentGameplayIndex]

    -- 清理假相框状态
    fakePhotoZone_.active = false
    fakeFrameReveal_.active = false
    fakeFrameReveal_.timer = 0

    -- 拔河玩法：使用双镜头
    if gp.dualCamera and gp.dualPhotoZone then
        tugPhotoZones_.left = gp.dualPhotoZone.left
        tugPhotoZones_.right = gp.dualPhotoZone.right
        photoZone_.x = gp.dualPhotoZone.left.x
        photoZone_.y = gp.dualPhotoZone.left.y
        photoZone_.width = gp.dualPhotoZone.left.width
        photoZone_.height = gp.dualPhotoZone.left.height
        photoZone_.active = true
        print(string.format("[TugOfWar] 双镜头: 左(%.1f,%.1f) 右(%.1f,%.1f)",
            tugPhotoZones_.left.x, tugPhotoZones_.left.y,
            tugPhotoZones_.right.x, tugPhotoZones_.right.y))
        return
    end

    -- 确定本轮镜头尺寸
    if gp.photoZone then
        photoZone_.width = gp.photoZone.width
        photoZone_.height = gp.photoZone.height
    else
        photoZone_.width = CONFIG.PhotoWidth
        photoZone_.height = CONFIG.PhotoHeight
    end

    -- 确定本轮可用位置预设
    local presets = (gp.photoZone and gp.photoZone.presets) or PHOTO_PRESETS

    -- 真假相框玩法：选两个不同位置
    if gp.dualFrame then
        local realPick = PickPresetAvoidLast(presets, nil)
        local fakePick = PickPresetAvoidLast(presets, realPick)

        local realPreset = presets[realPick]
        local fakePreset = presets[fakePick]

        -- 真相框
        photoZone_.x = realPreset.x
        photoZone_.y = realPreset.y
        photoZone_.width = realPreset.width or CONFIG.PhotoWidth
        photoZone_.height = realPreset.height or CONFIG.PhotoHeight
        photoZone_.active = true

        -- 假相框
        fakePhotoZone_.x = fakePreset.x
        fakePhotoZone_.y = fakePreset.y
        fakePhotoZone_.width = fakePreset.width or CONFIG.PhotoWidth
        fakePhotoZone_.height = fakePreset.height or CONFIG.PhotoHeight
        fakePhotoZone_.active = true

        lastUsedPresetIndex_ = realPick
        tugPhotoZones_.left = nil
        tugPhotoZones_.right = nil

        print(string.format("[DualFrame] 真相框: %s (%.1f, %.1f) | 假相框: %s (%.1f, %.1f)",
            realPreset.name, realPreset.x, realPreset.y,
            fakePreset.name, fakePreset.x, fakePreset.y))
        return
    end

    -- 普通单相框模式：只避免和上一轮相同位置
    local pick = PickPresetAvoidLast(presets, nil)
    lastUsedPresetIndex_ = pick

    local preset = presets[pick]
    photoZone_.x = preset.x
    photoZone_.y = preset.y
    if preset.width then photoZone_.width = preset.width end
    if preset.height then photoZone_.height = preset.height end
    photoZone_.active = true
    tugPhotoZones_.left = nil
    tugPhotoZones_.right = nil
    print(string.format("拍照区域出现: %s (%.1f, %.1f) [%.2f x %.2f]",
        preset.name, preset.x, preset.y, photoZone_.width, photoZone_.height))
end

function TakePhoto()
    roundResult_ = {}
    photoSnapshot_ = {}

    -- 播放快门音效
    if shutterSound_ then
        local soundNode = scene_:CreateChild("ShutterSFX")
        local soundSource = soundNode:CreateComponent("SoundSource")
        soundSource:Play(shutterSound_)
        soundSource.autoRemoveMode = REMOVE_NODE
    end

    -- 拍照快照
    for i, p in ipairs(players_) do
        local pos = p.node.position2D
        photoSnapshot_[i] = {
            x = pos.x, y = pos.y,
            facing = p.facing,
            onGround = p.onGround,
            isMoving = p.isMoving,
            animTime = p.animTime,
            pillScale = p.pillScale or 1.0,
        }
    end

    -- 子弹快照（拍照时子弹位置）
    bulletSnapshot_ = {}
    local bullets = Gameplay.GetBullets()
    for _, b in ipairs(bullets) do
        table.insert(bulletSnapshot_, { x = b.x, y = b.y, vx = b.vx, vy = b.vy })
    end

    local gp = GAMEPLAY_DATA[unlock_.currentGameplayIndex]

    -- 真假相框揭晓动画：拍照后启动
    if gp.dualFrame and fakePhotoZone_.active then
        fakeFrameReveal_.active = true
        fakeFrameReveal_.timer = 0
    end

    if gp.scoringRule == "tug_of_war" then
        -- 拔河结算：根据点击数决定获胜队伍
        local winnerTeam = Gameplay.GetTugWinner()
        local clicks = Gameplay.GetTugTeamClicks()
        print(string.format("[TugOfWar] 左队: %d clicks, 右队: %d clicks", clicks[1], clicks[2]))

        if winnerTeam == 0 then
            -- 平局：双方都得分
            for t = 1, 2 do
                for _, pi in ipairs(teams_[t].members) do
                    local p = players_[pi]
                    p.score = p.score + CONFIG.ScorePerPhoto
                    table.insert(roundResult_, pi)
                end
                teams_[t].score = teams_[t].score + CONFIG.ScorePerPhoto * #teams_[t].members
            end
            print("[TugOfWar] 平局! 双方都拍照得分")
            -- 检测双方同时达到目标分
            local ws = GetWinScore()
            if teams_[1].score >= ws and teams_[2].score >= ws then
                gameOver_ = true
                winner_ = "平局"
                print("=== 平局! ===")
            elseif teams_[1].score >= ws then
                gameOver_ = true
                winner_ = teams_[1].name
                print("=== " .. winner_ .. " 获胜! ===")
            elseif teams_[2].score >= ws then
                gameOver_ = true
                winner_ = teams_[2].name
                print("=== " .. winner_ .. " 获胜! ===")
            end
        else
            -- 获胜队所有成员得分
            local winTeam = teams_[winnerTeam]
            for _, pi in ipairs(winTeam.members) do
                local p = players_[pi]
                p.score = p.score + CONFIG.ScorePerPhoto
                table.insert(roundResult_, pi)
            end
            winTeam.score = winTeam.score + CONFIG.ScorePerPhoto * #winTeam.members
            print(string.format("[TugOfWar] %s 获胜! +%d", winTeam.name, CONFIG.ScorePerPhoto * #winTeam.members))

            if winTeam.score >= GetWinScore() then
                gameOver_ = true
                winner_ = winTeam.name
                print("=== " .. winner_ .. " 获胜! ===")
            end
        end
    else
        -- 常规结算：检测区域内玩家
        local playersInZone = {}
        for i, p in ipairs(players_) do
            -- 被子弹击中的玩家不参与结算
            if Gameplay.IsPlayerBulletDestroyed(i) then
                goto continue_score
            end

            local pos = p.node.position2D

            -- 胶囊体与矩形区域相交检测（考虑药丸放大）
            local pillS = p.pillScale or 1.0
            local capR = CONFIG.PlayerRadius * playerScale_ * pillS
            local capH = capsuleHeight_ * playerScale_ * (CONFIG.PlayerRadius / capsuleRadius_) * pillS
            local boxH = capH - capR * 2
            if boxH < 0 then boxH = 0 end

            local segBottom = pos.y - boxH / 2
            local segTop = pos.y + boxH / 2

            local rectLeft = photoZone_.x - photoZone_.width / 2
            local rectRight = photoZone_.x + photoZone_.width / 2
            local rectBottom = photoZone_.y - photoZone_.height / 2
            local rectTop = photoZone_.y + photoZone_.height / 2

            local dx = math.max(0, rectLeft - pos.x, pos.x - rectRight)
            local dy = 0
            if segTop < rectBottom then
                dy = rectBottom - segTop
            elseif segBottom > rectTop then
                dy = segBottom - rectTop
            end

            local inZone = (dx * dx + dy * dy) <= capR * capR
            if inZone then
                table.insert(playersInZone, i)
            end

            ::continue_score::
        end

        -- 使用 Gameplay 模块计算得分
        local scorers = Gameplay.CalculateScorers(playersInZone, unlock_.currentGameplayIndex)

        for _, idx in ipairs(scorers) do
            local p = players_[idx]
            p.score = p.score + CONFIG.ScorePerPhoto
            local teamIdx = playerTeam_[idx]
            if teamIdx then
                teams_[teamIdx].score = teams_[teamIdx].score + CONFIG.ScorePerPhoto
            end
            table.insert(roundResult_, idx)
            print(p.config.name .. " 得分! 个人: " .. p.score .. " 团队: " .. (teamIdx and teams_[teamIdx].score or 0))
        end

        -- 结算后统一检测胜负（避免先到先赢的顺序问题）
        if not gameOver_ then
            local ws = GetWinScore()
            local t1Done = teams_[1].score >= ws
            local t2Done = teams_[2].score >= ws
            if t1Done and t2Done then
                gameOver_ = true
                winner_ = "平局"
                print("=== 平局! ===")
            elseif t1Done then
                gameOver_ = true
                winner_ = teams_[1].name
                print("=== " .. winner_ .. " 获胜! ===")
            elseif t2Done then
                gameOver_ = true
                winner_ = teams_[2].name
                print("=== " .. winner_ .. " 获胜! ===")
            end
        end
    end

    -- 冻结玩家
    for _, p in ipairs(players_) do
        p.body.linearVelocity = Vector2(0, 0)
        p.body.bodyType = BT_STATIC
    end

    UpdateScoreUI()
end

function UpdateScoreUI()
    for i, p in ipairs(players_) do
        local label = UI.FindById("score" .. i)
        if label then label:SetText(tostring(p.score)) end
    end
    local winScore = GetWinScore()
    local t1Label = UI.FindById("team1Score")
    if t1Label then t1Label:SetText(teams_[1].name .. " " .. teams_[1].score .. "/" .. winScore) end
    local t2Label = UI.FindById("team2Score")
    if t2Label then t2Label:SetText(teams_[2].name .. " " .. teams_[2].score .. "/" .. winScore) end
end

--- GM: 直接跳转到结算画面
function GMSkipToGameOver()
    if gameOver_ then return end
    gameOver_ = true
    winner_ = teams_[1].name  -- 默认蓝队胜
    print("[GM] 跳转到结算画面")
end

function RestartGame()
    gameOver_ = false
    winner_ = ""
    photoZone_.active = false
    fakePhotoZone_.active = false
    fakeFrameReveal_.active = false
    fakeFrameReveal_.timer = 0
    lastUsedPresetIndex_ = nil
    roundResult_ = {}

    for i, p in ipairs(players_) do
        if p.node then p.node:Remove() end
    end
    players_ = {}

    unlock_.currentMapLevel = 1
    unlock_.currentGameplayIndex = 1
    Gameplay.ClearCoins()
    SwitchMap(1)

    -- 移除队伍 UI
    local t1Panel = UI.FindById("team1Panel")
    if t1Panel then t1Panel:Remove() end
    local t2Panel = UI.FindById("team2Panel")
    if t2Panel then t2Panel:Remove() end

    for i = 1, #PLAYERS do
        lobby_.slots[i].joined = false
        lobby_.slots[i].ready = false
    end
    -- players_ 已在上方清理（Remove + 清空）
    lobby_.phase = "select"
    lobby_.countdownActive = false
    lobby_.countdown = 5.0
    lobby_.warningFlash = 0
    lobby_.photoSnapshot = {}
    gameState_ = "lobby"
    SetLobbySelectUIVisible(true)
    print("=== 返回大厅 ===")
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================
function HandleNanoVGRender(eventType, eventData)
    if nvg_ == nil then return end

    -- 同步状态到 G 对象（每帧更新）
    SyncGameState()

    nvgBeginFrame(nvg_, screenW_, screenH_, 1.0)

    -- 主界面状态：不需要 NanoVG 绘制（纯 UI 实现）
    if gameState_ == "title" then
        nvgEndFrame(nvg_)
        return
    end

    if gameState_ == "lobby" then
        DrawLobby()
    elseif gameState_ == "team_reveal" then
        DrawTeamReveal()
    elseif gameState_ == "team_banner" then
        DrawTeamBanner()
    else
        -- 镜头翻转：整屏旋转
        if cameraFlipAngle_ ~= 0 then
            nvgSave(nvg_)
            nvgTranslate(nvg_, screenW_ / 2, screenH_ / 2)
            nvgRotate(nvg_, cameraFlipAngle_)
            nvgTranslate(nvg_, -screenW_ / 2, -screenH_ / 2)
        end

        Render.DrawBackground()
        Render.UpdateAndDrawClouds(frameDt_)
        Render.DrawPlatforms()
        Render.DrawCoins(Gameplay.GetCoins(), unlock_.currentGameplayIndex, Gameplay.GetCoinTime(), Gameplay.GetCoinParticles())
        Render.DrawPills(Gameplay.GetPills(), unlock_.currentGameplayIndex, Gameplay.GetPillTime(), Gameplay.GetPillParticles())
        Render.DrawBullets(Gameplay.GetBullets(), unlock_.currentGameplayIndex, Gameplay.GetBulletTime())
        Render.DrawPhotoZone()
        Render.UpdateAndDrawParticles(frameDt_)
        Render.DrawPlayers()
        Render.DrawTugPlayerClicks()
        Render.DrawPlayerCoinCount(Gameplay.GetPlayerCoins(), unlock_.currentGameplayIndex)
        Render.DrawPrepIndicator()
        Render.DrawTugScores()
        Render.DrawCountdown()
        Render.DrawFlashEffect()
        Render.DrawShowPhoto()
        Render.DrawBulletin()
        Render.DrawGameOver()

        if cameraFlipAngle_ ~= 0 then
            nvgRestore(nvg_)
        end
    end

    Editors.DrawTerrainEditor()
    Render.DrawSkinEditorPreview()

    nvgEndFrame(nvg_)
end

-- ============================================================================
-- 大厅渲染（新版：游戏地图 + 左上角小槽位 + 物理角色 + 拍照区域）
-- ============================================================================
function DrawLobby()
    local nvg = nvg_
    local sw, sh = screenW_, screenH_

    -- === 1. 渲染游戏地图背景和平台 ===
    Render.DrawBackground()
    Render.UpdateAndDrawClouds(frameDt_ or 0)
    Render.DrawPlatforms()

    -- === 2. 渲染拍照区域 ===
    Render.DrawPhotoZone()

    -- === 3. 渲染已落地的 lobby 玩家（从 players_[] 读取） ===
    local ppu = Render.GetPixelsPerUnit()
    for _, p in ipairs(players_) do
        local pos = p.node.position2D
        local playerSX, playerSY = Render.PhysToScreen(pos.x, pos.y)
        local slot = lobby_.slots[p.originalIndex]
        local skin = skinsRuntime_[slot.skinIndex]
        local pdata = p.config
        local c = pdata.color

        local limbSwing = 0
        local armSwing = 0
        if p.isMoving and p.onGround then
            limbSwing = math.sin(p.animTime * 8) * 0.5
            armSwing = -math.sin(p.animTime * 8) * 0.35
        end

        Render.DrawSinglePlayer({
            sx = playerSX,
            sy = playerSY,
            color = c,
            skin = skin,
            facing = p.facing,
            limbSwing = limbSwing,
            armSwing = armSwing,
            inAir = not p.onGround,
            isMoving = p.isMoving,
            onGround = p.onGround,
            velY = p.velY,
            name = pdata.name,
            scaleX = p.scale.x,
            scaleY = p.scale.y,
        })
    end

    -- === 4. 左上角小槽位面板（粉青可爱风） ===
    local cols = 4
    local slotW = sw * 0.065
    local slotH = sh * 0.13
    local gap = 8
    local panelPad = 12
    local panelW = cols * slotW + (cols - 1) * gap + panelPad * 2
    local panelH = 2 * slotH + gap + panelPad * 2

    -- 面板背景（白色半透明 + 粉色圆角边框）
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, 4, 4, panelW, panelH, 14)
    nvgFillColor(nvg, nvgRGBA(255, 245, 250, 210))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, 4, 4, panelW, panelH, 14)
    nvgStrokeColor(nvg, nvgRGBA(240, 100, 130, 160))
    nvgStrokeWidth(nvg, 2.5)
    nvgStroke(nvg)

    for i, slot in ipairs(lobby_.slots) do
        local row = (i <= 4) and 0 or 1
        local col = ((i - 1) % 4)
        local sx = 4 + panelPad + col * (slotW + gap)
        local sy = 4 + panelPad + row * (slotH + gap)
        local pdata = PLAYERS[i]
        local c = pdata.color

        -- 槽位背景（白色卡片风格）
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, sx, sy, slotW, slotH, 8)
        if slot.ready then
            nvgFillColor(nvg, nvgRGBA(220, 255, 235, 230))
        elseif slot.joined then
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 200))
        else
            nvgFillColor(nvg, nvgRGBA(240, 235, 245, 140))
        end
        nvgFill(nvg)

        -- 边框（柔和彩色）
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, sx, sy, slotW, slotH, 8)
        if slot.ready then
            nvgStrokeColor(nvg, nvgRGBA(100, 220, 160, 240))
            nvgStrokeWidth(nvg, 2.5)
        elseif slot.joined then
            nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], 200))
            nvgStrokeWidth(nvg, 2)
        else
            nvgStrokeColor(nvg, nvgRGBA(200, 180, 220, 100))
            nvgStrokeWidth(nvg, 1.5)
        end
        nvgStroke(nvg)

        if slot.joined then
            -- 缩小版角色预览
            local skinIdx = slot.skinIndex
            local skin = skinsRuntime_[skinIdx]
            if skin then
                local limbSwing = math.sin(lobby_.animTime + i) * 0.3
                local armSwing = -math.sin(lobby_.animTime + i) * 0.2
                Render.DrawSinglePlayer({
                    sx = sx + slotW / 2,
                    sy = sy + slotH * 0.45,
                    color = c,
                    skin = skin,
                    facing = 1,
                    limbSwing = slot.ready and 0 or limbSwing,
                    armSwing = slot.ready and 0 or armSwing,
                    inAir = false,
                    isMoving = not slot.ready,
                    onGround = true,
                    velY = 0,
                    name = "",
                    scaleX = 0.7,
                    scaleY = 0.7,
                })
            end

            -- 玩家名称（顶部，深粉紫色）
            nvgFontSize(nvg, 9)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(nvg, nvgRGBA(140, 60, 120, 240))
            nvgText(nvg, sx + slotW / 2, sy + 2, pdata.name, nil)

            -- 状态（底部）
            nvgFontSize(nvg, 8)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            if slot.ready then
                nvgFillColor(nvg, nvgRGBA(60, 190, 130, 240))
                nvgText(nvg, sx + slotW / 2, sy + slotH - 2, "READY ✓", nil)
            else
                nvgFillColor(nvg, nvgRGBA(240, 130, 80, 200))
                nvgText(nvg, sx + slotW / 2, sy + slotH - 2, "← →", nil)
            end

            -- X 按钮由 UI.Button 组件渲染（CreateKickButtons），此处不再用 NanoVG 绘制
        else
            -- 未加入：显示按键提示（柔和紫色）
            nvgFontSize(nvg, 9)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(160, 130, 180, 180))
            nvgText(nvg, sx + slotW / 2, sy + slotH / 2, GetKeyName(pdata.keys.jump), nil)
        end
    end

    -- 按键说明按钮+浮窗由 UI.Button 组件渲染（CreateKeyHelpUI），不再用 NanoVG

    -- === 5. 提示文字 + 倒数 ===
    nvgFontFace(nvg, "sans")

    local joinedCount = 0
    local readyCount = 0
    for _, slot in ipairs(lobby_.slots) do
        if slot.joined then
            joinedCount = joinedCount + 1
            if slot.ready then readyCount = readyCount + 1 end
        end
    end

    -- (A) 上方操作说明（闪烁，慢速）
    local blinkAlpha = math.floor(160 + 95 * math.sin((lobby_.animTime or 0) * 1.2))
    local instrX = sw * 0.5
    local instrY = sh * 0.18
    -- 背景半透明框
    local boxW, boxH = 580, 100
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, instrX - boxW / 2, instrY - boxH / 2, boxW, boxH, 14)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(blinkAlpha * 0.4)))
    nvgFill(nvg)
    -- 文字（放大2倍）
    nvgFontSize(nvg, 36)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, blinkAlpha))
    nvgText(nvg, instrX, instrY - 20, "单击 ↑ 加入游戏，← → 切换人物", nil)
    nvgText(nvg, instrX, instrY + 20, "再次单击 ↑ 确认", nil)

    -- (B) 手指指向拍照区域 + 提示
    local zone = lobby_.photoZone
    local zoneSX, zoneSY = Render.PhysToScreen(zone.x, zone.y)
    local zonePpu = Render.GetPixelsPerUnit()
    local zoneScreenW = zone.width * zonePpu
    -- 手指从上方指向拍照区域
    local zoneScreenH = zone.height * zonePpu
    local fingerX = zoneSX
    local fingerY = zoneSY - zoneScreenH / 2 - 40
    -- 浮动动画（上下）
    local floatOffset = math.sin((lobby_.animTime or 0) * 2.0) * 8
    fingerY = fingerY + floatOffset
    nvgFontSize(nvg, 64)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 240))
    nvgText(nvg, fingerX, fingerY, "👇", nil)
    -- 文字在手指上方
    nvgFontSize(nvg, 36)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    local arrowAlpha = math.floor(180 + 75 * math.sin((lobby_.animTime or 0) * 1.5))
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, arrowAlpha))
    nvgText(nvg, fingerX, fingerY - 38, "所有人到这拍照进入游戏", nil)

    -- (C) 倒数计时（屏幕中心，放大2倍）
    if lobby_.countdownActive then
        local cdSec = math.ceil(lobby_.countdown)
        nvgFontSize(nvg, 144)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(240, 80, 130, 250))
        nvgText(nvg, sw / 2, sh / 2 - 20, tostring(cdSec), nil)

        nvgFontSize(nvg, 32)
        nvgFillColor(nvg, nvgRGBA(100, 220, 240, 240))
        nvgText(nvg, sw / 2, sh / 2 + 60, "全员就位！即将拍照...", nil)
    end

    -- (C2) 奇数玩家全到拍照区域时的中央闪烁警告
    if lobby_.oddPlayerWarning then
        local flashT = lobby_.warningFlash * 5
        local alpha = math.floor(180 + 75 * math.sin(flashT))
        -- 半透明背景条
        local boxW2, boxH2 = 460, 56
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, sw / 2 - boxW2 / 2, sh / 2 - boxH2 / 2, boxW2, boxH2, 12)
        nvgFillColor(nvg, nvgRGBA(60, 10, 20, math.floor(alpha * 0.7)))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, sw / 2 - boxW2 / 2, sh / 2 - boxH2 / 2, boxW2, boxH2, 12)
        nvgStrokeColor(nvg, nvgRGBA(240, 80, 100, alpha))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)
        -- 文字
        nvgFontSize(nvg, 28)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(255, 100, 120, alpha))
        nvgText(nvg, sw / 2, sh / 2, "需要双数玩家才能进行游戏!", nil)
    end

    -- (D) 底部状态提示
    nvgFontSize(nvg, 18)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local hintY = sh - 40
    if joinedCount < 2 then
        nvgFillColor(nvg, nvgRGBA(120, 100, 160, 200))
        nvgText(nvg, sw / 2, hintY, "按 ↑ 加入 → ← → 选皮肤 → 再按 ↑ 确认落下", nil)
    elseif joinedCount ~= readyCount then
        nvgFillColor(nvg, nvgRGBA(240, 160, 60, 220))
        nvgText(nvg, sw / 2, hintY, "等待所有人确认...", nil)
    elseif joinedCount % 2 ~= 0 then
        local flashAlpha = math.floor(160 + 80 * math.sin(lobby_.warningFlash * 6))
        nvgFillColor(nvg, nvgRGBA(240, 80, 100, flashAlpha))
        nvgText(nvg, sw / 2, hintY, "玩家人数需要为双数!", nil)
    else
        nvgFillColor(nvg, nvgRGBA(80, 200, 160, 220))
        nvgText(nvg, sw / 2, hintY, "全员进入拍照区域开始倒数!", nil)
    end

    -- === 6. 闪光效果（拍照瞬间） ===
    if lobby_.phase == "flash" then
        local flashProgress = lobby_.flashTimer / 0.35
        local alpha = math.floor(255 * flashProgress)
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, sw, sh)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, alpha))
        nvgFill(nvg)
    end

    -- === 7. 拍立得展示（lobby 子阶段） ===
    if lobby_.phase == "showPhoto" then
        local progress = math.min(1.0, (2.0 - lobby_.showPhotoTimer) / 0.3)

        -- 半透明遮罩
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, sw, sh)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(180 * progress)))
        nvgFill(nvg)

        -- 拍立得相框
        local pZone = lobby_.photoZone
        local zoneAspect = pZone.width / pZone.height
        local maxPhotoW = sw * 0.55
        local maxPhotoH = sh * 0.55
        local photoW, photoH
        if maxPhotoW / zoneAspect <= maxPhotoH then
            photoW = maxPhotoW
            photoH = maxPhotoW / zoneAspect
        else
            photoH = maxPhotoH
            photoW = maxPhotoH * zoneAspect
        end

        local framePad = math.floor(photoW * 0.04)
        local frameBottom = math.floor(photoH * 0.18)
        local totalW = photoW + framePad * 2
        local totalH = photoH + framePad + frameBottom
        local frameX = (sw - totalW) / 2
        local frameY = (sh - totalH) / 2 - sh * 0.02
        local offsetY = (1.0 - progress) * 30
        frameY = frameY + offsetY

        -- 相框阴影
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, frameX + 4, frameY + 5, totalW, totalH, 5)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(80 * progress)))
        nvgFill(nvg)

        -- 白色相框
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, frameX, frameY, totalW, totalH, 5)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(250 * progress)))
        nvgFill(nvg)

        -- 照片内容区域（裁切到拍照区域）
        local photoX = frameX + framePad
        local photoY = frameY + framePad

        nvgSave(nvg)
        nvgScissor(nvg, photoX, photoY, photoW, photoH)

        -- 缩放渲染：将物理世界的拍照区域映射到照片区域
        local zoneCenterSX, zoneCenterSY = Render.PhysToScreen(pZone.x, pZone.y)
        local pZoneScreenW = pZone.width * ppu
        local pZoneScreenH = pZone.height * ppu
        local scaleX = photoW / pZoneScreenW
        local scaleY = photoH / pZoneScreenH
        local scale = math.min(scaleX, scaleY)

        local photoCenterX = photoX + photoW / 2
        local photoCenterY = photoY + photoH / 2

        nvgTranslate(nvg, photoCenterX, photoCenterY)
        nvgScale(nvg, scale, scale)
        nvgTranslate(nvg, -zoneCenterSX, -zoneCenterSY)

        -- 在变换坐标系中重新渲染背景和平台
        Render.DrawBackground()
        Render.DrawPlatforms()

        -- 渲染快照中的玩家
        for _, snap in ipairs(lobby_.photoSnapshot) do
            local snapSX, snapSY = Render.PhysToScreen(snap.px, snap.py)
            local skin = skinsRuntime_[snap.skinIndex]
            local pdata = PLAYERS[snap.playerIndex]
            local c = pdata.color
            Render.DrawSinglePlayer({
                sx = snapSX,
                sy = snapSY,
                color = c,
                skin = skin,
                facing = snap.facing,
                limbSwing = 0,
                armSwing = 0,
                inAir = not snap.onGround,
                isMoving = snap.isMoving,
                onGround = snap.onGround,
                velY = snap.velY,
                name = pdata.name,
                scaleX = snap.scaleX,
                scaleY = snap.scaleY,
            })
        end

        nvgRestore(nvg)

        -- 底部文字 "Photo Rush!"
        nvgFontSize(nvg, 18)
        nvgFontFace(nvg, "sans")
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(80, 80, 80, math.floor(220 * progress)))
        nvgText(nvg, sw / 2, frameY + totalH - frameBottom / 2, "Photo Rush!", nil)
    end
end

-- ============================================================================
-- 分队展示界面（team_reveal）- 粉蓝可爱风格
-- ============================================================================
function DrawTeamReveal()
    local nvg = nvg_
    local sw, sh = screenW_, screenH_

    -- 背景（浅粉蓝渐变 - 匹配开屏画面风格）
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, sw, sh)
    local bg = nvgLinearGradient(nvg, 0, 0, sw, sh,
        nvgRGBA(200, 230, 255, 255), nvgRGBA(255, 210, 230, 255))
    nvgFillPaint(nvg, bg)
    nvgFill(nvg)

    -- 装饰：散落的星星/圆点
    for i = 1, 12 do
        local dx = (sw * ((i * 137) % 100) / 100)
        local dy = (sh * ((i * 73 + 29) % 100) / 100)
        local pulse = 0.6 + 0.4 * math.sin(teamReveal_.timer * 2.0 + i * 0.8)
        local dotR = 4 + (i % 3) * 3
        nvgBeginPath(nvg)
        nvgCircle(nvg, dx, dy, dotR * pulse)
        if i % 2 == 0 then
            nvgFillColor(nvg, nvgRGBA(255, 150, 200, math.floor(100 * pulse)))
        else
            nvgFillColor(nvg, nvgRGBA(100, 200, 255, math.floor(100 * pulse)))
        end
        nvgFill(nvg)
    end

    -- 动画进度
    local t = math.min(teamReveal_.timer / 0.8, 1.0) -- 入场动画0.8秒

    -- VS 文字（大号粉色描边）
    nvgFontSize(nvg, 72)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local vsAlpha = math.floor(math.min(teamReveal_.timer / 0.5, 1.0) * 255)
    -- 白色描边
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, vsAlpha))
    nvgStrokeWidth(nvg, 4)
    -- 粉色填充
    nvgFillColor(nvg, nvgRGBA(240, 80, 140, vsAlpha))
    nvgText(nvg, sw/2, sh/2, "VS", nil)

    -- 分隔线（渐变粉色线）
    nvgBeginPath(nvg)
    nvgRect(nvg, sw/2 - 1.5, sh * 0.12, 3, sh * 0.76)
    local lineGrad = nvgLinearGradient(nvg, sw/2, sh*0.12, sw/2, sh*0.88,
        nvgRGBA(100, 200, 255, math.floor(vsAlpha*0.5)),
        nvgRGBA(255, 130, 180, math.floor(vsAlpha*0.5)))
    nvgFillPaint(nvg, lineGrad)
    nvgFill(nvg)

    -- 左队（蓝队）
    local team1 = teams_[1]
    local tc1 = team1.color
    -- 右队（红队）
    local team2 = teams_[2]
    local tc2 = team2.color

    -- 队名（加大，带阴影）
    nvgFontSize(nvg, 36)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    -- 蓝队名阴影
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(vsAlpha * 0.15)))
    nvgText(nvg, sw * 0.25 + 2, sh * 0.06 + 2, team1.name, nil)
    -- 蓝队名
    nvgFillColor(nvg, nvgRGBA(tc1[1], tc1[2], tc1[3], vsAlpha))
    nvgText(nvg, sw * 0.25, sh * 0.06, team1.name, nil)

    -- 红队名阴影
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(vsAlpha * 0.15)))
    nvgText(nvg, sw * 0.75 + 2, sh * 0.06 + 2, team2.name, nil)
    -- 红队名
    nvgFillColor(nvg, nvgRGBA(tc2[1], tc2[2], tc2[3], vsAlpha))
    nvgText(nvg, sw * 0.75, sh * 0.06, team2.name, nil)

    -- 绘制左队成员（从左滑入）
    local leftCount = #team1.members
    local cardH = math.min(150, (sh * 0.68) / math.max(leftCount, 1))
    local cardW = sw * 0.38
    local leftBaseX = sw * 0.25
    local baseY = sh * 0.16

    for idx, pi in ipairs(team1.members) do
        local p = players_[pi]
        local slideOffset = (1 - t) * (-250) -- 从左侧滑入
        local cy = baseY + (idx - 1) * (cardH + 10)
        local cx = leftBaseX + slideOffset
        local pc = p.config.color -- 玩家专属颜色

        -- 卡片背景（白色圆角卡片 + 柔和阴影）
        -- 阴影
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - cardW/2 + 3, cy + 3, cardW, cardH - 10, 16)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(20 * t)))
        nvgFill(nvg)
        -- 白色卡片
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - cardW/2, cy, cardW, cardH - 10, 16)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(230 * t)))
        nvgFill(nvg)
        -- 队伍颜色边框
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - cardW/2, cy, cardW, cardH - 10, 16)
        nvgStrokeColor(nvg, nvgRGBA(tc1[1], tc1[2], tc1[3], math.floor(200 * t)))
        nvgStrokeWidth(nvg, 2.5)
        nvgStroke(nvg)

        -- 角色立绘（通过 skinIndex 获取皮肤）
        local skinIdx = p.config.skinIndex or 1
        local skin = skinsRuntime_[skinIdx]
        if skin then
            local breathe = 1.0 + math.sin(teamReveal_.timer * 2.5 + pi * 1.3) * 0.03
            local baseScale = 2.0
            Render.DrawSinglePlayer({
                sx = cx - cardW * 0.22,
                sy = cy + cardH * 0.5,
                color = pc,
                skin = skin,
                facing = 1,
                limbSwing = math.sin(teamReveal_.timer * 2.0 + pi) * 0.1,
                armSwing = -math.sin(teamReveal_.timer * 2.0 + pi) * 0.08,
                inAir = false,
                isMoving = false,
                onGround = true,
                velY = 0,
                name = "",
                scaleX = baseScale * breathe,
                scaleY = baseScale * breathe,
            })
        end

        -- 玩家名区域（圆点 + 名字，垂直居中对齐）
        local nameX = cx + cardW * 0.05
        local nameY = cy + cardH/2 - 4

        -- 颜色圆点（与局内头顶颜色一致）
        nvgBeginPath(nvg)
        nvgCircle(nvg, nameX, nameY, 7)
        nvgFillColor(nvg, nvgRGBA(pc[1], pc[2], pc[3], math.floor(255 * t)))
        nvgFill(nvg)

        -- 玩家名（大号 + 使用玩家专属颜色）
        nvgFontSize(nvg, 36)
        nvgFontFace(nvg, "sans")
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(pc[1], pc[2], pc[3], math.floor(255 * t)))
        nvgText(nvg, nameX + 14, nameY, p.config.name, nil)

        -- PLAYER 小标签
        nvgFontSize(nvg, 14)
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(nvg, nvgRGBA(140, 140, 160, math.floor(200 * t)))
        nvgText(nvg, nameX + 14, nameY + 16, "PLAYER", nil)
    end

    -- 绘制右队成员（从右滑入）
    local rightCount = #team2.members
    local rightBaseX = sw * 0.75

    for idx, pi in ipairs(team2.members) do
        local p = players_[pi]
        local slideOffset = (1 - t) * 250 -- 从右侧滑入
        local cy = baseY + (idx - 1) * (cardH + 10)
        local cx = rightBaseX + slideOffset
        local pc = p.config.color -- 玩家专属颜色

        -- 卡片背景（白色圆角卡片 + 柔和阴影）
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - cardW/2 + 3, cy + 3, cardW, cardH - 10, 16)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(20 * t)))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - cardW/2, cy, cardW, cardH - 10, 16)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(230 * t)))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - cardW/2, cy, cardW, cardH - 10, 16)
        nvgStrokeColor(nvg, nvgRGBA(tc2[1], tc2[2], tc2[3], math.floor(200 * t)))
        nvgStrokeWidth(nvg, 2.5)
        nvgStroke(nvg)

        -- 角色立绘
        local skinIdx = p.config.skinIndex or 1
        local skin = skinsRuntime_[skinIdx]
        if skin then
            local breathe = 1.0 + math.sin(teamReveal_.timer * 2.5 + pi * 1.7) * 0.03
            local baseScale = 2.0
            Render.DrawSinglePlayer({
                sx = cx + cardW * 0.22,
                sy = cy + cardH * 0.5,
                color = pc,
                skin = skin,
                facing = -1,
                limbSwing = math.sin(teamReveal_.timer * 2.0 + pi) * 0.1,
                armSwing = -math.sin(teamReveal_.timer * 2.0 + pi) * 0.08,
                inAir = false,
                isMoving = false,
                onGround = true,
                velY = 0,
                name = "",
                scaleX = baseScale * breathe,
                scaleY = baseScale * breathe,
            })
        end

        -- 玩家名区域（名字 + 圆点，垂直居中对齐）
        local nameX = cx - cardW * 0.05
        local nameY = cy + cardH/2 - 4

        -- 颜色圆点（右侧，与局内头顶颜色一致）
        nvgBeginPath(nvg)
        nvgCircle(nvg, nameX, nameY, 7)
        nvgFillColor(nvg, nvgRGBA(pc[1], pc[2], pc[3], math.floor(255 * t)))
        nvgFill(nvg)

        -- 玩家名（大号 + 使用玩家专属颜色）
        nvgFontSize(nvg, 36)
        nvgFontFace(nvg, "sans")
        nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(pc[1], pc[2], pc[3], math.floor(255 * t)))
        nvgText(nvg, nameX - 14, nameY, p.config.name, nil)

        -- PLAYER 小标签
        nvgFontSize(nvg, 14)
        nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgFillColor(nvg, nvgRGBA(140, 140, 160, math.floor(200 * t)))
        nvgText(nvg, nameX - 14, nameY + 16, "PLAYER", nil)
    end

    -- 底部倒计时提示（可爱风格）
    local remaining = math.max(0, teamReveal_.duration - teamReveal_.timer)
    if remaining > 0 then
        nvgFontSize(nvg, 18)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(nvg, nvgRGBA(180, 100, 160, 220))
        nvgText(nvg, sw/2, sh - 24, string.format("%.1f 秒后开始...", remaining), nil)
    end
end

function UpdateTeamReveal(dt)
    teamReveal_.timer = teamReveal_.timer + dt
    if teamReveal_.timer >= teamReveal_.duration then
        -- 分队展示结束，进入横幅
        teamBanner_.timer = 0
        gameState_ = "team_banner"
        print("=== 进入横幅展示 ===")
    end
end

-- ============================================================================
-- 横幅动画（team_banner）
-- ============================================================================
function DrawTeamBanner()
    local nvg = nvg_
    local sw, sh = screenW_, screenH_

    -- 背景（与 team_reveal 一致的粉蓝渐变）
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, sw, sh)
    local bg = nvgLinearGradient(nvg, 0, 0, sw, sh,
        nvgRGBA(200, 230, 255, 255), nvgRGBA(255, 210, 230, 255))
    nvgFillPaint(nvg, bg)
    nvgFill(nvg)

    -- 装饰圆点（与 team_reveal 一致）
    for i = 1, 12 do
        local dx = (sw * ((i * 137) % 100) / 100)
        local dy = (sh * ((i * 73 + 29) % 100) / 100)
        local pulse = 0.6 + 0.4 * math.sin(teamBanner_.timer * 2.0 + i * 0.8)
        local dotR = 4 + (i % 3) * 3
        nvgBeginPath(nvg)
        nvgCircle(nvg, dx, dy, dotR * pulse)
        if i % 2 == 0 then
            nvgFillColor(nvg, nvgRGBA(255, 150, 200, math.floor(80 * pulse)))
        else
            nvgFillColor(nvg, nvgRGBA(100, 200, 255, math.floor(80 * pulse)))
        end
        nvgFill(nvg)
    end

    -- 横幅动画参数
    local t = teamBanner_.timer
    local dur = teamBanner_.duration
    local slideIn = 0.4
    local pauseEnd = dur - 0.5
    local slideOut = 0.5

    -- 计算横幅 X 位置
    local bannerX
    if t < slideIn then
        local p = t / slideIn
        p = 1 - (1 - p) * (1 - p) * (1 - p)
        bannerX = -sw * 0.5 + (sw * 0.5) * p
    elseif t < pauseEnd then
        bannerX = 0
    else
        local p = (t - pauseEnd) / slideOut
        p = p * p * p
        bannerX = sw * 0.5 * p
    end

    -- 横幅本体（白色圆角卡片风格）
    local bannerH = 80
    local bannerY = sh / 2 - bannerH / 2
    local centerX = sw / 2 + bannerX

    -- 横幅阴影
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, centerX - sw * 0.4 + 3, bannerY + 4, sw * 0.8, bannerH, 20)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 25))
    nvgFill(nvg)

    -- 横幅白色背景
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, centerX - sw * 0.4, bannerY, sw * 0.8, bannerH, 20)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 240))
    nvgFill(nvg)

    -- 上下粉色渐变边线
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, centerX - sw * 0.4, bannerY, sw * 0.8, 3, 2)
    local topLine = nvgLinearGradient(nvg, centerX - sw*0.4, bannerY, centerX + sw*0.4, bannerY,
        nvgRGBA(100, 200, 255, 220), nvgRGBA(255, 130, 200, 220))
    nvgFillPaint(nvg, topLine)
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, centerX - sw * 0.4, bannerY + bannerH - 3, sw * 0.8, 3, 2)
    local botLine = nvgLinearGradient(nvg, centerX - sw*0.4, bannerY+bannerH, centerX + sw*0.4, bannerY+bannerH,
        nvgRGBA(255, 130, 200, 220), nvgRGBA(100, 200, 255, 220))
    nvgFillPaint(nvg, botLine)
    nvgFill(nvg)

    -- 横幅文字（粉紫色，加大字号）
    local winScore = GetWinScore()
    local text = "率先达到 " .. winScore .. " 分的队伍获得胜利!"
    nvgFontSize(nvg, 40)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(180, 60, 140, 255))
    nvgText(nvg, centerX, bannerY + bannerH / 2, text, nil)
end

function UpdateTeamBanner(dt)
    teamBanner_.timer = teamBanner_.timer + dt
    if teamBanner_.timer >= teamBanner_.duration then
        -- 横幅结束，进入公告板
        bulletin_.round = 1
        bulletin_.confirmed = {}
        for i = 1, #players_ do
            bulletin_.confirmed[i] = false
        end
        bulletin_.animPhase = "enter"
        bulletin_.animTimer = 0
        gameState_ = "bulletin"

        unlock_.currentGameplayIndex = 1
        CheckUnlockAndPrepareRound()
        print("=== 横幅结束，进入游戏 ===")
    end
end

--- 获取按键显示名称
function GetKeyName(key)
    local names = {
        [KEY_W] = "W", [KEY_S] = "S", [KEY_X] = "X", [KEY_I] = "I",
        [KEY_Q] = "Q", [KEY_A] = "A", [KEY_Z] = "Z", [KEY_U] = "U",
        [KEY_E] = "E", [KEY_D] = "D", [KEY_C] = "C", [KEY_O] = "O",
        [KEY_J] = "J", [KEY_K] = "K", [KEY_L] = "L",
        [KEY_N] = "N", [KEY_M] = "M", [KEY_COMMA] = ",",
        [KEY_F] = "F", [KEY_G] = "G", [KEY_H] = "H",
        [KEY_R] = "R", [KEY_T] = "T", [KEY_Y] = "Y",
    }
    return names[key] or "?"
end

-- ============================================================================
-- 清理
-- ============================================================================
function Stop()
    UI.Shutdown()
    if nvg_ then nvgDelete(nvg_) end
end
