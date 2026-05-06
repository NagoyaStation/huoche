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
    quality_legend   = {220, 165, 30, 255},   -- 橙/金
    quality_supreme  = {210, 45, 45, 255},    -- 红

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
    { id = "shop",   name = "商城", img_normal = "image/商城界面图标未选中.png", img_active = "image/商城界面图标选中.png" },
    { id = "equip",  name = "装备", img_normal = "image/装备界面图标未选中.png", img_active = "image/装备界面图标选中.png" },
    { id = "battle", name = "战斗", img_normal = "image/战斗界面图标未选中.png", img_active = "image/战斗界面图标选中.png" },
    { id = "train",  name = "火车", img_normal = "image/火车界面图标未选中.png", img_active = "image/火车界面图标选中.png" },
    { id = "talent", name = "天赋", img_normal = "image/天赋界面图标未选中.png", img_active = "image/天赋界面图标选中.png" },
}

------------------------------------------------------------------------
-- 货币图标
------------------------------------------------------------------------
MD.CURRENCY_ICONS = {
    gold    = "image/图层_1 (2).png",
    diamond = "image/图层_4 (1).png",
    wood    = "image/图层_2 (1).png",
    stone   = "image/图层_3 (1).png",
}

------------------------------------------------------------------------
-- 装备系统
------------------------------------------------------------------------
MD.EQUIP_SLOTS = {
    { id = "weapon",    name = "武器",  icon = "image/装备界面/90d158e0-3033-4b48-8703-8e07b268c165.png" },
    { id = "accessory", name = "饰品",  icon = "image/装备界面/25b70b47-9324-4290-9413-72a32aade612.png" },
    { id = "ring",      name = "戒指",  icon = "image/装备界面/2f045d48-4402-4556-923c-c6229b877d69.png" },
    { id = "hat",       name = "帽子",  icon = "image/装备界面/Layer_0 (1).png" },
    { id = "clothes",   name = "衣服",  icon = "image/装备界面/67187031-0233-406a-bfc0-2feb66e29e80.png" },
    { id = "boots",     name = "鞋子",  icon = "image/装备界面/6348a94e-0b56-4d13-a980-780352bab06b.png" },
}

-- 装备品质
MD.QUALITY = {
    { id = "common",   name = "普通", color = MD.CLR.quality_common },
    { id = "uncommon", name = "优秀", color = MD.CLR.quality_uncommon },
    { id = "rare",     name = "稀有", color = MD.CLR.quality_rare },
    { id = "epic",     name = "史诗", color = MD.CLR.quality_epic },
    { id = "legend",   name = "传说", color = MD.CLR.quality_legend },
    { id = "supreme",  name = "至臻", color = MD.CLR.quality_supreme },
}

-- 装备数据库（示例装备）
MD.EQUIP_DB = {
    -- 武器
    { id = "sword_iron",   slot = "weapon",    name = "铁剑",     quality = 1, baseStats = {atk = 5},                   icon = "image/equip_weapon_sword_20260421064504.png" },
    { id = "axe_war",      slot = "weapon",    name = "战斧",     quality = 2, baseStats = {atk = 8, critRate = 5},      icon = "image/equip_weapon_axe_20260421064553.png" },
    { id = "sword_rare",   slot = "weapon",    name = "蓝钢剑",   quality = 3, baseStats = {atk = 15, critRate = 8},     icon = "image/equip_weapon_sword_20260421064504.png" },
    { id = "sword_epic",   slot = "weapon",    name = "暗影之刃", quality = 4, baseStats = {atk = 25, critDmg = 20},     icon = "image/equip_weapon_axe_20260421064553.png" },
    { id = "sword_legend", slot = "weapon",    name = "龙牙大剑", quality = 5, baseStats = {atk = 40, critRate = 15, critDmg = 30}, icon = "image/equip_weapon_sword_20260421064504.png" },
    { id = "sword_supreme",slot = "weapon",    name = "天命圣剑", quality = 6, baseStats = {atk = 60, critRate = 20, critDmg = 50}, icon = "image/equip_weapon_axe_20260421064553.png" },
    -- 饰品
    { id = "necklace_1",   slot = "accessory", name = "护身符",   quality = 1, baseStats = {def = 3},                   icon = "image/equip_accessory_necklace_20260421064510.png" },
    { id = "necklace_epic",slot = "accessory", name = "暗夜坠饰", quality = 4, baseStats = {def = 15, hp = 50},          icon = "image/equip_accessory_necklace_20260421064510.png" },
    -- 戒指
    { id = "ring_silver",  slot = "ring",      name = "银戒指",   quality = 2, baseStats = {atkSpd = 10},               icon = "image/equip_ring_20260421064511.png" },
    { id = "ring_legend",  slot = "ring",      name = "永恒之环", quality = 5, baseStats = {atkSpd = 25, critRate = 12}, icon = "image/equip_ring_20260421064511.png" },
    -- 帽子
    { id = "hat_winter",   slot = "hat",       name = "冬帽",     quality = 1, baseStats = {hp = 10},                   icon = "image/equip_hat_20260421064515.png" },
    { id = "hat_rare",     slot = "hat",       name = "精钢头盔", quality = 3, baseStats = {hp = 30, def = 8},           icon = "image/equip_hat_20260421064515.png" },
    -- 衣服
    { id = "coat_warm",    slot = "clothes",   name = "棉衣",     quality = 1, baseStats = {def = 5},                   icon = "image/equip_clothes_20260421064729.png" },
    { id = "coat_supreme", slot = "clothes",   name = "天神战甲", quality = 6, baseStats = {def = 40, hp = 100},         icon = "image/equip_clothes_20260421064729.png" },
    -- 鞋子
    { id = "boots_army",   slot = "boots",     name = "军靴",     quality = 1, baseStats = {speed = 8},                 icon = "image/equip_boots_20260421064742.png" },
    { id = "boots_epic",   slot = "boots",     name = "疾风之靴", quality = 4, baseStats = {speed = 20, atkSpd = 10},    icon = "image/equip_boots_20260421064742.png" },
}

------------------------------------------------------------------------
-- 装备随机词条系统
------------------------------------------------------------------------
-- 属性中文名和单位
MD.STAT_NAMES = {
    atk      = "攻击力",
    atkPct   = "攻击伤害",
    def      = "防御力",
    hp       = "生命值",
    critRate = "暴击率",
    critDmg  = "暴击伤害",
    atkSpd   = "攻击速度",
    speed    = "移动速度",
    arrowDmg   = "弓箭塔伤害",
    minigunDmg = "机枪塔伤害",
    flameDmg   = "喷火塔伤害",
    sniperDmg  = "狙击塔伤害",
    goldBonus  = "金币加成",
    rangePct   = "射程加成",
}
MD.STAT_UNITS = {
    atkPct = "%", critRate = "%", critDmg = "%", atkSpd = "%", speed = "%",
    arrowDmg = "%", minigunDmg = "%", flameDmg = "%", sniperDmg = "%",
    goldBonus = "%", rangePct = "%",
}

-- 词条等级：D/C/B/A/S
MD.AFFIX_GRADES = { "D", "C", "B", "A", "S" }
MD.AFFIX_GRADE_COLORS = {
    { 160, 160, 160 },  -- D 灰
    { 100, 200, 100 },  -- C 绿
    {  80, 150, 255 },  -- B 蓝
    { 180, 100, 255 },  -- A 紫
    { 255, 180,  40 },  -- S 橙
}

-- 随机词条池（values 对应 D/C/B/A/S 五个等级的数值）
MD.EQUIP_AFFIXES = {
    { id = "atk",        values = {3, 5, 8, 12, 18} },
    { id = "atkPct",     values = {5, 8, 12, 18, 25} },
    { id = "def",        values = {2, 4, 7, 10, 15} },
    { id = "hp",         values = {10, 20, 35, 50, 80} },
    { id = "critRate",   values = {3, 5, 8, 12, 18} },
    { id = "critDmg",    values = {8, 15, 25, 40, 60} },
    { id = "arrowDmg",   values = {5, 8, 12, 18, 25} },
    { id = "minigunDmg", values = {5, 8, 12, 18, 25} },
    { id = "flameDmg",   values = {5, 8, 12, 18, 25} },
    { id = "sniperDmg",  values = {5, 8, 12, 18, 25} },
    { id = "atkSpd",     values = {3, 5, 8, 12, 15} },
    { id = "goldBonus",  values = {3, 5, 8, 12, 18} },
    { id = "rangePct",   values = {3, 5, 8, 12, 15} },
}

-- 洗练费用（按品质等级）
MD.REFORGE_COST = { 50, 100, 200, 400, 800 }

-- 分解返还金币（按品质等级）
MD.DECOMPOSE_GOLD = { 10, 25, 60, 150, 400 }

-- 生成随机词条（quality: 1-5）
function MD.GenerateAffixes(quality)
    local count = math.min(math.max(quality, 1), 3)  -- 1~3条词条
    local affixes = {}
    local usedIds = {}
    for _ = 1, count do
        local pool = {}
        for _, a in ipairs(MD.EQUIP_AFFIXES) do
            if not usedIds[a.id] then table.insert(pool, a) end
        end
        if #pool == 0 then break end
        local picked = pool[math.random(#pool)]
        usedIds[picked.id] = true
        local maxGrade = math.min(quality + 1, 5)
        local grade = math.random(1, maxGrade)
        table.insert(affixes, { affixId = picked.id, grade = grade })
    end
    return affixes
end

-- 查找词条池数据
function MD.FindAffix(affixId)
    for _, a in ipairs(MD.EQUIP_AFFIXES) do
        if a.id == affixId then return a end
    end
    return nil
end

------------------------------------------------------------------------
-- 关卡系统
------------------------------------------------------------------------
MD.LEVELS = {
    { id = 1,  name = "保卫村庄", waves = 15, reward_gold = 50,  chest = "bronze", unlocked = true },
    { id = 2,  name = "冰封隧道", waves = 7,  reward_gold = 80,  chest = "bronze", unlocked = false },
    { id = 3,  name = "暴风雪谷", waves = 8,  reward_gold = 100, chest = "silver", unlocked = false },
    { id = 4,  name = "死寂车站", waves = 10, reward_gold = 150, chest = "silver", unlocked = false },
    { id = 5,  name = "钢铁废墟", waves = 12, reward_gold = 200, chest = "gold",   unlocked = false },
    { id = 6,  name = "末日核心", waves = 15, reward_gold = 300, chest = "gold",   unlocked = false },
}

MD.CHEST_ICONS = {
    bronze = "image/铜宝箱.png",
    silver = "image/银宝箱.png",
    gold   = "image/金宝箱.png",
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
    { id = "daily_gold",    name = "免费金币",     desc = "x100",    price = 0,   currency = "free",    icon = "image/hud_gold_coin.png" },
    { id = "daily_gatling", name = "加特林碎片",   desc = "x5",      price = 100, currency = "diamond", icon = "image/turret_minigun_v3_20260420035022.png" },
    { id = "daily_commando",name = "突击队员碎片", desc = "x5",      price = 100, currency = "diamond", icon = "image/turret_arrow_v3_20260420035036.png" },
    { id = "daily_wood",    name = "木材",         desc = "x1000",   price = 50,  currency = "diamond", icon = "image/meta_icon_wood_20260421063709.png" },
    { id = "daily_stone",   name = "石材",         desc = "x1000",   price = 50,  currency = "diamond", icon = "image/图层_3 (1).png" },
    { id = "daily_flame",   name = "喷火碎片",     desc = "x5",      price = 120, currency = "diamond", icon = "image/edited_turret_flame_nofire_20260423065123.png" },
    { id = "daily_sniper",  name = "狙击碎片",     desc = "x5",      price = 150, currency = "diamond", icon = "image/turret_sniper_v3_20260420035021.png" },
    { id = "daily_rocket",  name = "火箭碎片",     desc = "x3",      price = 200, currency = "diamond", icon = "image/turret_rocket_v3_20260420035019.png" },
}

MD.SHOP_FIXED = {
    { id = "fixed_gold_s", name = "金币礼包", desc = "x200",  price = 50,  currency = "diamond", icon = "image/hud_gold_coin.png" },
    { id = "fixed_gold_m", name = "金币礼包", desc = "x800",  price = 200, currency = "diamond", icon = "image/hud_gold_coin.png" },
}

MD.SHOP_GACHA = {
    name = "钻石抽奖",
    desc = "获得稀有装备与碎片",
    cost_single = 200,
    cost_ten = 2000,
}

------------------------------------------------------------------------
-- 炮塔升级数据（局外用碎片升级）
------------------------------------------------------------------------
MD.TURRET_UPGRADES = {
    { id = "arrow",    name = "弓箭炮塔", maxLv = 5, fragBase = 5,  fragGrow = 1.5, icon = "image/turret_arrow_v3_20260420035036.png",
        baseDmg = 8,  baseCD = 1.2, baseRange = 6.0 },
    { id = "minigun",  name = "机关枪塔", maxLv = 5, fragBase = 8,  fragGrow = 1.5, icon = "image/turret_minigun_v3_20260420035022.png",
        baseDmg = 4,  baseCD = 0.3, baseRange = 5.0 },
    { id = "flame",    name = "喷火炮塔", maxLv = 5, fragBase = 8,  fragGrow = 1.5, icon = "image/edited_turret_flame_nofire_20260423065123.png",
        baseDmg = 12, baseCD = 1.5, baseRange = 3.5 },
    { id = "sniper",   name = "狙击炮塔", maxLv = 5, fragBase = 10, fragGrow = 1.6, icon = "image/turret_sniper_v3_20260420035021.png",
        baseDmg = 30, baseCD = 3.0, baseRange = 12.0 },
    { id = "electric", name = "电能炮塔", maxLv = 5, fragBase = 10, fragGrow = 1.6, icon = "image/turret_electric_v10_20260423040517.png",
        baseDmg = 6,  baseCD = 0.8, baseRange = 5.5 },
    { id = "rocket",   name = "火箭炮塔", maxLv = 5, fragBase = 12, fragGrow = 1.8, icon = "image/turret_rocket_v3_20260420035019.png",
        baseDmg = 25, baseCD = 2.5, baseRange = 8.0 },
}

------------------------------------------------------------------------
-- 炮塔词条（每个等级解锁的特殊能力）
------------------------------------------------------------------------
MD.TURRET_AFFIXES = {
    arrow = {
        { lv = 1, desc = "攻击力+10%", color = {220, 220, 200} },
        { lv = 2, desc = "攻击速度+15%", color = {220, 220, 200} },
        { lv = 3, desc = "射程+20%", color = {100, 180, 255} },
        { lv = 4, desc = "双箭射击：同时射出2支箭", color = {200, 160, 50} },
        { lv = 5, desc = "穿透箭：箭矢穿透1个敌人", color = {255, 140, 40} },
    },
    minigun = {
        { lv = 1, desc = "攻击力+10%", color = {220, 220, 200} },
        { lv = 2, desc = "攻击速度+20%", color = {220, 220, 200} },
        { lv = 3, desc = "减速效果：命中减速10%", color = {100, 180, 255} },
        { lv = 4, desc = "弹幕风暴：攻速额外+30%", color = {200, 160, 50} },
        { lv = 5, desc = "过热模式：每10秒全力射击3秒", color = {255, 140, 40} },
    },
    flame = {
        { lv = 1, desc = "伤害+10%", color = {220, 220, 200} },
        { lv = 2, desc = "灼烧效果：持续伤害3秒", color = {220, 220, 200} },
        { lv = 3, desc = "范围+15%", color = {100, 180, 255} },
        { lv = 4, desc = "烈焰风暴：灼烧伤害+50%", color = {200, 160, 50} },
        { lv = 5, desc = "焚尽：灼烧降低敌人防御20%", color = {255, 140, 40} },
    },
    sniper = {
        { lv = 1, desc = "攻击力+15%", color = {220, 220, 200} },
        { lv = 2, desc = "暴击率+10%", color = {220, 220, 200} },
        { lv = 3, desc = "射程+25%", color = {100, 180, 255} },
        { lv = 4, desc = "致命打击：暴击伤害+80%", color = {200, 160, 50} },
        { lv = 5, desc = "处决：对30%以下生命敌人造成双倍伤害", color = {255, 140, 40} },
    },
    electric = {
        { lv = 1, desc = "伤害+10%", color = {220, 220, 200} },
        { lv = 2, desc = "链式闪电：跳跃至2个敌人", color = {220, 220, 200} },
        { lv = 3, desc = "麻痹效果：15%几率眩晕1秒", color = {100, 180, 255} },
        { lv = 4, desc = "闪电链+1跳跃目标", color = {200, 160, 50} },
        { lv = 5, desc = "雷暴领域：周围持续造成范围伤害", color = {255, 140, 40} },
    },
    rocket = {
        { lv = 1, desc = "爆炸范围+10%", color = {220, 220, 200} },
        { lv = 2, desc = "攻击力+15%", color = {220, 220, 200} },
        { lv = 3, desc = "破甲效果：无视20%防御", color = {100, 180, 255} },
        { lv = 4, desc = "集束弹头：分裂为3枚小火箭", color = {200, 160, 50} },
        { lv = 5, desc = "毁灭轰炸：爆炸留下灼烧区域4秒", color = {255, 140, 40} },
    },
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

        -- 装备（inventory 存实例对象，含随机词条）
        equipped = {},      -- {weapon=1, hat=2, ...} 槽位 -> inventory索引
        inventory = {       -- 背包装备实例
            { id = "sword_iron",    level = 1, affixes = { {affixId = "atk", grade = 1} } },
            { id = "hat_winter",    level = 1, affixes = { {affixId = "hp", grade = 1} } },
            { id = "coat_warm",     level = 1, affixes = { {affixId = "def", grade = 2} } },
            { id = "boots_army",    level = 1, affixes = { {affixId = "atkSpd", grade = 1}, {affixId = "goldBonus", grade = 2} } },
            { id = "axe_war",       level = 3, affixes = { {affixId = "atk", grade = 2} } },
            { id = "sword_rare",    level = 5, affixes = { {affixId = "critRate", grade = 3}, {affixId = "atk", grade = 2} } },
            { id = "sword_epic",    level = 8, affixes = { {affixId = "critDmg", grade = 4}, {affixId = "atk", grade = 3} } },
            { id = "sword_legend",  level = 12, affixes = { {affixId = "critRate", grade = 5}, {affixId = "critDmg", grade = 5}, {affixId = "atkPct", grade = 4} } },
            { id = "sword_supreme", level = 15, affixes = { {affixId = "critRate", grade = 5}, {affixId = "critDmg", grade = 5}, {affixId = "atkPct", grade = 5} } },
            { id = "necklace_epic", level = 6, affixes = { {affixId = "hp", grade = 3}, {affixId = "def", grade = 3} } },
            { id = "ring_legend",   level = 10, affixes = { {affixId = "atkSpd", grade = 5}, {affixId = "critRate", grade = 4} } },
            { id = "hat_rare",      level = 4, affixes = { {affixId = "hp", grade = 2}, {affixId = "def", grade = 2} } },
            { id = "coat_supreme",  level = 15, affixes = { {affixId = "def", grade = 5}, {affixId = "hp", grade = 5} } },
            { id = "boots_epic",    level = 7, affixes = { {affixId = "atkSpd", grade = 3} } },
        },

        -- 天赋等级
        talents = {},       -- {hp=0, atk=0, ...}

        -- 炮塔碎片 & 等级
        turretFrags = {},   -- {arrow=0, minigun=0, ...}
        turretLevels = {},  -- {arrow=1, minigun=0, ...}

        -- 炮塔装备（4个槽位，默认装备弓箭/机枪/狙击/火箭）
        turretEquipped = {"arrow", "minigun", "sniper", "rocket"},
        -- 已解锁的炮塔
        turretUnlocked = {arrow = true, minigun = true, sniper = true, rocket = true},

        -- 商城
        dailyBought = {},   -- 今日已买的daily商品id
        lastDailyReset = 0, -- 上次daily重置时间戳

        -- 玩家信息
        playerName = "幸存者",
        playerLevel = 1,
    }
end

return MD
