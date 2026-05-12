-- Game/Config.lua - 雪国列车：末日求生 资源收集配置
local C = {}

-- 延迟加载 Turret 模块（避免循环依赖，且只 require 一次）
local _Turret
local function getTurret()
    if not _Turret then _Turret = require("Game.Turret") end
    return _Turret
end

C.TITLE = "雪国列车"

------------------------------------------------------------------------
-- 滚动 & 世界
------------------------------------------------------------------------
C.BASE_SCROLL_SPEED = 30         -- 基础滚动速度 px/s (放缓节奏)
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
C.PLAYER_SPEED = 185
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
-- 丧尸 (只攻击列车)
------------------------------------------------------------------------
C.ZOMBIE_SPAWN_INTERVAL = 4.0    -- 基础丧尸生成间隔(秒)
C.ZOMBIE_SPAWN_INTERVAL_MIN = 1.0 -- 最小生成间隔(秒)
C.ZOMBIE_SPAWN_INTERVAL_REDUCE = 0.3 -- 每级减少间隔(秒)
C.ZOMBIE_SPEED = 30              -- 向列车移动速度 px/s (慢慢逼近)
C.ZOMBIE_SPEED_PER_LEVEL = 1.5   -- 每级加速 (更平缓)
C.CRAWLER_SPEED = 60             -- 爬行僵尸速度 px/s (快速)
C.CRAWLER_HP_BASE = 50           -- 爬行僵尸基础血量 (脆皮)
C.CRAWLER_SPAWN_LEVEL = 3        -- 爬行僵尸最低出现关卡
C.CRAWLER_CHANCE = 0.25          -- 爬行僵尸生成概率 (25%)
C.ZOMBIE_SIZE = 20               -- 碰撞半径
C.ZOMBIE_HP = 3                  -- 丧尸生命值
C.ZOMBIE_DAMAGE = 8              -- 对列车伤害
C.ZOMBIE_ATK_INTERVAL = 1.2      -- 攻击列车间隔
C.ZOMBIE_MAX_BASE = 8            -- 基础最大丧尸数
C.ZOMBIE_MAX_PER_LEVEL = 2       -- 每级增加最大丧尸数
C.ZOMBIE_MAX_CAP = 30            -- 绝对上限

------------------------------------------------------------------------
-- 装饰物生成
------------------------------------------------------------------------
C.DECO_INTERVAL = 2.5             -- 装饰物大幅减少(资源才是主角)
C.DECO_PER_SPAWN = 1

------------------------------------------------------------------------
-- 提交 & 升级
------------------------------------------------------------------------
C.BASE_TARGET = 13
C.TARGET_GROWTH = 1.35
C.GOLD_PER_SUBMIT = 3
C.GOLD_PER_LEVEL = 25
C.LEVEL_DIST_TARGET = 1000   -- 每关行驶目标距离(米)

------------------------------------------------------------------------
-- 提交区域
------------------------------------------------------------------------
C.SUBMIT_BOX_W = 44
C.SUBMIT_BOX_H = 44

------------------------------------------------------------------------
-- 升级卡 (末日求生主题)
------------------------------------------------------------------------
C.UPGRADES = {
    { id = "speed",    name = "急行军",   desc = "移动速度+25%",       icon = "boot",   apply = function(G) G.speedMul = G.speedMul * 1.25 end },
    { id = "carry",    name = "军用背包", desc = "携带上限+5",         icon = "bag",    apply = function(G) G.maxCarry = G.maxCarry + 5 end },
    { id = "atk",      name = "利刃强化", desc = "攻击力+1",           icon = "sword",  apply = function(G) G.atkBonus = G.atkBonus + 1 end },
    { id = "atkspd",   name = "疾风斩",   desc = "攻击速度+30%",       icon = "wind",   apply = function(G) G.atkSpdMul = G.atkSpdMul * 1.3 end },
    { id = "range",    name = "长臂猿",   desc = "攻击范围+35%",       icon = "magnet", apply = function(G) G.rangeMul = G.rangeMul * 1.35 end },
    { id = "gold",     name = "物资交换", desc = "提交金币+50%",       icon = "coin",   apply = function(G) G.goldMul = G.goldMul * 1.5 end },
    { id = "spawn",    name = "丰收区域", desc = "资源生成+30%",       icon = "star",   apply = function(G) G.spawnMul = G.spawnMul * 1.3 end },
    { id = "ore_luck", name = "探矿直觉", desc = "矿石出现率翻倍",    icon = "gem",    apply = function(G) G.oreLuckMul = G.oreLuckMul * 2.0 end },
    { id = "slow",     name = "制动系统", desc = "列车速度-15%",       icon = "gear",   apply = function(G) G.scrollSpeedMul = G.scrollSpeedMul * 0.85 end },
    { id = "repair",   name = "应急维修", desc = "列车回复30HP",       icon = "shield", apply = function(G) G.trainHP = math.min(G.trainMaxHP, G.trainHP + 30) end },
    { id = "armor",    name = "装甲强化", desc = "列车最大HP+25",      icon = "x2",     apply = function(G) G.trainMaxHP = G.trainMaxHP + 25; G.trainHP = G.trainHP + 25 end },
    { id = "multi",    name = "双倍搜刮", desc = "采集掉落概率×2",     icon = "fairy",  apply = function(G) G.doubleMul = G.doubleMul + 0.25 end },

    -- 炮塔解锁卡（通过肉鸽升级获得）
    { id = "turret_arrow",    name = "弓箭炮塔",   desc = "解锁弓箭炮塔",       icon = "turret_arrow",    isTurret = true, turretType = "arrow",
      apply = function(G) getTurret().UnlockTurret(G, "arrow") end },
    { id = "turret_minigun",  name = "机关枪塔",   desc = "解锁机关枪炮塔",     icon = "turret_minigun",  isTurret = true, turretType = "minigun",
      apply = function(G) getTurret().UnlockTurret(G, "minigun") end },
    { id = "turret_flame",    name = "喷火炮塔",   desc = "解锁喷火炮塔",       icon = "turret_flame",    isTurret = true, turretType = "flame",
      apply = function(G) getTurret().UnlockTurret(G, "flame") end },
    { id = "turret_sniper",   name = "狙击炮塔",   desc = "解锁狙击炮塔",       icon = "turret_sniper",   isTurret = true, turretType = "sniper",
      apply = function(G) getTurret().UnlockTurret(G, "sniper") end },
    { id = "turret_electric", name = "电能炮塔",   desc = "解锁电能炮塔",       icon = "turret_electric", isTurret = true, turretType = "electric",
      apply = function(G) getTurret().UnlockTurret(G, "electric") end },
    { id = "turret_rocket",   name = "火箭炮塔",   desc = "解锁火箭炮塔",       icon = "turret_rocket",   isTurret = true, turretType = "rocket",
      apply = function(G) getTurret().UnlockTurret(G, "rocket") end },
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
    path       = {85, 78, 68},         -- 暗褐冻土
    path_light = {100, 92, 80},        -- 碎石亮面
    path_dark  = {60, 55, 45},         -- 泥坑暗部
    path_edge  = {120, 125, 135},      -- 路缘过渡

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
