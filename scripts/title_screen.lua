-- ============================================================================
-- Title Screen - 主界面（纯 UI 组件实现）
-- 所有素材均为 1920x1080 全屏分层图，使用 UI.Panel + backgroundImage 堆叠
-- 人物和胶片使用 UI 内置 Animate() 关键帧动画实现弹性旋转+缩放
-- 点击英文副标题触发像素风格菱形蒙版转场（淡出+淡入）
-- ============================================================================

local UI = require("urhox-libs/UI")

local TitleScreen = {}

-- 状态
local isVisible_ = true
local root_ = nil
local onStartCallback_ = nil
local transitioning_ = false

-- 图层定义（从底到顶），animated 标记需要动画的图层
-- "char"=人物旋转缩放, "film"=胶片旋转缩放, "float"=上下浮动, "corner"=角落缩放, "shake"=震动
local LAYER_DEFS = {
    { path = "image/mainUI/底色背景.png",       animated = false },
    { path = "image/mainUI/背景色.png",         animated = false },
    { path = "image/mainUI/底色波点.png",       animated = false },
    { path = "image/mainUI/速度线.png",         animated = "shake" },
    { path = "image/mainUI/左下角的纸片.png",   animated = "corner" },
    { path = "image/mainUI/左上角纸片..png",    animated = "corner" },
    { path = "image/mainUI/右上角胶片.png",     animated = "corner" },
    { path = "image/mainUI/人物底部胶片.png",   animated = "film" },
    { path = "image/mainUI/人物.png",           animated = "char" },
    { path = "image/mainUI/人物旁边星星.png",   animated = false },
    { path = "image/mainUI/中文主标题..png",    animated = "float" },
    { path = "image/mainUI/英文副标题..png",    animated = "subtitle" },
    { path = "image/mainUI/右下角小拍立得.png", animated = "corner" },
    { path = "image/mainUI/右下角星星..png",    animated = "corner" },
}

-- 像素转场参数
local TRANSITION_OUT = {
    cols = 20,          -- 横向格子数
    rows = 12,          -- 纵向格子数
    duration = 0.5,     -- 单块动画时长
    staggerMax = 0.35,  -- 最大错开延迟
    color = {20, 20, 30, 255},  -- 像素块颜色（深色）
}

local TRANSITION_IN = {
    cols = 20,          -- 横向格子数（与淡出一致）
    rows = 12,          -- 纵向格子数（与淡出一致）
    duration = 0.5,     -- 单块动画时长
    staggerMax = 0.35,  -- 最大错开延迟
    color = {20, 20, 30, 255},
}

--- 启动像素菱形蒙版转场（淡出）
local function StartPixelTransition()
    if transitioning_ then return end
    transitioning_ = true

    -- 创建全屏转场遮罩容器
    local transitionRoot = UI.Panel {
        id = "pixelTransition",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        pointerEvents = "none",
    }

    local cols = TRANSITION_OUT.cols
    local rows = TRANSITION_OUT.rows
    local cellW = 100 / cols
    local cellH = 100 / rows
    local centerCol = cols / 2
    local centerRow = rows / 2

    -- 计算最大曼哈顿距离
    local maxDist = centerCol + centerRow

    -- 创建像素网格
    local blocks = {}
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            local dist = math.abs(c + 0.5 - centerCol) + math.abs(r + 0.5 - centerRow)
            local normalizedDist = dist / maxDist

            local block = UI.Panel {
                position = "absolute",
                left = tostring(c * cellW) .. "%",
                top = tostring(r * cellH) .. "%",
                width = tostring(cellW + 0.5) .. "%",
                height = tostring(cellH + 0.5) .. "%",
                backgroundColor = TRANSITION_OUT.color,
                opacity = 0,
                scale = 0,
                transformOrigin = "center",
            }
            blocks[#blocks + 1] = { panel = block, delay = normalizedDist }
            transitionRoot:AddChild(block)
        end
    end

    root_:AddChild(transitionRoot)

    -- 按距离分批启动动画（从中心向外扩散菱形蒙版）
    for _, b in ipairs(blocks) do
        local delay = b.delay * TRANSITION_OUT.staggerMax
        local blockDur = TRANSITION_OUT.duration
        if blockDur < 0.1 then blockDur = 0.1 end

        b.panel:Animate({
            keyframes = {
                [0] = { opacity = 0, scale = 0 },
                [0.4] = { opacity = 1, scale = 1.2 },
                [1] = { opacity = 1, scale = 1.0 },
            },
            duration = blockDur,
            easing = "easeOut",
            loop = false,
            direction = "normal",
            fillMode = "forwards",
            delay = delay,
        })
    end

    -- 转场结束后隐藏主界面
    local totalTime = TRANSITION_OUT.duration + TRANSITION_OUT.staggerMax + 0.05
    local timer = UI.Panel {
        position = "absolute",
        width = 1, height = 1,
        opacity = 0,
    }
    transitionRoot:AddChild(timer)
    timer:Animate({
        keyframes = {
            [0] = { opacity = 0 },
            [1] = { opacity = 0.01 },
        },
        duration = totalTime,
        loop = false,
        fillMode = "forwards",
        onComplete = function()
            TitleScreen.Hide()
        end,
    })
end

--- 创建淡入转场（菱形蒙版从中心向外消失），挂载到指定 parent 上
function TitleScreen.PlayFadeIn(parent)
    if not parent then return end

    local transitionRoot = UI.Panel {
        id = "pixelFadeIn",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        pointerEvents = "none",
    }

    local cols = TRANSITION_IN.cols
    local rows = TRANSITION_IN.rows
    local cellW = 100 / cols
    local cellH = 100 / rows
    local centerCol = cols / 2
    local centerRow = rows / 2

    -- 计算最大曼哈顿距离
    local maxDist = centerCol + centerRow

    -- 创建像素网格（初始全覆盖）
    local blocks = {}
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            local dist = math.abs(c + 0.5 - centerCol) + math.abs(r + 0.5 - centerRow)
            local normalizedDist = dist / maxDist

            local block = UI.Panel {
                position = "absolute",
                left = tostring(c * cellW) .. "%",
                top = tostring(r * cellH) .. "%",
                width = tostring(cellW + 0.5) .. "%",
                height = tostring(cellH + 0.5) .. "%",
                backgroundColor = TRANSITION_IN.color,
                opacity = 1,
                scale = 1,
                transformOrigin = "center",
            }
            blocks[#blocks + 1] = { panel = block, delay = normalizedDist }
            transitionRoot:AddChild(block)
        end
    end

    parent:AddChild(transitionRoot)

    -- 从中心向外逐步消失（菱形扩散揭开）
    for _, b in ipairs(blocks) do
        local delay = b.delay * TRANSITION_IN.staggerMax

        b.panel:Animate({
            keyframes = {
                [0]   = { opacity = 1, scale = 1.0 },
                [0.4] = { opacity = 0.8, scale = 1.2 },
                [1]   = { opacity = 0, scale = 0 },
            },
            duration = TRANSITION_IN.duration,
            easing = "easeIn",
            loop = false,
            direction = "normal",
            fillMode = "forwards",
            delay = delay,
        })
    end

    -- 动画结束后移除转场容器
    local totalTime = TRANSITION_IN.duration + TRANSITION_IN.staggerMax + 0.05
    local timer = UI.Panel {
        position = "absolute",
        width = 1, height = 1,
        opacity = 0,
    }
    transitionRoot:AddChild(timer)
    timer:Animate({
        keyframes = {
            [0] = { opacity = 0 },
            [1] = { opacity = 0.01 },
        },
        duration = totalTime,
        loop = false,
        fillMode = "forwards",
        onComplete = function()
            transitionRoot:Remove()
        end,
    })
end

--- 初始化主界面
function TitleScreen.Create(onStart)
    onStartCallback_ = onStart
    isVisible_ = true
    transitioning_ = false

    -- 构建所有图层作为绝对定位的全屏面板
    local children = {}

    ---@type table<string, any>
    local animatedPanels = {}

    for i, layer in ipairs(LAYER_DEFS) do
        local panelProps = {
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundImage = layer.path,
            backgroundFit = "cover",
            pointerEvents = "none",
            transformOrigin = "center",
        }

        -- 英文副标题需要可点击
        if layer.animated == "subtitle" then
            panelProps.pointerEvents = "auto"
            panelProps.onClick = function(self)
                StartPixelTransition()
            end
        end

        local panel = UI.Panel(panelProps)
        children[#children + 1] = panel

        if layer.animated then
            if layer.animated == "corner" then
                if not animatedPanels["corner"] then
                    animatedPanels["corner"] = {}
                end
                table.insert(animatedPanels["corner"], panel)
            else
                animatedPanels[layer.animated] = panel
            end
        end
    end

    -- 根面板
    root_ = UI.Panel {
        id = "titleScreen",
        width = "100%",
        height = "100%",
        children = children,
    }

    -- 启动动画
    -- 人物：弹性旋转 ±3° + 缩放 1.0 ~ 1.03
    if animatedPanels["char"] then
        animatedPanels["char"]:Animate({
            keyframes = {
                [0]   = { rotate = 0,  scale = 1.0 },
                [0.25] = { rotate = 3,  scale = 1.015 },
                [0.5] = { rotate = 0,  scale = 1.03 },
                [0.75] = { rotate = -3, scale = 1.015 },
                [1]   = { rotate = 0,  scale = 1.0 },
            },
            duration = 3.0,
            easing = "easeInOut",
            loop = true,
            direction = "normal",
            fillMode = "none",
        })
    end

    -- 人物底部胶片：弹性旋转 ±2° + 缩放 1.0 ~ 1.04（节奏错开）
    if animatedPanels["film"] then
        animatedPanels["film"]:Animate({
            keyframes = {
                [0]   = { rotate = 2,   scale = 1.02 },
                [0.25] = { rotate = 0,   scale = 1.04 },
                [0.5] = { rotate = -2,  scale = 1.02 },
                [0.75] = { rotate = 0,   scale = 1.0 },
                [1]   = { rotate = 2,   scale = 1.02 },
            },
            duration = 3.5,
            easing = "easeInOut",
            loop = true,
            direction = "normal",
            fillMode = "none",
        })
    end

    -- 中文主标题：上下循环浮动
    if animatedPanels["float"] then
        animatedPanels["float"]:Animate({
            keyframes = {
                [0] = { translateY = 0 },
                [1] = { translateY = -12 },
            },
            duration = 1.8,
            easing = "easeInOut",
            loop = true,
            direction = "alternate",
            fillMode = "none",
        })
    end

    -- 英文副标题：快速闪烁提示点击
    if animatedPanels["subtitle"] then
        animatedPanels["subtitle"]:Animate({
            keyframes = {
                [0] = { opacity = 1.0 },
                [1] = { opacity = 0.4 },
            },
            duration = 0.5,
            easing = "easeInOut",
            loop = true,
            direction = "alternate",
            fillMode = "none",
        })
    end

    -- 速度线：高频微震动（scale 1.0 ~ 1.01）
    if animatedPanels["shake"] then
        animatedPanels["shake"]:Animate({
            keyframes = {
                [0]   = { scale = 1.0,  translateX = 0 },
                [0.25] = { scale = 1.01, translateX = 1 },
                [0.5] = { scale = 1.0,  translateX = -1 },
                [0.75] = { scale = 1.01, translateX = 0.5 },
                [1]   = { scale = 1.0,  translateX = 0 },
            },
            duration = 0.3,
            easing = "linear",
            loop = true,
            direction = "normal",
            fillMode = "none",
        })
    end

    -- 四角图片+拍立得：以中心为原点 1.0 ~ 1.1 循环缩放（各角节奏略有错开）
    if animatedPanels["corner"] then
        local durations = { 2.0, 2.3, 2.6, 2.1, 2.4 }
        for idx, panel in ipairs(animatedPanels["corner"]) do
            panel:Animate({
                keyframes = {
                    [0] = { scale = 1.0 },
                    [1] = { scale = 1.1 },
                },
                duration = durations[idx] or 2.0,
                easing = "easeInOut",
                loop = true,
                direction = "alternate",
                fillMode = "none",
            })
        end
    end

    return root_
end

--- 隐藏主界面并触发回调
function TitleScreen.Hide()
    if not isVisible_ then return end
    isVisible_ = false

    if root_ then
        root_:Remove()
        root_ = nil
    end

    if onStartCallback_ then
        onStartCallback_()
    end
end

--- 是否可见
function TitleScreen.IsVisible()
    return isVisible_
end

--- 通过按键隐藏
function TitleScreen.HandleInput()
    if not isVisible_ then return end
    if transitioning_ then return end
    if input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_RETURN) then
        StartPixelTransition()
    end
end

return TitleScreen
