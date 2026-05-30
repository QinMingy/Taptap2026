-- ============================================================================
-- 三人抓拍游戏 (Photo Rush)
-- 玩法: 3个玩家在同一地图上，随机刷新拍照区域，倒计时结束时
--       在区域内的玩家获得分数
-- 操作:
--   玩家1 (红色): Q=左, W=跳跃, E=右
--   玩家2 (绿色): A=左, S=跳跃, D=右
--   玩家3 (蓝色): Z=左, X=跳跃, C=右
-- ============================================================================

require "LuaScripts/Utilities/Sample"
local UI = require("urhox-libs/UI")

-- ============================================================================
-- 游戏配置
-- ============================================================================
local CONFIG = {
    Title = "Photo Rush - 三人抓拍",
    Gravity = 20.0,
    PixelPerUnit = 50,

    -- 地图
    MapWidth = 20,        -- 地图宽度(物理单位)
    MapHeight = 12,       -- 地图高度
    GroundY = -5.0,       -- 地面Y

    -- 玩家
    PlayerRadius = 0.4,
    PlayerSpeed = 6.0,
    PlayerJumpSpeed = 11.0,

    -- 拍照区域
    PhotoWidth = 4.0,       -- 拍照区域宽度
    PhotoHeight = 3.0,      -- 拍照区域高度
    CountdownTime = 5.0,    -- 倒计时秒数
    IntervalTime = 3.0,     -- 两次拍照间隔

    -- 分数
    ScorePerPhoto = 1,      -- 每次拍照得分
    WinScore = 5,           -- 胜利所需分数
}

-- 玩家数据定义
local PLAYERS = {
    {
        name = "P1",
        color = {220, 60, 60, 255},       -- 红色
        keys = {left = KEY_Q, jump = KEY_W, right = KEY_E},
        spawnX = -4,
    },
    {
        name = "P2",
        color = {60, 200, 60, 255},       -- 绿色
        keys = {left = KEY_A, jump = KEY_S, right = KEY_D},
        spawnX = 0,
    },
    {
        name = "P3",
        color = {60, 100, 220, 255},      -- 蓝色
        keys = {left = KEY_Z, jump = KEY_X, right = KEY_C},
        spawnX = 4,
    },
}

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
local players_ = {}  -- {node, body, onGround, groundContacts, score, facing, animTime, isMoving, velY}

-- 拍照区域状态
local photoZone_ = {
    active = false,
    x = 0,
    y = 0,
    width = CONFIG.PhotoWidth,
    height = CONFIG.PhotoHeight,
}

-- 游戏状态
local gameState_ = "waiting"  -- waiting, countdown, flash, showPhoto
local countdown_ = 0
local intervalTimer_ = 2.0    -- 初始等待时间
local flashTimer_ = 0         -- 拍照闪光效果
local showPhotoTimer_ = 0     -- 展示照片计时
local roundResult_ = {}       -- 本轮结果(入镜玩家索引)
local photoSnapshot_ = {}     -- 拍照瞬间玩家位置快照
local gameOver_ = false
local winner_ = ""

-- 平台数据
local platforms_ = {}

-- 屏幕尺寸
local screenW_ = 1280
local screenH_ = 720

-- 音效
local shutterSound_ = nil

-- 相机状态（用于 showPhoto 推进/恢复）
local cameraNormalPos_ = Vector3(0, 0, -10)
local cameraNormalOrtho_ = CONFIG.MapHeight
local cameraZoomed_ = false

-- ============================================================================
-- 入口
-- ============================================================================
function Start()
    SampleStart()
    graphics.windowTitle = CONFIG.Title

    nvg_ = nvgCreate(1)
    nvgCreateFont(nvg_, "sans", "Fonts/MiSans-Regular.ttf")

    -- 加载快门音效
    shutterSound_ = cache:GetResource("Sound", "audio/sfx/shutter.ogg")

    CreateScene()
    CreateWorld()
    CreatePlayers()
    CreateUI()

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(nvg_, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleBeginContact")
    SubscribeToEvent("PhysicsEndContact2D", "HandleEndContact")

    print("=== Photo Rush 三人抓拍游戏启动 ===")
    print("P1(红): Q左 W跳 E右 | P2(绿): A左 S跳 D右 | P3(蓝): Z左 X跳 C右")
end

function Stop()
    UI.Shutdown()
    if nvg_ then nvgDelete(nvg_) end
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
    camera.orthoSize = screenH_ / CONFIG.PixelPerUnit  -- 保持 PPU=50
    cameraNode_.position = Vector3(0, 0, -10)

    renderer:SetViewport(0, Viewport:new(scene_, camera))
end

-- ============================================================================
-- 创建世界(地面+平台)
-- ============================================================================
function CreateWorld()
    -- 地面
    local groundNode = scene_:CreateChild("Ground")
    groundNode:SetPosition2D(0, CONFIG.GroundY)
    local groundBody = groundNode:CreateComponent("RigidBody2D")
    groundBody.bodyType = BT_STATIC
    local groundShape = groundNode:CreateComponent("CollisionBox2D")
    groundShape:SetSize(CONFIG.MapWidth + 4, 1)
    groundShape.friction = 0.3
    groundShape.restitution = 0.0
    groundShape.categoryBits = 1
    table.insert(platforms_, {x=0, y=CONFIG.GroundY, width=CONFIG.MapWidth+4, height=1})

    -- 平台
    local platformData = {
        {x = -6, y = -2.5, width = 3, height = 0.4},
        {x = -2, y = -1.0, width = 2.5, height = 0.4},
        {x = 3,  y = -2.0, width = 3, height = 0.4},
        {x = 7,  y = -0.5, width = 2.5, height = 0.4},
        {x = 0,  y = 1.0,  width = 3, height = 0.4},
        {x = -5, y = 0.5,  width = 2, height = 0.4},
        {x = 5,  y = 2.0,  width = 2.5, height = 0.4},
    }

    for _, data in ipairs(platformData) do
        local node = scene_:CreateChild("Platform")
        node:SetPosition2D(data.x, data.y)
        local body = node:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = node:CreateComponent("CollisionBox2D")
        shape:SetSize(data.width, data.height)
        shape.friction = 0.3
        shape.restitution = 0.0
        shape.categoryBits = 1
        table.insert(platforms_, data)
    end

    -- 左右墙壁(防止掉出地图)
    local wallX = CONFIG.MapWidth / 2 + 1.5
    for _, wx in ipairs({-wallX, wallX}) do
        local wallNode = scene_:CreateChild("Wall")
        wallNode:SetPosition2D(wx, 0)
        local wallBody = wallNode:CreateComponent("RigidBody2D")
        wallBody.bodyType = BT_STATIC
        local wallShape = wallNode:CreateComponent("CollisionBox2D")
        wallShape:SetSize(1, CONFIG.MapHeight + 4)
        wallShape.categoryBits = 1
    end
end

-- ============================================================================
-- 创建玩家
-- ============================================================================
function CreatePlayers()
    for i, pdata in ipairs(PLAYERS) do
        local node = scene_:CreateChild("Player" .. i)
        node:SetPosition2D(pdata.spawnX, CONFIG.GroundY + 2)

        local body = node:CreateComponent("RigidBody2D")
        body.bodyType = BT_DYNAMIC
        body.fixedRotation = true
        body.linearDamping = 0.0
        body.gravityScale = 1.0

        -- 主碰撞体(圆形)
        local bodyShape = node:CreateComponent("CollisionCircle2D")
        bodyShape.radius = CONFIG.PlayerRadius
        bodyShape.density = 1.0
        bodyShape.friction = 0.0
        bodyShape.restitution = 0.0
        bodyShape.categoryBits = 2
        bodyShape.maskBits = 0xFFFF

        -- 脚底传感器
        local footSensor = node:CreateComponent("CollisionCircle2D")
        footSensor.radius = CONFIG.PlayerRadius * 0.6
        footSensor.center = Vector2(0, -CONFIG.PlayerRadius * 0.9)
        footSensor.trigger = true
        footSensor.categoryBits = 4
        footSensor.maskBits = 1

        players_[i] = {
            node = node,
            body = body,
            onGround = false,
            groundContacts = 0,
            score = 0,
            facing = 1,  -- 1=右, -1=左
            config = pdata,
            animTime = 0,    -- 动画计时器
            isMoving = false, -- 是否在移动
            velY = 0,        -- 纵向速度(用于跳跃动画)
        }
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

    local children = {}
    for i, pdata in ipairs(PLAYERS) do
        table.insert(children, UI.Label {
            id = "score" .. i,
            text = pdata.name .. ": 0",
            fontSize = 18,
            fontColor = pdata.color,
            fontWeight = "bold",
        })
    end

    UI.SetRoot(UI.Panel {
        id = "root",
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = {
            -- 顶部分数栏
            UI.Panel {
                id = "scoreBar",
                position = "absolute",
                top = 12, left = 0, right = 0,
                flexDirection = "row",
                justifyContent = "center",
                gap = 40,
                pointerEvents = "none",
                children = children,
            },
            -- 底部操作提示
            UI.Label {
                position = "absolute",
                bottom = 10, left = 0, right = 0,
                textAlign = "center",
                fontSize = 12,
                fontColor = {255, 255, 255, 180},
                text = "P1(红): Q左 W跳 E右 | P2(绿): A左 S跳 D右 | P3(蓝): Z左 X跳 C右",
            },
        }
    })
end

-- ============================================================================
-- 物理碰撞检测(地面检测)
-- ============================================================================
local function GetPlayerIndex(node)
    for i, p in ipairs(players_) do
        if p.node == node then return i end
    end
    return nil
end

local function IsGround(node)
    if node == nil then return false end
    local name = node.name
    return name == "Ground" or name == "Platform" or name == "Wall"
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

-- ============================================================================
-- 游戏逻辑更新
-- ============================================================================
---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    screenW_ = graphics:GetWidth()
    screenH_ = graphics:GetHeight()

    -- 正常模式下：保持相机 orthoSize 与固定 PPU 一致
    if not cameraZoomed_ then
        local camera = cameraNode_:GetComponent("Camera")
        camera.orthoSize = screenH_ / CONFIG.PixelPerUnit
    end

    if gameOver_ then
        -- R 键重启
        if input:GetKeyPress(KEY_R) then
            RestartGame()
        end
        return
    end

    -- showPhoto 期间冻结玩家（拍照定格效果）
    if gameState_ ~= "showPhoto" and gameState_ ~= "flash" then
        UpdatePlayers(dt)
    end

    -- 更新游戏状态机
    UpdateGameState(dt)
end

function UpdatePlayers(dt)
    for i, p in ipairs(players_) do
        local keys = p.config.keys
        local vel = p.body.linearVelocity
        local desiredVelX = 0

        -- 左右移动
        if input:GetKeyDown(keys.left) then
            desiredVelX = -CONFIG.PlayerSpeed
            p.facing = -1
        elseif input:GetKeyDown(keys.right) then
            desiredVelX = CONFIG.PlayerSpeed
            p.facing = 1
        end

        p.body.linearVelocity = Vector2(desiredVelX, vel.y)

        -- 跳跃
        if p.onGround and input:GetKeyPress(keys.jump) then
            p.body.linearVelocity = Vector2(desiredVelX, CONFIG.PlayerJumpSpeed)
            p.body.awake = true
        end

        -- 更新动画状态
        p.isMoving = math.abs(desiredVelX) > 0.1
        p.velY = p.body.linearVelocity.y
        if p.isMoving then
            p.animTime = p.animTime + dt * 10  -- 走路动画速度
        else
            p.animTime = 0
        end
    end
end

function UpdateGameState(dt)
    if gameState_ == "waiting" then
        intervalTimer_ = intervalTimer_ - dt
        if intervalTimer_ <= 0 then
            SpawnPhotoZone()
            gameState_ = "countdown"
            countdown_ = CONFIG.CountdownTime
        end

    elseif gameState_ == "countdown" then
        countdown_ = countdown_ - dt
        if countdown_ <= 0 then
            TakePhoto()
            gameState_ = "flash"
            flashTimer_ = 0.3  -- 短暂白色闪光
        end

    elseif gameState_ == "flash" then
        flashTimer_ = flashTimer_ - dt
        if flashTimer_ <= 0 then
            gameState_ = "showPhoto"
            showPhotoTimer_ = 1.5  -- 展示照片1.5秒
            -- 推进相机到拍照区域
            ZoomCameraToPhotoZone()
        end

    elseif gameState_ == "showPhoto" then
        showPhotoTimer_ = showPhotoTimer_ - dt
        if showPhotoTimer_ <= 0 then
            photoZone_.active = false
            gameState_ = "waiting"
            intervalTimer_ = CONFIG.IntervalTime
            -- 恢复相机
            RestoreCameraFromZoom()
        end
    end
end

-- ============================================================================
-- 拍照逻辑
-- ============================================================================
function SpawnPhotoZone()
    -- 随机位置(确保在地图内)
    local halfMap = CONFIG.MapWidth / 2 - CONFIG.PhotoWidth / 2 - 1
    local zx = math.random() * halfMap * 2 - halfMap
    local zy = CONFIG.GroundY + 1 + math.random() * (CONFIG.MapHeight - CONFIG.PhotoHeight - 2)

    photoZone_.x = zx
    photoZone_.y = zy
    photoZone_.active = true

    print(string.format("拍照区域出现: (%.1f, %.1f)", zx, zy))
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

    for i, p in ipairs(players_) do
        local pos = p.node.position2D
        -- 记录快照(用于展示照片)
        photoSnapshot_[i] = {
            x = pos.x,
            y = pos.y,
            facing = p.facing,
        }

        -- 检查玩家是否在拍照区域内
        local inZone = pos.x >= photoZone_.x - photoZone_.width / 2
                   and pos.x <= photoZone_.x + photoZone_.width / 2
                   and pos.y >= photoZone_.y - photoZone_.height / 2
                   and pos.y <= photoZone_.y + photoZone_.height / 2

        if inZone then
            p.score = p.score + CONFIG.ScorePerPhoto
            table.insert(roundResult_, i)
            print(p.config.name .. " 入镜得分! 总分: " .. p.score)

            -- 检查胜利
            if p.score >= CONFIG.WinScore then
                gameOver_ = true
                winner_ = p.config.name
                print("=== " .. winner_ .. " 获胜! ===")
            end
        end
    end

    -- 更新UI分数
    UpdateScoreUI()
end

-- ============================================================================
-- 相机推进/恢复（拍照展示用）
-- ============================================================================
function ZoomCameraToPhotoZone()
    -- 保存当前状态
    cameraNormalPos_ = cameraNode_.position
    local camera = cameraNode_:GetComponent("Camera")
    cameraNormalOrtho_ = camera.orthoSize

    -- 轻微缩放：仅缩小到正常的 80%，主要靠居中+暗色边框营造拍照感
    -- 不要缩放太多，否则角色会变成"大胖球"
    local targetOrtho = cameraNormalOrtho_ * 0.8

    cameraNode_.position = Vector3(photoZone_.x, photoZone_.y, -10)
    camera.orthoSize = targetOrtho
    cameraZoomed_ = true

    -- 冻结物理世界（玩家定格）
    for _, p in ipairs(players_) do
        p.savedVelocity = p.body.linearVelocity
        p.body.linearVelocity = Vector2(0, 0)
        p.body.gravityScale = 0
    end
end

function RestoreCameraFromZoom()
    if not cameraZoomed_ then return end
    cameraNode_.position = cameraNormalPos_
    local camera = cameraNode_:GetComponent("Camera")
    camera.orthoSize = cameraNormalOrtho_
    cameraZoomed_ = false

    -- 恢复物理
    for _, p in ipairs(players_) do
        p.body.gravityScale = 1.0
        if p.savedVelocity then
            p.body.linearVelocity = p.savedVelocity
            p.savedVelocity = nil
        end
    end
end

function UpdateScoreUI()
    for i, p in ipairs(players_) do
        local label = UI.FindById("score" .. i)
        if label then
            label:SetText(p.config.name .. ": " .. p.score)
        end
    end
end

function RestartGame()
    gameOver_ = false
    winner_ = ""
    gameState_ = "waiting"
    intervalTimer_ = 2.0
    photoZone_.active = false
    roundResult_ = {}

    for i, p in ipairs(players_) do
        p.score = 0
        p.node:SetPosition2D(p.config.spawnX, CONFIG.GroundY + 2)
        p.body.linearVelocity = Vector2(0, 0)
    end
    UpdateScoreUI()
    print("=== 游戏重新开始 ===")
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================
function HandleNanoVGRender(eventType, eventData)
    if nvg_ == nil then return end

    nvgBeginFrame(nvg_, screenW_, screenH_, 1.0)

    DrawBackground()
    DrawPlatforms()
    DrawPhotoZone()
    DrawPlayers()
    DrawCountdown()
    DrawFlashEffect()
    DrawShowPhoto()
    DrawGameOver()

    nvgEndFrame(nvg_)
end

-- 当前每单位像素数（根据相机 orthoSize 动态计算）
function GetPixelsPerUnit()
    local camera = cameraNode_:GetComponent("Camera")
    return screenH_ / camera.orthoSize
end

-- 物理坐标转屏幕坐标（相机感知）
function PhysToScreen(px, py)
    local camera = cameraNode_:GetComponent("Camera")
    local orthoSize = camera.orthoSize
    local camX = cameraNode_.position.x
    local camY = cameraNode_.position.y
    local ppu = screenH_ / orthoSize

    local sx = screenW_ / 2 + (px - camX) * ppu
    local sy = screenH_ / 2 - (py - camY) * ppu
    return sx, sy
end

function DrawBackground()
    -- 天空渐变（浅蓝到白）
    nvgBeginPath(nvg_)
    nvgRect(nvg_, 0, 0, screenW_, screenH_)
    local skyGrad = nvgLinearGradient(nvg_, 0, 0, 0, screenH_,
        nvgRGBA(100, 180, 255, 255), nvgRGBA(200, 230, 255, 255))
    nvgFillPaint(nvg_, skyGrad)
    nvgFill(nvg_)

    -- 太阳
    local sunX = screenW_ * 0.82
    local sunY = screenH_ * 0.12
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, sunX, sunY, 40)
    local sunGrad = nvgRadialGradient(nvg_, sunX, sunY, 10, 40,
        nvgRGBA(255, 250, 200, 255), nvgRGBA(255, 200, 80, 200))
    nvgFillPaint(nvg_, sunGrad)
    nvgFill(nvg_)
    -- 太阳光晕
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, sunX, sunY, 55)
    local haloGrad = nvgRadialGradient(nvg_, sunX, sunY, 35, 55,
        nvgRGBA(255, 240, 150, 60), nvgRGBA(255, 240, 150, 0))
    nvgFillPaint(nvg_, haloGrad)
    nvgFill(nvg_)

    -- 云朵
    math.randomseed(42)
    for i = 1, 5 do
        local cx = math.random(50, math.floor(screenW_ - 50))
        local cy = math.random(30, math.floor(screenH_ * 0.25))
        local cloudW = math.random(60, 120)
        DrawCloud(cx, cy, cloudW)
    end
    math.randomseed(os.time())

    -- 远山（深绿）
    DrawMountain(screenH_ * 0.45, nvgRGBA(60, 120, 80, 255), 123)
    -- 近山（浅绿）
    DrawMountain(screenH_ * 0.55, nvgRGBA(80, 160, 90, 255), 456)

    -- 草地（地面以下区域填充绿色）
    local _, groundScreenY = PhysToScreen(0, CONFIG.GroundY)
    nvgBeginPath(nvg_)
    nvgRect(nvg_, 0, groundScreenY - 10, screenW_, screenH_ - groundScreenY + 10)
    local grassGrad = nvgLinearGradient(nvg_, 0, groundScreenY, 0, screenH_,
        nvgRGBA(80, 180, 60, 255), nvgRGBA(50, 120, 40, 255))
    nvgFillPaint(nvg_, grassGrad)
    nvgFill(nvg_)

    -- 草地顶部草丛装饰
    math.randomseed(99)
    for i = 1, 40 do
        local gx = math.random(0, math.floor(screenW_))
        local gh = math.random(4, 12)
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, gx, groundScreenY - 10)
        nvgLineTo(nvg_, gx - 2, groundScreenY - 10 - gh)
        nvgLineTo(nvg_, gx + 2, groundScreenY - 10 - gh * 0.7)
        nvgClosePath(nvg_)
        nvgFillColor(nvg_, nvgRGBA(60, 160 + math.random(0, 40), 50, 200))
        nvgFill(nvg_)
    end
    math.randomseed(os.time())

    -- 远处的小树
    math.randomseed(77)
    for i = 1, 6 do
        local tx = math.random(30, math.floor(screenW_ - 30))
        local ty = groundScreenY - 10
        DrawTree(tx, ty, math.random(25, 45))
    end
    math.randomseed(os.time())
end

-- 绘制云朵
function DrawCloud(cx, cy, w)
    local h = w * 0.4
    nvgBeginPath(nvg_)
    nvgEllipse(nvg_, cx, cy, w * 0.5, h * 0.4)
    nvgEllipse(nvg_, cx - w * 0.25, cy + 3, w * 0.3, h * 0.35)
    nvgEllipse(nvg_, cx + w * 0.25, cy + 2, w * 0.35, h * 0.35)
    nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 220))
    nvgFill(nvg_)
end

-- 绘制山脉
function DrawMountain(baseY, color, seed)
    math.randomseed(seed)
    nvgBeginPath(nvg_)
    nvgMoveTo(nvg_, 0, baseY + 40)
    local step = 60
    for x = 0, screenW_ + step, step do
        local peakY = baseY - math.random(20, 80)
        nvgLineTo(nvg_, x, peakY)
    end
    nvgLineTo(nvg_, screenW_, screenH_)
    nvgLineTo(nvg_, 0, screenH_)
    nvgClosePath(nvg_)
    nvgFillColor(nvg_, color)
    nvgFill(nvg_)
    math.randomseed(os.time())
end

-- 绘制小树
function DrawTree(x, y, height)
    -- 树干
    local trunkW = height * 0.12
    local trunkH = height * 0.35
    nvgBeginPath(nvg_)
    nvgRect(nvg_, x - trunkW / 2, y - trunkH, trunkW, trunkH)
    nvgFillColor(nvg_, nvgRGBA(100, 70, 40, 200))
    nvgFill(nvg_)
    -- 树冠
    nvgBeginPath(nvg_)
    nvgEllipse(nvg_, x, y - trunkH - height * 0.3, height * 0.3, height * 0.35)
    nvgFillColor(nvg_, nvgRGBA(40, 140 + math.random(0, 30), 50, 220))
    nvgFill(nvg_)
end

function DrawPlatforms()
    local ppu = GetPixelsPerUnit()
    for _, plat in ipairs(platforms_) do
        local sx, sy = PhysToScreen(plat.x, plat.y)
        local pw = plat.width * ppu
        local ph = plat.height * ppu

        -- 土质平台外观
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, sx - pw/2, sy - ph/2, pw, ph, 6)
        local grad = nvgLinearGradient(nvg_, sx - pw/2, sy - ph/2, sx - pw/2, sy + ph/2,
            nvgRGBA(140, 100, 60, 255), nvgRGBA(100, 70, 40, 255))
        nvgFillPaint(nvg_, grad)
        nvgFill(nvg_)

        -- 顶部草皮
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, sx - pw/2, sy - ph/2 - 3, pw, 6, 3)
        nvgFillColor(nvg_, nvgRGBA(80, 180, 50, 255))
        nvgFill(nvg_)

        -- 草皮上的小草
        local grassCount = math.floor(pw / 12)
        for g = 1, grassCount do
            local gx = sx - pw/2 + g * (pw / (grassCount + 1))
            nvgBeginPath(nvg_)
            nvgMoveTo(nvg_, gx, sy - ph/2 - 3)
            nvgLineTo(nvg_, gx - 1.5, sy - ph/2 - 8)
            nvgLineTo(nvg_, gx + 1.5, sy - ph/2 - 6)
            nvgClosePath(nvg_)
            nvgFillColor(nvg_, nvgRGBA(60, 160, 40, 200))
            nvgFill(nvg_)
        end
    end
end

function DrawPhotoZone()
    if not photoZone_.active then return end
    if gameState_ == "showPhoto" then return end  -- 相机已推进，不绘制标记

    local ppu = GetPixelsPerUnit()
    local sx, sy = PhysToScreen(photoZone_.x, photoZone_.y)
    local pw = photoZone_.width * ppu
    local ph = photoZone_.height * ppu

    -- 闪烁效果
    local alpha = 120 + math.floor(math.sin(os.clock() * 4) * 40)

    -- 填充(半透明黄色)
    nvgBeginPath(nvg_)
    nvgRect(nvg_, sx - pw/2, sy - ph/2, pw, ph)
    nvgFillColor(nvg_, nvgRGBA(255, 220, 50, math.floor(alpha * 0.3)))
    nvgFill(nvg_)

    -- 边框(虚线效果用多段线模拟)
    nvgBeginPath(nvg_)
    nvgRect(nvg_, sx - pw/2, sy - ph/2, pw, ph)
    nvgStrokeColor(nvg_, nvgRGBA(255, 220, 50, alpha))
    nvgStrokeWidth(nvg_, 3)
    nvgStroke(nvg_)

    -- 四角标记
    local cornerLen = 12
    local corners = {
        {sx - pw/2, sy - ph/2, 1, 1},
        {sx + pw/2, sy - ph/2, -1, 1},
        {sx - pw/2, sy + ph/2, 1, -1},
        {sx + pw/2, sy + ph/2, -1, -1},
    }
    nvgStrokeColor(nvg_, nvgRGBA(255, 255, 255, 220))
    nvgStrokeWidth(nvg_, 3)
    for _, c in ipairs(corners) do
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, c[1], c[2])
        nvgLineTo(nvg_, c[1] + cornerLen * c[3], c[2])
        nvgMoveTo(nvg_, c[1], c[2])
        nvgLineTo(nvg_, c[1], c[2] + cornerLen * c[4])
        nvgStroke(nvg_)
    end

    -- "📷" 相机图标文字
    nvgFontSize(nvg_, 20)
    nvgFontFace(nvg_, "sans")
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvg_, nvgRGBA(255, 220, 50, 200))
    nvgText(nvg_, sx, sy - ph/2 - 24, "📷 拍照区域", nil)
end

function DrawPlayers()
    local ppu = GetPixelsPerUnit()
    for i, p in ipairs(players_) do
        local pos = p.node.position2D
        local sx, sy = PhysToScreen(pos.x, pos.y)
        local r = CONFIG.PlayerRadius * ppu
        local c = p.config.color

        -- 动画参数
        local limbSwing = 0
        local armSwing = 0
        local inAir = not p.onGround

        if inAir then
            -- 跳跃姿态：手脚张开
            limbSwing = 0.4
            armSwing = -0.5
        elseif p.isMoving then
            -- 走路摆动
            limbSwing = math.sin(p.animTime) * 0.6
            armSwing = -math.sin(p.animTime) * 0.5
        end

        local legLen = r * 0.75
        local armLen = r * 0.6
        local limbWidth = 3.5
        local darkC = {math.max(0, c[1] - 50), math.max(0, c[2] - 50), math.max(0, c[3] - 50)}

        -- 左腿
        local leftLegAngle = limbSwing
        local leftLegEndX = sx - 5 + math.sin(leftLegAngle) * legLen
        local leftLegEndY = sy + r * 0.6 + math.cos(leftLegAngle) * legLen
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, sx - 5, sy + r * 0.5)
        nvgLineTo(nvg_, leftLegEndX, leftLegEndY)
        nvgStrokeColor(nvg_, nvgRGBA(darkC[1], darkC[2], darkC[3], 255))
        nvgStrokeWidth(nvg_, limbWidth)
        nvgLineCap(nvg_, NVG_ROUND)
        nvgStroke(nvg_)
        -- 左脚（小圆）
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, leftLegEndX, leftLegEndY, 3.5)
        nvgFillColor(nvg_, nvgRGBA(darkC[1], darkC[2], darkC[3], 255))
        nvgFill(nvg_)

        -- 右腿
        local rightLegAngle = -limbSwing
        local rightLegEndX = sx + 5 + math.sin(rightLegAngle) * legLen
        local rightLegEndY = sy + r * 0.6 + math.cos(rightLegAngle) * legLen
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, sx + 5, sy + r * 0.5)
        nvgLineTo(nvg_, rightLegEndX, rightLegEndY)
        nvgStrokeColor(nvg_, nvgRGBA(darkC[1], darkC[2], darkC[3], 255))
        nvgStrokeWidth(nvg_, limbWidth)
        nvgLineCap(nvg_, NVG_ROUND)
        nvgStroke(nvg_)
        -- 右脚
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, rightLegEndX, rightLegEndY, 3.5)
        nvgFillColor(nvg_, nvgRGBA(darkC[1], darkC[2], darkC[3], 255))
        nvgFill(nvg_)

        -- 左手臂
        local leftArmAngle = armSwing
        local armStartX = sx - r * 0.7
        local armStartY = sy - r * 0.1
        local leftArmEndX = armStartX + math.sin(leftArmAngle) * armLen - 4
        local leftArmEndY = armStartY + math.cos(leftArmAngle) * armLen
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, armStartX, armStartY)
        nvgLineTo(nvg_, leftArmEndX, leftArmEndY)
        nvgStrokeColor(nvg_, nvgRGBA(c[1], c[2], c[3], 255))
        nvgStrokeWidth(nvg_, limbWidth)
        nvgLineCap(nvg_, NVG_ROUND)
        nvgStroke(nvg_)
        -- 左手（小圆）
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, leftArmEndX, leftArmEndY, 3)
        nvgFillColor(nvg_, nvgRGBA(255, 220, 180, 255))
        nvgFill(nvg_)

        -- 右手臂
        local rightArmAngle = -armSwing
        local armStartRX = sx + r * 0.7
        local rightArmEndX = armStartRX + math.sin(rightArmAngle) * armLen + 4
        local rightArmEndY = armStartY + math.cos(rightArmAngle) * armLen
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, armStartRX, armStartY)
        nvgLineTo(nvg_, rightArmEndX, rightArmEndY)
        nvgStrokeColor(nvg_, nvgRGBA(c[1], c[2], c[3], 255))
        nvgStrokeWidth(nvg_, limbWidth)
        nvgLineCap(nvg_, NVG_ROUND)
        nvgStroke(nvg_)
        -- 右手
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, rightArmEndX, rightArmEndY, 3)
        nvgFillColor(nvg_, nvgRGBA(255, 220, 180, 255))
        nvgFill(nvg_)

        -- 身体(圆形+渐变)
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, sx, sy, r)
        local bodyGrad = nvgRadialGradient(nvg_, sx - 4, sy - 4, 2, r + 2,
            nvgRGBA(math.min(255, c[1] + 40), math.min(255, c[2] + 40), math.min(255, c[3] + 40), 255),
            nvgRGBA(c[1], c[2], c[3], 255))
        nvgFillPaint(nvg_, bodyGrad)
        nvgFill(nvg_)

        -- 边框
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, sx, sy, r)
        nvgStrokeColor(nvg_, nvgRGBA(255, 255, 255, 100))
        nvgStrokeWidth(nvg_, 2)
        nvgStroke(nvg_)

        -- 眼睛(朝向方向)
        local eyeOffX = p.facing * 5
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, sx + eyeOffX - 4, sy - 4, 3)
        nvgCircle(nvg_, sx + eyeOffX + 4, sy - 4, 3)
        nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 255))
        nvgFill(nvg_)

        -- 瞳孔
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, sx + eyeOffX - 3 + p.facing, sy - 3, 1.5)
        nvgCircle(nvg_, sx + eyeOffX + 5 + p.facing, sy - 3, 1.5)
        nvgFillColor(nvg_, nvgRGBA(0, 0, 0, 255))
        nvgFill(nvg_)

        -- 微笑（移动时张嘴）
        nvgBeginPath(nvg_)
        if p.isMoving or inAir then
            -- 开心的嘴
            nvgArc(nvg_, sx + p.facing * 3, sy + 4, 4, 0, math.pi, NVG_CW)
        else
            -- 微笑弧线
            nvgArc(nvg_, sx + p.facing * 3, sy + 3, 3, 0.2, math.pi - 0.2, NVG_CW)
        end
        nvgStrokeColor(nvg_, nvgRGBA(0, 0, 0, 200))
        nvgStrokeWidth(nvg_, 1.5)
        nvgStroke(nvg_)

        -- 移动时的速度线
        if p.isMoving and p.onGround then
            local lineDir = -p.facing
            for l = 1, 3 do
                local lx = sx + lineDir * (r + 4 + l * 5)
                local ly = sy - 4 + l * 5
                local lineLen = 6 + (3 - l) * 3
                nvgBeginPath(nvg_)
                nvgMoveTo(nvg_, lx, ly)
                nvgLineTo(nvg_, lx + lineDir * lineLen, ly)
                nvgStrokeColor(nvg_, nvgRGBA(200, 200, 200, 150 - l * 40))
                nvgStrokeWidth(nvg_, 1.5)
                nvgStroke(nvg_)
            end
        end

        -- 跳跃时的下方气流效果
        if inAir and p.velY > 2 then
            for l = 1, 3 do
                nvgBeginPath(nvg_)
                nvgCircle(nvg_, sx - 6 + l * 6, sy + r + 8 + l * 4, 2 - l * 0.4)
                nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 120 - l * 30))
                nvgFill(nvg_)
            end
        end

        -- 名字标签
        nvgFontSize(nvg_, 14)
        nvgFontFace(nvg_, "sans")
        nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(nvg_, nvgRGBA(c[1], c[2], c[3], 255))
        nvgText(nvg_, sx, sy - r - 10, p.config.name, nil)
    end
end

function DrawCountdown()
    if gameState_ ~= "countdown" then return end

    local num = math.ceil(countdown_)
    local text = tostring(num)

    -- 大数字居中
    local scale = 1.0 + (countdown_ - math.floor(countdown_)) * 0.3
    nvgFontSize(nvg_, 80 * scale)
    nvgFontFace(nvg_, "sans")
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 阴影
    nvgFillColor(nvg_, nvgRGBA(0, 0, 0, 150))
    nvgText(nvg_, screenW_/2 + 3, screenH_/2 + 3, text, nil)

    -- 主体(白色)
    local urgency = math.max(0, 1 - countdown_ / CONFIG.CountdownTime)
    local r = math.floor(255 * urgency)
    local g = math.floor(255 * (1 - urgency))
    nvgFillColor(nvg_, nvgRGBA(r + 100, g + 100, 100, 255))
    nvgText(nvg_, screenW_/2, screenH_/2, text, nil)
end

function DrawFlashEffect()
    if gameState_ ~= "flash" then return end

    -- 白色闪光(快速闪烁)
    local alpha = math.floor((flashTimer_ / 0.3) * 255)
    nvgBeginPath(nvg_)
    nvgRect(nvg_, 0, 0, screenW_, screenH_)
    nvgFillColor(nvg_, nvgRGBA(255, 255, 255, math.min(alpha, 220)))
    nvgFill(nvg_)
end

function DrawShowPhoto()
    if gameState_ ~= "showPhoto" then return end

    -- 相机已推进到拍照区域，viewport 就是"照片内容"
    -- NanoVG 叠加拍立得相框效果

    -- 拍立得相框参数（按屏幕比例计算）
    local borderLR = math.floor(screenW_ * 0.06)        -- 左右边框 ~6%
    local borderTop = math.floor(screenH_ * 0.06)       -- 上边框 ~6%
    local borderBottom = math.floor(screenH_ * 0.14)    -- 下边框大一些（放文字）

    -- 淡入动画
    local progress = math.min(1.0, (1.5 - showPhotoTimer_) / 0.15)

    nvgSave(nvg_)

    -- 照片内容区域（中间不遮挡，保留游戏画面）
    local photoX = borderLR
    local photoY = borderTop
    local photoW = screenW_ - borderLR * 2
    local photoH = screenH_ - borderTop - borderBottom

    -- 1) 半透明黑色遮罩四边（突出中间照片区域）
    local maskAlpha = math.floor(180 * progress)
    nvgFillColor(nvg_, nvgRGBA(0, 0, 0, maskAlpha))
    -- 上
    nvgBeginPath(nvg_)
    nvgRect(nvg_, 0, 0, screenW_, photoY)
    nvgFill(nvg_)
    -- 下
    nvgBeginPath(nvg_)
    nvgRect(nvg_, 0, photoY + photoH, screenW_, screenH_ - photoY - photoH)
    nvgFill(nvg_)
    -- 左
    nvgBeginPath(nvg_)
    nvgRect(nvg_, 0, photoY, photoX, photoH)
    nvgFill(nvg_)
    -- 右
    nvgBeginPath(nvg_)
    nvgRect(nvg_, photoX + photoW, photoY, screenW_ - photoX - photoW, photoH)
    nvgFill(nvg_)

    -- 2) 白色相框边（拍立得风格）
    local frameBorder = 4
    nvgBeginPath(nvg_)
    nvgRect(nvg_, photoX - frameBorder, photoY - frameBorder,
            photoW + frameBorder * 2, photoH + frameBorder * 2)
    nvgStrokeColor(nvg_, nvgRGBA(255, 255, 255, math.floor(240 * progress)))
    nvgStrokeWidth(nvg_, frameBorder)
    nvgStroke(nvg_)

    -- 5) 照片内暗角效果（四边渐暗）
    local vigAlpha = math.floor(40 * progress)
    -- 上暗角
    nvgBeginPath(nvg_)
    nvgRect(nvg_, photoX, photoY, photoW, photoH * 0.15)
    local topVig = nvgLinearGradient(nvg_, photoX, photoY, photoX, photoY + photoH * 0.15,
        nvgRGBA(0, 0, 0, vigAlpha), nvgRGBA(0, 0, 0, 0))
    nvgFillPaint(nvg_, topVig)
    nvgFill(nvg_)
    -- 下暗角
    nvgBeginPath(nvg_)
    nvgRect(nvg_, photoX, photoY + photoH * 0.85, photoW, photoH * 0.15)
    local botVig = nvgLinearGradient(nvg_, photoX, photoY + photoH * 0.85, photoX, photoY + photoH,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, vigAlpha))
    nvgFillPaint(nvg_, botVig)
    nvgFill(nvg_)

    -- 6) 底部结果文字（白色大字，在黑色遮罩区域上）
    local textY = photoY + photoH + borderBottom * 0.5
    nvgFontSize(nvg_, math.max(22, math.floor(screenH_ * 0.038)))
    nvgFontFace(nvg_, "sans")
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if #roundResult_ > 0 then
        local names = {}
        for _, idx in ipairs(roundResult_) do
            table.insert(names, players_[idx].config.name)
        end
        nvgFillColor(nvg_, nvgRGBA(100, 255, 100, math.floor(255 * progress)))
        nvgText(nvg_, screenW_ / 2, textY, "📸 " .. table.concat(names, " & ") .. " 入镜! +1", nil)
    else
        nvgFillColor(nvg_, nvgRGBA(255, 120, 120, math.floor(255 * progress)))
        nvgText(nvg_, screenW_ / 2, textY, "😢 没人入镜!", nil)
    end

    -- 7) 顶部 "PHOTO" 小标签（白色，在黑色遮罩区域上）
    nvgFontSize(nvg_, 14)
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg_, nvgRGBA(255, 255, 255, math.floor(200 * progress)))
    nvgText(nvg_, screenW_ / 2, photoY * 0.5, "📷 PHOTO", nil)

    nvgRestore(nvg_)
end

function DrawGameOver()
    if not gameOver_ then return end

    -- 半透明遮罩
    nvgBeginPath(nvg_)
    nvgRect(nvg_, 0, 0, screenW_, screenH_)
    nvgFillColor(nvg_, nvgRGBA(0, 0, 0, 180))
    nvgFill(nvg_)

    -- 获胜文字
    nvgFontSize(nvg_, 56)
    nvgFontFace(nvg_, "sans")
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg_, nvgRGBA(255, 220, 50, 255))
    nvgText(nvg_, screenW_/2, screenH_/2 - 30, winner_ .. " 获胜!", nil)

    nvgFontSize(nvg_, 24)
    nvgFillColor(nvg_, nvgRGBA(200, 200, 200, 255))
    nvgText(nvg_, screenW_/2, screenH_/2 + 30, "按 R 重新开始", nil)
end
