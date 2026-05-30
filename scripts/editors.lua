-- ============================================================================
-- editors.lua - 编辑器系统（皮肤编辑器 + 地形编辑器）
-- 提供开发时的可视化编辑工具，Tab 键切换
-- ============================================================================

local Cfg = require("config")
local UI = require("urhox-libs/UI")

local M = {}

-- ============================================================================
-- 编辑器状态
-- ============================================================================
M.skinEditorOpen = false
M.terrainEditorOpen = false
M.gameplayGMOpen = false
M.editorMenuOpen = false
M.skinEditorAnimTime = 0  -- 预览动画计时器
M.gmForceGameplay = nil   -- 强制玩法索引（生效一次后自动清除）

-- 内部状态
local skinEditorPanel_ = nil
local editorMenuPanel_ = nil
local terrainEditorPanel_ = nil
local gameplayGMPanel_ = nil
local gameplayGMButtons_ = {}  -- 玩法按钮引用列表
local exportPopup_ = nil

-- 地形编辑器拖拽状态
local terrainSelected_ = nil      -- 选中的平台索引
local terrainDragMode_ = "none"   -- "none", "move", "left", "right", "top", "bottom"
local terrainDragStart_ = {sx = 0, sy = 0}
local terrainDragOrigin_ = {x = 0, y = 0, width = 0, height = 0}
local terrainMouseDown_ = false

-- 外部依赖引用（Init 时设置）
local G = nil  -- 共享游戏状态: nvg, screenW, screenH, platforms, skinsRuntime, playerScale, capsuleRadius, capsuleHeight, cameraNode
local Render = nil  -- render 模块引用（用于 PhysToScreen/GetPixelsPerUnit）

function M.Init(gameState, renderModule)
    G = gameState
    Render = renderModule
end

-- ============================================================================
-- 编辑器菜单
-- ============================================================================

--- Tab 键统一入口
function M.ToggleEditorMenu()
    -- 如果有编辑器正在打开 → 关闭它
    if M.terrainEditorOpen then
        M.ToggleTerrainEditor()
        return
    end
    if M.skinEditorOpen then
        M.ToggleSkinEditor()
        return
    end
    if M.gameplayGMOpen then
        M.ToggleGameplayGM()
        return
    end

    -- 否则切换编辑器选择菜单
    M.editorMenuOpen = not M.editorMenuOpen
    if editorMenuPanel_ then
        editorMenuPanel_:SetVisible(M.editorMenuOpen)
    end
end

function M.CreateEditorMenu()
    editorMenuPanel_ = UI.Panel {
        id = "editorMenu",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = {0, 0, 0, 160},
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 260,
                backgroundColor = {30, 35, 50, 240},
                borderRadius = 12,
                padding = 20,
                gap = 12,
                alignItems = "center",
                children = {
                    UI.Label { text = "编辑器", fontSize = 18, fontColor = {255, 255, 255, 255} },
                    UI.Label { text = "选择要打开的编辑器 (Tab 关闭)", fontSize = 11, fontColor = {160, 160, 160, 255} },
                    UI.Button {
                        text = "地形编辑器", variant = "primary", width = "100%", height = 38,
                        onClick = function()
                            M.editorMenuOpen = false
                            editorMenuPanel_:SetVisible(false)
                            M.ToggleTerrainEditor()
                        end
                    },
                    UI.Button {
                        text = "皮肤编辑器", variant = "outline", width = "100%", height = 38,
                        onClick = function()
                            M.editorMenuOpen = false
                            editorMenuPanel_:SetVisible(false)
                            M.ToggleSkinEditor()
                        end
                    },
                    UI.Button {
                        text = "玩法 GM", variant = "outline", width = "100%", height = 38,
                        onClick = function()
                            M.editorMenuOpen = false
                            editorMenuPanel_:SetVisible(false)
                            M.ToggleGameplayGM()
                        end
                    },
                }
            }
        }
    }
    editorMenuPanel_:SetVisible(false)

    local root = UI.FindById("root")
    if root then
        root:AddChild(editorMenuPanel_)
    end
end

-- ============================================================================
-- 皮肤编辑器
-- ============================================================================

function M.ToggleSkinEditor()
    if skinEditorPanel_ == nil then return end
    M.skinEditorOpen = not M.skinEditorOpen
    skinEditorPanel_:SetVisible(M.skinEditorOpen)
end

function M.CreateSkinEditor()
    if not G.skinsRuntime or #G.skinsRuntime == 0 then return end
    local skin = G.skinsRuntime[1]  -- 编辑第一套皮肤

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

    local function syncTransformToAll()
        for i = 2, #G.skinsRuntime do
            G.skinsRuntime[i].headTransform = skin.headTransform
            G.skinsRuntime[i].torsoTransform = skin.torsoTransform
            G.skinsRuntime[i].armTransform = skin.armTransform
            G.skinsRuntime[i].legTransform = skin.legTransform
        end
    end

    local function updateVal(label, v)
        local lbl = UI.FindById("val_" .. label)
        if lbl then lbl:SetText(string.format("%.1f", v)) end
    end

    skinEditorPanel_ = UI.Panel {
        id = "skinEditor",
        position = "absolute",
        top = 10, right = 10,
        width = 420,
        maxHeight = "90%",
        backgroundColor = {20, 20, 30, 230},
        borderRadius = 10,
        padding = 12,
        gap = 6,
        children = {
            UI.Label { text = "Skin Editor (Tab 关闭)", fontSize = 14, fontColor = {255, 220, 100, 255} },
            UI.ScrollView {
                width = "100%", height = 400,
                children = {
                    UI.Panel {
                        flexDirection = "row", gap = 16, width = "100%",
                        children = {
                            -- ===== 左列：角色 + 头部 + 手臂 + 腿部 =====
                            UI.Panel {
                                flex = 1, gap = 4,
                                children = {
                                    UI.Label { text = "-- 角色 --", fontSize = 11, fontColor = {140, 140, 140, 255} },
                                    MakeSlider("P.Scale", 0.5, 2.0, G.playerScale, 0.1, function(self, v)
                                        G.playerScale = v; updateVal("P.Scale", v)
                                    end),
                                    MakeSlider("Cap.R", 0.1, 0.8, G.capsuleRadius, 0.05, function(self, v)
                                        G.capsuleRadius = v; updateVal("Cap.R", v)
                                    end),
                                    MakeSlider("Cap.H", 0.4, 2.0, G.capsuleHeight, 0.05, function(self, v)
                                        G.capsuleHeight = v; updateVal("Cap.H", v)
                                    end),
                                    UI.Label { text = "-- 头部 --", fontSize = 11, fontColor = {140, 140, 140, 255} },
                                    MakeSlider("H.Scale", 0.2, 3.0, skin.headTransform.scale, 0.1, function(self, v)
                                        skin.headTransform.scale = v; syncTransformToAll(); updateVal("H.Scale", v)
                                    end),
                                    MakeSlider("H.OffX", -30, 30, skin.headTransform.offsetX, 1, function(self, v)
                                        skin.headTransform.offsetX = v; syncTransformToAll(); updateVal("H.OffX", v)
                                    end),
                                    MakeSlider("H.OffY", -30, 30, skin.headTransform.offsetY, 1, function(self, v)
                                        skin.headTransform.offsetY = v; syncTransformToAll(); updateVal("H.OffY", v)
                                    end),
                                    MakeSlider("H.Rot", -180, 180, skin.headTransform.rotation, 1, function(self, v)
                                        skin.headTransform.rotation = v; syncTransformToAll(); updateVal("H.Rot", v)
                                    end),
                                    UI.Label { text = "-- 手臂 --", fontSize = 11, fontColor = {140, 140, 140, 255} },
                                    MakeSlider("A.OffX", -30, 30, skin.armTransform.offsetX, 1, function(self, v)
                                        skin.armTransform.offsetX = v; syncTransformToAll(); updateVal("A.OffX", v)
                                    end),
                                    MakeSlider("A.OffY", -30, 30, skin.armTransform.offsetY, 1, function(self, v)
                                        skin.armTransform.offsetY = v; syncTransformToAll(); updateVal("A.OffY", v)
                                    end),
                                    MakeSlider("A.Gap", -20, 20, skin.armTransform.spacing, 1, function(self, v)
                                        skin.armTransform.spacing = v; syncTransformToAll(); updateVal("A.Gap", v)
                                    end),
                                    UI.Label { text = "-- 腿部 --", fontSize = 11, fontColor = {140, 140, 140, 255} },
                                    MakeSlider("L.OffX", -30, 30, skin.legTransform.offsetX, 1, function(self, v)
                                        skin.legTransform.offsetX = v; syncTransformToAll(); updateVal("L.OffX", v)
                                    end),
                                    MakeSlider("L.OffY", -30, 30, skin.legTransform.offsetY, 1, function(self, v)
                                        skin.legTransform.offsetY = v; syncTransformToAll(); updateVal("L.OffY", v)
                                    end),
                                    MakeSlider("L.Gap", -20, 20, skin.legTransform.spacing, 1, function(self, v)
                                        skin.legTransform.spacing = v; syncTransformToAll(); updateVal("L.Gap", v)
                                    end),
                                }
                            },
                            -- ===== 右列：躯干 =====
                            UI.Panel {
                                flex = 1, gap = 4,
                                children = {
                                    UI.Label { text = "-- 躯干 --", fontSize = 11, fontColor = {140, 140, 140, 255} },
                                    MakeSlider("T.Scale", 0.2, 3.0, skin.torsoTransform.scale, 0.1, function(self, v)
                                        skin.torsoTransform.scale = v; syncTransformToAll(); updateVal("T.Scale", v)
                                    end),
                                    MakeSlider("T.OffX", -30, 30, skin.torsoTransform.offsetX, 1, function(self, v)
                                        skin.torsoTransform.offsetX = v; syncTransformToAll(); updateVal("T.OffX", v)
                                    end),
                                    MakeSlider("T.OffY", -30, 30, skin.torsoTransform.offsetY, 1, function(self, v)
                                        skin.torsoTransform.offsetY = v; syncTransformToAll(); updateVal("T.OffY", v)
                                    end),
                                    MakeSlider("T.Rot", -180, 180, skin.torsoTransform.rotation, 1, function(self, v)
                                        skin.torsoTransform.rotation = v; syncTransformToAll(); updateVal("T.Rot", v)
                                    end),
                                    UI.Label { text = "-- 调试 --", fontSize = 11, fontColor = {140, 140, 140, 255} },
                                    UI.Panel {
                                        flexDirection = "row", alignItems = "center", gap = 8,
                                        children = {
                                            UI.Label { text = "碰撞线框", fontSize = 12, fontColor = {200, 200, 200, 255} },
                                            UI.Toggle {
                                                value = G.showCollisionDebug or false,
                                                onChange = function(self, v)
                                                    G.showCollisionDebug = v
                                                end,
                                            },
                                        }
                                    },
                                    UI.Button {
                                        text = "保存配置", variant = "primary", height = 30, marginTop = 12,
                                        onClick = function()
                                            local ok, err = pcall(function()
                                                local data = {
                                                    playerScale = G.playerScale,
                                                    capsuleRadius = G.capsuleRadius,
                                                    capsuleHeight = G.capsuleHeight,
                                                    headTransform = skin.headTransform,
                                                    torsoTransform = skin.torsoTransform,
                                                    armTransform = skin.armTransform,
                                                    legTransform = skin.legTransform,
                                                }
                                                local jsonStr = cjson.encode(data)
                                                local saveFile = File("skin-editor.json", FILE_WRITE)
                                                if saveFile and saveFile:IsOpen() then
                                                    saveFile:WriteString(jsonStr)
                                                    saveFile:Close()
                                                    print("[SkinEditor] Config saved to skin-editor.json")
                                                else
                                                    print("[SkinEditor] ERROR: Failed to open file for writing!")
                                                end
                                            end)
                                            if not ok then
                                                print("[SkinEditor] ERROR saving: " .. tostring(err))
                                            end
                                        end
                                    },
                                }
                            },
                        }
                    },
                }
            },
        }
    }
    skinEditorPanel_:SetVisible(false)

    local root = UI.FindById("root")
    if root then
        root:AddChild(skinEditorPanel_)
    end
end

-- ============================================================================
-- 导出弹窗
-- ============================================================================

function M.ShowExportPopup(content)
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
                    UI.Label { text = "已复制到剪贴板（如未生效请手动复制）", fontSize = 14, fontColor = {255, 220, 100, 255} },
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

-- ============================================================================
-- 地形编辑器
-- ============================================================================

function M.ToggleTerrainEditor()
    M.terrainEditorOpen = not M.terrainEditorOpen
    if terrainEditorPanel_ then
        terrainEditorPanel_:SetVisible(M.terrainEditorOpen)
    end
    if not M.terrainEditorOpen then
        terrainSelected_ = nil
        terrainDragMode_ = "none"
        terrainMouseDown_ = false
    end
end

function M.CreateTerrainEditor()
    terrainEditorPanel_ = UI.Panel {
        id = "terrainEditor",
        position = "absolute",
        top = 50, left = 10,
        width = 200,
        backgroundColor = {20, 20, 30, 220},
        borderRadius = 8,
        padding = 10,
        gap = 6,
        children = {
            UI.Label { text = "地形编辑器 (Tab 关闭)", fontSize = 13, fontColor = {100, 255, 180, 255} },
            UI.Label { id = "te_hint", text = "点击选中平台\n拖拽移动 / 边缘拉伸", fontSize = 11, fontColor = {180, 180, 180, 255} },
            UI.Label { id = "te_info", text = "", fontSize = 11, fontColor = {200, 200, 200, 255} },
            UI.Button {
                text = "复制配置", variant = "primary", height = 28,
                onClick = function()
                    local content = M.ExportTerrainConfig()
                    ui.useSystemClipboard = true
                    ui:SetClipboardText(content)
                    M.ShowExportPopup(content)
                end
            },
        }
    }
    terrainEditorPanel_:SetVisible(false)

    local root = UI.FindById("root")
    if root then
        root:AddChild(terrainEditorPanel_)
    end
end

--- 导出地形配置为 JSON
function M.ExportTerrainConfig()
    local platforms = G.platforms
    local lines = {}
    table.insert(lines, '{')
    table.insert(lines, '  "ground": {')
    local g = platforms[1]
    table.insert(lines, string.format('    "x": %.2f, "y": %.2f, "width": %.2f, "height": %.2f', g.x, g.y, g.width, g.height))
    table.insert(lines, '  },')
    table.insert(lines, '  "platforms": [')
    for i = 2, #platforms do
        local p = platforms[i]
        local comma = (i < #platforms) and "," or ""
        table.insert(lines, string.format('    { "x": %.2f, "y": %.2f, "width": %.2f, "height": %.2f }%s', p.x, p.y, p.width, p.height, comma))
    end
    table.insert(lines, '  ]')
    table.insert(lines, '}')
    return table.concat(lines, "\n")
end

--- 更新选中平台信息显示
local function UpdateTerrainInfoLabel()
    local lbl = UI.FindById("te_info")
    if not lbl then return end
    if terrainSelected_ then
        local p = G.platforms[terrainSelected_]
        local name = terrainSelected_ == 1 and "地面" or ("平台 #" .. (terrainSelected_ - 1))
        lbl:SetText(string.format("%s\nx=%.1f y=%.1f\nw=%.1f h=%.2f", name, p.x, p.y, p.width, p.height))
    else
        lbl:SetText("")
    end
end

--- 判断鼠标在平台的哪个区域
local function HitTestPlatform(platIdx, mx, my)
    local p = G.platforms[platIdx]
    local ppu = Render.GetPixelsPerUnit()
    local sx, sy = Render.PhysToScreen(p.x, p.y)
    local halfW = p.width * ppu / 2
    local halfH = p.height * ppu / 2

    local handleSize = 10

    if mx < sx - halfW - handleSize or mx > sx + halfW + handleSize then return nil end
    if my < sy - halfH - handleSize or my > sy + halfH + handleSize then return nil end

    if mx >= sx - halfW - handleSize and mx <= sx - halfW + handleSize then return "left" end
    if mx >= sx + halfW - handleSize and mx <= sx + halfW + handleSize then return "right" end
    if my >= sy - halfH - handleSize and my <= sy - halfH + handleSize then return "top" end
    if my >= sy + halfH - handleSize and my <= sy + halfH + handleSize then return "bottom" end

    if mx >= sx - halfW and mx <= sx + halfW and my >= sy - halfH and my <= sy + halfH then
        return "move"
    end

    return nil
end

--- 同步编辑结果到物理世界节点
local function SyncPlatformToNode(platIdx)
    local p = G.platforms[platIdx]
    if not p.node then return end
    p.node:SetPosition2D(p.x, p.y)
    local shape = p.node:GetComponent("CollisionBox2D")
    if shape then
        shape:SetSize(p.width, p.height)
    end
end

--- 地形编辑器主更新（鼠标交互）
function M.UpdateTerrainEditor(dt)
    local mx = input.mousePosition.x
    local my = input.mousePosition.y
    local mousePressed = input:GetMouseButtonPress(MOUSEB_LEFT)
    local mouseDown = input:GetMouseButtonDown(MOUSEB_LEFT)

    -- 鼠标按下：选中或开始拖拽
    if mousePressed then
        terrainMouseDown_ = true
        local hit = false

        if terrainSelected_ then
            local mode = HitTestPlatform(terrainSelected_, mx, my)
            if mode then
                terrainDragMode_ = mode
                terrainDragStart_.sx = mx
                terrainDragStart_.sy = my
                local p = G.platforms[terrainSelected_]
                terrainDragOrigin_ = {x = p.x, y = p.y, width = p.width, height = p.height}
                hit = true
            end
        end

        if not hit then
            terrainSelected_ = nil
            terrainDragMode_ = "none"
            for i = #G.platforms, 1, -1 do
                local mode = HitTestPlatform(i, mx, my)
                if mode then
                    terrainSelected_ = i
                    terrainDragMode_ = mode
                    terrainDragStart_.sx = mx
                    terrainDragStart_.sy = my
                    local p = G.platforms[i]
                    terrainDragOrigin_ = {x = p.x, y = p.y, width = p.width, height = p.height}
                    break
                end
            end
            UpdateTerrainInfoLabel()
        end
    end

    -- 拖拽中
    if mouseDown and terrainMouseDown_ and terrainSelected_ and terrainDragMode_ ~= "none" then
        local dx = mx - terrainDragStart_.sx
        local dy = my - terrainDragStart_.sy
        local ppu = Render.GetPixelsPerUnit()
        local worldDx = dx / ppu
        local worldDy = -dy / ppu

        local p = G.platforms[terrainSelected_]
        local orig = terrainDragOrigin_

        if terrainDragMode_ == "move" then
            p.x = orig.x + worldDx
            p.y = orig.y + worldDy
        elseif terrainDragMode_ == "left" then
            local newWidth = math.max(0.5, orig.width - worldDx)
            local widthDiff = newWidth - orig.width
            p.width = newWidth
            p.x = orig.x - widthDiff / 2
        elseif terrainDragMode_ == "right" then
            local newWidth = math.max(0.5, orig.width + worldDx)
            local widthDiff = newWidth - orig.width
            p.width = newWidth
            p.x = orig.x + widthDiff / 2
        elseif terrainDragMode_ == "top" then
            local newHeight = math.max(0.2, orig.height + worldDy)
            local heightDiff = newHeight - orig.height
            p.height = newHeight
            p.y = orig.y + heightDiff / 2
        elseif terrainDragMode_ == "bottom" then
            local newHeight = math.max(0.2, orig.height - worldDy)
            local heightDiff = newHeight - orig.height
            p.height = newHeight
            p.y = orig.y - heightDiff / 2
        end

        SyncPlatformToNode(terrainSelected_)
        UpdateTerrainInfoLabel()
    end

    -- 鼠标释放
    if not mouseDown then
        terrainMouseDown_ = false
        terrainDragMode_ = "none"
    end
end

--- 绘制地形编辑器覆盖层（NanoVG）
function M.DrawTerrainEditor()
    if not M.terrainEditorOpen then return end

    local nvg = G.nvg
    local ppu = Render.GetPixelsPerUnit()
    local handleSize = 8

    for i, plat in ipairs(G.platforms) do
        local sx, sy = Render.PhysToScreen(plat.x, plat.y)
        local pw = plat.width * ppu
        local ph = plat.height * ppu

        if i == terrainSelected_ then
            nvgBeginPath(nvg)
            nvgRect(nvg, sx - pw/2, sy - ph/2, pw, ph)
            nvgFillColor(nvg, nvgRGBA(100, 255, 180, 40))
            nvgFill(nvg)
            nvgBeginPath(nvg)
            nvgRect(nvg, sx - pw/2, sy - ph/2, pw, ph)
            nvgStrokeColor(nvg, nvgRGBA(100, 255, 180, 255))
            nvgStrokeWidth(nvg, 2)
            nvgStroke(nvg)

            local handles = {
                {x = sx - pw/2, y = sy, mode = "left"},
                {x = sx + pw/2, y = sy, mode = "right"},
                {x = sx, y = sy - ph/2, mode = "top"},
                {x = sx, y = sy + ph/2, mode = "bottom"},
            }
            for _, h in ipairs(handles) do
                nvgBeginPath(nvg)
                nvgRect(nvg, h.x - handleSize/2, h.y - handleSize/2, handleSize, handleSize)
                local isActive = (terrainDragMode_ == h.mode)
                if isActive then
                    nvgFillColor(nvg, nvgRGBA(255, 220, 80, 255))
                else
                    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 220))
                end
                nvgFill(nvg)
                nvgBeginPath(nvg)
                nvgRect(nvg, h.x - handleSize/2, h.y - handleSize/2, handleSize, handleSize)
                nvgStrokeColor(nvg, nvgRGBA(0, 0, 0, 180))
                nvgStrokeWidth(nvg, 1)
                nvgStroke(nvg)
            end

            -- 尺寸标注
            nvgFontSize(nvg, 11)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(nvg, nvgRGBA(100, 255, 180, 220))
            local label = string.format("%.1f x %.2f", plat.width, plat.height)
            nvgText(nvg, sx, sy - ph/2 - 4, label, nil)
        else
            nvgBeginPath(nvg)
            nvgRect(nvg, sx - pw/2, sy - ph/2, pw, ph)
            nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 80))
            nvgStrokeWidth(nvg, 1)
            nvgStroke(nvg)
        end
    end

    -- 顶部提示
    nvgFontSize(nvg, 14)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(100, 255, 180, 200))
    nvgText(nvg, G.screenW / 2, 6, "[ 地形编辑模式 - 游戏已暂停 | Tab 退出 ]", nil)
end

--- 绘制皮肤编辑器预览（NanoVG）
function M.DrawSkinEditorPreview()
    if not M.skinEditorOpen then return end
    if not G.skinsRuntime or #G.skinsRuntime == 0 then return end

    local nvg = G.nvg
    -- 预览区域（左侧中间位置）
    local previewX = G.screenW * 0.35
    local previewY = G.screenH * 0.5

    -- 半透明背景
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, previewX - 80, previewY - 120, 160, 240, 10)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 100))
    nvgFill(nvg)

    -- 使用 render 模块的 DrawSinglePlayer 绘制预览角色
    local limbSwing = math.sin(M.skinEditorAnimTime) * 0.5
    local armSwing = -math.sin(M.skinEditorAnimTime) * 0.4

    Render.DrawSinglePlayer({
        sx = previewX,
        sy = previewY,
        facing = 1,
        onGround = true,
        isMoving = true,
        animTime = M.skinEditorAnimTime,
        velY = 0,
        limbSwing = limbSwing,
        armSwing = armSwing,
        skinIndex = 1,
        color = {200, 200, 200, 255},
        name = G.skinsRuntime[1].name,
    })
end

-- ============================================================================
-- 玩法 GM
-- ============================================================================

--- 更新按钮样式（选中高亮）
local function RefreshGMButtons()
    for i, btn in ipairs(gameplayGMButtons_) do
        if M.gmForceGameplay == i then
            btn:SetVariant("primary")
            btn:SetText(string.format("✓ 玩法%d：%s", i, Cfg.GAMEPLAY_DATA[i].name))
        else
            btn:SetVariant("outline")
            btn:SetText(string.format("玩法%d：%s", i, Cfg.GAMEPLAY_DATA[i].name))
        end
    end
end

function M.ToggleGameplayGM()
    M.gameplayGMOpen = not M.gameplayGMOpen
    if gameplayGMPanel_ then
        gameplayGMPanel_:SetVisible(M.gameplayGMOpen)
    end
    -- 打开时刷新按钮高亮状态
    if M.gameplayGMOpen then
        RefreshGMButtons()
    end
end

function M.CreateGameplayGM()
    local GAMEPLAY_DATA = Cfg.GAMEPLAY_DATA
    gameplayGMButtons_ = {}

    local buttonChildren = {}
    for i, gp in ipairs(GAMEPLAY_DATA) do
        local idx = i  -- 闭包捕获
        local btn = UI.Button {
            text = string.format("玩法%d：%s", idx, gp.name),
            variant = "outline",
            width = "100%",
            height = 34,
            onClick = function(self)
                -- toggle：再次点击取消
                if M.gmForceGameplay == idx then
                    M.gmForceGameplay = nil
                else
                    M.gmForceGameplay = idx
                end
                RefreshGMButtons()
                print(string.format("[GM] 强制玩法: %s",
                    M.gmForceGameplay and GAMEPLAY_DATA[M.gmForceGameplay].name or "无（正常随机）"))
            end
        }
        gameplayGMButtons_[idx] = btn
        table.insert(buttonChildren, btn)
    end

    -- 状态提示
    local hintChildren = {
        UI.Label { text = "玩法 GM (Tab 关闭)", fontSize = 14, fontColor = {255, 180, 80, 255} },
        UI.Label { text = "选中后下一轮强制该玩法\n再次点击取消", fontSize = 11, fontColor = {160, 160, 160, 255} },
    }
    -- 合并按钮
    for _, child in ipairs(buttonChildren) do
        table.insert(hintChildren, child)
    end

    gameplayGMPanel_ = UI.Panel {
        id = "gameplayGM",
        position = "absolute",
        top = 50, left = 10,
        width = 220,
        backgroundColor = {20, 20, 30, 220},
        borderRadius = 8,
        padding = 12,
        gap = 8,
        children = hintChildren,
    }
    gameplayGMPanel_:SetVisible(false)

    local root = UI.FindById("root")
    if root then
        root:AddChild(gameplayGMPanel_)
    end
end

return M
