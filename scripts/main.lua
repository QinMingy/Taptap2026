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
            name = "mgz",
            headImage = "image/Charactor/mgz/head_mgz.png",
            torsoImage = "image/Charactor/mgz/body_mgz.png",
            armColor = "#FFFFFFFF",
            handColor = "#F5D2AAFF",
            legColor = "#3A4A5CFF",
            shoeColor = "#2A3A4CFF",
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
    xButtonRects = {},
    -- 新选人界面：已落地玩家物理对象
    lobbyPlayers = {},  -- [slotIndex] = { node, body, onGround, groundContacts, facing, ... }
    -- 固定拍照区域（右侧）
    photoZone = { x = 5.5, y = 0.5, width = CONFIG.PhotoWidth, height = CONFIG.PhotoHeight },
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
    G.getUnlockValue = function() return Gameplay.GetUnlockValue(teams_) end
    G.nextRoundPrepared = bulletin_.nextRoundPrepared or false
    G.globalTime = globalTime_
end

-- ============================================================================
-- 解锁系统逻辑（对接 Gameplay 模块）
-- ============================================================================

function GetWinScore()
    local teamSize = math.max(1, #players_ // 2)
    return teamSize * 20
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
        selectedGameplay = Gameplay.SelectGameplayByWeight(unlockedGameplays)
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
    jumpSound_ = cache:GetResource("Sound", "audio/sfx/jump.ogg")
    landSound_ = cache:GetResource("Sound", "audio/sfx/land.ogg")
    readyConfirmSound_ = cache:GetResource("Sound", "audio/sfx/ready_confirm.ogg")

    CreateScene()

    -- 播放背景音乐（需在 CreateScene 之后）
    local bgm = cache:GetResource("Sound", "audio/music_1780146499986.ogg")
    if bgm then
        bgm.looped = true
        bgmNode_ = scene_:CreateChild("BGM")
        local bgmSource = bgmNode_:CreateComponent("SoundSource")
        bgmSource.soundType = SOUND_MUSIC
        bgmSource.gain = 0.5
        bgmSource:Play(bgm)
        bgmSource.looped = true
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
    Editors.CreateEditorMenu()

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(nvg_, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleBeginContact")
    SubscribeToEvent("PhysicsEndContact2D", "HandleEndContact")
    SubscribeToEvent("PhysicsUpdateContact2D", "HandleUpdateContact")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")

    -- 显示主界面（标题屏幕）
    gameState_ = "title"
    local titleRoot = TitleScreen.Create(function()
        -- 主界面结束后进入大厅
        gameState_ = "lobby"
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
function CreatePlayers(activeIndices)
    players_ = {}
    local indicesToCreate = activeIndices or {}
    if #indicesToCreate == 0 then
        for i = 1, #PLAYERS do indicesToCreate[i] = i end
    end

    for seq, pi in ipairs(indicesToCreate) do
        local pdata = PLAYERS[pi]
        pdata.skinIndex = lobby_.slots[pi].skinIndex

        local node = scene_:CreateChild("Player" .. pi)
        node:SetPosition2D(pdata.spawnX, CONFIG.GroundY + 2)

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

        players_[seq] = {
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
        }
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

    -- 可爱风格颜色（白底+柔和团队色边框）
    local cuteBg1 = {255, 245, 250, 220}       -- 浅粉白背景（左队）
    local cuteBg2 = {245, 250, 255, 220}       -- 浅蓝白背景（右队）
    local cuteBorder1 = {t1c[1], t1c[2], t1c[3], 180}  -- 队伍色边框
    local cuteBorder2 = {t2c[1], t2c[2], t2c[3], 180}

    -- 构建左队成员行
    local t1MemberRows = {}
    for _, pi in ipairs(teams_[1].members) do
        local pdata = PLAYERS[pi]
        table.insert(t1MemberRows, UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6,
            children = {
                -- 圆形标识
                UI.Panel { width = 10, height = 10, borderRadius = 5, backgroundColor = pdata.color },
                UI.Label { text = pdata.name, fontSize = 13, fontColor = {80, 60, 100, 255} },
                UI.Label { id = "score" .. pi, text = "0", fontSize = 15, fontColor = {t1c[1], t1c[2], t1c[3], 255}, fontWeight = "bold" },
            }
        })
    end

    -- 构建右队成员行
    local t2MemberRows = {}
    for _, pi in ipairs(teams_[2].members) do
        local pdata = PLAYERS[pi]
        table.insert(t2MemberRows, UI.Panel {
            flexDirection = "row", alignItems = "center", justifyContent = "flex-end", gap = 6,
            children = {
                UI.Label { id = "score" .. pi, text = "0", fontSize = 15, fontColor = {t2c[1], t2c[2], t2c[3], 255}, fontWeight = "bold" },
                UI.Label { text = pdata.name, fontSize = 13, fontColor = {100, 60, 80, 255} },
                UI.Panel { width = 10, height = 10, borderRadius = 5, backgroundColor = pdata.color },
            }
        })
    end

    -- 左队面板（圆角白底 + 柔和边框）
    local t1Panel = UI.Panel {
        id = "team1Panel",
        position = "absolute",
        top = 10, left = 10,
        padding = 10, gap = 5,
        backgroundColor = cuteBg1,
        borderWidth = 2.5, borderColor = cuteBorder1, borderRadius = 12,
        pointerEvents = "none",
        children = {
            -- 队伍标题行
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                marginBottom = 4,
                children = {
                    UI.Panel { width = 8, height = 8, borderRadius = 4, backgroundColor = t1c },
                    UI.Label {
                        id = "team1Score",
                        text = teams_[1].name .. " 0/" .. winScore,
                        fontSize = 16,
                        fontColor = {t1c[1], t1c[2], t1c[3], 255},
                        fontWeight = "bold",
                    },
                }
            },
            table.unpack(t1MemberRows),
        }
    }

    -- 右队面板（圆角白底 + 柔和边框）
    local t2Panel = UI.Panel {
        id = "team2Panel",
        position = "absolute",
        top = 10, right = 10,
        padding = 10, gap = 5,
        alignItems = "flex-end",
        backgroundColor = cuteBg2,
        borderWidth = 2.5, borderColor = cuteBorder2, borderRadius = 12,
        pointerEvents = "none",
        children = {
            -- 队伍标题行
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                marginBottom = 4,
                children = {
                    UI.Label {
                        id = "team2Score",
                        text = teams_[2].name .. " 0/" .. winScore,
                        fontSize = 16,
                        fontColor = {t2c[1], t2c[2], t2c[3], 255},
                        fontWeight = "bold",
                    },
                    UI.Panel { width = 8, height = 8, borderRadius = 4, backgroundColor = t2c },
                }
            },
            table.unpack(t2MemberRows),
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

--- 查找 lobby 玩家（返回 slotIndex 或 nil）
local function GetLobbyPlayerIndex(node)
    for idx, lp in pairs(lobby_.lobbyPlayers) do
        if lp.node == node then return idx end
    end
    return nil
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
    else
        -- 检查 lobby 玩家
        local li = GetLobbyPlayerIndex(nodeA) or GetLobbyPlayerIndex(nodeB)
        if li then
            local lp = lobby_.lobbyPlayers[li]
            local otherNode = GetLobbyPlayerIndex(nodeA) and nodeB or nodeA
            if IsGround(otherNode) then
                lp.groundContacts = lp.groundContacts + 1
                lp.onGround = true
            end
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
    else
        -- 检查 lobby 玩家
        local li = GetLobbyPlayerIndex(nodeA) or GetLobbyPlayerIndex(nodeB)
        if li then
            local lp = lobby_.lobbyPlayers[li]
            local otherNode = GetLobbyPlayerIndex(nodeA) and nodeB or nodeA
            if IsGround(otherNode) then
                lp.groundContacts = lp.groundContacts - 1
                if lp.groundContacts <= 0 then
                    lp.groundContacts = 0
                    lp.onGround = false
                end
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
    local playerBottomY = playerPos.y - (capsuleHeight_ * playerScale_) / 2

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

    -- 金币动画 & 粒子更新（所有状态都需要）
    Gameplay.UpdateCoinTime(dt)

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
        end
    end

    -- 公告板确认
    if gameState_ == "bulletin" and bulletin_.animPhase == "stay" then
        UpdateBulletinConfirm()
    end

    UpdateGameState(dt)
end

-- ============================================================================
-- 大厅逻辑
-- ============================================================================

--- 创建一个大厅玩家物理体（确认后落下）
function CreateLobbyPlayer(slotIndex)
    local pdata = PLAYERS[slotIndex]
    pdata.skinIndex = lobby_.slots[slotIndex].skinIndex

    -- 计算落下起始位置：从槽位屏幕位置映射到世界坐标
    -- 槽位在左上角，4列2行
    local cols = 4
    local slotW = screenW_ * 0.065
    local slotH = screenH_ * 0.13
    local gap = 8
    local panelPad = 12
    local row = (slotIndex <= 4) and 0 or 1
    local col = ((slotIndex - 1) % 4)
    local sx = panelPad + col * (slotW + gap) + slotW / 2
    local sy = panelPad + row * (slotH + gap) + slotH / 2

    -- 屏幕坐标 → 物理坐标
    local px, py = Render.ScreenToPhys(sx, sy)

    local node = scene_:CreateChild("LobbyPlayer" .. slotIndex)
    node:SetPosition2D(px, py)

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

    lobby_.lobbyPlayers[slotIndex] = {
        node = node,
        body = body,
        onGround = false,
        groundContacts = 0,
        facing = 1,
        config = pdata,
        originalIndex = slotIndex,
        animTime = 0,
        isMoving = false,
        velY = 0,
        jumping = false,
        scale = { x = 1.0, y = 1.0 },
        scaleTween = nil,
        wasOnGround = true,
        runDustTimer = 0,
        score = 0,
    }
    print(PLAYERS[slotIndex].name .. " 确认并落下")
end

--- 移除一个大厅玩家（退出）
function RemoveLobbyPlayer(slotIndex)
    local lp = lobby_.lobbyPlayers[slotIndex]
    if lp and lp.node then
        lp.node:Remove()
    end
    lobby_.lobbyPlayers[slotIndex] = nil
end

--- 检查大厅玩家是否在拍照区域内
function IsLobbyPlayerInZone(lp)
    local pos = lp.node.position2D
    local zone = lobby_.photoZone
    local halfW = zone.width / 2
    local halfH = zone.height / 2
    return pos.x >= zone.x - halfW and pos.x <= zone.x + halfW
       and pos.y >= zone.y - halfH and pos.y <= zone.y + halfH
end

--- 更新大厅玩家移动（同 UpdatePlayers 逻辑）
function UpdateLobbyPlayerMovement(lp, dt)
    local keys = lp.config.keys
    local vel = lp.body.linearVelocity
    local desiredVelX = 0

    if input:GetKeyDown(keys.left) then
        desiredVelX = -CONFIG.PlayerSpeed
        lp.facing = -1
    elseif input:GetKeyDown(keys.right) then
        desiredVelX = CONFIG.PlayerSpeed
        lp.facing = 1
    end

    lp.body.linearVelocity = Vector2(desiredVelX, vel.y)

    -- 跳跃
    if lp.onGround and input:GetKeyPress(keys.jump) then
        lp.body.linearVelocity = Vector2(desiredVelX, CONFIG.PlayerJumpSpeed)
        lp.body.awake = true
        lp.jumping = true
        lp.onGround = false
        lp.groundContacts = 0
        if jumpSound_ then
            local sfxNode = scene_:CreateChild("JumpSFX")
            local sfxSource = sfxNode:CreateComponent("SoundSource")
            sfxSource:Play(jumpSound_)
            sfxSource.autoRemoveMode = REMOVE_NODE
        end
        lp.scale.x = 1.0
        lp.scale.y = 1.0
        lp.scaleTween = tween.new(0.15, lp.scale, { x = 0.8, y = 1.3 }, "outQuad")
        local pos = lp.node.position2D
        local footY = pos.y - (capsuleHeight_ * playerScale_ / 2)
        Render.SpawnJumpDust(pos.x, footY)
    elseif lp.jumping then
        if not input:GetKeyDown(keys.jump) then
            local vy = lp.body.linearVelocity.y
            if vy > 0 then
                lp.body.linearVelocity = Vector2(lp.body.linearVelocity.x, vy * CONFIG.JumpCutMultiplier)
            end
            lp.jumping = false
        elseif lp.body.linearVelocity.y <= 0 then
            lp.jumping = false
        end
    end

    -- 落地检测
    if lp.onGround and not lp.wasOnGround then
        if landSound_ then
            local sfxNode = scene_:CreateChild("LandSFX")
            local sfxSource = sfxNode:CreateComponent("SoundSource")
            sfxSource:Play(landSound_)
            sfxSource.autoRemoveMode = REMOVE_NODE
        end
        lp.scale.x = 1.0
        lp.scale.y = 1.0
        lp.scaleTween = tween.new(0.2, lp.scale, { x = 1.25, y = 0.75 }, "outQuad")
        lp._squashRecover = true
    end
    lp.wasOnGround = lp.onGround

    -- 缩放动画
    if not lp.onGround and not lp.scaleTween then
        local vy = math.abs(lp.body.linearVelocity.y)
        local maxVy = math.abs(CONFIG.PlayerJumpSpeed)
        local t = math.min(vy / maxVy, 1.0)
        lp.scale.x = 1.0 - t * 0.2
        lp.scale.y = 1.0 + t * 0.3
    elseif lp.scaleTween then
        local done = lp.scaleTween:update(dt)
        if done then
            if lp._squashRecover then
                lp._squashRecover = false
                lp.scaleTween = tween.new(0.15, lp.scale, { x = 1.0, y = 1.0 }, "outBack")
            else
                lp.scaleTween = nil
                lp.scale.x = 1.0
                lp.scale.y = 1.0
            end
        end
    elseif lp.onGround and not lp.scaleTween then
        lp.scale.x = 1.0
        lp.scale.y = 1.0
    end

    lp.isMoving = math.abs(desiredVelX) > 0.1
    lp.velY = lp.body.linearVelocity.y
    if lp.isMoving then
        lp.animTime = lp.animTime + dt * 10
        if lp.onGround then
            lp.runDustTimer = lp.runDustTimer + dt
            if lp.runDustTimer >= 0.12 then
                lp.runDustTimer = 0
                local pos = lp.node.position2D
                local footY = pos.y - (capsuleHeight_ * playerScale_ / 2)
                Render.SpawnRunDust(pos.x, footY, lp.facing)
            end
        else
            lp.runDustTimer = 0
        end
    else
        lp.animTime = 0
        lp.runDustTimer = 0
    end
end

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

    -- 按跳跃键加入/准备
    for i, slot in ipairs(lobby_.slots) do
        local keys = PLAYERS[i].keys
        if input:GetKeyPress(keys.jump) then
            if not slot.joined then
                -- 加入游戏
                slot.joined = true
                print(PLAYERS[i].name .. " 加入游戏")
            elseif not slot.ready then
                -- 确认准备：创建物理体并落下
                slot.ready = true
                CreateLobbyPlayer(i)
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

    -- 更新所有已落地的大厅玩家移动
    for slotIdx, lp in pairs(lobby_.lobbyPlayers) do
        UpdateLobbyPlayerMovement(lp, dt)
    end

    -- 检查拍照区域逻辑
    local joinedCount = 0
    local readyCount = 0
    local allInZone = true

    for i, slot in ipairs(lobby_.slots) do
        if slot.joined then
            joinedCount = joinedCount + 1
            if slot.ready then
                readyCount = readyCount + 1
                local lp = lobby_.lobbyPlayers[i]
                if lp then
                    if not IsLobbyPlayerInZone(lp) then
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

    -- 记录快照（用于拍立得内渲染）
    lobby_.photoSnapshot = {}
    for i, slot in ipairs(lobby_.slots) do
        if slot.ready then
            local lp = lobby_.lobbyPlayers[i]
            if lp then
                local pos = lp.node.position2D
                table.insert(lobby_.photoSnapshot, {
                    playerIndex = i,
                    px = pos.x,
                    py = pos.y,
                    facing = lp.facing,
                    skinIndex = slot.skinIndex,
                    animTime = lp.animTime,
                    isMoving = lp.isMoving,
                    onGround = lp.onGround,
                    velY = lp.velY,
                    scaleX = lp.scale.x,
                    scaleY = lp.scale.y,
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
    -- 收集已加入的玩家索引
    local activeIndices = {}
    for i, slot in ipairs(lobby_.slots) do
        if slot.joined then
            table.insert(activeIndices, i)
        end
    end

    -- 清除大厅物理体
    for idx, lp in pairs(lobby_.lobbyPlayers) do
        if lp.node then lp.node:Remove() end
    end
    lobby_.lobbyPlayers = {}

    -- 重置大厅子阶段
    lobby_.phase = "select"
    lobby_.countdownActive = false
    lobby_.countdown = 5.0

    CreatePlayers(activeIndices)
    AssignTeams()
    CreateTeamUI()

    -- 进入分队展示界面
    teamReveal_.timer = 0
    gameState_ = "team_reveal"

    print("=== 进入分队展示 ===")
end

-- ============================================================================
-- 鼠标点击处理（大厅 X 按钮取消）
-- ============================================================================
function HandleMouseDown(eventType, eventData)
    if gameState_ ~= "lobby" then return end

    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end

    local mx = eventData["X"]:GetInt()
    local my = eventData["Y"]:GetInt()

    -- DPR 转换：鼠标坐标是物理像素，NanoVG 绘图使用逻辑像素
    local dpr = graphics:GetDPR()
    mx = mx / dpr
    my = my / dpr

    -- 碰撞检测 X 按钮
    for i, rect in pairs(lobby_.xButtonRects) do
        if mx >= rect.x and mx <= rect.x + rect.w and
           my >= rect.y and my <= rect.y + rect.h then
            -- 点击了玩家 i 的 X 按钮
            local slot = lobby_.slots[i]
            if slot.joined then
                if slot.ready then
                    -- 已准备（已落下）→ 取消准备，移除物理体
                    slot.ready = false
                    RemoveLobbyPlayer(i)
                    print(PLAYERS[i].name .. " 取消准备（回到选皮肤）")
                else
                    -- 已加入但未准备 → 退出
                    slot.joined = false
                    print(PLAYERS[i].name .. " 退出大厅")
                end
            end
            break
        end
    end
end

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
        }
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
            local pos = p.node.position2D

            -- 胶囊体与矩形区域相交检测
            local capR = CONFIG.PlayerRadius * playerScale_
            local capH = capsuleHeight_ * playerScale_ * (CONFIG.PlayerRadius / capsuleRadius_)
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

            if teamIdx and teams_[teamIdx].score >= GetWinScore() then
                gameOver_ = true
                winner_ = teams_[teamIdx].name
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
    -- 清理 lobby 物理体
    for idx, lp in pairs(lobby_.lobbyPlayers) do
        if lp.node then lp.node:Remove() end
    end
    lobby_.lobbyPlayers = {}
    lobby_.xButtonRects = {}
    lobby_.phase = "select"
    lobby_.countdownActive = false
    lobby_.countdown = 5.0
    lobby_.warningFlash = 0
    lobby_.photoSnapshot = {}
    gameState_ = "lobby"
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

    -- === 3. 渲染已落地的 lobby 玩家 ===
    local ppu = Render.GetPixelsPerUnit()
    for slotIdx, lp in pairs(lobby_.lobbyPlayers) do
        local pos = lp.node.position2D
        local playerSX, playerSY = Render.PhysToScreen(pos.x, pos.y)
        local slot = lobby_.slots[slotIdx]
        local skin = skinsRuntime_[slot.skinIndex]
        local pdata = PLAYERS[slotIdx]
        local c = pdata.color

        local limbSwing = 0
        local armSwing = 0
        if lp.isMoving and lp.onGround then
            limbSwing = math.sin(lp.animTime * 8) * 0.5
            armSwing = -math.sin(lp.animTime * 8) * 0.35
        end

        Render.DrawSinglePlayer({
            sx = playerSX,
            sy = playerSY,
            color = c,
            skin = skin,
            facing = lp.facing,
            limbSwing = limbSwing,
            armSwing = armSwing,
            inAir = not lp.onGround,
            isMoving = lp.isMoving,
            onGround = lp.onGround,
            velY = lp.velY,
            name = pdata.name,
            scaleX = lp.scale.x,
            scaleY = lp.scale.y,
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

    lobby_.xButtonRects = {}  -- 每帧重置碰撞矩形

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

            -- X 按钮（右上角，圆形粉色）
            local btnSize = 14
            local bx = sx + slotW - btnSize - 2
            local by = sy + 2
            nvgBeginPath(nvg)
            nvgCircle(nvg, bx + btnSize / 2, by + btnSize / 2, btnSize / 2)
            nvgFillColor(nvg, nvgRGBA(240, 100, 130, 200))
            nvgFill(nvg)
            nvgFontSize(nvg, 10)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 240))
            nvgText(nvg, bx + btnSize / 2, by + btnSize / 2, "✕", nil)
            lobby_.xButtonRects[i] = { x = bx, y = by, w = btnSize, h = btnSize }
        else
            -- 未加入：显示按键提示（柔和紫色）
            nvgFontSize(nvg, 9)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(160, 130, 180, 180))
            nvgText(nvg, sx + slotW / 2, sy + slotH / 2, GetKeyName(pdata.keys.jump), nil)
        end
    end

    -- === 5. 中下方提示文字 ===
    nvgFontSize(nvg, 18)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local joinedCount = 0
    local readyCount = 0
    for _, slot in ipairs(lobby_.slots) do
        if slot.joined then
            joinedCount = joinedCount + 1
            if slot.ready then readyCount = readyCount + 1 end
        end
    end

    if lobby_.countdownActive then
        -- 倒数计时（大字居中，粉色）
        local cdSec = math.ceil(lobby_.countdown)
        nvgFontSize(nvg, 72)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local pulse = 1.0 + math.sin(lobby_.countdown * math.pi * 2) * 0.1
        nvgFillColor(nvg, nvgRGBA(240, 80, 130, 250))
        nvgText(nvg, sw / 2, sh / 2, tostring(cdSec), nil)

        nvgFontSize(nvg, 16)
        nvgFillColor(nvg, nvgRGBA(100, 200, 220, 230))
        nvgText(nvg, sw / 2, sh / 2 + 50, "全员就位！即将拍照...", nil)
    else
        -- 提示信息（柔和配色）
        local hintY = sh - 40
        if joinedCount < 2 then
            nvgFillColor(nvg, nvgRGBA(120, 100, 160, 200))
            nvgText(nvg, sw / 2, hintY, "按跳跃键加入 → 选皮肤(左右键) → 再按跳跃确认落下", nil)
        elseif joinedCount ~= readyCount then
            nvgFillColor(nvg, nvgRGBA(240, 160, 60, 220))
            nvgText(nvg, sw / 2, hintY, "等待所有人确认...", nil)
        elseif joinedCount % 2 ~= 0 then
            -- 奇数人警告（闪烁粉红）
            local flashAlpha = math.floor(160 + 80 * math.sin(lobby_.warningFlash * 6))
            nvgFillColor(nvg, nvgRGBA(240, 80, 100, flashAlpha))
            nvgText(nvg, sw / 2, hintY, "玩家人数需要为双数!", nil)
        else
            nvgFillColor(nvg, nvgRGBA(80, 200, 160, 220))
            nvgText(nvg, sw / 2, hintY, "全员进入拍照区域开始倒数!", nil)
        end
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
        local zone = lobby_.photoZone
        local zoneAspect = zone.width / zone.height
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
        local zoneCenterSX, zoneCenterSY = Render.PhysToScreen(zone.x, zone.y)
        local zoneScreenW = zone.width * ppu
        local zoneScreenH = zone.height * ppu
        local scaleX = photoW / zoneScreenW
        local scaleY = photoH / zoneScreenH
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
-- 分队展示界面（team_reveal）
-- ============================================================================
function DrawTeamReveal()
    local nvg = nvg_
    local sw, sh = screenW_, screenH_

    -- 背景（深色渐变）
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, sw, sh)
    local bg = nvgLinearGradient(nvg, 0, 0, 0, sh,
        nvgRGBA(15, 20, 40, 255), nvgRGBA(5, 8, 20, 255))
    nvgFillPaint(nvg, bg)
    nvgFill(nvg)

    -- 动画进度
    local t = math.min(teamReveal_.timer / 0.8, 1.0) -- 入场动画0.8秒

    -- VS 文字
    nvgFontSize(nvg, 60)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local vsAlpha = math.floor(math.min(teamReveal_.timer / 0.5, 1.0) * 255)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, vsAlpha))
    nvgText(nvg, sw/2, sh/2, "VS", nil)

    -- 闪光分隔线
    nvgBeginPath(nvg)
    nvgRect(nvg, sw/2 - 2, sh * 0.15, 4, sh * 0.7)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(vsAlpha * 0.3)))
    nvgFill(nvg)

    -- 左队（蓝队）
    local team1 = teams_[1]
    local tc1 = team1.color
    -- 右队（红队）
    local team2 = teams_[2]
    local tc2 = team2.color

    -- 队名
    nvgFontSize(nvg, 28)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(tc1[1], tc1[2], tc1[3], vsAlpha))
    nvgText(nvg, sw * 0.25, sh * 0.08, team1.name, nil)

    nvgFillColor(nvg, nvgRGBA(tc2[1], tc2[2], tc2[3], vsAlpha))
    nvgText(nvg, sw * 0.75, sh * 0.08, team2.name, nil)

    -- 绘制左队成员（从左滑入）
    local leftCount = #team1.members
    local cardH = math.min(140, (sh * 0.7) / math.max(leftCount, 1))
    local cardW = sw * 0.35
    local leftBaseX = sw * 0.25
    local baseY = sh * 0.18

    for idx, pi in ipairs(team1.members) do
        local p = players_[pi]
        local slideOffset = (1 - t) * (-200) -- 从左侧滑入
        local cy = baseY + (idx - 1) * (cardH + 8)
        local cx = leftBaseX + slideOffset

        -- 卡片背景
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - cardW/2, cy, cardW, cardH - 8, 10)
        nvgFillColor(nvg, nvgRGBA(tc1[1], tc1[2], tc1[3], math.floor(40 * t)))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - cardW/2, cy, cardW, cardH - 8, 10)
        nvgStrokeColor(nvg, nvgRGBA(tc1[1], tc1[2], tc1[3], math.floor(180 * t)))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)

        -- 角色立绘（通过 skinIndex 获取皮肤）
        local skinIdx = p.config.skinIndex or 1
        local skin = skinsRuntime_[skinIdx]
        if skin then
            -- 呼吸动画：轻微缩放脉动
            local breathe = 1.0 + math.sin(teamReveal_.timer * 2.5 + pi * 1.3) * 0.03
            local baseScale = 1.8
            Render.DrawSinglePlayer({
                sx = cx - cardW * 0.2,
                sy = cy + cardH * 0.5,
                color = p.config.color,
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

        -- 玩家名
        nvgFontSize(nvg, 18)
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(255 * t)))
        nvgText(nvg, cx + cardW * 0.05, cy + cardH/2 - 4, p.config.name, nil)
    end

    -- 绘制右队成员（从右滑入）
    local rightCount = #team2.members
    local rightBaseX = sw * 0.75

    for idx, pi in ipairs(team2.members) do
        local p = players_[pi]
        local slideOffset = (1 - t) * 200 -- 从右侧滑入
        local cy = baseY + (idx - 1) * (cardH + 8)
        local cx = rightBaseX + slideOffset

        -- 卡片背景
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - cardW/2, cy, cardW, cardH - 8, 10)
        nvgFillColor(nvg, nvgRGBA(tc2[1], tc2[2], tc2[3], math.floor(40 * t)))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - cardW/2, cy, cardW, cardH - 8, 10)
        nvgStrokeColor(nvg, nvgRGBA(tc2[1], tc2[2], tc2[3], math.floor(180 * t)))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)

        -- 角色立绘（通过 skinIndex 获取皮肤）
        local skinIdx = p.config.skinIndex or 1
        local skin = skinsRuntime_[skinIdx]
        if skin then
            -- 呼吸动画：轻微缩放脉动
            local breathe = 1.0 + math.sin(teamReveal_.timer * 2.5 + pi * 1.7) * 0.03
            local baseScale = 1.8
            Render.DrawSinglePlayer({
                sx = cx + cardW * 0.2,
                sy = cy + cardH * 0.5,
                color = p.config.color,
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

        -- 玩家名
        nvgFontSize(nvg, 18)
        nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(255 * t)))
        nvgText(nvg, cx - cardW * 0.05, cy + cardH/2 - 4, p.config.name, nil)
    end

    -- 底部倒计时提示
    local remaining = math.max(0, teamReveal_.duration - teamReveal_.timer)
    if remaining > 0 then
        nvgFontSize(nvg, 16)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(nvg, nvgRGBA(200, 200, 200, 180))
        nvgText(nvg, sw/2, sh - 20, string.format("%.1f 秒后开始...", remaining), nil)
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

    -- 背景（与 team_reveal 一致的深色）
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, sw, sh)
    local bg = nvgLinearGradient(nvg, 0, 0, 0, sh,
        nvgRGBA(15, 20, 40, 255), nvgRGBA(5, 8, 20, 255))
    nvgFillPaint(nvg, bg)
    nvgFill(nvg)

    -- 横幅动画参数
    local t = teamBanner_.timer
    local dur = teamBanner_.duration
    local slideIn = 0.4    -- 飘入时间
    local pauseEnd = dur - 0.5  -- 飘出开始时间
    local slideOut = 0.5   -- 飘出时间

    -- 计算横幅 X 位置
    local bannerX
    if t < slideIn then
        -- 从左侧飘入中间
        local p = t / slideIn
        -- 缓入效果 (easeOutCubic)
        p = 1 - (1 - p) * (1 - p) * (1 - p)
        bannerX = -sw * 0.5 + (sw * 0.5) * p  -- 从 -sw/2 到 0（中心偏移）
    elseif t < pauseEnd then
        -- 停在中间
        bannerX = 0
    else
        -- 飘出到右侧
        local p = (t - pauseEnd) / slideOut
        -- 缓出效果 (easeInCubic)
        p = p * p * p
        bannerX = sw * 0.5 * p  -- 从 0 到 sw/2
    end

    -- 横幅本体
    local bannerH = 70
    local bannerY = sh / 2 - bannerH / 2
    local centerX = sw / 2 + bannerX

    -- 横幅背景条
    nvgBeginPath(nvg)
    nvgRect(nvg, centerX - sw * 0.45, bannerY, sw * 0.9, bannerH)
    nvgFillColor(nvg, nvgRGBA(20, 20, 40, 230))
    nvgFill(nvg)

    -- 上下金色边线
    nvgBeginPath(nvg)
    nvgRect(nvg, centerX - sw * 0.45, bannerY, sw * 0.9, 3)
    nvgFillColor(nvg, nvgRGBA(255, 200, 60, 220))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRect(nvg, centerX - sw * 0.45, bannerY + bannerH - 3, sw * 0.9, 3)
    nvgFillColor(nvg, nvgRGBA(255, 200, 60, 220))
    nvgFill(nvg)

    -- 横幅文字
    local winScore = GetWinScore()
    local text = "率先达到 " .. winScore .. " 分的队伍获得胜利"
    nvgFontSize(nvg, 28)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 220, 80, 255))
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
