------------------------------------------------------------------------
-- Audio.lua  —— 游戏音频系统
-- BGM 切换 + SFX 播放 + 音量/静音控制
------------------------------------------------------------------------
local A = {}

-- 音频 Scene & 节点（挂载 SoundSource 组件）
---@type Scene
local audioScene = nil
---@type Node
local bgmNode = nil
---@type Node
local sfxNode = nil
---@type SoundSource
local bgmSource = nil

-- 当前正在播放的 BGM 路径
local currentBGM = ""

-- 音量 & 开关（外部通过 A.SetVolume/A.SetMute 更新）
local bgmVolume = 0.1
local bgmOn = true
local sfxVolume = 0.5
local sfxOn = true

-- 音效增益倍率（源文件音量偏小，用此倍率补偿）
local SFX_GAIN_BOOST = 3.0

-- BGM 资源路径
A.BGM_TITLE    = "audio/music_1780570668136.ogg"   -- 标题画面
A.BGM_LOBBY    = "audio/music_1780570305080.ogg"   -- 局外大厅
A.BGM_BATTLE   = "audio/music_1780570378032.ogg"   -- 战斗中
A.BGM_VICTORY  = "audio/music_1780570738287.ogg"   -- 胜利
A.BGM_GAMEOVER = "audio/music_1780570804868.ogg"   -- 失败

-- SFX 资源路径（新音效）
A.SFX_BTN_CLICK       = "audio/火车音效/点击1.ogg"
A.SFX_EQUIP_ATTACH    = "audio/sfx/equip_attach.ogg"
A.SFX_GACHA_SPIN      = "audio/sfx/gacha_spin_v2.ogg"
A.SFX_GACHA_CLICK     = "audio/火车音效/抽卡2.ogg"    -- 抽卡按钮点击
A.SFX_UPGRADE         = "audio/火车音效/升级.ogg"     -- 火车升级

-- 炮塔音效
A.SFX_TURRET_ARROW    = "audio/火车音效/弓箭炮塔发射.ogg"
A.SFX_TURRET_SNIPER   = "audio/火车音效/狙击.ogg"
A.SFX_TURRET_FLAME    = "audio/火车音效/喷火炮塔.ogg"
A.SFX_TURRET_ELECTRIC = "audio/火车音效/电能.ogg"
A.SFX_TURRET_ROCKET   = "audio/火车音效/火箭发射.ogg"
A.SFX_TURRET_MINIGUN  = "audio/火车音效/机枪.ogg"
A.SFX_ROCKET_EXPLODE  = "audio/火车音效/炸弹爆炸.ogg"  -- 火箭爆炸
A.SFX_LASER_SKILL     = "audio/火车音效/激光技能音效.ogg" -- 狙击激光升级

-- 角色技能音效
A.SFX_SKILL_BOMB    = "audio/sfx/skill_bomb.ogg"
A.SFX_SKILL_HEAL    = "audio/sfx/skill_heal.ogg"
A.SFX_SKILL_BERSERK = "audio/sfx/skill_berserk.ogg"
A.SFX_SKILL_DASH    = "audio/sfx/skill_dash.ogg"

-- 局内交互音效
A.SFX_CHOP_1     = "audio/火车音效/砍1.ogg"
A.SFX_CHOP_2     = "audio/火车音效/砍2.ogg"
A.SFX_CHOP_BREAK = "audio/火车音效/砍破.ogg"
A.SFX_MINE_ORE   = "audio/火车音效/挖钻石.ogg"      -- 挖钻石类资源
A.SFX_MINE_STONE = "audio/火车音效/挖石头.ogg"      -- 挖石头类资源
A.SFX_HIT_ZOMBIE = "audio/火车音效/砍怪物.ogg"      -- 近战攻击僵尸
A.SFX_KILL_ZOMBIE    = "audio/火车音效/砍怪物砍死.ogg"  -- 最后一下砍死僵尸
A.SFX_STONE_BREAK    = "audio/火车音效/钻石和石头破.ogg" -- 钻石/石头类资源砍破
A.SFX_THROW_RES      = "audio/火车音效/丢资源.ogg"      -- 收集资源后丢给火车

-- 炮塔类型 → SFX 映射
A.TURRET_SFX = {
    arrow    = A.SFX_TURRET_ARROW,
    sniper   = A.SFX_TURRET_SNIPER,
    flame    = A.SFX_TURRET_FLAME,
    electric = A.SFX_TURRET_ELECTRIC,
    rocket   = A.SFX_TURRET_ROCKET,
    minigun  = A.SFX_TURRET_MINIGUN,
}

-- SFX 缓存（避免重复 GetResource）
local sfxCache = {}

-- 喷火炮塔循环音效追踪
local flameLoopSources = {}  -- turret → SoundSource

-- 抽卡音效追踪（用于跳过时停止）
local gachaClickSource = nil

------------------------------------------------------------------------
-- 初始化（在 Start() 中调用一次）
------------------------------------------------------------------------
function A.Init()
    -- 创建专用于音频的轻量 Scene（纯 NanoVG 游戏没有 3D scene）
    audioScene = Scene()
    audioScene:CreateComponent("Octree")

    -- 创建 BGM 播放节点
    bgmNode = audioScene:CreateChild("BGMNode")
    bgmSource = bgmNode:CreateComponent("SoundSource")
    bgmSource.soundType = "Music"
    bgmSource.gain = bgmVolume

    -- 创建 SFX 播放节点
    sfxNode = audioScene:CreateChild("SFXNode")

    -- 预加载 SFX 到缓存
    local sfxPaths = {
        A.SFX_BTN_CLICK,
        A.SFX_EQUIP_ATTACH,
        A.SFX_GACHA_SPIN,
        A.SFX_GACHA_CLICK,
        A.SFX_UPGRADE,
        A.SFX_TURRET_ARROW,
        A.SFX_TURRET_SNIPER,
        A.SFX_TURRET_FLAME,
        A.SFX_TURRET_ELECTRIC,
        A.SFX_TURRET_ROCKET,
        A.SFX_TURRET_MINIGUN,
        A.SFX_ROCKET_EXPLODE,
        A.SFX_LASER_SKILL,
        A.SFX_CHOP_1,
        A.SFX_CHOP_2,
        A.SFX_CHOP_BREAK,
        A.SFX_MINE_ORE,
        A.SFX_MINE_STONE,
        A.SFX_HIT_ZOMBIE,
        A.SFX_KILL_ZOMBIE,
        A.SFX_STONE_BREAK,
        A.SFX_THROW_RES,
    }
    for _, path in ipairs(sfxPaths) do
        local snd = cache:GetResource("Sound", path)
        if snd then
            snd.looped = false
            sfxCache[path] = snd
        else
            print("[Audio] WARNING: Failed to load SFX: " .. path)
        end
    end

    -- 预加载喷火炮塔循环音效（设置 looped）
    local flameSnd = cache:GetResource("Sound", A.SFX_TURRET_FLAME)
    if flameSnd then
        -- 保留一个 looped 版本用于循环播放
        sfxCache["flame_loop"] = flameSnd
    end

    print("[Audio] Initialized")
end

------------------------------------------------------------------------
-- BGM 控制
------------------------------------------------------------------------

--- 播放 BGM（如果与当前相同则不重新播放）
function A.PlayBGM(path)
    if not path or path == "" then return end
    if path == currentBGM and bgmSource:IsPlaying() then return end

    if not bgmOn then
        currentBGM = path
        return
    end

    local snd = cache:GetResource("Sound", path)
    if snd then
        -- 胜利/失败音乐不循环，其他 BGM 循环
        if path == A.BGM_VICTORY or path == A.BGM_GAMEOVER then
            snd.looped = false
        else
            snd.looped = true
        end
        bgmSource:Play(snd)
        bgmSource.gain = bgmVolume
        currentBGM = path
        print("[Audio] BGM → " .. path)
    else
        print("[Audio] WARNING: Failed to load BGM: " .. path)
    end
end

--- 停止 BGM
function A.StopBGM()
    if bgmSource then
        bgmSource:Stop()
    end
    currentBGM = ""
end

--- 获取当前 BGM 路径
function A.GetCurrentBGM()
    return currentBGM
end

------------------------------------------------------------------------
-- SFX 控制
------------------------------------------------------------------------

--- 播放音效
function A.PlaySFX(path)
    if not sfxOn or not path or path == "" then return end
    local snd = sfxCache[path]
    if not snd then
        snd = cache:GetResource("Sound", path)
        if snd then
            snd.looped = false
            sfxCache[path] = snd
        end
    end
    if snd then
        local src = sfxNode:CreateComponent("SoundSource")
        src.soundType = "Effect"
        src.gain = sfxVolume * SFX_GAIN_BOOST
        src.autoRemoveMode = REMOVE_COMPONENT
        src:Play(snd)
        return src
    end
    return nil
end

--- 播放按钮点击音效
function A.PlayClick()
    A.PlaySFX(A.SFX_BTN_CLICK)
end

--- 炮塔音效节流：高频炮塔限制播放间隔，避免叠加噪音
local turretSfxCooldown = {}  -- typeKey → 下次允许播放的时间戳
local TURRET_SFX_MIN_INTERVAL = {
    arrow    = 0.4,   -- 弓箭：最快 0.4 秒一次
    sniper   = 0.6,   -- 狙击：最快 0.6 秒一次
    flame    = 0.8,   -- 火焰：最快 0.8 秒一次
    minigun  = 0.08,  -- 机枪：每发子弹都播放
    electric = 0.8,   -- 电能：最快 0.8 秒一次
    rocket   = 0.5,   -- 火箭：最快 0.5 秒一次
}

--- 播放炮塔开火音效（带节流）
function A.PlayTurretFire(typeKey)
    -- 喷火炮塔使用循环音效，不走单次播放
    if typeKey == "flame" then return end

    local path = A.TURRET_SFX[typeKey]
    if not path then return end

    -- 检查节流
    local minInterval = TURRET_SFX_MIN_INTERVAL[typeKey] or 0.5
    local now = time.elapsedTime
    local nextAllowed = turretSfxCooldown[typeKey] or 0
    if now < nextAllowed then return end
    turretSfxCooldown[typeKey] = now + minInterval

    A.PlaySFX(path)
end

--- 播放火箭爆炸音效
function A.PlayRocketExplode()
    A.PlaySFX(A.SFX_ROCKET_EXPLODE)
end

--- 播放狙击激光技能音效
function A.PlayLaserSkill()
    A.PlaySFX(A.SFX_LASER_SKILL)
end

--- 播放火车升级音效
function A.PlayUpgrade()
    A.PlaySFX(A.SFX_UPGRADE)
end

------------------------------------------------------------------------
-- 喷火炮塔循环音效
------------------------------------------------------------------------

--- 开始喷火循环音效（每个炮塔只创建一个循环源）
function A.StartFlameLoop(turret)
    if not sfxOn then return end
    if flameLoopSources[turret] then return end  -- 已在播放

    local snd = cache:GetResource("Sound", A.SFX_TURRET_FLAME)
    if snd then
        snd.looped = true
        local src = sfxNode:CreateComponent("SoundSource")
        src.soundType = "Effect"
        src.gain = sfxVolume * SFX_GAIN_BOOST
        src:Play(snd)
        flameLoopSources[turret] = src
    end
end

--- 停止喷火循环音效
function A.StopFlameLoop(turret)
    local src = flameLoopSources[turret]
    if src then
        src:Stop()
        sfxNode:RemoveComponent(src)
        flameLoopSources[turret] = nil
    end
end

--- 停止所有喷火循环（场景结束时调用）
function A.StopAllFlameLoops()
    for turret, src in pairs(flameLoopSources) do
        if src then
            src:Stop()
            sfxNode:RemoveComponent(src)
        end
    end
    flameLoopSources = {}
end

------------------------------------------------------------------------
-- 抽卡音效
------------------------------------------------------------------------

--- 播放抽卡点击音效（可被跳过停止）
function A.PlayGachaClick()
    -- 停止之前的抽卡点击音效
    A.StopGachaClick()
    local src = A.PlaySFX(A.SFX_GACHA_CLICK)
    if src then
        gachaClickSource = src
    end
end

--- 停止抽卡点击音效（跳过时调用）
function A.StopGachaClick()
    if gachaClickSource then
        gachaClickSource:Stop()
        gachaClickSource = nil
    end
end

------------------------------------------------------------------------
-- 局内交互音效
------------------------------------------------------------------------

--- 局内交互音效节流
local interactSfxCooldown = {}  -- key → 下次允许时间
local INTERACT_SFX_INTERVAL = 0.3  -- 最快 0.3 秒一次

--- 播放局内交互音效（带节流）
local function playInteractSFX(path, key)
    local now = time.elapsedTime
    local nextAllowed = interactSfxCooldown[key] or 0
    if now < nextAllowed then return end
    interactSfxCooldown[key] = now + INTERACT_SFX_INTERVAL
    A.PlaySFX(path)
end

--- 播放砍树音效（砍1和砍2随机）
function A.PlayChopTree()
    local path = math.random(2) == 1 and A.SFX_CHOP_1 or A.SFX_CHOP_2
    playInteractSFX(path, "chop")
end

--- 播放砍破音效（资源最后一下破碎）
function A.PlayChopBreak()
    A.PlaySFX(A.SFX_CHOP_BREAK)
end

--- 播放挖矿音效
function A.PlayMineOre()
    playInteractSFX(A.SFX_MINE_ORE, "ore")
end

--- 播放挖石头音效
function A.PlayMineStone()
    playInteractSFX(A.SFX_MINE_STONE, "stone")
end

--- 播放攻击僵尸音效
function A.PlayHitZombie()
    playInteractSFX(A.SFX_HIT_ZOMBIE, "hit")
end

--- 播放砍死僵尸音效（最后一下）
function A.PlayKillZombie()
    A.PlaySFX(A.SFX_KILL_ZOMBIE)
end

--- 播放钻石/石头类资源砍破音效（最后一下）
function A.PlayStoneBreak()
    A.PlaySFX(A.SFX_STONE_BREAK)
end

--- 播放丢资源音效（提交资源到火车）
function A.PlayThrowRes()
    A.PlaySFX(A.SFX_THROW_RES)
end

--- 播放装备音效
function A.PlayEquip()
    A.PlaySFX(A.SFX_EQUIP_ATTACH)
end

--- 播放抽卡音效（旧接口兼容）
function A.PlayGacha()
    A.PlaySFX(A.SFX_GACHA_SPIN)
end

--- 角色技能音效（按角色 id 播放）
local SKILL_SFX_MAP = {
    warrior      = "audio/sfx/skill_bomb.ogg",
    auntie       = "audio/sfx/skill_heal.ogg",
    lisanguang   = "audio/sfx/skill_berserk.ogg",
    weifenglong  = "audio/sfx/skill_dash.ogg",
}

function A.PlaySkill(charId)
    local path = SKILL_SFX_MAP[charId]
    if path then A.PlaySFX(path) end
end

------------------------------------------------------------------------
-- 音量/静音设置
------------------------------------------------------------------------

function A.SetBGMVolume(vol)
    bgmVolume = vol
    if bgmSource then
        bgmSource.gain = bgmVolume
    end
end

function A.SetSFXVolume(vol)
    sfxVolume = vol
    -- 更新所有正在循环的喷火音效增益
    for _, src in pairs(flameLoopSources) do
        if src then src.gain = sfxVolume * SFX_GAIN_BOOST end
    end
end

function A.SetBGMOn(on)
    bgmOn = on
    if not on then
        if bgmSource then bgmSource:Stop() end
    else
        -- 恢复播放当前 BGM
        if currentBGM ~= "" then
            local snd = cache:GetResource("Sound", currentBGM)
            if snd then
                if currentBGM == A.BGM_VICTORY or currentBGM == A.BGM_GAMEOVER then
                    snd.looped = false
                else
                    snd.looped = true
                end
                bgmSource:Play(snd)
                bgmSource.gain = bgmVolume
            end
        end
    end
end

function A.SetSFXOn(on)
    sfxOn = on
    -- 关闭音效时停止所有循环音效
    if not on then
        A.StopAllFlameLoops()
    end
end

--- 上次同步的值（用于变化检测，避免每帧重复触发）
local lastSyncBgmVol = nil
local lastSyncSfxVol = nil
local lastSyncBgmOn  = nil
local lastSyncSfxOn  = nil

--- 从外部设置同步音量（由 settings popup 调用，每帧安全）
function A.SyncSettings(settings)
    if settings.bgmVolume ~= nil and settings.bgmVolume ~= lastSyncBgmVol then
        lastSyncBgmVol = settings.bgmVolume
        A.SetBGMVolume(settings.bgmVolume)
    end
    if settings.sfxVolume ~= nil and settings.sfxVolume ~= lastSyncSfxVol then
        lastSyncSfxVol = settings.sfxVolume
        A.SetSFXVolume(settings.sfxVolume)
    end
    if settings.bgmOn ~= nil and settings.bgmOn ~= lastSyncBgmOn then
        lastSyncBgmOn = settings.bgmOn
        A.SetBGMOn(settings.bgmOn)
    end
    if settings.sfxOn ~= nil and settings.sfxOn ~= lastSyncSfxOn then
        lastSyncSfxOn = settings.sfxOn
        A.SetSFXOn(settings.sfxOn)
    end
end

return A
