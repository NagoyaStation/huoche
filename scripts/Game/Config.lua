-- Game/Config.lua - 末世：我开火车送快递 资源收集配置
local C = {}

-- 延迟加载 Turret 模块（避免循环依赖，且只 require 一次）
local _Turret
local function getTurret()
    if not _Turret then _Turret = require("Game.Turret") end
    return _Turret
end

-- 延迟加载 Drone 模块
local _Drone
local function getDrone()
    if not _Drone then _Drone = require("Game.Drone") end
    return _Drone
end

C.TITLE = "末世：我开火车送快递"

------------------------------------------------------------------------
-- 滚动 & 世界
------------------------------------------------------------------------
C.BASE_SCROLL_SPEED = 20         -- 基础滚动速度 px/s (视觉放缓，节奏靠LEVEL_DIST_TARGET同步调整)
C.SCROLL_SPEED_PER_LEVEL = 0     -- 不随关卡加速
C.PATH_WIDTH_RATIO = 0.30        -- 路径(铁轨/雪道)宽度占屏幕比例

------------------------------------------------------------------------
-- 列车 HP
------------------------------------------------------------------------
C.TRAIN_MAX_HP = 1000            -- 列车最大生命值
C.TRAIN_HP_REGEN = 0             -- 列车每秒自动回复(默认不回)

------------------------------------------------------------------------
-- 玩家 (人类幸存者)
------------------------------------------------------------------------
C.PLAYER_SPEED = 140
C.PLAYER_W = 22
C.PLAYER_H = 32
C.MAX_CARRY = 10

-- 自动攻击/采集 (浮岛物语风格)
C.AUTO_ATTACK_RANGE = 48         -- 自动攻击/采集范围(匹配更大的资源节点)
C.AUTO_ATTACK_INTERVAL = 0.35    -- 攻击间隔(秒)
C.PLAYER_ATK = 30                -- 玩家基础攻击力
C.PLAYER_ATK_ZOMBIE = 30         -- 对丧尸攻击力

------------------------------------------------------------------------
-- 资源节点 (有HP，需采集)
------------------------------------------------------------------------
C.RES = {
    wood  = { name = "木材", freq = 0.35, hp = 80,  drop = 2 },
    stone = { name = "岩石", freq = 0.30, hp = 100, drop = 2 },
    ore   = { name = "矿石", freq = 0.10, hp = 150, drop = 1 },
    bush  = { name = "灌木", freq = 0.15, hp = 50,  drop = 1 },
    pebble = { name = "碎石", freq = 0.10, hp = 60,  drop = 1 },
}
C.SPAWN_INTERVAL = 1.4            -- 生成间隔加大，降低密度
C.RES_PER_SPAWN_MIN = 1
C.RES_PER_SPAWN_MAX = 2
C.RES_SIZE = 28                  -- 节点视觉大，像真实物体

------------------------------------------------------------------------
-- 丧尸 (只攻击列车) - Spine 动画系统
------------------------------------------------------------------------
C.ZOMBIE_SPAWN_INTERVAL = 2.5    -- 基础丧尸生成间隔(秒)
C.ZOMBIE_SPAWN_INTERVAL_MIN = 0.6 -- 最小生成间隔(秒)
C.ZOMBIE_SPAWN_INTERVAL_REDUCE = 0.3 -- 每级减少间隔(秒)
C.ZOMBIE_SIZE = 20               -- 碰撞半径
C.ZOMBIE_DAMAGE = 8              -- 基础对列车伤害
C.ZOMBIE_ATK_INTERVAL = 1.2      -- 攻击列车间隔
C.ZOMBIE_MAX_BASE = 15           -- 基础最大丧尸数
C.ZOMBIE_MAX_PER_LEVEL = 5       -- 每级增加最大丧尸数
C.ZOMBIE_MAX_CAP = 100           -- 绝对上限

-- Spine 丧尸类型定义
-- tier: 1=低级 2=中级 3=高级 4=精英 5=Boss
-- unlockLevel: 该类型最早出现的关卡
-- midWave: 是否仅在波次中期才出现（新丧尸不在波次开头出）
C.ZOMBIE_TYPES = {
    -- ====== Tier 1: 低级丧尸 (关卡1起) ======
    { id = "famish",              name = "饥饿丧尸",   tier = 1, unlockLevel = 1,
      spine = "spine/Zombies/famish/famish.json",
      hp = 70,  speed = 24, damage = 7,  drawScale = 0.14, midWave = false },
    { id = "twitch",              name = "抽搐丧尸",   tier = 1, unlockLevel = 1,
      spine = "spine/Zombies/twitch/twitch.json",
      hp = 50,  speed = 35, damage = 5,  drawScale = 0.14, midWave = false },
    { id = "DroughtT1_MaleForm",  name = "旱区丧尸♂",  tier = 1, unlockLevel = 3,
      spine = "spine/Zombies/DroughtT1_MaleForm/DroughtT1_MaleForm.json",
      hp = 85,  speed = 18, damage = 9,  drawScale = 0.14, midWave = true },
    { id = "DroughtT1_FemaleForm",name = "旱区丧尸♀",  tier = 1, unlockLevel = 3,
      spine = "spine/Zombies/DroughtT1_FemaleForm/DroughtT1_FemaleForm.json",
      hp = 75,  speed = 22, damage = 7,  drawScale = 0.14, midWave = true },

    -- ====== Tier 2: 中级丧尸 (关卡4起) ======
    { id = "headless",            name = "无头丧尸",   tier = 2, unlockLevel = 4,
      spine = "spine/Zombies/headless/headless.json",
      hp = 130, speed = 22, damage = 12, drawScale = 0.13, midWave = true },
    { id = "boomer",              name = "膨胀丧尸",   tier = 2, unlockLevel = 4,
      spine = "spine/Zombies/boomer/boomer.json",
      hp = 200, speed = 14, damage = 15, drawScale = 0.12, midWave = true },
    { id = "ember",               name = "余烬丧尸",   tier = 2, unlockLevel = 5,
      spine = "spine/Zombies/ember/ember.json",
      hp = 120, speed = 25, damage = 10, drawScale = 0.14, midWave = true },
    { id = "old_guard",           name = "老卫兵",     tier = 2, unlockLevel = 5,
      spine = "spine/Zombies/old_guard/old_guard.json",
      hp = 160, speed = 16, damage = 14, drawScale = 0.14, midWave = true },
    { id = "DroughtT2_MaleForm",  name = "旱区精壮♂",  tier = 2, unlockLevel = 6,
      spine = "spine/Zombies/DroughtT2_MaleForm/DroughtT2_MaleForm.json",
      hp = 150, speed = 20, damage = 12, drawScale = 0.14, midWave = true },
    { id = "DroughtT2_FemaleForm",name = "旱区精壮♀",  tier = 2, unlockLevel = 6,
      spine = "spine/Zombies/DroughtT2_FemaleForm/DroughtT2_FemaleForm.json",
      hp = 140, speed = 22, damage = 11, drawScale = 0.14, midWave = true },

    -- ====== Tier 3: 高级丧尸 (关卡7起) ======
    { id = "armed_female",        name = "武装女尸",   tier = 3, unlockLevel = 7,
      spine = "spine/Zombies/armed_female/armed_female.json",
      hp = 180, speed = 26, damage = 16, drawScale = 0.14, midWave = true },
    { id = "armed_famish",        name = "武装饥尸",   tier = 3, unlockLevel = 7,
      spine = "spine/Zombies/armed_famish/armed_famish.json",
      hp = 200, speed = 24, damage = 18, drawScale = 0.13, midWave = true },
    { id = "armed_boomer",        name = "武装胖子",   tier = 3, unlockLevel = 8,
      spine = "spine/Zombies/armed_boomer/armed_boomer.json",
      hp = 300, speed = 12, damage = 22, drawScale = 0.11, midWave = true },
    { id = "poison_witch",        name = "毒巫丧尸",   tier = 3, unlockLevel = 8,
      spine = "spine/Zombies/poison_witch/poison_witch.json",
      hp = 150, speed = 20, damage = 14, drawScale = 0.14, midWave = true },
    { id = "frostbite",           name = "冰霜丧尸",   tier = 3, unlockLevel = 9,
      spine = "spine/Zombies/frostbite/frostbite.json",
      hp = 170, speed = 28, damage = 15, drawScale = 0.11, midWave = true },
    { id = "DroughtT3_MaleForm",  name = "旱区重装♂",  tier = 3, unlockLevel = 9,
      spine = "spine/Zombies/DroughtT3_MaleForm/DroughtT3_MaleForm.json",
      hp = 220, speed = 18, damage = 18, drawScale = 0.14, midWave = true },
    { id = "DroughtT3_FemaleForm",name = "旱区重装♀",  tier = 3, unlockLevel = 10,
      spine = "spine/Zombies/DroughtT3_FemaleForm/DroughtT3_FemaleForm.json",
      hp = 200, speed = 22, damage = 16, drawScale = 0.14, midWave = true },
    { id = "DroughtT3_BigForm",   name = "旱区巨人",   tier = 3, unlockLevel = 10,
      spine = "spine/Zombies/DroughtT3_BigForm/DroughtT3_BigForm.json",
      hp = 350, speed = 10, damage = 25, drawScale = 0.12, midWave = true },

    -- ====== Tier 4: 精英丧尸 (关卡11起) ======
    { id = "devourer",            name = "吞噬者",     tier = 4, unlockLevel = 11,
      spine = "spine/Zombies/devourer/devourer.json",
      hp = 500, speed = 15, damage = 30, drawScale = 0.08, midWave = true },
    { id = "swarm",               name = "蜂群丧尸",   tier = 4, unlockLevel = 11,
      spine = "spine/Zombies/swarm/swarm.json",
      hp = 400, speed = 20, damage = 25, drawScale = 0.07, midWave = true },
    { id = "enrage_big",          name = "暴怒巨尸",   tier = 4, unlockLevel = 12,
      spine = "spine/Zombies/enrage_big/enrage_big.json",
      hp = 450, speed = 18, damage = 28, drawScale = 0.12, midWave = true },
    { id = "enrage_ember",        name = "暴怒余烬",   tier = 4, unlockLevel = 12,
      spine = "spine/Zombies/enrage_ember/enrage_ember.json",
      hp = 350, speed = 28, damage = 22, drawScale = 0.14, midWave = true },
    { id = "enrage_juggernaut",   name = "暴怒主宰",   tier = 4, unlockLevel = 13,
      spine = "spine/Zombies/enrage_juggernaut/enrage_juggernaut.json",
      hp = 600, speed = 12, damage = 35, drawScale = 0.07, midWave = true },
    { id = "enrage_male",         name = "暴怒雄尸",   tier = 4, unlockLevel = 13,
      spine = "spine/Zombies/enrage_male/enrage_male.json",
      hp = 380, speed = 24, damage = 24, drawScale = 0.13, midWave = true },
    { id = "celestial_soldier",   name = "天选战士",   tier = 4, unlockLevel = 14,
      spine = "spine/Zombies/celestial_soldier/celestial_soldier.json",
      hp = 420, speed = 22, damage = 26, drawScale = 0.11, midWave = true },
    { id = "celestial_researcher",name = "天选研究员", tier = 4, unlockLevel = 14,
      spine = "spine/Zombies/celestial_researcher/celestial_researcher.json",
      hp = 320, speed = 26, damage = 20, drawScale = 0.14, midWave = true },
    { id = "armed_devourer",      name = "武装吞噬",   tier = 4, unlockLevel = 15,
      spine = "spine/Zombies/armed_devourer/armed_devourer.json",
      hp = 650, speed = 14, damage = 35, drawScale = 0.08, midWave = true },
    { id = "eternal_zombie",      name = "永恒丧尸",   tier = 4, unlockLevel = 15,
      spine = "spine/Zombies/eternal_zombie/eternal_zombie.json",
      hp = 500, speed = 20, damage = 28, drawScale = 0.11, midWave = true },
    { id = "poison_armed_headless",name = "剧毒无头", tier = 4, unlockLevel = 16,
      spine = "spine/Zombies/poison_armed_headless/poison_armed_headless.json",
      hp = 400, speed = 24, damage = 26, drawScale = 0.12, midWave = true },

    -- ====== Tier 5: Boss (每5关出现) ======
    { id = "Boss_map_1",          name = "地图Boss",   tier = 5, unlockLevel = 5,
      spine = "spine/Zombies/Boss_map_1/Boss_map_1.json",
      hp = 2000, speed = 8,  damage = 50, drawScale = 0.07, midWave = false, isBoss = true },
    { id = "boss_2_the_tank",     name = "坦克Boss",   tier = 5, unlockLevel = 10,
      spine = "spine/Zombies/boss_2_the_tank/boss_2_the_tank.json",
      hp = 3000, speed = 6,  damage = 60, drawScale = 0.07, midWave = false, isBoss = true },
    { id = "boss_3_big_bad_wolf", name = "大灰狼Boss", tier = 5, unlockLevel = 15,
      spine = "spine/Zombies/boss_3_big_bad_wolf/boss_3_big_bad_wolf.json",
      hp = 4000, speed = 10, damage = 70, drawScale = 0.08, midWave = false, isBoss = true },
    { id = "boss_5_giant_corpse_pot",name = "尸锅Boss",tier = 5, unlockLevel = 20,
      spine = "spine/Zombies/boss_5_giant_corpse_pot/boss_5_giant_corpse_pot.json",
      hp = 5000, speed = 5,  damage = 80, drawScale = 0.07, midWave = false, isBoss = true },
}

-- 根据当前关卡获取可用丧尸池（排除Boss）
-- waveProgress: 0.0~1.0 当前波次进度，0=波次开始 1=波次结束
function C.GetZombiePool(stage, waveProgress)
    -- stage 决定最大解锁等级：stage1→3, stage2→6, stage3→9, stage4→12 ...
    local maxUnlock = stage * 3
    local pool = {}
    for _, zt in ipairs(C.ZOMBIE_TYPES) do
        if not zt.isBoss and zt.unlockLevel <= maxUnlock then
            -- midWave 类型在波次前30%不出现
            if zt.midWave and waveProgress < 0.3 then
                -- 跳过：新丧尸在波次前期不出现
            else
                table.insert(pool, zt)
            end
        end
    end
    return pool
end

-- 获取当前关卡的Boss（如有）
function C.GetBossForLevel(level)
    -- 每5关出一个Boss
    if level % 5 ~= 0 then return nil end
    local best = nil
    for _, zt in ipairs(C.ZOMBIE_TYPES) do
        if zt.isBoss and zt.unlockLevel <= level then
            if not best or zt.unlockLevel > best.unlockLevel then
                best = zt
            end
        end
    end
    return best
end

-- HP 随关卡递增公式
function C.GetZombieHP(baseHP, level)
    return baseHP + math.floor(level / 2) * 10
end

-- 速度随关卡微增
function C.GetZombieSpeed(baseSpeed, level)
    return baseSpeed + level * 0.5
end

------------------------------------------------------------------------
-- 升级面板钻石消耗
------------------------------------------------------------------------
C.REFRESH_DIAMOND_COST = 30      -- 刷新一次消耗钻石
C.GETALL_DIAMOND_COST = 50       -- 获取全部消耗钻石

------------------------------------------------------------------------
-- 自动采集无人机
------------------------------------------------------------------------
C.DRONE = {
    SPEED        = 180,      -- 飞行速度 px/s
    COLLECT_TIME = 0.35,     -- 采集停留时间(秒)
    SEARCH_RADIUS = 600,     -- 搜索资源半径(px)
    MAX_COUNT    = 3,        -- 最大无人机数量
    SIZE         = 36,       -- 绘制尺寸(px)
    HOVER_AMP    = 3,        -- 悬停上下浮动幅度(px)
    HOVER_FREQ   = 2,        -- 悬停频率(Hz)
}

------------------------------------------------------------------------
-- 装饰物生成
------------------------------------------------------------------------
C.DECO_INTERVAL = 2.5             -- 装饰物大幅减少(资源才是主角)
C.DECO_PER_SPAWN = 1

------------------------------------------------------------------------
-- 提交 & 升级
------------------------------------------------------------------------
C.BASE_TARGET = 2          -- 第1次所需资源
C.TARGET_BASE_STEP = 3    -- 每次基础增量
C.TARGET_ACCEL = 0.15     -- 第4次起的二次加速系数
C.GOLD_PER_SUBMIT = 3
C.GOLD_PER_LEVEL = 25
C.LEVEL_DIST_TARGET = 667    -- 每关行驶目标距离(米)，随滚动速度等比缩减(30→20)保持关卡时长不变

------------------------------------------------------------------------
-- 提交区域
------------------------------------------------------------------------
C.SUBMIT_BOX_W = 52
C.SUBMIT_BOX_H = 56

------------------------------------------------------------------------
-- 品质概率表：QUALITY_WEIGHTS[等级] = { 优质, 稀有, 史诗, 传说, 至臻 }
-- 等级越高，高品质权重越大
------------------------------------------------------------------------
C.QUALITY_NAMES = { "优质", "稀有", "史诗", "传说", "至臻" }
C.QUALITY_WEIGHTS = {
    [1]  = { 92,  5,  1,  2,  0 },  -- Lv1:  传说极低概率
    [2]  = { 80, 12,  4,  3,  1 },  -- Lv2:  传说/至臻极低概率
    [3]  = { 68, 20,  8,  3,  1 },  -- Lv3:  史诗小概率
    [4]  = { 58, 25, 12,  4,  1 },  -- Lv4:  传说微概率
    [5]  = { 47, 26, 17,  7,  3 },  -- Lv5:  至臻微概率
    [6]  = { 37, 27, 20, 11,  5 },  -- Lv6
    [7]  = { 28, 27, 24, 14,  7 },  -- Lv7
    [8]  = { 20, 26, 27, 17, 10 },  -- Lv8
    [9]  = { 13, 22, 30, 22, 13 },  -- Lv9
    [10] = {  7, 18, 30, 27, 18 },  -- Lv10+: 高品质为主
}

--- 根据等级 roll 一个品质 (1~5)
function C.RollQuality(level)
    local idx = math.min(level, 10)
    local w = C.QUALITY_WEIGHTS[idx]
    local total = 0
    for i = 1, 5 do total = total + w[i] end
    local roll = math.random() * total
    local acc = 0
    for i = 1, 5 do
        acc = acc + w[i]
        if roll <= acc then return i end
    end
    return 1
end

------------------------------------------------------------------------
-- 升级卡 (末日求生主题)
-- tiers[品质] = { desc, apply }，品质 1~5 对应 优质~至臻
------------------------------------------------------------------------
C.UPGRADES = {
    { id = "speed", name = "急行军", icon = "boot",
      tiers = {
        { desc = "移动速度+18%",  apply = function(G) G.speedMul = G.speedMul * 1.18 end },
        { desc = "移动速度+25%",  apply = function(G) G.speedMul = G.speedMul * 1.25 end },
        { desc = "移动速度+35%",  apply = function(G) G.speedMul = G.speedMul * 1.35 end },
        { desc = "移动速度+50%",  apply = function(G) G.speedMul = G.speedMul * 1.50 end },
        { desc = "移动速度+70%",  apply = function(G) G.speedMul = G.speedMul * 1.70 end },
      },
    },
    { id = "carry", name = "军用背包", icon = "bag",
      tiers = {
        { desc = "携带上限+3",  apply = function(G) G.maxCarry = G.maxCarry + 3 end },
        { desc = "携带上限+5",  apply = function(G) G.maxCarry = G.maxCarry + 5 end },
        { desc = "携带上限+7",  apply = function(G) G.maxCarry = G.maxCarry + 7 end },
        { desc = "携带上限+10", apply = function(G) G.maxCarry = G.maxCarry + 10 end },
        { desc = "携带上限+15", apply = function(G) G.maxCarry = G.maxCarry + 15 end },
      },
    },
    { id = "meleeAtk", name = "利刃强化", icon = "sword",
      tiers = {
        { desc = "近战攻击力+20%", apply = function(G) G.meleeAtkMul = (G.meleeAtkMul or 1.0) * 1.20 end },
        { desc = "近战攻击力+30%", apply = function(G) G.meleeAtkMul = (G.meleeAtkMul or 1.0) * 1.30 end },
        { desc = "近战攻击力+50%", apply = function(G) G.meleeAtkMul = (G.meleeAtkMul or 1.0) * 1.50 end },
        { desc = "近战攻击力+80%", apply = function(G) G.meleeAtkMul = (G.meleeAtkMul or 1.0) * 1.80 end },
        { desc = "近战攻击力+100%", apply = function(G) G.meleeAtkMul = (G.meleeAtkMul or 1.0) * 2.00 end },
      },
    },
    { id = "rangedAtk", name = "精准瞄具", icon = "sword",
      tiers = {
        { desc = "射击攻击力+20%", apply = function(G) G.rangedAtkMul = (G.rangedAtkMul or 1.0) * 1.20 end },
        { desc = "射击攻击力+30%", apply = function(G) G.rangedAtkMul = (G.rangedAtkMul or 1.0) * 1.30 end },
        { desc = "射击攻击力+50%", apply = function(G) G.rangedAtkMul = (G.rangedAtkMul or 1.0) * 1.50 end },
        { desc = "射击攻击力+80%", apply = function(G) G.rangedAtkMul = (G.rangedAtkMul or 1.0) * 1.80 end },
        { desc = "射击攻击力+100%", apply = function(G) G.rangedAtkMul = (G.rangedAtkMul or 1.0) * 2.00 end },
      },
    },
    { id = "atkspd", name = "疾风斩", icon = "wind",
      tiers = {
        { desc = "攻击速度+18%", apply = function(G) G.atkSpdMul = G.atkSpdMul * 1.18 end },
        { desc = "攻击速度+30%", apply = function(G) G.atkSpdMul = G.atkSpdMul * 1.30 end },
        { desc = "攻击速度+45%", apply = function(G) G.atkSpdMul = G.atkSpdMul * 1.45 end },
        { desc = "攻击速度+65%", apply = function(G) G.atkSpdMul = G.atkSpdMul * 1.65 end },
        { desc = "攻击速度+90%", apply = function(G) G.atkSpdMul = G.atkSpdMul * 1.90 end },
      },
    },
    { id = "range", name = "长臂猿", icon = "magnet",
      tiers = {
        { desc = "攻击范围+20%", apply = function(G) G.rangeMul = G.rangeMul * 1.20 end },
        { desc = "攻击范围+30%", apply = function(G) G.rangeMul = G.rangeMul * 1.30 end },
        { desc = "攻击范围+50%", apply = function(G) G.rangeMul = G.rangeMul * 1.50 end },
        { desc = "攻击范围+70%", apply = function(G) G.rangeMul = G.rangeMul * 1.70 end },
        { desc = "攻击范围+100%", apply = function(G) G.rangeMul = G.rangeMul * 2.00 end },
      },
    },

    { id = "repair", name = "应急维修", icon = "shield",
      tiers = {
        { desc = "列车回复20%HP",  apply = function(G) G.trainHP = math.min(G.trainMaxHP, G.trainHP + math.floor(G.trainMaxHP * 0.20)) end },
        { desc = "列车回复40%HP",  apply = function(G) G.trainHP = math.min(G.trainMaxHP, G.trainHP + math.floor(G.trainMaxHP * 0.40)) end },
        { desc = "列车回复60%HP",  apply = function(G) G.trainHP = math.min(G.trainMaxHP, G.trainHP + math.floor(G.trainMaxHP * 0.60)) end },
        { desc = "列车回复80%HP",  apply = function(G) G.trainHP = math.min(G.trainMaxHP, G.trainHP + math.floor(G.trainMaxHP * 0.80)) end },
        { desc = "列车回复满血",   apply = function(G) G.trainHP = G.trainMaxHP end },
      },
    },
    { id = "armor", name = "装甲强化", icon = "x2",
      tiers = {
        { desc = "列车最大HP+18",  apply = function(G) G.trainMaxHP = G.trainMaxHP + 18; G.trainHP = G.trainHP + 18 end },
        { desc = "列车最大HP+25",  apply = function(G) G.trainMaxHP = G.trainMaxHP + 25; G.trainHP = G.trainHP + 25 end },
        { desc = "列车最大HP+40",  apply = function(G) G.trainMaxHP = G.trainMaxHP + 40; G.trainHP = G.trainHP + 40 end },
        { desc = "列车最大HP+60",  apply = function(G) G.trainMaxHP = G.trainMaxHP + 60; G.trainHP = G.trainHP + 60 end },
        { desc = "列车最大HP+100", apply = function(G) G.trainMaxHP = G.trainMaxHP + 100; G.trainHP = G.trainHP + 100 end },
      },
    },
    { id = "multi", name = "双倍搜刮", icon = "fairy",
      tiers = {
        { desc = "采集双倍概率+18%", apply = function(G) G.doubleMul = G.doubleMul + 0.18 end },
        { desc = "采集双倍概率+25%", apply = function(G) G.doubleMul = G.doubleMul + 0.25 end },
        { desc = "采集双倍概率+35%", apply = function(G) G.doubleMul = G.doubleMul + 0.35 end },
        { desc = "采集双倍概率+50%", apply = function(G) G.doubleMul = G.doubleMul + 0.50 end },
        { desc = "采集双倍概率+70%", apply = function(G) G.doubleMul = G.doubleMul + 0.70 end },
      },
    },

    -- 炮塔解锁卡（不分品质，解锁就是解锁）
    { id = "turret_arrow",    name = "弓箭炮塔",   icon = "turret_arrow",    isTurret = true, turretType = "arrow",
      tiers = {{ desc = "解锁弓箭炮塔", apply = function(G) getTurret().UnlockTurret(G, "arrow") end }},
    },
    { id = "turret_minigun",  name = "机关枪塔",   icon = "turret_minigun",  isTurret = true, turretType = "minigun",
      tiers = {{ desc = "解锁机关枪炮塔", apply = function(G) getTurret().UnlockTurret(G, "minigun") end }},
    },
    { id = "turret_flame",    name = "喷火炮塔",   icon = "turret_flame",    isTurret = true, turretType = "flame",
      tiers = {{ desc = "解锁喷火炮塔", apply = function(G) getTurret().UnlockTurret(G, "flame") end }},
    },
    { id = "turret_sniper",   name = "狙击炮塔",   icon = "turret_sniper",   isTurret = true, turretType = "sniper",
      tiers = {{ desc = "解锁狙击炮塔", apply = function(G) getTurret().UnlockTurret(G, "sniper") end }},
    },
    { id = "turret_electric", name = "电能炮塔",   icon = "turret_electric", isTurret = true, turretType = "electric",
      tiers = {{ desc = "解锁电能炮塔", apply = function(G) getTurret().UnlockTurret(G, "electric") end }},
    },
    { id = "turret_rocket",   name = "火箭炮塔",   icon = "turret_rocket",   isTurret = true, turretType = "rocket",
      tiers = {{ desc = "解锁火箭炮塔", apply = function(G) getTurret().UnlockTurret(G, "rocket") end }},
    },

    -- ===================================================================
    -- 炮塔升级卡（isTurretUpgrade=true，炮塔解锁后才出现）
    -- fixedQuality: 1=优质 2=稀有 3=史诗 4=传说 5=至臻
    -- unlockLevel: 局外炮塔需达到该等级才解锁此卡
    -- ===================================================================

    -- ---------------------------------------------------------------
    -- 弓箭炮塔升级 (arrow) - maxLv=6
    -- ---------------------------------------------------------------
    { id = "arrow_dmg1", name = "硬化箭矢", icon = "turret_arrow",
      isTurretUpgrade = true, turretType = "arrow", fixedQuality = 3, unlockLevel = 1,
      tiers = {
        { desc = "弓箭伤害+60%",  apply = function(G)
            if not G.turretDmgBonus then G.turretDmgBonus = {} end
            G.turretDmgBonus["arrow"] = (G.turretDmgBonus["arrow"] or 0) + 60
          end },
      },
    },
    { id = "arrow_range1", name = "远程弓弦", icon = "turret_arrow",
      isTurretUpgrade = true, turretType = "arrow", fixedQuality = 3, unlockLevel = 2,
      tiers = {
        { desc = "弓箭射程+60%",  apply = function(G)
            if not G.turretRangeBonus then G.turretRangeBonus = {} end
            G.turretRangeBonus["arrow"] = (G.turretRangeBonus["arrow"] or 0) + 60
          end },
      },
    },
    { id = "arrow_spd1", name = "速射改装", icon = "turret_arrow",
      isTurretUpgrade = true, turretType = "arrow", fixedQuality = 3, unlockLevel = 3,
      tiers = {
        { desc = "弓箭攻速+80%",  apply = function(G)
            if not G.turretCoolBonus then G.turretCoolBonus = {} end
            G.turretCoolBonus["arrow"] = (G.turretCoolBonus["arrow"] or 0) + 80
          end },
      },
    },
    { id = "arrow_pierce", name = "贯穿箭", icon = "turret_arrow",
      isTurretUpgrade = true, turretType = "arrow", fixedQuality = 3, unlockLevel = 4,
      tiers = {
        { desc = "箭矢贯穿+3个目标",   apply = function(G) getTurret().SetUpgrade(G, "arrow", "pierce", 3) end },
      },
    },
    { id = "arrow_poison", name = "毒素箭头", icon = "turret_arrow",
      isTurretUpgrade = true, turretType = "arrow", fixedQuality = 4, unlockLevel = 5,
      tiers = {
        { desc = "箭矢命中施加4秒毒素buff",       apply = function(G) getTurret().SetUpgrade(G, "arrow", "poison", true) end },
      },
    },
    { id = "arrow_poison_plus", name = "剧毒强化", icon = "turret_arrow",
      isTurretUpgrade = true, turretType = "arrow", fixedQuality = 3, unlockLevel = 5,
      prereq = function(G) return getTurret().HasUpgrade(G, "arrow", "poison") end,
      tiers = {
        { desc = "毒素时间+2秒，毒伤+30%",     apply = function(G)
            getTurret().SetUpgrade(G, "arrow", "poison_extra", true)
          end },
      },
    },
    { id = "arrow_chain", name = "穿链弹", icon = "turret_arrow",
      isTurretUpgrade = true, turretType = "arrow", fixedQuality = 4, unlockLevel = 6,
      tiers = {
        { desc = "箭矢击中后弹射至附近1个敌人",   apply = function(G) getTurret().SetUpgrade(G, "arrow", "chain", 1) end },
      },
    },
    { id = "arrow_chain_plus", name = "连锁强化", icon = "turret_arrow",
      isTurretUpgrade = true, turretType = "arrow", fixedQuality = 3, unlockLevel = 6,
      prereq = function(G) return getTurret().HasUpgrade(G, "arrow", "chain") end,
      tiers = {
        { desc = "弹射链增加至2次",                apply = function(G) getTurret().SetUpgrade(G, "arrow", "chain", 2) end },
      },
    },

    -- ---------------------------------------------------------------
    -- 机关枪升级 (minigun) - maxLv=5
    -- ---------------------------------------------------------------
    { id = "minigun_dmg1", name = "穿甲弹芯", icon = "turret_minigun",
      isTurretUpgrade = true, turretType = "minigun", fixedQuality = 3, unlockLevel = 1,
      tiers = {
        { desc = "机枪伤害+55%",  apply = function(G)
            if not G.turretDmgBonus then G.turretDmgBonus = {} end
            G.turretDmgBonus["minigun"] = (G.turretDmgBonus["minigun"] or 0) + 55
          end },
      },
    },
    { id = "minigun_firerate", name = "超频枪管", icon = "turret_minigun",
      isTurretUpgrade = true, turretType = "minigun", fixedQuality = 3, unlockLevel = 2,
      tiers = {
        { desc = "机枪攻速+90%",  apply = function(G)
            if not G.turretCoolBonus then G.turretCoolBonus = {} end
            G.turretCoolBonus["minigun"] = (G.turretCoolBonus["minigun"] or 0) + 90
          end },
      },
    },
    { id = "minigun_range1", name = "长管改造", icon = "turret_minigun",
      isTurretUpgrade = true, turretType = "minigun", fixedQuality = 2, unlockLevel = 3,
      tiers = {
        { desc = "机枪射程+50%",  apply = function(G)
            if not G.turretRangeBonus then G.turretRangeBonus = {} end
            G.turretRangeBonus["minigun"] = (G.turretRangeBonus["minigun"] or 0) + 50
          end },
      },
    },
    { id = "minigun_ricochet", name = "跳弹装甲", icon = "turret_minigun",
      isTurretUpgrade = true, turretType = "minigun", fixedQuality = 2, unlockLevel = 4,
      tiers = {
        { desc = "机枪子弹反弹2次",            apply = function(G) getTurret().SetUpgrade(G, "minigun", "ricochet", 2) end },
      },
    },
    { id = "minigun_incendiary", name = "燃烧弹头", icon = "turret_minigun",
      isTurretUpgrade = true, turretType = "minigun", fixedQuality = 4, unlockLevel = 5,
      tiers = {
        { desc = "命中附加2.5秒燃烧buff",   apply = function(G) getTurret().SetUpgrade(G, "minigun", "incendiary", true) end },
      },
    },
    { id = "minigun_incendiary_plus", name = "火药强化", icon = "turret_minigun",
      isTurretUpgrade = true, turretType = "minigun", fixedQuality = 3, unlockLevel = 5,
      prereq = function(G) return getTurret().HasUpgrade(G, "minigun", "incendiary") end,
      tiers = {
        { desc = "燃烧时间+1.5s，燃烧伤害+40%",    apply = function(G)
            getTurret().SetUpgrade(G, "minigun", "incendiary_plus", true)
          end },
      },
    },

    -- ---------------------------------------------------------------
    -- 喷火炮塔升级 (flame) - maxLv=5
    -- ---------------------------------------------------------------
    { id = "flame_dmg1", name = "高温燃料", icon = "turret_flame",
      isTurretUpgrade = true, turretType = "flame", fixedQuality = 3, unlockLevel = 1,
      tiers = {
        { desc = "喷火伤害+65%",  apply = function(G)
            if not G.turretDmgBonus then G.turretDmgBonus = {} end
            G.turretDmgBonus["flame"] = (G.turretDmgBonus["flame"] or 0) + 65
          end },
      },
    },
    { id = "flame_range1", name = "长焰喷嘴", icon = "turret_flame",
      isTurretUpgrade = true, turretType = "flame", fixedQuality = 2, unlockLevel = 2,
      tiers = {
        { desc = "喷火射程+50%",  apply = function(G)
            if not G.turretRangeBonus then G.turretRangeBonus = {} end
            G.turretRangeBonus["flame"] = (G.turretRangeBonus["flame"] or 0) + 50
          end },
      },
    },
    { id = "flame_spd1", name = "快速点火", icon = "turret_flame",
      isTurretUpgrade = true, turretType = "flame", fixedQuality = 2, unlockLevel = 3,
      tiers = {
        { desc = "喷火攻速+55%",  apply = function(G)
            if not G.turretCoolBonus then G.turretCoolBonus = {} end
            G.turretCoolBonus["flame"] = (G.turretCoolBonus["flame"] or 0) + 55
          end },
      },
    },
    { id = "flame_ricochet", name = "跳弹装甲", icon = "turret_flame",
      isTurretUpgrade = true, turretType = "flame", fixedQuality = 2, unlockLevel = 4,
      tiers = {
        { desc = "火焰弹反弹2次至另一敌人",  apply = function(G) getTurret().SetUpgrade(G, "flame", "ricochet", 2) end },
      },
    },
    { id = "flame_rotating", name = "旋转火舌", icon = "turret_flame",
      isTurretUpgrade = true, turretType = "flame", fixedQuality = 5, unlockLevel = 5,
      tiers = {
        { desc = "喷火方向持续旋转扫射，覆盖更大范围",   apply = function(G) getTurret().SetUpgrade(G, "flame", "rotating", true) end },
      },
    },
    { id = "flame_rotating_plus", name = "旋转强化", icon = "turret_flame",
      isTurretUpgrade = true, turretType = "flame", fixedQuality = 3, unlockLevel = 5,
      prereq = function(G) return getTurret().HasUpgrade(G, "flame", "rotating") end,
      tiers = {
        { desc = "转速+80%，火舌宽度+30%",            apply = function(G)
            getTurret().SetUpgrade(G, "flame", "rotating_plus", true)
          end },
      },
    },

    -- ---------------------------------------------------------------
    -- 狙击炮塔升级 (sniper) - maxLv=5
    -- ---------------------------------------------------------------
    { id = "sniper_dmg1", name = "穿甲狙击弹", icon = "turret_sniper",
      isTurretUpgrade = true, turretType = "sniper", fixedQuality = 3, unlockLevel = 1,
      tiers = {
        { desc = "狙击伤害+80%",  apply = function(G)
            if not G.turretDmgBonus then G.turretDmgBonus = {} end
            G.turretDmgBonus["sniper"] = (G.turretDmgBonus["sniper"] or 0) + 80
          end },
      },
    },
    { id = "sniper_range1", name = "长距镜", icon = "turret_sniper",
      isTurretUpgrade = true, turretType = "sniper", fixedQuality = 3, unlockLevel = 2,
      tiers = {
        { desc = "狙击射程+90%",  apply = function(G)
            if not G.turretRangeBonus then G.turretRangeBonus = {} end
            G.turretRangeBonus["sniper"] = (G.turretRangeBonus["sniper"] or 0) + 90
          end },
      },
    },
    { id = "sniper_reload", name = "快拉枪栓", icon = "turret_sniper",
      isTurretUpgrade = true, turretType = "sniper", fixedQuality = 2, unlockLevel = 3,
      tiers = {
        { desc = "狙击装填速度+70%",  apply = function(G)
            if not G.turretCoolBonus then G.turretCoolBonus = {} end
            G.turretCoolBonus["sniper"] = (G.turretCoolBonus["sniper"] or 0) + 70
          end },
      },
    },
    { id = "sniper_crit", name = "要害瞄准", icon = "turret_sniper",
      isTurretUpgrade = true, turretType = "sniper", fixedQuality = 3, unlockLevel = 4,
      tiers = {
        { desc = "暴击概率50%+暴击倍率×2.5",  apply = function(G)
            getTurret().SetUpgrade(G, "sniper", "crit", 50)
            getTurret().SetUpgrade(G, "sniper", "crit_plus", true)
          end },
      },
    },
    { id = "sniper_freeze", name = "冰封子弹", icon = "turret_sniper",
      isTurretUpgrade = true, turretType = "sniper", fixedQuality = 5, unlockLevel = 5,
      tiers = {
        { desc = "狙击命中敌人眩晕1.8秒",    apply = function(G) getTurret().SetUpgrade(G, "sniper", "freeze", true) end },
      },
    },
    { id = "sniper_freeze_plus", name = "冰封强化", icon = "turret_sniper",
      isTurretUpgrade = true, turretType = "sniper", fixedQuality = 3, unlockLevel = 5,
      prereq = function(G) return getTurret().HasUpgrade(G, "sniper", "freeze") end,
      tiers = {
        { desc = "眩晕+1s，命中回复列车HP",  apply = function(G)
            getTurret().SetUpgrade(G, "sniper", "freeze_plus", true)
          end },
      },
    },

    -- ---------------------------------------------------------------
    -- 电能炮塔升级 (electric) - maxLv=4
    -- ---------------------------------------------------------------
    { id = "electric_dmg1", name = "高压电容", icon = "turret_electric",
      isTurretUpgrade = true, turretType = "electric", fixedQuality = 3, unlockLevel = 1,
      tiers = {
        { desc = "电能伤害+70%",  apply = function(G)
            if not G.turretDmgBonus then G.turretDmgBonus = {} end
            G.turretDmgBonus["electric"] = (G.turretDmgBonus["electric"] or 0) + 70
          end },
      },
    },
    { id = "electric_spd1", name = "急放电", icon = "turret_electric",
      isTurretUpgrade = true, turretType = "electric", fixedQuality = 3, unlockLevel = 2,
      tiers = {
        { desc = "电能攻速+85%",  apply = function(G)
            if not G.turretCoolBonus then G.turretCoolBonus = {} end
            G.turretCoolBonus["electric"] = (G.turretCoolBonus["electric"] or 0) + 85
          end },
      },
    },
    { id = "electric_range1", name = "导电延伸", icon = "turret_electric",
      isTurretUpgrade = true, turretType = "electric", fixedQuality = 2, unlockLevel = 3,
      tiers = {
        { desc = "电能射程+55%",  apply = function(G)
            if not G.turretRangeBonus then G.turretRangeBonus = {} end
            G.turretRangeBonus["electric"] = (G.turretRangeBonus["electric"] or 0) + 55
          end },
      },
    },
    { id = "electric_chain", name = "链式放电", icon = "turret_electric",
      isTurretUpgrade = true, turretType = "electric", fixedQuality = 3, unlockLevel = 4,
      tiers = {
        { desc = "电弧弹射至附近+1个目标",  apply = function(G)
            getTurret().SetUpgrade(G, "electric", "chain", 1)
          end },
      },
    },
    { id = "electric_chain_plus", name = "链式强化", icon = "turret_electric",
      isTurretUpgrade = true, turretType = "electric", fixedQuality = 2, unlockLevel = 4,
      prereq = function(G) return getTurret().HasUpgrade(G, "electric", "chain") end,
      tiers = {
        { desc = "弹射链+1目标",               apply = function(G)
            local v = getTurret().GetUpgradeVal(G, "electric", "chain")
            getTurret().SetUpgrade(G, "electric", "chain", (v or 1) + 1)
          end },
      },
    },

    -- ---------------------------------------------------------------
    -- 火箭炮塔升级 (rocket) - maxLv=4
    -- ---------------------------------------------------------------
    { id = "rocket_dmg1", name = "重型弹头", icon = "turret_rocket",
      isTurretUpgrade = true, turretType = "rocket", fixedQuality = 3, unlockLevel = 1,
      tiers = {
        { desc = "火箭伤害+80%",  apply = function(G)
            if not G.turretDmgBonus then G.turretDmgBonus = {} end
            G.turretDmgBonus["rocket"] = (G.turretDmgBonus["rocket"] or 0) + 80
          end },
      },
    },
    { id = "rocket_aoe", name = "扩爆装药", icon = "turret_rocket",
      isTurretUpgrade = true, turretType = "rocket", fixedQuality = 3, unlockLevel = 2,
      tiers = {
        { desc = "火箭爆炸范围+85%",  apply = function(G)
            if not G.turretAoeBonus then G.turretAoeBonus = {} end
            G.turretAoeBonus["rocket"] = (G.turretAoeBonus["rocket"] or 0) + 85
          end },
      },
    },
    { id = "rocket_reload", name = "快速装弹", icon = "turret_rocket",
      isTurretUpgrade = true, turretType = "rocket", fixedQuality = 2, unlockLevel = 3,
      tiers = {
        { desc = "火箭装填速度+65%",  apply = function(G)
            if not G.turretCoolBonus then G.turretCoolBonus = {} end
            G.turretCoolBonus["rocket"] = (G.turretCoolBonus["rocket"] or 0) + 65
          end },
      },
    },
    { id = "rocket_volley5", name = "五连齐射", icon = "turret_rocket",
      isTurretUpgrade = true, turretType = "rocket", fixedQuality = 5, unlockLevel = 4,
      tiers = {
        { desc = "同时发射5枚散布火箭",        apply = function(G) getTurret().SetUpgrade(G, "rocket", "volley5", true) end },
      },
    },
    { id = "rocket_volley5_plus", name = "齐射强化", icon = "turret_rocket",
      isTurretUpgrade = true, turretType = "rocket", fixedQuality = 3, unlockLevel = 4,
      prereq = function(G) return getTurret().HasUpgrade(G, "rocket", "volley5") end,
      tiers = {
        { desc = "5连齐射，每枚伤害+25%",               apply = function(G)
            getTurret().SetUpgrade(G, "rocket", "volley5_plus", true)
          end },
      },
    },

    -- 无人机解锁卡（不分品质）
    { id = "drone", name = "采集无人机", icon = "drone", isDrone = true,
      tiers = {{ desc = "采集无人机+1", apply = function(G) getDrone().UnlockDrone(G) end }},
    },
}

------------------------------------------------------------------------
-- 颜色主题 (雪国末日)
------------------------------------------------------------------------
C.CLR = {
    -- 雪地 (灰暗冻土，被灰烬污染的雪)
    snow1     = {155, 160, 168},       -- 脏灰雪
    snow2     = {130, 138, 148},       -- 深灰雪纹
    snow3     = {170, 175, 182},       -- 浅灰
    snow_dark = {105, 112, 125},       -- 阴影区

    -- 道路 (冻泥碎石，血迹混杂)
    path       = {105, 95, 82},        -- 暖灰褐冻土
    path_light = {120, 110, 95},       -- 碎石亮面
    path_dark  = {75, 68, 58},         -- 泥坑暗部
    path_edge  = {130, 132, 138},      -- 路缘过渡

    -- 列车 (锈蚀铁甲，暗铁+暗红)
    train_body    = {52, 55, 50},      -- 暗铁灰车身
    train_dark    = {35, 38, 32},      -- 深暗面
    train_light   = {72, 78, 68},      -- 微弱高光
    train_roof    = {40, 42, 38},      -- 车顶
    train_metal   = {65, 68, 62},      -- 金属件
    train_window  = {75, 105, 130},    -- 脏窗玻璃
    train_window2 = {55, 80, 105},     -- 深色窗
    train_stripe  = {140, 35, 25},     -- 暗血红装饰
    train_stripe2 = {110, 25, 18},     -- 深红锈
    train_brass   = {145, 120, 55},    -- 氧化铜
    train_brass2  = {170, 145, 70},    -- 铜亮面
    train_brass3  = {110, 90, 40},     -- 铜暗面
    train_smoke   = {38, 35, 30},      -- 烟囱黑
    train_smoke2  = {25, 22, 18},      -- 烟囱暗
    train_rivet   = {80, 85, 75},      -- 锈铆钉
    train_frame   = {30, 32, 28},      -- 暗轮廓
    train_plate   = {120, 105, 55},    -- 锈铭牌
    train_cab_bg  = {45, 48, 42},      -- 驾驶室
    train_pipe    = {95, 90, 80},      -- 锈管道

    -- 铁轨 (锈蚀)
    rail_color    = {75, 78, 85},      -- 暗铁轨
    rail_light    = {100, 105, 115},   -- 磨亮面
    sleeper_color = {70, 60, 42},      -- 腐朽枕木
    sleeper_dark  = {48, 40, 28},      -- 枕木暗面
    ballast_color = {80, 75, 65},      -- 暗碎石

    -- 提交方块
    submit_bg     = {55, 58, 65, 220},
    submit_border = {85, 90, 100},
    submit_full   = {50, 130, 80},     -- 暗绿

    -- HUD (更暗更沉)
    hud_bg     = {18, 20, 28, 240},
    hud_border = {40, 45, 58},
    hud_text   = {175, 180, 190},

    -- 枯树 (黑化腐烂)
    trunk       = {55, 45, 35},        -- 黑褐树干
    trunk_dark  = {35, 28, 20},        -- 腐烂暗部
    tree_snow   = {140, 148, 160},     -- 灰雪
    tree_bare   = {65, 52, 40},        -- 枯枝
    tree_dark   = {45, 38, 28},        -- 暗枝

    -- 雪堆/残骸 (污雪+废墟)
    snowdrift1 = {148, 155, 165},      -- 脏雪堆
    snowdrift2 = {120, 128, 140},      -- 深灰雪
    ruin_color = {68, 62, 55},         -- 废墟残骸

    -- 资源 (暗沉写实)
    wood_color  = {110, 78, 40},       -- 暗木色
    stone_color = {95, 95, 105},       -- 暗岩灰
    ore_color   = {65, 120, 170},      -- 深蓝矿脉
    bush_color  = {60, 100, 50},       -- 深绿灌木
    pebble_color = {130, 125, 115},    -- 浅灰碎石
    gold_color  = {200, 165, 40},      -- 暗金

    -- 丧尸 (腐烂发绿，更恐怖)
    zombie_skin  = {85, 110, 72},      -- 腐肉绿
    zombie_dark  = {50, 65, 38},       -- 深腐色
    zombie_eye   = {200, 35, 20},      -- 血红眼
    zombie_cloth = {55, 48, 42},       -- 破烂深色

    -- 玩家 (脏旧生存者)
    player_coat  = {125, 55, 35},      -- 暗红破旧大衣
    player_skin  = {185, 155, 130},    -- 偏暗肤色
    player_pants = {48, 50, 58},       -- 深灰裤
    player_boot  = {38, 35, 28},       -- 泥靴
    player_hat   = {105, 42, 28},      -- 暗红帽
    player_scarf = {145, 125, 40},     -- 脏黄围巾

    -- 文字
    text_white = {220, 225, 230},      -- 偏灰白
    text_dark  = {15, 18, 25},
    text_dim   = {100, 108, 120},
    text_red   = {190, 50, 35},        -- 暗血红

    -- 卡片
    card_bg     = {28, 32, 42},
    card_border = {55, 60, 75},
    card_glow   = {70, 140, 200},
}

return C
