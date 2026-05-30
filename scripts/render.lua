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

function M.Init(gameState)
    G = gameState
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

    -- 天空渐变
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, sw, sh)
    local skyGrad = nvgLinearGradient(nvg, 0, 0, 0, sh,
        nvgRGBA(100, 180, 255, 255), nvgRGBA(200, 230, 255, 255))
    nvgFillPaint(nvg, skyGrad)
    nvgFill(nvg)

    -- 太阳
    local sunX = sw * 0.82
    local sunY = sh * 0.12
    nvgBeginPath(nvg)
    nvgCircle(nvg, sunX, sunY, 40)
    local sunGrad = nvgRadialGradient(nvg, sunX, sunY, 10, 40,
        nvgRGBA(255, 250, 200, 255), nvgRGBA(255, 200, 80, 200))
    nvgFillPaint(nvg, sunGrad)
    nvgFill(nvg)
    -- 太阳光晕
    nvgBeginPath(nvg)
    nvgCircle(nvg, sunX, sunY, 55)
    local haloGrad = nvgRadialGradient(nvg, sunX, sunY, 35, 55,
        nvgRGBA(255, 240, 150, 60), nvgRGBA(255, 240, 150, 0))
    nvgFillPaint(nvg, haloGrad)
    nvgFill(nvg)

    -- 云朵
    math.randomseed(42)
    for i = 1, 5 do
        local cx = math.random(50, math.floor(sw - 50))
        local cy = math.random(30, math.floor(sh * 0.25))
        local cloudW = math.random(60, 120)
        M.DrawCloud(cx, cy, cloudW)
    end
    math.randomseed(os.time())

    -- 远山 / 近山
    M.DrawMountain(sh * 0.45, nvgRGBA(60, 120, 80, 255), 123)
    M.DrawMountain(sh * 0.55, nvgRGBA(80, 160, 90, 255), 456)

    -- 草地
    local _, groundScreenY = M.PhysToScreen(0, CONFIG.GroundY)
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, groundScreenY - 10, sw, sh - groundScreenY + 10)
    local grassGrad = nvgLinearGradient(nvg, 0, groundScreenY, 0, sh,
        nvgRGBA(80, 180, 60, 255), nvgRGBA(50, 120, 40, 255))
    nvgFillPaint(nvg, grassGrad)
    nvgFill(nvg)

    -- 草地顶部草丛装饰
    math.randomseed(99)
    for i = 1, 40 do
        local gx = math.random(0, math.floor(sw))
        local gh = math.random(4, 12)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, gx, groundScreenY - 10)
        nvgLineTo(nvg, gx - 2, groundScreenY - 10 - gh)
        nvgLineTo(nvg, gx + 2, groundScreenY - 10 - gh * 0.7)
        nvgClosePath(nvg)
        nvgFillColor(nvg, nvgRGBA(60, 160 + math.random(0, 40), 50, 200))
        nvgFill(nvg)
    end
    math.randomseed(os.time())

    -- 远处的小树
    math.randomseed(77)
    for i = 1, 6 do
        local tx = math.random(30, math.floor(sw - 30))
        local ty = groundScreenY - 10
        M.DrawTree(tx, ty, math.random(25, 45))
    end
    math.randomseed(os.time())
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

        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, sx - pw/2, sy - ph/2, pw, ph, 6)
        local grad = nvgLinearGradient(nvg, sx - pw/2, sy - ph/2, sx - pw/2, sy + ph/2,
            nvgRGBA(140, 100, 60, 255), nvgRGBA(100, 70, 40, 255))
        nvgFillPaint(nvg, grad)
        nvgFill(nvg)

        -- 顶部草皮
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, sx - pw/2, sy - ph/2 - 3, pw, 6, 3)
        nvgFillColor(nvg, nvgRGBA(80, 180, 50, 255))
        nvgFill(nvg)

        -- 草皮上的小草
        local grassCount = math.floor(pw / 12)
        for g = 1, grassCount do
            local gx = sx - pw/2 + g * (pw / (grassCount + 1))
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, gx, sy - ph/2 - 3)
            nvgLineTo(nvg, gx - 1.5, sy - ph/2 - 8)
            nvgLineTo(nvg, gx + 1.5, sy - ph/2 - 6)
            nvgClosePath(nvg)
            nvgFillColor(nvg, nvgRGBA(60, 160, 40, 200))
            nvgFill(nvg)
        end
    end
end

-- ============================================================================
-- 拍照区域渲染
-- ============================================================================

function M.DrawPhotoZone()
    local nvg = G.nvg
    if not G.photoZone.active then return end
    if G.gameState == "showPhoto" then return end

    local ppu = M.GetPixelsPerUnit()
    local sx, sy = M.PhysToScreen(G.photoZone.x, G.photoZone.y)
    local pw = G.photoZone.width * ppu
    local ph = G.photoZone.height * ppu

    local alpha = 120 + math.floor(math.sin(os.clock() * 4) * 40)

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

    nvgFontSize(nvg, 20)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(255, 220, 50, 200))
    nvgText(nvg, sx, sy - ph/2 - 24, "📷 拍照区域", nil)
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
    nvgFontSize(nvg, 14)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 255))
    local nameY = skin and (headY - headR - 6) or (sy - r - 10)
    nvgText(nvg, sx, nameY, name, nil)

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
end

function M.DrawPlayers()
    for i, p in ipairs(G.players) do
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
        })
    end
end

function M.DrawPlayersSnapshot()
    for i, snap in ipairs(G.photoSnapshot) do
        local p = G.players[i]
        if not p then break end

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
        })
    end
end

-- ============================================================================
-- 金币渲染
-- ============================================================================

function M.DrawCoins(coins, currentGameplayIndex)
    local gp = GAMEPLAY_DATA[currentGameplayIndex]
    if gp.scoringRule ~= "coin_top3" then return end
    if G.gameState == "showPhoto" or G.gameState == "bulletin" then return end

    local nvg = G.nvg
    local ppu = M.GetPixelsPerUnit()

    for _, coin in ipairs(coins) do
        if not coin.collected then
            local sx, sy = M.PhysToScreen(coin.x, coin.y)
            local r = Cfg.COIN_RADIUS * ppu

            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, r)
            nvgFillColor(nvg, nvgRGBA(255, 200, 40, 255))
            nvgFill(nvg)

            nvgStrokeColor(nvg, nvgRGBA(200, 150, 0, 255))
            nvgStrokeWidth(nvg, 2)
            nvgStroke(nvg)

            nvgFontSize(nvg, r * 1.2)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(180, 120, 0, 255))
            nvgText(nvg, sx, sy, "$", nil)
        end
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
    local num = math.ceil(G.prepTimer)
    local text = "准备 " .. tostring(num)

    nvgFontSize(nvg, 48)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 120))
    nvgText(nvg, G.screenW/2 + 2, G.screenH/2 + 2, text, nil)

    nvgFillColor(nvg, nvgRGBA(255, 220, 80, 255))
    nvgText(nvg, G.screenW/2, G.screenH/2, text, nil)
end

function M.DrawCountdown()
    if G.gameState ~= "countdown" then return end
    local nvg = G.nvg
    local num = math.ceil(G.countdown)
    local text = tostring(num)

    local scale = 1.0 + (G.countdown - math.floor(G.countdown)) * 0.3
    nvgFontSize(nvg, 80 * scale)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 150))
    nvgText(nvg, G.screenW/2 + 3, G.screenH/2 + 3, text, nil)

    local gp = GAMEPLAY_DATA[G.unlock.currentGameplayIndex]
    local urgency = math.max(0, 1 - G.countdown / gp.rushTime)
    local r = math.floor(255 * urgency)
    local g = math.floor(255 * (1 - urgency))
    nvgFillColor(nvg, nvgRGBA(r + 100, g + 100, 100, 255))
    nvgText(nvg, G.screenW/2, G.screenH/2, text, nil)
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

function M.DrawShowPhoto()
    if G.gameState ~= "showPhoto" then return end
    local nvg = G.nvg
    local sw, sh = G.screenW, G.screenH

    local progress = math.min(1.0, (2.5 - G.showPhotoTimer) / 0.3)

    nvgSave(nvg)

    -- 全屏遮罩
    local maskAlpha = math.floor(200 * progress)
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, sw, sh)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, maskAlpha))
    nvgFill(nvg)

    -- 拍立得照片展示
    local zoneAspect = G.photoZone.width / G.photoZone.height
    local maxPhotoW = sw * 0.65
    local maxPhotoH = sh * 0.50
    local photoW, photoH

    if maxPhotoW / zoneAspect <= maxPhotoH then
        photoW = maxPhotoW
        photoH = maxPhotoW / zoneAspect
    else
        photoH = maxPhotoH
        photoW = maxPhotoH * zoneAspect
    end

    local framePad = math.floor(photoW * 0.05)
    local frameBottom = math.floor(photoH * 0.25)
    local totalW = photoW + framePad * 2
    local totalH = photoH + framePad + frameBottom

    local frameX = (sw - totalW) / 2
    local frameY = (sh - totalH) / 2 - sh * 0.03
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

    -- 底部结果文字
    local textY = photoY + photoH + frameBottom * 0.5
    nvgFontSize(nvg, math.max(18, math.floor(frameBottom * 0.35)))
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if #G.roundResult > 0 then
        local names = {}
        for _, idx in ipairs(G.roundResult) do
            table.insert(names, G.players[idx].config.name)
        end
        nvgFillColor(nvg, nvgRGBA(40, 160, 60, math.floor(255 * progress)))
        nvgText(nvg, sw / 2, textY, table.concat(names, " & ") .. " 入镜! +1", nil)
    else
        nvgFillColor(nvg, nvgRGBA(200, 80, 80, math.floor(255 * progress)))
        nvgText(nvg, sw / 2, textY, "没人入镜!", nil)
    end

    -- 顶部 PHOTO 标签
    nvgFontSize(nvg, 13)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(180 * progress)))
    nvgText(nvg, sw / 2, frameY - 6, "PHOTO", nil)

    nvgRestore(nvg)
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

    local function easeOutBack(t)
        local c1 = 1.70158
        local c3 = c1 + 1
        return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
    end

    local displayProgress
    if G.bulletin.animPhase == "enter" then
        displayProgress = easeOutBack(progress)
    elseif G.bulletin.animPhase == "exit" then
        displayProgress = progress * progress
    else
        displayProgress = 1.0
    end

    -- 背景遮罩
    local maskAlpha = math.floor(140 * displayProgress)
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, sw, sh)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, maskAlpha))
    nvgFill(nvg)

    -- 公告板
    local boardW = math.min(480, sw * 0.7)
    local boardH = math.min(320, sh * 0.6)
    local boardX = (sw - boardW) / 2
    local targetY = (sh - boardH) / 2
    local startY = -boardH - 20
    local boardY = startY + (targetY - startY) * displayProgress

    nvgSave(nvg)

    -- 阴影
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, boardX + 4, boardY + 6, boardW, boardH, 16)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(80 * displayProgress)))
    nvgFill(nvg)

    -- 主体
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, boardX, boardY, boardW, boardH, 16)
    local boardGrad = nvgLinearGradient(nvg, boardX, boardY, boardX, boardY + boardH,
        nvgRGBA(45, 55, 75, 250), nvgRGBA(30, 38, 55, 250))
    nvgFillPaint(nvg, boardGrad)
    nvgFill(nvg)

    -- 边框
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, boardX, boardY, boardW, boardH, 16)
    nvgStrokeColor(nvg, nvgRGBA(100, 160, 255, math.floor(180 * displayProgress)))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)

    -- 标题栏
    local titleBarH = 50
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, boardX, boardY, boardW, titleBarH, 16)
    nvgFillColor(nvg, nvgRGBA(60, 120, 220, math.floor(200 * displayProgress)))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRect(nvg, boardX, boardY + titleBarH - 16, boardW, 16)
    nvgFillColor(nvg, nvgRGBA(60, 120, 220, math.floor(200 * displayProgress)))
    nvgFill(nvg)

    -- 标题文字
    nvgFontSize(nvg, 26)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(255 * displayProgress)))
    nvgText(nvg, sw / 2, boardY + titleBarH / 2, "第 " .. G.bulletin.round .. " 关", nil)

    -- 玩法名称
    local gp = GAMEPLAY_DATA[G.unlock.currentGameplayIndex]
    local gpName = gp and gp.name or "经典抓拍"
    local gpDesc = gp and gp.description or ""
    nvgFontSize(nvg, 16)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 200, 80, math.floor(220 * displayProgress)))
    nvgText(nvg, sw / 2, boardY + titleBarH + 28, "玩法: " .. gpName, nil)

    nvgFontSize(nvg, 18)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(230, 230, 240, math.floor(240 * displayProgress)))
    nvgText(nvg, sw / 2, boardY + titleBarH + 55, gpDesc, nil)

    -- 地图/解锁信息
    local mapName = MAP_DATA[G.unlock.currentMapLevel] and MAP_DATA[G.unlock.currentMapLevel].name or ""
    local unlockVal = G.getUnlockValue()
    nvgFontSize(nvg, 13)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(160, 180, 200, math.floor(180 * displayProgress)))
    nvgText(nvg, sw / 2, boardY + titleBarH + 78, string.format("地图: %s | 解锁值: %.1f", mapName, unlockVal), nil)

    -- 玩家头像区域
    local avatarY = boardY + titleBarH + 95
    local avatarR = 22

    for t = 1, 2 do
        local team = G.teams[t]
        local tc = team.color
        local members = team.members
        local teamCount = #members

        local teamCenterX
        if t == 1 then teamCenterX = boardX + boardW * 0.25
        else teamCenterX = boardX + boardW * 0.75 end

        nvgFontSize(nvg, 16)
        nvgFontFace(nvg, "sans")
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(nvg, nvgRGBA(tc[1], tc[2], tc[3], math.floor(255 * displayProgress)))
        nvgText(nvg, teamCenterX, avatarY - avatarR - 10, team.name, nil)

        local memberSpacing = (avatarR * 2 + 12)
        local startX = teamCenterX - (teamCount - 1) * memberSpacing / 2

        for mIdx, pi in ipairs(members) do
            local pdata = PLAYERS[pi]
            local ax = startX + (mIdx - 1) * memberSpacing
            local ay = avatarY
            local c = pdata.color

            nvgBeginPath(nvg)
            nvgCircle(nvg, ax, ay, avatarR)
            local avatarGrad = nvgRadialGradient(nvg, ax - 3, ay - 3, 2, avatarR,
                nvgRGBA(math.min(255, c[1] + 60), math.min(255, c[2] + 60), math.min(255, c[3] + 60), 255),
                nvgRGBA(c[1], c[2], c[3], 255))
            nvgFillPaint(nvg, avatarGrad)
            nvgFill(nvg)

            nvgBeginPath(nvg)
            nvgCircle(nvg, ax, ay, avatarR)
            nvgStrokeColor(nvg, nvgRGBA(tc[1], tc[2], tc[3], 200))
            nvgStrokeWidth(nvg, 2.5)
            nvgStroke(nvg)

            -- 眼睛
            nvgBeginPath(nvg)
            nvgCircle(nvg, ax - 5, ay - 4, 3)
            nvgCircle(nvg, ax + 5, ay - 4, 3)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
            nvgFill(nvg)
            nvgBeginPath(nvg)
            nvgCircle(nvg, ax - 4, ay - 3, 1.5)
            nvgCircle(nvg, ax + 6, ay - 3, 1.5)
            nvgFillColor(nvg, nvgRGBA(0, 0, 0, 255))
            nvgFill(nvg)

            -- 微笑
            nvgBeginPath(nvg)
            nvgArc(nvg, ax, ay + 4, 5, 0.2, math.pi - 0.2, NVG_CW)
            nvgStrokeColor(nvg, nvgRGBA(0, 0, 0, 200))
            nvgStrokeWidth(nvg, 1.5)
            nvgStroke(nvg)

            -- 名字
            nvgFontSize(nvg, 12)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], math.floor(255 * displayProgress)))
            nvgText(nvg, ax, ay + avatarR + 4, pdata.name, nil)

            -- 对勾
            if G.bulletin.confirmed[pi] then
                nvgBeginPath(nvg)
                nvgCircle(nvg, ax + avatarR * 0.6, ay - avatarR * 0.6, 10)
                nvgFillColor(nvg, nvgRGBA(40, 200, 80, 255))
                nvgFill(nvg)
                nvgBeginPath(nvg)
                nvgCircle(nvg, ax + avatarR * 0.6, ay - avatarR * 0.6, 10)
                nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 255))
                nvgStrokeWidth(nvg, 1.5)
                nvgStroke(nvg)

                local cx = ax + avatarR * 0.6
                local cy = ay - avatarR * 0.6
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, cx - 4, cy)
                nvgLineTo(nvg, cx - 1, cy + 3)
                nvgLineTo(nvg, cx + 5, cy - 3)
                nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 255))
                nvgStrokeWidth(nvg, 2)
                nvgLineCap(nvg, NVG_ROUND)
                nvgLineJoin(nvg, NVG_ROUND)
                nvgStroke(nvg)
            end
        end
    end

    -- VS
    nvgFontSize(nvg, 22)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 200, 80, math.floor(220 * displayProgress)))
    nvgText(nvg, sw / 2, avatarY, "VS", nil)

    -- 底部提示
    local hintY = boardY + boardH - 35
    local hintAlpha = math.floor((math.sin(os.clock() * 3) * 0.3 + 0.7) * 255 * displayProgress)
    nvgFontSize(nvg, 15)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(180, 200, 255, hintAlpha))
    nvgText(nvg, sw / 2, hintY, "按 [跳跃键] 表示已理解规则", nil)

    nvgRestore(nvg)
end

function M.DrawGameOver()
    if not G.gameOver then return end
    local nvg = G.nvg
    local sw, sh = G.screenW, G.screenH

    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, sw, sh)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 180))
    nvgFill(nvg)

    nvgFontSize(nvg, 56)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 220, 50, 255))
    nvgText(nvg, sw/2, sh/2 - 30, G.winner .. " 获胜!", nil)

    nvgFontSize(nvg, 24)
    nvgFillColor(nvg, nvgRGBA(200, 200, 200, 255))
    nvgText(nvg, sw/2, sh/2 + 30, "按 R 重新开始", nil)
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
