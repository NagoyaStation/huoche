-- Meta/MetaData.lua - 局外系统数据定义
-- 装备、天赋、关卡、商城等所有数据配置

local MD = {}

------------------------------------------------------------------------
-- 颜色主题（局外 UI 专用，与游戏内暗色调保持统一）
------------------------------------------------------------------------
MD.CLR = {
    -- 主背景
    bg_dark    = {18, 20, 28, 255},       -- 最深背景
    bg_panel   = {28, 32, 42, 255},       -- 面板背景
    bg_card    = {38, 42, 55, 255},       -- 卡片背景
    bg_input   = {22, 25, 35, 255},       -- 输入框背景

    -- 顶栏/底栏
    bar_bg     = {14, 16, 22, 245},       -- 顶/底栏背景
    bar_border = {45, 50, 65, 255},       -- 栏边框

    -- Tab 栏
    tab_active   = {70, 140, 200, 255},   -- 激活 Tab 颜色
    tab_inactive = {100, 108, 120, 255},  -- 未激活 Tab
    tab_bg       = {22, 25, 35, 240},     -- Tab 背景

    -- 按钮
    btn_primary   = {55, 130, 85, 255},   -- 主按钮（暗绿）
    btn_secondary = {50, 55, 70, 255},    -- 次按钮
    btn_danger    = {160, 45, 35, 255},   -- 危险按钮
    btn_gold      = {180, 145, 40, 255},  -- 金色按钮

    -- 品质颜色
    quality_common   = {160, 165, 175, 255},  -- 白
    quality_uncommon = {65, 170, 80, 255},    -- 绿
    quality_rare     = {55, 120, 210, 255},   -- 蓝
    quality_epic     = {150, 60, 200, 255},   -- 紫
    quality_legend   = {220, 165, 30, 255},   -- 橙

    -- 文字
    text_white  = {220, 225, 230, 255},
    text_gray   = {130, 138, 150, 255},
    text_dim    = {80, 85, 95, 255},
    text_gold   = {220, 185, 50, 255},
    text_green  = {65, 180, 90, 255},
    text_red    = {200, 55, 40, 255},

    -- 分割线
    divider = {40, 45, 58, 255},
}

------------------------------------------------------------------------
-- Tab 定义
------------------------------------------------------------------------
MD.TABS = {
    { id = "shop",   name = "商城", icon = "image/meta_tab_shop_20260421063707.png" },
    { id = "equip",  name = "装备", icon = "image/meta_tab_equip_20260421063710.png" },
    { id = "battle", name = "战斗", icon = "image/meta_tab_battle_20260421063808.png" },
    { id = "train",  name = "列车", icon = "image/meta_tab_train_20260421063842.png" },
    { id = "talent", name = "天赋", icon = "image/meta_tab_talent_20260421063732.png" },
}

------------------------------------------------------------------------
-- 货币图标
------------------------------------------------------------------------
MD.CURRENCY_ICONS = {
    gold    = "image/hud_gold_coin.png",
    diamond = "image/meta_icon_diamond_20260421063718.png",
    wood    = "image/meta_icon_wood_20260421063709.png",
    stone   = "image/meta_icon_stone_20260421063705.png",
}

------------------------------------------------------------------------
-- 装备系统
------------------------------------------------------------------------
MD.EQUIP_SLOTS = {
    { id = "weapon",    name = "武器",  icon = "image/equip_weapon_sword_20260421064504.png" },
    { id = "accessory", name = "饰品",  icon = "image/equip_accessory_necklace_20260421064510.png" },
    { id = "ring",      name = "戒指",  icon = "image/equip_ring_20260421064511.png" },
    { id = "hat",       name = "帽子",  icon = "image/equip_hat_20260421064515.png" },
    { id = "clothes",   name = "衣服",  icon = "image/equip_clothes_20260421064729.png" },
    { id = "boots",     name = "鞋子",  icon = "image/equip_boots_20260421064742.png" },
}

-- 装备品质
MD.QUALITY = {
    { id = "common",   name = "普通", color = MD.CLR.quality_common },
    { id = "uncommon", name = "优秀", color = MD.CLR.quality_uncommon },
    { id = "rare",     name = "稀有", color = MD.CLR.quality_rare },
    { id = "epic",     name = "史诗", color = MD.CLR.quality_epic },
    { id = "legend",   name = "传说", color = MD.CLR.quality_legend },
}

-- 装备数据库（示例装备）
MD.EQUIP_DB = {
    -- 武器
    { id = "sword_iron",   slot = "weapon",    name = "铁剑",     quality = 1, atk = 5,  icon = "image/equip_weapon_sword_20260421064504.png" },
    { id = "axe_war",      slot = "weapon",    name = "战斧",     quality = 2, atk = 8,  icon = "image/equip_weapon_axe_20260421064553.png" },
    -- 饰品
    { id = "necklace_1",   slot = "accessory", name = "护身符",   quality = 1, def = 3,  icon = "image/equip_accessory_necklace_20260421064510.png" },
    -- 戒指
    { id = "ring_silver",  slot = "ring",      name = "银戒指",   quality = 2, atkSpd = 0.1, icon = "image/equip_ring_20260421064511.png" },
    -- 帽子
    { id = "hat_winter",   slot = "hat",       name = "冬帽",     quality = 1, hp = 10,  icon = "image/equip_hat_20260421064515.png" },
    -- 衣服
    { id = "coat_warm",    slot = "clothes",   name = "棉衣",     quality = 1, def = 5,  icon = "image/equip_clothes_20260421064729.png" },
    -- 鞋子
    { id = "boots_army",   slot = "boots",     name = "军靴",     quality = 1, speed = 0.1, icon = "image/equip_boots_20260421064742.png" },
}

------------------------------------------------------------------------
-- 关卡系统
------------------------------------------------------------------------
MD.LEVELS = {
    { id = 1,  name = "荒原前哨", waves = 5,  reward_gold = 50,  chest = "bronze", unlocked = true },
    { id = 2,  name = "冰封隧道", waves = 7,  reward_gold = 80,  chest = "bronze", unlocked = false },
    { id = 3,  name = "暴风雪谷", waves = 8,  reward_gold = 100, chest = "silver", unlocked = false },
    { id = 4,  name = "死寂车站", waves = 10, reward_gold = 150, chest = "silver", unlocked = false },
    { id = 5,  name = "钢铁废墟", waves = 12, reward_gold = 200, chest = "gold",   unlocked = false },
    { id = 6,  name = "末日核心", waves = 15, reward_gold = 300, chest = "gold",   unlocked = false },
}

MD.CHEST_ICONS = {
    bronze = "image/chest_bronze_20260421064750.png",
    silver = "image/chest_silver_20260421064733.png",
    gold   = "image/chest_gold_20260421064736.png",
}

------------------------------------------------------------------------
-- 天赋系统（阶梯式，每个天赋可升多级）
------------------------------------------------------------------------
MD.TALENTS = {
    { id = "hp",     name = "生命强化", desc = "列车最大HP+10",     maxLv = 10, costBase = 50,  costGrow = 1.3, icon = "image/talent_hp_20260421065056.png" },
    { id = "atk",    name = "力量提升", desc = "攻击力+1",          maxLv = 10, costBase = 60,  costGrow = 1.3, icon = "image/talent_atk_20260421065251.png" },
    { id = "atkspd", name = "疾速打击", desc = "攻击速度+5%",       maxLv = 8,  costBase = 80,  costGrow = 1.4, icon = "image/talent_atkspd_20260421065058.png" },
    { id = "def",    name = "铁壁防御", desc = "减少列车受伤-5%",   maxLv = 8,  costBase = 70,  costGrow = 1.3, icon = "image/talent_def_20260421065053.png" },
    { id = "speed",  name = "轻身术",   desc = "移动速度+8%",       maxLv = 6,  costBase = 60,  costGrow = 1.4, icon = "image/talent_speed_20260421065223.png" },
    { id = "gold",   name = "聚财术",   desc = "金币收益+10%",      maxLv = 8,  costBase = 100, costGrow = 1.5, icon = "image/talent_gold_20260421065059.png" },
    { id = "carry",  name = "负重训练", desc = "携带上限+2",         maxLv = 5,  costBase = 80,  costGrow = 1.4, icon = "image/talent_carry_20260421065057.png" },
    { id = "unlock", name = "求生本能", desc = "解锁新技能",        maxLv = 3,  costBase = 200, costGrow = 2.0, icon = "image/talent_unlock_20260421065109.png" },
}

------------------------------------------------------------------------
-- 商城系统
------------------------------------------------------------------------
MD.SHOP_DAILY = {
    { id = "daily_gold",    name = "金币礼包",  desc = "获得500金币",          price = 50,  currency = "diamond", icon = "image/hud_gold_coin.png" },
    { id = "daily_wood",    name = "木材补给",  desc = "获得20木材",           price = 30,  currency = "diamond", icon = "image/meta_icon_wood_20260421063709.png" },
    { id = "daily_stone",   name = "石材补给",  desc = "获得15石材",           price = 30,  currency = "diamond", icon = "image/meta_icon_stone_20260421063705.png" },
    { id = "daily_chest",   name = "银色宝箱",  desc = "随机稀有装备×1",       price = 100, currency = "diamond", icon = "image/chest_silver_20260421064733.png" },
}

MD.SHOP_GACHA = {
    name = "末日抽卡",
    desc = "消耗钻石抽取装备碎片",
    cost_single = 100,
    cost_ten = 900,
}

------------------------------------------------------------------------
-- 炮塔升级数据（局外用碎片升级）
------------------------------------------------------------------------
MD.TURRET_UPGRADES = {
    { id = "arrow",    name = "弓箭炮塔", maxLv = 5, fragBase = 5,  fragGrow = 1.5, icon = "image/turret_arrow_v3_20260420035036.png" },
    { id = "minigun",  name = "机关枪塔", maxLv = 5, fragBase = 8,  fragGrow = 1.5, icon = "image/turret_minigun_v3_20260420035022.png" },
    { id = "flame",    name = "喷火炮塔", maxLv = 5, fragBase = 8,  fragGrow = 1.5, icon = "image/edited_turret_flame_nofire_20260423065123.png" },
    { id = "sniper",   name = "狙击炮塔", maxLv = 5, fragBase = 10, fragGrow = 1.6, icon = "image/turret_sniper_v3_20260420035021.png" },
    { id = "electric", name = "电能炮塔", maxLv = 5, fragBase = 10, fragGrow = 1.6, icon = "image/turret_electric_v10_20260423040517.png" },
    { id = "rocket",   name = "火箭炮塔", maxLv = 5, fragBase = 12, fragGrow = 1.8, icon = "image/turret_rocket_v3_20260420035019.png" },
}

------------------------------------------------------------------------
-- 玩家存档数据初始值
------------------------------------------------------------------------
function MD.NewSaveData()
    return {
        -- 货币
        gold = 500,
        diamond = 100,
        wood = 30,
        stone = 20,

        -- 关卡进度
        maxLevel = 1,       -- 已解锁最高关卡
        levelStars = {},    -- 每关星数 {[1]=3, [2]=2, ...}

        -- 装备
        equipped = {},      -- {weapon="sword_iron", hat="hat_winter", ...}
        inventory = {"sword_iron", "hat_winter", "coat_warm", "boots_army"},  -- 背包里的装备id

        -- 天赋等级
        talents = {},       -- {hp=0, atk=0, ...}

        -- 炮塔碎片 & 等级
        turretFrags = {},   -- {arrow=0, minigun=0, ...}
        turretLevels = {},  -- {arrow=1, minigun=0, ...}

        -- 商城
        dailyBought = {},   -- 今日已买的daily商品id
        lastDailyReset = 0, -- 上次daily重置时间戳

        -- 玩家信息
        playerName = "幸存者",
        playerLevel = 1,
    }
end

return MD
