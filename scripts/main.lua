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

--- 皮肤配置（与 docs/skins_data.lua 保持同步）
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
            headTransform = { scale = 1.0, offsetX = 0, offsetY = 0, rotation = 0 },
            torsoTransform = { scale = 1.0, offsetX = 0, offsetY = 0, rotation = 0 },
        },
    }
end

-- 皮肤数据（运行时）
local skinsData_ = {}     -- 从 JSON 解析的原始数据
local skinsRuntime_ = {}  -- 运行时数据（含 NanoVG 图片句柄）

-- ============================================================================
-- 游戏配置
-- ============================================================================
local CONFIG = {
    Title = "Photo Rush - 三人抓拍",
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
        color = {220, 60, 60, 255},       -- 红色（备用/名牌色）
        keys = {left = KEY_Q, jump = KEY_W, right = KEY_E},
        spawnX = -4,
        skinIndex = 1,
    },
    {
        name = "P2",
        color = {60, 200, 60, 255},       -- 绿色
        keys = {left = KEY_A, jump = KEY_S, right = KEY_D},
        spawnX = 0,
        skinIndex = 1,
    },
    {
        name = "P3",
        color = {60, 100, 220, 255},      -- 蓝色
        keys = {left = KEY_Z, jump = KEY_X, right = KEY_C},
        spawnX = 4,
        skinIndex = 1,
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
local gameState_ = "bulletin"  -- bulletin, countdown, flash, showPhoto
local countdown_ = 0
local flashTimer_ = 0         -- 拍照闪光效果
local showPhotoTimer_ = 0     -- 展示照片计时
local roundResult_ = {}       -- 本轮结果(入镜玩家索引)
local photoSnapshot_ = {}     -- 拍照瞬间玩家位置快照
local gameOver_ = false
local winner_ = ""

-- 公告板状态
local bulletin_ = {
    round = 1,                -- 当前关卡
    confirmed = {},           -- 各玩家是否确认 {false, false, false}
    animPhase = "enter",      -- "enter"=弹入, "stay"=等待确认, "exit"=收起
    animTimer = 0,            -- 动画计时器
    enterDuration = 0.4,      -- 弹入动画时长
    exitDuration = 0.35,      -- 收起动画时长
}

-- 关卡玩法描述（预留扩展）
local ROUND_DESCRIPTIONS = {
    "跑进📷拍照区域，倒计时结束时入镜得分！",
    "拍照区域随机出现，抢占有利位置！",
    "争分夺秒，冲进取景框！",
    "站在📷里就能得分，别落下！",
    "找到拍照区域，坚持到快门响起！",
}

-- 平台数据
local platforms_ = {}

-- 屏幕尺寸
local screenW_ = 1280
local screenH_ = 720

-- 音效
local shutterSound_ = nil

-- 相机状态（用于 showPhoto 推进/恢复）
local cameraNormalPos_ = Vector3(0, 0, -10)
local cameraNormalOrtho_ = CONFIG.OrthoSize  -- 会在运行时被 CalcContainOrthoSize() 更新
local cameraZoomed_ = false

-- 皮肤编辑器状态
local skinEditorOpen_ = false
local skinEditorPanel_ = nil

-- ============================================================================
-- 入口
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
    CreatePlayers()
    CreateUI()
    CreateSkinEditor()

    -- 初始化公告板
    bulletin_.confirmed = {}
    for i = 1, #PLAYERS do
        bulletin_.confirmed[i] = false
    end

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(nvg_, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleBeginContact")
    SubscribeToEvent("PhysicsEndContact2D", "HandleEndContact")


    print("=== Photo Rush 三人抓拍游戏启动 ===")
    print("P1(红): Q左 W跳 E右 | P2(绿): A左 S跳 D右 | P3(蓝): Z左 X跳 C右")
end

--- 解析 transform 字段，提供默认值
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
    skinsRuntime_ = {}

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
        }
        table.insert(skinsRuntime_, runtime)
        print(string.format("[Skin] Loaded: %s (head=%d, torso=%d)", skin.name, runtime.headImg, runtime.torsoImg))
    end

    if #skinsRuntime_ == 0 then
        print("[Skin] WARNING: No skins loaded, will use fallback rendering")
    end
end

-- ============================================================================
-- 皮肤编辑器 UI
-- ============================================================================
function CreateSkinEditor()
    if #skinsRuntime_ == 0 then return end
    local skin = skinsRuntime_[1]  -- 编辑第一套皮肤

    --- 创建一行 Slider 控制器
    local function MakeSlider(label, min, max, value, step, onChange)
        return UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 8,
            height = 28,
            children = {
                UI.Label { text = label, fontSize = 12, fontColor = {200, 200, 200, 255}, width = 60 },
                UI.Slider {
                    width = 120, height = 16,
                    min = min, max = max, value = value, step = step,
                    onChange = onChange,
                },
                UI.Label {
                    id = "val_" .. label,
                    text = string.format("%.1f", value),
                    fontSize = 11, fontColor = {160, 160, 160, 255}, width = 40,
                },
            }
        }
    end

    local function updateVal(label, v)
        local lbl = UI.FindById("val_" .. label)
        if lbl then lbl:SetText(string.format("%.1f", v)) end
    end

    skinEditorPanel_ = UI.Panel {
        id = "skinEditor",
        position = "absolute",
        top = 50, right = 10,
        width = 260,
        backgroundColor = {20, 20, 30, 220},
        borderRadius = 8,
        padding = 10,
        gap = 4,
        children = {
            UI.Label { text = "Skin Editor (Tab 关闭)", fontSize = 14, fontColor = {255, 220, 100, 255} },
            UI.Label { text = "── 头部 ──", fontSize = 12, fontColor = {150, 200, 255, 255} },
            MakeSlider("H.Scale", 0.2, 3.0, skin.headTransform.scale, 0.1, function(self, v)
                skin.headTransform.scale = v; updateVal("H.Scale", v)
            end),
            MakeSlider("H.OffX", -30, 30, skin.headTransform.offsetX, 1, function(self, v)
                skin.headTransform.offsetX = v; updateVal("H.OffX", v)
            end),
            MakeSlider("H.OffY", -30, 30, skin.headTransform.offsetY, 1, function(self, v)
                skin.headTransform.offsetY = v; updateVal("H.OffY", v)
            end),
            MakeSlider("H.Rot", -180, 180, skin.headTransform.rotation, 1, function(self, v)
                skin.headTransform.rotation = v; updateVal("H.Rot", v)
            end),
            UI.Label { text = "── 躯干 ──", fontSize = 12, fontColor = {150, 200, 255, 255} },
            MakeSlider("T.Scale", 0.2, 3.0, skin.torsoTransform.scale, 0.1, function(self, v)
                skin.torsoTransform.scale = v; updateVal("T.Scale", v)
            end),
            MakeSlider("T.OffX", -30, 30, skin.torsoTransform.offsetX, 1, function(self, v)
                skin.torsoTransform.offsetX = v; updateVal("T.OffX", v)
            end),
            MakeSlider("T.OffY", -30, 30, skin.torsoTransform.offsetY, 1, function(self, v)
                skin.torsoTransform.offsetY = v; updateVal("T.OffY", v)
            end),
            MakeSlider("T.Rot", -180, 180, skin.torsoTransform.rotation, 1, function(self, v)
                skin.torsoTransform.rotation = v; updateVal("T.Rot", v)
            end),
            -- 导出按钮（弹出文本框供复制）
            UI.Button {
                text = "导出配置", variant = "primary", height = 30,
                onClick = function()
                    local ht = skin.headTransform
                    local tt = skin.torsoTransform
                    local content = string.format(
                        '-- 皮肤配置数据（由编辑器导出）\n'
                        .. 'return {\n'
                        .. '    skins = {\n'
                        .. '        {\n'
                        .. '            name = "Nekoark",\n'
                        .. '            headImage = "image/Charactor/Nekoark/head_neko.png",\n'
                        .. '            torsoImage = "image/Charactor/Nekoark/body_neko.png",\n'
                        .. '            armColor = "#FFFFFFFF",\n'
                        .. '            handColor = "#F5D2AAFF",\n'
                        .. '            legColor = "#32323CFF",\n'
                        .. '            shoeColor = "#50505AFF",\n'
                        .. '            headTransform = { scale = %.1f, offsetX = %g, offsetY = %g, rotation = %g },\n'
                        .. '            torsoTransform = { scale = %.1f, offsetX = %g, offsetY = %g, rotation = %g },\n'
                        .. '        },\n'
                        .. '    }\n'
                        .. '}\n',
                        ht.scale, ht.offsetX, ht.offsetY, ht.rotation,
                        tt.scale, tt.offsetX, tt.offsetY, tt.rotation
                    )
                    ShowExportPopup(content)
                end
            },
        }
    }
    skinEditorPanel_:SetVisible(false)

    -- 挂载到 UI 根节点
    local root = UI.FindById("root")
    if root then
        root:AddChild(skinEditorPanel_)
    end
end

-- 导出弹窗（显示可复制的文本）
local exportPopup_ = nil

function ShowExportPopup(content)
    -- 关闭已有弹窗
    if exportPopup_ then
        exportPopup_:Remove()
        exportPopup_ = nil
    end

    exportPopup_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = {0, 0, 0, 180},
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 420, maxHeight = "80%",
                backgroundColor = {30, 30, 40, 250},
                borderRadius = 10,
                padding = 16,
                gap = 10,
                children = {
                    UI.Label { text = "配置内容（全选复制）", fontSize = 14, fontColor = {255, 220, 100, 255} },
                    UI.ScrollView {
                        width = "100%",
                        height = 260,
                        children = {
                            UI.Label {
                                text = content,
                                fontSize = 11,
                                fontColor = {220, 220, 220, 255},
                                fontFamily = "monospace",
                                selectable = true,
                            },
                        }
                    },
                    UI.Button {
                        text = "关闭", variant = "outline", height = 30,
                        onClick = function()
                            if exportPopup_ then
                                exportPopup_:Remove()
                                exportPopup_ = nil
                            end
                        end
                    },
                }
            }
        }
    }

    local root = UI.FindById("root")
    if root then
        root:AddChild(exportPopup_)
    end
end

function ToggleSkinEditor()
    if skinEditorPanel_ == nil then return end
    skinEditorOpen_ = not skinEditorOpen_
    skinEditorPanel_:SetVisible(skinEditorOpen_)
    print("[SkinEditor] " .. (skinEditorOpen_ and "打开" or "关闭"))
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
    -- Contain策略: 确保19.2x10.8设计区域始终完整可见并居中
    camera.orthoSize = CalcContainOrthoSize()
    cameraNode_.position = Vector3(0, 0, -10)

    renderer:SetViewport(0, Viewport:new(scene_, camera))
end

--- 计算Contain策略下的orthoSize
--- 设计区域19.2x10.8(16:9)始终完整可见，居中显示，多余部分留空
function CalcContainOrthoSize()
    local sw = graphics:GetWidth()
    local sh = graphics:GetHeight()
    if sw <= 0 or sh <= 0 then return CONFIG.OrthoSize end

    local screenAspect = sw / sh
    local designAspect = CONFIG.MapWidth / CONFIG.MapHeight  -- 16/9 ≈ 1.778

    if screenAspect >= designAspect then
        -- 屏幕更宽(或刚好16:9): 高度适配，两侧留空
        return CONFIG.MapHeight  -- 10.8
    else
        -- 屏幕更高: 宽度适配，上下留空
        return CONFIG.MapWidth / screenAspect
    end
end

-- ============================================================================
-- 创建世界(地面+平台)
-- ============================================================================
function CreateWorld()
    -- 地面（高度0.8，底部贴屏幕底-5.4）
    local groundHeight = 0.8
    local groundNode = scene_:CreateChild("Ground")
    groundNode:SetPosition2D(0, CONFIG.GroundY)
    local groundBody = groundNode:CreateComponent("RigidBody2D")
    groundBody.bodyType = BT_STATIC
    local groundShape = groundNode:CreateComponent("CollisionBox2D")
    groundShape:SetSize(CONFIG.MapWidth + 2, groundHeight)
    groundShape.friction = 0.3
    groundShape.restitution = 0.0
    groundShape.categoryBits = 1
    table.insert(platforms_, {x=0, y=CONFIG.GroundY, width=CONFIG.MapWidth+2, height=groundHeight})

    -- 平台（根据设计图 1920x1080 布局，视野 19.2x10.8）
    -- 地面顶部 Y=-4.6，屏幕顶部 Y=+5.4
    local platformData = {
        -- 左下
        {x = -7.0, y = -3.2, width = 2.6, height = 0.35},
        -- 左中
        {x = -4.5, y = -0.8, width = 2.4, height = 0.35},
        -- 中下
        {x = -1.2, y = -2.0, width = 2.4, height = 0.35},
        -- 中间（偏上）
        {x =  1.2, y =  0.8, width = 2.8, height = 0.35},
        -- 中右下
        {x =  3.5, y = -3.0, width = 2.8, height = 0.35},
        -- 右中
        {x =  5.2, y = -0.5, width = 2.4, height = 0.35},
        -- 右下
        {x =  7.8, y = -1.8, width = 3.0, height = 0.35},
        -- 上方（偏右）
        {x =  4.5, y =  3.2, width = 1.8, height = 0.35},
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

    -- 使用Contain策略保持设计区域完整可见并居中
    local camera = cameraNode_:GetComponent("Camera")
    camera.orthoSize = CalcContainOrthoSize()
    cameraNode_.position = Vector3(0, 0, -10)

    -- Tab 切换皮肤编辑器
    if input:GetKeyPress(KEY_TAB) then
        ToggleSkinEditor()
    end

    if gameOver_ then
        -- R 键重启
        if input:GetKeyPress(KEY_R) then
            RestartGame()
        end
        return
    end

    -- 只有 countdown 阶段玩家可以移动
    if gameState_ == "countdown" then
        UpdatePlayers(dt)
    end

    -- 公告板阶段处理确认输入
    if gameState_ == "bulletin" and bulletin_.animPhase == "stay" then
        UpdateBulletinConfirm()
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

function UpdateBulletinConfirm()
    for i, p in ipairs(players_) do
        if not bulletin_.confirmed[i] then
            if input:GetKeyPress(p.config.keys.jump) then
                bulletin_.confirmed[i] = true
                print(p.config.name .. " 已确认准备")
            end
        end
    end

    -- 检查是否全员确认
    local allConfirmed = true
    for i = 1, #PLAYERS do
        if not bulletin_.confirmed[i] then
            allConfirmed = false
            break
        end
    end

    if allConfirmed then
        -- 全员确认，开始收起动画
        bulletin_.animPhase = "exit"
        bulletin_.animTimer = 0
    end
end

function UpdateGameState(dt)
    if gameState_ == "bulletin" then
        bulletin_.animTimer = bulletin_.animTimer + dt

        if bulletin_.animPhase == "enter" then
            -- 弹入动画播放完毕 → 进入等待确认
            if bulletin_.animTimer >= bulletin_.enterDuration then
                bulletin_.animPhase = "stay"
                bulletin_.animTimer = 0
            end
        elseif bulletin_.animPhase == "exit" then
            -- 收起动画播放完毕 → 进入游戏
            if bulletin_.animTimer >= bulletin_.exitDuration then
                -- 公告板结束，开始本关游戏
                SpawnPhotoZone()
                gameState_ = "countdown"
                countdown_ = CONFIG.CountdownTime
            end
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
            showPhotoTimer_ = 2.5  -- 展示照片2.5秒
        end

    elseif gameState_ == "showPhoto" then
        showPhotoTimer_ = showPhotoTimer_ - dt
        if showPhotoTimer_ <= 0 then
            photoZone_.active = false
            -- 进入下一关公告板
            StartNextBulletin()
        end
    end
end

function StartNextBulletin()
    bulletin_.round = bulletin_.round + 1
    bulletin_.confirmed = {}
    for i = 1, #PLAYERS do
        bulletin_.confirmed[i] = false
    end
    bulletin_.animPhase = "enter"
    bulletin_.animTimer = 0
    gameState_ = "bulletin"
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
            onGround = p.onGround,
            isMoving = p.isMoving,
            animTime = p.animTime,
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
    photoZone_.active = false
    roundResult_ = {}

    for i, p in ipairs(players_) do
        p.score = 0
        p.node:SetPosition2D(p.config.spawnX, CONFIG.GroundY + 2)
        p.body.linearVelocity = Vector2(0, 0)
    end
    UpdateScoreUI()

    -- 重置公告板，从第 1 关开始
    bulletin_.round = 0  -- StartNextBulletin 会 +1
    StartNextBulletin()
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
    DrawBulletin()
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
    if gameState_ == "showPhoto" then return end  -- 展示照片时不绘制标记

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

--- 绘制单个玩家（共享函数）
--- @param params table {sx, sy, color, skin, skinIdx, facing, limbSwing, armSwing, inAir, isMoving, onGround, velY, name}
function DrawSinglePlayer(params)
    local ppu = GetPixelsPerUnit()
    local r = CONFIG.PlayerRadius * ppu
    local sx, sy = params.sx, params.sy
    local c = params.color
    local skin = params.skin
    local facing = params.facing
    local limbSwing = params.limbSwing
    local armSwing = params.armSwing
    local inAir = params.inAir
    local isMoving = params.isMoving
    local onGround = params.onGround
    local velY = params.velY or 0
    local name = params.name

    -- 部件尺寸（基于文档比例，r=20px 基准）
    local headR = r * 0.75
    local torsoW = r * 1.8
    local torsoH = r * 2.0
    local armW = r * 0.28
    local armH = r * 0.85
    local handR = r * 0.17
    local legW = r * 0.32
    local legH = r * 0.9
    local shoeW = r * 0.45
    local shoeH = r * 0.26

    -- 身体中心偏移
    local torsoY = sy
    local headY = torsoY - torsoH * 0.35 - headR
    local hipY = torsoY + torsoH * 0.45

    if skin then
        local ac = skin.armColor
        local hc = skin.handColor
        local lc = skin.legColor
        local sc = skin.shoeColor

        -- ========== 1. 腿部 + 鞋子（最底层）==========
        local legSpacing = torsoW * 0.22
        for side = -1, 1, 2 do
            local legAngle = side == -1 and limbSwing or -limbSwing
            local legCX = sx + side * legSpacing

            nvgSave(nvg_)
            nvgTranslate(nvg_, legCX, hipY)
            nvgRotate(nvg_, legAngle)

            nvgBeginPath(nvg_)
            nvgRoundedRect(nvg_, -legW / 2, 0, legW, legH, legW * 0.3)
            nvgFillColor(nvg_, nvgRGBA(lc[1], lc[2], lc[3], lc[4]))
            nvgFill(nvg_)

            nvgBeginPath(nvg_)
            nvgRoundedRect(nvg_, -shoeW / 2, legH - shoeH * 0.3, shoeW, shoeH, shoeH * 0.3)
            nvgFillColor(nvg_, nvgRGBA(sc[1], sc[2], sc[3], sc[4]))
            nvgFill(nvg_)

            nvgRestore(nvg_)
        end

        -- ========== 2. 躯干（图片，圆角矩形裁剪）==========
        local tt = skin.torsoTransform
        nvgSave(nvg_)
        nvgTranslate(nvg_, sx + tt.offsetX, torsoY + tt.offsetY)
        nvgRotate(nvg_, math.rad(tt.rotation))
        nvgScale(nvg_, tt.scale, tt.scale)

        local halfTW = torsoW / 2
        local halfTH = torsoH / 2
        local cornerR = torsoW * 0.15

        if skin.torsoImg > 0 then
            nvgBeginPath(nvg_)
            nvgRoundedRect(nvg_, -halfTW, -halfTH, torsoW, torsoH, cornerR)
            local imgPaint
            if facing < 0 then
                imgPaint = nvgImagePattern(nvg_, halfTW, -halfTH, -torsoW, torsoH, 0, skin.torsoImg, 1.0)
            else
                imgPaint = nvgImagePattern(nvg_, -halfTW, -halfTH, torsoW, torsoH, 0, skin.torsoImg, 1.0)
            end
            nvgFillPaint(nvg_, imgPaint)
            nvgFill(nvg_)
        else
            nvgBeginPath(nvg_)
            nvgRoundedRect(nvg_, -halfTW, -halfTH, torsoW, torsoH, cornerR)
            nvgFillColor(nvg_, nvgRGBA(ac[1], ac[2], ac[3], ac[4]))
            nvgFill(nvg_)
        end
        nvgRestore(nvg_)

        -- ========== 3. 手臂 + 手掌 ==========
        local shoulderY = torsoY - torsoH * 0.3
        local armOffsetX = torsoW / 2 + armW * 0.3
        for side = -1, 1, 2 do
            local armAngle = side == -1 and armSwing or -armSwing
            local armCX = sx + side * armOffsetX

            nvgSave(nvg_)
            nvgTranslate(nvg_, armCX, shoulderY)
            nvgRotate(nvg_, armAngle)

            nvgBeginPath(nvg_)
            nvgRoundedRect(nvg_, -armW / 2, 0, armW, armH, armW * 0.4)
            nvgFillColor(nvg_, nvgRGBA(ac[1], ac[2], ac[3], ac[4]))
            nvgFill(nvg_)

            nvgBeginPath(nvg_)
            nvgCircle(nvg_, 0, armH + handR * 0.5, handR)
            nvgFillColor(nvg_, nvgRGBA(hc[1], hc[2], hc[3], hc[4]))
            nvgFill(nvg_)

            nvgRestore(nvg_)
        end

        -- ========== 4. 头部（图片，圆形裁剪）==========
        local ht = skin.headTransform
        nvgSave(nvg_)
        nvgTranslate(nvg_, sx + ht.offsetX, headY + ht.offsetY)
        nvgRotate(nvg_, math.rad(ht.rotation))
        nvgScale(nvg_, ht.scale, ht.scale)

        if skin.headImg > 0 then
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, 0, 0, headR)
            local headImgPaint
            if facing < 0 then
                headImgPaint = nvgImagePattern(nvg_, headR, -headR, -headR * 2, headR * 2, 0, skin.headImg, 1.0)
            else
                headImgPaint = nvgImagePattern(nvg_, -headR, -headR, headR * 2, headR * 2, 0, skin.headImg, 1.0)
            end
            nvgFillPaint(nvg_, headImgPaint)
            nvgFill(nvg_)
        else
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, 0, 0, headR)
            nvgFillColor(nvg_, nvgRGBA(hc[1], hc[2], hc[3], hc[4]))
            nvgFill(nvg_)
        end
        nvgRestore(nvg_)

    else
        -- ========== 无皮肤回退：简单圆形 ==========
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, sx, sy, r)
        nvgFillColor(nvg_, nvgRGBA(c[1], c[2], c[3], c[4]))
        nvgFill(nvg_)
    end

    -- ========== 速度线效果 ==========
    if isMoving and onGround then
        local lineDir = -facing
        for l = 1, 3 do
            local lx = sx + lineDir * (torsoW / 2 + 4 + l * 5)
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

    -- ========== 跳跃气流效果 ==========
    if inAir and velY > 2 then
        for l = 1, 3 do
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, sx - 6 + l * 6, hipY + legH + 8 + l * 4, 2 - l * 0.4)
            nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 120 - l * 30))
            nvgFill(nvg_)
        end
    end

    -- ========== 名字标签 ==========
    nvgFontSize(nvg_, 14)
    nvgFontFace(nvg_, "sans")
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(nvg_, nvgRGBA(c[1], c[2], c[3], 255))
    local nameY = skin and (headY - headR - 6) or (sy - r - 10)
    nvgText(nvg_, sx, nameY, name, nil)
end

function DrawPlayers()
    for i, p in ipairs(players_) do
        local pos = p.node.position2D
        local sx, sy = PhysToScreen(pos.x, pos.y)
        local skinIdx = p.config.skinIndex or 1
        local skin = skinsRuntime_[skinIdx]

        -- 计算动画参数
        local limbSwing = 0
        local armSwing = 0
        local inAir = not p.onGround
        if inAir then
            limbSwing = 0.35
            armSwing = -0.4
        elseif p.isMoving then
            limbSwing = math.sin(p.animTime) * 0.5
            armSwing = -math.sin(p.animTime) * 0.4
        end

        DrawSinglePlayer({
            sx = sx, sy = sy,
            color = p.config.color,
            skin = skin,
            facing = p.facing,
            limbSwing = limbSwing,
            armSwing = armSwing,
            inAir = inAir,
            isMoving = p.isMoving,
            onGround = p.onGround,
            velY = p.velY or 0,
            name = p.config.name,
        })
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

    -- 淡入动画（0.3秒淡入）
    local progress = math.min(1.0, (2.5 - showPhotoTimer_) / 0.3)

    nvgSave(nvg_)

    -- 1) 全屏半透明黑色遮罩
    local maskAlpha = math.floor(200 * progress)
    nvgBeginPath(nvg_)
    nvgRect(nvg_, 0, 0, screenW_, screenH_)
    nvgFillColor(nvg_, nvgRGBA(0, 0, 0, maskAlpha))
    nvgFill(nvg_)

    -- 2) 计算拍立得照片展示区域（拍照区域的宽高比）
    local zoneAspect = photoZone_.width / photoZone_.height

    -- 照片最大占屏幕 65% 宽、50% 高
    local maxPhotoW = screenW_ * 0.65
    local maxPhotoH = screenH_ * 0.50
    local photoW, photoH

    if maxPhotoW / zoneAspect <= maxPhotoH then
        photoW = maxPhotoW
        photoH = maxPhotoW / zoneAspect
    else
        photoH = maxPhotoH
        photoW = maxPhotoH * zoneAspect
    end

    -- 拍立得相框：上/左/右白边等宽，下方白边更大（放文字）
    local framePad = math.floor(photoW * 0.05)
    local frameBottom = math.floor(photoH * 0.25)

    local totalW = photoW + framePad * 2
    local totalH = photoH + framePad + frameBottom

    -- 居中定位（稍偏上）
    local frameX = (screenW_ - totalW) / 2
    local frameY = (screenH_ - totalH) / 2 - screenH_ * 0.03

    -- 弹入动画（从稍下方弹起）
    local offsetY = (1.0 - progress) * 40
    frameY = frameY + offsetY

    -- 3) 相框阴影
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, frameX + 4, frameY + 5, totalW, totalH, 5)
    nvgFillColor(nvg_, nvgRGBA(0, 0, 0, math.floor(80 * progress)))
    nvgFill(nvg_)

    -- 4) 绘制白色相框背景（拍立得风格）
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, frameX, frameY, totalW, totalH, 5)
    nvgFillColor(nvg_, nvgRGBA(255, 255, 255, math.floor(250 * progress)))
    nvgFill(nvg_)

    -- 5) 在相框内绘制游戏快照（裁剪到照片区域）
    local photoX = frameX + framePad
    local photoY = frameY + framePad

    -- 使用 scissor 裁剪到照片区域
    nvgScissor(nvg_, photoX, photoY, photoW, photoH)

    -- 计算缩放：将拍照区域（世界坐标）映射到照片像素区域
    -- 拍照区域中心的屏幕坐标
    local zoneCenterSX, zoneCenterSY = PhysToScreen(photoZone_.x, photoZone_.y)
    -- 拍照区域在当前屏幕上的像素尺寸
    local ppu = GetPixelsPerUnit()
    local zoneScreenW = photoZone_.width * ppu
    local zoneScreenH = photoZone_.height * ppu

    -- 缩放比例：将拍照区域屏幕尺寸映射到照片尺寸
    local scaleX = photoW / zoneScreenW
    local scaleY = photoH / zoneScreenH
    local scale = math.min(scaleX, scaleY)

    -- 变换：先平移使拍照区域中心对齐照片中心，再缩放
    local photoCenterX = photoX + photoW / 2
    local photoCenterY = photoY + photoH / 2

    nvgSave(nvg_)
    nvgTranslate(nvg_, photoCenterX, photoCenterY)
    nvgScale(nvg_, scale, scale)
    nvgTranslate(nvg_, -zoneCenterSX, -zoneCenterSY)

    -- 重绘背景
    DrawBackground()
    -- 重绘平台
    DrawPlatforms()

    -- 绘制拍照区域边框（固定alpha，不闪烁）
    local zsx, zsy = PhysToScreen(photoZone_.x, photoZone_.y)
    local zpw = photoZone_.width * ppu
    local zph = photoZone_.height * ppu
    nvgBeginPath(nvg_)
    nvgRect(nvg_, zsx - zpw/2, zsy - zph/2, zpw, zph)
    nvgFillColor(nvg_, nvgRGBA(255, 220, 50, 30))
    nvgFill(nvg_)
    nvgBeginPath(nvg_)
    nvgRect(nvg_, zsx - zpw/2, zsy - zph/2, zpw, zph)
    nvgStrokeColor(nvg_, nvgRGBA(255, 220, 50, 160))
    nvgStrokeWidth(nvg_, 3)
    nvgStroke(nvg_)

    -- 绘制快照中的玩家（使用保存的位置）
    DrawPlayersSnapshot()

    nvgRestore(nvg_)
    -- 取消 scissor
    nvgResetScissor(nvg_)

    -- 6) 照片内暗角效果
    local vigAlpha = math.floor(40 * progress)
    nvgBeginPath(nvg_)
    nvgRect(nvg_, photoX, photoY, photoW, photoH * 0.15)
    local topVig = nvgLinearGradient(nvg_, photoX, photoY, photoX, photoY + photoH * 0.15,
        nvgRGBA(0, 0, 0, vigAlpha), nvgRGBA(0, 0, 0, 0))
    nvgFillPaint(nvg_, topVig)
    nvgFill(nvg_)

    nvgBeginPath(nvg_)
    nvgRect(nvg_, photoX, photoY + photoH * 0.85, photoW, photoH * 0.15)
    local botVig = nvgLinearGradient(nvg_, photoX, photoY + photoH * 0.85, photoX, photoY + photoH,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, vigAlpha))
    nvgFillPaint(nvg_, botVig)
    nvgFill(nvg_)

    -- 7) 底部结果文字（在拍立得白色区域内）
    local textY = photoY + photoH + frameBottom * 0.5
    nvgFontSize(nvg_, math.max(18, math.floor(frameBottom * 0.35)))
    nvgFontFace(nvg_, "sans")
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if #roundResult_ > 0 then
        local names = {}
        for _, idx in ipairs(roundResult_) do
            table.insert(names, players_[idx].config.name)
        end
        nvgFillColor(nvg_, nvgRGBA(40, 160, 60, math.floor(255 * progress)))
        nvgText(nvg_, screenW_ / 2, textY, table.concat(names, " & ") .. " 入镜! +1", nil)
    else
        nvgFillColor(nvg_, nvgRGBA(200, 80, 80, math.floor(255 * progress)))
        nvgText(nvg_, screenW_ / 2, textY, "没人入镜!", nil)
    end

    -- 8) 顶部 "PHOTO" 标签
    nvgFontSize(nvg_, 13)
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(nvg_, nvgRGBA(255, 255, 255, math.floor(180 * progress)))
    nvgText(nvg_, screenW_ / 2, frameY - 6, "PHOTO", nil)

    nvgRestore(nvg_)
end

--- 绘制快照中的玩家（使用保存的位置而非实时位置）
function DrawPlayersSnapshot()
    for i, snap in ipairs(photoSnapshot_) do
        local p = players_[i]
        if not p then break end

        local sx, sy = PhysToScreen(snap.x, snap.y)
        local skinIdx = p.config.skinIndex or 1
        local skin = skinsRuntime_[skinIdx]

        -- 使用保存的动画状态还原拍照瞬间的姿态
        local limbSwing = 0
        local armSwing = 0
        local inAir = not snap.onGround

        if inAir then
            limbSwing = 0.35
            armSwing = -0.4
        elseif snap.isMoving then
            limbSwing = math.sin(snap.animTime) * 0.5
            armSwing = -math.sin(snap.animTime) * 0.4
        end

        DrawSinglePlayer({
            sx = sx, sy = sy,
            color = p.config.color,
            skin = skin,
            facing = snap.facing,
            limbSwing = limbSwing,
            armSwing = armSwing,
            inAir = inAir,
            isMoving = snap.isMoving,
            onGround = snap.onGround,
            velY = 0,
            name = p.config.name,
        })
    end
end

function DrawBulletin()
    if gameState_ ~= "bulletin" then return end

    -- 计算动画进度 (0~1)
    local progress = 0
    if bulletin_.animPhase == "enter" then
        progress = math.min(1.0, bulletin_.animTimer / bulletin_.enterDuration)
    elseif bulletin_.animPhase == "stay" then
        progress = 1.0
    elseif bulletin_.animPhase == "exit" then
        progress = 1.0 - math.min(1.0, bulletin_.animTimer / bulletin_.exitDuration)
    end

    -- easeOutBack 缓动（弹入时有弹性感）
    local function easeOutBack(t)
        local c1 = 1.70158
        local c3 = c1 + 1
        return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
    end

    -- 弹入用 easeOutBack，收起用加速
    local displayProgress
    if bulletin_.animPhase == "enter" then
        displayProgress = easeOutBack(progress)
    elseif bulletin_.animPhase == "exit" then
        displayProgress = progress * progress  -- easeIn (加速收起)
    else
        displayProgress = 1.0
    end

    -- 半透明背景遮罩
    local maskAlpha = math.floor(140 * displayProgress)
    nvgBeginPath(nvg_)
    nvgRect(nvg_, 0, 0, screenW_, screenH_)
    nvgFillColor(nvg_, nvgRGBA(0, 0, 0, maskAlpha))
    nvgFill(nvg_)

    -- 公告板尺寸
    local boardW = math.min(480, screenW_ * 0.7)
    local boardH = math.min(320, screenH_ * 0.6)
    local boardX = (screenW_ - boardW) / 2
    -- 从上方滑入：初始位置在屏幕上方外面
    local targetY = (screenH_ - boardH) / 2
    local startY = -boardH - 20
    local boardY = startY + (targetY - startY) * displayProgress

    nvgSave(nvg_)

    -- 公告板阴影
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, boardX + 4, boardY + 6, boardW, boardH, 16)
    nvgFillColor(nvg_, nvgRGBA(0, 0, 0, math.floor(80 * displayProgress)))
    nvgFill(nvg_)

    -- 公告板主体（深色背景+圆角）
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, boardX, boardY, boardW, boardH, 16)
    local boardGrad = nvgLinearGradient(nvg_, boardX, boardY, boardX, boardY + boardH,
        nvgRGBA(45, 55, 75, 250), nvgRGBA(30, 38, 55, 250))
    nvgFillPaint(nvg_, boardGrad)
    nvgFill(nvg_)

    -- 边框
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, boardX, boardY, boardW, boardH, 16)
    nvgStrokeColor(nvg_, nvgRGBA(100, 160, 255, math.floor(180 * displayProgress)))
    nvgStrokeWidth(nvg_, 2)
    nvgStroke(nvg_)

    -- 顶部标题栏背景
    local titleBarH = 50
    nvgBeginPath(nvg_)
    -- 顶部两个圆角，底部直角（用 clip 模拟）
    nvgRoundedRect(nvg_, boardX, boardY, boardW, titleBarH, 16)
    nvgFillColor(nvg_, nvgRGBA(60, 120, 220, math.floor(200 * displayProgress)))
    nvgFill(nvg_)
    -- 底部覆盖掉圆角
    nvgBeginPath(nvg_)
    nvgRect(nvg_, boardX, boardY + titleBarH - 16, boardW, 16)
    nvgFillColor(nvg_, nvgRGBA(60, 120, 220, math.floor(200 * displayProgress)))
    nvgFill(nvg_)

    -- 标题文字: "第 X 关"
    nvgFontSize(nvg_, 26)
    nvgFontFace(nvg_, "sans")
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg_, nvgRGBA(255, 255, 255, math.floor(255 * displayProgress)))
    nvgText(nvg_, screenW_ / 2, boardY + titleBarH / 2, "第 " .. bulletin_.round .. " 关", nil)

    -- 玩法说明文字
    local descIdx = ((bulletin_.round - 1) % #ROUND_DESCRIPTIONS) + 1
    local desc = ROUND_DESCRIPTIONS[descIdx]
    nvgFontSize(nvg_, 20)
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg_, nvgRGBA(230, 230, 240, math.floor(240 * displayProgress)))
    nvgText(nvg_, screenW_ / 2, boardY + titleBarH + 45, desc, nil)

    -- 玩家头像区域
    local avatarY = boardY + titleBarH + 100
    local avatarSpacing = boardW / (#PLAYERS + 1)
    local avatarR = 28

    for i, pdata in ipairs(PLAYERS) do
        local ax = boardX + avatarSpacing * i
        local ay = avatarY
        local c = pdata.color

        -- 头像圆圈背景
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, ax, ay, avatarR)
        local avatarGrad = nvgRadialGradient(nvg_, ax - 4, ay - 4, 2, avatarR,
            nvgRGBA(math.min(255, c[1] + 60), math.min(255, c[2] + 60), math.min(255, c[3] + 60), 255),
            nvgRGBA(c[1], c[2], c[3], 255))
        nvgFillPaint(nvg_, avatarGrad)
        nvgFill(nvg_)

        -- 头像边框
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, ax, ay, avatarR)
        nvgStrokeColor(nvg_, nvgRGBA(255, 255, 255, 150))
        nvgStrokeWidth(nvg_, 2)
        nvgStroke(nvg_)

        -- 头像里的眼睛
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, ax - 7, ay - 5, 4)
        nvgCircle(nvg_, ax + 7, ay - 5, 4)
        nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 255))
        nvgFill(nvg_)
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, ax - 6, ay - 4, 2)
        nvgCircle(nvg_, ax + 8, ay - 4, 2)
        nvgFillColor(nvg_, nvgRGBA(0, 0, 0, 255))
        nvgFill(nvg_)

        -- 微笑
        nvgBeginPath(nvg_)
        nvgArc(nvg_, ax, ay + 6, 6, 0.2, math.pi - 0.2, NVG_CW)
        nvgStrokeColor(nvg_, nvgRGBA(0, 0, 0, 200))
        nvgStrokeWidth(nvg_, 2)
        nvgStroke(nvg_)

        -- 名字
        nvgFontSize(nvg_, 14)
        nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(nvg_, nvgRGBA(c[1], c[2], c[3], math.floor(255 * displayProgress)))
        nvgText(nvg_, ax, ay + avatarR + 6, pdata.name, nil)

        -- 对勾（如果已确认）
        if bulletin_.confirmed[i] then
            -- 绿色对勾圆圈
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, ax + avatarR * 0.65, ay - avatarR * 0.65, 12)
            nvgFillColor(nvg_, nvgRGBA(40, 200, 80, 255))
            nvgFill(nvg_)
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, ax + avatarR * 0.65, ay - avatarR * 0.65, 12)
            nvgStrokeColor(nvg_, nvgRGBA(255, 255, 255, 255))
            nvgStrokeWidth(nvg_, 2)
            nvgStroke(nvg_)

            -- 绘制对勾 ✓
            local cx = ax + avatarR * 0.65
            local cy = ay - avatarR * 0.65
            nvgBeginPath(nvg_)
            nvgMoveTo(nvg_, cx - 5, cy)
            nvgLineTo(nvg_, cx - 1, cy + 4)
            nvgLineTo(nvg_, cx + 6, cy - 4)
            nvgStrokeColor(nvg_, nvgRGBA(255, 255, 255, 255))
            nvgStrokeWidth(nvg_, 2.5)
            nvgLineCap(nvg_, NVG_ROUND)
            nvgLineJoin(nvg_, NVG_ROUND)
            nvgStroke(nvg_)
        end
    end

    -- 底部提示文字
    local hintY = boardY + boardH - 35
    local hintAlpha = math.floor((math.sin(os.clock() * 3) * 0.3 + 0.7) * 255 * displayProgress)
    nvgFontSize(nvg_, 15)
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg_, nvgRGBA(180, 200, 255, hintAlpha))
    nvgText(nvg_, screenW_ / 2, hintY, "按 [跳跃键] 表示已理解规则", nil)

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
