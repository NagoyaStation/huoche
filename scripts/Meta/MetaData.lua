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
-- 角色系统
------------------------------------------------------------------------
MD.CHARACTERS = {
    { id = "warrior",   name = "求生者",   quality = 3, icon = "image/hero_idle_20260414072856.png",
      portrait = "image/Layer_0 (1).png",
      equipDisplay = "image/装备界面/装备界面主角 .png",
      mountedImg = "image/Layer_0 (11).png",
      desc = "近战输出，攻守兼备", baseStats = {hp = 120},
      passive = "经验加成+10%",
      skill = { name = "投掷炸弹", desc = "在脚下放置炸弹，1.5秒后爆炸，对范围内敌人和资源造成200%攻击力伤害" },
      stars = {
          "初始获得武器[铁剑]",
          "近战伤害+10%",
          "近战体积+20% 穿透+3",
          "所有武器穿透+2",
          "伤害加成+15%",
          "全属性提升+10%",
      },
    },
    { id = "auntie",    name = "王阿姨", quality = 5, icon = "image/角色素材/艾达待机.png",
      portrait = "image/装备界面/Layer_0 (3).png",
      equipDisplay = "image/装备界面/Layer_0 (4).png",
      mountedImg = "image/王阿姨上车.png",
      desc = "治愈辅助，全队增益", baseStats = {hp = 140},
      passive = "全队生命恢复+5/秒",
      skill = { name = "治疗", desc = "立即回复列车20%血量，冷却60秒", icon = "image/治疗.png", cd = 60 },
      attackFrames = {
          "image/角色素材/艾达攻击动画1.png",
          "image/角色素材/艾达攻击动画2.png.png",
          "image/角色素材/艾达攻击动画3.png",
          "image/角色素材/艾达攻击动画4.png",
          "image/角色素材/艾达攻击动画5.png",
          "image/角色素材/艾达攻击动画6.png",
          "image/角色素材/艾达攻击动画7.png",
      },
      attackFPS = 8,
      walkFrames = {
          "image/角色素材/艾达行走动画1.png",
          "image/角色素材/艾达行走动画2.png",
          "image/角色素材/艾达行走动画3.png",
          "image/角色素材/艾达行走动画4.png",
          "image/角色素材/艾达行走动画5.png",
          "image/角色素材/艾达行走动画6.png",
          "image/角色素材/艾达行走动画7.png",
          "image/角色素材/艾达行走动画8.png",
          "image/角色素材/艾达行走动画9.png",
          "image/角色素材/艾达行走动画10.png",
      },
      walkFPS = 10,
      stars = {
          "初始获得武器[手杖]",
          "治愈效果+10%",
          "增益持续时间+20%",
          "全队防御+8%",
          "冷却缩减+15%",
          "终极增益：全属性+12%",
      },
    },
    { id = "lisanguang", name = "李三光", quality = 4, icon = "image/角色素材/李三光/李三光待机.png",
      portrait = "image/角色素材/李三光/Layer_0 (5).png",
      equipDisplay = "image/角色素材/李三光/Layer_0 (6).png",
      mountedImg = "image/李三光上车.png",
      desc = "远程输出，精准打击", baseStats = {hp = 100},
      passive = "暴击率+8%",
      skill = { name = "狂暴", desc = "7秒内攻速与冷却速度+100%", icon = "image/狂暴.png", cd = 15 },
      attackFrames = {
          "image/角色素材/李三光/李三光攻击1.png",
          "image/角色素材/李三光/李三光攻击2.png",
          "image/角色素材/李三光/李三光攻击3.png",
          "image/角色素材/李三光/李三光攻击4.png",
          "image/角色素材/李三光/李三光攻击5.png",
          "image/角色素材/李三光/李三光攻击6.png",
          "image/角色素材/李三光/李三光攻击7.png",
          "image/角色素材/李三光/李三光攻击8.png",
      },
      attackFPS = 8,
      walkFrames = {
          "image/角色素材/李三光/李三光行走1.png",
          "image/角色素材/李三光/李三光行走2.png",
          "image/角色素材/李三光/李三光行走3.png",
          "image/角色素材/李三光/李三光行走4.png",
          "image/角色素材/李三光/李三光行走5.png",
          "image/角色素材/李三光/李三光行走6.png",
          "image/角色素材/李三光/李三光行走7.png",
          "image/角色素材/李三光/李三光行走8.png",
          "image/角色素材/李三光/李三光行走9.png",
          "image/角色素材/李三光/李三光行走10.png",
      },
      walkFPS = 10,
      stars = {
          "初始获得武器[步枪]",
          "暴击伤害+15%",
          "射速+10%",
          "穿透+1层",
          "攻击范围+20%",
          "终极射击：弹道追踪",
      },
    },
    { id = "weifenglong", name = "威风的龙", quality = 6, icon = "image/角色素材/威风的龙/威风的龙待机.png",
      portrait = "image/角色素材/威风的龙/威风的龙头像.png",
      equipDisplay = "image/角色素材/威风的龙/威风的龙人物形象.png",
      mountedImg = "image/威龙上车.png",
      desc = "龙族后裔，近战霸主", baseStats = {hp = 130},
      passive = "受伤减免+10%",
      skill = { name = "喷气", desc = "向最后移动方向快速位移，无冷却", icon = "image/威龙喷气.png", cd = 0 },
      attackFrames = {
          "image/角色素材/威风的龙/威风的龙攻击1.png",
          "image/角色素材/威风的龙/威风的龙攻击2.png",
          "image/角色素材/威风的龙/威风的龙攻击3.png",
          "image/角色素材/威风的龙/威风的龙攻击4.png",
          "image/角色素材/威风的龙/威风的龙攻击5.png",
          "image/角色素材/威风的龙/威风的龙攻击6.png",
      },
      attackFPS = 8,
      walkFrames = {
          "image/角色素材/威风的龙/威风的龙行走1.png",
          "image/角色素材/威风的龙/威风的龙行走2.png",
          "image/角色素材/威风的龙/威风的龙行走3.png",
          "image/角色素材/威风的龙/威风的龙行走4.png",
          "image/角色素材/威风的龙/威风的龙行走5.png",
          "image/角色素材/威风的龙/威风的龙行走6.png",
          "image/角色素材/威风的龙/威风的龙行走7.png",
          "image/角色素材/威风的龙/威风的龙行走8.png",
          "image/角色素材/威风的龙/威风的龙行走9.png",
          "image/角色素材/威风的龙/威风的龙行走10.png",
      },
      walkFPS = 10,
      stars = {
          "初始获得武器[龙爪]",
          "受伤减免+15%",
          "攻击力+12%",
          "灼烧伤害+30%",
          "生命值+20%",
          "终极形态：龙化变身",
      },
    },
}

-- 升星碎片需求
MD.STAR_FRAG_COST = { 0, 2, 4, 6, 8, 10 }
MD.MAX_STAR = 6

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

-- 装备数据库
MD.EQUIP_DB = {
    ---------------------------------------------------------------------------
    -- 武器 ── 品质1 普通（原始/简陋武器）── 近战 weaponType="melee"
    ---------------------------------------------------------------------------
    { id = "stick",             slot = "weapon", name = "木棍",       quality = 1, weaponType = "melee",  baseStats = {meleeAtk = 3},                                       icon = "image/装备/武器/stick_icon.png" },
    { id = "stick_nails",       slot = "weapon", name = "钉棍",       quality = 1, weaponType = "melee",  baseStats = {meleeAtk = 5},                                       icon = "image/装备/武器/stick_nails_icon.png" },
    { id = "stone_knife",       slot = "weapon", name = "石刀",       quality = 1, weaponType = "melee",  baseStats = {meleeAtk = 4, atkSpd = 5},                           icon = "image/装备/武器/stone_knife_icon.png" },
    { id = "stone_pickaxe",     slot = "weapon", name = "石镐",       quality = 1, weaponType = "melee",  baseStats = {meleeAtk = 4},                                       icon = "image/装备/武器/stone_pickaxe_icon.png" },
    { id = "stone_axe",         slot = "weapon", name = "石斧",       quality = 1, weaponType = "melee",  baseStats = {meleeAtk = 5},                                       icon = "image/装备/武器/stone_axe_icon.png" },
    { id = "knife_basic",       slot = "weapon", name = "匕首",       quality = 1, weaponType = "melee",  baseStats = {meleeAtk = 4, atkSpd = 8},                           icon = "image/装备/武器/knife_icon.png" },
    ---------------------------------------------------------------------------
    -- 武器 ── 品质2 优秀（工具/基础武器）
    ---------------------------------------------------------------------------
    { id = "bat",               slot = "weapon", name = "棒球棒",     quality = 2, weaponType = "melee",  baseStats = {meleeAtk = 8},                                       icon = "image/装备/武器/bat_icon.png" },
    { id = "bat_nails",         slot = "weapon", name = "钉刺球棒",   quality = 2, weaponType = "melee",  baseStats = {meleeAtk = 10, critRate = 3},                        icon = "image/装备/武器/bat_nails_icon.png" },
    { id = "axe_basic",         slot = "weapon", name = "手斧",       quality = 2, weaponType = "melee",  baseStats = {meleeAtk = 9, critDmg = 5},                          icon = "image/装备/武器/axe_icon.png" },
    { id = "picaxe",            slot = "weapon", name = "铁镐",       quality = 2, weaponType = "melee",  baseStats = {meleeAtk = 7, critRate = 5},                         icon = "image/装备/武器/picaxe_icon.png" },
    { id = "bone_spear",        slot = "weapon", name = "骨矛",       quality = 2, weaponType = "melee",  baseStats = {meleeAtk = 9},                                       icon = "image/装备/武器/bone_spear_icon.png" },
    { id = "bow_basic",         slot = "weapon", name = "短弓",       quality = 2, weaponType = "ranged", baseStats = {rangedAtk = 8, atkSpd = 5},                          icon = "image/装备/武器/bow_icon.png" },
    ---------------------------------------------------------------------------
    -- 武器 ── 品质3 稀有（精良制造/改装武器）
    ---------------------------------------------------------------------------
    { id = "metal_hammer",      slot = "weapon", name = "铁锤",       quality = 3, weaponType = "melee",  baseStats = {meleeAtk = 15, critDmg = 10},                        icon = "image/装备/武器/metal_hammer_icon.png" },
    { id = "cinderblock_hammer",slot = "weapon", name = "重锤",       quality = 3, weaponType = "melee",  baseStats = {meleeAtk = 16, critDmg = 12},                        icon = "image/装备/武器/cinderblock_hammer_icon.png" },
    { id = "saw_bat",           slot = "weapon", name = "锯刃棒",     quality = 3, weaponType = "melee",  baseStats = {meleeAtk = 14, critRate = 8},                        icon = "image/装备/武器/saw_bat_icon.png" },
    { id = "rambo_knife",       slot = "weapon", name = "兰博刀",     quality = 3, weaponType = "melee",  baseStats = {meleeAtk = 13, atkSpd = 10, critRate = 5},           icon = "image/装备/武器/rambo_knife_icon.png" },
    { id = "bone_bow",          slot = "weapon", name = "骨弓",       quality = 3, weaponType = "ranged", baseStats = {rangedAtk = 14, atkSpd = 8},                         icon = "image/装备/武器/bone_bow_icon.png" },
    { id = "pistol",            slot = "weapon", name = "手枪",       quality = 3, weaponType = "ranged", baseStats = {rangedAtk = 15, atkSpd = 10},                        icon = "image/装备/武器/pistol_icon.png" },
    { id = "grenade",           slot = "weapon", name = "手雷",       quality = 3, weaponType = "ranged", baseStats = {rangedAtk = 18},                                     icon = "image/装备/武器/grenade_icon.png" },
    ---------------------------------------------------------------------------
    -- 武器 ── 品质4 史诗（军用/高级武器）
    ---------------------------------------------------------------------------
    { id = "katana",            slot = "weapon", name = "武士刀",     quality = 4, weaponType = "melee",  baseStats = {meleeAtk = 25, critRate = 12, critDmg = 15},         icon = "image/装备/武器/katana_icon.png" },
    { id = "revolver",          slot = "weapon", name = "左轮手枪",   quality = 4, weaponType = "ranged", baseStats = {rangedAtk = 22, critDmg = 20},                       icon = "image/装备/武器/revolver_icon.png" },
    { id = "sport_bow",         slot = "weapon", name = "竞技弓",     quality = 4, weaponType = "ranged", baseStats = {rangedAtk = 23, atkSpd = 12, critRate = 8},          icon = "image/装备/武器/sport_bow_icon_new.png" },
    { id = "desert_eagle",      slot = "weapon", name = "沙漠之鹰",   quality = 4, weaponType = "ranged", baseStats = {rangedAtk = 28, critDmg = 18},                       icon = "image/装备/武器/desert_eagle_icon.png" },
    { id = "remington_870",     slot = "weapon", name = "雷明顿霰弹", quality = 4, weaponType = "ranged", baseStats = {rangedAtk = 26, critRate = 10},                      icon = "image/装备/武器/remington_870_icon.png" },
    ---------------------------------------------------------------------------
    -- 武器 ── 品质5 传说（顶级军火）── 远程 weaponType="ranged"
    ---------------------------------------------------------------------------
    { id = "akm",               slot = "weapon", name = "AKM突击步枪",quality = 5, weaponType = "ranged", baseStats = {rangedAtk = 38, atkSpd = 15, critRate = 10},         icon = "image/装备/武器/akm_icon.png" },
    { id = "m16",               slot = "weapon", name = "M16步枪",    quality = 5, weaponType = "ranged", baseStats = {rangedAtk = 35, atkSpd = 18, critRate = 12},         icon = "image/装备/武器/m16_icon.png" },
    { id = "acr",               slot = "weapon", name = "ACR精准步枪",quality = 5, weaponType = "ranged", baseStats = {rangedAtk = 36, critRate = 15, critDmg = 25},        icon = "image/装备/武器/acr_icon.png" },
    { id = "remington_700",     slot = "weapon", name = "雷明顿狙击",  quality = 5, weaponType = "ranged", baseStats = {rangedAtk = 42, critDmg = 35},                      icon = "image/装备/武器/remington_700_icon.png" },
    ---------------------------------------------------------------------------
    -- 武器 ── 品质6 至臻（限定/收藏级）
    ---------------------------------------------------------------------------
    { id = "xmas_revolver",     slot = "weapon", name = "圣诞左轮",   quality = 6, weaponType = "ranged", baseStats = {rangedAtk = 50, critRate = 18, critDmg = 40},        icon = "image/装备/武器/christmas_revolver_icon.png" },
    { id = "xmas_revolver2",    slot = "weapon", name = "极光左轮",   quality = 6, weaponType = "ranged", baseStats = {rangedAtk = 55, critRate = 20, critDmg = 45},        icon = "image/装备/武器/christmas_revolver2_icon.png" },
    { id = "xmas_shotgun",      slot = "weapon", name = "圣诞霰弹枪", quality = 6, weaponType = "ranged", baseStats = {rangedAtk = 58, critRate = 15, atkSpd = 15},         icon = "image/装备/武器/christmas_shotgun_icon.png" },
    { id = "xmas_bat",          slot = "weapon", name = "圣诞战棒",   quality = 6, weaponType = "melee",  baseStats = {meleeAtk = 52, critDmg = 50},                        icon = "image/装备/武器/christmas_bat_icon.png" },
    { id = "xmas_candy_cane",   slot = "weapon", name = "糖果权杖",   quality = 6, weaponType = "melee",  baseStats = {meleeAtk = 48, atkSpd = 20, critRate = 18},          icon = "image/装备/武器/christmas_candy_cane_icon.png" },
    { id = "xmas_lollipop",     slot = "weapon", name = "棒棒糖锤",   quality = 6, weaponType = "melee",  baseStats = {meleeAtk = 45, critDmg = 55, hp = 30},               icon = "image/装备/武器/christmas_lollipop.png" },
    -- 饰品（项链） —— 品质1 普通
    { id = "common_necklace",    slot = "accessory", name = "破旧绳坠",     quality = 1, baseStats = {def = 3},                                    icon = "image/装备/首饰/common_necklace.png" },
    { id = "casual_necklace",    slot = "accessory", name = "皮绳铁牌链",   quality = 1, baseStats = {def = 5, hp = 5},                            icon = "image/装备/首饰/casual_necklace.png" },
    -- 品质2 优秀
    { id = "cultist_necklace",   slot = "accessory", name = "骷髅图腾链",   quality = 2, baseStats = {def = 8, critRate = 3},                      icon = "image/装备/首饰/cultist_necklace.png" },
    -- 品质3 稀有
    { id = "scavenger_necklace", slot = "accessory", name = "拾荒者弹链",   quality = 3, baseStats = {def = 12, hp = 20},                          icon = "image/装备/首饰/scavenger_necklace.png" },
    { id = "explorer_necklace",  slot = "accessory", name = "探险者罗盘链", quality = 3, baseStats = {def = 10, atkSpd = 5, hp = 15},               icon = "image/装备/首饰/explorer_necklace.png" },
    -- 品质4 史诗
    { id = "warchief_necklace",  slot = "accessory", name = "战酋锁链",     quality = 4, baseStats = {def = 18, hp = 40, critRate = 4},             icon = "image/装备/首饰/warchief_necklace.png" },
    -- 品质5 传说
    { id = "venom_necklace",     slot = "accessory", name = "剧毒战链",     quality = 5, baseStats = {def = 22, hp = 55, critDmg = 8},              icon = "image/装备/首饰/venom_necklace.png" },
    { id = "inferno_necklace",   slot = "accessory", name = "炽焰核心链",   quality = 5, baseStats = {def = 25, hp = 50, critRate = 6},             icon = "image/装备/首饰/inferno_necklace.png" },
    { id = "doom_necklace",      slot = "accessory", name = "末日牛魔链",   quality = 5, baseStats = {def = 20, hp = 60, atkSpd = 8},               icon = "image/装备/首饰/doom_necklace.png" },
    -- 品质6 至臻
    { id = "overlord_necklace",  slot = "accessory", name = "霸主蓝晶链",   quality = 6, baseStats = {def = 30, hp = 80, critRate = 10, critDmg = 12}, icon = "image/装备/首饰/overlord_necklace.png" },
    -- 戒指 —— 品质1 普通
    { id = "rusty_ring",          slot = "ring", name = "锈铁石环",     quality = 1, baseStats = {atkSpd = 3},                                       icon = "image/装备/戒指/rusty_ring.png" },
    { id = "pendant_ring",        slot = "ring", name = "铁坠指环",     quality = 1, baseStats = {atkSpd = 4, def = 2},                               icon = "image/装备/戒指/pendant_ring.png" },
    -- 品质2 优秀
    { id = "scrap_ring",          slot = "ring", name = "废铁螺母环",   quality = 2, baseStats = {atkSpd = 6, critRate = 2},                           icon = "image/装备/戒指/scrap_ring.png" },
    { id = "hunter_ring",         slot = "ring", name = "猎人药瓶环",   quality = 2, baseStats = {atkSpd = 5, hp = 10},                               icon = "image/装备/戒指/hunter_ring.png" },
    { id = "bone_ring",           slot = "ring", name = "兽骨指环",     quality = 2, baseStats = {atkSpd = 7, def = 3},                               icon = "image/装备/戒指/bone_ring.png" },
    -- 品质3 稀有
    { id = "crystal_shard_ring",  slot = "ring", name = "紫晶裂片环",   quality = 3, baseStats = {atkSpd = 10, critRate = 3},                          icon = "image/装备/戒指/crystal_shard_ring.png" },
    { id = "turquoise_ring",      slot = "ring", name = "绿松石铁环",   quality = 3, baseStats = {atkSpd = 8, hp = 15, def = 5},                      icon = "image/装备/戒指/turquoise_ring.png" },
    { id = "frost_crystal_ring",  slot = "ring", name = "冰蓝晶石环",   quality = 3, baseStats = {atkSpd = 9, critRate = 4},                          icon = "image/装备/戒指/frost_crystal_ring.png" },
    -- 品质4 史诗
    { id = "energy_core_ring",    slot = "ring", name = "能量核心环",   quality = 4, baseStats = {atkSpd = 14, critRate = 5, hp = 20},                 icon = "image/装备/戒指/energy_core_ring.png" },
    { id = "demon_spike_ring",    slot = "ring", name = "恶魔尖刺环",   quality = 4, baseStats = {atkSpd = 12, critDmg = 6, critRate = 4},             icon = "image/装备/戒指/demon_spike_ring.png" },
    { id = "ruby_signet_ring",    slot = "ring", name = "红宝石印戒",   quality = 4, baseStats = {atkSpd = 15, critRate = 6},                          icon = "image/装备/戒指/ruby_signet_ring.png" },
    { id = "void_crystal_ring",   slot = "ring", name = "虚空晶环",     quality = 4, baseStats = {atkSpd = 13, critDmg = 5, hp = 25},                 icon = "image/装备/戒指/void_crystal_ring.png" },
    -- 品质5 传说
    { id = "radiant_ring",        slot = "ring", name = "辐光翡翠环",   quality = 5, baseStats = {atkSpd = 20, critRate = 8, critDmg = 8},             icon = "image/装备/戒指/radiant_ring.png" },
    { id = "nuclear_ring",        slot = "ring", name = "核能指环",     quality = 5, baseStats = {atkSpd = 22, critRate = 10, hp = 40},                icon = "image/装备/戒指/nuclear_ring.png" },
    { id = "magma_ring",          slot = "ring", name = "熔岩之环",     quality = 5, baseStats = {atkSpd = 25, critDmg = 10, critRate = 6},            icon = "image/装备/戒指/magma_ring.png" },
    -- 品质6 至臻
    { id = "doomforge_ring",      slot = "ring", name = "末日锻造之环", quality = 6, baseStats = {atkSpd = 30, critRate = 12, critDmg = 15, hp = 60}, icon = "image/装备/戒指/doomforge_ring.png" },
    -- 头盔 —— 品质1 普通
    { id = "common_head",   slot = "hat", name = "破旧毛线帽", quality = 1, baseStats = {hp = 8},                              icon = "image/装备/头盔/common_head.png" },
    { id = "casual_head",   slot = "hat", name = "渔夫防护帽", quality = 1, baseStats = {hp = 10, def = 2},                    icon = "image/装备/头盔/casual_head.png" },
    -- 品质2 优秀
    { id = "bad_head",      slot = "hat", name = "破烂兜帽",   quality = 2, baseStats = {hp = 15, def = 4},                    icon = "image/装备/头盔/bad_head.png" },
    { id = "cultist_head",  slot = "hat", name = "骨面邪盔",   quality = 2, baseStats = {hp = 18, critRate = 3},               icon = "image/装备/头盔/cultist_head.png" },
    -- 品质3 稀有
    { id = "garbage_head",  slot = "hat", name = "拾荒者面罩", quality = 3, baseStats = {hp = 25, def = 6},                    icon = "image/装备/头盔/garbage_man_head.png" },
    { id = "mad_head",      slot = "hat", name = "狂暴战盔",   quality = 3, baseStats = {hp = 28, atkSpd = 6},                 icon = "image/装备/头盔/mad_head.png" },
    { id = "hazmat_head",   slot = "hat", name = "防化头罩",   quality = 3, baseStats = {hp = 30, def = 8},                    icon = "image/装备/头盔/hazmat_head.png" },
    -- 品质4 史诗
    { id = "football_head", slot = "hat", name = "狂怒橄榄盔", quality = 4, baseStats = {hp = 40, def = 10, atkSpd = 5},       icon = "image/装备/头盔/football_player_head.png" },
    { id = "military_head", slot = "hat", name = "军用战术盔", quality = 4, baseStats = {hp = 45, def = 14},                   icon = "image/装备/头盔/military_head.png" },
    { id = "noir_head",     slot = "hat", name = "暗影战盔",   quality = 4, baseStats = {hp = 42, def = 12, critRate = 4},     icon = "image/装备/头盔/noir_head.png" },
    -- 品质5 传说
    { id = "juggernaut_head", slot = "hat", name = "重装指挥盔", quality = 5, baseStats = {hp = 60, def = 20},                 icon = "image/装备/头盔/juggernaut_head.png" },
    { id = "warlord_head",  slot = "hat", name = "恶魔领主盔", quality = 5, baseStats = {hp = 55, def = 15, critDmg = 10},     icon = "image/装备/头盔/warlord_head.png" },
    { id = "overlord_head", slot = "hat", name = "暗金征服盔", quality = 5, baseStats = {hp = 58, def = 18, critRate = 6},     icon = "image/装备/头盔/overlord_head.png" },
    -- 品质6 至臻
    { id = "xmas_head",     slot = "hat", name = "圣诞战盔",   quality = 6, baseStats = {hp = 80, def = 25, critRate = 8},     icon = "image/装备/头盔/christmas_armor_head.png" },
    -- 衣服 —— 品质1 普通
    { id = "common_body",   slot = "clothes", name = "普通衣物",   quality = 1, baseStats = {def = 3},                              icon = "image/装备/衣服/common_body.png" },
    { id = "casual_body",   slot = "clothes", name = "休闲服",     quality = 1, baseStats = {def = 4, hp = 5},                      icon = "image/装备/衣服/casual_body.png" },
    -- 品质2 优秀
    { id = "bad_body",      slot = "clothes", name = "破旧夹克",   quality = 2, baseStats = {def = 6, speed = 5},                   icon = "image/装备/衣服/bad_body.png" },
    { id = "cultist_body",  slot = "clothes", name = "邪教徒袍",   quality = 2, baseStats = {def = 7, hp = 10},                     icon = "image/装备/衣服/cultist_body.png" },
    -- 品质3 稀有
    { id = "mad_body",      slot = "clothes", name = "疯狂套装",   quality = 3, baseStats = {def = 12, atkSpd = 8},                 icon = "image/装备/衣服/mad_body.png" },
    { id = "hazmat_body",   slot = "clothes", name = "防化服",     quality = 3, baseStats = {def = 15, hp = 25},                    icon = "image/装备/衣服/hazmat_body.png" },
    -- 品质4 史诗
    { id = "military_body", slot = "clothes", name = "军用战术甲", quality = 4, baseStats = {def = 22, hp = 40},                    icon = "image/装备/衣服/military_body.png" },
    { id = "noir_body",     slot = "clothes", name = "暗影风衣",   quality = 4, baseStats = {def = 18, critRate = 6, speed = 8},    icon = "image/装备/衣服/noir_body.png" },
    -- 品质5 传说
    { id = "juggernaut_body", slot = "clothes", name = "重装战甲", quality = 5, baseStats = {def = 35, hp = 80, atkSpd = -5},       icon = "image/装备/衣服/juggernaut_body.png" },
    -- 品质6 至臻
    { id = "xmas_armor",    slot = "clothes", name = "圣诞战甲",   quality = 6, baseStats = {def = 40, hp = 100, critRate = 8},     icon = "image/装备/衣服/christmas_armor_upper.png" },
    -- 鞋子 —— 品质1 普通
    { id = "common_boots",   slot = "boots", name = "普通布鞋",   quality = 1, baseStats = {speed = 4},                             icon = "image/装备/鞋子/common_boots.png" },
    { id = "casual_boots",   slot = "boots", name = "休闲运动鞋", quality = 1, baseStats = {speed = 5, hp = 5},                     icon = "image/装备/鞋子/casual_boots.png" },
    -- 品质2 优秀
    { id = "bad_boots",      slot = "boots", name = "破旧皮靴",   quality = 2, baseStats = {speed = 7, def = 3},                    icon = "image/装备/鞋子/bad_boots.png" },
    { id = "cultist_boots",  slot = "boots", name = "邪教徒靴",   quality = 2, baseStats = {speed = 8, hp = 8},                     icon = "image/装备/鞋子/cultist_boots.png" },
    -- 品质3 稀有
    { id = "garbage_boots",  slot = "boots", name = "拾荒者长靴", quality = 3, baseStats = {speed = 10, def = 6},                   icon = "image/装备/鞋子/garbage_man_boots.png" },
    { id = "mad_boots",      slot = "boots", name = "狂暴战靴",   quality = 3, baseStats = {speed = 12, atkSpd = 6},                icon = "image/装备/鞋子/mad_boots.png" },
    { id = "hazmat_boots",   slot = "boots", name = "防化长靴",   quality = 3, baseStats = {speed = 10, hp = 20, def = 5},          icon = "image/装备/鞋子/hazmat_boots.png" },
    -- 品质4 史诗
    { id = "football_boots", slot = "boots", name = "球星战靴",   quality = 4, baseStats = {speed = 18, atkSpd = 8},                icon = "image/装备/鞋子/football_player_boots.png" },
    { id = "military_boots", slot = "boots", name = "军用作战靴", quality = 4, baseStats = {speed = 15, def = 12, hp = 20},         icon = "image/装备/鞋子/military_boots.png" },
    { id = "noir_boots",     slot = "boots", name = "暗影之靴",   quality = 4, baseStats = {speed = 16, critRate = 5},              icon = "image/装备/鞋子/noir_boots.png" },
    -- 品质5 传说
    { id = "juggernaut_boots", slot = "boots", name = "重装战靴", quality = 5, baseStats = {speed = 20, def = 18, hp = 40},         icon = "image/装备/鞋子/juggernaut_boots.png" },
    -- 品质6 至臻
    { id = "xmas_boots",     slot = "boots", name = "圣诞战靴",   quality = 6, baseStats = {speed = 25, atkSpd = 15, critRate = 6}, icon = "image/装备/鞋子/christmas_armor_boots.png" },
}

------------------------------------------------------------------------
-- 装备随机词条系统
------------------------------------------------------------------------
-- 属性中文名和单位
MD.STAT_NAMES = {
    meleeAtk   = "近战攻击力",
    rangedAtk  = "射击攻击力",
    atkPct   = "攻击伤害",
    def      = "列车防御",
    hp       = "列车生命",
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
    { id = "meleeAtk",   values = {3, 5, 8, 12, 18} },
    { id = "rangedAtk",  values = {3, 5, 8, 12, 18} },
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

-- 查找装备定义
function MD.FindEquipDef(equipId)
    for _, e in ipairs(MD.EQUIP_DB) do
        if e.id == equipId then return e end
    end
    return nil
end

--- 计算装备+角色总属性加成，返回统一的 stats 表
--- @param saveData table 存档数据（含 equipped, inventory, activeChar）
--- @return table stats 各属性总值
function MD.CalcEquipStats(saveData)
    local stats = {
        meleeAtk = 0, rangedAtk = 0, atkPct = 0, def = 0, hp = 0,
        critRate = 0, critDmg = 0, atkSpd = 0, speed = 0,
        arrowDmg = 0, minigunDmg = 0, flameDmg = 0, sniperDmg = 0,
        goldBonus = 0, rangePct = 0,
    }
    if not saveData then return stats end

    -- 1. 角色基础属性
    local charId = saveData.activeChar or "warrior"
    for _, ch in ipairs(MD.CHARACTERS) do
        if ch.id == charId then
            stats.meleeAtk  = stats.meleeAtk  + (ch.baseStats.meleeAtk or 0)
            stats.rangedAtk = stats.rangedAtk + (ch.baseStats.rangedAtk or 0)
            stats.hp        = stats.hp        + (ch.baseStats.hp or 0)
            break
        end
    end

    -- 2. 装备属性（baseStats + 词条）
    local equipped = saveData.equipped or {}
    local inventory = saveData.inventory or {}
    for _, invIdx in pairs(equipped) do
        local item = inventory[invIdx]
        if item then
            -- 查找装备定义获取 baseStats
            local def = MD.FindEquipDef(item.id)
            if def and def.baseStats then
                for k, v in pairs(def.baseStats) do
                    if stats[k] then
                        stats[k] = stats[k] + v
                    end
                end
            end
            -- 累加词条属性
            if item.affixes then
                for _, aff in ipairs(item.affixes) do
                    local pool = MD.FindAffix(aff.affixId)
                    if pool and aff.grade then
                        local grade = math.max(1, math.min(aff.grade, 5))
                        local val = pool.values[grade] or 0
                        if stats[aff.affixId] then
                            stats[aff.affixId] = stats[aff.affixId] + val
                        end
                    end
                end
            end
        end
    end

    return stats
end

------------------------------------------------------------------------
-- 关卡系统
------------------------------------------------------------------------
MD.LEVELS = {
    -- 雪地 (关卡1-4)
    { id = 1,  name = "起始之地",   waves = 15, reward_gold = 50,   chest = "bronze", unlocked = true,  mapImg = "image/图层_13.png",           floorImg = "image/bg_white_snow_20260416070957.png" },
    { id = 2,  name = "雪原哨站",   waves = 7,  reward_gold = 80,   chest = "bronze", unlocked = false, mapImg = "image/地图/雪地1.png",        floorImg = "image/bg_white_snow_20260416070957.png" },
    { id = 3,  name = "暴雪矿道",   waves = 8,  reward_gold = 100,  chest = "bronze", unlocked = false, mapImg = "image/地图/雪地2 (2).png",   floorImg = "image/bg_white_snow_20260416070957.png" },
    { id = 4,  name = "风雪断哨",   waves = 10, reward_gold = 150,  chest = "silver", unlocked = false, mapImg = "image/地图/雪地3.png",        floorImg = "image/bg_white_snow_20260416070957.png" },
    -- 雪地2 (关卡5-7)
    { id = 5,  name = "白霜补给站", waves = 12, reward_gold = 200,  chest = "silver", unlocked = false, mapImg = "image/地图/雪地2-1.png",      floorImg = "image/地图/雪地.png" },
    { id = 6,  name = "积雪林线",   waves = 15, reward_gold = 300,  chest = "gold",   unlocked = false, mapImg = "image/地图/雪地2-2.png",      floorImg = "image/地图/雪地.png" },
    { id = 7,  name = "寒夜前哨",   waves = 8,  reward_gold = 120,  chest = "bronze", unlocked = false, mapImg = "image/地图/雪地2-3.png",      floorImg = "image/地图/雪地.png" },
    -- 冻原 (关卡8-10)
    { id = 8,  name = "冻土驿路",   waves = 10, reward_gold = 160,  chest = "bronze", unlocked = false, mapImg = "image/地图/冻原1.png",        floorImg = "image/地图/冻原.png" },
    { id = 9,  name = "永冻废墟",   waves = 12, reward_gold = 200,  chest = "silver", unlocked = false, mapImg = "image/地图/冻原2.png",        floorImg = "image/地图/冻原.png" },
    { id = 10, name = "裂谷补给点", waves = 14, reward_gold = 250,  chest = "silver", unlocked = false, mapImg = "image/地图/冻原3.png",        floorImg = "image/地图/冻原.png" },
    -- 冰原 (关卡11-13)
    { id = 11, name = "冰原孤灯",   waves = 15, reward_gold = 300,  chest = "gold",   unlocked = false, mapImg = "image/地图/冰原1.png",        floorImg = "image/地图/冰原.png" },
    { id = 12, name = "冰河信标",   waves = 10, reward_gold = 180,  chest = "bronze", unlocked = false, mapImg = "image/地图/冰原2.png",        floorImg = "image/地图/冰原.png" },
    { id = 13, name = "极寒终点站", waves = 12, reward_gold = 220,  chest = "silver", unlocked = false, mapImg = "image/地图/冰原3.png",        floorImg = "image/地图/冰原.png" },
    -- 城市 (关卡14-16)
    { id = 14, name = "废城外环",   waves = 14, reward_gold = 280,  chest = "silver", unlocked = false, mapImg = "image/地图/城市1.png",        floorImg = "image/地图/城市.png" },
    { id = 15, name = "黑烟街区",   waves = 16, reward_gold = 350,  chest = "gold",   unlocked = false, mapImg = "image/地图/城市2.png",        floorImg = "image/地图/城市.png" },
    { id = 16, name = "中央避难所", waves = 12, reward_gold = 240,  chest = "bronze", unlocked = false, mapImg = "image/地图/城市3.png",        floorImg = "image/地图/城市.png" },
    -- 森林 (关卡17-19)
    { id = 17, name = "枯林哨塔",   waves = 14, reward_gold = 300,  chest = "silver", unlocked = false, mapImg = "image/地图/森林1.png",        floorImg = "image/地图/森林.png" },
    { id = 18, name = "雪松营地",   waves = 16, reward_gold = 360,  chest = "silver", unlocked = false, mapImg = "image/地图/森林2.png",        floorImg = "image/地图/森林.png" },
    { id = 19, name = "迷雾林站",   waves = 18, reward_gold = 420,  chest = "gold",   unlocked = false, mapImg = "image/地图/森林3.png",        floorImg = "image/地图/森林.png" },
    -- 沙漠 (关卡20-22)
    { id = 20, name = "黄沙旧轨",   waves = 15, reward_gold = 350,  chest = "silver", unlocked = false, mapImg = "image/地图/沙漠1.png",        floorImg = "image/地图/沙漠.png" },
    { id = 21, name = "风蚀驿站",   waves = 18, reward_gold = 450,  chest = "gold",   unlocked = false, mapImg = "image/地图/沙漠2.png",        floorImg = "image/地图/沙漠.png" },
    { id = 22, name = "烈日补给线", waves = 16, reward_gold = 400,  chest = "silver", unlocked = false, mapImg = "image/地图/沙漠3.png",        floorImg = "image/地图/沙漠.png" },
    -- 熔岩 (关卡23-25)
    { id = 23, name = "焦土裂隙",   waves = 20, reward_gold = 500,  chest = "gold",   unlocked = false, mapImg = "image/地图/熔岩1.png",        floorImg = "image/地图/熔岩.png" },
    { id = 24, name = "熔岩矿坑",   waves = 22, reward_gold = 600,  chest = "gold",   unlocked = false, mapImg = "image/地图/熔岩2.png",        floorImg = "image/地图/熔岩.png" },
    { id = 25, name = "火山终点站", waves = 25, reward_gold = 800,  chest = "gold",   unlocked = false, mapImg = "image/地图/熔岩3.png",        floorImg = "image/地图/熔岩.png" },
}

MD.CHEST_ICONS = {
    bronze = "image/铜宝箱.png",
    silver = "image/银宝箱.png",
    gold   = "image/金宝箱.png",
}

MD.CHEST_ICONS_OPENED = {
    bronze = "image/铜宝箱开.png",
    silver = "image/银宝箱开.png",
    gold   = "image/金宝箱开.png",
}

-- 宝箱奖励：每个关卡3个宝箱(25%/50%/100%)的奖励内容
-- 格式: { {label, amount}, ... }
MD.CHEST_REWARDS = {
    bronze = {
        { { "金币", 50 },  { "木材", 200 } },    -- 25%
        { { "金币", 100 }, { "石材", 300 } },     -- 50%
        { { "金币", 200 }, { "钻石", 10 } },      -- 100%
    },
    silver = {
        { { "金币", 100 }, { "木材", 500 } },
        { { "金币", 200 }, { "石材", 500 } },
        { { "金币", 300 }, { "钻石", 20 } },
    },
    gold = {
        { { "金币", 200 }, { "木材", 1000 } },
        { { "金币", 400 }, { "石材", 1000 } },
        { { "金币", 500 }, { "钻石", 50 } },
    },
}

------------------------------------------------------------------------
-- 天赋系统（50级线性解锁，依次激活）
------------------------------------------------------------------------
-- 天赋类型图标映射（同类型共享图标）
MD.TALENT_ICONS = {
    atk       = "image/talent_atk_20260601020310.png",         -- 攻击力
    crit_rate = "image/talent_crit_rate_20260601020320.png",   -- 暴击率
    crit_dmg  = "image/talent_crit_dmg_20260601020308.png",    -- 暴击伤害
    atk_spd   = "image/talent_atk_spd_20260601020311.png",    -- 攻击速度
    atk_range = "image/talent_atk_range_20260601020313.png",   -- 攻击范围
    atk_dmg   = "image/talent_atk_dmg_20260601020325.png",    -- 攻击伤害%
    turret_dmg= "image/talent_turret_dmg_20260601020310.png",  -- 炮塔伤害
    armor_pen = "image/talent_armor_pen_20260601020309.png",   -- 护甲穿透
    cooldown  = "image/talent_cooldown_20260601020312.png",    -- 冷却速度
    gather    = "image/talent_gather_20260601020333.png",      -- 采集速度/时运
    carry     = "image/talent_carry_20260601020505.png",       -- 携带上限
    weapon_dmg= "image/talent_weapon_dmg_20260601020505.png",  -- 武器伤害
}

MD.TALENTS = {
    { lv=1,  type="atk",       name="攻击力+10",      desc="攻击力+10",         cost=500 },
    { lv=2,  type="crit_rate", name="暴击率+2%",      desc="暴击率+2%",         cost=1000 },
    { lv=3,  type="crit_dmg",  name="暴击伤害+5%",    desc="暴击伤害+5%",       cost=2000 },
    { lv=4,  type="atk_spd",   name="攻击速度+5%",    desc="攻击速度+5%",       cost=4000 },
    { lv=5,  type="atk_range", name="攻击范围+5%",    desc="攻击范围+5%",       cost=8000 },
    { lv=6,  type="atk_dmg",   name="攻击伤害+10%",   desc="攻击伤害+10%",      cost=12000 },
    { lv=7,  type="turret_dmg",name="炮塔伤害+5%",    desc="炮塔伤害+5%",       cost=16000 },
    { lv=8,  type="armor_pen", name="护甲穿透+2",     desc="护甲穿透+2",        cost=20000 },
    { lv=9,  type="cooldown",  name="炮塔冷却速度+3%",desc="炮塔冷却速度+3%",   cost=24000 },
    { lv=10, type="atk",       name="攻击力+20",      desc="攻击力+20",         cost=28000 },
    { lv=11, type="crit_rate", name="暴击率+2%",      desc="暴击率+2%",         cost=35000 },
    { lv=12, type="crit_dmg",  name="暴击伤害+5%",    desc="暴击伤害+5%",       cost=40000 },
    { lv=13, type="gather",    name="采集速度+5%",    desc="采集速度+5%",       cost=45000 },
    { lv=14, type="carry",     name="携带上限+2",     desc="携带上限+2",        cost=50000 },
    { lv=15, type="atk_dmg",   name="伤害加成+3%",    desc="伤害加成+3%",       cost=55000 },
    { lv=16, type="atk",       name="攻击力+30",      desc="攻击力+30",         cost=70000 },
    { lv=17, type="crit_rate", name="暴击率+2%",      desc="暴击率+2%",         cost=80000 },
    { lv=18, type="crit_dmg",  name="暴击伤害+5%",    desc="暴击伤害+5%",       cost=90000 },
    { lv=19, type="atk_dmg",   name="攻击伤害+10%",   desc="攻击伤害+10%",      cost=100000 },
    { lv=20, type="weapon_dmg",name="武器伤害+5%",    desc="武器伤害+5%",       cost=110000 },
    { lv=21, type="atk",       name="攻击力+40",      desc="攻击力+40",         cost=125000 },
    { lv=22, type="gather",    name="采集时运",       desc="采集时运",          cost=140000 },
    { lv=23, type="crit_dmg",  name="暴击伤害+6%",    desc="暴击伤害+6%",       cost=155000 },
    { lv=24, type="cooldown",  name="冷却速度+3%",    desc="冷却速度+3%",       cost=170000 },
    { lv=25, type="carry",     name="携带上限+3",     desc="携带上限+3",        cost=185000 },
    { lv=26, type="atk",       name="攻击力+50",      desc="攻击力+50",         cost=205000 },
    { lv=27, type="atk_spd",   name="攻击速度+5%",    desc="攻击速度+5%",       cost=225000 },
    { lv=28, type="armor_pen", name="护甲穿透+4",     desc="护甲穿透+4",        cost=245000 },
    { lv=29, type="atk_dmg",   name="攻击伤害+12%",   desc="攻击伤害+12%",      cost=265000 },
    { lv=30, type="weapon_dmg",name="武器伤害+6%",    desc="武器伤害+6%",       cost=285000 },
    { lv=31, type="atk",       name="攻击力+60",      desc="攻击力+60",         cost=310000 },
    { lv=32, type="crit_rate", name="暴击率+3%",      desc="暴击率+3%",         cost=335000 },
    { lv=33, type="cooldown",  name="冷却速度+3%",    desc="冷却速度+3%",       cost=360000 },
    { lv=34, type="crit_dmg",  name="暴击伤害+6%",    desc="暴击伤害+6%",       cost=385000 },
    { lv=35, type="carry",     name="携带上限+5",     desc="携带上限+5",        cost=410000 },
    { lv=36, type="atk",       name="攻击力+70",      desc="攻击力+70",         cost=440000 },
    { lv=37, type="atk_spd",   name="攻击速度+5%",    desc="攻击速度+5%",       cost=470000 },
    { lv=38, type="armor_pen", name="护甲穿透+4",     desc="护甲穿透+4",        cost=500000 },
    { lv=39, type="atk_dmg",   name="攻击伤害+12%",   desc="攻击伤害+12%",      cost=530000 },
    { lv=40, type="weapon_dmg",name="武器伤害+6%",    desc="武器伤害+6%",       cost=560000 },
    { lv=41, type="atk",       name="攻击力+80",      desc="攻击力+80",         cost=595000 },
    { lv=42, type="crit_rate", name="暴击率+3%",      desc="暴击率+3%",         cost=630000 },
    { lv=43, type="cooldown",  name="冷却速度+3%",    desc="冷却速度+3%",       cost=665000 },
    { lv=44, type="crit_dmg",  name="暴击伤害+6%",    desc="暴击伤害+6%",       cost=700000 },
    { lv=45, type="carry",     name="携带上限+5",     desc="携带上限+5",        cost=735000 },
    { lv=46, type="atk",       name="攻击力+90",      desc="攻击力+90",         cost=775000 },
    { lv=47, type="atk_spd",   name="攻击速度+5%",    desc="攻击速度+5%",       cost=815000 },
    { lv=48, type="armor_pen", name="护甲穿透+4",     desc="护甲穿透+4",        cost=855000 },
    { lv=49, type="atk_dmg",   name="攻击伤害+12%",   desc="攻击伤害+12%",      cost=895000 },
    { lv=50, type="weapon_dmg",name="武器伤害+6%",    desc="武器伤害+6%",       cost=935000 },
}
MD.TALENT_MAX_LV = 50

--- 计算天赋累计加成（根据当前已解锁等级）
--- @param talentLevel number 当前天赋等级（0~50）
--- @return table 累计属性加成
function MD.CalcTalentStats(talentLevel)
    local stats = {
        atk = 0,           -- 攻击力（固定值加成）
        critRate = 0,      -- 暴击率%
        critDmg = 0,       -- 暴击伤害%
        atkSpd = 0,        -- 攻击速度%
        atkRange = 0,      -- 攻击范围%
        atkDmg = 0,        -- 攻击伤害%（通用伤害加成）
        turretDmg = 0,     -- 炮塔伤害%
        armorPen = 0,      -- 护甲穿透（固定值）
        cooldown = 0,      -- 炮塔冷却速度%
        gather = 0,        -- 采集速度%（含时运次数）
        carry = 0,         -- 携带上限（固定值加成）
        weaponDmg = 0,     -- 武器伤害%
    }
    if not talentLevel or talentLevel <= 0 then return stats end
    local maxLv = math.min(talentLevel, MD.TALENT_MAX_LV)
    for i = 1, maxLv do
        local t = MD.TALENTS[i]
        if not t then break end
        local tp = t.type
        -- 从 name 中提取数值
        local num = tonumber(string.match(t.name, "%+(%d+)"))
        if num then
            if     tp == "atk"        then stats.atk = stats.atk + num
            elseif tp == "crit_rate"  then stats.critRate = stats.critRate + num
            elseif tp == "crit_dmg"   then stats.critDmg = stats.critDmg + num
            elseif tp == "atk_spd"    then stats.atkSpd = stats.atkSpd + num
            elseif tp == "atk_range"  then stats.atkRange = stats.atkRange + num
            elseif tp == "atk_dmg"    then stats.atkDmg = stats.atkDmg + num
            elseif tp == "turret_dmg" then stats.turretDmg = stats.turretDmg + num
            elseif tp == "armor_pen"  then stats.armorPen = stats.armorPen + num
            elseif tp == "cooldown"   then stats.cooldown = stats.cooldown + num
            elseif tp == "gather"     then stats.gather = stats.gather + num
            elseif tp == "carry"      then stats.carry = stats.carry + num
            elseif tp == "weapon_dmg" then stats.weaponDmg = stats.weaponDmg + num
            end
        else
            -- 特殊天赋无数值（如"采集时运"），给固定加成
            if tp == "gather" then stats.gather = stats.gather + 10 end
        end
    end
    return stats
end

------------------------------------------------------------------------
-- 商城系统
------------------------------------------------------------------------
-- 第一格固定：免费金币
MD.SHOP_DAILY_FREE = { id = "daily_gold", name = "免费金币", desc = "x100", price = 0, currency = "free", icon = "image/hud_gold_coin.png" }

-- 随机池：每天从中抽5个填入后5格
MD.SHOP_DAILY_POOL = {
    -- 炮塔碎片
    { id = "daily_gatling", name = "机关枪塔碎片", desc = "x5",      price = 100, currency = "diamond", icon = "image/turret_minigun_v3_20260420035022.png",              turretId = "minigun" },
    { id = "daily_commando",name = "弓箭炮塔碎片", desc = "x5",      price = 100, currency = "diamond", icon = "image/turret_arrow_v3_20260420035036.png",                turretId = "arrow" },
    { id = "daily_flame",   name = "喷火炮塔碎片", desc = "x5",      price = 120, currency = "diamond", icon = "image/edited_turret_flame_nofire_20260423065123.png",     turretId = "flame" },
    { id = "daily_sniper",  name = "狙击炮塔碎片", desc = "x5",      price = 150, currency = "diamond", icon = "image/turret_sniper_v3_20260420035021.png",               turretId = "sniper" },
    { id = "daily_rocket",  name = "火箭炮塔碎片", desc = "x3",      price = 200, currency = "diamond", icon = "image/turret_rocket_v3_20260420035019.png",               turretId = "rocket" },
    -- 资源
    { id = "daily_wood",    name = "木材",         desc = "x1000",   price = 50,  currency = "diamond", icon = "image/meta_icon_wood_20260421063709.png" },
    { id = "daily_stone",   name = "石材",         desc = "x1000",   price = 50,  currency = "diamond", icon = "image/图层_3 (1).png" },
    -- 角色碎片
    { id = "daily_char_auntie",      name = "王阿姨碎片",   desc = "x3", price = 150, currency = "diamond", icon = "image/角色素材/艾达待机.png",                    charId = "auntie" },
    { id = "daily_char_lisanguang",  name = "李三光碎片",   desc = "x3", price = 120, currency = "diamond", icon = "image/角色素材/李三光/李三光待机.png",             charId = "lisanguang" },
    { id = "daily_char_weifenglong", name = "威风的龙碎片", desc = "x3", price = 200, currency = "diamond", icon = "image/角色素材/威风的龙/威风的龙待机.png",          charId = "weifenglong" },
}
MD.SHOP_DAILY_PICK = 5  -- 每天从池子里抽几个

MD.SHOP_FIXED = {
    { id = "fixed_gold_s", name = "金币礼包", desc = "x200",  price = 50,  currency = "diamond", icon = "image/hud_gold_coin.png" },
    { id = "fixed_gold_m", name = "金币礼包", desc = "x800",  price = 200, currency = "diamond", icon = "image/hud_gold_coin.png" },
}

MD.SHOP_GACHA = {
    name = "钻石抽奖",
    desc = "获得稀有装备与碎片",
    cost_single = 30,
    cost_ten = 300,
}

-- 充值获取钻石（免费定时抽取）
MD.SHOP_RECHARGE = {
    -- 概率表：{钻石数量, 概率权重, 品质标签}
    pool = {
        { amount = 30,  weight = 50, label = "N" },
        { amount = 98,  weight = 30, label = "R" },
        { amount = 198, weight = 15, label = "SR" },
        { amount = 648, weight = 5,  label = "SSR" },
    },
    cooldown_once = 60,       -- 充值一次冷却：60秒
    cooldown_ten  = 28800,    -- 充值十次冷却：8小时(28800秒)
}

-- ===== 7日签到奖励 =====
MD.SIGN_IN_REWARDS = {
    { day = 1, type = "gold",   amount = 1000, name = "金币",     icon = "image/图层_1 (2).png",   quality = 1 },
    { day = 2, type = "diamond", amount = 200,  name = "钻石",     icon = "image/图层_4 (1).png",   quality = 3 },
    { day = 3, type = "turret_frag", turretId = "flame", amount = 5, name = "喷火塔碎片", icon = "image/edited_turret_flame_nofire_20260423065123.png", quality = 3 },
    { day = 4, type = "gold",   amount = 3000, name = "金币",     icon = "image/图层_1 (2).png",   quality = 2 },
    { day = 5, type = "diamond", amount = 500,  name = "钻石",     icon = "image/图层_4 (1).png",   quality = 4 },
    { day = 6, type = "wood",   amount = 800,  name = "木材",     icon = "image/图层_2 (1).png",   quality = 2 },
    { day = 7, type = "equip",  id = "katana", name = "武士刀", icon = "image/装备/武器/katana_icon.png", quality = 4 },
}

------------------------------------------------------------------------
-- 邮件/公告列表（静态配置，可按需增删）
------------------------------------------------------------------------
MD.MAIL_LIST = {
    {
        id = "mail_welcome",
        title = "新手礼包",
        date = "2026/5/5",
        expireDays = 30,
        content = "亲爱的列车长，欢迎登上雪国列车！这是一份新手礼包，助你快速启程，祝游戏愉快！",
        attachments = {
            { type = "gold",    amount = 1500, name = "金币", icon = "image/图层_1 (2).png" },
            { type = "wood",    amount = 500,  name = "木材", icon = "image/图层_2 (1).png" },
            { type = "stone",   amount = 500,  name = "石材", icon = "image/图层_3 (1).png" },
        },
    },
}

-- 抽奖奖池（权重越高出现概率越大）
MD.GACHA_POOL = {
    -- 装备类（直接获得装备，加入背包）
    -- 品质1 普通
    { type = "equip", id = "stick",             weight = 25 },
    { type = "equip", id = "stick_nails",       weight = 25 },
    { type = "equip", id = "stone_knife",       weight = 25 },
    { type = "equip", id = "stone_pickaxe",     weight = 25 },
    { type = "equip", id = "stone_axe",         weight = 25 },
    { type = "equip", id = "knife_basic",       weight = 25 },
    { type = "equip", id = "common_head",       weight = 25 },
    { type = "equip", id = "casual_head",       weight = 25 },
    { type = "equip", id = "common_body",       weight = 25 },
    { type = "equip", id = "casual_body",       weight = 25 },
    { type = "equip", id = "common_boots",      weight = 25 },
    { type = "equip", id = "casual_boots",      weight = 25 },
    { type = "equip", id = "common_necklace",    weight = 25 },
    { type = "equip", id = "casual_necklace",    weight = 25 },
    { type = "equip", id = "rusty_ring",          weight = 25 },
    { type = "equip", id = "pendant_ring",        weight = 25 },
    -- 品质2 优秀
    { type = "equip", id = "bat",               weight = 18 },
    { type = "equip", id = "bat_nails",         weight = 18 },
    { type = "equip", id = "axe_basic",         weight = 18 },
    { type = "equip", id = "picaxe",            weight = 18 },
    { type = "equip", id = "bone_spear",        weight = 18 },
    { type = "equip", id = "bow_basic",         weight = 18 },
    { type = "equip", id = "scrap_ring",         weight = 18 },
    { type = "equip", id = "hunter_ring",        weight = 18 },
    { type = "equip", id = "bone_ring",          weight = 18 },
    { type = "equip", id = "bad_head",          weight = 18 },
    { type = "equip", id = "cultist_head",      weight = 18 },
    { type = "equip", id = "bad_body",          weight = 18 },
    { type = "equip", id = "cultist_body",      weight = 18 },
    { type = "equip", id = "bad_boots",         weight = 18 },
    { type = "equip", id = "cultist_boots",     weight = 18 },
    { type = "equip", id = "cultist_necklace",  weight = 18 },
    -- 品质3 稀有
    { type = "equip", id = "metal_hammer",      weight = 12 },
    { type = "equip", id = "cinderblock_hammer",weight = 12 },
    { type = "equip", id = "saw_bat",           weight = 12 },
    { type = "equip", id = "rambo_knife",       weight = 12 },
    { type = "equip", id = "bone_bow",          weight = 12 },
    { type = "equip", id = "pistol",            weight = 12 },
    { type = "equip", id = "grenade",           weight = 12 },
    { type = "equip", id = "garbage_head",      weight = 12 },
    { type = "equip", id = "mad_head",          weight = 12 },
    { type = "equip", id = "hazmat_head",       weight = 12 },
    { type = "equip", id = "mad_body",          weight = 12 },
    { type = "equip", id = "hazmat_body",       weight = 12 },
    { type = "equip", id = "garbage_boots",     weight = 12 },
    { type = "equip", id = "mad_boots",         weight = 12 },
    { type = "equip", id = "hazmat_boots",      weight = 12 },
    { type = "equip", id = "scavenger_necklace", weight = 12 },
    { type = "equip", id = "explorer_necklace",  weight = 12 },
    { type = "equip", id = "crystal_shard_ring",  weight = 12 },
    { type = "equip", id = "turquoise_ring",      weight = 12 },
    { type = "equip", id = "frost_crystal_ring",  weight = 12 },
    -- 品质4 史诗
    { type = "equip", id = "katana",            weight = 6 },
    { type = "equip", id = "revolver",          weight = 6 },
    { type = "equip", id = "sport_bow",         weight = 6 },
    { type = "equip", id = "desert_eagle",      weight = 6 },
    { type = "equip", id = "remington_870",     weight = 6 },
    { type = "equip", id = "warchief_necklace", weight = 6 },
    { type = "equip", id = "football_boots",    weight = 6 },
    { type = "equip", id = "military_boots",    weight = 6 },
    { type = "equip", id = "noir_boots",        weight = 6 },
    { type = "equip", id = "football_head",     weight = 6 },
    { type = "equip", id = "military_head",     weight = 6 },
    { type = "equip", id = "noir_head",         weight = 6 },
    { type = "equip", id = "military_body",     weight = 6 },
    { type = "equip", id = "noir_body",         weight = 6 },
    { type = "equip", id = "energy_core_ring",    weight = 6 },
    { type = "equip", id = "demon_spike_ring",    weight = 6 },
    { type = "equip", id = "ruby_signet_ring",    weight = 6 },
    { type = "equip", id = "void_crystal_ring",   weight = 6 },
    -- 品质5 传说
    { type = "equip", id = "akm",               weight = 2 },
    { type = "equip", id = "m16",               weight = 2 },
    { type = "equip", id = "acr",               weight = 2 },
    { type = "equip", id = "remington_700",     weight = 2 },
    { type = "equip", id = "radiant_ring",       weight = 2 },
    { type = "equip", id = "nuclear_ring",       weight = 2 },
    { type = "equip", id = "magma_ring",         weight = 2 },
    { type = "equip", id = "juggernaut_head",   weight = 2 },
    { type = "equip", id = "warlord_head",      weight = 2 },
    { type = "equip", id = "overlord_head",     weight = 2 },
    { type = "equip", id = "juggernaut_body",   weight = 2 },
    { type = "equip", id = "juggernaut_boots",  weight = 2 },
    { type = "equip", id = "venom_necklace",    weight = 2 },
    { type = "equip", id = "inferno_necklace",  weight = 2 },
    { type = "equip", id = "doom_necklace",     weight = 2 },
    -- 品质6 至臻
    { type = "equip", id = "xmas_revolver",     weight = 0.5 },
    { type = "equip", id = "xmas_revolver2",    weight = 0.5 },
    { type = "equip", id = "xmas_shotgun",      weight = 0.5 },
    { type = "equip", id = "xmas_bat",          weight = 0.5 },
    { type = "equip", id = "xmas_candy_cane",   weight = 0.5 },
    { type = "equip", id = "xmas_lollipop",     weight = 0.5 },
    { type = "equip", id = "xmas_armor",        weight = 0.5 },
    { type = "equip", id = "xmas_boots",        weight = 0.5 },
    { type = "equip", id = "xmas_head",         weight = 0.5 },
    { type = "equip", id = "overlord_necklace", weight = 0.5 },
    { type = "equip", id = "doomforge_ring",    weight = 0.5 },
    -- 资源类
    { type = "gold",   amount = 200,  weight = 30, name = "金币",     icon = "image/图层_1 (2).png" },
    { type = "gold",   amount = 500,  weight = 15, name = "金币",     icon = "image/图层_1 (2).png" },
    { type = "gold",   amount = 1000, weight = 5,  name = "金币",     icon = "image/图层_1 (2).png" },
    { type = "diamond", amount = 50,  weight = 8,  name = "钻石",     icon = "image/图层_4 (1).png" },
    { type = "diamond", amount = 100, weight = 3,  name = "钻石",     icon = "image/图层_4 (1).png" },
    { type = "wood",   amount = 300,  weight = 20, name = "木材",     icon = "image/图层_2 (1).png" },
    { type = "stone",  amount = 300,  weight = 20, name = "石材",     icon = "image/图层_3 (1).png" },
    -- 炮塔碎片
    { type = "turret_frag", turretId = "arrow",   amount = 3, weight = 12, name = "弓箭塔碎片", icon = "image/turret_arrow_v3_20260420035036.png" },
    { type = "turret_frag", turretId = "minigun", amount = 3, weight = 12, name = "机枪塔碎片", icon = "image/turret_minigun_v3_20260420035022.png" },
    { type = "turret_frag", turretId = "flame",   amount = 2, weight = 10, name = "喷火塔碎片", icon = "image/edited_turret_flame_nofire_20260423065123.png" },
    { type = "turret_frag", turretId = "sniper",  amount = 2, weight = 8,  name = "狙击塔碎片", icon = "image/turret_sniper_v3_20260420035021.png" },
    { type = "turret_frag", turretId = "electric",amount = 2, weight = 8,  name = "电能塔碎片", icon = "image/turret_electric_v10_20260423040517.png" },
    { type = "turret_frag", turretId = "rocket",  amount = 1, weight = 6,  name = "火箭塔碎片", icon = "image/turret_rocket_v3_20260420035019.png" },
}

------------------------------------------------------------------------
-- 钻石抽奖等级系统
------------------------------------------------------------------------
-- 每品质获得的经验值
MD.GACHA_EXP_PER_QUALITY = {
    [1] = 10,   -- 白色(普通)
    [2] = 15,   -- 绿色(优质)
    [3] = 20,   -- 蓝色(稀有)
    [4] = 50,   -- 紫色(史诗)
    [5] = 100,  -- 金色(传说)
    [6] = 200,  -- 红色(至臻)
}

-- 每级所需经验 = level * 800
function MD.GetGachaMaxExp(level)
    return level * 800
end

-- 等级提升高品质权重加成（百分比）
-- 每级对品质3+的装备weight乘以 (1 + level * bonus)
MD.GACHA_LEVEL_BONUS = {
    [1] = 0,        -- 品质1(白) 无加成
    [2] = 0,        -- 品质2(绿) 无加成
    [3] = 0.03,     -- 品质3(蓝) 每级+3%
    [4] = 0.05,     -- 品质4(紫) 每级+5%
    [5] = 0.08,     -- 品质5(金) 每级+8%
    [6] = 0.12,     -- 品质6(红) 每级+12%
}

-- 增加抽卡经验，自动升级
function MD.AddGachaExp(saveData, expGain)
    if saveData.gachaLevel >= 20 then return end  -- 满级不加
    saveData.gachaExp = (saveData.gachaExp or 0) + expGain
    -- 循环升级
    while saveData.gachaLevel < 20 do
        local maxExp = MD.GetGachaMaxExp(saveData.gachaLevel)
        if saveData.gachaExp >= maxExp then
            saveData.gachaExp = saveData.gachaExp - maxExp
            saveData.gachaLevel = saveData.gachaLevel + 1
            print("[Gacha] 抽奖等级提升! Lv." .. saveData.gachaLevel)
        else
            break
        end
    end
    -- 满级时经验锁定为0
    if saveData.gachaLevel >= 20 then
        saveData.gachaExp = 0
    end
end

-- 抽奖：按权重随机抽取 count 个物品（等级影响高品质掉率）
function MD.RollGacha(count, gachaLevel)
    gachaLevel = gachaLevel or 1
    -- 构建带等级加成的权重表
    local totalWeight = 0
    local adjustedWeights = {}
    for i, item in ipairs(MD.GACHA_POOL) do
        local w = item.weight
        -- 装备类根据品质和等级调整权重
        if item.type == "equip" and gachaLevel > 1 then
            -- 查找装备品质
            local quality = 1
            for _, eq in ipairs(MD.EQUIP_DB) do
                if eq.id == item.id then
                    quality = eq.quality or 1
                    break
                end
            end
            local bonus = MD.GACHA_LEVEL_BONUS[quality] or 0
            if bonus > 0 then
                w = w * (1 + (gachaLevel - 1) * bonus)
            end
        end
        adjustedWeights[i] = w
        totalWeight = totalWeight + w
    end
    -- 抽取
    local results = {}
    for _ = 1, count do
        local roll = math.random() * totalWeight
        local acc = 0
        for i, item in ipairs(MD.GACHA_POOL) do
            acc = acc + adjustedWeights[i]
            if roll <= acc then
                -- 构建奖励信息
                local reward = { type = item.type }
                if item.type == "equip" then
                    -- 查找装备数据
                    for _, eq in ipairs(MD.EQUIP_DB) do
                        if eq.id == item.id then
                            reward.id = eq.id
                            reward.name = eq.name
                            reward.quality = eq.quality
                            reward.icon = eq.icon
                            reward.slot = eq.slot
                            break
                        end
                    end
                else
                    reward.name = item.name
                    reward.icon = item.icon
                    reward.amount = item.amount
                    reward.quality = 1  -- 资源默认白色品质
                    if item.type == "diamond" then reward.quality = 3 end
                    if item.type == "turret_frag" then
                        reward.quality = 2
                        reward.turretId = item.turretId
                    end
                end
                table.insert(results, reward)
                break
            end
        end
    end
    return results
end

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
-- 品质颜色映射（用于局外展示）
MD.QUALITY_COLORS = {
    [1] = {220, 220, 200},   -- 优质(白)
    [2] = {100, 180, 255},   -- 稀有(蓝)
    [3] = {200, 130, 255},   -- 史诗(紫)
    [4] = {255, 160, 40},    -- 传说(橙)
    [5] = {255, 60, 60},     -- 至臻(红)
}
MD.QUALITY_NAMES = { "优质", "稀有", "史诗", "传说", "至臻" }

-- 炮塔强化卡解锁数据（局外展示用，与 Config.UPGRADES 中 unlockLevel 对应）
MD.TURRET_AFFIXES = {
    arrow = {
        { lv = 1, name = "硬化箭矢", desc = "弓箭伤害+60%", quality = 3 },
        { lv = 2, name = "远程弓弦", desc = "弓箭射程+60%", quality = 3 },
        { lv = 3, name = "速射改装", desc = "弓箭攻速+80%", quality = 3 },
        { lv = 4, name = "贯穿箭",   desc = "箭矢穿透+3个目标", quality = 3 },
        { lv = 5, name = "毒素箭头", desc = "命中施加4秒毒素", quality = 4 },
        { lv = 6, name = "穿链弹",   desc = "击中后弹射至附近1个敌人", quality = 4 },
    },
    minigun = {
        { lv = 1, name = "穿甲弹芯", desc = "机枪伤害+55%", quality = 3 },
        { lv = 2, name = "超频枪管", desc = "机枪攻速+90%", quality = 3 },
        { lv = 3, name = "长管改造", desc = "机枪射程+50%", quality = 2 },
        { lv = 4, name = "跳弹装甲", desc = "子弹反弹2次", quality = 2 },
        { lv = 5, name = "燃烧弹头", desc = "命中附加2.5秒燃烧", quality = 4 },
    },
    flame = {
        { lv = 1, name = "高温燃料", desc = "喷火伤害+65%", quality = 3 },
        { lv = 2, name = "长焰喷嘴", desc = "喷火射程+50%", quality = 2 },
        { lv = 3, name = "快速点火", desc = "喷火攻速+55%", quality = 2 },
        { lv = 4, name = "跳弹装甲", desc = "子弹反弹2次", quality = 2 },
        { lv = 5, name = "旋转火舌", desc = "喷火方向持续旋转扫射", quality = 5 },
    },
    sniper = {
        { lv = 1, name = "穿甲狙击弹", desc = "狙击伤害+80%", quality = 3 },
        { lv = 2, name = "长距镜",     desc = "狙击射程+90%", quality = 3 },
        { lv = 3, name = "快拉枪栓",   desc = "狙击装填速度+70%", quality = 2 },
        { lv = 4, name = "要害瞄准",   desc = "50%暴击×2.5倍", quality = 3 },
        { lv = 5, name = "冰封子弹",   desc = "命中敌人眩晕1.8秒", quality = 5 },
    },
    electric = {
        { lv = 1, name = "高压电容", desc = "电能伤害+70%", quality = 3 },
        { lv = 2, name = "急放电",   desc = "电能攻速+85%", quality = 3 },
        { lv = 3, name = "导电延伸", desc = "电能射程+55%", quality = 2 },
        { lv = 4, name = "链式放电", desc = "电弧弹射至附近+1个目标", quality = 3 },
    },
    rocket = {
        { lv = 1, name = "重型弹头", desc = "火箭伤害+80%", quality = 3 },
        { lv = 2, name = "扩爆装药", desc = "火箭爆炸范围+85%", quality = 3 },
        { lv = 3, name = "快速装弹", desc = "火箭装填速度+65%", quality = 2 },
        { lv = 4, name = "五连齐射", desc = "同时发射5枚散布火箭", quality = 5 },
    },
}

------------------------------------------------------------------------
-- 玩家存档数据初始值
------------------------------------------------------------------------
function MD.NewSaveData()
    return {
        -- 货币
        gold = 500,
        diamond = 4000,
        wood = 30,
        stone = 20,

        -- 关卡进度
        maxLevel = 1,       -- 已解锁最高关卡（第1关默认解锁）
        levelStars = {},    -- 每关星数 {[1]=3, [2]=2, ...}
        chestClaimed = {},  -- 已领取宝箱 {["1_1"]=true, ["1_2"]=true} 键="关卡_宝箱序号"

        -- 装备（inventory 存实例对象，含随机词条）
        equipped = {},      -- {weapon=1, hat=2, ...} 槽位 -> inventory索引
        inventory = {       -- 背包装备实例
            { id = "knife_basic",   level = 1, affixes = { {affixId = "meleeAtk", grade = 1} } },
            { id = "common_head",   level = 1, affixes = { {affixId = "hp", grade = 1} } },
            { id = "common_body",   level = 1, affixes = { {affixId = "def", grade = 2} } },
            { id = "common_boots",  level = 1, affixes = { {affixId = "atkSpd", grade = 1}, {affixId = "goldBonus", grade = 2} } },
            { id = "bat",           level = 3, affixes = { {affixId = "meleeAtk", grade = 2} } },
            { id = "pistol",        level = 5, affixes = { {affixId = "critRate", grade = 3}, {affixId = "rangedAtk", grade = 2} } },
            { id = "katana",        level = 8, affixes = { {affixId = "critDmg", grade = 4}, {affixId = "meleeAtk", grade = 3} } },
            { id = "akm",           level = 12, affixes = { {affixId = "critRate", grade = 5}, {affixId = "critDmg", grade = 5}, {affixId = "atkPct", grade = 4} } },
            { id = "xmas_revolver", level = 15, affixes = { {affixId = "critRate", grade = 5}, {affixId = "critDmg", grade = 5}, {affixId = "atkPct", grade = 5} } },
            { id = "overlord_necklace", level = 6, affixes = { {affixId = "hp", grade = 3}, {affixId = "def", grade = 3} } },
            { id = "doomforge_ring", level = 10, affixes = { {affixId = "atkSpd", grade = 5}, {affixId = "critRate", grade = 4} } },
            { id = "xmas_head",     level = 4, affixes = { {affixId = "hp", grade = 2}, {affixId = "def", grade = 2} } },
            { id = "xmas_armor",    level = 15, affixes = { {affixId = "def", grade = 5}, {affixId = "hp", grade = 5} } },
            { id = "xmas_boots",    level = 7, affixes = { {affixId = "atkSpd", grade = 3} } },
        },

        -- 角色
        activeChar = "warrior",                     -- 当前使用的角色id
        unlockedChars = { warrior = true, auntie = true, lisanguang = true, weifenglong = true },  -- 已解锁角色
        charFrags = { warrior = 1, auntie = 1, lisanguang = 1, weifenglong = 1 },          -- 角色碎片数 {charId = count}
        charStars = { warrior = 1, auntie = 1, lisanguang = 1, weifenglong = 1 },           -- 角色星级 {charId = star}

        -- 天赋等级（线性50级）
        talentLevel = 0,    -- 当前已解锁到的天赋等级（0-50）

        -- 炮塔碎片 & 等级
        turretFrags = {},   -- {arrow=0, minigun=0, ...}
        turretLevels = {},  -- {arrow=1, minigun=0, ...}

        -- 炮塔装备（4个槽位，默认装备弓箭/机枪/狙击/火箭）
        turretEquipped = {"arrow", "minigun", "sniper", "rocket"},
        -- 已解锁的炮塔
        turretUnlocked = {arrow = true, minigun = true, sniper = true, rocket = true},

        -- 商城
        dailyBought = {},   -- 今日已买的daily商品id
        dailyPicks = {},    -- 今日随机商品id列表（5个）
        lastDailyReset = 0, -- 上次daily重置时间戳

        -- 充值钻石冷却（os.time 时间戳，0=立即可用）
        rechargeOnceTime = 0,   -- 上次充值一次的时间
        rechargeTenTime = 0,    -- 上次充值十次的时间

        -- 钻石抽奖等级
        gachaLevel = 1,         -- 抽奖等级 1~20
        gachaExp = 0,           -- 当前经验值

        -- 玩家信息
        playerName = "幸存者",
        playerLevel = 1,

        -- 7日签到
        signInDay = 0,          -- 已签到天数(0~7)
        signInLastDate = "",    -- 上次签到日期字符串 "YYYY-MM-DD"

        -- 邮件状态
        mailRead    = {},       -- {["mail_id"]=true} 已读邮件
        mailClaimed = {},       -- {["mail_id"]=true} 已领取附件的邮件
    }
end

return MD
