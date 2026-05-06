-- main.lua - 雪国列车：末日求生 Roguelike
-- 竖屏2D 俯视角，NanoVG 渲染 + VirtualControls 触摸输入

require "urhox-libs.UI.VirtualControls"

local C    = require "Game.Config"
local Ent  = require "Game.Entities"
local Rend = require "Game.Renderer"
local RL   = require "Game.Roguelike"
local Turret = require "Game.Turret"
local Meta = require "Meta.MetaMain"
local UIEditor = require "Editor.UIEditor"

------------------------------------------------------------------------
-- 全局游戏状态
------------------------------------------------------------------------
---@type any
local G = {}
local vg = nil
local vc_joystick = nil
local toolImgHandle = 0  -- 采集装备图片句柄 (模块级，ResetGame不丢失)
local heroImgHandle = 0  -- 主角立绘图片句柄
local heroAnimHandles = {}  -- 主角序列帧: {idle, raise, swing, hit, recover}
local heroWalkHandles = {}  -- 主角行走序列帧: {walk1, walk2, walk3, walk4}
local zombieIdleHandle = 0  -- 僵尸1 idle图片句柄
local zombieWalkHandles = {} -- 僵尸1 行走序列帧: {a, b, c, d}
local zombie2IdleHandle = 0  -- 僵尸2 idle图片句柄
local zombie2WalkHandles = {} -- 僵尸2 行走序列帧: {a, b, c, d}
local crawlerIdleHandle = 0   -- 爬行僵尸 idle图片句柄
local crawlerWalkHandles = {} -- 爬行僵尸 行走序列帧: 8帧爬行动画
local trainImgHandle = 0     -- 火车精灵图片句柄
local trainFrontHandle = 0   -- 火车正面图（升级UI用）
local titleBannerHandle = 0  -- 标题横幅背景
-- 背景纹理句柄
local bgGroundHandle = 0
-- 地图素材图片句柄
local mapDeadTreeHandle = 0
local mapPineTreeHandle = 0
local mapGreenTreeHandle = 0
local mapStoneHandle = 0

local mapOreHandle = 0
local mapBushHandle = 0
local mapPebbleHandle = 0
-- HUD 图标句柄
local hudIconGoldHandle = 0
local hudIconWoodHandle = 0
local hudIconStoneHandle = 0
local hudIconGemHandle = 0
-- HUD 框架图片句柄
local hudFrameCapHandle = 0   -- 图层_6: 端盖
local hudFrameMidHandle = 0   -- 图层_7: 中间平铺
local hudInnerFrameHandle = 0
local hudSettingsFrameHandle = 0
local waveUIHandle = 0
local killUIHandle = 0




------------------------------------------------------------------------
-- 初始化游戏状态
------------------------------------------------------------------------
local function ResetGame()
    G = {
        state = "menu",       -- menu / playing / upgrade / gameover
        gameTime = 0,
        screenW = 400,
        screenH = 800,

        -- 滚动
        scrollY = 0,
        distance = 0,

        -- 级别 & 进度
        level = 1,
        levelProgress = 0,
        levelTarget = C.BASE_TARGET,
        pendingLevelUp = false,

        -- 经济
        gold = 0,
        totalRes = { wood = 0, stone = 0, ore = 0, bush = 0, pebble = 0 },

        -- 列车HP
        trainHP = C.TRAIN_MAX_HP,
        trainMaxHP = C.TRAIN_MAX_HP,

        -- 关卡距离追踪
        levelStartDist = 0,

        -- 升级倍率
        speedMul = 1.0,
        goldMul = 1.0,
        spawnMul = 1.0,
        oreLuckMul = 1.0,
        scrollSpeedMul = 1.0,
        doubleMul = 0.0,
        maxCarry = C.MAX_CARRY,

        -- 自动攻击倍率
        atkBonus = 0,           -- 额外攻击力
        atkSpdMul = 1.0,        -- 攻击速度倍率
        rangeMul = 1.0,         -- 攻击范围倍率

        -- 实体列表
        resources = {},
        decorations = {},
        floatTexts = {},
        particles = {},
        zombies = {},
        turrets = {},
        turretProjectiles = {},

        -- 波次系统
        currentWave = 1,
        maxWaves = 20,
        waveTimer = 0,           -- 当前波次已进行时间
        waveDuration = 30,       -- 每波持续时间(秒)
        waveCountdown = 0,       -- 下一波倒计时
        waveActive = true,       -- 当前波次是否正在进行
        killCount = 0,           -- 总击杀数

        -- 生成计时器
        resSpawnTimer = 0,
        decoSpawnTimer = 0,
        zombieSpawnTimer = 0,

        -- 提示
        hintText = nil,
        hintTimer = 0,

        -- 布局 (CalcLayout 填充)
        hudH = 48,
        cartCenterX = 0,
        cartTopY = 0,
        cartW = 72,
        cartH = 80,
        cartBottomY = 0,
        submitBox = { x = 0, y = 0 },

        -- 升级 UI
        upgradeCards = {},
        upgradeCardBtns = {},

        -- 菜单/重开按钮
        menuBtn = nil,
        restartBtn = nil,
    }

    Ent.CreatePlayer(G)
    print("=== Game Reset ===")
end

------------------------------------------------------------------------
-- 挂载图片句柄到 G（ResetGame 后调用）
------------------------------------------------------------------------
local function MountImageHandles()
    G.toolImg = toolImgHandle
    G.heroImg = heroImgHandle
    G.heroAnimFrames = heroAnimHandles
    G.heroWalkFrames = heroWalkHandles
    G.zombieIdleImg = zombieIdleHandle
    G.zombieWalkFrames = zombieWalkHandles
    G.zombie2IdleImg = zombie2IdleHandle
    G.zombie2WalkFrames = zombie2WalkHandles
    G.crawlerIdleImg = crawlerIdleHandle
    G.crawlerWalkFrames = crawlerWalkHandles
    G.trainImg = trainImgHandle
    G.trainCarriageImg = trainCarriageHandle
    G.trainFrontImg = trainFrontHandle
    G.titleBannerImg = titleBannerHandle
    G.bgGroundImg = bgGroundHandle
    G.mapDeadTreeImg = mapDeadTreeHandle
    G.mapPineTreeImg = mapPineTreeHandle
    G.mapGreenTreeImg = mapGreenTreeHandle
    G.mapStoneImg = mapStoneHandle
    G.mapOreImg = mapOreHandle
    G.mapBushImg = mapBushHandle
    G.mapPebbleImg = mapPebbleHandle
    G.hudIconGold = hudIconGoldHandle
    G.hudIconWood = hudIconWoodHandle
    G.hudIconStone = hudIconStoneHandle
    G.hudIconGem = hudIconGemHandle
    G.hudSettings = hudSettingsHandle
    G.hudFrameCap = hudFrameCapHandle
    G.hudFrameMid = hudFrameMidHandle
    G.hudInnerFrame = hudInnerFrameHandle
    G.hudSettingsFrame = hudSettingsFrameHandle
    G.hpBarFrame = hpBarFrameHandle
    G.waveUIImg = waveUIHandle
    G.killUIImg = killUIHandle
    G.turretImgs = turretImgs
    G.turretBaseTop = turretBaseTopHandle
    G.turretBaseMid = turretBaseMidHandle
    G.turretBaseBot = turretBaseBotHandle
    G.turretLockedImg = turretLockedHandle
    G.turretFrameImg  = turretFrameHandle
    G.titleBg = titleBgHandle
    -- 升级卡图标 
    G.upgradeIcons = upgradeIconHandles
    -- 弓箭发射物图片
    G.arrowProjImg = arrowProjHandle
    -- 火箭弹图片
    G.rocketProjImg = rocketProjHandle
    -- 喷火序列帧
    G.flameFrames = flameFrameHandles
    G.FLAME_FRAME_COUNT = 21
    G.FLAME_FRAME_W = 101
    G.FLAME_FRAME_H = 235
end

--- 从局外进入关卡
local function StartLevel()
    ResetGame()
    MountImageHandles()
    Turret.InitTurrets(G)
    G.state = "playing"
    G.hintText = "靠近资源自动采集，送到列车下方！保护列车！"
    G.hintTimer = 4.0
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    Rend.CalcLayout(G, physW / dpr, physH / dpr)
    Ent.CreatePlayer(G)
    print("[Game] Started playing!")
end

------------------------------------------------------------------------
-- Start / Stop
------------------------------------------------------------------------
function Start()
    vg = nvgCreate(1)
    if not vg then
        print("ERROR: Failed to create NanoVG context")
        return
    end

    if nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf") == -1 then
        print("ERROR: Failed to load font")
        return
    end

    -- 加载采集装备图片
    toolImgHandle = nvgCreateImage(vg, "image/tile_0115.png", 0)
    if toolImgHandle == 0 then
        print("WARNING: Failed to load tool image tile_0115.png")
    else
        print("Loaded tool image, handle=" .. tostring(toolImgHandle))
    end

    -- 加载主角序列帧动画 (idle, raise, swing, hit, recover)
    local animFiles = {
        "image/hero_idle_20260414072856.png",
        "image/hero_axe_raise_20260414072858.png",
        "image/hero_axe_swing_20260414072953.png",
        "image/hero_axe_hit_20260414072957.png",
        "image/hero_axe_recover_20260414072959.png",
    }
    heroAnimHandles = {}
    for i, path in ipairs(animFiles) do
        heroAnimHandles[i] = nvgCreateImage(vg, path, NVG_IMAGE_NEAREST)
        if heroAnimHandles[i] == 0 then
            print("WARNING: Failed to load hero anim frame: " .. path)
        end
    end
    heroImgHandle = heroAnimHandles[1]  -- idle帧作为默认
    print("Loaded hero animation frames: " .. #heroAnimHandles)

    -- 加载主角行走序列帧 (4关键帧 + 程序化补间: 弹跳/倾斜)
    local walkFiles = {
        "image/hero_run_a_20260414082846.png",  -- 1: 左脚大步前迈
        "image/hero_run_b_20260414082855.png",  -- 2: 双腿交叉
        "image/hero_run_c_20260414082948.png",  -- 3: 右脚大步前迈
        "image/hero_run_d_20260414083003.png",  -- 4: 双腿交叉
    }
    heroWalkHandles = {}
    for i, path in ipairs(walkFiles) do
        heroWalkHandles[i] = nvgCreateImage(vg, path, NVG_IMAGE_NEAREST)
        if heroWalkHandles[i] == 0 then
            print("WARNING: Failed to load hero walk frame: " .. path)
        end
    end
    print("Loaded hero walk frames: " .. #heroWalkHandles)

    -- 加载僵尸序列帧 (idle + 4帧行走: 迈左腿→交叉→迈右腿→交叉)
    zombieIdleHandle = nvgCreateImage(vg, "image/zombie_idle_20260415091321.png", NVG_IMAGE_NEAREST)
    local zombieWalkFiles = {
        "image/zombie_walk_a_20260415092010.png",
        "image/zombie_walk_b_20260415092054.png",
        "image/zombie_walk_c_20260415092252.png",
        "image/zombie_walk_d_20260415092130.png",
    }
    zombieWalkHandles = {}
    for i, path in ipairs(zombieWalkFiles) do
        zombieWalkHandles[i] = nvgCreateImage(vg, path, NVG_IMAGE_NEAREST)
    end
    print("Loaded zombie1 frames: idle + " .. #zombieWalkHandles .. " walk")

    -- 加载僵尸2序列帧 (棕色大衣版)
    zombie2IdleHandle = nvgCreateImage(vg, "image/zombie_idle_20260415074148.png", NVG_IMAGE_NEAREST)
    local zombie2WalkFiles = {
        "image/zombie_walk_a_20260415085059.png",
        "image/zombie_walk_b_20260415085055.png",
        "image/zombie_walk_c_20260415085121.png",
        "image/zombie_walk_d_20260415085120.png",
    }
    zombie2WalkHandles = {}
    for i, path in ipairs(zombie2WalkFiles) do
        zombie2WalkHandles[i] = nvgCreateImage(vg, path, NVG_IMAGE_NEAREST)
    end
    print("Loaded zombie2 frames: idle + " .. #zombie2WalkHandles .. " walk")

    -- 加载爬行僵尸序列帧 (8帧爬行动画，手脚交替运动)
    crawlerIdleHandle = nvgCreateImage(vg, "image/edited_crawler_topdown_idle_v2_20260424025325.png", NVG_IMAGE_NEAREST)
    local crawlerWalkFiles = {
        "image/edited_crawler_td_f1_20260424025443.png",  -- 帧1: 左手前伸抓地，右膝前顶，身体右倾
        "image/edited_crawler_td_f2_20260424025528.png",  -- 帧2: 左手撑地发力，右手前移过渡
        "image/edited_crawler_td_f3_20260424031336.png",  -- 帧3: 双手对称撑地，中间过渡帧
        "image/edited_crawler_td_f4_20260424025700.png",  -- 帧4: 右手开始前伸，左手后收，身体左倾
        "image/edited_crawler_td_f5_20260424031411.png",  -- 帧5: 右手前伸抓地，左膝前顶，身体左倾
        "image/edited_crawler_td_f6_20260424025839.png",  -- 帧6: 右手撑地发力，左手前移过渡
        "image/edited_crawler_td_f7_20260424025920.png",  -- 帧7: 双手撑地，过渡回左手周期
        "image/edited_crawler_td_f8_20260424030008.png",  -- 帧8: 左手开始前伸，循环回帧1
    }
    crawlerWalkHandles = {}
    for i, path in ipairs(crawlerWalkFiles) do
        crawlerWalkHandles[i] = nvgCreateImage(vg, path, NVG_IMAGE_NEAREST)
    end
    print("Loaded crawler frames: idle + " .. #crawlerWalkHandles .. " walk")

    -- 火车精灵（干净版，无烟雾，烟雾由程序化粒子绘制）
    trainImgHandle = nvgCreateImage(vg, "image/edited_train_clean_edge_20260416031151.png", NVG_IMAGE_NEAREST)
    trainCarriageHandle = nvgCreateImage(vg, "image/train_carriage_20260416100938.png", NVG_IMAGE_NEAREST)
    trainFrontHandle = nvgCreateImage(vg, "image/train_front_20260422062046.png", 0)
    titleBannerHandle = nvgCreateImage(vg, "image/title_banner_20260422074156.png", 0)
    print("Loaded train sprite: " .. trainImgHandle .. " carriage: " .. trainCarriageHandle .. " front: " .. trainFrontHandle)

    -- 背景纹理
    bgGroundHandle = nvgCreateImage(vg, "image/bg_white_snow_20260416070957.png", NVG_IMAGE_REPEATX | NVG_IMAGE_REPEATY)

    -- 地图素材（像素风统一风格）
    mapDeadTreeHandle = nvgCreateImage(vg, "image/edited_map_dead_tree_clean_20260416060145.png", NVG_IMAGE_NEAREST)
    mapPineTreeHandle = nvgCreateImage(vg, "image/edited_map_pine_tree_clean_20260416060114.png", NVG_IMAGE_NEAREST)
    mapGreenTreeHandle = nvgCreateImage(vg, "image/edited_map_green_tree_clean_20260416060048.png", NVG_IMAGE_NEAREST)
    mapStoneHandle = nvgCreateImage(vg, "image/edited_map_stone_clean_20260416060244.png", NVG_IMAGE_NEAREST)

    mapOreHandle = nvgCreateImage(vg, "image/edited_map_ore_clean_20260416060319.png", NVG_IMAGE_NEAREST)
    mapBushHandle = nvgCreateImage(vg, "image/map_bush_small_20260416074158.png", NVG_IMAGE_NEAREST)
    mapPebbleHandle = nvgCreateImage(vg, "image/map_pebble_v2_20260416074909.png", NVG_IMAGE_NEAREST)

    -- 标题背景
    titleBgHandle = nvgCreateImage(vg, "image/title_bg_20260421072428.png", 0)

    -- HUD 图标
    hudIconGoldHandle = nvgCreateImage(vg, "image/hud_gold_coin.png", 0)
    hudIconWoodHandle = nvgCreateImage(vg, "image/hud_wood_log.png", 0)
    hudIconStoneHandle = nvgCreateImage(vg, "image/hud_icon_stone_20260416075733.png", 0)
    hudIconGemHandle = nvgCreateImage(vg, "image/hud_icon_gem_20260416075717.png", 0)
    hudSettingsHandle = nvgCreateImage(vg, "image/hud_settings.png", 0)
    hudFrameCapHandle = nvgCreateImage(vg, "image/图层_6.png", 0)
    hudFrameMidHandle = nvgCreateImage(vg, "image/图层_7.png", NVG_IMAGE_REPEATX)
    hudInnerFrameHandle = nvgCreateImage(vg, "image/内框.png", 0)
    hudSettingsFrameHandle = nvgCreateImage(vg, "image/设置框底.png", 0)
    waveUIHandle = nvgCreateImage(vg, "image/怪物波次UI.png", 0)
    killUIHandle = nvgCreateImage(vg, "image/击杀怪物数量.png", 0)

    -- 炮塔底三段拼接图片（顶部 139x28 / 中部 138x29 可平铺 / 底部 141x32）
    turretBaseTopHandle    = nvgCreateImage(vg, "image/炮塔底（顶部）.png", 0)
    turretBaseMidHandle    = nvgCreateImage(vg, "image/炮塔底（中部）.png", 0)
    turretBaseBotHandle    = nvgCreateImage(vg, "image/炮塔底（底部）.png", 0)
    turretLockedHandle     = nvgCreateImage(vg, "image/炮塔上锁.png", 0)
    turretFrameHandle      = nvgCreateImage(vg, "image/炮塔显示框.png", 0)
    hpBarFrameHandle = nvgCreateImage(vg, "image/hp_bar_frame_20260420020959.png", 0)
    heartIconHandle = nvgCreateImage(vg, "image/22fb797b.png", 0)

    -- 炮塔图标 (v3: 48x64, 纯武器造型, 朝下, 透明背景)
    turretImgs = {
        arrow    = nvgCreateImage(vg, "image/turret_arrow_v3_20260420035036.png", NVG_IMAGE_NEAREST),
        sniper   = nvgCreateImage(vg, "image/turret_sniper_v3_20260420035021.png", NVG_IMAGE_NEAREST),
        flame    = nvgCreateImage(vg, "image/edited_turret_flame_nofire_20260423065123.png", NVG_IMAGE_NEAREST),
        electric = nvgCreateImage(vg, "image/turret_electric_v10_20260423040517.png", NVG_IMAGE_NEAREST),
        rocket   = nvgCreateImage(vg, "image/turret_rocket_v3_20260420035019.png", NVG_IMAGE_NEAREST),
        minigun  = nvgCreateImage(vg, "image/turret_minigun_v3_20260420035022.png", NVG_IMAGE_NEAREST),
    }

    -- 升级卡图标
    upgradeIconHandles = {
        sword  = nvgCreateImage(vg, "image/icon_sword.png", 0),
        wind   = nvgCreateImage(vg, "image/icon_wind.png", 0),
        boot   = nvgCreateImage(vg, "image/icon_boot.png", 0),
        bag    = nvgCreateImage(vg, "image/icon_bag.png", 0),
        magnet = nvgCreateImage(vg, "image/icon_magnet.png", 0),
        coin   = nvgCreateImage(vg, "image/icon_coin.png", 0),
        star   = nvgCreateImage(vg, "image/icon_star.png", 0),
        gem    = nvgCreateImage(vg, "image/icon_gem.png", 0),
        gear   = nvgCreateImage(vg, "image/icon_gear.png", 0),
        x2     = nvgCreateImage(vg, "image/icon_x2.png", 0),
        fairy  = nvgCreateImage(vg, "image/icon_fairy.png", 0),
        shield = nvgCreateImage(vg, "image/icon_shield.png", 0),
        -- 炮塔专用图标
        turret_arrow    = nvgCreateImage(vg, "image/icon_arrow.png", 0),
        turret_minigun  = nvgCreateImage(vg, "image/icon_minigun.png", 0),
        turret_flame    = nvgCreateImage(vg, "image/icon_flame.png", 0),
        turret_sniper   = nvgCreateImage(vg, "image/icon_sniper.png", 0),
        turret_electric = nvgCreateImage(vg, "image/icon_electric.png", 0),
        turret_rocket   = nvgCreateImage(vg, "image/icon_rocket.png", 0),
    }

    -- 弓箭发射物图片
    arrowProjHandle = nvgCreateImage(vg, "image/arrow_projectile.png", 0)

    -- 火箭弹图片
    rocketProjHandle = nvgCreateImage(vg, "image/rocket_projectile.png", 0)

    -- 喷火炮台序列帧（21帧，101x235 RGBA）— 存模块级变量，ResetGame 不会丢失
    flameFrameHandles = {}
    for i = 1, 21 do
        local path = string.format("image/flame_seq/flame_%02d.png", i)
        flameFrameHandles[i] = nvgCreateImage(vg, path, 0)
    end

    print("Loaded map sprites: deadTree=" .. mapDeadTreeHandle .. " pine=" .. mapPineTreeHandle .. " green=" .. mapGreenTreeHandle .. " stone=" .. mapStoneHandle .. " ore=" .. mapOreHandle .. " bush=" .. mapBushHandle .. " pebble=" .. mapPebbleHandle)

    ResetGame()
    MountImageHandles()
    Turret.InitTurrets(G)

    -- 初始化局外系统
    Meta.Init(vg)

    CreateVirtualControls()
    -- 初始状态是 menu，摇杆只在 playing 时显示
    if vc_joystick then vc_joystick.visible = false; vc_joystick:_updateShouldShow() end

    SubscribeToEvent(vg, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")

    print("=== " .. C.TITLE .. " Started ===")
end

function Stop()
    if vg then nvgDelete(vg); vg = nil end
end

------------------------------------------------------------------------
-- 虚拟控件 (只需要摇杆)
------------------------------------------------------------------------
function CreateVirtualControls()
    -- 竖屏游戏：设计分辨率 ~400x800（与 CalcLayout 一致）
    -- VirtualControls 内部使用物理像素，需传入物理分辨率作为设计基准
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    VirtualControls.Initialize(physW, physH)

    vc_joystick = VirtualControls.CreateJoystick({
        position = Vector2(0, -200),
        alignment = {HA_CENTER, VA_BOTTOM},
        baseRadius = 65,
        knobRadius = 30,
        moveRadius = 45,
        deadZone = 0.15,
        opacity = 0.45,
        activeOpacity = 0.85,
        -- 不设 keyBinding，键盘输入已在 HandleUpdate 中手动处理
        -- 这样摇杆圆盘在所有平台都会显示
    })

    -- Web/PC 端启用鼠标模拟触摸，让鼠标可以拖动摇杆
    VirtualControls.SetMouseEmulation(true)

    print("[Controls] Joystick created, screen=" .. physW .. "x" .. physH)
end

------------------------------------------------------------------------
-- 更新
------------------------------------------------------------------------
---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    G.gameTime = G.gameTime + dt

    -- VirtualControls.Update() 由 Initialize() 内部自动订阅 BeginFrame 事件调用，无需手动调用

    -- 计算屏幕尺寸 & 布局
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local W = physW / dpr
    local H = physH / dpr
    Rend.CalcLayout(G, W, H)

    -- F2 切换 UI 编辑器（仅在 lobby 状态下生效）
    if G.state == "lobby" and input:GetKeyPress(KEY_F2) then
        UIEditor.Toggle()
    end
    -- 编辑器键盘处理（R 重置）
    UIEditor.HandleKeyboard()

    if G.state == "menu" or G.state == "gameover" then
        return
    end

    if G.state == "lobby" then
        Meta.Update(dt)
        return
    end

    if G.state == "upgrade" then
        -- 升级状态下不更新世界
        return
    end

    -- == playing 状态 ==

    -- 读取摇杆输入
    local moveX = 0
    local moveY = 0

    if vc_joystick then
        moveX = vc_joystick.x or 0
        moveY = vc_joystick.y or 0
    end

    -- 键盘补充
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then moveX = -1 end
    if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then moveX = 1 end
    if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then moveY = -1 end
    if input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) then moveY = 1 end

    -- 世界滚动
    Ent.UpdateScroll(G, dt)

    -- 资源生成
    G.resSpawnTimer = G.resSpawnTimer + dt
    if G.resSpawnTimer >= C.SPAWN_INTERVAL then
        G.resSpawnTimer = G.resSpawnTimer - C.SPAWN_INTERVAL
        Ent.SpawnResources(G)
    end

    -- 装饰物生成
    G.decoSpawnTimer = G.decoSpawnTimer + dt
    if G.decoSpawnTimer >= C.DECO_INTERVAL then
        G.decoSpawnTimer = G.decoSpawnTimer - C.DECO_INTERVAL
        Ent.SpawnDecorations(G)
    end

    -- 波次系统更新
    if G.waveActive then
        G.waveTimer = G.waveTimer + dt
        G.waveCountdown = math.max(0, G.waveDuration - G.waveTimer)

        -- 丧尸生成（间隔随波次递减，越打越多）
        local spawnInterval = math.max(C.ZOMBIE_SPAWN_INTERVAL_MIN,
            C.ZOMBIE_SPAWN_INTERVAL - G.currentWave * C.ZOMBIE_SPAWN_INTERVAL_REDUCE)
        G.zombieSpawnTimer = G.zombieSpawnTimer + dt
        if G.zombieSpawnTimer >= spawnInterval then
            G.zombieSpawnTimer = G.zombieSpawnTimer - spawnInterval
            Ent.SpawnZombie(G)
        end

        -- 波次结束 → 进入间歇期
        if G.waveTimer >= G.waveDuration then
            G.waveActive = false
            G.waveTimer = 0
            G.waveCountdown = 10  -- 间歇期10秒
        end
    else
        -- 间歇期倒计时
        G.waveCountdown = G.waveCountdown - dt
        if G.waveCountdown <= 0 then
            G.currentWave = math.min(G.currentWave + 1, G.maxWaves)
            G.waveActive = true
            G.waveTimer = 0
            G.waveCountdown = G.waveDuration
            G.level = G.currentWave  -- 同步level用于难度缩放

            -- 波次开始时批量涌现一大群僵尸
            local hordeCount = math.min(6 + G.currentWave * 2, 30)
            Ent.SpawnWaveHorde(G, hordeCount)
        end
    end

    -- 更新玩家
    Ent.UpdatePlayer(G, dt, moveX, moveY)

    -- 更新丧尸 (朝列车移动 + 攻击列车)
    Ent.UpdateZombies(G, dt)
    Turret.Update(G, dt)

    -- 更新资源节点 (受击动画/清理)
    Ent.UpdateResources(G, dt)

    -- 自动攻击/采集 (浮岛物语风格)
    Ent.AutoAttack(G, dt)

    -- 列车HP回复
    if C.TRAIN_HP_REGEN > 0 and G.trainHP < G.trainMaxHP then
        G.trainHP = math.min(G.trainMaxHP, G.trainHP + C.TRAIN_HP_REGEN * dt)
    end

    -- 提交检测
    Ent.TrySubmit(G)

    -- 升级检测
    if G.pendingLevelUp then
        G.pendingLevelUp = false
        RL.PrepareUpgrade(G)
    end

    -- 更新浮动文字 & 粒子
    Ent.UpdateFloatTexts(G, dt)
    Ent.UpdateParticles(G, dt)

    -- 提示计时器
    if G.hintTimer > 0 then
        G.hintTimer = G.hintTimer - dt
    end
end

------------------------------------------------------------------------
-- 触摸/点击处理
------------------------------------------------------------------------
local mouseDragging = false

function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    local mx = eventData["X"]:GetInt()
    local my = eventData["Y"]:GetInt()
    local dpr = graphics:GetDPR()
    local lx, ly = mx / dpr, my / dpr

    -- 编辑器优先拦截
    if G.state == "lobby" and UIEditor.HandlePointerDown(lx, ly) then
        mouseDragging = true
        return
    end

    if G.state == "lobby" then
        Meta.HandleTouchStart(lx, ly)
        mouseDragging = true
    end

    HandleClick(lx, ly)
end

function HandleMouseMove(eventType, eventData)
    if not mouseDragging then return end
    if G.state ~= "lobby" then return end
    local mx = eventData["X"]:GetInt()
    local my = eventData["Y"]:GetInt()
    local dpr = graphics:GetDPR()
    local lx, ly = mx / dpr, my / dpr

    -- 编辑器优先拦截
    if UIEditor.HandlePointerMove(lx, ly) then return end

    Meta.HandleTouchMove(lx, ly)
end

function HandleMouseUp(eventType, eventData)
    if mouseDragging then
        mouseDragging = false
        -- 编辑器优先拦截
        if UIEditor.HandlePointerUp() then return end
        if G.state == "lobby" then
            Meta.HandleTouchEnd()
        end
    end
end

function HandleTouchBegin(eventType, eventData)
    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    local dpr = graphics:GetDPR()
    local lx, ly = tx / dpr, ty / dpr

    -- 编辑器优先拦截
    if G.state == "lobby" and UIEditor.HandlePointerDown(lx, ly) then
        return
    end

    if G.state == "lobby" then
        Meta.HandleTouchStart(lx, ly)
    end

    HandleClick(lx, ly)
end

function HandleTouchMove(eventType, eventData)
    if G.state ~= "lobby" then return end
    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    local dpr = graphics:GetDPR()
    local lx, ly = tx / dpr, ty / dpr

    -- 编辑器优先拦截
    if UIEditor.HandlePointerMove(lx, ly) then return end

    Meta.HandleTouchMove(lx, ly)
end

function HandleTouchEnd(eventType, eventData)
    if G.state == "lobby" then
        -- 编辑器优先拦截
        if UIEditor.HandlePointerUp() then return end
        Meta.HandleTouchEnd()
    end
end

function HandleClick(x, y)
    if G.state == "menu" then
        local btn = G.menuBtn
        if btn and x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            G.state = "lobby"
            if vc_joystick then vc_joystick.visible = false; vc_joystick:_updateShouldShow() end
            print("[Game] Entered lobby")
        end
        return
    end

    if G.state == "lobby" then
        local physW = graphics:GetWidth()
        local physH = graphics:GetHeight()
        local dpr = graphics:GetDPR()
        local W = physW / dpr
        local H = physH / dpr
        local result, param = Meta.HandleClick(x, y, W, H)
        if result == "start_level" then
            StartLevel()
            if vc_joystick then vc_joystick.visible = true; vc_joystick:_updateShouldShow() end
            print("[Game] Starting level " .. tostring(param))
        end
        return
    end

    if G.state == "upgrade" then
        for _, cb in ipairs(G.upgradeCardBtns or {}) do
            if x >= cb.x and x <= cb.x + cb.w and y >= cb.y and y <= cb.y + cb.h then
                RL.ApplyUpgrade(G, cb.index)
                print("[Upgrade] Selected card " .. cb.index)
                return
            end
        end
        return
    end

    if G.state == "gameover" then
        local btn = G.restartBtn
        if btn and x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            G.state = "lobby"
            if vc_joystick then vc_joystick.visible = false; vc_joystick:_updateShouldShow() end
            print("[Game] Returned to lobby")
        end
        return
    end
end

------------------------------------------------------------------------
-- 渲染
------------------------------------------------------------------------
function HandleRender(eventType, eventData)
    if not vg then return end

    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local W = physW / dpr
    local H = physH / dpr

    nvgBeginFrame(vg, W, H, dpr)

    -- 菜单：全屏插画启动页
    if G.state == "menu" then
        Rend.DrawMenu(vg, G)
        nvgEndFrame(vg)
        return
    end

    -- 局外大厅：独立渲染
    if G.state == "lobby" then
        Meta.Draw(vg, W, H)
        -- UI 编辑器覆盖层（在所有 UI 之上）
        UIEditor.DrawOverlay(vg, W, H)
        nvgEndFrame(vg)
        return
    end

    -- 雪地背景
    Rend.DrawSnow(vg, G)

    -- 碎石路径
    Rend.DrawPath(vg, G)

    -- 铁轨 (枕木 + 钢轨)
    Rend.DrawRailway(vg, G)

    -- 装饰物 (枯树、雪堆)
    Rend.DrawDecorations(vg, G)

    -- 资源
    Rend.DrawResources(vg, G)

    -- 提交方块
    Rend.DrawSubmitBox(vg, G)

    -- 装甲列车
    Rend.DrawTrain(vg, G)
    Turret.Draw(vg, G)

    -- 丧尸
    Rend.DrawZombies(vg, G)

    -- 玩家 (人类幸存者)
    Rend.DrawPlayer(vg, G)

    -- 列车血条 (在玩家之后绘制，确保最高显示层级)
    Rend.DrawTrainHP(vg, G)

    -- 粒子 & 浮动文字
    Rend.DrawParticles(vg, G)
    Rend.DrawFloatTexts(vg, G)

    -- HUD
    Rend.DrawHUD(vg, G)

    -- 波次面板
    Rend.DrawWavePanel(vg, G)

    -- 右侧面板（炮塔图标 + 距离条）
    Rend.DrawRightPanel(vg, G)

    -- 提示
    Rend.DrawHint(vg, G)

    -- 菜单覆盖
    if G.state == "menu" then
        Rend.DrawMenu(vg, G)
    end

    -- 升级选卡覆盖
    if G.state == "upgrade" then
        RL.DrawUpgradeUI(vg, G)
    end

    -- Game Over 覆盖
    if G.state == "gameover" then
        Rend.DrawGameOver(vg, G)
    end

    -- 虚拟摇杆由 VirtualControls 自身的 NanoVG 上下文独立渲染（renderOrder=999999）
    -- Initialize() 已自动订阅 NanoVGRender 事件，无需手动调用 Render()

    nvgEndFrame(vg)
end
