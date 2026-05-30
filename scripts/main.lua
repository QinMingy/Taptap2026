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
local Cfg = require("config")
local Gameplay = require("gameplay")
local Render = require("render")
local Editors = require("editors")

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
    }
end

--- 编辑器 Transform 数据
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
    local docsFile = cache:GetFile("docs/skin-editor.json")
    if docsFile then
        jsonStr = docsFile:ReadString()
        docsFile:Close()
    end
    if not jsonStr or #jsonStr == 0 then
        if fileSystem:FileExists("skin-editor.json") then
            local file = File("skin-editor.json", FILE_READ)
            if file:IsOpen() then
                jsonStr = file:ReadString()
                file:Close()
            end
        end
    end
    if not jsonStr or #jsonStr == 0 then
        local file = cache:GetFile("skin-editor.json")
        if file then
            jsonStr = file:ReadString()
            file:Close()
        end
    end
    if not jsonStr or #jsonStr == 0 then return default end
    local ok, data = pcall(cjson.decode, jsonStr)
    if not ok or not data then return default end
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
local usedPresets_ = {}

-- 游戏状态
local gameState_ = "lobby"
local countdown_ = 0
local prepTimer_ = 0
local flashTimer_ = 0
local showPhotoTimer_ = 0
local roundResult_ = {}
local photoSnapshot_ = {}
local gameOver_ = false
local winner_ = ""

-- 大厅状态
local lobby_ = {
    slots = {
        { joined = false, skinIndex = 1, ready = false },
        { joined = false, skinIndex = 1, ready = false },
        { joined = false, skinIndex = 2, ready = false },
        { joined = false, skinIndex = 2, ready = false },
    },
    animTime = 0,
    xButtonRects = {},
}

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

-- 相机状态
local cameraNormalPos_ = Vector3(0, 0, -10)
local cameraNormalOrtho_ = CONFIG.OrthoSize
local cameraZoomed_ = false

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
    G.photoZone = photoZone_
    G.gameState = gameState_
    G.bulletin = bulletin_
    G.unlock = unlock_
    G.teams = teams_
    G.playerTeam = playerTeam_
    G.roundResult = roundResult_
    G.photoSnapshot = photoSnapshot_
    G.playerScale = playerScale_
    G.capsuleHeight = capsuleHeight_
    G.capsuleRadius = capsuleRadius_
    G.showCollisionDebug = showCollisionDebug_
    G.skinsRuntime = skinsRuntime_
    G.skinEditorOpen = Editors.skinEditorOpen
    G.skinEditorAnimTime = Editors.skinEditorAnimTime
    G.gameOver = gameOver_
    G.winner = winner_
    G.prepTimer = prepTimer_
    G.countdown = countdown_
    G.flashTimer = flashTimer_
    G.showPhotoTimer = showPhotoTimer_
    G.getUnlockValue = function() return Gameplay.GetUnlockValue(teams_) end
end

-- ============================================================================
-- 解锁系统逻辑（对接 Gameplay 模块）
-- ============================================================================

function GetWinScore()
    local teamSize = math.max(1, #players_ / 2)
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

    local unlockedGameplays = Gameplay.GetUnlockedGameplays(unlockValue)
    local selectedGameplay = Gameplay.SelectGameplayByWeight(unlockedGameplays)
    unlock_.currentGameplayIndex = selectedGameplay

    local gp = GAMEPLAY_DATA[selectedGameplay]
    print(string.format("[Unlock] 本轮玩法: %s (权重 %d, 已解锁 %d 个玩法)", gp.name, gp.weight, #unlockedGameplays))
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

    -- 加载快门音效
    shutterSound_ = cache:GetResource("Sound", "audio/sfx/shutter.ogg")

    CreateScene()
    CreateWorld()
    CreateUI()

    -- 初始化模块
    SyncGameState()
    Render.Init(G)
    Editors.Init(G, Render)

    -- 创建编辑器 UI
    Editors.CreateSkinEditor()
    Editors.CreateTerrainEditor()
    Editors.CreateEditorMenu()

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(nvg_, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleBeginContact")
    SubscribeToEvent("PhysicsEndContact2D", "HandleEndContact")
    SubscribeToEvent("PhysicsUpdateContact2D", "HandleUpdateContact")

    gameState_ = "lobby"
    print("=== Photo Rush 团队抓拍游戏启动 ===")
    print("按跳跃键加入: W / S / X / I")
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
        children = {
            UI.Label {
                position = "absolute",
                bottom = 10, left = 0, right = 0,
                textAlign = "center",
                fontSize = 12,
                fontColor = {255, 255, 255, 180},
                text = "P1: QWE | P2: ASD | P3: ZXC | P4: UIO",
            },
        }
    })
end

--- 大厅结束后创建队伍 UI
function CreateTeamUI()
    local root = UI.FindById("root")
    if not root then return end

    -- 构建左队成员
    local t1PanelChildren = {
        UI.Label {
            id = "team1Score",
            text = "团队总分 0",
            fontSize = 18,
            fontColor = teams_[1].color,
            fontWeight = "bold",
        },
    }
    for _, pi in ipairs(teams_[1].members) do
        local pdata = PLAYERS[pi]
        table.insert(t1PanelChildren, UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6,
            children = {
                UI.Panel { width = 14, height = 14, borderRadius = 7, backgroundColor = pdata.color },
                UI.Label { id = "score" .. pi, text = "0", fontSize = 16, fontColor = {255, 255, 255, 220} },
            }
        })
    end

    -- 构建右队成员
    local t2PanelChildren = {
        UI.Label {
            id = "team2Score",
            text = "0 团队总分",
            fontSize = 18,
            fontColor = teams_[2].color,
            fontWeight = "bold",
        },
    }
    for _, pi in ipairs(teams_[2].members) do
        local pdata = PLAYERS[pi]
        table.insert(t2PanelChildren, UI.Panel {
            flexDirection = "row", alignItems = "center", justifyContent = "flex-end", gap = 6,
            children = {
                UI.Label { id = "score" .. pi, text = "0", fontSize = 16, fontColor = {255, 255, 255, 220} },
                UI.Panel { width = 14, height = 14, borderRadius = 7, backgroundColor = pdata.color },
            }
        })
    end

    root:AddChild(UI.Panel {
        id = "team1Panel",
        position = "absolute",
        top = 8, left = 10,
        padding = 8, gap = 4,
        pointerEvents = "none",
        children = t1PanelChildren,
    })
    root:AddChild(UI.Panel {
        id = "team2Panel",
        position = "absolute",
        top = 8, right = 10,
        padding = 8, gap = 4,
        alignItems = "flex-end",
        pointerEvents = "none",
        children = t2PanelChildren,
    })
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
---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    screenW_ = graphics:GetWidth()
    screenH_ = graphics:GetHeight()

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

    -- 大厅逻辑
    if gameState_ == "lobby" then
        UpdateLobby(dt)
        return
    end

    if gameOver_ then
        if input:GetKeyPress(KEY_R) then
            RestartGame()
        end
        return
    end

    -- prep 和 countdown 阶段玩家可移动
    if gameState_ == "prep" or gameState_ == "countdown" then
        UpdatePlayers(dt)
        Gameplay.UpdateCoinCollection(players_, unlock_.currentGameplayIndex)
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
function UpdateLobby(dt)
    lobby_.animTime = lobby_.animTime + dt * 4.0

    -- 按跳跃键加入/准备
    for i, slot in ipairs(lobby_.slots) do
        local keys = PLAYERS[i].keys
        if input:GetKeyPress(keys.jump) then
            if not slot.joined then
                slot.joined = true
                print(PLAYERS[i].name .. " 加入游戏")
            elseif not slot.ready then
                slot.ready = true
                print(PLAYERS[i].name .. " 准备就绪")
            end
        end
        -- 左右键切换皮肤
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

    -- 检查是否所有加入的玩家都准备就绪（至少2人）
    local joinedCount = 0
    local allReady = true
    for _, slot in ipairs(lobby_.slots) do
        if slot.joined then
            joinedCount = joinedCount + 1
            if not slot.ready then allReady = false end
        end
    end

    if joinedCount >= 2 and allReady then
        StartGameFromLobby()
    end
end

function StartGameFromLobby()
    -- 收集已加入的玩家索引
    local activeIndices = {}
    for i, slot in ipairs(lobby_.slots) do
        if slot.joined then
            table.insert(activeIndices, i)
        end
    end

    CreatePlayers(activeIndices)
    AssignTeams()
    CreateTeamUI()

    -- 进入第一个公告板
    bulletin_.round = 1
    bulletin_.confirmed = {}
    for i = 1, #players_ do
        bulletin_.confirmed[i] = false
    end
    bulletin_.animPhase = "enter"
    bulletin_.animTimer = 0
    gameState_ = "bulletin"

    -- 选择第一轮玩法
    unlock_.currentGameplayIndex = 1
    CheckUnlockAndPrepareRound()

    print("=== 游戏开始! ===")
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

        p.isMoving = math.abs(desiredVelX) > 0.1
        p.velY = p.body.linearVelocity.y
        if p.isMoving then
            p.animTime = p.animTime + dt * 10
        else
            p.animTime = 0
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

                -- 通知 gameplay 模块准备阶段开始
                Gameplay.OnPrepStart(unlock_.currentGameplayIndex, unlock_.currentMapLevel)
                gameState_ = "prep"
                prepTimer_ = gp.prepTime
            end
        end

    elseif gameState_ == "prep" then
        prepTimer_ = prepTimer_ - dt
        if prepTimer_ <= 0 then
            SpawnPhotoZone()
            local gp = GAMEPLAY_DATA[unlock_.currentGameplayIndex]
            gameState_ = "countdown"
            countdown_ = gp.rushTime
        end

    elseif gameState_ == "countdown" then
        countdown_ = countdown_ - dt
        if countdown_ <= 0 then
            TakePhoto()
            gameState_ = "flash"
            flashTimer_ = 0.3
        end

    elseif gameState_ == "flash" then
        flashTimer_ = flashTimer_ - dt
        if flashTimer_ <= 0 then
            gameState_ = "showPhoto"
            showPhotoTimer_ = 2.5
        end

    elseif gameState_ == "showPhoto" then
        showPhotoTimer_ = showPhotoTimer_ - dt
        if showPhotoTimer_ <= 0 then
            photoZone_.active = false
            Gameplay.OnRoundEnd()
            StartNextBulletin()
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
-- 拍照逻辑
-- ============================================================================
function SpawnPhotoZone()
    local available = {}
    for i = 1, #PHOTO_PRESETS do
        if not usedPresets_[i] then
            available[#available + 1] = i
        end
    end
    if #available == 0 then
        usedPresets_ = {}
        for i = 1, #PHOTO_PRESETS do
            available[#available + 1] = i
        end
    end

    local pick = available[math.random(#available)]
    usedPresets_[pick] = true

    local preset = PHOTO_PRESETS[pick]
    photoZone_.x = preset.x
    photoZone_.y = preset.y
    photoZone_.active = true
    print(string.format("拍照区域出现: %s (%.1f, %.1f)", preset.name, preset.x, preset.y))
end

function TakePhoto()
    roundResult_ = {}
    photoSnapshot_ = {}
    local playersInZone = {}

    -- 播放快门音效
    if shutterSound_ then
        local soundNode = scene_:CreateChild("ShutterSFX")
        local soundSource = soundNode:CreateComponent("SoundSource")
        soundSource:Play(shutterSound_)
        soundSource.autoRemoveMode = REMOVE_NODE
    end

    for i, p in ipairs(players_) do
        local pos = p.node.position2D
        photoSnapshot_[i] = {
            x = pos.x, y = pos.y,
            facing = p.facing,
            onGround = p.onGround,
            isMoving = p.isMoving,
            animTime = p.animTime,
        }

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
    local t1Label = UI.FindById("team1Score")
    if t1Label then t1Label:SetText("团队总分 " .. teams_[1].score) end
    local t2Label = UI.FindById("team2Score")
    if t2Label then t2Label:SetText(teams_[2].score .. " 团队总分") end
end

function RestartGame()
    gameOver_ = false
    winner_ = ""
    photoZone_.active = false
    roundResult_ = {}
    usedPresets_ = {}

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
    lobby_.xButtonRects = {}
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

    if gameState_ == "lobby" then
        DrawLobby()
    else
        Render.DrawBackground()
        Render.DrawPlatforms()
        Render.DrawCoins(Gameplay.GetCoins(), unlock_.currentGameplayIndex)
        Render.DrawPhotoZone()
        Render.DrawPlayers()
        Render.DrawPlayerCoinCount(Gameplay.GetPlayerCoins(), unlock_.currentGameplayIndex)
        Render.DrawPrepIndicator()
        Render.DrawCountdown()
        Render.DrawFlashEffect()
        Render.DrawShowPhoto()
        Render.DrawBulletin()
        Render.DrawGameOver()
    end

    Editors.DrawTerrainEditor()
    Render.DrawSkinEditorPreview()

    nvgEndFrame(nvg_)
end

-- ============================================================================
-- 大厅渲染
-- ============================================================================
function DrawLobby()
    local nvg = nvg_
    local sw, sh = screenW_, screenH_

    -- 背景
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, sw, sh)
    local bg = nvgLinearGradient(nvg, 0, 0, 0, sh,
        nvgRGBA(30, 40, 60, 255), nvgRGBA(15, 20, 35, 255))
    nvgFillPaint(nvg, bg)
    nvgFill(nvg)

    -- 标题
    nvgFontSize(nvg, 36)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 220, 80, 255))
    nvgText(nvg, sw/2, sh * 0.12, "Photo Rush", nil)

    nvgFontSize(nvg, 16)
    nvgFillColor(nvg, nvgRGBA(180, 200, 220, 200))
    nvgText(nvg, sw/2, sh * 0.18, "按跳跃键加入 → 选皮肤(左右键) → 再按跳跃准备", nil)

    -- 玩家槽位
    local slotW = 140
    local slotH = 200
    local totalW = #PLAYERS * slotW + (#PLAYERS - 1) * 20
    local startX = (sw - totalW) / 2

    for i, slot in ipairs(lobby_.slots) do
        local sx = startX + (i - 1) * (slotW + 20)
        local sy = sh * 0.3
        local pdata = PLAYERS[i]
        local c = pdata.color

        -- 槽位背景
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, sx, sy, slotW, slotH, 10)
        if slot.joined then
            nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 40))
        else
            nvgFillColor(nvg, nvgRGBA(40, 40, 50, 180))
        end
        nvgFill(nvg)

        -- 边框
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, sx, sy, slotW, slotH, 10)
        if slot.ready then
            nvgStrokeColor(nvg, nvgRGBA(80, 255, 120, 255))
        elseif slot.joined then
            nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], 200))
        else
            nvgStrokeColor(nvg, nvgRGBA(80, 80, 100, 150))
        end
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)

        -- 玩家名称
        nvgFontSize(nvg, 14)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 255))
        nvgText(nvg, sx + slotW/2, sy + 10, pdata.name, nil)

        if slot.joined then
            -- 绘制角色预览
            local skinIdx = slot.skinIndex
            local skin = skinsRuntime_[skinIdx]
            if skin then
                local limbSwing = math.sin(lobby_.animTime + i) * 0.3
                local armSwing = -math.sin(lobby_.animTime + i) * 0.2
                Render.DrawSinglePlayer({
                    sx = sx + slotW/2,
                    sy = sy + slotH * 0.55,
                    color = c,
                    skin = skin,
                    facing = 1,
                    limbSwing = limbSwing,
                    armSwing = armSwing,
                    inAir = false,
                    isMoving = true,
                    onGround = true,
                    velY = 0,
                    name = "",
                })
            end

            -- 皮肤名称
            local skinName = (skin and skin.name) or "?"
            nvgFontSize(nvg, 11)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(nvg, nvgRGBA(200, 200, 200, 180))
            nvgText(nvg, sx + slotW/2, sy + slotH - 30, skinName, nil)

            -- 状态
            nvgFontSize(nvg, 13)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            if slot.ready then
                nvgFillColor(nvg, nvgRGBA(80, 255, 120, 255))
                nvgText(nvg, sx + slotW/2, sy + slotH - 10, "READY!", nil)
            else
                nvgFillColor(nvg, nvgRGBA(255, 220, 80, 200))
                nvgText(nvg, sx + slotW/2, sy + slotH - 10, "← 选皮肤 →", nil)
            end
        else
            -- 未加入状态
            nvgFontSize(nvg, 14)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(120, 120, 140, 180))
            nvgText(nvg, sx + slotW/2, sy + slotH/2, "按 " .. GetKeyName(pdata.keys.jump) .. " 加入", nil)
        end
    end

    -- 底部提示
    local joinedCount = 0
    for _, slot in ipairs(lobby_.slots) do
        if slot.joined then joinedCount = joinedCount + 1 end
    end
    if joinedCount >= 2 then
        nvgFontSize(nvg, 14)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(nvg, nvgRGBA(200, 200, 200, 180))
        nvgText(nvg, sw/2, sh - 30, "全员准备后自动开始 (至少2人)", nil)
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
