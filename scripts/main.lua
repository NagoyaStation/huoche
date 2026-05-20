-- main.lua - 末世：我开火车送快递 Roguelike
-- 竖屏2D 俯视角，NanoVG 渲染 + VirtualControls 触摸输入

require "urhox-libs.UI.VirtualControls"

local C    = require "Game.Config"
local Ent  = require "Game.Entities"
local Rend = require "Game.Renderer"
local RL   = require "Game.Roguelike"
local Turret = require "Game.Turret"
local Drone  = require "Game.Drone"
local Meta = require "Meta.MetaMain"
local UIEditor = require "Editor.UIEditor"
local MD = require "Meta.MetaData"
local Comic = require "Game.ComicCutscene"

------------------------------------------------------------------------
-- 全局游戏状态
------------------------------------------------------------------------
---@type any
local G = {}
local vg = nil
local vc_joystick = nil

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
local trainSandbagHandle = 0 -- 火车顶部沙袋图片句柄
local mountedShootHandle = 0 -- 上车射击角色图片句柄
local muzzleFlashHandles = {} -- 开火帧序列: 4帧
local titleBannerHandle = 0  -- 标题横幅背景
-- 背景纹理句柄
local bgGroundHandle = 0
local railwayImgHandle = 0   -- 铁轨图片句柄
-- 地图素材图片句柄
local mapDeadTreeHandle = 0
local mapPineTreeHandle = 0
local mapGreenTreeHandle = 0
local mapStoneHandle = 0

local mapOreHandle = 0
local mapBushHandle = 0
local mapPebbleHandle = 0
local droneImgHandle = 0  -- 自动采集无人机图片句柄
-- 路边装饰物句柄
local decoHandles = {}  -- { poles={}, houses={}, ruins={} }
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
-- 技能按钮图片句柄
local skillBoardTrainHandle = 0       -- 上车按钮图片（可用/绿色）
local skillBoardDisabledHandle = 0    -- 上车按钮图片（不可用/灰色）
local skillDismountHandle = 0         -- 下车按钮图片
local skillFrameHandle = 0            -- 技能按钮边框
local skillBombHandle = 0             -- 角色技能图标（炸弹）
-- 炸弹 & 爆炸帧动画句柄
local bombImgHandle = 0               -- 落地炸弹图片
local bombRedImgHandle = 0            -- 炸弹红色闪烁帧
local explosionFrameHandles = {}      -- 爆炸帧动画(9帧)
-- 游戏内设置弹窗
local gameSettingPopup = {
    show = false,
    animTimer = 0,
    sfxVolume = 0.8,
    bgmVolume = 0.6,
    sfxOn = true,
    bgmOn = true,
    dragging = nil,  -- "sfx" / "bgm" / nil
    -- 布局缓存
    closeBtn = nil,
    togSfx = nil, togBgm = nil,
    sliderSfx = nil, sliderBgm = nil,
    exitBtn = nil,
    popupRect = nil,
}
local waveUIHandle = 0
local killUIHandle = 0

------------------------------------------------------------------------
-- 设计分辨率适配（lobby UI 在所有设备上保持一致布局）
------------------------------------------------------------------------
-- 设计分辨率：UI 按此尺寸设计（竖屏），在所有设备上等比缩放
local DESIGN_W = 390
local DESIGN_H = 844

-- 运行时缩放参数（每帧更新）—— 全局 SHOW_ALL，所有状态共用
local showAllScale = 1.0    -- 缩放因子
local showAllOffX  = 0      -- 水平偏移（居中补偿）
local showAllOffY  = 0      -- 垂直偏移（居中补偿）

--- 根据实际逻辑分辨率计算 SHOW_ALL 缩放参数
local function CalcShowAllScale(logW, logH)
    local sx = logW / DESIGN_W
    local sy = logH / DESIGN_H
    showAllScale = math.min(sx, sy)  -- SHOW_ALL：保证全部可见
    -- 居中偏移（letterbox/pillarbox）
    showAllOffX = (logW - DESIGN_W * showAllScale) / 2
    showAllOffY = (logH - DESIGN_H * showAllScale) / 2
end

--- 将逻辑屏幕坐标转换为设计坐标（用于输入事件）
local function LogicalToDesign(lx, ly)
    return (lx - showAllOffX) / showAllScale,
           (ly - showAllOffY) / showAllScale
end


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
        meleeAtkBonus = 0,      -- 近战攻击力加成（含采集）
        rangedAtkBonus = 0,     -- 射击攻击力加成（列车射击）
        atkSpdMul = 1.0,        -- 攻击速度倍率
        rangeMul = 1.0,         -- 攻击范围倍率

        -- 实体列表
        resources = {},
        decorations = {},
        lastDecoSide = 0,       -- 上次装饰物生成侧(1=左,2=右)，用于交替
        floatTexts = {},
        particles = {},
        puffs = {},             -- 烟雾特效（序列帧）
        bursts = {},            -- 攻击爆点特效（序列帧）
        dropItems = {},         -- 弹出资源动画
        zombies = {},
        turrets = {},
        turretProjectiles = {},
        bombs = {},
        explosions = {},
        drones = {},
        bloodStains = {},

        -- 关卡 & 波次系统
        stage = 1,               -- 当前关卡（通关10波后+1）
        currentWave = 1,
        maxWaves = 10,
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

        -- 技能系统
        mounted = false,            -- 是否上车（固定在列车顶部射击）
        mountedAimDir = 0,          -- 上车后瞄准方向（弧度）
        nearTrain = false,          -- 是否靠近列车（可上车）

        skillBoardCD = 0,           -- 上车技能冷却计时
        skillBoardCDMax = 5,        -- 上车技能冷却时长（秒）
        skillCharCD = 0,            -- 角色技能冷却计时
        skillCharCDMax = 15,        -- 角色技能冷却时长（秒）
        skillCharActive = false,    -- 角色技能是否激活中
        skillCharDuration = 0,      -- 角色技能持续剩余时间
        skillCharDurationMax = 0,   -- 角色技能持续总时长
        activeCharId = nil,         -- 当前角色ID（从存档读取）

        -- 技能按钮点击区域（由 Renderer 填充）
        skillBoardBtn = nil,
        skillCharBtn = nil,
    }

    Ent.CreatePlayer(G)
    print("=== Game Reset ===")
end

------------------------------------------------------------------------
-- 挂载图片句柄到 G（ResetGame 后调用）
------------------------------------------------------------------------
local function MountImageHandles()

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
    G.trainSandbagImg = trainSandbagHandle
    G.mountedShootImg = mountedShootHandle
    G.muzzleFlashFrames = muzzleFlashHandles
    G.titleBannerImg = titleBannerHandle
    G.bgGroundImg = bgGroundHandle
    G.railwayImg = railwayImgHandle
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
    -- 烟雾 & 攻击爆点序列帧
    G.smokeAFrames = smokeAFrameHandles
    G.smokeBFrames = smokeBFrameHandles
    G.burstFrames = burstFrameHandles
    -- 技能按钮图片
    G.skillBoardTrainImg = skillBoardTrainHandle
    G.skillBoardDisabledImg = skillBoardDisabledHandle
    G.skillDismountImg = skillDismountHandle
    G.droneImg = droneImgHandle
    G.skillFrameImg = skillFrameHandle
    -- 炸弹 & 爆炸帧动画
    G.bombImg = bombImgHandle
    G.bombRedImg = bombRedImgHandle
    G.explosionFrames = explosionFrameHandles
    G.skillBombImg = skillBombHandle
    -- 路边装饰物图片
    G.decoImgs = decoHandles
end

--- 根据局外选择的角色动态加载图片到 G
local function LoadActiveCharImages()
    local sd = Meta.GetSaveData()
    if not sd or not sd.activeChar then return end
    local charDef = nil
    for _, cd in ipairs(MD.CHARACTERS) do
        if cd.id == sd.activeChar then charDef = cd; break end
    end
    if not charDef then return end

    -- 加载角色 idle 图（待机图）
    local iconImg = nvgCreateImage(vg, charDef.icon, NVG_IMAGE_NEAREST)
    if iconImg and iconImg ~= 0 then
        G.heroImg = iconImg
    end

    -- 如果角色有攻击帧动画，用攻击帧替换默认的战斗动画
    -- 没有 attackFrames 时保留 MountImageHandles() 已挂载的默认帧
    if charDef.attackFrames and #charDef.attackFrames > 0 then
        local frames = {}
        for i, path in ipairs(charDef.attackFrames) do
            frames[i] = nvgCreateImage(vg, path, NVG_IMAGE_NEAREST)
        end
        G.heroAnimFrames = frames
    end

    -- 如果角色有行走帧动画，替换默认行走动画
    if charDef.walkFrames and #charDef.walkFrames > 0 then
        local wFrames = {}
        for i, path in ipairs(charDef.walkFrames) do
            wFrames[i] = nvgCreateImage(vg, path, NVG_IMAGE_NEAREST)
        end
        G.heroWalkFrames = wFrames
    end

    -- 加载角色专属上车图片（mounted shooting image）
    if charDef.mountedImg then
        local mImg = nvgCreateImage(vg, charDef.mountedImg, NVG_IMAGE_NEAREST)
        if mImg and mImg ~= 0 then
            G.mountedShootImg = mImg
        end
    end

    -- 扫描所有帧图片，取最大宽高作为统一画布尺寸（避免帧间大小跳变）
    local maxW, maxH = 0, 0
    local allImgs = {}
    if G.heroImg and G.heroImg ~= 0 then allImgs[#allImgs + 1] = G.heroImg end
    if G.heroAnimFrames then
        for _, img in ipairs(G.heroAnimFrames) do allImgs[#allImgs + 1] = img end
    end
    if G.heroWalkFrames then
        for _, img in ipairs(G.heroWalkFrames) do allImgs[#allImgs + 1] = img end
    end
    for _, img in ipairs(allImgs) do
        if img and img ~= 0 then
            local iw, ih = nvgImageSize(vg, img)
            if iw > maxW then maxW = iw end
            if ih > maxH then maxH = ih end
        end
    end
    if maxW > 0 and maxH > 0 then
        G.heroCanvasW = maxW
        G.heroCanvasH = maxH
    end

    print("[Game] Loaded character: " .. charDef.name .. " (" .. charDef.id .. ")"
        .. " canvas=" .. (G.heroCanvasW or 0) .. "x" .. (G.heroCanvasH or 0))
end

--- 从局外进入关卡
local function StartLevel()
    ResetGame()
    MountImageHandles()
    LoadActiveCharImages()  -- 根据局外选择的角色替换图片
    -- 记录当前角色ID（用于技能系统）
    local sd = Meta.GetSaveData()
    G.activeCharId = sd and sd.activeChar or "warrior"
    -- 将局外装备的炮台列表传入局内（只有装备了的炮台才能在升级中刷到）
    G.equippedTurrets = sd and sd.turretEquipped or {"arrow", "minigun", "sniper", "rocket"}

    -- 装备+角色属性带入局内
    local eqStats = MD.CalcEquipStats(sd)
    G.meleeAtkBonus  = G.meleeAtkBonus  + eqStats.meleeAtk              -- 近战攻击力加成
    G.rangedAtkBonus = G.rangedAtkBonus + eqStats.rangedAtk            -- 射击攻击力加成
    G.atkSpdMul   = G.atkSpdMul * (1 + eqStats.atkSpd / 100)          -- 攻速百分比
    G.speedMul    = G.speedMul  * (1 + eqStats.speed / 100)           -- 移速百分比
    G.rangeMul    = G.rangeMul  * (1 + eqStats.rangePct / 100)        -- 射程百分比
    G.goldMul     = G.goldMul   * (1 + eqStats.goldBonus / 100)       -- 金币加成百分比
    G.atkPctMul   = 1 + eqStats.atkPct / 100                          -- 攻击伤害百分比加成
    G.critRate    = eqStats.critRate                                    -- 暴击率%
    G.critDmg     = 150 + eqStats.critDmg                              -- 暴击伤害%（基础150%）
    G.defFlat     = eqStats.def                                        -- 固定减伤
    G.trainMaxHP  = C.TRAIN_MAX_HP + eqStats.hp                       -- 列车生命值加成
    G.trainHP     = G.trainMaxHP
    -- 炮台专属伤害加成（百分比）
    G.turretDmgBonus = {
        arrow   = eqStats.arrowDmg,
        minigun = eqStats.minigunDmg,
        flame   = eqStats.flameDmg,
        sniper  = eqStats.sniperDmg,
    }
    print(string.format("[Game] EquipStats applied: meleeAtk+%d rangedAtk+%d atkPct+%d%% def+%d hp+%d critRate=%d%% critDmg=%d%% atkSpd+%d%% speed+%d%% range+%d%% gold+%d%%",
        eqStats.meleeAtk, eqStats.rangedAtk, eqStats.atkPct, eqStats.def, eqStats.hp,
        eqStats.critRate, eqStats.critDmg, eqStats.atkSpd, eqStats.speed,
        eqStats.rangePct, eqStats.goldBonus))

    Turret.InitTurrets(G)
    G.state = "playing"
    G.hintText = "靠近资源自动采集，送到列车下方！保护列车！"
    G.hintTimer = 4.0
    Rend.CalcLayout(G, DESIGN_W, DESIGN_H)
    Drone.Init(G)
    Drone.UnlockDrone(G)  -- 默认解锁1架采集无人机
    Ent.CreatePlayer(G)
    print("[Game] Started playing!")
end

------------------------------------------------------------------------
-- Start / Stop
------------------------------------------------------------------------
function Start()
    -- 用 os.date 获取真实时间构造种子（os.time/os.clock/Rand在WASM中可能不可靠）
    do
        local dt = os.date("*t")
        local timeSeed = ((dt.year or 2026) * 366 + (dt.yday or 1)) * 86400
                       + (dt.hour or 0) * 3600 + (dt.min or 0) * 60 + (dt.sec or 0)
        math.randomseed(timeSeed)
    end

    vg = nvgCreate(1)
    if not vg then
        print("ERROR: Failed to create NanoVG context")
        return
    end

    if nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf") == -1 then
        print("ERROR: Failed to load font")
        return
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
    trainSandbagHandle = nvgCreateImage(vg, "image/沙袋雪地.png", 0)
    mountedShootHandle = nvgCreateImage(vg, "image/Layer_0 (11).png", 0)
    for i = 1, 4 do
        muzzleFlashHandles[i] = nvgCreateImage(vg, "image/开火帧" .. i .. ".png", 0)
    end
    titleBannerHandle = nvgCreateImage(vg, "image/title_banner_20260422074156.png", 0)
    print("Loaded train sprite: " .. trainImgHandle .. " carriage: " .. trainCarriageHandle .. " front: " .. trainFrontHandle .. " sandbag: " .. trainSandbagHandle)

    -- 背景纹理
    bgGroundHandle = nvgCreateImage(vg, "image/bg_white_snow_20260416070957.png", NVG_IMAGE_REPEATX | NVG_IMAGE_REPEATY)
    railwayImgHandle = nvgCreateImage(vg, "image/铁轨旧.png", NVG_IMAGE_REPEATY)

    -- 地图素材（像素风统一风格）
    mapDeadTreeHandle = nvgCreateImage(vg, "image/edited_map_dead_tree_clean_20260416060145.png", NVG_IMAGE_NEAREST)
    mapPineTreeHandle = nvgCreateImage(vg, "image/edited_map_pine_tree_clean_20260416060114.png", NVG_IMAGE_NEAREST)
    mapGreenTreeHandle = nvgCreateImage(vg, "image/edited_map_green_tree_clean_20260416060048.png", NVG_IMAGE_NEAREST)
    mapStoneHandle = nvgCreateImage(vg, "image/edited_map_stone_clean_20260416060244.png", NVG_IMAGE_NEAREST)

    mapOreHandle = nvgCreateImage(vg, "image/edited_map_ore_clean_20260416060319.png", NVG_IMAGE_NEAREST)
    mapBushHandle = nvgCreateImage(vg, "image/map_bush_small_20260416074158.png", NVG_IMAGE_NEAREST)
    mapPebbleHandle = nvgCreateImage(vg, "image/map_pebble_v2_20260416074909.png", NVG_IMAGE_NEAREST)

    -- 路边装饰物图片
    decoHandles.poles = {
        nvgCreateImage(vg, "image/地图装饰/电线杆.png", 0),
        nvgCreateImage(vg, "image/地图装饰/电线杆2.png", 0),
        nvgCreateImage(vg, "image/地图装饰/电线杆3.png", 0),
        nvgCreateImage(vg, "image/地图装饰/电线杆4.png", 0),
    }
    decoHandles.houses = {
        nvgCreateImage(vg, "image/地图装饰/装饰房.png", 0),
        nvgCreateImage(vg, "image/地图装饰/装饰房1.png", 0),
        nvgCreateImage(vg, "image/地图装饰/装饰房2.png", 0),
        nvgCreateImage(vg, "image/地图装饰/装饰房3.png", 0),
        nvgCreateImage(vg, "image/地图装饰/装饰房4.png", 0),
    }
    decoHandles.small = {
        nvgCreateImage(vg, "image/地图装饰/装饰房5.png", 0),  -- 小门栏
    }
    decoHandles.ruins = {
        nvgCreateImage(vg, "image/地图装饰/装饰废墟.png", 0),
        nvgCreateImage(vg, "image/地图装饰/装饰废墟1.png", 0),
        nvgCreateImage(vg, "image/地图装饰/装饰废墟2.png", 0),
        nvgCreateImage(vg, "image/地图装饰/装饰废墟3.png", 0),
        nvgCreateImage(vg, "image/地图装饰/装饰废墟4.png", 0),
        nvgCreateImage(vg, "image/地图装饰/装饰废墟5.png", 0),
        nvgCreateImage(vg, "image/地图装饰/装饰废墟6.png", 0),
        nvgCreateImage(vg, "image/地图装饰/装饰废墟7.png", 0),
        nvgCreateImage(vg, "image/地图装饰/装饰废墟8.png", 0),
    }
    print("Loaded deco images: poles=" .. #decoHandles.poles .. " houses=" .. #decoHandles.houses .. " ruins=" .. #decoHandles.ruins)

    -- 标题背景
    titleBgHandle = nvgCreateImage(vg, "image/title_bg_20260421072428.png", 0)

    -- HUD 图标
    hudIconGoldHandle = nvgCreateImage(vg, "image/hud_gold_coin.png", 0)
    hudIconWoodHandle = nvgCreateImage(vg, "image/图层_2 (1).png", 0)
    hudIconStoneHandle = nvgCreateImage(vg, "image/图层_3 (1).png", 0)
    hudIconGemHandle = nvgCreateImage(vg, "image/图层_4 (1).png", 0)
    hudSettingsHandle = nvgCreateImage(vg, "image/hud_settings.png", 0)
    hudFrameCapHandle = nvgCreateImage(vg, "image/局内资源外框.png", 0)
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
        -- 无人机卡图标
        drone = nvgCreateImage(vg, "image/b262b1ff-cae3-4ba3-99e6-9e7f9f63f9bb.png", 0),
    }

    -- 无人机图片
    droneImgHandle = nvgCreateImage(vg, "image/b262b1ff-cae3-4ba3-99e6-9e7f9f63f9bb.png", 0)
    print("Loaded drone image: " .. droneImgHandle)

    -- 技能按钮图片
    skillBoardTrainHandle = nvgCreateImage(vg, "image/局内上车按钮.png", 0)
    skillBoardDisabledHandle = nvgCreateImage(vg, "image/局内上车按钮不可用.png", 0)
    skillDismountHandle = nvgCreateImage(vg, "image/下车按钮.png", 0)
    skillFrameHandle = nvgCreateImage(vg, "image/局内技能按钮.png", 0)
    skillBombHandle = nvgCreateImage(vg, "image/局内技能炸弹.png", 0)
    print("Loaded skill button images: board=" .. skillBoardTrainHandle .. " disabled=" .. skillBoardDisabledHandle .. " dismount=" .. skillDismountHandle .. " frame=" .. skillFrameHandle .. " bomb=" .. skillBombHandle)

    -- 炸弹 & 爆炸帧动画
    bombImgHandle = nvgCreateImage(vg, "image/炸弹/炸弹.png", 0)
    bombRedImgHandle = nvgCreateImage(vg, "image/炸弹/炸弹红帧.png", 0)
    explosionFrameHandles = {}
    for i = 1, 9 do
        explosionFrameHandles[i] = nvgCreateImage(vg, "image/炸弹/" .. i .. ".png", 0)
    end
    print("Loaded bomb assets: bomb=" .. bombImgHandle .. " red=" .. bombRedImgHandle .. " explosion frames=" .. #explosionFrameHandles)

    -- 弓箭发射物图片
    arrowProjHandle = nvgCreateImage(vg, "image/arrow_projectile.png", 0)

    -- 火箭弹图片
    rocketProjHandle = nvgCreateImage(vg, "image/rocket_projectile.png", 0)

    -- 喷火炮台序列帧（21帧，101x235 RGBA）— 存模块级变量，ResetGame 不会丢失
    flameFrameHandles = {}
    for i = 1, 21 do
        local path = string.format("image/火焰特效/flame_%02d.png", i)
        flameFrameHandles[i] = nvgCreateImage(vg, path, 0)
    end

    -- 烟雾特效序列帧 (A: 9帧, B: 16帧)
    smokeAFrameHandles = {}
    for i = 1, 9 do
        smokeAFrameHandles[i] = nvgCreateImage(vg, "image/特效/烟雾特效" .. i .. ".png", 0)
    end
    smokeBFrameHandles = {}
    for i = 1, 16 do
        smokeBFrameHandles[i] = nvgCreateImage(vg, "image/特效/第二种烟雾特效" .. i .. ".png", 0)
    end
    -- 攻击爆点序列帧 (4帧)
    burstFrameHandles = {}
    for i = 1, 4 do
        burstFrameHandles[i] = nvgCreateImage(vg, "image/特效/攻击爆点" .. i .. ".png", 0)
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

    -- 计算屏幕尺寸 & 布局（始终使用设计分辨率）
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local W = physW / dpr
    local H = physH / dpr
    CalcShowAllScale(W, H)
    Rend.CalcLayout(G, DESIGN_W, DESIGN_H)

    -- F2 切换 UI 编辑器（仅在 lobby 状态下生效）
    if G.state == "lobby" and input:GetKeyPress(KEY_F2) then
        UIEditor.Toggle()
    end
    -- 编辑器键盘处理（R 重置）
    UIEditor.HandleKeyboard()

    -- 漫画剧情更新
    if Comic.IsActive() then
        Comic.Update(dt)
    end

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
            if G.currentWave >= G.maxWaves then
                -- 本关所有波次完成 → 进入下一关
                G.stage = (G.stage or 1) + 1
                G.currentWave = 1
                print("[Game] Stage " .. G.stage .. " started!")
            else
                G.currentWave = G.currentWave + 1
            end
            G.waveActive = true
            G.waveTimer = 0
            G.waveCountdown = G.waveDuration
            G.level = (G.stage - 1) * G.maxWaves + G.currentWave  -- 全局难度等级

            -- 波次开始时批量涌现一大群僵尸
            local hordeCount = math.min(6 + G.level * 2, 30)
            Ent.SpawnWaveHorde(G, hordeCount)
        end
    end

    -- ===== 技能系统更新 =====
    -- 近距检测
    G.nearTrain = Ent.IsNearTrain(G)

    -- 上车/下车冷却
    if not G.mounted and G.skillBoardCD > 0 then
        G.skillBoardCD = math.max(0, G.skillBoardCD - dt)
    end

    -- 角色技能冷却
    if G.skillCharCD > 0 then
        G.skillCharCD = math.max(0, G.skillCharCD - dt)
    end

    -- 角色技能持续时间倒计时
    if G.skillCharActive and G.skillCharDuration > 0 then
        G.skillCharDuration = G.skillCharDuration - dt
        if G.skillCharDuration <= 0 then
            Ent.EndCharSkill(G)
        end
    end

    -- 灼烧DOT（龙息技能）
    for _, z in ipairs(G.zombies or {}) do
        if not z.dead and z.burnTimer and z.burnTimer > 0 then
            z.burnTimer = z.burnTimer - dt
            z.hp = z.hp - (z.burnDps or 0) * dt
            if z.hp <= 0 then
                z.dead = true
                G.killCount = (G.killCount or 0) + 1
                Ent.SpawnParticles(G, z.x, z.y, { 255, 100, 20 }, 3)
            end
        end
    end

    -- 上车状态：触摸/鼠标瞄准（替代摇杆）
    if G.mounted then
        local mouseDown = input:GetMouseButtonDown(MOUSEB_LEFT)
        if mouseDown then
            local mousePos = input:GetMousePosition()
            local lx = mousePos.x / dpr
            local ly = mousePos.y / dpr
            local tdx, tdy = LogicalToDesign(lx, ly)
            local p = G.player
            local aimDx = tdx - p.x
            local aimDy = tdy - p.y
            if math.abs(aimDx) > 5 or math.abs(aimDy) > 5 then
                G.mountedAimDir = math.atan(aimDy, aimDx)
                G.mountedAimActive = true
                if math.abs(aimDx) > 5 then
                    p.facing = aimDx > 0 and 1 or -1
                end
            end
        else
            G.mountedAimActive = false
        end
    end

    -- 更新玩家（上车状态 vs 自由移动）
    if G.mounted then
        Ent.UpdateMounted(G, dt, moveX, moveY)
    else
        Ent.UpdatePlayer(G, dt, moveX, moveY)
    end

    -- 更新丧尸 (朝列车移动 + 攻击列车)
    Ent.UpdateZombies(G, dt)
    Turret.Update(G, dt)
    Drone.Update(G, dt)

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

    -- 更新炸弹 & 爆炸
    Ent.UpdateBombs(G, dt, G.lastScrollDelta or 0)
    Ent.UpdateExplosions(G, dt)

    -- 更新浮动文字 & 粒子 & 血迹
    Ent.UpdateFloatTexts(G, dt)
    Ent.UpdateParticles(G, dt)
    Ent.UpdatePuffs(G, dt)
    Ent.UpdateBursts(G, dt)
    Ent.UpdateDropItems(G, dt)
    Ent.UpdateBloodStains(G, dt)

    -- 火车受击闪红递减
    if (G.trainHitFlash or 0) > 0 then
        G.trainHitFlash = G.trainHitFlash - dt
        if G.trainHitFlash < 0 then G.trainHitFlash = 0 end
    end

    -- 提示计时器
    if G.hintTimer > 0 then
        G.hintTimer = G.hintTimer - dt
    end
end

------------------------------------------------------------------------
-- 触摸/点击处理
------------------------------------------------------------------------
local mouseDragging = false

local lastPointerDownFrame = -1
function HandleMouseDown(eventType, eventData)
    -- 帧级去重：触摸屏会同时触发 Mouse + Touch，只处理第一个
    local frame = time.frameNumber
    if frame == lastPointerDownFrame then return end
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    lastPointerDownFrame = frame
    local mx = eventData["X"]:GetInt()
    local my = eventData["Y"]:GetInt()
    local dpr = graphics:GetDPR()
    local lx, ly = mx / dpr, my / dpr

    -- 所有状态统一转换为设计坐标
    local dx, dy = LogicalToDesign(lx, ly)

    if G.state == "lobby" then
        -- 编辑器优先拦截
        if UIEditor.HandlePointerDown(dx, dy) then
            mouseDragging = true
            return
        end
        Meta.HandleTouchStart(dx, dy)
        mouseDragging = true
        HandleClick(dx, dy)
        return
    end

    HandleClick(dx, dy)
end

function HandleMouseMove(eventType, eventData)
    if not mouseDragging then return end
    local mx = eventData["X"]:GetInt()
    local my = eventData["Y"]:GetInt()
    local dpr = graphics:GetDPR()
    local lx, ly = mx / dpr, my / dpr
    local dx, dy = LogicalToDesign(lx, ly)

    -- 游戏内设置弹窗滑块拖拽（设计坐标）
    if gameSettingPopup.show and gameSettingPopup.dragging then
        local sp = gameSettingPopup
        if sp.dragging == "sfx" and sp.sliderSfx then
            sp.sfxVolume = math.max(0, math.min(1, (dx - sp.sliderSfx.sx) / sp.sliderSfx.sw))
        elseif sp.dragging == "bgm" and sp.sliderBgm then
            sp.bgmVolume = math.max(0, math.min(1, (dx - sp.sliderBgm.sx) / sp.sliderBgm.sw))
        end
        return
    end

    if G.state ~= "lobby" then return end

    -- 编辑器优先拦截
    if UIEditor.HandlePointerMove(dx, dy) then return end

    Meta.HandleTouchMove(dx, dy)
end

function HandleMouseUp(eventType, eventData)
    if mouseDragging then
        mouseDragging = false
        -- 游戏内设置弹窗释放拖拽
        if gameSettingPopup.dragging then
            gameSettingPopup.dragging = nil
            return
        end
        -- 编辑器优先拦截
        if UIEditor.HandlePointerUp() then return end
        if G.state == "lobby" then
            Meta.HandleTouchEnd()
        end
    end
end

function HandleTouchBegin(eventType, eventData)
    -- 帧级去重（与 HandleMouseDown 共享）
    local frame = time.frameNumber
    if frame == lastPointerDownFrame then return end
    lastPointerDownFrame = frame

    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    local dpr = graphics:GetDPR()
    local lx, ly = tx / dpr, ty / dpr
    local dx, dy = LogicalToDesign(lx, ly)

    if G.state == "lobby" then
        -- 编辑器优先拦截
        if UIEditor.HandlePointerDown(dx, dy) then return end
        Meta.HandleTouchStart(dx, dy)
        HandleClick(dx, dy)
        return
    end

    HandleClick(dx, dy)
end

function HandleTouchMove(eventType, eventData)
    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    local dpr = graphics:GetDPR()
    local lx, ly = tx / dpr, ty / dpr
    local dx, dy = LogicalToDesign(lx, ly)

    -- 游戏内设置弹窗滑块拖拽（设计坐标）
    if gameSettingPopup.show and gameSettingPopup.dragging then
        local sp = gameSettingPopup
        if sp.dragging == "sfx" and sp.sliderSfx then
            sp.sfxVolume = math.max(0, math.min(1, (dx - sp.sliderSfx.sx) / sp.sliderSfx.sw))
        elseif sp.dragging == "bgm" and sp.sliderBgm then
            sp.bgmVolume = math.max(0, math.min(1, (dx - sp.sliderBgm.sx) / sp.sliderBgm.sw))
        end
        return
    end

    if G.state ~= "lobby" then return end

    -- 编辑器优先拦截
    if UIEditor.HandlePointerMove(dx, dy) then return end

    Meta.HandleTouchMove(dx, dy)
end

function HandleTouchEnd(eventType, eventData)
    -- 游戏内设置弹窗释放拖拽
    if gameSettingPopup.dragging then
        gameSettingPopup.dragging = nil
        return
    end
    if G.state == "lobby" then
        -- 编辑器优先拦截
        if UIEditor.HandlePointerUp() then return end
        Meta.HandleTouchEnd()
    end
end

------------------------------------------------------------------------
-- 游戏内设置弹窗绘制（逻辑坐标系）
------------------------------------------------------------------------
local function DrawGameSettingPopup(W, H)
    local sp = gameSettingPopup
    local s = G.uiScale or 1
    sp.animTimer = sp.animTimer + 1/60
    local t = math.min(sp.animTimer / 0.2, 1.0)
    local easeT = 1 - (1 - t) * (1 - t)
    local sc = 0.85 + 0.15 * easeT
    local alpha = math.floor(255 * easeT)

    -- 遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(140 * easeT)))
    nvgFill(vg)

    -- 弹窗尺寸
    local pw = math.min(W * 0.78, 300 * s)
    local ph = 280 * s
    local px = (W - pw) / 2
    local py = (H - ph) / 2

    nvgSave(vg)
    local cx, cy = px + pw / 2, py + ph / 2
    nvgTranslate(vg, cx, cy)
    nvgScale(vg, sc, sc)
    nvgTranslate(vg, -cx, -cy)
    nvgGlobalAlpha(vg, alpha / 255)

    -- 外发光
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px - 14, py - 14, pw + 28, ph + 28, 26)
    nvgFillPaint(vg, nvgBoxGradient(vg, px - 4, py - 4, pw + 8, ph + 8, 18, 24,
        nvgRGBA(60, 130, 220, math.floor(50 * easeT)), nvgRGBA(0, 0, 0, 0)))
    nvgFill(vg)

    -- 主背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 14)
    nvgFillPaint(vg, nvgLinearGradient(vg, px, py, px, py + ph,
        nvgRGBA(28, 36, 62, 252), nvgRGBA(18, 22, 42, 252)))
    nvgFill(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 14)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokePaint(vg, nvgLinearGradient(vg, px, py, px + pw, py + ph,
        nvgRGBA(60, 110, 200, 140), nvgRGBA(80, 60, 180, 140)))
    nvgStroke(vg)

    -- 标题栏
    local titleH = 46 * s
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px + 2, py + 2, pw - 4, titleH, 12 * s)
    nvgFillPaint(vg, nvgLinearGradient(vg, px, py, px, py + titleH,
        nvgRGBA(35, 55, 110, 200), nvgRGBA(22, 28, 48, 160)))
    nvgFill(vg)

    -- 高光线
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 24 * s, py + 3)
    nvgLineTo(vg, px + pw - 24 * s, py + 3)
    nvgStrokeWidth(vg, 1)
    nvgStrokeColor(vg, nvgRGBA(120, 170, 255, 60))
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 20 * s)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 235, 255, 255))
    nvgText(vg, cx, py + titleH / 2, "设 置")

    -- 装饰线
    local decoY = py + titleH / 2
    for side = -1, 1, 2 do
        local lx1 = cx + side * 30 * s
        local lx2 = cx + side * (pw / 2 - 24 * s)
        nvgBeginPath(vg)
        nvgMoveTo(vg, lx1, decoY)
        nvgLineTo(vg, lx2, decoY)
        nvgStrokeWidth(vg, 1)
        nvgStrokePaint(vg, nvgLinearGradient(vg, lx1, decoY, lx2, decoY,
            nvgRGBA(100, 160, 255, 80), nvgRGBA(100, 160, 255, 0)))
        nvgStroke(vg)
    end

    -- 关闭按钮
    local closeX = px + pw - 20 * s
    local closeY = py + titleH / 2
    nvgBeginPath(vg)
    nvgCircle(vg, closeX, closeY, 12 * s)
    nvgFillColor(vg, nvgRGBA(200, 60, 60, 180))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, closeX, closeY, 12 * s)
    nvgStrokeColor(vg, nvgRGBA(255, 100, 100, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, 16 * s)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
    nvgText(vg, closeX, closeY, "✕")
    sp.closeBtn = { x = closeX, y = closeY }

    -- 内容区域
    local contentY = py + titleH + 12 * s
    local padX = 20 * s
    local leftX = px + padX
    local rightEnd = px + pw - padX

    -- 音频行绘制
    local function drawAudioRow(label, isOn, volume, rowY, key)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16 * s)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(190, 210, 240, 255))
        nvgText(vg, leftX, rowY + 12 * s, label)

        -- 开关
        local togW, togH = 42 * s, 22 * s
        local togX = leftX + 52 * s
        local togY = rowY + 12 * s - togH / 2
        nvgBeginPath(vg)
        nvgRoundedRect(vg, togX, togY, togW, togH, togH / 2)
        if isOn then
            nvgFillPaint(vg, nvgLinearGradient(vg, togX, togY, togX + togW, togY,
                nvgRGBA(50, 160, 80, 255), nvgRGBA(80, 200, 120, 255)))
        else
            nvgFillColor(vg, nvgRGBA(60, 65, 80, 255))
        end
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, togX, togY, togW, togH, togH / 2)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, isOn and 40 or 20))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        local dotR = togH / 2 - 3
        local dotCX = isOn and (togX + togW - togH / 2) or (togX + togH / 2)
        nvgBeginPath(vg)
        nvgCircle(vg, dotCX, togY + togH / 2, dotR)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        nvgFill(vg)

        sp["tog" .. key] = { x = togX, y = togY, w = togW, h = togH }

        -- 滑块
        local sliderX = togX + togW + 14 * s
        local sliderW = rightEnd - sliderX
        local sliderY = rowY + 12 * s
        local trackH = 6 * s
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sliderX, sliderY - trackH / 2, sliderW, trackH, trackH / 2)
        nvgFillColor(vg, nvgRGBA(40, 45, 60, isOn and 255 or 120))
        nvgFill(vg)

        local fillW = sliderW * volume
        if fillW > 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sliderX, sliderY - trackH / 2, fillW, trackH, trackH / 2)
            if isOn then
                nvgFillPaint(vg, nvgLinearGradient(vg, sliderX, sliderY, sliderX + fillW, sliderY,
                    nvgRGBA(60, 140, 255, 255), nvgRGBA(100, 180, 255, 255)))
            else
                nvgFillColor(vg, nvgRGBA(80, 90, 110, 150))
            end
            nvgFill(vg)
        end

        local thumbX = sliderX + fillW
        local thumbR = 9 * s
        if isOn then
            nvgBeginPath(vg)
            nvgCircle(vg, thumbX, sliderY, thumbR + 3 * s)
            nvgFillColor(vg, nvgRGBA(60, 140, 255, 40))
            nvgFill(vg)
        end
        nvgBeginPath(vg)
        nvgCircle(vg, thumbX, sliderY, thumbR)
        if isOn then
            nvgFillPaint(vg, nvgRadialGradient(vg, thumbX, sliderY, 0, thumbR,
                nvgRGBA(200, 230, 255, 255), nvgRGBA(100, 170, 255, 255)))
        else
            nvgFillColor(vg, nvgRGBA(100, 105, 120, 200))
        end
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, thumbX, sliderY, thumbR)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, isOn and 60 or 20))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        nvgFontSize(vg, 11 * s)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(160, 180, 210, isOn and 200 or 100))
        nvgText(vg, thumbX, sliderY + thumbR + 4 * s, math.floor(volume * 100) .. "%")

        sp["slider" .. key] = { x = sliderX, y = sliderY - 16, w = sliderW, h = 32, sx = sliderX, sw = sliderW }
    end

    -- 音效行
    nvgBeginPath(vg)
    nvgMoveTo(vg, leftX, contentY - 4)
    nvgLineTo(vg, rightEnd, contentY - 4)
    nvgStrokeColor(vg, nvgRGBA(80, 110, 180, 40))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    drawAudioRow("音效", sp.sfxOn, sp.sfxVolume, contentY, "Sfx")

    -- 音乐行
    local bgmRowY = contentY + 52 * s
    nvgBeginPath(vg)
    nvgMoveTo(vg, leftX, bgmRowY - 4 * s)
    nvgLineTo(vg, rightEnd, bgmRowY - 4 * s)
    nvgStrokeColor(vg, nvgRGBA(80, 110, 180, 40))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    drawAudioRow("音乐", sp.bgmOn, sp.bgmVolume, bgmRowY, "Bgm")

    -- 分隔线
    local sepY = bgmRowY + 56 * s
    nvgBeginPath(vg)
    nvgMoveTo(vg, leftX + 10 * s, sepY)
    nvgLineTo(vg, rightEnd - 10 * s, sepY)
    nvgStrokeColor(vg, nvgRGBA(80, 110, 180, 50))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 退出按钮（替代兑换码）
    local btnW = 180 * s
    local btnH = 40 * s
    local btnX = cx - btnW / 2
    local btnY = sepY + 14 * s
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 10 * s)
    nvgFillPaint(vg, nvgLinearGradient(vg, btnX, btnY, btnX, btnY + btnH,
        nvgRGBA(160, 50, 50, 240), nvgRGBA(120, 35, 35, 240)))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX + 1, btnY + 1, btnW - 2, btnH / 2 - 1, 9 * s)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 18))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 10 * s)
    nvgStrokeColor(vg, nvgRGBA(255, 100, 100, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16 * s)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 220, 255))
    nvgText(vg, cx, btnY + btnH / 2, "退出游戏")
    sp.exitBtn = { x = btnX, y = btnY, w = btnW, h = btnH }

    -- 版本号（右下角）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12 * s)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(100, 120, 150, 160))
    nvgText(vg, px + pw - 14 * s, py + ph - 10 * s, "版本：1.0.0")

    nvgRestore(vg)
    sp.popupRect = { x = px, y = py, w = pw, h = ph }
end

------------------------------------------------------------------------
-- 游戏内设置弹窗点击处理
------------------------------------------------------------------------
local function HandleGameSettingClick(x, y)
    local sp = gameSettingPopup

    -- 关闭按钮
    if sp.closeBtn then
        local b = sp.closeBtn
        if (x - b.x) * (x - b.x) + (y - b.y) * (y - b.y) <= 14 * 14 then
            sp.show = false
            sp.dragging = nil
            return true
        end
    end

    -- 音效开关
    if sp.togSfx then
        local t = sp.togSfx
        if x >= t.x and x <= t.x + t.w and y >= t.y and y <= t.y + t.h then
            sp.sfxOn = not sp.sfxOn
            print("[GameSetting] SFX: " .. tostring(sp.sfxOn))
            return true
        end
    end

    -- 音乐开关
    if sp.togBgm then
        local t = sp.togBgm
        if x >= t.x and x <= t.x + t.w and y >= t.y and y <= t.y + t.h then
            sp.bgmOn = not sp.bgmOn
            print("[GameSetting] BGM: " .. tostring(sp.bgmOn))
            return true
        end
    end

    -- 音效滑块
    if sp.sliderSfx and sp.sfxOn then
        local s = sp.sliderSfx
        if x >= s.x - 10 and x <= s.x + s.w + 10 and y >= s.y and y <= s.y + s.h then
            sp.sfxVolume = math.max(0, math.min(1, (x - s.sx) / s.sw))
            sp.dragging = "sfx"
            return true
        end
    end

    -- 音乐滑块
    if sp.sliderBgm and sp.bgmOn then
        local s = sp.sliderBgm
        if x >= s.x - 10 and x <= s.x + s.w + 10 and y >= s.y and y <= s.y + s.h then
            sp.bgmVolume = math.max(0, math.min(1, (x - s.sx) / s.sw))
            sp.dragging = "bgm"
            return true
        end
    end

    -- 退出按钮
    if sp.exitBtn then
        local b = sp.exitBtn
        if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            sp.show = false
            sp.dragging = nil
            -- 上传分数并返回大厅
            local stage = G.stage or 1
            local wave = G.currentWave or 1
            Meta.UploadGameScore(stage, wave)
            G.state = "lobby"
            if vc_joystick then vc_joystick.visible = false; vc_joystick:_updateShouldShow() end
            print("[GameSetting] Exit to lobby, stage:" .. stage .. " wave:" .. wave)
            return true
        end
    end

    -- 弹窗外关闭
    if sp.popupRect then
        local p = sp.popupRect
        if x < p.x or x > p.x + p.w or y < p.y or y > p.y + p.h then
            sp.show = false
            sp.dragging = nil
            return true
        end
    end

    return true  -- 吞掉弹窗内点击
end

local lastClickFrame = -1
function HandleClick(x, y)
    -- 同一帧内去重（触摸屏会同时触发 Mouse + Touch 事件）
    local frame = time.frameNumber
    if frame == lastClickFrame then return end
    lastClickFrame = frame

    -- 游戏内设置弹窗优先拦截（所有状态）
    if gameSettingPopup.show then
        HandleGameSettingClick(x, y)
        return
    end

    -- 漫画剧情进行中：接管点击
    if Comic.IsActive() then
        Comic.HandleClick(x, y, DESIGN_W, DESIGN_H)
        return
    end

    if G.state == "menu" then
        local btn = G.menuBtn
        if btn and x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            -- 启动开幕漫画剧情
            Comic.Start(vg, function()
                G.state = "lobby"
                if vc_joystick then vc_joystick.visible = false; vc_joystick:_updateShouldShow() end
                print("[Game] Comic finished, entered lobby")
            end)
            print("[Game] Starting opening comic")
        end
        return
    end

    if G.state == "lobby" then
        -- x, y 已在上游转换为设计坐标，使用设计分辨率
        local result, param = Meta.HandleClick(x, y, DESIGN_W, DESIGN_H)
        if result == "start_level" then
            StartLevel()
            if vc_joystick then vc_joystick.visible = true; vc_joystick:_updateShouldShow() end
            print("[Game] Starting level " .. tostring(param))
        end
        return
    end

    if G.state == "playing" then
        -- 齿轮按钮打开设置弹窗
        if G.hudSettingBtn then
            local sb = G.hudSettingBtn
            if x >= sb.x and x <= sb.x + sb.w and y >= sb.y and y <= sb.y + sb.h then
                gameSettingPopup.show = true
                gameSettingPopup.animTimer = 0
                print("[Game] Open in-game settings")
                return
            end
        end

        -- 左侧技能按钮：上车/下车
        if G.skillBoardBtn then
            local sb = G.skillBoardBtn
            if x >= sb.x and x <= sb.x + sb.w and y >= sb.y and y <= sb.y + sb.h then
                if G.mounted then
                    -- 已在车上 → 下车，恢复摇杆
                    Ent.DismountTrain(G)
                    if vc_joystick then vc_joystick.visible = true; vc_joystick:_updateShouldShow() end
                elseif G.nearTrain and (G.skillBoardCD or 0) <= 0 then
                    -- 靠近列车且不在冷却 → 上车，隐藏摇杆
                    Ent.MountTrain(G)
                    if vc_joystick then vc_joystick.visible = false; vc_joystick:_updateShouldShow() end
                end
                return
            end
        end

        -- 右侧技能按钮：角色技能
        if G.skillCharBtn then
            local sb = G.skillCharBtn
            if x >= sb.x and x <= sb.x + sb.w and y >= sb.y and y <= sb.y + sb.h then
                if (G.skillCharCD or 0) <= 0 and not G.skillCharActive then
                    Ent.ActivateCharSkill(G)
                end
                return
            end
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
            -- 上传本局最高记录到云排行榜
            local stage = G.stage or 1
            local wave = G.currentWave or 1
            Meta.UploadGameScore(stage, wave)
            G.state = "lobby"
            if vc_joystick then vc_joystick.visible = false; vc_joystick:_updateShouldShow() end
            print("[Game] Returned to lobby, stage:" .. stage .. " wave:" .. wave)
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

    -- 漫画剧情（全屏覆盖，优先级最高）
    if Comic.IsActive() then
        if showAllOffX > 0 or showAllOffY > 0 then
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, W, H)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
            nvgFill(vg)
        end
        nvgSave(vg)
        nvgTranslate(vg, showAllOffX, showAllOffY)
        nvgScale(vg, showAllScale, showAllScale)
        Comic.Draw(vg, DESIGN_W, DESIGN_H)
        nvgRestore(vg)
        nvgEndFrame(vg)
        return
    end

    -- 菜单：全屏插画启动页（SHOW_ALL 包装）
    if G.state == "menu" then
        if showAllOffX > 0 or showAllOffY > 0 then
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, W, H)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
            nvgFill(vg)
        end
        nvgSave(vg)
        nvgTranslate(vg, showAllOffX, showAllOffY)
        nvgScale(vg, showAllScale, showAllScale)
        Rend.DrawMenu(vg, G)
        nvgRestore(vg)
        nvgEndFrame(vg)
        return
    end

    -- 局外大厅：独立渲染（设计分辨率缩放）
    if G.state == "lobby" then
        -- 黑色背景填充（letterbox/pillarbox 区域）
        if showAllOffX > 0 or showAllOffY > 0 then
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, W, H)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
            nvgFill(vg)
        end
        nvgSave(vg)
        nvgTranslate(vg, showAllOffX, showAllOffY)
        nvgScale(vg, showAllScale, showAllScale)
        Meta.Draw(vg, DESIGN_W, DESIGN_H)
        -- UI 编辑器覆盖层（在所有 UI 之上）
        UIEditor.DrawOverlay(vg, DESIGN_W, DESIGN_H)
        nvgRestore(vg)
        nvgEndFrame(vg)
        return
    end

    -- ===== 战斗场景 SHOW_ALL 包装 =====
    if showAllOffX > 0 or showAllOffY > 0 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, W, H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        nvgFill(vg)
    end
    nvgSave(vg)
    nvgTranslate(vg, showAllOffX, showAllOffY)
    nvgScale(vg, showAllScale, showAllScale)

    -- 雪地背景
    Rend.DrawSnow(vg, G)

    -- 碎石路径
    Rend.DrawPath(vg, G)

    -- 铁轨 (枕木 + 钢轨)
    Rend.DrawRailway(vg, G)

    -- 装饰物 (枯树、雪堆)
    Rend.DrawDecorations(vg, G)

    -- 地面血迹（僵尸死亡残留，在装饰物之后、资源之前）
    Rend.DrawBloodStains(vg, G)

    -- 资源
    Rend.DrawResources(vg, G)

    -- 提交方块
    Rend.DrawSubmitBox(vg, G)

    -- 装甲列车
    Rend.DrawTrain(vg, G)
    Turret.Draw(vg, G)
    Drone.Draw(vg, G)

    -- 炸弹（地面上）
    Rend.DrawBombs(vg, G)

    -- 丧尸
    Rend.DrawZombies(vg, G)

    -- 携带资源跟随队列（在玩家后面层级）
    Rend.DrawCarryQueue(vg, G)

    -- 玩家 (人类幸存者)
    Rend.DrawPlayer(vg, G)

    -- 资源血条 & 掉落信息（在玩家之后绘制，保证不被遮挡）
    Rend.DrawResourceUI(vg, G)

    -- 瞄准虚线（上车状态，玩家之后绘制）
    Rend.DrawAimLine(vg, G)

    -- 列车血条 (在玩家之后绘制，确保最高显示层级)
    Rend.DrawTrainHP(vg, G)

    -- 爆炸特效
    Rend.DrawExplosions(vg, G)

    -- 粒子 & 烟雾 & 弹出资源 & 浮动文字
    Rend.DrawParticles(vg, G)
    Rend.DrawPuffs(vg, G)
    Rend.DrawBursts(vg, G)
    Rend.DrawDropItems(vg, G)
    Rend.DrawFloatTexts(vg, G)

    -- HUD
    Rend.DrawHUD(vg, G)

    -- 波次面板
    Rend.DrawWavePanel(vg, G)

    -- 右侧面板（炮塔图标 + 距离条）
    Rend.DrawRightPanel(vg, G)

    -- 技能按钮（摇杆左右两侧）
    Rend.DrawSkillButtons(vg, G)

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

    -- 游戏内设置弹窗（最高层级，覆盖所有游戏内容）
    if gameSettingPopup.show then
        DrawGameSettingPopup(DESIGN_W, DESIGN_H)
    end

    nvgRestore(vg)  -- ===== 结束 SHOW_ALL 包装 =====

    -- 虚拟摇杆由 VirtualControls 自身的 NanoVG 上下文独立渲染（renderOrder=999999）
    -- Initialize() 已自动订阅 NanoVGRender 事件，无需手动调用 Render()

    nvgEndFrame(vg)
end
