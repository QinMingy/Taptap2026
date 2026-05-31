-- ============================================================================
-- render.lua - NanoVG 渲染系统
-- 负责所有 NanoVG 绘制：背景、平台、玩家、拍照区域、特效、公告板、GameOver
-- ============================================================================

local Cfg = require("config")
local CONFIG = Cfg.CONFIG
local PLAYERS = Cfg.PLAYERS
local GAMEPLAY_DATA = Cfg.GAMEPLAY_DATA
local MAP_DATA = Cfg.MAP_DATA

local M = {}

-- G 引用（在 init 时设置）
local G = nil

-- 背景图片
local bgImage_ = -1

-- 云朵系统
local cloudImage_ = -1
local clouds_ = {}

-- 平台图片
local platformImage_ = -1

-- 地板图片
local groundImage_ = -1

-- ============================================================================
-- 粒子系统
-- ============================================================================
local particles_ = {}
local PARTICLE_POOL_MAX = 100

--- 生成一组起跳灰尘粒子
---@param physX number 物理坐标 X
---@param physY number 物理坐标 Y（角色脚底）
function M.SpawnJumpDust(physX, physY)
    local count = 6
    for _ = 1, count do
        if #particles_ >= PARTICLE_POOL_MAX then break end
        local angle = math.random() * math.pi  -- 向上的半圆范围 (0 ~ π)
        local speed = 40 + math.random() * 60  -- 像素/秒
        table.insert(particles_, {
            px = physX,  -- 物理坐标
            py = physY,
            vx = math.cos(angle) * speed * (math.random() > 0.5 and 1 or -1),
            vy = -math.sin(angle) * speed,  -- 屏幕坐标向上为负
            life = 0.3 + math.random() * 0.2,
            maxLife = 0.3 + math.random() * 0.2,
            size = 3 + math.random() * 4,
            alpha = 180 + math.random(0, 50),
        })
    end
end

--- 生成跑步灰尘粒子（较小、较淡、朝后方扩散）
---@param physX number 物理坐标 X（脚底）
---@param physY number 物理坐标 Y（脚底）
---@param facing number 朝向（-1 或 1），灰尘向反方向喷
function M.SpawnRunDust(physX, physY, facing)
    local count = 5
    for _ = 1, count do
        if #particles_ >= PARTICLE_POOL_MAX then break end
        local angle = math.random() * math.pi * 0.6 + math.pi * 0.2  -- 偏上扩散
        local speed = 35 + math.random() * 50
        table.insert(particles_, {
            px = physX,
            py = physY,
            vx = -facing * (30 + math.random() * 40),  -- 向角色背后喷
            vy = -math.sin(angle) * speed,
            life = 0.25 + math.random() * 0.2,
            maxLife = 0.25 + math.random() * 0.2,
            size = 3 + math.random() * 4,
            alpha = 170 + math.random(0, 50),
        })
    end
end

--- 更新和绘制粒子（每帧调用）
function M.UpdateAndDrawParticles(dt)
    local nvg = G.nvg
    if nvg == nil then return end

    local i = 1
    while i <= #particles_ do
        local p = particles_[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(particles_, i)
        else
            -- 物理更新（速度减缓 + 轻微重力）
            p.vx = p.vx * 0.95
            p.vy = p.vy + 80 * dt  -- 微弱重力让灰尘下落
            p.px = p.px + p.vx * dt / M.GetPixelsPerUnit()
            p.py = p.py - p.vy * dt / M.GetPixelsPerUnit()

            -- 转屏幕坐标绘制
            local sx, sy = M.PhysToScreen(p.px, p.py)
            local t = p.life / p.maxLife  -- 1→0
            local alpha = math.floor(p.alpha * t)
            local size = p.size * (0.5 + 0.5 * t)

            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, size)
            nvgFillColor(nvg, nvgRGBA(180, 170, 155, alpha))
            nvgFill(nvg)

            i = i + 1
        end
    end
end

function M.Init(gameState)
    G = gameState
    -- 加载背景图片
    bgImage_ = nvgCreateImage(G.nvg, "image/img_v3_02126_74376101-52cd-4dbc-8040-f8e090f3314g.png", 0)
    print("[Render] Background image loaded: " .. tostring(bgImage_))

    -- 加载平台图片
    platformImage_ = nvgCreateImage(G.nvg, "image/platform_tile.png", 0)
    print("[Render] Platform image loaded: " .. tostring(platformImage_))

    groundImage_ = nvgCreateImage(G.nvg, "image/ground_tiled.png", 0)
    print("[Render] Ground image loaded: " .. tostring(groundImage_))

    -- 加载云朵图片并初始化 2-3 朵云
    cloudImage_ = nvgCreateImage(G.nvg, "image/img_v3_02126_97886e77-a440-4381-a610-264ae30d98bg.png", 0)
    print("[Render] Cloud image loaded: " .. tostring(cloudImage_))

    -- 加载结算画面背景框
    gameOverFrameImg_ = nvgCreateImage(G.nvg, "image/edited_gameover_frame_20260531032825.png", 0)
    print("[Render] GameOver frame loaded: " .. tostring(gameOverFrameImg_))
    loseCryImg_ = nvgCreateImage(G.nvg, "image/lose_cry_photo.png", 0)
    print("[Render] Lose cry photo loaded: " .. tostring(loseCryImg_))

    local cloudCount = math.random(2, 3)
    clouds_ = {}
    for i = 1, cloudCount do
        table.insert(clouds_, {
            x = math.random(0, 100) / 100,  -- 归一化 x 位置 (0~1)
            y = math.random(3, 12) / 100,   -- 屏幕顶部区域 (3%~12%)
            scale = 0.8 + math.random() * 0.5,  -- 0.8~1.3 随机大小
            speed = (math.random() > 0.5 and 1 or -1) * (0.01 + math.random() * 0.015), -- 随机方向和速度
            alpha = 180 + math.random(0, 60),
        })
    end
end

-- ============================================================================
-- 工具函数
-- ============================================================================

function M.GetPixelsPerUnit()
    local camera = G.cameraNode:GetComponent("Camera")
    return G.screenH / camera.orthoSize
end

function M.PhysToScreen(px, py)
    local camera = G.cameraNode:GetComponent("Camera")
    local orthoSize = camera.orthoSize
    local camX = G.cameraNode.position.x
    local camY = G.cameraNode.position.y
    local ppu = G.screenH / orthoSize

    local sx = G.screenW / 2 + (px - camX) * ppu
    local sy = G.screenH / 2 - (py - camY) * ppu
    return sx, sy
end

function M.ScreenToPhys(sx, sy)
    local camera = G.cameraNode:GetComponent("Camera")
    local orthoSize = camera.orthoSize
    local camX = G.cameraNode.position.x
    local camY = G.cameraNode.position.y
    local ppu = G.screenH / orthoSize

    local px = camX + (sx - G.screenW / 2) / ppu
    local py = camY - (sy - G.screenH / 2) / ppu
    return px, py
end

-- ============================================================================
-- 背景渲染
-- ============================================================================

function M.DrawCloud(cx, cy, w)
    local nvg = G.nvg
    local h = w * 0.4
    nvgBeginPath(nvg)
    nvgEllipse(nvg, cx, cy, w * 0.5, h * 0.4)
    nvgEllipse(nvg, cx - w * 0.25, cy + 3, w * 0.3, h * 0.35)
    nvgEllipse(nvg, cx + w * 0.25, cy + 2, w * 0.35, h * 0.35)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 220))
    nvgFill(nvg)
end

function M.DrawMountain(baseY, color, seed)
    local nvg = G.nvg
    math.randomseed(seed)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, 0, baseY + 40)
    local step = 60
    for x = 0, G.screenW + step, step do
        local peakY = baseY - math.random(20, 80)
        nvgLineTo(nvg, x, peakY)
    end
    nvgLineTo(nvg, G.screenW, G.screenH)
    nvgLineTo(nvg, 0, G.screenH)
    nvgClosePath(nvg)
    nvgFillColor(nvg, color)
    nvgFill(nvg)
    math.randomseed(os.time())
end

function M.DrawTree(x, y, height)
    local nvg = G.nvg
    local trunkW = height * 0.12
    local trunkH = height * 0.35
    nvgBeginPath(nvg)
    nvgRect(nvg, x - trunkW / 2, y - trunkH, trunkW, trunkH)
    nvgFillColor(nvg, nvgRGBA(100, 70, 40, 200))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgEllipse(nvg, x, y - trunkH - height * 0.3, height * 0.3, height * 0.35)
    nvgFillColor(nvg, nvgRGBA(40, 140 + math.random(0, 30), 50, 220))
    nvgFill(nvg)
end

function M.DrawBackground()
    local nvg = G.nvg
    local sw, sh = G.screenW, G.screenH

    if bgImage_ > 0 then
        -- 用图片填充整个屏幕（Cover 策略：保持比例，裁切多余部分）
        local imgW, imgH = 2048, 1152  -- 图片原始尺寸（16:9 像素风）
        local imgAspect = imgW / imgH
        local screenAspect = sw / sh

        local drawW, drawH, drawX, drawY
        if screenAspect > imgAspect then
            -- 屏幕更宽，以宽度为基准
            drawW = sw
            drawH = sw / imgAspect
            drawX = 0
            drawY = (sh - drawH) / 2
        else
            -- 屏幕更高，以高度为基准
            drawH = sh
            drawW = sh * imgAspect
            drawX = (sw - drawW) / 2
            drawY = 0
        end

        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, sw, sh)
        local imgPaint = nvgImagePattern(nvg, drawX, drawY, drawW, drawH, 0, bgImage_, 1.0)
        nvgFillPaint(nvg, imgPaint)
        nvgFill(nvg)
    else
        -- 回退：简单天空渐变
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, sw, sh)
        local skyGrad = nvgLinearGradient(nvg, 0, 0, 0, sh,
            nvgRGBA(100, 180, 255, 255), nvgRGBA(200, 230, 255, 255))
        nvgFillPaint(nvg, skyGrad)
        nvgFill(nvg)
    end
end

-- ============================================================================
-- 云朵漂浮渲染
-- ============================================================================

--- 更新并绘制漂浮云朵
function M.UpdateAndDrawClouds(dt)
    local nvg = G.nvg
    if nvg == nil or cloudImage_ <= 0 then return end

    local sw, sh = G.screenW, G.screenH
    local cloudW = 200  -- 云朵绘制宽度基准
    local cloudH = 70   -- 云朵绘制高度基准

    for _, cloud in ipairs(clouds_) do
        -- 更新位置
        cloud.x = cloud.x + cloud.speed * dt

        -- 超出屏幕后从另一边回来
        local halfW = (cloudW * cloud.scale) / sw
        if cloud.speed > 0 and cloud.x > 1 + halfW then
            cloud.x = -halfW
        elseif cloud.speed < 0 and cloud.x < -halfW then
            cloud.x = 1 + halfW
        end

        -- 绘制
        local cx = cloud.x * sw
        local cy = cloud.y * sh
        local w = cloudW * cloud.scale
        local h = cloudH * cloud.scale

        nvgBeginPath(nvg)
        nvgRect(nvg, cx - w / 2, cy - h / 2, w, h)
        local imgPaint = nvgImagePattern(nvg, cx - w / 2, cy - h / 2, w, h, 0, cloudImage_, cloud.alpha / 255)
        nvgFillPaint(nvg, imgPaint)
        nvgFill(nvg)
    end
end

-- ============================================================================
-- 平台渲染
-- ============================================================================

function M.DrawPlatforms()
    local nvg = G.nvg
    local ppu = M.GetPixelsPerUnit()

    for _, plat in ipairs(G.platforms) do
        local sx, sy = M.PhysToScreen(plat.x, plat.y)
        local pw = plat.width * ppu
        local ph = plat.height * ppu

        -- 判断是否为底部地板（宽度 > 20 的为地板）
        local isGround = plat.width > 20

        if isGround and groundImage_ > 0 then
            -- 地板：使用拼接地板图片，向上偏移让玩家站在表面
            local visualH = ph * 2.8
            local offsetUp = ph * 0.8

            nvgBeginPath(nvg)
            nvgRect(nvg, sx - pw / 2, sy - ph / 2 - offsetUp, pw, visualH)
            local imgPaint = nvgImagePattern(nvg, sx - pw / 2, sy - ph / 2 - offsetUp, pw, visualH, 0, groundImage_, 1.0)
            nvgFillPaint(nvg, imgPaint)
            nvgFill(nvg)
        elseif platformImage_ > 0 then
            -- 图片平台：视觉上向上偏移，让碰撞体位于平台下半部分
            -- 这样玩家脚踩在碰撞体顶部时，看起来站在平台表面
            local visualH = ph * 2.5  -- 图片视觉高度比碰撞体高
            local offsetUp = ph * 0.6 -- 向上偏移量

            -- 地图倾斜：获取平台节点旋转角度
            local rot2d = 0
            if plat.node then
                rot2d = plat.node:GetRotation2D()  -- 物理角度（负值=顺时针）
            end

            if rot2d ~= 0 then
                -- 围绕平台中心旋转绘制
                nvgSave(nvg)
                nvgTranslate(nvg, sx, sy)
                nvgRotate(nvg, math.rad(-rot2d))  -- 物理负→NanoVG正=顺时针
                nvgTranslate(nvg, -sx, -sy)
            end

            nvgBeginPath(nvg)
            nvgRect(nvg, sx - pw / 2, sy - ph / 2 - offsetUp, pw, visualH)
            local imgPaint = nvgImagePattern(nvg, sx - pw / 2, sy - ph / 2 - offsetUp, pw, visualH, 0, platformImage_, 1.0)
            nvgFillPaint(nvg, imgPaint)
            nvgFill(nvg)

            if rot2d ~= 0 then
                nvgRestore(nvg)
            end
        else
            -- 回退：程序化绘制
            -- 地图倾斜：获取平台节点旋转角度
            local rot2d = 0
            if plat.node then
                rot2d = plat.node:GetRotation2D()
            end

            if rot2d ~= 0 then
                nvgSave(nvg)
                nvgTranslate(nvg, sx, sy)
                nvgRotate(nvg, math.rad(-rot2d))
                nvgTranslate(nvg, -sx, -sy)
            end

            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, sx - pw/2, sy - ph/2, pw, ph, 6)
            local grad = nvgLinearGradient(nvg, sx - pw/2, sy - ph/2, sx - pw/2, sy + ph/2,
                nvgRGBA(140, 100, 60, 255), nvgRGBA(100, 70, 40, 255))
            nvgFillPaint(nvg, grad)
            nvgFill(nvg)

            if rot2d ~= 0 then
                nvgRestore(nvg)
            end
        end
    end
end

-- ============================================================================
-- 拍照区域渲染
-- ============================================================================

--- 绘制单个拍照区域边框
local function DrawSinglePhotoZoneFrame(nvg, sx, sy, pw, ph, label)
    local alpha = 120 + math.floor(math.sin(G.globalTime * 4) * 40)

    nvgBeginPath(nvg)
    nvgRect(nvg, sx - pw/2, sy - ph/2, pw, ph)
    nvgFillColor(nvg, nvgRGBA(255, 220, 50, math.floor(alpha * 0.3)))
    nvgFill(nvg)

    nvgBeginPath(nvg)
    nvgRect(nvg, sx - pw/2, sy - ph/2, pw, ph)
    nvgStrokeColor(nvg, nvgRGBA(255, 220, 50, alpha))
    nvgStrokeWidth(nvg, 3)
    nvgStroke(nvg)

    -- 四角标记
    local cornerLen = 12
    local corners = {
        {sx - pw/2, sy - ph/2, 1, 1},
        {sx + pw/2, sy - ph/2, -1, 1},
        {sx - pw/2, sy + ph/2, 1, -1},
        {sx + pw/2, sy + ph/2, -1, -1},
    }
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 220))
    nvgStrokeWidth(nvg, 3)
    for _, c in ipairs(corners) do
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, c[1], c[2])
        nvgLineTo(nvg, c[1] + cornerLen * c[3], c[2])
        nvgMoveTo(nvg, c[1], c[2])
        nvgLineTo(nvg, c[1], c[2] + cornerLen * c[4])
        nvgStroke(nvg)
    end

    if label then
        nvgFontSize(nvg, 20)
        nvgFontFace(nvg, "sans")
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(nvg, nvgRGBA(255, 220, 50, 200))
        nvgText(nvg, sx, sy - ph/2 - 24, label, nil)
    end
end

--- 绘制假相框揭晓动画（标红 + 渐隐）
local function DrawFakeFrameReveal(nvg, sx, sy, pw, ph, progress)
    -- progress: 0→1 (从刚开始揭晓到完全消失)
    local alpha = math.floor(255 * (1.0 - progress))
    if alpha <= 0 then return end

    -- 红色填充（标红）
    nvgBeginPath(nvg)
    nvgRect(nvg, sx - pw/2, sy - ph/2, pw, ph)
    nvgFillColor(nvg, nvgRGBA(255, 40, 40, math.floor(alpha * 0.4)))
    nvgFill(nvg)

    -- 红色边框
    nvgBeginPath(nvg)
    nvgRect(nvg, sx - pw/2, sy - ph/2, pw, ph)
    nvgStrokeColor(nvg, nvgRGBA(255, 40, 40, alpha))
    nvgStrokeWidth(nvg, 3)
    nvgStroke(nvg)

    -- 大 X 标记
    local crossSize = math.min(pw, ph) * 0.3
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, sx - crossSize, sy - crossSize)
    nvgLineTo(nvg, sx + crossSize, sy + crossSize)
    nvgMoveTo(nvg, sx + crossSize, sy - crossSize)
    nvgLineTo(nvg, sx - crossSize, sy + crossSize)
    nvgStrokeColor(nvg, nvgRGBA(255, 60, 60, alpha))
    nvgStrokeWidth(nvg, 5)
    nvgLineCap(nvg, NVG_ROUND)
    nvgStroke(nvg)

    -- "假" 文字
    nvgFontSize(nvg, 28)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(255, 60, 60, alpha))
    nvgText(nvg, sx, sy - ph/2 - 32, "❌ 假相框", nil)
end

function M.DrawPhotoZone()
    local nvg = G.nvg
    if not G.photoZone.active then return end
    if G.gameState == "showPhoto" then return end

    local ppu = M.GetPixelsPerUnit()

    -- 拔河双镜头模式
    local tugZones = G.tugPhotoZones
    if tugZones and tugZones.left and tugZones.right then
        local lz = tugZones.left
        local rz = tugZones.right
        local lsx, lsy = M.PhysToScreen(lz.x, lz.y)
        local lpw, lph = lz.width * ppu, lz.height * ppu
        local rsx, rsy = M.PhysToScreen(rz.x, rz.y)
        local rpw, rph = rz.width * ppu, rz.height * ppu

        DrawSinglePhotoZoneFrame(nvg, lsx, lsy, lpw, lph, "📷 " .. G.teams[1].name)
        DrawSinglePhotoZoneFrame(nvg, rsx, rsy, rpw, rph, "📷 " .. G.teams[2].name)
        return
    end

    -- 真假相框玩法：绘制两个外观一致的相框
    local fakeZone = G.fakePhotoZone
    local reveal = G.fakeFrameReveal

    if fakeZone and fakeZone.active then
        -- 揭晓阶段：假框用红色动画，真框正常显示
        if reveal and reveal.active then
            -- 真框正常显示
            local sx, sy = M.PhysToScreen(G.photoZone.x, G.photoZone.y)
            local pw = G.photoZone.width * ppu
            local ph = G.photoZone.height * ppu
            DrawSinglePhotoZoneFrame(nvg, sx, sy, pw, ph, "📷 拍照区域")

            -- 假框揭晓动画
            local fsx, fsy = M.PhysToScreen(fakeZone.x, fakeZone.y)
            local fpw = fakeZone.width * ppu
            local fph = fakeZone.height * ppu
            local progress = reveal.timer / reveal.duration
            DrawFakeFrameReveal(nvg, fsx, fsy, fpw, fph, progress)
        else
            -- 倒计时阶段：两个框外观完全一致，无法分辨
            local sx, sy = M.PhysToScreen(G.photoZone.x, G.photoZone.y)
            local pw = G.photoZone.width * ppu
            local ph = G.photoZone.height * ppu
            DrawSinglePhotoZoneFrame(nvg, sx, sy, pw, ph, "📷 拍照区域")

            local fsx, fsy = M.PhysToScreen(fakeZone.x, fakeZone.y)
            local fpw = fakeZone.width * ppu
            local fph = fakeZone.height * ppu
            DrawSinglePhotoZoneFrame(nvg, fsx, fsy, fpw, fph, "📷 拍照区域")
        end
        return
    end

    -- 普通单镜头
    local sx, sy = M.PhysToScreen(G.photoZone.x, G.photoZone.y)
    local pw = G.photoZone.width * ppu
    local ph = G.photoZone.height * ppu
    DrawSinglePhotoZoneFrame(nvg, sx, sy, pw, ph, "📷 拍照区域")

    -- 金币玩法：在拍照区域上方显示闪动提示文字
    local gp = GAMEPLAY_DATA[G.unlock.currentGameplayIndex]
    if gp.scoringRule == "coin_top3" then
        local flashAlpha = math.floor(140 + 115 * math.sin(G.globalTime * 6))
        local hintY = sy - ph / 2 - 48
        nvgFontSize(nvg, 22)
        nvgFontFace(nvg, "sans")
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        -- 黑色描边
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, flashAlpha))
        for ox = -1, 1 do
            for oy = -1, 1 do
                if ox ~= 0 or oy ~= 0 then
                    nvgText(nvg, sx + ox, hintY + oy, "需拾取3枚以上金币", nil)
                end
            end
        end
        -- 主体文字（金黄色闪动）
        nvgFillColor(nvg, nvgRGBA(255, 240, 80, flashAlpha))
        nvgText(nvg, sx, hintY, "需拾取3枚以上金币", nil)
    end
end

-- ============================================================================
-- 玩家渲染
-- ============================================================================

--- 绘制单个玩家
function M.DrawSinglePlayer(params)
    local nvg = G.nvg
    local ppu = M.GetPixelsPerUnit()
    local r = CONFIG.PlayerRadius * G.playerScale * ppu
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
    local tweenScaleX = params.scaleX or 1.0
    local tweenScaleY = params.scaleY or 1.0
    local showGlow = params.showGlow or false
    local pillScale = params.pillScale or 1.0

    -- 当 pillScale > 1 时，Box2D 自然将 node 中心顶高了 (pillScale-1)*halfHeight
    -- 需要将绘制基准 sy 下移同等距离，使 base feet 对齐实际物理脚底
    if pillScale > 1.0 then
        sy = sy + r * 2.5 * (pillScale - 1.0)
    end

    -- 应用 squash/stretch 缩放（以角色脚底为锚点）
    local needScale = (tweenScaleX ~= 1.0 or tweenScaleY ~= 1.0)
    if needScale then
        nvgSave(nvg)
        -- 脚底位置作为缩放锚点（角色向上拉伸/压扁）
        local footY = sy + r * 2.5
        nvgTranslate(nvg, sx, footY)
        nvgScale(nvg, tweenScaleX, tweenScaleY)
        nvgTranslate(nvg, -sx, -footY)
    end

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
    local editorScale = ppu / 100 * G.playerScale

    local torsoY = sy
    local headY = torsoY - torsoH * 0.35 - headR
    local hipY = torsoY + torsoH * 0.45

    -- 脚下椭圆形圈（仅游戏中显示，拍立得不显示）
    if showGlow then
        local fe = Cfg.PLAYER_VISUALS.footEllipse
        local footEllipseY = hipY + legH + shoeH * fe.offsetY
        local ellipseRX = r * fe.radiusX
        local ellipseRY = r * fe.radiusY
        -- 按阵营颜色区分：通过 playerIndex 查找队伍
        local playerIdx = params.playerIndex or 0
        local teamIdx = G.playerTeam and G.playerTeam[playerIdx] or 0
        local tc = (teamIdx > 0 and G.teams and G.teams[teamIdx]) and G.teams[teamIdx].color or c
        nvgSave(nvg)
        nvgTranslate(nvg, sx, footEllipseY)
        nvgScale(nvg, 1.0, ellipseRY / ellipseRX)
        nvgBeginPath(nvg)
        nvgCircle(nvg, 0, 0, ellipseRX)
        nvgFillColor(nvg, nvgRGBA(tc[1], tc[2], tc[3], fe.fillAlpha))
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(tc[1], tc[2], tc[3], fe.strokeAlpha))
        nvgStrokeWidth(nvg, fe.strokeWidth)
        nvgStroke(nvg)
        nvgRestore(nvg)
    end

    if skin then
        local ac = skin.armColor
        local hc = skin.handColor
        local lc = skin.legColor
        local sc = skin.shoeColor

        -- 1. 腿部 + 鞋子
        local lt = skin.legTransform
        local legSpacing = torsoW * 0.22 + (lt and lt.spacing or 0) * editorScale
        for side = -1, 1, 2 do
            local legAngle = side == -1 and limbSwing or -limbSwing
            local legCX = sx + side * legSpacing + (lt and lt.offsetX or 0) * editorScale

            nvgSave(nvg)
            nvgTranslate(nvg, legCX, hipY + (lt and lt.offsetY or 0) * editorScale)
            nvgRotate(nvg, legAngle)

            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, -legW / 2, 0, legW, legH, legW * 0.3)
            nvgFillColor(nvg, nvgRGBA(lc[1], lc[2], lc[3], lc[4]))
            nvgFill(nvg)

            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, -shoeW / 2, legH - shoeH * 0.3, shoeW, shoeH, shoeH * 0.3)
            nvgFillColor(nvg, nvgRGBA(sc[1], sc[2], sc[3], sc[4]))
            nvgFill(nvg)

            nvgRestore(nvg)
        end

        -- 2. 躯干
        local tt = skin.torsoTransform
        nvgSave(nvg)
        nvgTranslate(nvg, sx + tt.offsetX * editorScale, torsoY + tt.offsetY * editorScale)
        nvgRotate(nvg, math.rad(tt.rotation))
        nvgScale(nvg, tt.scale, tt.scale)

        local halfTW = torsoW / 2
        local halfTH = torsoH / 2
        local cornerR = torsoW * 0.15

        if skin.torsoImg > 0 then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, -halfTW, -halfTH, torsoW, torsoH, cornerR)
            local imgPaint
            if facing < 0 then
                imgPaint = nvgImagePattern(nvg, halfTW, -halfTH, -torsoW, torsoH, 0, skin.torsoImg, 1.0)
            else
                imgPaint = nvgImagePattern(nvg, -halfTW, -halfTH, torsoW, torsoH, 0, skin.torsoImg, 1.0)
            end
            nvgFillPaint(nvg, imgPaint)
            nvgFill(nvg)
        else
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, -halfTW, -halfTH, torsoW, torsoH, cornerR)
            nvgFillColor(nvg, nvgRGBA(ac[1], ac[2], ac[3], ac[4]))
            nvgFill(nvg)
        end
        nvgRestore(nvg)

        -- 3. 头部
        local ht = skin.headTransform
        nvgSave(nvg)
        nvgTranslate(nvg, sx + ht.offsetX * editorScale, headY + ht.offsetY * editorScale)
        nvgRotate(nvg, math.rad(ht.rotation))
        nvgScale(nvg, ht.scale, ht.scale)

        if skin.headImg > 0 then
            nvgBeginPath(nvg)
            nvgCircle(nvg, 0, 0, headR)
            local headImgPaint
            if facing < 0 then
                headImgPaint = nvgImagePattern(nvg, headR, -headR, -headR * 2, headR * 2, 0, skin.headImg, 1.0)
            else
                headImgPaint = nvgImagePattern(nvg, -headR, -headR, headR * 2, headR * 2, 0, skin.headImg, 1.0)
            end
            nvgFillPaint(nvg, headImgPaint)
            nvgFill(nvg)
        else
            nvgBeginPath(nvg)
            nvgCircle(nvg, 0, 0, headR)
            nvgFillColor(nvg, nvgRGBA(hc[1], hc[2], hc[3], hc[4]))
            nvgFill(nvg)
        end
        nvgRestore(nvg)

        -- 4. 手臂 + 手掌
        local at = skin.armTransform
        local shoulderY = torsoY - torsoH * 0.3
        local armOffsetX = torsoW / 2 + armW * 0.3 + (at and at.spacing or 0) * editorScale
        for side = -1, 1, 2 do
            local armAngle = side == -1 and armSwing or -armSwing
            local armCX = sx + side * armOffsetX + (at and at.offsetX or 0) * editorScale

            nvgSave(nvg)
            nvgTranslate(nvg, armCX, shoulderY + (at and at.offsetY or 0) * editorScale)
            nvgRotate(nvg, armAngle)

            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, -armW / 2, 0, armW, armH, armW * 0.4)
            nvgFillColor(nvg, nvgRGBA(ac[1], ac[2], ac[3], ac[4]))
            nvgFill(nvg)

            nvgBeginPath(nvg)
            nvgCircle(nvg, 0, armH + handR * 0.5, handR)
            nvgFillColor(nvg, nvgRGBA(hc[1], hc[2], hc[3], hc[4]))
            nvgFill(nvg)

            nvgRestore(nvg)
        end

    else
        -- 无皮肤回退
        nvgBeginPath(nvg)
        nvgCircle(nvg, sx, sy, r)
        nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], c[4]))
        nvgFill(nvg)
    end

    -- 速度线效果
    if isMoving and onGround then
        local lineDir = -facing
        for l = 1, 3 do
            local lx = sx + lineDir * (torsoW / 2 + 4 + l * 5)
            local ly = sy - 4 + l * 5
            local lineLen = 6 + (3 - l) * 3
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, lx, ly)
            nvgLineTo(nvg, lx + lineDir * lineLen, ly)
            nvgStrokeColor(nvg, nvgRGBA(200, 200, 200, 150 - l * 40))
            nvgStrokeWidth(nvg, 1.5)
            nvgStroke(nvg)
        end
    end

    -- 跳跃气流效果
    if inAir and velY > 2 then
        for l = 1, 3 do
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx - 6 + l * 6, hipY + legH + 8 + l * 4, 2 - l * 0.4)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 120 - l * 30))
            nvgFill(nvg)
        end
    end

    -- 名字标签
    local nl = Cfg.PLAYER_VISUALS.nameLabel
    local nameY = skin and (headY - headR + nl.offsetY) or (sy - r + nl.offsetYNoSkin)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    if showGlow then
        -- 游戏中：加粗（多方向描边模拟）
        nvgFontSize(nvg, nl.fontSize)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, nl.outlineAlpha))
        local ofs = nl.outlineOffset
        for ox = -ofs, ofs do
            for oy = -ofs, ofs do
                if ox ~= 0 or oy ~= 0 then
                    nvgText(nvg, sx + ox, nameY + oy, name, nil)
                end
            end
        end
        nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 255))
        nvgText(nvg, sx, nameY, name, nil)
    else
        -- 拍立得中：普通样式
        nvgFontSize(nvg, nl.fontSizePhoto)
        nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 255))
        nvgText(nvg, sx, nameY, name, nil)
    end

    -- 碰撞体线框（调试）
    if G.showCollisionDebug then
        local capR = CONFIG.PlayerRadius * G.playerScale * ppu
        local capH = G.capsuleHeight * G.playerScale * (CONFIG.PlayerRadius / G.capsuleRadius) * ppu
        local boxH = capH - capR * 2
        if boxH < 1 then boxH = 1 end

        nvgStrokeWidth(nvg, 2.0)
        nvgStrokeColor(nvg, nvgRGBA(0, 255, 0, 200))

        nvgBeginPath(nvg)
        nvgArc(nvg, sx, sy - boxH / 2, capR, math.pi, 0, 2)
        nvgLineTo(nvg, sx + capR, sy + boxH / 2)
        nvgArc(nvg, sx, sy + boxH / 2, capR, 0, math.pi, 2)
        nvgLineTo(nvg, sx - capR, sy - boxH / 2)
        nvgClosePath(nvg)
        nvgStroke(nvg)

        local footR = capR * 0.6
        local footOffY = (capH / 2) * 0.9
        nvgBeginPath(nvg)
        nvgCircle(nvg, sx, sy + footOffY, footR)
        nvgStrokeColor(nvg, nvgRGBA(255, 255, 0, 200))
        nvgStroke(nvg)
    end

    -- 恢复 squash/stretch 变换
    if needScale then
        nvgRestore(nvg)
    end
end

function M.DrawPlayers()
    local bulletDestroyed = G.bulletDestroyedPlayers or {}
    local bulletFlashTimers = G.bulletFlashTimers or {}
    local bulletTime = G.bulletTime or 0

    for i, p in ipairs(G.players) do
        -- 被子弹击中且闪烁结束的玩家不再渲染
        if bulletDestroyed[i] and not bulletFlashTimers[i] then
            goto continue_player
        end

        local pos = p.node.position2D
        local sx, sy = M.PhysToScreen(pos.x, pos.y)
        local skinIdx = p.config.skinIndex or 1
        local skin = G.skinsRuntime[skinIdx]

        local limbSwing = 0
        local armSwing = 0
        local inAir = not p.onGround
        if inAir then
            limbSwing = 0.35
            armSwing = -(math.pi + 0.4)
        elseif p.isMoving then
            limbSwing = math.sin(p.animTime) * 0.5
            armSwing = -math.sin(p.animTime) * 0.4
        end

        -- 被子弹击中正在闪烁：透明度闪烁效果
        local bulletAlpha = 1.0
        if bulletDestroyed[i] and bulletFlashTimers[i] then
            local flashPhase = math.sin(bulletTime * Cfg.BULLET_FLASH_FREQ * math.pi * 2)
            bulletAlpha = (flashPhase > 0) and 0.8 or 0.2
        end

        local pillS = p.pillScale or 1.0
        if bulletAlpha < 1.0 then
            nvgGlobalAlpha(G.nvg, bulletAlpha)
        end
        M.DrawSinglePlayer({
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
            scaleX = (p.scale and p.scale.x or 1.0) * pillS,
            scaleY = (p.scale and p.scale.y or 1.0) * pillS,
            pillScale = pillS,
            showGlow = true,
            playerIndex = i,
        })
        if bulletAlpha < 1.0 then
            nvgGlobalAlpha(G.nvg, 1.0)
        end

        ::continue_player::
    end
end

--- 绘制拔河模式下玩家头顶个人点击数
function M.DrawTugPlayerClicks()
    local gp = GAMEPLAY_DATA[G.unlock.currentGameplayIndex]
    if gp.scoringRule ~= "tug_of_war" then return end
    if G.gameState ~= "prep" and G.gameState ~= "countdown" then return end

    local clicks = G.tugPlayerClicks
    if not clicks then return end

    local nvg = G.nvg
    local ppu = M.GetPixelsPerUnit()
    local r = CONFIG.PlayerRadius * G.playerScale * ppu

    for i, p in ipairs(G.players) do
        local count = clicks[i] or 0
        if count > 0 then
            local pos = p.node.position2D
            local sx, sy = M.PhysToScreen(pos.x, pos.y)
            local textY = sy - r - 24  -- 头顶上方

            nvgFontSize(nvg, 18)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(nvg, nvgRGBA(0, 0, 0, 150))
            nvgText(nvg, sx + 1, textY + 1, tostring(count), nil)
            local c = p.config.color
            nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 255))
            nvgText(nvg, sx, textY, tostring(count), nil)
        end
    end
end

function M.DrawPlayersSnapshot()
    local bulletDestroyed = G.bulletDestroyedPlayers or {}

    for i, snap in ipairs(G.photoSnapshot) do
        local p = G.players[i]
        if not p then break end

        -- 被子弹击中的玩家不出现在照片中
        if bulletDestroyed[i] then goto continue_snapshot end

        local sx, sy = M.PhysToScreen(snap.x, snap.y)
        local skinIdx = p.config.skinIndex or 1
        local skin = G.skinsRuntime[skinIdx]

        local limbSwing = 0
        local armSwing = 0
        local inAir = not snap.onGround
        if inAir then
            limbSwing = 0.35
            armSwing = -(math.pi + 0.4)
        elseif snap.isMoving then
            limbSwing = math.sin(snap.animTime) * 0.5
            armSwing = -math.sin(snap.animTime) * 0.4
        end

        local pillS = snap.pillScale or 1.0
        M.DrawSinglePlayer({
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
            scaleX = pillS,
            scaleY = pillS,
            pillScale = pillS,
        })

        ::continue_snapshot::
    end
end

-- ============================================================================
-- 金币渲染
-- ============================================================================

function M.DrawCoins(coins, currentGameplayIndex, coinTime, coinParticles)
    local gp = GAMEPLAY_DATA[currentGameplayIndex]
    if gp.scoringRule ~= "coin_top3" then return end
    if G.gameState == "showPhoto" or G.gameState == "bulletin" then return end

    local nvg = G.nvg
    local ppu = M.GetPixelsPerUnit()
    local t = coinTime or 0

    -- 绘制金币（带旋转动画）
    for _, coin in ipairs(coins) do
        if not coin.collected then
            local sx, sy = M.PhysToScreen(coin.x, coin.y)
            local r = Cfg.COIN_RADIUS * ppu

            -- 用水平缩放模拟3D旋转（每个金币相位不同）
            local phase = (coin.x * 2.7 + coin.y * 1.3)  -- 基于位置的随机相位
            local scaleX = math.cos(t * 3.0 + phase)      -- 旋转周期约2秒
            local absScaleX = math.abs(scaleX)

            nvgSave(nvg)
            nvgTranslate(nvg, sx, sy)
            nvgScale(nvg, 0.3 + absScaleX * 0.7, 1.0)  -- 最小缩至30%宽度

            -- 金币主体
            nvgBeginPath(nvg)
            nvgCircle(nvg, 0, 0, r)
            -- 旋转到背面时颜色略暗
            if scaleX > 0 then
                nvgFillColor(nvg, nvgRGBA(255, 210, 50, 255))
            else
                nvgFillColor(nvg, nvgRGBA(220, 170, 30, 255))
            end
            nvgFill(nvg)

            nvgStrokeColor(nvg, nvgRGBA(200, 140, 0, 255))
            nvgStrokeWidth(nvg, 2)
            nvgStroke(nvg)

            -- 只有正面显示$符号
            if absScaleX > 0.4 then
                local textAlpha = math.floor(((absScaleX - 0.4) / 0.6) * 255)
                nvgFontSize(nvg, r * 1.2)
                nvgFontFace(nvg, "sans")
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvg, nvgRGBA(160, 100, 0, textAlpha))
                nvgText(nvg, 0, 0, "$", nil)
            end

            -- 闪光高光
            nvgBeginPath(nvg)
            nvgEllipse(nvg, -r * 0.25, -r * 0.3, r * 0.2, r * 0.15)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 80))
            nvgFill(nvg)

            nvgRestore(nvg)
        end
    end

    -- 绘制金币拾取粒子
    if coinParticles then
        for _, p in ipairs(coinParticles) do
            local sx, sy = M.PhysToScreen(p.x, p.y)
            local alpha = math.floor((p.life / p.maxLife) * 255)
            local sz = p.size * ppu * (0.5 + 0.5 * (p.life / p.maxLife))

            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, sz)
            nvgFillColor(nvg, nvgRGBA(255, 220, 50, alpha))
            nvgFill(nvg)

            -- 小星星光芒
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, sz * 0.5)
            nvgFillColor(nvg, nvgRGBA(255, 255, 200, alpha))
            nvgFill(nvg)
        end
    end
end

-- ============================================================================
-- 放大药丸渲染
-- ============================================================================
function M.DrawPills(pills, currentGameplayIndex, pillTime, pillParticles)
    local gp = GAMEPLAY_DATA[currentGameplayIndex]
    if not gp.enlargePill then return end
    if G.gameState == "showPhoto" or G.gameState == "bulletin" then return end

    local nvg = G.nvg
    local ppu = M.GetPixelsPerUnit()
    local t = pillTime or 0

    -- 绘制药丸（胶囊形状，带浮动动画）
    for _, pill in ipairs(pills) do
        if not pill.collected then
            local floatY = math.sin(t * 2.5 + pill.x * 1.7) * 0.15
            local sx, sy = M.PhysToScreen(pill.x, pill.y + floatY)
            local r = Cfg.PILL_RADIUS * ppu

            nvgSave(nvg)
            nvgTranslate(nvg, sx, sy)

            -- 发光光晕
            local glowAlpha = math.floor(80 + 40 * math.sin(t * 4.0 + pill.y * 2.0))
            nvgBeginPath(nvg)
            nvgCircle(nvg, 0, 0, r * 1.6)
            nvgFillColor(nvg, nvgRGBA(50, 255, 120, glowAlpha))
            nvgFill(nvg)

            -- 药丸主体（胶囊形：左右半圆 + 中间矩形）
            local capsW = r * 1.4
            local capsH = r * 0.8
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, -capsW, -capsH, capsW * 2, capsH * 2, capsH)
            nvgFillColor(nvg, nvgRGBA(40, 220, 100, 255))
            nvgFill(nvg)
            nvgStrokeColor(nvg, nvgRGBA(20, 160, 60, 255))
            nvgStrokeWidth(nvg, 2)
            nvgStroke(nvg)

            -- 中间分割线
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, 0, -capsH)
            nvgLineTo(nvg, 0, capsH)
            nvgStrokeColor(nvg, nvgRGBA(20, 160, 60, 180))
            nvgStrokeWidth(nvg, 1.5)
            nvgStroke(nvg)

            -- 左半高光
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, -capsW + 3, -capsH + 3, capsW - 3, capsH * 2 - 6, capsH - 3)
            nvgFillColor(nvg, nvgRGBA(100, 255, 160, 60))
            nvgFill(nvg)

            -- 箭头标记（向上↑表示放大）
            nvgFontSize(nvg, r * 0.9)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 220))
            nvgText(nvg, 0, 0, "↑", nil)

            nvgRestore(nvg)
        end
    end

    -- 绘制拾取粒子
    for _, p in ipairs(pillParticles) do
        local psx, psy = M.PhysToScreen(p.x, p.y)
        local alpha = math.floor((p.life / p.maxLife) * 255)
        local size = p.size * ppu
        nvgBeginPath(nvg)
        nvgCircle(nvg, psx, psy, size)
        nvgFillColor(nvg, nvgRGBA(50, 255, 120, alpha))
        nvgFill(nvg)
    end
end

-- ============================================================================
-- 子弹渲染
-- ============================================================================

function M.DrawBullets(bullets, currentGameplayIndex, bulletTime)
    local gp = GAMEPLAY_DATA[currentGameplayIndex]
    if not gp.dodgeBullet then return end
    if G.gameState == "showPhoto" or G.gameState == "bulletin" then return end

    local nvg = G.nvg
    local ppu = M.GetPixelsPerUnit()
    local t = bulletTime or 0

    for _, b in ipairs(bullets) do
        local sx, sy = M.PhysToScreen(b.x, b.y)
        local r = Cfg.BULLET_RADIUS * ppu

        nvgSave(nvg)
        nvgTranslate(nvg, sx, sy)

        -- 子弹尾焰（运动方向的反方向）
        local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
        if speed > 0.01 then
            local tailLen = r * 2.0
            -- 物理坐标中 vy 朝上为正，屏幕坐标 Y 反向
            local dirX = -b.vx / speed
            local dirY = b.vy / speed  -- 注意：屏幕Y翻转
            local tailX = dirX * tailLen
            local tailY = dirY * tailLen

            nvgBeginPath(nvg)
            nvgMoveTo(nvg, tailX * 1.5, tailY * 1.5)
            nvgLineTo(nvg, r * 0.4 * (-dirY), r * 0.4 * dirX)
            nvgLineTo(nvg, -r * 0.4 * (-dirY), -r * 0.4 * dirX)
            nvgClosePath(nvg)
            local trailAlpha = math.floor(120 + 40 * math.sin(t * 15))
            nvgFillColor(nvg, nvgRGBA(255, 140, 50, trailAlpha))
            nvgFill(nvg)
        end

        -- 子弹外圈发光
        nvgBeginPath(nvg)
        nvgCircle(nvg, 0, 0, r * 1.4)
        local glowAlpha = math.floor(60 + 30 * math.sin(t * 8 + b.x * 3))
        nvgFillColor(nvg, nvgRGBA(255, 80, 50, glowAlpha))
        nvgFill(nvg)

        -- 子弹主体
        nvgBeginPath(nvg)
        nvgCircle(nvg, 0, 0, r)
        nvgFillColor(nvg, nvgRGBA(255, 60, 40, 255))
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(200, 30, 20, 255))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)

        -- 内部高光
        nvgBeginPath(nvg)
        nvgCircle(nvg, -r * 0.25, -r * 0.25, r * 0.4)
        nvgFillColor(nvg, nvgRGBA(255, 200, 150, 150))
        nvgFill(nvg)

        nvgRestore(nvg)
    end
end

--- 绘制拍照快照中的子弹（用于照片展示）
function M.DrawBulletsSnapshot()
    local bullets = G.bulletSnapshot
    if not bullets or #bullets == 0 then return end

    local gp = GAMEPLAY_DATA[G.unlock.currentGameplayIndex]
    if not gp.dodgeBullet then return end

    local nvg = G.nvg
    local ppu = M.GetPixelsPerUnit()

    for _, b in ipairs(bullets) do
        local sx, sy = M.PhysToScreen(b.x, b.y)
        local r = Cfg.BULLET_RADIUS * ppu

        nvgSave(nvg)
        nvgTranslate(nvg, sx, sy)

        -- 子弹外圈发光
        nvgBeginPath(nvg)
        nvgCircle(nvg, 0, 0, r * 1.4)
        nvgFillColor(nvg, nvgRGBA(255, 80, 50, 70))
        nvgFill(nvg)

        -- 子弹主体
        nvgBeginPath(nvg)
        nvgCircle(nvg, 0, 0, r)
        nvgFillColor(nvg, nvgRGBA(255, 60, 40, 255))
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(200, 30, 20, 255))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)

        -- 内部高光
        nvgBeginPath(nvg)
        nvgCircle(nvg, -r * 0.25, -r * 0.25, r * 0.4)
        nvgFillColor(nvg, nvgRGBA(255, 200, 150, 150))
        nvgFill(nvg)

        nvgRestore(nvg)
    end
end

function M.DrawPlayerCoinCount(playerCoins, currentGameplayIndex)
    local gp = GAMEPLAY_DATA[currentGameplayIndex]
    if gp.scoringRule ~= "coin_top3" then return end
    if G.gameState == "bulletin" then return end

    local nvg = G.nvg
    local ppu = M.GetPixelsPerUnit()

    for i, p in ipairs(G.players) do
        local count = playerCoins[i] or 0
        if count > 0 then
            local px, py = p.node.position2D.x, p.node.position2D.y
            local sx, sy = M.PhysToScreen(px, py)
            local offsetY = G.capsuleHeight * G.playerScale * ppu * 0.6 + 20

            local text = "\240\159\146\176" .. tostring(count)
            nvgFontSize(nvg, 20)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)

            nvgFillColor(nvg, nvgRGBA(0, 0, 0, 150))
            nvgText(nvg, sx + 1, sy - offsetY + 1, text, nil)

            nvgFillColor(nvg, nvgRGBA(255, 220, 50, 255))
            nvgText(nvg, sx, sy - offsetY, text, nil)
        end
    end
end

-- ============================================================================
-- UI 特效渲染
-- ============================================================================

function M.DrawPrepIndicator()
    if G.gameState ~= "prep" then return end
    local nvg = G.nvg
    local gp = GAMEPLAY_DATA[G.unlock.currentGameplayIndex]
    local num = math.ceil(G.prepTimer)

    -- 自定义 prep 文字（如拔河的"疯狂点击！"）
    local prepText = gp.prepText or "准备"
    local text = prepText .. " " .. tostring(num)

    -- 拔河模式位置偏上
    local centerY = G.screenH / 2
    if gp.scoringRule == "tug_of_war" then
        centerY = G.screenH * 0.3
    end

    nvgFontSize(nvg, 48)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 120))
    nvgText(nvg, G.screenW/2 + 2, centerY + 2, text, nil)

    nvgFillColor(nvg, nvgRGBA(255, 220, 80, 255))
    nvgText(nvg, G.screenW/2, centerY, text, nil)
end

function M.DrawCountdown()
    if G.gameState ~= "countdown" then return end
    local nvg = G.nvg
    local num = math.ceil(G.countdown)
    local text = tostring(num)

    local gp = GAMEPLAY_DATA[G.unlock.currentGameplayIndex]

    -- 拔河模式倒计时位置偏上（避免与角色重叠）
    local centerY = G.screenH / 2
    if gp.scoringRule == "tug_of_war" then
        centerY = G.screenH * 0.3
    end

    local scale = 1.0 + (G.countdown - math.floor(G.countdown)) * 0.3
    nvgFontSize(nvg, 80 * scale)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 150))
    nvgText(nvg, G.screenW/2 + 3, centerY + 3, text, nil)

    local urgency = math.max(0, 1 - G.countdown / gp.rushTime)
    local r = math.floor(255 * urgency)
    local g = math.floor(255 * (1 - urgency))
    nvgFillColor(nvg, nvgRGBA(r + 100, g + 100, 100, 255))
    nvgText(nvg, G.screenW/2, centerY, text, nil)
end

--- 绘制拔河分数显示（双方点击数）
function M.DrawTugScores()
    local gp = GAMEPLAY_DATA[G.unlock.currentGameplayIndex]
    if gp.scoringRule ~= "tug_of_war" then return end
    if G.gameState ~= "prep" and G.gameState ~= "countdown" then return end

    local nvg = G.nvg
    local sw, sh = G.screenW, G.screenH
    local clicks = G.tugTeamClicks
    if not clicks then return end

    local t = G.globalTime or 0
    local c1 = clicks[1] or 0
    local c2 = clicks[2] or 0
    local total = c1 + c2
    local t1c = G.teams[1].color
    local t2c = G.teams[2].color

    -- === 数字缩放：随点击数疯狂变大，上限 4.5x ===
    local baseSize = 58
    local scale1 = math.min(1.0 + c1 * 0.018, 4.5)
    local scale2 = math.min(1.0 + c2 * 0.018, 4.5)

    -- === 大方压小方：赢家侧向中间挤压，输家被推开 ===
    local baseGap = 110
    local pushAmount = 0  -- 正值=左队占优向右推，负值=右队占优向左推
    if total > 0 then
        local ratio = (c1 - c2) / math.max(total, 1)  -- -1 ~ +1
        pushAmount = ratio * 100  -- 最大偏移 100px，压迫感更强
    end

    local bottomY = sh - 70  -- 固定底部基线，文字向上生长
    local leftX = sw / 2 - baseGap + pushAmount
    local rightX = sw / 2 + baseGap + pushAmount

    -- === 抖动：基于 globalTime 的高频 sin/cos 组合，越大越疯狂 ===
    local shake1X = math.sin(t * 47.0 + 1.7) * 3.5 + math.cos(t * 67.0) * 2.5 + math.sin(t * 97.0) * 1.5
    local shake1Y = math.cos(t * 53.0 + 0.3) * 3.0 + math.sin(t * 73.0) * 2.0 + math.cos(t * 101.0) * 1.2
    local shake2X = math.sin(t * 51.0 + 3.1) * 3.5 + math.cos(t * 71.0) * 2.5 + math.sin(t * 89.0) * 1.5
    local shake2Y = math.cos(t * 43.0 + 2.1) * 3.0 + math.sin(t * 79.0) * 2.0 + math.cos(t * 103.0) * 1.2
    -- 点击越多抖动越疯狂（上限更高）
    local shakeIntensity1 = math.min(1.0 + c1 * 0.04, 6.0)
    local shakeIntensity2 = math.min(1.0 + c2 * 0.04, 6.0)
    shake1X = shake1X * shakeIntensity1
    shake1Y = shake1Y * shakeIntensity1
    shake2X = shake2X * shakeIntensity2
    shake2Y = shake2Y * shakeIntensity2

    -- === "VS" 中央文字 ===
    nvgFontSize(nvg, 26)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 220))
    nvgText(nvg, sw / 2 + pushAmount * 0.3, bottomY, "VS", nil)

    -- === 左队数字（加粗 + 描边 + 缩放 + 抖动） ===
    local fontSize1 = math.floor(baseSize * scale1)
    local numX1 = leftX + shake1X
    local numY1 = bottomY + shake1Y  -- 底部对齐，向上生长

    nvgFontSize(nvg, fontSize1)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    -- 描边（黑色粗边）
    nvgStrokeColor(nvg, nvgRGBA(0, 0, 0, 220))
    nvgStrokeWidth(nvg, 4 + scale1)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 220))
    -- 多偏移模拟粗描边
    for ox = -2, 2 do
        for oy = -2, 2 do
            if ox ~= 0 or oy ~= 0 then
                nvgText(nvg, numX1 + ox, numY1 + oy, tostring(c1), nil)
            end
        end
    end
    -- 主体填充（队伍颜色）
    nvgFillColor(nvg, nvgRGBA(t1c[1], t1c[2], t1c[3], 255))
    nvgText(nvg, numX1, numY1, tostring(c1), nil)
    -- 高光
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 80))
    nvgText(nvg, numX1, numY1 - 1, tostring(c1), nil)

    -- === 右队数字（加粗 + 描边 + 缩放 + 抖动） ===
    local fontSize2 = math.floor(baseSize * scale2)
    local numX2 = rightX + shake2X
    local numY2 = bottomY + shake2Y  -- 底部对齐，向上生长

    nvgFontSize(nvg, fontSize2)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    -- 描边
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 220))
    for ox = -2, 2 do
        for oy = -2, 2 do
            if ox ~= 0 or oy ~= 0 then
                nvgText(nvg, numX2 + ox, numY2 + oy, tostring(c2), nil)
            end
        end
    end
    -- 主体填充（队伍颜色）
    nvgFillColor(nvg, nvgRGBA(t2c[1], t2c[2], t2c[3], 255))
    nvgText(nvg, numX2, numY2, tostring(c2), nil)
    -- 高光
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 80))
    nvgText(nvg, numX2, numY2 - 1, tostring(c2), nil)

    -- === 按钮：两个被疯狂按动的大按钮，位于数字下方 ===
    local btnW = 90
    local btnH = 50
    local btnY = bottomY + 15  -- 按钮固定在数字底线下方
    local btnRadius = 12

    -- 按钮按压动画：利用点击数的快速变化模拟弹跳
    -- 使用 sin 高频模拟被快速按下的感觉
    local press1 = math.abs(math.sin(t * 25.0 + c1 * 0.7)) * 0.3
    local press2 = math.abs(math.sin(t * 28.0 + c2 * 0.9)) * 0.3
    -- 如果点击数为 0，按钮静止
    if c1 == 0 then press1 = 0 end
    if c2 == 0 then press2 = 0 end

    local pressDepth1 = press1 * 6  -- 按下深度（像素）
    local pressDepth2 = press2 * 6

    -- 左队按钮
    local btn1X = leftX - btnW / 2
    local btn1Y = btnY + pressDepth1
    -- 按钮阴影（未按下时有阴影，按下时阴影缩小）
    local shadowOff1 = math.floor(6 - pressDepth1)
    if shadowOff1 > 0 then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, btn1X, btn1Y + shadowOff1, btnW, btnH, btnRadius)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, 80))
        nvgFill(nvg)
    end
    -- 按钮底色（深色）
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, btn1X, btn1Y, btnW, btnH, btnRadius)
    local darken1 = math.floor(40 + pressDepth1 * 8)
    nvgFillColor(nvg, nvgRGBA(
        math.max(0, t1c[1] - darken1),
        math.max(0, t1c[2] - darken1),
        math.max(0, t1c[3] - darken1), 255))
    nvgFill(nvg)
    -- 按钮顶面（亮色，按下时偏移减少）
    local topOff1 = math.floor(4 - pressDepth1 * 0.7)
    if topOff1 < 0 then topOff1 = 0 end
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, btn1X, btn1Y - topOff1, btnW, btnH - 4, btnRadius)
    nvgFillColor(nvg, nvgRGBA(t1c[1], t1c[2], t1c[3], 255))
    nvgFill(nvg)
    -- 按钮高光
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, btn1X + 4, btn1Y - topOff1 + 3, btnW - 8, btnH * 0.35, btnRadius - 2)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 60 - math.floor(pressDepth1 * 8)))
    nvgFill(nvg)
    -- 按钮文字
    nvgFontSize(nvg, 18)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 240))
    nvgText(nvg, btn1X + btnW / 2, btn1Y - topOff1 + (btnH - 4) / 2, "SMASH!", nil)

    -- 右队按钮
    local btn2X = rightX - btnW / 2
    local btn2Y = btnY + pressDepth2
    local shadowOff2 = math.floor(6 - pressDepth2)
    if shadowOff2 > 0 then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, btn2X, btn2Y + shadowOff2, btnW, btnH, btnRadius)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, 80))
        nvgFill(nvg)
    end
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, btn2X, btn2Y, btnW, btnH, btnRadius)
    local darken2 = math.floor(40 + pressDepth2 * 8)
    nvgFillColor(nvg, nvgRGBA(
        math.max(0, t2c[1] - darken2),
        math.max(0, t2c[2] - darken2),
        math.max(0, t2c[3] - darken2), 255))
    nvgFill(nvg)
    local topOff2 = math.floor(4 - pressDepth2 * 0.7)
    if topOff2 < 0 then topOff2 = 0 end
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, btn2X, btn2Y - topOff2, btnW, btnH - 4, btnRadius)
    nvgFillColor(nvg, nvgRGBA(t2c[1], t2c[2], t2c[3], 255))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, btn2X + 4, btn2Y - topOff2 + 3, btnW - 8, btnH * 0.35, btnRadius - 2)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 60 - math.floor(pressDepth2 * 8)))
    nvgFill(nvg)
    nvgFontSize(nvg, 18)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 240))
    nvgText(nvg, btn2X + btnW / 2, btn2Y - topOff2 + (btnH - 4) / 2, "SMASH!", nil)
end

function M.DrawFlashEffect()
    if G.gameState ~= "flash" then return end
    local nvg = G.nvg
    local alpha = math.floor((G.flashTimer / 0.3) * 255)
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, G.screenW, G.screenH)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.min(alpha, 220)))
    nvgFill(nvg)
end

--- 拔河模式照片展示（获胜队/平局双照片）
function M.DrawTugShowPhoto(progress)
    local nvg = G.nvg
    local sw, sh = G.screenW, G.screenH
    local tugZones = G.tugPhotoZones
    local winner = G.tugWinner  -- 1, 2, or 0 (tie)
    local clicks = G.tugTeamClicks or { 0, 0 }

    -- 决定要展示哪些照片
    local zonesToShow = {}
    if winner == 0 then
        -- 平局：两张照片并排
        table.insert(zonesToShow, { zone = tugZones.left, teamIdx = 1 })
        table.insert(zonesToShow, { zone = tugZones.right, teamIdx = 2 })
    elseif winner == 1 then
        table.insert(zonesToShow, { zone = tugZones.left, teamIdx = 1 })
    else
        table.insert(zonesToShow, { zone = tugZones.right, teamIdx = 2 })
    end

    local photoCount = #zonesToShow
    local maxPhotoW = (photoCount == 1) and (sw * 0.55) or (sw * 0.4)
    local maxPhotoH = sh * 0.45

    for idx, item in ipairs(zonesToShow) do
        local zone = item.zone
        local teamIdx = item.teamIdx
        local zoneAspect = zone.width / zone.height

        local photoW, photoH
        if maxPhotoW / zoneAspect <= maxPhotoH then
            photoW = maxPhotoW
            photoH = maxPhotoW / zoneAspect
        else
            photoH = maxPhotoH
            photoW = maxPhotoH * zoneAspect
        end

        local framePad = math.floor(photoW * 0.05)
        local frameBottom = math.floor(photoH * 0.22)
        local totalW = photoW + framePad * 2
        local totalH = photoH + framePad + frameBottom

        -- 位置计算
        local frameX, frameY
        if photoCount == 1 then
            frameX = (sw - totalW) / 2
        else
            if idx == 1 then
                frameX = sw / 2 - totalW - 10
            else
                frameX = sw / 2 + 10
            end
        end
        frameY = (sh - totalH) / 2 - sh * 0.02
        local offsetY = (1.0 - progress) * 40
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

        -- 照片内容区域
        local photoX = frameX + framePad
        local photoY = frameY + framePad

        nvgScissor(nvg, photoX, photoY, photoW, photoH)

        local ppu = M.GetPixelsPerUnit()
        local zoneCenterSX, zoneCenterSY = M.PhysToScreen(zone.x, zone.y)
        local zoneScreenW = zone.width * ppu
        local zoneScreenH = zone.height * ppu

        local scaleX = photoW / zoneScreenW
        local scaleY = photoH / zoneScreenH
        local scale = math.min(scaleX, scaleY)

        local photoCenterX = photoX + photoW / 2
        local photoCenterY = photoY + photoH / 2

        nvgSave(nvg)
        nvgTranslate(nvg, photoCenterX, photoCenterY)
        nvgScale(nvg, scale, scale)
        nvgTranslate(nvg, -zoneCenterSX, -zoneCenterSY)

        M.DrawBackground()
        M.DrawPlatforms()
        M.DrawPlayersSnapshot()

        nvgRestore(nvg)
        nvgResetScissor(nvg)

        -- 底部结果文字
        local tc = G.teams[teamIdx].color
        local textY = photoY + photoH + frameBottom * 0.5
        nvgFontSize(nvg, math.max(16, math.floor(frameBottom * 0.4)))
        nvgFontFace(nvg, "sans")
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(tc[1], tc[2], tc[3], math.floor(255 * progress)))

        local teamName = G.teams[teamIdx].name
        local clickStr = tostring(clicks[teamIdx]) .. " clicks"
        if winner == 0 then
            nvgText(nvg, frameX + totalW / 2, textY, teamName .. " " .. clickStr .. " 平局!", nil)
        else
            nvgText(nvg, frameX + totalW / 2, textY, teamName .. " 获胜! " .. clickStr, nil)
        end

        -- 顶部 PHOTO 标签
        nvgFontSize(nvg, 13)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(180 * progress)))
        nvgText(nvg, frameX + totalW / 2, frameY - 6, "PHOTO", nil)
    end
end

function M.DrawShowPhoto()
    if G.gameState ~= "showPhoto" then return end
    local nvg = G.nvg
    local sw, sh = G.screenW, G.screenH

    local progress = math.min(1.0, (2.5 - G.showPhotoTimer) / 0.3)

    -- 判断是否已进入"规则展示"阶段
    local showRule = G.nextRoundPrepared
    -- 规则面板的弹入进度 (0→1)
    local ruleProgress = 0
    if showRule then
        ruleProgress = math.min(1.0, (1.0 - G.showPhotoTimer) / 0.4)  -- 0.4s 弹入动画
    end

    nvgSave(nvg)

    -- 全屏遮罩
    local maskAlpha = math.floor(200 * progress)
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, sw, sh)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, maskAlpha))
    nvgFill(nvg)

    -- 拔河模式：展示获胜队伍照片（或平局双照片）
    local prevGpIndex = G.unlock.currentGameplayIndex
    -- 如果规则已准备，当前 gameplayIndex 已经是下一轮的了，照片用的是上一轮
    local tugZones = G.tugPhotoZones
    if not showRule then
        local gp = GAMEPLAY_DATA[prevGpIndex]
        if gp.scoringRule == "tug_of_war" and tugZones and tugZones.left then
            M.DrawTugShowPhoto(progress)
            nvgRestore(nvg)
            return
        end
    end

    -- 布局计算：上部拍立得，下部规则面板
    local photoAreaH = showRule and (sh * 0.55) or sh  -- 规则展示时，拍立得占上方 55%
    local ruleAreaH = sh * 0.45  -- 规则面板占下方 45%

    -- 拍立得照片展示（上半部分）
    local zoneAspect = G.photoZone.width / G.photoZone.height
    local maxPhotoW = sw * 0.60
    local maxPhotoH = (showRule and (photoAreaH * 0.75)) or (sh * 0.50)
    local photoW, photoH

    if maxPhotoW / zoneAspect <= maxPhotoH then
        photoW = maxPhotoW
        photoH = maxPhotoW / zoneAspect
    else
        photoH = maxPhotoH
        photoW = maxPhotoH * zoneAspect
    end

    local framePad = math.floor(photoW * 0.05)
    local frameBottom = math.floor(photoH * 0.20)
    local totalW = photoW + framePad * 2
    local totalH = photoH + framePad + frameBottom

    local frameX = (sw - totalW) / 2
    local frameY
    if showRule then
        -- 拍立得向上移动
        local targetY = (photoAreaH - totalH) / 2 - sh * 0.02
        local startY = (sh - totalH) / 2 - sh * 0.03
        local moveProgress = math.min(1.0, ruleProgress)
        frameY = startY + (targetY - startY) * moveProgress
    else
        frameY = (sh - totalH) / 2 - sh * 0.03
    end
    local offsetY = (1.0 - progress) * 40
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

    -- 照片内容区域
    local photoX = frameX + framePad
    local photoY = frameY + framePad

    nvgScissor(nvg, photoX, photoY, photoW, photoH)

    local ppu = M.GetPixelsPerUnit()
    local zoneCenterSX, zoneCenterSY = M.PhysToScreen(G.photoZone.x, G.photoZone.y)
    local zoneScreenW = G.photoZone.width * ppu
    local zoneScreenH = G.photoZone.height * ppu

    local scaleX = photoW / zoneScreenW
    local scaleY = photoH / zoneScreenH
    local scale = math.min(scaleX, scaleY)

    local photoCenterX = photoX + photoW / 2
    local photoCenterY = photoY + photoH / 2

    nvgSave(nvg)
    nvgTranslate(nvg, photoCenterX, photoCenterY)
    nvgScale(nvg, scale, scale)
    nvgTranslate(nvg, -zoneCenterSX, -zoneCenterSY)

    M.DrawBackground()
    M.DrawPlatforms()

    -- 拍照区域边框
    local zsx, zsy = M.PhysToScreen(G.photoZone.x, G.photoZone.y)
    local zpw = G.photoZone.width * ppu
    local zph = G.photoZone.height * ppu
    nvgBeginPath(nvg)
    nvgRect(nvg, zsx - zpw/2, zsy - zph/2, zpw, zph)
    nvgFillColor(nvg, nvgRGBA(255, 220, 50, 30))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRect(nvg, zsx - zpw/2, zsy - zph/2, zpw, zph)
    nvgStrokeColor(nvg, nvgRGBA(255, 220, 50, 160))
    nvgStrokeWidth(nvg, 3)
    nvgStroke(nvg)

    -- 照片中的子弹快照
    M.DrawBulletsSnapshot()

    M.DrawPlayersSnapshot()

    nvgRestore(nvg)
    nvgResetScissor(nvg)

    -- 暗角
    local vigAlpha = math.floor(40 * progress)
    nvgBeginPath(nvg)
    nvgRect(nvg, photoX, photoY, photoW, photoH * 0.15)
    local topVig = nvgLinearGradient(nvg, photoX, photoY, photoX, photoY + photoH * 0.15,
        nvgRGBA(0, 0, 0, vigAlpha), nvgRGBA(0, 0, 0, 0))
    nvgFillPaint(nvg, topVig)
    nvgFill(nvg)

    nvgBeginPath(nvg)
    nvgRect(nvg, photoX, photoY + photoH * 0.85, photoW, photoH * 0.15)
    local botVig = nvgLinearGradient(nvg, photoX, photoY + photoH * 0.85, photoX, photoY + photoH,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, vigAlpha))
    nvgFillPaint(nvg, botVig)
    nvgFill(nvg)

    -- 顶部 PHOTO 标签
    nvgFontSize(nvg, 13)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(180 * progress)))
    nvgText(nvg, sw / 2, frameY - 6, "PHOTO", nil)

    -- ====================================================================
    -- 下一关规则面板（底部弹入）
    -- ====================================================================
    if showRule and ruleProgress > 0 then
        M.DrawNextRulePanel(sw, sh, photoAreaH, ruleAreaH, ruleProgress)
    end

    -- ====================================================================
    -- 拍立得外部下方：入镜角色弹性出场动画 + 头顶得分飘字（层级高于规则面板）
    -- 按队伍分组，用队伍颜色线框圈起来，每个头像带 P1/P2 徽章
    -- ====================================================================
    if #G.roundResult > 0 then
        -- 动画时间
        local animStartDelay = 0.4
        local perCharDelay = 0.25
        local elapsed = (2.5 - G.showPhotoTimer)

        -- 按队伍分组
        local team1Members = {} -- 蓝队入镜成员
        local team2Members = {} -- 红队入镜成员
        for _, idx in ipairs(G.roundResult) do
            local teamIdx = G.playerTeam and G.playerTeam[idx] or 1
            if teamIdx == 1 then
                table.insert(team1Members, idx)
            else
                table.insert(team2Members, idx)
            end
        end

        local charAreaY = photoY + photoH + frameBottom * 0.5
        local avatarR = 28
        local avatarSpacing = 64 -- 同组内头像间距
        local groupGap = 30 -- 两组之间间距
        local groupPadX = 16 -- 组框左右内边距
        local groupPadY = 12 -- 组框上下内边距

        -- 计算各组宽度
        local function groupWidth(members)
            if #members == 0 then return 0 end
            return (#members - 1) * avatarSpacing + avatarR * 2 + groupPadX * 2
        end
        local w1 = groupWidth(team1Members)
        local w2 = groupWidth(team2Members)
        local totalGroupW = w1 + w2 + (w1 > 0 and w2 > 0 and groupGap or 0)

        -- 起始 X（居中排列）
        local startX = sw / 2 - totalGroupW / 2

        -- easeOutBack 弹性缓动
        local function easeOutBack(t)
            local c1 = 1.70158
            local c3 = c1 + 1
            return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
        end

        -- 绘制一组队伍
        local globalSeq = 0 -- 全局顺序计数（用于动画延迟）
        local function drawTeamGroup(members, groupX, teamColor)
            if #members == 0 then return end

            -- 组框动画（取组内第一个成员的动画进度）
            local firstDelay = animStartDelay + globalSeq * perCharDelay
            local groupElapsed = elapsed - firstDelay
            local groupT = math.min(1.0, math.max(0, groupElapsed / 0.5))
            local groupEased = easeOutBack(math.max(0.01, groupT))

            -- 绘制队伍颜色线框（圆角矩形）
            if groupT > 0 then
                local gfW = (#members - 1) * avatarSpacing + avatarR * 2 + groupPadX * 2
                local gfH = avatarR * 2 + groupPadY * 2
                local gfX = groupX
                local gfTopY = charAreaY - avatarR - groupPadY

                nvgSave(nvg)
                nvgGlobalAlpha(nvg, math.min(1.0, groupEased) * progress)
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, gfX, gfTopY, gfW, gfH, 12)
                nvgStrokeColor(nvg, nvgRGBA(teamColor[1], teamColor[2], teamColor[3], math.floor(200 * groupEased)))
                nvgStrokeWidth(nvg, 2.5)
                nvgStroke(nvg)
                -- 半透明填充
                nvgFillColor(nvg, nvgRGBA(teamColor[1], teamColor[2], teamColor[3], math.floor(20 * groupEased)))
                nvgFill(nvg)
                nvgRestore(nvg)
            end

            -- 绘制每个成员头像
            for i, idx in ipairs(members) do
                local p = G.players[idx]
                if not p then
                    globalSeq = globalSeq + 1
                    goto continue_team_member
                end

                local skinIdx = p.config.skinIndex or 1
                local skin = G.skinsRuntime[skinIdx]
                local charDelay = animStartDelay + globalSeq * perCharDelay
                local charElapsed = elapsed - charDelay
                globalSeq = globalSeq + 1

                if charElapsed > 0 then
                    local animDuration = 0.5
                    local t = math.min(1.0, charElapsed / animDuration)
                    local easedT = easeOutBack(t)

                    local cx = groupX + groupPadX + avatarR + (i - 1) * avatarSpacing
                    local cy = charAreaY

                    -- 从下方弹入
                    local startOffsetY = 60
                    local currentOffsetY = startOffsetY * (1.0 - easedT)
                    local drawY = cy + currentOffsetY
                    local scaleVal = easedT
                    local drawAlpha = math.min(1.0, easedT * 1.5)

                    nvgSave(nvg)
                    nvgGlobalAlpha(nvg, drawAlpha * progress)

                    local headImg = skin and skin.headImg or -1
                    local tc = p.config.color

                    -- 发光光环
                    local glowPhase = math.sin((G.globalTime or 0) * 3.0 + globalSeq * 1.2) * 0.3 + 0.7
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, cx, drawY, avatarR + 6 + glowPhase * 3)
                    nvgFillColor(nvg, nvgRGBA(tc[1], tc[2], tc[3], math.floor(30 * scaleVal)))
                    nvgFill(nvg)

                    -- 星星粒子
                    local starCount = 3
                    local starTime = (G.globalTime or 0) * 2.0 + globalSeq * 0.8
                    for si = 1, starCount do
                        local angle = starTime + (si / starCount) * math.pi * 2
                        local dist = avatarR + 10 + math.sin(starTime * 1.5 + si) * 4
                        local sx2 = cx + math.cos(angle) * dist
                        local sy2 = drawY + math.sin(angle) * dist
                        local starSize = 2.0 + math.sin(starTime * 3 + si * 2) * 0.8
                        nvgBeginPath(nvg)
                        nvgCircle(nvg, sx2, sy2, starSize * scaleVal)
                        nvgFillColor(nvg, nvgRGBA(255, 220, 80, math.floor(160 * scaleVal)))
                        nvgFill(nvg)
                    end

                    -- 头像背景圈（队伍色）
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, cx, drawY, avatarR + 3)
                    nvgFillColor(nvg, nvgRGBA(tc[1], tc[2], tc[3], math.floor(200 * scaleVal)))
                    nvgFill(nvg)

                    -- 头像
                    if headImg and headImg > 0 then
                        nvgBeginPath(nvg)
                        nvgCircle(nvg, cx, drawY, avatarR)
                        local imgPaint = nvgImagePattern(nvg, cx - avatarR, drawY - avatarR,
                            avatarR * 2, avatarR * 2, 0, headImg, 1.0)
                        nvgFillPaint(nvg, imgPaint)
                        nvgFill(nvg)
                    else
                        nvgBeginPath(nvg)
                        nvgCircle(nvg, cx, drawY, avatarR)
                        nvgFillColor(nvg, nvgRGBA(tc[1], tc[2], tc[3], math.floor(255 * scaleVal)))
                        nvgFill(nvg)
                    end

                    -- P1/P2 徽章（右下角小圆）
                    local badgeR = 11
                    local badgeX = cx + avatarR * 0.65
                    local badgeY = drawY + avatarR * 0.65
                    -- 徽章背景
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, badgeX, badgeY, badgeR)
                    nvgFillColor(nvg, nvgRGBA(tc[1], tc[2], tc[3], math.floor(240 * scaleVal)))
                    nvgFill(nvg)
                    -- 徽章边框
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, badgeX, badgeY, badgeR)
                    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, math.floor(220 * scaleVal)))
                    nvgStrokeWidth(nvg, 1.5)
                    nvgStroke(nvg)
                    -- 徽章文字
                    nvgFontSize(nvg, 11)
                    nvgFontFace(nvg, "sans")
                    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(255 * scaleVal)))
                    nvgText(nvg, badgeX, badgeY, p.config.name or ("P" .. idx), nil)

                    -- 头顶得分飘字（不消失）
                    local scoreText = "+1"
                    local scoreY = drawY - avatarR - 16
                    local textAnimT = math.min(1.0, math.max(0, (charElapsed - 0.2) / 0.3))
                    local textEased = easeOutBack(textAnimT)
                    local textScale = textEased
                    local textOffsetY = (1.0 - textEased) * 15

                    if textAnimT > 0 then
                        nvgSave(nvg)
                        nvgTranslate(nvg, cx, scoreY - textOffsetY)
                        nvgScale(nvg, textScale, textScale)
                        nvgTranslate(nvg, -cx, -(scoreY - textOffsetY))

                        nvgFontSize(nvg, 22)
                        nvgFontFace(nvg, "sans")
                        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                        -- 描边
                        nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(180 * textAnimT)))
                        local ofs = 1.5
                        for ox = -ofs, ofs, ofs do
                            for oy = -ofs, ofs, ofs do
                                if ox ~= 0 or oy ~= 0 then
                                    nvgText(nvg, cx + ox, scoreY - textOffsetY + oy, scoreText, nil)
                                end
                            end
                        end
                        -- 金色文字
                        nvgFillColor(nvg, nvgRGBA(255, 220, 50, math.floor(255 * textAnimT)))
                        nvgText(nvg, cx, scoreY - textOffsetY, scoreText, nil)
                        nvgRestore(nvg)
                    end

                    nvgRestore(nvg)
                end

                ::continue_team_member::
            end
        end

        -- 绘制蓝队组（左侧）
        local curX = startX
        if #team1Members > 0 then
            local tc1 = G.teams and G.teams[1] and G.teams[1].color or {80, 140, 255, 255}
            drawTeamGroup(team1Members, curX, tc1)
            curX = curX + w1 + groupGap
        end
        -- 绘制红队组（右侧）
        if #team2Members > 0 then
            local tc2 = G.teams and G.teams[2] and G.teams[2].color or {255, 90, 80, 255}
            drawTeamGroup(team2Members, curX, tc2)
        end
    else
        -- 没人入镜：显示红色X特效（层级高于规则面板）
        local animElapsed = (2.5 - G.showPhotoTimer) - 0.3
        if animElapsed > 0 then
            local failY = photoY + photoH + frameBottom * 0.5
            local function easeOutBack(t)
                local c1 = 1.70158
                local c3 = c1 + 1
                return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
            end
            local t = math.min(1.0, animElapsed / 0.4)
            local easedT = easeOutBack(t)
            local scaleVal = easedT

            nvgSave(nvg)
            nvgGlobalAlpha(nvg, progress)
            nvgTranslate(nvg, sw / 2, failY)
            nvgScale(nvg, scaleVal, scaleVal)
            nvgTranslate(nvg, -(sw / 2), -failY)

            -- 红色X图标
            local xSize = 18
            nvgBeginPath(nvg)
            nvgCircle(nvg, sw / 2, failY, 28)
            nvgFillColor(nvg, nvgRGBA(220, 60, 60, math.floor(200 * scaleVal)))
            nvgFill(nvg)
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, sw / 2 - xSize, failY - xSize)
            nvgLineTo(nvg, sw / 2 + xSize, failY + xSize)
            nvgMoveTo(nvg, sw / 2 + xSize, failY - xSize)
            nvgLineTo(nvg, sw / 2 - xSize, failY + xSize)
            nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, math.floor(255 * scaleVal)))
            nvgStrokeWidth(nvg, 4)
            nvgLineCap(nvg, NVG_ROUND)
            nvgStroke(nvg)

            nvgRestore(nvg)

            -- "无人入镜" 文字说明
            nvgSave(nvg)
            nvgGlobalAlpha(nvg, progress * math.min(1.0, easedT))
            nvgFontSize(nvg, 18)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            -- 描边
            nvgFillColor(nvg, nvgRGBA(0, 0, 0, 150))
            local ofs = 1.0
            for ox = -ofs, ofs, ofs do
                for oy = -ofs, ofs, ofs do
                    if ox ~= 0 or oy ~= 0 then
                        nvgText(nvg, sw / 2 + ox, failY + 34 + oy, "无人入镜", nil)
                    end
                end
            end
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 230))
            nvgText(nvg, sw / 2, failY + 34, "无人入镜", nil)
            nvgRestore(nvg)
        end
    end

    nvgRestore(nvg)
end

--- 绘制下一关规则面板（从底部弹入）
function M.DrawNextRulePanel(sw, sh, photoAreaH, ruleAreaH, ruleProgress, overrideTitle)
    local nvg = G.nvg

    -- easeOutBack 缓动
    local function easeOutBack(t)
        local c1 = 1.70158
        local c3 = c1 + 1
        return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
    end
    local easedProgress = easeOutBack(math.min(1.0, ruleProgress))

    -- 面板尺寸和位置
    local panelW = math.min(sw * 0.9, 800)
    local panelH = ruleAreaH * 0.88
    local panelX = (sw - panelW) / 2
    local targetPanelY = photoAreaH + (ruleAreaH - panelH) / 2
    local startPanelY = sh + 20  -- 从屏幕底部下方开始
    local panelY = startPanelY + (targetPanelY - startPanelY) * easedProgress

    -- 面板背景（毛玻璃效果模拟）
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, panelX, panelY, panelW, panelH, 16)
    local panelGrad = nvgLinearGradient(nvg, panelX, panelY, panelX, panelY + panelH,
        nvgRGBA(200, 210, 235, math.floor(230 * easedProgress)),
        nvgRGBA(180, 190, 220, math.floor(240 * easedProgress)))
    nvgFillPaint(nvg, panelGrad)
    nvgFill(nvg)

    -- 边框
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, panelX, panelY, panelW, panelH, 16)
    nvgStrokeColor(nvg, nvgRGBA(140, 160, 200, math.floor(180 * easedProgress)))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)

    -- 获取玩法数据
    local gp = GAMEPLAY_DATA[G.unlock.currentGameplayIndex]
    local gpName = gp and gp.name or "常规拍照"
    local gpDesc = gp and gp.description or ""

    -- 标题
    local titleY = panelY + panelH * 0.18
    nvgFontSize(nvg, 48)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(30, 40, 60, math.floor(255 * easedProgress)))
    -- 模拟加粗：多方向偏移
    local titleStr = overrideTitle or ("下一照片：" .. gpName)
    for _, off in ipairs({{-1.0,0},{1.0,0},{0,-1.0},{0,1.0}}) do
        nvgText(nvg, sw / 2 + off[1], titleY + off[2], titleStr, nil)
    end
    nvgText(nvg, sw / 2, titleY, titleStr, nil)

    -- 玩法规则描述（居中，大字号）
    local descY = panelY + panelH * 0.42
    nvgFontSize(nvg, 36)
    nvgFillColor(nvg, nvgRGBA(50, 60, 80, math.floor(240 * easedProgress)))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(nvg, sw / 2, descY, gpDesc, nil)

    -- 确认提示文字 + 按键动效
    local promptY = panelY + panelH * 0.58
    nvgFontSize(nvg, 28)
    local promptAlpha = math.floor((math.sin(G.globalTime * 3) * 0.2 + 0.8) * 220 * easedProgress)
    nvgFillColor(nvg, nvgRGBA(80, 90, 120, promptAlpha))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    -- 计算文字宽度以居中整体（文字+按键图标）
    local promptStr = "知悉规则后单击 跳跃键 准备"
    local textW = nvgTextBounds(nvg, 0, 0, promptStr, nil, nil)
    local iconW = 36  -- 按键图标宽度
    local totalW = textW + 10 + iconW
    local startTextX = (sw - totalW) / 2

    nvgFillColor(nvg, nvgRGBA(80, 90, 120, promptAlpha))
    nvgText(nvg, startTextX, promptY, promptStr, nil)

    -- ↑ 按键图标（不断按下的动效）
    local keyX = startTextX + textW + 12
    local keyW = 34
    local keyH = 38
    local maxPress = 8  -- 最大按下位移（像素）
    local shadowFullH = 8  -- 未按下时阴影高度

    -- 按下动画：快速按下，短暂保持，缓慢弹起
    local t = G.globalTime
    local cycle = (t * 2.0) % 1.0  -- 每秒2次
    local pressDepth = 0.0  -- 0=未按下, 1=完全按下
    if cycle < 0.12 then
        pressDepth = cycle / 0.12  -- 快速按下
    elseif cycle < 0.25 then
        pressDepth = 1.0  -- 保持按下
    elseif cycle < 0.55 then
        pressDepth = 1.0 - (cycle - 0.25) / 0.3  -- 弹起
    else
        pressDepth = 0.0  -- 静止等待
    end

    local press = pressDepth * maxPress
    local shadowH = shadowFullH * (1.0 - pressDepth)
    local keyTopY = promptY - keyH / 2 + press  -- 按键顶部Y（按下时整体下移）

    -- 阴影（在按键下方，按下时缩小）
    local shadowY = promptY + keyH / 2  -- 阴影固定在底部基线
    if shadowH > 0.5 then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, keyX, shadowY, keyW, shadowH, 2)
        nvgFillColor(nvg, nvgRGBA(40, 45, 70, math.floor(160 * easedProgress)))
        nvgFill(nvg)
    end

    -- 按键主体（按下时变暗一点）
    local keyBrightness = 240 - math.floor(pressDepth * 30)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, keyX, keyTopY, keyW, keyH, 4)
    nvgFillColor(nvg, nvgRGBA(keyBrightness, keyBrightness, keyBrightness + 5, math.floor(255 * easedProgress)))
    nvgFill(nvg)
    nvgStrokeColor(nvg, nvgRGBA(50, 60, 90, math.floor(220 * easedProgress)))
    nvgStrokeWidth(nvg, 2.5)
    nvgStroke(nvg)

    -- ↑ 箭头（跟随按键移动）
    local arrowCX = keyX + keyW / 2
    local arrowCY = keyTopY + keyH / 2
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, arrowCX, arrowCY - 9)
    nvgLineTo(nvg, arrowCX - 8, arrowCY + 5)
    nvgLineTo(nvg, arrowCX + 8, arrowCY + 5)
    nvgClosePath(nvg)
    nvgFillColor(nvg, nvgRGBA(40, 50, 80, math.floor(240 * easedProgress)))
    nvgFill(nvg)

    -- 玩家皮肤头像确认区域（按阵营分组）
    local dotY = panelY + panelH * 0.78
    local avatarR = 30
    local dotSpacing = avatarR * 2 + 16
    local teamGap = 100  -- 两队之间的间距

    -- 收集两队成员
    local team1Members = (G.teams and G.teams[1]) and G.teams[1].members or {}
    local team2Members = (G.teams and G.teams[2]) and G.teams[2].members or {}
    local t1Color = (G.teams and G.teams[1]) and G.teams[1].color or {80, 140, 255, 255}
    local t2Color = (G.teams and G.teams[2]) and G.teams[2].color or {255, 90, 80, 255}

    -- 计算两组的总宽度
    local t1Width = math.max(0, (#team1Members - 1)) * dotSpacing
    local t2Width = math.max(0, (#team2Members - 1)) * dotSpacing
    local totalWidth = t1Width + teamGap + t2Width
    local startX = (sw - totalWidth) / 2

    -- 绘制队伍背景框的辅助函数
    local function drawTeamBg(groupStartX, memberCount, teamColor)
        if memberCount == 0 then return end
        local bgPadX = avatarR + 8
        local bgPadY = avatarR + 6
        local bgW = (memberCount - 1) * dotSpacing + bgPadX * 2
        local bgH = bgPadY * 2
        local bgX = groupStartX - bgPadX
        local bgY = dotY - bgPadY
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, bgX, bgY, bgW, bgH, 12)
        nvgFillColor(nvg, nvgRGBA(teamColor[1], teamColor[2], teamColor[3], math.floor(30 * easedProgress)))
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(teamColor[1], teamColor[2], teamColor[3], math.floor(100 * easedProgress)))
        nvgStrokeWidth(nvg, 1.5)
        nvgStroke(nvg)
    end

    -- 绘制单个头像的辅助函数
    local function drawAvatar(dx, playerIdx, displayIdx)
        local confirmed = G.bulletin.confirmed[playerIdx]
        local pdata = G.players[playerIdx] and G.players[playerIdx].config
        local skinIdx = pdata and pdata.skinIndex or 1
        local skin = G.skinsRuntime[skinIdx]
        local headImg = skin and skin.headImg or -1

        -- 头像圆形裁剪绘制
        if headImg > 0 then
            local imgPaint = nvgImagePattern(nvg, dx - avatarR, dotY - avatarR,
                avatarR * 2, avatarR * 2, 0, headImg, easedProgress)
            nvgBeginPath(nvg)
            nvgCircle(nvg, dx, dotY, avatarR)
            nvgFillPaint(nvg, imgPaint)
            nvgFill(nvg)
        else
            local c = pdata and pdata.color or {180, 180, 180, 255}
            nvgBeginPath(nvg)
            nvgCircle(nvg, dx, dotY, avatarR)
            nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], math.floor(220 * easedProgress)))
            nvgFill(nvg)
        end

        if confirmed then
            -- 已确认：阵营色描边
            local teamIdx = G.playerTeam and G.playerTeam[playerIdx] or 0
            local tc = (teamIdx > 0 and G.teams[teamIdx]) and G.teams[teamIdx].color or {100, 200, 100, 255}
            nvgBeginPath(nvg)
            nvgCircle(nvg, dx, dotY, avatarR + 2)
            nvgStrokeColor(nvg, nvgRGBA(tc[1], tc[2], tc[3], math.floor(255 * easedProgress)))
            nvgStrokeWidth(nvg, 3.0)
            nvgStroke(nvg)

            -- 右上角绿色徽章 + 白色对勾
            local badgeR = 6
            local badgeX = dx + avatarR * 0.65
            local badgeY = dotY - avatarR * 0.65
            nvgBeginPath(nvg)
            nvgCircle(nvg, badgeX, badgeY, badgeR)
            nvgFillColor(nvg, nvgRGBA(60, 190, 80, math.floor(255 * easedProgress)))
            nvgFill(nvg)
            nvgBeginPath(nvg)
            nvgCircle(nvg, badgeX, badgeY, badgeR)
            nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, math.floor(255 * easedProgress)))
            nvgStrokeWidth(nvg, 1.5)
            nvgStroke(nvg)
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, badgeX - 3, badgeY)
            nvgLineTo(nvg, badgeX - 0.5, badgeY + 2.5)
            nvgLineTo(nvg, badgeX + 3.5, badgeY - 2)
            nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, math.floor(255 * easedProgress)))
            nvgStrokeWidth(nvg, 1.8)
            nvgLineCap(nvg, NVG_ROUND)
            nvgLineJoin(nvg, NVG_ROUND)
            nvgStroke(nvg)
        else
            -- 未确认：半透明边框
            nvgBeginPath(nvg)
            nvgCircle(nvg, dx, dotY, avatarR + 1)
            nvgStrokeColor(nvg, nvgRGBA(120, 130, 160, math.floor(150 * easedProgress)))
            nvgStrokeWidth(nvg, 1.5)
            nvgStroke(nvg)
        end

        -- 头像下方 P1/P2 标签
        nvgFontSize(nvg, 20)
        nvgFontFace(nvg, "sans")
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(nvg, nvgRGBA(60, 70, 90, math.floor(200 * easedProgress)))
        nvgText(nvg, dx, dotY + avatarR + 5, "P" .. tostring(playerIdx), nil)
    end

    -- 绘制蓝队（左侧）
    local t1StartX = startX
    drawTeamBg(t1StartX, #team1Members, t1Color)
    for idx, playerIdx in ipairs(team1Members) do
        local dx = t1StartX + (idx - 1) * dotSpacing
        drawAvatar(dx, playerIdx)
    end

    -- 绘制红队（右侧）
    local t2StartX = startX + t1Width + teamGap
    drawTeamBg(t2StartX, #team2Members, t2Color)
    for idx, playerIdx in ipairs(team2Members) do
        local dx = t2StartX + (idx - 1) * dotSpacing
        drawAvatar(dx, playerIdx)
    end


end

-- ============================================================================
-- 公告板渲染
-- ============================================================================

function M.DrawBulletin()
    if G.gameState ~= "bulletin" then return end
    local nvg = G.nvg
    local sw, sh = G.screenW, G.screenH

    local progress = 0
    if G.bulletin.animPhase == "enter" then
        progress = math.min(1.0, G.bulletin.animTimer / G.bulletin.enterDuration)
    elseif G.bulletin.animPhase == "stay" then
        progress = 1.0
    elseif G.bulletin.animPhase == "exit" then
        progress = 1.0 - math.min(1.0, G.bulletin.animTimer / G.bulletin.exitDuration)
    end

    -- 背景遮罩
    local maskAlpha = math.floor(140 * progress)
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, sw, sh)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, maskAlpha))
    nvgFill(nvg)

    -- 直接复用 DrawNextRulePanel 的全部逻辑
    -- 将整个屏幕作为规则区域（photoAreaH=0, ruleAreaH=sh）
    local titleStr = "第 " .. G.bulletin.round .. " 关"
    M.DrawNextRulePanel(sw, sh, 0, sh, progress, titleStr)
end

function M.DrawGameOver()
    if not G.gameOver then return end
    local nvg = G.nvg
    local sw, sh = G.screenW, G.screenH

    -- === 全屏背景图（装饰框） ===
    if gameOverFrameImg_ and gameOverFrameImg_ > 0 then
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, sw, sh)
        local imgPaint = nvgImagePattern(nvg, 0, 0, sw, sh, 0, gameOverFrameImg_, 1.0)
        nvgFillPaint(nvg, imgPaint)
        nvgFill(nvg)
    else
        -- fallback: 半透明遮罩
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, sw, sh)
        nvgFillColor(nvg, nvgRGBA(20, 10, 30, 200))
        nvgFill(nvg)
    end

    -- 找出获胜队伍（或平局）
    local isDraw = (G.winner == "平局")
    local winTeam = nil
    local loseTeam = nil
    if not isDraw then
        for i = 1, 2 do
            if G.teams[i].name == G.winner then
                winTeam = G.teams[i]
                loseTeam = G.teams[3 - i]
            end
        end
        if not winTeam then return end
    end

    -- 主色调
    local wc = isDraw and {255, 200, 60, 255} or winTeam.color

    -- === 内容区域（在装饰框的白色卡片内绘制） ===
    -- 白色卡片大约在画面中心偏上，占比约 60%×55%
    local contentW = sw * 0.55
    local contentH = sh * 0.50
    local contentX = (sw - contentW) / 2
    local contentY = sh * 0.14

    -- === 顶部标题（大号） ===
    local titleY = contentY + 40
    nvgFontSize(nvg, 52)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(wc[1], wc[2], wc[3], 255))
    if isDraw then
        nvgText(nvg, sw / 2, titleY, "平局!", nil)
    else
        nvgText(nvg, sw / 2, titleY, winTeam.name .. " WIN!", nil)
    end

    -- === 分隔线 ===
    local divY = titleY + 40
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, contentX + 40, divY)
    nvgLineTo(nvg, contentX + contentW - 40, divY)
    nvgStrokeColor(nvg, nvgRGBA(wc[1], wc[2], wc[3], 100))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)

    -- === 双列玩家分数 ===
    local leftTeam = isDraw and G.teams[1] or winTeam
    local rightTeam = isDraw and G.teams[2] or loseTeam

    -- 收集并排序玩家分数
    local leftPlayers = {}
    local rightPlayers = {}

    for i, p in ipairs(G.players) do
        local entry = { name = p.config.name, score = p.score or 0, color = p.config.color }
        local inLeftTeam = false
        for _, mi in ipairs(leftTeam.members) do
            if mi == i then inLeftTeam = true; break end
        end
        if inLeftTeam then
            table.insert(leftPlayers, entry)
        else
            table.insert(rightPlayers, entry)
        end
    end

    table.sort(leftPlayers, function(a, b) return a.score > b.score end)
    table.sort(rightPlayers, function(a, b) return a.score > b.score end)

    -- 列布局参数
    local colStartY = divY + 30
    local rowH = 36
    local leftColX = contentX + 40
    local rightColX = sw / 2 + 20
    local colW = contentW / 2 - 60

    local ltc = leftTeam.color
    local rtc = rightTeam.color

    -- 左列标题
    nvgFontSize(nvg, 20)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(ltc[1], ltc[2], ltc[3], 240))
    nvgText(nvg, leftColX, colStartY, leftTeam.name, nil)
    nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(120, 100, 140, 200))
    nvgText(nvg, leftColX + colW, colStartY, "得分", nil)

    -- 右列标题
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(rtc[1], rtc[2], rtc[3], 240))
    nvgText(nvg, rightColX, colStartY, rightTeam.name, nil)
    nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(120, 100, 140, 200))
    nvgText(nvg, rightColX + colW, colStartY, "得分", nil)

    -- 左列玩家行
    for idx, entry in ipairs(leftPlayers) do
        local y = colStartY + idx * rowH
        local ec = entry.color
        -- 圆形标识
        nvgBeginPath(nvg)
        nvgCircle(nvg, leftColX + 6, y, 6)
        nvgFillColor(nvg, nvgRGBA(ec[1], ec[2], ec[3], 230))
        nvgFill(nvg)
        -- 玩家名
        nvgFontSize(nvg, 18)
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(60, 40, 80, 240))
        nvgText(nvg, leftColX + 18, y, entry.name, nil)
        -- 分数
        nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(ltc[1], ltc[2], ltc[3], 255))
        nvgFontSize(nvg, 20)
        nvgText(nvg, leftColX + colW, y, tostring(entry.score), nil)
    end

    -- 右列玩家行
    for idx, entry in ipairs(rightPlayers) do
        local y = colStartY + idx * rowH
        local ec = entry.color
        -- 圆形标识
        nvgBeginPath(nvg)
        nvgCircle(nvg, rightColX + 6, y, 6)
        nvgFillColor(nvg, nvgRGBA(ec[1], ec[2], ec[3], 230))
        nvgFill(nvg)
        -- 玩家名
        nvgFontSize(nvg, 18)
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(60, 40, 80, 240))
        nvgText(nvg, rightColX + 18, y, entry.name, nil)
        -- 分数
        nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(rtc[1], rtc[2], rtc[3], 255))
        nvgFontSize(nvg, 20)
        nvgText(nvg, rightColX + colW, y, tostring(entry.score), nil)
    end

    -- === 角色展示区域（单排横向，左队 + 右队） ===
    if not isDraw then
        local gridStartY = colStartY + math.max(#leftPlayers, #rightPlayers) * rowH + 30
        local halfW = contentW * 0.5
        local numLeft = math.max(1, #leftTeam.members)
        local numRight = math.max(1, #loseTeam.members)
        local leftSpacing = halfW / (numLeft + 1)
        local rightSpacing = halfW / (numRight + 1)

        -- 绘制胜利方角色（左半单排）——双手过头庆祝
        for idx, pi in ipairs(leftTeam.members) do
            local cx = contentX + idx * leftSpacing
            local cy = gridStartY + 40

            local pdata = G.players[pi]
            if pdata then
                local skinIdx = pdata.config.skinIndex or 1
                local skin = G.skinsRuntime[skinIdx]
                -- 脚下圆圈（椭圆阴影）
                nvgBeginPath(nvg)
                nvgEllipse(nvg, cx, cy + 22, 18, 7)
                local pc = pdata.config.color
                nvgFillColor(nvg, nvgRGBA(pc[1], pc[2], pc[3], 60))
                nvgFill(nvg)
                nvgBeginPath(nvg)
                nvgEllipse(nvg, cx, cy + 22, 18, 7)
                nvgStrokeColor(nvg, nvgRGBA(pc[1], pc[2], pc[3], 120))
                nvgStrokeWidth(nvg, 1.5)
                nvgStroke(nvg)
                -- 胜利姿势：手臂举过头顶
                M.DrawSinglePlayer({
                    sx = cx, sy = cy,
                    color = pdata.config.color,
                    skin = skin,
                    facing = 1,
                    limbSwing = 0.15,
                    armSwing = -(math.pi + 0.5),  -- 双手高举
                    inAir = false,
                    isMoving = false,
                    onGround = true,
                    velY = 0,
                    name = pdata.config.name,
                    scaleX = 1.0,
                    scaleY = 1.0,
                    showGlow = false,
                    playerIndex = pi,
                })
                -- 胜利星星特效
                local t = G.globalTime or 0
                for s = 1, 3 do
                    local starAngle = t * 2.0 + s * 2.1
                    local starDist = 18 + math.sin(t * 3 + s) * 4
                    local starX = cx + math.cos(starAngle) * starDist
                    local starY = cy - 28 + math.sin(starAngle) * starDist * 0.6
                    nvgFontSize(nvg, 12)
                    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(nvg, nvgRGBA(255, 220, 50, 200))
                    nvgText(nvg, starX, starY, "★", nil)
                end
            end
        end

        -- 绘制失败方角色（右半单排）——躺在地上 + 乌云下雨
        for idx, pi in ipairs(loseTeam.members) do
            local cx = contentX + halfW + idx * rightSpacing
            local cy = gridStartY + 40

            local pdata = G.players[pi]
            if pdata then
                local skinIdx = pdata.config.skinIndex or 1
                local skin = G.skinsRuntime[skinIdx]
                -- 脚下圆圈（椭圆阴影）
                nvgBeginPath(nvg)
                nvgEllipse(nvg, cx, cy + 22, 18, 7)
                local pc = pdata.config.color
                nvgFillColor(nvg, nvgRGBA(pc[1], pc[2], pc[3], 40))
                nvgFill(nvg)
                nvgBeginPath(nvg)
                nvgEllipse(nvg, cx, cy + 22, 18, 7)
                nvgStrokeColor(nvg, nvgRGBA(pc[1], pc[2], pc[3], 100))
                nvgStrokeWidth(nvg, 1.5)
                nvgStroke(nvg)
                -- 失败姿势：旋转90度躺倒
                nvgSave(nvg)
                nvgTranslate(nvg, cx, cy + 10)
                nvgRotate(nvg, math.rad(90))
                nvgTranslate(nvg, -cx, -(cy + 10))
                M.DrawSinglePlayer({
                    sx = cx, sy = cy + 10,
                    color = pdata.config.color,
                    skin = skin,
                    facing = 1,
                    limbSwing = 0,
                    armSwing = 0.3,  -- 手臂微微下垂
                    inAir = false,
                    isMoving = false,
                    onGround = true,
                    velY = 0,
                    name = "",  -- 躺下时不显示名字
                    scaleX = 1.0,
                    scaleY = 1.0,
                    showGlow = false,
                    playerIndex = pi,
                })
                nvgRestore(nvg)

                -- 乌云
                local cloudX = cx
                local cloudY = cy - 20
                local cloudW = 30
                nvgBeginPath(nvg)
                nvgEllipse(nvg, cloudX, cloudY, cloudW, 10)
                nvgEllipse(nvg, cloudX - 10, cloudY - 4, 14, 9)
                nvgEllipse(nvg, cloudX + 10, cloudY - 3, 12, 8)
                nvgEllipse(nvg, cloudX + 2, cloudY - 8, 13, 8)
                nvgFillColor(nvg, nvgRGBA(80, 80, 100, 180))
                nvgFill(nvg)

                -- 雨滴
                local t = G.globalTime or 0
                for d = 1, 5 do
                    local dropX = cloudX - 16 + d * 7
                    local dropOff = ((t * 60 + d * 17) % 30)
                    local dropY = cloudY + 10 + dropOff
                    local dropAlpha = math.max(0, 200 - dropOff * 7)
                    nvgBeginPath(nvg)
                    nvgMoveTo(nvg, dropX, dropY)
                    nvgLineTo(nvg, dropX - 1.5, dropY + 6)
                    nvgLineTo(nvg, dropX + 1.5, dropY + 6)
                    nvgClosePath(nvg)
                    nvgFillColor(nvg, nvgRGBA(100, 140, 220, math.floor(dropAlpha)))
                    nvgFill(nvg)
                end
            end
        end
    end
end

-- ============================================================================
-- 皮肤编辑器预览
-- ============================================================================

function M.DrawSkinEditorPreview()
    if not G.skinEditorOpen then return end
    local skin = G.skinsRuntime[1]
    if not skin then return end
    local nvg = G.nvg
    local sw, sh = G.screenW, G.screenH

    local previewW = 180
    local previewH = 320
    local panelLeftEdge = sw - 560
    local previewRight = panelLeftEdge - 20
    local previewLeft = previewRight - previewW
    local previewTop = 50
    local previewCenterX = previewLeft + previewW / 2
    local previewCenterY = previewTop + previewH * 0.45

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, previewLeft, previewTop, previewW, previewH, 8)
    nvgFillColor(nvg, nvgRGBA(15, 15, 25, 220))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, previewLeft, previewTop, previewW, previewH, 8)
    nvgStrokeColor(nvg, nvgRGBA(60, 60, 80, 180))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    nvgFontSize(nvg, 12)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(120, 120, 140, 255))
    nvgText(nvg, previewCenterX, previewTop + 6, "预览", nil)

    local limbSwing = math.sin(G.skinEditorAnimTime) * 0.5
    local armSwing = -math.sin(G.skinEditorAnimTime) * 0.4

    M.DrawSinglePlayer({
        sx = previewCenterX,
        sy = previewCenterY,
        color = PLAYERS[1].color,
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

return M
