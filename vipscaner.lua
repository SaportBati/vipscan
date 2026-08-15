script_name('VIPScanner')
script_author('Nehto_Otto')

require 'lib.moonloader'
require 'lib.sampfuncs'

local encoding = require "encoding"
encoding.default = 'CP1251'
u8 = encoding.UTF8

local sampev, imgui = require 'samp.events', require 'mimgui'
local new = imgui.new

-- ==================== chat_emoji integration ====================
-- Библиотека рендерит текстовые emoji-коды (:name: и текстовые смайлы вроде :) )
-- прямо в тексте mimgui картинками. Файлы подкачиваются автоматически при первом запуске,
-- ссылки и логика загрузки взяты из примера использования библиотеки.
local VIP_CHAT_EMOJI_FILES = {
    { url = 'https://raw.githubusercontent.com/Levushkins/mimgui-chat-emoji/main/moonloader/lib/chat_emoji.lua', path = 'lib/chat_emoji.lua' },
    { url = 'https://raw.githubusercontent.com/Levushkins/mimgui-chat-emoji/main/moonloader/resource/chat_emoji/chat_emoji.png', path = 'resource/chat_emoji/chat_emoji.png' },
    { url = 'https://raw.githubusercontent.com/Levushkins/mimgui-chat-emoji/main/moonloader/resource/chat_emoji/chat_emoji_atlas.lua', path = 'resource/chat_emoji/chat_emoji_atlas.lua' }
}

local VIP_CHAT_EMOJI_SYMBOLS = {
    [':d'] = 'grinning', [':D'] = 'grinning', [':-d'] = 'grinning', [':-D'] = 'grinning',
    [':-)'] = 'smiley', [':)'] = 'smiley', ['^_^'] = 'blush', ['<3'] = 'heart',
    [':('] = 'frowning', [';)'] = 'wink', ['xd'] = 'laughing', ['xD'] = 'laughing', ['XD'] = 'laughing'
}

local vipChatEmoji, vipChatEmojiLibLoaded, vipChatEmojiTexLoaded = nil, false, false

local function vipChatEmojiFileSize(path)
    local f = io.open(path, 'rb')
    if not f then return 0 end
    local size = f:seek('end')
    f:close()
    return size
end

-- скачивает файлы библиотеки chat_emoji, если их ещё нет или они битые (логика 1:1 из примера библиотеки)
local function vipDownloadChatEmojiFiles()
    createDirectory(getWorkingDirectory() .. '/resource')
    createDirectory(getWorkingDirectory() .. '/resource/chat_emoji')

    for _, file in ipairs(VIP_CHAT_EMOJI_FILES) do
        local fullPath = getWorkingDirectory() .. '/' .. file.path
        if not doesFileExist(fullPath) or vipChatEmojiFileSize(fullPath) < 500 then
            local done = false
            downloadUrlToFile(file.url, fullPath, function(id, status)
                if status == 6 or status == 3 then done = true end
            end)
            local timeout = os.clock() + 10
            while not done and os.clock() < timeout do wait(100) end
        end
    end
end

-- подкачивает и подключает библиотеку chat_emoji (вызывается один раз из main())
function vipSetupChatEmojiLib()
    vipDownloadChatEmojiFiles()

    package.loaded['chat_emoji'] = nil
    local ok, lib = pcall(require, 'chat_emoji')
    if ok and lib then
        vipChatEmoji = lib
        vipChatEmojiLibLoaded = true
    else
        vipChatEmoji = nil
        vipChatEmojiLibLoaded = false
        sampAddChatMessage('[VIP] {FF0000}Не удалось подключить библиотеку chat_emoji: ' .. tostring(lib), 0xFF0000)
    end
end

-- преобразует текстовые emoji-коды (текст уже в UTF8) в токены, которые понимает vipChatEmoji.text()
local function vipProcessChatEmoji(utf8Text)
    if not vipChatEmoji or not vipChatEmojiTexLoaded or not utf8Text or utf8Text == '' then
        return utf8Text
    end

    local result = utf8Text

    result = result:gsub(':([%w_%-]+):', function(name)
        local item = vipChatEmoji.get(name) or vipChatEmoji.get(':' .. name .. ':')
        if item then
            return vipChatEmoji.encode(item)
        end
        return ':' .. name .. ':'
    end)

    for sym, target in pairs(VIP_CHAT_EMOJI_SYMBOLS) do
        local item = vipChatEmoji.get(target) or vipChatEmoji.get(sym)
        if item then
            local token = vipChatEmoji.encode(item)
            if token then
                local pattern = sym:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1')
                result = result:gsub(pattern, token)
            end
        end
    end

    return result
end

-- отрисовывает обычный (не мат/не капс) фрагмент текста сообщения чата, прогоняя его через chat_emoji.
-- Именно через эту функцию проходит весь "чистый" текст сообщений в окне VIP-истории.
local function vipDrawPlainTextWithChatEmoji(plainText, r, g, b)
    local utf8Text = u8(plainText)
    if vipChatEmoji and vipChatEmojiTexLoaded then
        local processed = vipProcessChatEmoji(utf8Text)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(r, g, b, 1))
        local ok = pcall(vipChatEmoji.text, processed, imgui.GetTextLineHeight())
        imgui.PopStyleColor(1)
        if not ok then
            imgui.TextColored(imgui.ImVec4(r, g, b, 1), utf8Text)
        end
    else
        imgui.TextColored(imgui.ImVec4(r, g, b, 1), utf8Text)
    end
end
-- ================== /chat_emoji integration ==================

local ffi = require 'ffi'
local effilOk, effil = pcall(require, 'effil')
if not effilOk then effil = nil end

local ffiDirOk = pcall(ffi.cdef, [[
    int CreateDirectoryA(const char* lpPathName, void* lpSecurityAttributes);
]])
local kernel32Dir = ffiDirOk and ffi.load('kernel32') or nil

local function vipMkDir(path)
    if kernel32Dir then
        kernel32Dir.CreateDirectoryA(path, nil)
    end
end

local VIP_LOG_DIR = getWorkingDirectory() .. '\\MatDetector_VIP'
vipMkDir(VIP_LOG_DIR)
local VIP_CHAT_DIR = VIP_LOG_DIR .. '\\VipChat'
vipMkDir(VIP_CHAT_DIR)
local VIP_LOG_FILE = VIP_CHAT_DIR .. '\\vip_' .. os.date('%Y-%m-%d_%H-%M-%S') .. '.txt'

local VIP_PREFIXES = {'[VIP ADV]', '[FOREVER]', '[ADMIN]', '[VIP]', '[PREMIUM]', ':u1fc28:', ':u1fc29:', ':u1fc30:', ':u1fc31:', ':u1fc32:', ':u1fc33:', ':u1fc36:', ':u1fc37:', ':u1fc38:', ':u1fc2f:', ':u1fc2d:', ':u1fc2a:', ':u1fc2b:', ':u1fc2c:'}

local EMOJI_TAGS_RAW = {}

local SETTINGS_FILE = VIP_LOG_DIR .. '\\settings.txt'

local EMOJI_TAGS = {}
for _, tag in ipairs(EMOJI_TAGS_RAW) do
    local name = tag:match("^:([%w_]+):$")
    if name then
        table.insert(EMOJI_TAGS, {tag = tag, name = name})
    end
end

local emojiTextures = {}
local VIP_IMG_DATA = {
}

local VIP_IMG_URL, VIP_IMG_TMP_FILE = 'https://gitverse.ru/api/repos/Nehto/VipScaner/raw/branch/master/img.txt', VIP_LOG_DIR .. '\\img_tmp.txt'
local VIP_WORDS_URL, BAD_WORDS_FILE, badWords, VIP_WHITELIST_URL = 'https://gitverse.ru/api/repos/Nehto/VipScaner/raw/branch/master/words.txt', VIP_LOG_DIR .. '\\words.txt', {}, 'https://gitverse.ru/api/repos/Nehto/VipScaner/raw/branch/master/whitelist.txt'
local VIP_ITEMS_API_URL, VIP_ITEM_ICON_BASE_URL, ITEMS_CACHE_FILE, VIP_ITEM_TMP_DIR = 'https://items.shinoa.tech/items.php', 'https://cdn.azresources.cloud/projects/arizona-rp/assets/images/donate/', VIP_LOG_DIR .. '\\items_cache.txt', VIP_LOG_DIR .. '\\itemstmp'
vipMkDir(VIP_ITEM_TMP_DIR)
local VIP_ITEM_FALLBACK_BASE_URL = 'https://gitverse.ru/api/repos/Nehto/VipScaner/raw/branch/master/img/'

VIP_SCR = {
    HISTORY_FILE = VIP_LOG_DIR .. '\\screenshots.txt',
    SEARCH_MAX_DEPTH = 8,
    SEARCH_MAX_DIRS = 30000,
    POLL_INTERVAL = 100,
    MAX_WAIT = 4000,
    list = {},
    windowOpen = new.bool(false),
    freeimageApiKey = nil, -- ключ freeimage.host, подгружается автоматически при каждом запуске скрипта
    uploadChannels = {},
    cachedRootPath = nil,
}

local itemNames, itemFetchPending, itemIconTextures = {}, {}, {}

local vipFetchItemName, vipFetchItemIcon

local CAPS_MIN_LEN = 3

local FLOOD_WINDOW_SEC, FLOOD_MAX_MSGS, floodHistory = 10, 3, {}

local MAT_WINDOW_MSGS, MAT_TRIGGER_COUNT, matHistory = 3, 3, {}

local TRADE_WORDS_RAW = {
    'продам', 'куплю', 'продажа', 'покупка', 'сдам', 'возьму',
    'отдам', 'приобрету', 'скупка', 'обмен', 'аренда', 'выкуп'
}
local TRADE_EXCLUDED_PREFIXES, TRADE_HIGHLIGHT_COLOR, TRADE_WORDS =
    {['[ADMIN]'] = true, ['[VIP ADV]'] = true, [':u1fc29:'] = true, [':u1fc28:'] = true, [':u1fc36:'] = true, [':u1fc38:'] = true, [':u1fc2a:'] = true, [':u1fc2b:'] = true, [':u1fc2c:'] = true, [':u1fc2d:'] = true}, 'FFA500', {}

local BAD_WORD_COLOR, CAPS_COLOR, FLOOD_COLOR, MATWINDOW_COLOR = 'FF0000', 'FF0000', 'FF0000', 'FF0000'

local WHITELIST_FILE, whitelist = VIP_LOG_DIR .. '\\whitelist.txt', {}

local FLOOD_WHITELIST_FILE, floodWhitelist = VIP_LOG_DIR .. '\\flood_whitelist.txt', {}

local vipWindowOpen, vipLines, vipAllLines, vipCurrentFilter, vipDeleteConfirmEntry, vipViewingFile =
    new.bool(false), {}, {}, nil, nil, nil

local avipWindowOpen = new.bool(false)
local vipAvipUI = {activeSection = 'colors'}

local punNameBuf, punTimeBuf, punReasonBuf, punTypeIdx =
    new.char[128](""), new.char[32](""), new.char[256](""), new.int(0)

local PUN = {
    windowOpen = new.bool(false),
    targetOverride = nil,
    lastMainPos = {x = 140, y = 140},
    lastPunPos = {x = 140, y = 140},
    lastPunSize = {x = 260, y = 40},
    applyTypeIdx = new.int(0),
    applyTimeBuf = new.char[32](""),
    applyReasonBuf = new.char[256](""),
    customWindowOpen = new.bool(false),
    confirmPending = nil,
    confirmOpened = false,
}

local PUN_HIST = {
    windowOpen = new.bool(false),
    nick = nil,
    lines = {},
    title = 'История наказаний',
    windowSec = 7 * 24 * 3600,
    checkCooldown = 5,
    lastCheckTime = -math.huge,
    pendingNick = nil,
    matchWindow = 0.5,
}

VIP_NOTIFY = {
    active = false,
    nick = nil,
    untilClock = 0,
    enterWasDown = false,
    user32 = nil,
    holdSec = 10,
}

pcall(ffi.cdef, [[
    short GetAsyncKeyState(int vKey);
]])

function vipGetUser32ForKeys()
    if VIP_NOTIFY.user32 == nil then
        local ok, user32 = pcall(ffi.load, 'user32')
        VIP_NOTIFY.user32 = ok and user32 or false
    end
    return VIP_NOTIFY.user32 or nil
end

function vipIsKeyDownNow(vk)
    local user32 = vipGetUser32ForKeys()
    if not user32 then return false end
    local ok, state = pcall(function() return user32.GetAsyncKeyState(vk) end)
    if not ok or not state then return false end
    return tonumber(state) < 0
end

-- проверяет, открыт ли сейчас какой-либо интерфейс SAMP (ввод чата, диалог, скорборд, курсор),
-- чтобы не перехватывать Enter, когда игрок печатает сообщение или взаимодействует с другим окном
function vipIsAnyGameInterfaceActive()
    local checkFuncNames = {
        'sampIsChatInputActive',
        'sampIsDialogActive',
        'sampIsScoreboardOpen',
        'sampIsCursorActive',
    }
    for _, fname in ipairs(checkFuncNames) do
        local fn = _G[fname]
        if fn then
            local ok, active = pcall(fn)
            if ok and active then
                return true
            end
        end
    end
    return false
end

function vipShowViolationNotify(nick)
    if not nick or nick == '' then return end
    VIP_NOTIFY.nick = nick
    VIP_NOTIFY.untilClock = os.clock() + VIP_NOTIFY.holdSec
    VIP_NOTIFY.active = true

    VIP_NOTIFY.enterWasDown = vipIsKeyDownNow(0x0D)
end

local PUNISHMENT_TYPES_RAW, PUNISHMENT_TYPES_U8 = {'Ban', 'Mute', 'Rmute', 'Jail', 'Custom'}, {}
for i, t in ipairs(PUNISHMENT_TYPES_RAW) do PUNISHMENT_TYPES_U8[i] = u8(t) end

local vipPunishments = {}

local uiColorBadWord, uiColorCaps, uiColorTrade, uiColorFlood, uiColorMatWindow
local uiFloodWindow, uiFloodMax, uiMatWindow, uiMatTrigger, uiCapsMin
uiTheme = {}

local VIP_FONT_SIZE, VIP_FONT_UI_SIZE, vipFontLarge, vipFontUI = 14, 20, nil, nil

local VIP_FONT_TTF_URL, VIP_FONT_TTF_PATH, vipFontUiWarned =
    'https://gitverse.ru/api/repos/Nehto/VipScaner/raw/branch/master/vipscaner.ttf',
    VIP_LOG_DIR .. '\\vipscaner.ttf',
    false

local vipLastFrameClock, vipDeltaTime, vipAnimValues = os.clock(), 0, {}

local function vipLerp(a, b, t)
    return a + (b - a) * t
end

local function vipAnimate(key, target, speed)
    speed = speed or 10
    local cur = vipAnimValues[key]
    if cur == nil then
        vipAnimValues[key] = target
        return target
    end
    local t = 1 - math.exp(-speed * vipDeltaTime)
    if t > 1 then t = 1 elseif t < 0 then t = 0 end
    cur = vipLerp(cur, target, t)
    if math.abs(cur - target) < 0.002 then cur = target end
    vipAnimValues[key] = cur
    return cur
end

local function vipPackColor(r, g, b, a)
    local function to255(v)
        v = math.floor((v or 0) * 255 + 0.5)
        if v < 0 then v = 0 elseif v > 255 then v = 255 end
        return v
    end
    if a == nil then a = 1 end
    return (to255(a) * 0x1000000) + (to255(b) * 0x10000) + (to255(g) * 0x100) + to255(r)
end

local VIP_ACCENT, VIP_ACCENT2, VIP_SUCCESS, VIP_DANGER, VIP_WARNING =
    {0.40, 0.62, 1.00}, {0.62, 0.48, 1.00}, {0.30, 0.78, 0.58}, {0.92, 0.30, 0.34}, {0.92, 0.65, 0.28}

VIP_DEFAULT_THEME = {
    accent = {0.40, 0.62, 1.00},
}

-- подмешивает текущий акцентный цвет темы (VIP_ACCENT) в базовый тёмный цвет фона
function vipTintBg(baseR, baseG, baseB, tintAmount)
    tintAmount = tintAmount or 0.07
    local ax, ay, az = VIP_ACCENT[1], VIP_ACCENT[2], VIP_ACCENT[3]
    return
        baseR + (ax - baseR) * tintAmount,
        baseG + (ay - baseG) * tintAmount,
        baseB + (az - baseB) * tintAmount
end

local function vipHoverHighlight(rounding)
    if imgui.IsItemHovered() then
        local dl, rmin, rmax = imgui.GetWindowDrawList(), imgui.GetItemRectMin(), imgui.GetItemRectMax()
        dl:AddRectFilled(rmin, rmax, vipPackColor(1, 1, 1, 0.10), rounding or 4)
    end
end

local function vipSelectable(label, ...)
    local clicked = imgui.Selectable(label, ...)
    vipHoverHighlight(4)
    return clicked
end

local function vipAnimatedButton(id, label, w, h, baseCol, hoverCol, activeCol)
    local hoverKey, activeKey = 'btn_h_' .. id, 'btn_a_' .. id
    local ht, at = vipAnimValues[hoverKey] or 0, vipAnimValues[activeKey] or 0
    local r, g, b =
        vipLerp(vipLerp(baseCol[1], hoverCol[1], ht), activeCol[1], at), vipLerp(vipLerp(baseCol[2], hoverCol[2], ht), activeCol[2], at), vipLerp(vipLerp(baseCol[3], hoverCol[3], ht), activeCol[3], at)
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(r, g, b, 1))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(r, g, b, 1))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(r, g, b, 1))
    local clicked = imgui.Button(label .. '##' .. id, imgui.ImVec2(w, h))
    vipHoverHighlight(imgui.GetStyle().FrameRounding)
    imgui.PopStyleColor(3)
    vipAnimate(hoverKey, imgui.IsItemHovered() and 1 or 0, 10)
    vipAnimate(activeKey, imgui.IsItemActive() and 1 or 0, 16)
    return clicked
end

local vipFontUiLoaded = false

function vipEnsureGlyphRanges()
    if VIP_GLYPH_RANGES then return VIP_GLYPH_RANGES end
    local builder = imgui.ImFontGlyphRangesBuilder()
    builder:AddRanges(imgui.GetIO().Fonts:GetGlyphRangesCyrillic())
    builder:AddText(u8'№‚„…†‡€‰‹‘’“”•–—™›')
    VIP_GLYPH_RANGES = imgui.ImVector_ImWchar()
    builder:BuildRanges(VIP_GLYPH_RANGES)
    return VIP_GLYPH_RANGES
end

imgui.OnInitialize(function()
    local glyphRanges = vipEnsureGlyphRanges()[0].Data

    vipFontLarge = false
    local fontsDir, candidates =
        getFolderPath(0x14), {'arialbd.ttf', 'arial.ttf', 'segoeui.ttf', 'tahoma.ttf', 'trebucbd.ttf'}
    for _, fname in ipairs(candidates) do
        local path = fontsDir .. '\\' .. fname
        if doesFileExist(path) then
            local ok, font = pcall(function()
                return imgui.GetIO().Fonts:AddFontFromFileTTF(path, VIP_FONT_SIZE, nil, glyphRanges)
            end)
            if ok and font then
                vipFontLarge = font
                break
            end
        end
    end

    vipFontUI = false
    if doesFileExist(VIP_FONT_TTF_PATH) then
        local ok, font = pcall(function()
            return imgui.GetIO().Fonts:AddFontFromFileTTF(VIP_FONT_TTF_PATH, VIP_FONT_UI_SIZE, nil, glyphRanges)
        end)
        if ok and font then
            vipFontUI = font
            vipFontUiLoaded = true
        elseif not vipFontUiWarned then
            vipFontUiWarned = true
            sampAddChatMessage('[VIP] {FF0000}Не удалось применить шрифт vipscaner.ttf (файл есть, но ImGui не смог его прочитать)', 0xFF0000)
        end
    end
end)

function imgui.BeforeDrawFrame()
    local vipNowClock = os.clock()
    vipDeltaTime = vipNowClock - vipLastFrameClock
    if vipDeltaTime < 0 or vipDeltaTime > 1 then vipDeltaTime = 0 end
    vipLastFrameClock = vipNowClock

    if not vipFontUiLoaded and doesFileExist(VIP_FONT_TTF_PATH) then
        local ok, font = pcall(function()
            return imgui.GetIO().Fonts:AddFontFromFileTTF(VIP_FONT_TTF_PATH, VIP_FONT_UI_SIZE, nil, vipEnsureGlyphRanges()[0].Data)
        end)
        if ok and font then
            vipFontUI = font
            vipFontUiLoaded = true
            imgui.RebuildFonts()
        elseif not vipFontUiWarned then
            vipFontUiWarned = true
            sampAddChatMessage('[VIP] {FF0000}Не удалось применить шрифт vipscaner.ttf (файл есть, но ImGui не смог его прочитать)', 0xFF0000)
        end
    end
end

local initFile = io.open(VIP_LOG_FILE, "a")
if initFile then initFile:close() end

local function convertSampColorToRGB(color)
    color = color or 0xFFFFFFFF
    if color < 0 then
        color = color + 4294967296
    end
    return math.floor(color / 256) % 16777216
end

local function normalizeColor(color)
    color = convertSampColorToRGB(color)
    local hex = string.format("%06X", color)
    return hex
end

local function vipMskTimeStr(ts)
    ts = (ts or os.time()) + 3 * 3600
    return os.date("!%H:%M:%S", ts)
end

local VIP_DUP_WINDOW_SEC, vipLastRawColor, vipLastRawText, vipLastRawTick = 0.6, nil, nil, 0

local function vipIsDuplicateRawMessage(color, text)
    local now = os.clock()
    local isDup = (text == vipLastRawText) and (color == vipLastRawColor) and ((now - vipLastRawTick) < VIP_DUP_WINDOW_SEC)
    vipLastRawColor, vipLastRawText, vipLastRawTick = color, text, now
    return isDup
end

local function vipGetMatchedPrefix(text)
    for _, p in ipairs(VIP_PREFIXES) do
        if text:sub(1, #p) == p then return p end
    end
    return nil
end

local function vipColorToRGB(colorInt)
    colorInt = colorInt or 0xFFFFFF
    local r, g, b = math.floor(colorInt / 0x10000) % 256, math.floor(colorInt / 0x100) % 256, colorInt % 256
    return r / 255, g / 255, b / 255
end

local function vipParseNickId(line)
    local cleanLine = line:gsub("{[0-9a-fA-F]+}", "")
    local nick, id = cleanLine:match("([%w_%.%-]+)%[(%d+)%]")
    return nick, id
end

local vipLastLine, vipLastTick = nil, 0

local function vipRewriteLogFile()
    local f = io.open(VIP_LOG_FILE, "w")
    if not f then return end
    for _, entry in ipairs(vipAllLines) do
        f:write(string.format("%06X\t%d\t%s\n", entry.color, entry.time or os.time(), entry.text))
    end
    f:close()
end

local vipLogFlush = {interval = 2, dirty = false, lastFlush = 0}

function vipLogFlush.mark()
    vipLogFlush.dirty = true
end

function vipLogFlush.poll()
    if not vipLogFlush.dirty then return end
    local now = os.clock()
    if (now - vipLogFlush.lastFlush) < vipLogFlush.interval then return end
    vipLogFlush.lastFlush = now
    vipLogFlush.dirty = false
    vipRewriteLogFile()
end

local function vipSaveLine(baseColor, text)
    local now = os.clock()
    if text == vipLastLine and (now - vipLastTick) < 1 then
        return nil
    end
    vipLastLine, vipLastTick = text, now

    local rgbColor = convertSampColorToRGB(baseColor)
    local colorHex, ts = string.format("%06X", rgbColor), os.time()

    local f = io.open(VIP_LOG_FILE, "a")
    if f then
        f:write(string.format("%s\t%d\t%s\n", colorHex, ts, text))
        f:close()
    end

    local entry = {color = rgbColor, time = ts, text = text}
    table.insert(vipAllLines, entry)

    if vipWindowOpen[0] and not vipViewingFile then
        local matchesFilter = true
        if vipCurrentFilter then
            local nick = vipParseNickId(text)
            matchesFilter = nick ~= nil and nick:lower() == vipCurrentFilter:lower()
        end
        if matchesFilter then
            table.insert(vipLines, entry)
        end
    end

    return entry
end

local function vipListLogFiles()
    local files = {}
    local ok, lfs = pcall(require, 'lfs')
    if ok and lfs then
        local latest, latestTime = nil, 0
        for name in lfs.dir(VIP_CHAT_DIR) do
            if name:match("^vip_.*%.txt$") then
                local path = VIP_CHAT_DIR .. '\\' .. name
                local attr = lfs.attributes(path)
                if attr and attr.modification > latestTime then
                    latestTime = attr.modification
                    latest = path
                end
            end
        end
        if latest then
            table.insert(files, latest)
        end
    else
        files = {VIP_LOG_FILE}
    end
    return files
end

local function vipListAllLogFilesSorted()
    local files = {}
    local ok, lfs = pcall(require, 'lfs')
    if ok and lfs then
        for name in lfs.dir(VIP_CHAT_DIR) do
            if name:match("^vip_.*%.txt$") then
                local path = VIP_CHAT_DIR .. '\\' .. name
                local attr = lfs.attributes(path)
                table.insert(files, {name = name, path = path, mtime = attr and attr.modification or 0})
            end
        end
        table.sort(files, function(a, b) return a.mtime > b.mtime end)
    else
        local name = VIP_LOG_FILE:match("[^\\]+$") or VIP_LOG_FILE
        table.insert(files, {name = name, path = VIP_LOG_FILE, mtime = os.time()})
    end
    return files
end

local function vipFormatLogFileLabel(name)
    local y, mo, d, h, mi, s = name:match("^vip_(%d+)%-(%d+)%-(%d+)_(%d+)%-(%d+)%-(%d+)%.txt$")
    if y then
        return string.format("%s.%s.%s  %s:%s:%s", d, mo, y, h, mi, s)
    end
    return name
end

local function vipParseLine(line)
    local colorHex, ts, text = line:match("^(%x+)\t(%d+)\t(.*)$")
    if not colorHex then
        colorHex, text = line:match("^(%x+)\t(.*)$")
        ts = nil
    end
    if not colorHex then return nil end

    local color = 0xFFFFFF
    if #colorHex >= 6 then
        color = tonumber(colorHex:sub(1, 6), 16) or 0xFFFFFF
    end

    return color, tonumber(ts), text
end

local function vipFindNickById(id)
    local numId = tonumber(id)
    if not numId then return nil, false end
    numId = math.floor(numId)

    -- Защита от краша: не вызываем нативки sampfuncs по невалидному/несуществующему id
    if numId < 0 or numId > 999 then
        return nil, false
    end

    local okConn, connected = pcall(sampIsPlayerConnected, numId)
    if not okConn or not connected then
        return nil, false
    end

    local okNick, nick = pcall(sampGetPlayerNickname, numId)
    if okNick and nick and nick ~= "" then
        return nick, true
    end
    return nil, false
end

function vipHideEntry(entry)
    if not entry then return end
    for idx = #vipLines, 1, -1 do
        if vipLines[idx] == entry then
            table.remove(vipLines, idx)
            break
        end
    end
end

function vipDeleteEntry(entry)
    if not entry then return end
    for idx = #vipAllLines, 1, -1 do
        if vipAllLines[idx] == entry then
            table.remove(vipAllLines, idx)
            break
        end
    end
    for idx = #vipLines, 1, -1 do
        if vipLines[idx] == entry then
            table.remove(vipLines, idx)
            break
        end
    end
    vipRewriteLogFile()
end

local function vipLoadLines(filter)
    local result = {}
    for _, path in ipairs(vipListLogFiles()) do
        local f = io.open(path, "r")
        if f then
            for line in f:lines() do
                local color, ts, text = vipParseLine(line)
                if text then
                    if not filter or filter == "" then
                        table.insert(result, {color = color, time = ts, text = text})
                    else
                        local nick = vipParseNickId(text)
                        if nick and nick:lower() == filter:lower() then table.insert(result, {color = color, time = ts, text = text}) end
                    end
                end
            end
            f:close()
        end
    end
    return result
end

local function vipLoadLinesFromSingleFile(path, filter)
    local result, f = {}, io.open(path, "r")
    if f then
        for line in f:lines() do
            local color, ts, text = vipParseLine(line)
            if text then
                if not filter or filter == "" then
                    table.insert(result, {color = color, time = ts, text = text})
                else
                    local nick = vipParseNickId(text)
                    if nick and nick:lower() == filter:lower() then table.insert(result, {color = color, time = ts, text = text}) end
                end
            end
        end
        f:close()
    end
    return result
end

local function vipColorFromHex6(hex)
    hex = hex or "FFFFFF"
    local r, g, b =
        tonumber(hex:sub(1, 2), 16) or 255, tonumber(hex:sub(3, 4), 16) or 255, tonumber(hex:sub(5, 6), 16) or 255
    return r / 255, g / 255, b / 255
end

function vipSetColorTableFromHex(t, hex)
    local r, g, b = vipColorFromHex6(hex)
    t[1], t[2], t[3] = r, g, b
end

function vipColorTableToHex(t)
    local function to255(v)
        v = math.floor((v or 0) * 255 + 0.5)
        if v < 0 then v = 0 elseif v > 255 then v = 255 end
        return v
    end
    return string.format("%02X%02X%02X", to255(t[1]), to255(t[2]), to255(t[3]))
end

function vipRGBtoHSV(r, g, b)
    local maxV, minV = math.max(r, g, b), math.min(r, g, b)
    local delta, h, s, v = maxV - minV, 0, 0, maxV
    if maxV > 0 then s = delta / maxV end
    if delta > 0 then
        if maxV == r then h = ((g - b) / delta) % 6
        elseif maxV == g then h = (b - r) / delta + 2
        else h = (r - g) / delta + 4 end
        h = h * 60
        if h < 0 then h = h + 360 end
    end
    return h, s, v
end

function vipHSVtoRGB(h, s, v)
    h = h % 360
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b
    if h < 60 then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    return r + m, g + m, b + m
end

-- по одному выбранному цвету автоматически подбирает второй акцентный оттенок (для градиентов/обводок)
function vipApplyThemeColor(r, g, b)
    VIP_ACCENT[1], VIP_ACCENT[2], VIP_ACCENT[3] = r, g, b

    local h, s, v = vipRGBtoHSV(r, g, b)
    local r2, g2, b2 = vipHSVtoRGB(h + 36, s, v)
    VIP_ACCENT2[1], VIP_ACCENT2[2], VIP_ACCENT2[3] = r2, g2, b2
end

local function vipGetPngSize(path)
    local f = io.open(path, 'rb')
    if not f then return nil, nil end
    local data = f:read(24)
    f:close()
    if not data or #data < 24 then return nil, nil end

    local function be32(s, pos)
        local b1, b2, b3, b4 = s:byte(pos, pos + 3)
        return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
    end

    return be32(data, 17), be32(data, 21)
end

local function vipGetPngSizeFromMemory(data)
    if not data or #data < 24 then return nil, nil end

    local function be32(s, pos)
        local b1, b2, b3, b4 = s:byte(pos, pos + 3)
        return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
    end

    return be32(data, 17), be32(data, 21)
end

local function vipLoadEmojiTexture(name)
    local cached = emojiTextures[name]
    if cached and cached.attempted then return cached end

    cached = cached or {}
    cached.attempted = true
    emojiTextures[name] = cached

    local data = VIP_IMG_DATA[name]
    if not data or data == "" then
        cached.error = 'нет встроенных данных картинки: ' .. tostring(name)
        return cached
    end

    local w, h = vipGetPngSizeFromMemory(data)
    if not w or not h or w == 0 or h == 0 then
        cached.error = 'не удалось прочитать PNG из памяти: ' .. tostring(name)
        return cached
    end

    local ok, tex = pcall(imgui.CreateTextureFromFileInMemory, imgui.new('const char*', data), #data)
    if not ok or not tex then
        cached.error = tostring(tex)
        return cached
    end

    cached.texture, cached.w, cached.h = tex, w, h
    return cached
end

function vipDrawImageButton(screenPos, size, normalName, hoverName, isHovered)
    local tex = vipLoadEmojiTexture(isHovered and hoverName or normalName)
    if not tex.texture then
        tex = vipLoadEmojiTexture(normalName)
    end
    if not tex.texture then return end

    local scale = 1
    if tex.w > 0 and tex.h > 0 then
        scale = math.min(size / tex.w, size / tex.h)
    end
    local drawW, drawH = tex.w * scale, tex.h * scale
    local p0 = imgui.ImVec2(screenPos.x + (size - drawW) / 2, screenPos.y + (size - drawH) / 2)
    local p1 = imgui.ImVec2(p0.x + drawW, p0.y + drawH)
    imgui.GetWindowDrawList():AddImage(tex.texture, p0, p1)
end

local NUM_TAG_PREFIXES = {'call', 'house', 'biz', 'lavka'}

local function vipFindNextNumTag(text, fromPos)
    fromPos = fromPos or 1
    local bestS, bestE, bestId, bestPrefix
    for _, prefix in ipairs(NUM_TAG_PREFIXES) do
        local s, e, id = text:find(":" .. prefix .. " ?(%d+):", fromPos)
        if s and (not bestS or s < bestS) then
            bestS, bestE, bestId, bestPrefix = s, e, id, prefix
        end
    end
    if not bestS then return nil end
    return bestS, bestE, bestId, bestPrefix
end

local function vipFindNextItemTag(text, fromPos)
    fromPos = fromPos or 1
    local s, e, id = text:find(":item(%d+):", fromPos)
    if not s then return nil end
    return s, e, id
end

local function vipFindNextEmojiTag(text, fromPos)
    fromPos = fromPos or 1
    local bestS, bestE, bestName, bestId, bestPrefix
    for _, et in ipairs(EMOJI_TAGS) do
        local s, e = text:find(et.tag, fromPos, true)
        if s and (not bestS or s < bestS) then
            bestS, bestE, bestName, bestId, bestPrefix = s, e, et.name, nil, nil
        end
    end

    local ns, ne, nid, nprefix = vipFindNextNumTag(text, fromPos)
    if ns and (not bestS or ns < bestS) then
        bestS, bestE, bestId, bestPrefix = ns, ne, nid, nprefix
        bestName = nprefix .. #nid
    end

    local is, ie, iid = vipFindNextItemTag(text, fromPos)
    if is and (not bestS or is < bestS) then
        bestS, bestE, bestId, bestPrefix = is, ie, iid, 'item'
        bestName = nil
    end

    return bestS, bestE, bestName, bestId, bestPrefix
end

local VIP_NUM_TAG_TRACKING = 0.85

local function vipUtf8Chars(text)
    local chars = {}
    local i, n = 1, #text
    while i <= n do
        local b, len = text:byte(i), 1
        if b >= 0xF0 then len = 4
        elseif b >= 0xE0 then len = 3
        elseif b >= 0xC0 then len = 2
        end
        table.insert(chars, text:sub(i, i + len - 1))
        i = i + len
    end
    return chars
end

local function vipTrackedTextWidth(text, trackScale)
    local chars = vipUtf8Chars(text)
    if #chars == 0 then return 0 end
    local maxW = 0
    for _, ch in ipairs(chars) do
        local w = imgui.CalcTextSize(ch).x
        if w > maxW then maxW = w end
    end
    return (maxW * trackScale) * #chars
end

local function vipDrawTrackedText(dl, pos, color, text, trackScale)
    local chars = vipUtf8Chars(text)
    if #chars == 0 then return end
    local maxW = 0
    for _, ch in ipairs(chars) do
        local w = imgui.CalcTextSize(ch).x
        if w > maxW then maxW = w end
    end
    local cell = maxW * trackScale
    local x, y = pos.x, pos.y
    for _, ch in ipairs(chars) do
        local w = imgui.CalcTextSize(ch).x
        dl:AddText(imgui.ImVec2(x + (cell - w) / 2, y), color, ch)
        x = x + cell
    end
end

local function vipRenderTextWithEmojis(trimmed, r, g, b, first)
    local pos, n = 1, #trimmed
    local targetH = imgui.GetTextLineHeight()
    while pos <= n do
        local s, e, name, numId, numPrefix = vipFindNextEmojiTag(trimmed, pos)
        local plain = s and trimmed:sub(pos, s - 1) or trimmed:sub(pos)

        if plain ~= "" then
            if not first then imgui.SameLine(0, 4) end
            vipDrawPlainTextWithChatEmoji(plain, r, g, b)
            first = false
        end

        if s then
            if numPrefix == 'item' then
                local itemId = numId
                vipFetchItemName(itemId)
                vipFetchItemIcon(itemId)

                local iconTex = itemIconTextures[itemId]
                if iconTex and iconTex.texture then
                    if not first then imgui.SameLine(0, 4) end
                    local scale = iconTex.h > 0 and (targetH / iconTex.h) or 1
                    local drawW, drawH = iconTex.w * scale, iconTex.h * scale
                    local vOffset, screenPos = 1.5, imgui.GetCursorScreenPos()
                    local p0 = imgui.ImVec2(screenPos.x, screenPos.y + (targetH - drawH) / 2 + vOffset)
                    local p1 = imgui.ImVec2(p0.x + drawW, p0.y + drawH)
                    imgui.GetWindowDrawList():AddImage(iconTex.texture, p0, p1)
                    imgui.Dummy(imgui.ImVec2(drawW, targetH))
                    first = false
                end

                local itemLabel = itemNames[itemId] and u8(itemNames[itemId]) or u8'Загрузка...'
                if not first then imgui.SameLine(0, 4) end
                imgui.TextColored(imgui.ImVec4(r, g, b, 1), itemLabel)
                first = false
            else
                local tex = vipLoadEmojiTexture(name)
                if not first then imgui.SameLine(0, 4) end
                if tex.texture then
                    local scale = tex.h > 0 and (targetH / tex.h) or 1
                    local drawW, drawH = tex.w * scale, tex.h * scale
                    local vOffset, screenPos = 1.5, imgui.GetCursorScreenPos()
                    local p0 = imgui.ImVec2(screenPos.x, screenPos.y + (targetH - drawH) / 2 + vOffset)
                    local p1 = imgui.ImVec2(p0.x + drawW, p0.y + drawH)
                    imgui.GetWindowDrawList():AddImage(tex.texture, p0, p1)

                    if numId then
                        local prefixU8 = (numPrefix ~= 'call') and u8'№' or ''
                        local digitsU8 = u8(numId)
                        local prefixW = prefixU8 ~= '' and imgui.CalcTextSize(prefixU8).x or 0
                        local digitsW = vipTrackedTextWidth(digitsU8, VIP_NUM_TAG_TRACKING)
                        local textW, textH = prefixW + digitsW, imgui.CalcTextSize(digitsU8).y
                        local tx, ty = p0.x + drawW - textW - 1, p0.y + (drawH - textH) / 2
                        local numDl = imgui.GetWindowDrawList()
                        if prefixU8 ~= '' then
                            numDl:AddText(imgui.ImVec2(tx, ty), 0xFF000000, prefixU8)
                        end
                        vipDrawTrackedText(numDl, imgui.ImVec2(tx + prefixW, ty), 0xFF000000, digitsU8, VIP_NUM_TAG_TRACKING)
                    end

                    imgui.Dummy(imgui.ImVec2(drawW, targetH))
                else
                    imgui.TextColored(imgui.ImVec4(r, g, b, 1), u8(trimmed:sub(s, e)))
                end
                first = false
            end
            pos = e + 1
        else
            pos = n + 1
        end
    end
    return first
end

local function vipRenderColoredLine(entry, lineIdx)
    local timeStr = vipMskTimeStr(entry.time)
    imgui.TextColored(imgui.ImVec4(0.55, 0.55, 0.55, 1), u8(timeStr))
    imgui.SameLine(0, 6)

    local text = entry.text
    local pos, curHex, first = 1, nil, true
    local segIdx, anyBadWordHovered = 0, false
    while true do
        local s, e, hex = text:find("{([0-9a-fA-F]+)}", pos)
        local segText = s and text:sub(pos, s - 1) or text:sub(pos)
        local trimmed = segText:gsub(" +$", "")
        if trimmed ~= "" then
            segIdx = segIdx + 1
            local r, g, b
            local isBadWord = false
            if curHex then
                r, g, b = vipColorFromHex6(curHex:sub(1, 6))
                local upperHex = curHex:sub(1, 6):upper()
                isBadWord = upperHex == BAD_WORD_COLOR:upper()
                    or upperHex == CAPS_COLOR:upper()
                    or upperHex == TRADE_HIGHLIGHT_COLOR:upper()
                    or upperHex == FLOOD_COLOR:upper()
                    or upperHex == MATWINDOW_COLOR:upper()
            else
                r, g, b = vipColorToRGB(entry.color)
            end
            if isBadWord then
                if not first then imgui.SameLine(0, 4) end
                imgui.TextColored(imgui.ImVec4(r, g, b, 1), u8(trimmed))
                if imgui.IsItemHovered() then anyBadWordHovered = true end
            else
                first = vipRenderTextWithEmojis(trimmed, r, g, b, first)
            end

            if isBadWord then
                local popupId = string.format("wordctx_%d_%d", lineIdx, segIdx)
                if imgui.BeginPopupContextItem(popupId) then
                    if entry.flagType == 'flood' then
                        if vipSelectable(u8'Не флуд') then
                            vipAddToFloodWhitelist(entry.flagNick)
                            vipUnflagEntry(entry)
                        end
                    elseif entry.flagType == 'matwindow' then
                        if vipSelectable(u8'Не мат') then
                            if entry.matWords then
                                for _, w in ipairs(entry.matWords) do
                                    vipAddToWhitelist(w)
                                end
                            end
                            vipUnflagEntry(entry)
                        end
                    else
                        if vipTextContainsBadWord(trimmed) then
                            if vipSelectable(u8'Не мат') then
                                vipAddToWhitelist(trimmed)
                            end
                        elseif vipIsCapsPattern(trimmed) then
                            if vipSelectable(u8'Не капс') then
                                vipAddToWhitelist(trimmed)
                            end
                        else
                            if vipSelectable(u8'Не мат') then
                                vipAddToWhitelist(trimmed)
                            end
                        end
                    end
                    if vipSelectable(u8'Отмена') then
                    end
                    imgui.EndPopup()
                end
            end

            first = false
        end
        if not s then break end
        curHex = hex
        pos = e + 1
    end

    return anyBadWordHovered
end

local function vipPushModernStyle()
    local pushedColors = 0
    local function pc(idx, r, g, b, a)
        imgui.PushStyleColor(idx, imgui.ImVec4(r, g, b, a))
        pushedColors = pushedColors + 1
    end

    local ax, ay, az = VIP_ACCENT[1], VIP_ACCENT[2], VIP_ACCENT[3]

    -- лёгкая подмешка акцентного цвета темы в фон окна (чтобы тема ощущалась не только на кнопках)
    local function tintBg(baseR, baseG, baseB, tintAmount)
        tintAmount = tintAmount or 0.06
        return
            baseR + (ax - baseR) * tintAmount,
            baseG + (ay - baseG) * tintAmount,
            baseB + (az - baseB) * tintAmount
    end

    do
        local r, g, b = tintBg(0.07, 0.075, 0.095, 0.07)
        pc(imgui.Col.WindowBg, r, g, b, 0.98)
    end
    do
        local r, g, b = tintBg(0.09, 0.095, 0.12, 0.10)
        pc(imgui.Col.TitleBg, r, g, b, 1.0)
    end
    do
        local r, g, b = tintBg(0.11, 0.12, 0.16, 0.16)
        pc(imgui.Col.TitleBgActive, r, g, b, 1.0)
    end
    pc(imgui.Col.Border, 0.24, 0.26, 0.34, 0.5)
    do
        local r, g, b = tintBg(0.10, 0.105, 0.135, 0.07)
        pc(imgui.Col.ChildBg, r, g, b, 1.0)
    end
    do
        local r, g, b = tintBg(0.11, 0.12, 0.155, 0.09)
        pc(imgui.Col.PopupBg, r, g, b, 0.98)
    end

    pc(imgui.Col.FrameBg, 0.14, 0.15, 0.19, 1.0)
    pc(imgui.Col.FrameBgHovered, ax * 0.30, ay * 0.30, az * 0.30, 1.0)
    pc(imgui.Col.FrameBgActive, ax * 0.38, ay * 0.38, az * 0.38, 1.0)

    pc(imgui.Col.ScrollbarBg, 0.09, 0.095, 0.12, 1.0)
    pc(imgui.Col.ScrollbarGrab, 0.30, 0.32, 0.40, 1.0)
    pc(imgui.Col.ScrollbarGrabHovered, ax, ay, az, 0.7)
    pc(imgui.Col.ScrollbarGrabActive, ax, ay, az, 0.9)

    pc(imgui.Col.Text, 0.93, 0.94, 0.97, 1.0)
    pc(imgui.Col.TextDisabled, 0.55, 0.57, 0.62, 1.0)

    pc(imgui.Col.Header, ax * 0.35, ay * 0.35, az * 0.35, 0.55)
    pc(imgui.Col.HeaderHovered, ax * 0.55, ay * 0.55, az * 0.55, 0.8)
    pc(imgui.Col.HeaderActive, ax * 0.70, ay * 0.70, az * 0.70, 0.9)

    pc(imgui.Col.Separator, 0.25, 0.27, 0.34, 1.0)

    pc(imgui.Col.Button, 0.17, 0.18, 0.23, 1.0)
    pc(imgui.Col.ButtonHovered, ax * 0.55, ay * 0.55, az * 0.55, 1.0)
    pc(imgui.Col.ButtonActive, ax * 0.75, ay * 0.75, az * 0.75, 1.0)

    pc(imgui.Col.CheckMark, ax, ay, az, 1.0)
    pc(imgui.Col.SliderGrab, ax, ay, az, 0.9)
    pc(imgui.Col.SliderGrabActive, ax, ay, az, 1.0)

    pc(imgui.Col.Tab, 0.13, 0.14, 0.18, 1.0)
    pc(imgui.Col.TabHovered, ax * 0.55, ay * 0.55, az * 0.55, 0.9)
    pc(imgui.Col.TabActive, ax * 0.42, ay * 0.42, az * 0.42, 1.0)
    pc(imgui.Col.TabUnfocused, 0.12, 0.13, 0.16, 1.0)
    pc(imgui.Col.TabUnfocusedActive, 0.16, 0.17, 0.22, 1.0)

    pc(imgui.Col.ResizeGrip, ax, ay, az, 0.15)
    pc(imgui.Col.ResizeGripHovered, ax, ay, az, 0.5)
    pc(imgui.Col.ResizeGripActive, ax, ay, az, 0.8)

    local style = imgui.GetStyle()
    local savedVars = {
        WindowRounding = style.WindowRounding,
        ChildRounding = style.ChildRounding,
        PopupRounding = style.PopupRounding,
        ScrollbarRounding = style.ScrollbarRounding,
        FrameRounding = style.FrameRounding,
        GrabRounding = style.GrabRounding,
        TabRounding = style.TabRounding,
        WindowPadding = imgui.ImVec2(style.WindowPadding.x, style.WindowPadding.y),
        FramePadding = imgui.ImVec2(style.FramePadding.x, style.FramePadding.y),
        WindowBorderSize = style.WindowBorderSize,
        FrameBorderSize = style.FrameBorderSize,
        ItemSpacing = imgui.ImVec2(style.ItemSpacing.x, style.ItemSpacing.y),
        ScrollbarSize = style.ScrollbarSize,
        GrabMinSize = style.GrabMinSize,
    }

    style.WindowRounding = 14
    style.ChildRounding = 10
    style.PopupRounding = 10
    style.ScrollbarRounding = 10
    style.FrameRounding = 7
    style.GrabRounding = 7
    style.TabRounding = 8
    style.WindowPadding = imgui.ImVec2(14, 12)
    style.FramePadding = imgui.ImVec2(8, 5)
    style.WindowBorderSize = 1
    style.FrameBorderSize = 0
    style.ItemSpacing = imgui.ImVec2(8, 8)
    style.ScrollbarSize = 11
    style.GrabMinSize = 10

    return pushedColors, savedVars
end

local function vipRestoreStyleVars(savedVars)
    local style = imgui.GetStyle()
    for k, v in pairs(savedVars) do
        style[k] = v
    end
end

imgui.OnFrame(function() return vipWindowOpen[0] end, function(self)
    local usingUiFont = vipFontUI and vipFontUI ~= false
    if usingUiFont then imgui.PushFont(vipFontUI) end

    if vipChatEmoji and not vipChatEmojiTexLoaded then
        local okCall, okLoad = pcall(function() return vipChatEmoji.load() end)
        if okCall and okLoad then
            vipChatEmojiTexLoaded = true
        end
    end

    local nColors, savedVars = vipPushModernStyle()

    imgui.SetNextWindowSize(imgui.ImVec2(1020, 520), imgui.Cond.Always)
    imgui.Begin(u8'VIP история###vipwnd', vipWindowOpen,
        imgui.WindowFlags.NoResize + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoCollapse)

    local winW, winPos, dl = imgui.GetWindowWidth(), imgui.GetWindowPos(), imgui.GetWindowDrawList()

    PUN.lastMainPos.x, PUN.lastMainPos.y = winPos.x, winPos.y

    local btnSize, topY = 24, 9

    imgui.SetCursorPos(imgui.ImVec2(winW - btnSize - 12, topY))

    imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(0, 0, 0, 0))

    local btnScreenPos, closeClicked =
        imgui.GetCursorScreenPos(), imgui.Button(u8'##vipclose', imgui.ImVec2(btnSize, btnSize))

    local closeHovered = imgui.IsItemHovered()

    imgui.PopStyleColor(3)

    vipDrawImageButton(btnScreenPos, btnSize, 'close', 'closebutton', closeHovered)

    if closeClicked then
        vipWindowOpen[0] = false
    end

    imgui.SetCursorPos(imgui.ImVec2(winW - btnSize * 3 - 12 - 8 * 2, topY))

    imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(0, 0, 0, 0))

    local histScreenPos, histClicked =
        imgui.GetCursorScreenPos(), imgui.Button(u8'##viphistory', imgui.ImVec2(btnSize, btnSize))

    local histHovered = imgui.IsItemHovered()

    imgui.PopStyleColor(3)

    local histActive = vipViewingFile ~= nil

    if histHovered then
        imgui.SetTooltip(u8'История сообщений')
    end

    vipDrawImageButton(histScreenPos, btnSize, 'storage', 'storagebutton', histHovered or histActive)

    if histClicked then
        imgui.OpenPopup(u8'История файлов###viphistorypopup')
    end

    if imgui.BeginPopup(u8'История файлов###viphistorypopup') then
        imgui.TextColored(imgui.ImVec4(0.55, 0.57, 0.62, 1), u8'Выберите файл истории')
        imgui.Separator()

        if vipSelectable(u8'Текущая сессия (live)', vipViewingFile == nil) then
            vipViewingFile = nil
            vipLines = vipLoadLines(vipCurrentFilter)
            imgui.CloseCurrentPopup()
        end
        imgui.Separator()

        imgui.BeginChild('vip_history_list', imgui.ImVec2(260, 220), false)
        for _, file in ipairs(vipListAllLogFilesSorted()) do
            local isSel = (vipViewingFile == file.path)
            if vipSelectable(u8(vipFormatLogFileLabel(file.name)), isSel) then
                vipViewingFile = file.path
                vipLines = vipLoadLinesFromSingleFile(file.path, vipCurrentFilter)
                imgui.CloseCurrentPopup()
            end
        end
        imgui.EndChild()

        imgui.EndPopup()
    end

    imgui.SetCursorPos(imgui.ImVec2(winW - btnSize * 2 - 12 - 8, topY))
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0, 0, 0, 0))
    local gearScreenPos, gearClicked =
        imgui.GetCursorScreenPos(), imgui.Button(u8'##vipsettings', imgui.ImVec2(btnSize, btnSize))
    local gearHovered = imgui.IsItemHovered()
    imgui.PopStyleColor(3)

    if gearHovered then
        imgui.SetTooltip(u8'Настройки VIPScanner')
    end

    vipDrawImageButton(gearScreenPos, btnSize, 'settings', 'settingsbutton', gearHovered)

    if gearClicked then
        avipWindowOpen[0] = true
    end

    imgui.SetCursorPos(imgui.ImVec2(winW - btnSize * 4 - 12 - 8 * 3, topY))
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0, 0, 0, 0))
    local camScreenPos, camClicked =
        imgui.GetCursorScreenPos(), imgui.Button(u8'##vipscreens', imgui.ImVec2(btnSize, btnSize))
    local camHovered = imgui.IsItemHovered()
    imgui.PopStyleColor(3)

    if camHovered then
        imgui.SetTooltip(u8'История скриншотов')
    end

    vipDrawImageButton(camScreenPos, btnSize, 'cam', 'cambutton', camHovered)

    if camClicked then
        VIP_SCR.windowOpen[0] = not VIP_SCR.windowOpen[0]
    end

    if vipCurrentFilter then
        imgui.SetCursorPos(imgui.ImVec2(12, topY))
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0, 0, 0, 0))
        local homeScreenPos, homeClicked =
            imgui.GetCursorScreenPos(), imgui.Button(u8'##viphome', imgui.ImVec2(btnSize, btnSize))
        local homeHovered = imgui.IsItemHovered()
        imgui.PopStyleColor(3)

        if homeHovered then
            imgui.SetTooltip(u8'Сбросить фильтр и показать все сообщения')
        end

        vipDrawImageButton(homeScreenPos, btnSize, 'house', 'housebutton', homeHovered)

        if homeClicked then
            vipCurrentFilter = nil
            vipViewingFile = nil
            vipLines = vipLoadLines(nil)
            if not PUN.targetOverride then
                PUN.windowOpen[0] = false
                PUN_HIST.windowOpen[0] = false
            end
        end
    end

    local label = vipCurrentFilter and ('Фильтр: ' .. vipCurrentFilter) or 'Все сообщения'
    if vipViewingFile then
        local histName = vipViewingFile:match("[^\\]+$") or vipViewingFile
        label = label .. '  [' .. vipFormatLogFileLabel(histName) .. ']'
    end
    local labelU8 = u8(label)
    local textSize, pulse, dotR = imgui.CalcTextSize(labelU8), 0.5 + 0.5 * math.sin(imgui.GetTime() * 3.2), 4
    local groupW = dotR * 2 + 8 + textSize.x
    local groupX, groupY = (winW - groupW) / 2, topY + (btnSize - textSize.y) / 2

    dl:AddCircleFilled(
        imgui.ImVec2(winPos.x + groupX + dotR, winPos.y + groupY + textSize.y / 2), dotR,
        vipPackColor(VIP_SUCCESS[1], VIP_SUCCESS[2], VIP_SUCCESS[3], 0.35 + 0.65 * pulse), 12)

    imgui.SetCursorPos(imgui.ImVec2(groupX + dotR * 2 + 8, groupY))
    imgui.TextColored(imgui.ImVec4(0.72, 0.80, 0.98, 1), labelU8)

    imgui.SetCursorPosY(topY + btnSize + 8)
    imgui.Dummy(imgui.ImVec2(0, 2))

    do local r, g, b = vipTintBg(0.085, 0.09, 0.115, 0.07) imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(r, g, b, 1.0)) end
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(VIP_ACCENT[1], VIP_ACCENT[2], VIP_ACCENT[3], 0.12))
    imgui.BeginChild('vip_scroll', imgui.ImVec2(0, 0), true)

    local vipLogoTex = vipLoadEmojiTexture('otto')
    if vipLogoTex.texture then
        local logoMaxH = 240
        local logoScale = vipLogoTex.h > 0 and math.min(1, logoMaxH / vipLogoTex.h) or 1
        local logoW, logoH = vipLogoTex.w * logoScale, vipLogoTex.h * logoScale
        local childPos, childSize = imgui.GetWindowPos(), imgui.GetWindowSize()
        local logoX, logoY = childPos.x + (childSize.x - logoW) / 2, childPos.y + (childSize.y - logoH) / 2
        imgui.GetWindowDrawList():AddImage(vipLogoTex.texture, imgui.ImVec2(logoX, logoY), imgui.ImVec2(logoX + logoW, logoY + logoH))
    end

    local rowH, rowTextYOffset
    do
        local usingChatFontForHeight = vipFontLarge and vipFontLarge ~= false
        if usingChatFontForHeight then imgui.PushFont(vipFontLarge) end
        local textH = imgui.GetTextLineHeight()
        if usingChatFontForHeight then imgui.PopFont() end
        local pad = imgui.GetStyle().ItemSpacing.y
        rowH = textH + pad
        rowTextYOffset = pad / 2
    end
    local clickedNick, hideRequested, deleteRequested = nil, nil, nil

    local totalRows = #vipLines
    local scrollY, viewportH = imgui.GetScrollY(), imgui.GetWindowHeight()
    local visibleBuffer = 4
    local startIdx = math.max(1, math.floor(scrollY / rowH) - visibleBuffer + 1)
    local endIdx = math.min(totalRows, math.ceil((scrollY + viewportH) / rowH) + visibleBuffer)

    if startIdx > 1 then
        imgui.Dummy(imgui.ImVec2(0, (startIdx - 1) * rowH))
    end

    for i = startIdx, endIdx do
        local entry = vipLines[i]
        local rowPos = imgui.GetCursorPos()

        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(VIP_ACCENT[1], VIP_ACCENT[2], VIP_ACCENT[3], 0.08))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(VIP_ACCENT[1], VIP_ACCENT[2], VIP_ACCENT[3], 0.14))
        local rowClicked = imgui.Button('##vip_row_' .. i, imgui.ImVec2(-1, rowH))
        vipHoverHighlight(4)
        imgui.PopStyleColor(3)

        local rowMin, rowMax = imgui.GetItemRectMin(), imgui.GetItemRectMax()

        if rowClicked and not clickedNick then
            local rowNick = vipParseNickId(entry.text)
            if rowNick then clickedNick = rowNick end
        end

        imgui.SetCursorPos(imgui.ImVec2(rowPos.x, rowPos.y + rowTextYOffset))
        local usingChatFont = vipFontLarge and vipFontLarge ~= false
        if usingChatFont then imgui.PushFont(vipFontLarge) end
        local hoveredBadWord = vipRenderColoredLine(entry, i)
        if usingChatFont then imgui.PopFont() end

        local rowPopupId = string.format('rowctx_%d', i)
        if not hoveredBadWord and imgui.IsMouseReleased(1) and imgui.IsMouseHoveringRect(rowMin, rowMax) then
            imgui.OpenPopup(rowPopupId)
        end
        if imgui.BeginPopup(rowPopupId) then
            if vipSelectable(u8'Скрыть') then
                hideRequested = entry
            end
            if vipSelectable(u8'Удалить') then
                deleteRequested = entry
            end
            if vipSelectable(u8'Наказать') then
                local rowNick = vipParseNickId(entry.text)
                if rowNick then
                    PUN.targetOverride = rowNick
                    PUN.windowOpen[0] = true
                    vipRequestPunishHistory(rowNick)
                end
            end
            imgui.EndPopup()
        end
    end

    if endIdx < totalRows then
        imgui.Dummy(imgui.ImVec2(0, (totalRows - endIdx) * rowH))
    end

    imgui.EndChild()
    imgui.PopStyleColor(2)

    if hideRequested then
        vipHideEntry(hideRequested)
    end

    if deleteRequested then
        vipDeleteConfirmEntry = deleteRequested
        imgui.OpenPopup(u8'Подтверждение удаления')
    end

    local modalColors, modalVars = vipPushModernStyle()
    local style = imgui.GetStyle()
    local prevTitleAlign = imgui.ImVec2(style.WindowTitleAlign.x, style.WindowTitleAlign.y)
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    imgui.SetNextWindowSize(imgui.ImVec2(360, 0), imgui.Cond.Always)
    if imgui.BeginPopupModal(u8'Подтверждение удаления', nil, imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoResize) then
        local msg = u8'Вы точно хотите удалить это сообщение?'
        local msgSize = imgui.CalcTextSize(msg)
        imgui.SetCursorPosX((imgui.GetWindowWidth() - msgSize.x) / 2)
        imgui.Text(msg)
        imgui.Dummy(imgui.ImVec2(0, 10))

        local modalW = imgui.GetWindowWidth() - imgui.GetStyle().WindowPadding.x * 2
        local btnW = (modalW - 10) / 2

        if vipAnimatedButton('vip_del_no', u8'Отмена', btnW, 34,
            {0.20, 0.22, 0.28}, {0.40, 0.44, 0.54}, {0.15, 0.16, 0.20}) then
            vipDeleteConfirmEntry = nil
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine(0, 10)
        if vipAnimatedButton('vip_del_yes', u8'Удалить', btnW, 34,
            {0.58, 0.19, 0.21}, {0.96, 0.33, 0.37}, {0.50, 0.15, 0.17}) then
            vipDeleteEntry(vipDeleteConfirmEntry)
            vipDeleteConfirmEntry = nil
            imgui.CloseCurrentPopup()
        end
        imgui.EndPopup()
    end
    style.WindowTitleAlign = prevTitleAlign
    vipRestoreStyleVars(modalVars)
    imgui.PopStyleColor(modalColors)

    if clickedNick then
        vipCurrentFilter = clickedNick
        if vipViewingFile then
            vipLines = vipLoadLinesFromSingleFile(vipViewingFile, clickedNick)
        else
            vipLines = vipLoadLines(clickedNick)
        end
        PUN.targetOverride = nil
        PUN.windowOpen[0] = true
        vipRequestPunishHistory(clickedNick)
    end

    imgui.End()

    vipRestoreStyleVars(savedVars)
    imgui.PopStyleColor(nColors)

    if usingUiFont then imgui.PopFont() end
end)

local function cp1251Lower(s)
    local res = {}
    for i = 1, #s do
        local b = s:byte(i)
        if b >= 0xC0 and b <= 0xDF then
            b = b + 0x20
        elseif b == 0xA8 then
            b = 0xB8
        elseif b >= 0x41 and b <= 0x5A then
            b = b + 0x20
        end
        res[i] = string.char(b)
    end
    return table.concat(res)
end

local function vipInitTradeWords()
    TRADE_WORDS = {}
    for _, w in ipairs(TRADE_WORDS_RAW) do
        table.insert(TRADE_WORDS, cp1251Lower(w))
    end
end

local function vipFindTradeWord(text, startPos)
    startPos = startPos or 1
    if #TRADE_WORDS == 0 then return nil end
    local lowerText = cp1251Lower(text)
    local bestS, bestE
    for _, word in ipairs(TRADE_WORDS) do
        local s, e = lowerText:find(word, startPos, true)
        if s and (not bestS or s < bestS) then
            bestS, bestE = s, e
        end
    end
    return bestS, bestE
end

local function vipLoadWhitelist()
    whitelist = {}
    local f = io.open(WHITELIST_FILE, "r")
    if not f then return end
    for line in f:lines() do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            whitelist[line] = true
        end
    end
    f:close()
end

function vipAddToWhitelist(word)
    word = cp1251Lower(word)
    if word == "" or whitelist[word] then return end
    whitelist[word] = true
    local f = io.open(WHITELIST_FILE, "a")
    if f then
        f:write(word .. "\n")
        f:close()
    end
end

local function vipLoadFloodWhitelist()
    floodWhitelist = {}
    local f = io.open(FLOOD_WHITELIST_FILE, "r")
    if not f then return end
    for line in f:lines() do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            floodWhitelist[line:lower()] = true
        end
    end
    f:close()
end

function vipAddToFloodWhitelist(nick)
    if not nick or nick == "" then return end
    local key = nick:lower()
    if floodWhitelist[key] then return end
    floodWhitelist[key] = true
    local f = io.open(FLOOD_WHITELIST_FILE, "a")
    if f then
        f:write(key .. "\n")
        f:close()
    end
end

local function vipLoadSettingsFile()
    vipPunishments = {}
    VIP_SCR.cachedRootPath = nil

    local f = io.open(SETTINGS_FILE, "r")
    if not f then return end

    local section = "settings"
    for line in f:lines() do
        line = line:gsub("\r", "")
        if line == "[SCREENS_CACHE]" then
            section = "screens_cache"
        elseif line == "[PUNISHMENTS]" then
            section = "punishments"
        elseif line ~= "" then
            if section == "settings" then
                local k, v = line:match("^(%u[%u_]*)=(.*)$")
                if k and v then
                    if k == "BAD_WORD_COLOR" then BAD_WORD_COLOR = v
                    elseif k == "CAPS_COLOR" then CAPS_COLOR = v
                    elseif k == "TRADE_HIGHLIGHT_COLOR" then TRADE_HIGHLIGHT_COLOR = v
                    elseif k == "FLOOD_COLOR" then FLOOD_COLOR = v
                    elseif k == "MATWINDOW_COLOR" then MATWINDOW_COLOR = v
                    elseif k == "FLOOD_WINDOW_SEC" then FLOOD_WINDOW_SEC = tonumber(v) or FLOOD_WINDOW_SEC
                    elseif k == "FLOOD_MAX_MSGS" then FLOOD_MAX_MSGS = tonumber(v) or FLOOD_MAX_MSGS
                    elseif k == "MAT_WINDOW_MSGS" then MAT_WINDOW_MSGS = tonumber(v) or MAT_WINDOW_MSGS
                    elseif k == "MAT_TRIGGER_COUNT" then MAT_TRIGGER_COUNT = tonumber(v) or MAT_TRIGGER_COUNT
                    elseif k == "CAPS_MIN_LEN" then CAPS_MIN_LEN = tonumber(v) or CAPS_MIN_LEN
                    elseif k == "THEME_ACCENT" then vipApplyThemeColor(vipColorFromHex6(v))
                    end
                end
            elseif section == "screens_cache" then
                VIP_SCR.cachedRootPath = line
            elseif section == "punishments" then
                local name, ptype, time, reason = line:match("^(.-)\t(.-)\t(.-)\t(.*)$")
                if name and name ~= "" then
                    table.insert(vipPunishments, {name = name, ptype = ptype, time = time, reason = reason})
                end
            end
        end
    end
    f:close()
end

local function vipWriteSettingsFile()
    local f = io.open(SETTINGS_FILE, "w")
    if not f then return end

    f:write("BAD_WORD_COLOR=" .. BAD_WORD_COLOR .. "\n")
    f:write("CAPS_COLOR=" .. CAPS_COLOR .. "\n")
    f:write("TRADE_HIGHLIGHT_COLOR=" .. TRADE_HIGHLIGHT_COLOR .. "\n")
    f:write("FLOOD_COLOR=" .. FLOOD_COLOR .. "\n")
    f:write("MATWINDOW_COLOR=" .. MATWINDOW_COLOR .. "\n")
    f:write("FLOOD_WINDOW_SEC=" .. FLOOD_WINDOW_SEC .. "\n")
    f:write("FLOOD_MAX_MSGS=" .. FLOOD_MAX_MSGS .. "\n")
    f:write("MAT_WINDOW_MSGS=" .. MAT_WINDOW_MSGS .. "\n")
    f:write("MAT_TRIGGER_COUNT=" .. MAT_TRIGGER_COUNT .. "\n")
    f:write("CAPS_MIN_LEN=" .. CAPS_MIN_LEN .. "\n")
    f:write("THEME_ACCENT=" .. vipColorTableToHex(VIP_ACCENT) .. "\n")

    f:write("\n[SCREENS_CACHE]\n")
    f:write((VIP_SCR.cachedRootPath or '') .. "\n")

    f:write("\n[PUNISHMENTS]\n")
    for _, p in ipairs(vipPunishments) do
        f:write(string.format("%s\t%s\t%s\t%s\n", p.name, p.ptype, p.time, p.reason))
    end

    f:close()
end

local function vipSaveSettings() vipWriteSettingsFile() end
local function vipSavePunishments() vipWriteSettingsFile() end

local PUNISH_CMD_BY_TYPE = {
    Ban = 'ban',
    Mute = 'mute',
    Rmute = 'rmute',
    Jail = 'jail',
}

function vipBuildPunishPreview(nick, ptype, time, reason)
    nick = (nick and nick ~= '') and nick or '?'

    local cmdWord = PUNISH_CMD_BY_TYPE[ptype]
    if not cmdWord then
        if reason and reason:sub(1, 1) == '/' then
            return (reason:gsub('#', function() return nick end))
        end
        return u8'Custom: укажите команду, начиная с "/" (используйте # вместо ника)'
    end

    local parts = {'/' .. cmdWord, nick}
    if time and time ~= '' then table.insert(parts, time) end
    if reason and reason ~= '' then table.insert(parts, reason) end

    return table.concat(parts, ' ')
end

function vipParsePunishHistDate(line)
    local y, mo, d, h, mi, s = line:match("%[(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)%]")
    if not y then return nil end
    return os.time({
        year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = tonumber(s)
    })
end

function vipRequestPunishHistory(nick)
    if not nick or nick == '' or nick == '?' then return end
    PUN_HIST.nick = nick
    PUN_HIST.lines = {}
    PUN_HIST.windowOpen[0] = false

    local now = os.clock()
    if (now - PUN_HIST.lastCheckTime) >= PUN_HIST.checkCooldown then
        PUN_HIST.lastCheckTime = now
        PUN_HIST.pendingNick = nil
        sampSendChat('/checkpunishoff ' .. nick)
    else
        PUN_HIST.pendingNick = nick
    end
end

function vipPollCheckPunishQueue()
    if not PUN_HIST.pendingNick then return end
    local now = os.clock()
    if (now - PUN_HIST.lastCheckTime) >= PUN_HIST.checkCooldown then
        local nick = PUN_HIST.pendingNick
        PUN_HIST.pendingNick = nil
        PUN_HIST.lastCheckTime = now
        sampSendChat('/checkpunishoff ' .. nick)
    end
end

function VIP_SCR.isDir(path)
    local ok, lfs = pcall(require, 'lfs')
    if not ok or not lfs then return false end
    local attr = lfs.attributes(path)
    return attr ~= nil and attr.mode == 'directory'
end

function VIP_SCR.loadCachedRoot()
    local path = VIP_SCR.cachedRootPath
    if path and path ~= '' and VIP_SCR.isDir(path) then
        return path
    end
    return nil
end

function VIP_SCR.saveCachedRoot(path)
    VIP_SCR.cachedRootPath = path
    vipWriteSettingsFile()
    return true
end

function VIP_SCR.searchArizonaScreens(root)
    local ok, lfs = pcall(require, 'lfs')
    if not ok or not lfs then return nil end
    local visited = 0

    local function scan(path, depth, parentName)
        if visited > VIP_SCR.SEARCH_MAX_DIRS or depth > VIP_SCR.SEARCH_MAX_DEPTH then
            return nil
        end

        local dok, iter, dirObj = pcall(lfs.dir, path)
        if not dok or not iter then return nil end

        for entry in iter, dirObj do
            if entry ~= '.' and entry ~= '..' then
                visited = visited + 1
                if visited % 50 == 0 then wait(0) end
                if visited > VIP_SCR.SEARCH_MAX_DIRS then return nil end

                local full = path .. '\\' .. entry
                local attrOk, attr = pcall(lfs.attributes, full)
                if attrOk and attr and attr.mode == 'directory' then
                    local lname = entry:lower()
                    if lname == 'screens' and parentName == 'arizona' then
                        return full
                    end
                    local found = scan(full, depth + 1, lname)
                    if found then return found end
                end
            end
        end
        return nil
    end

    return scan(root, 0, '')
end

function VIP_SCR.resolveRoot()
    local rootFolder = VIP_SCR.loadCachedRoot()
    if rootFolder then return rootFolder end

    local userProfile = os.getenv('USERPROFILE')
    local found = userProfile and VIP_SCR.searchArizonaScreens(userProfile) or nil

    if not found and userProfile then
        local fallbackRoots = {
            userProfile .. '\\Documents\\GTA San Andreas User Files\\SAMP\\arizona\\screens',
            userProfile .. '\\Documents\\GTA San Andreas User Files\\Gallery'
        }
        for _, path in ipairs(fallbackRoots) do
            if VIP_SCR.isDir(path) then found = path break end
        end
    end

    if not found then
        return nil, 'root_not_found'
    end

    VIP_SCR.saveCachedRoot(found)
    return found
end

function VIP_SCR.findLatest()
    local ok, lfs = pcall(require, 'lfs')
    if not ok or not lfs then return nil, 'no_lfs' end

    local rootFolder, rootErr = VIP_SCR.resolveRoot()
    if not rootFolder then
        return nil, rootErr
    end

    local latestSubfolder, maxFolderTime = nil, 0
    for fileName in lfs.dir(rootFolder) do
        if fileName ~= '.' and fileName ~= '..' then
            local fullSub = rootFolder .. '\\' .. fileName
            if VIP_SCR.isDir(fullSub) then
                local attr = lfs.attributes(fullSub)
                if attr and attr.modification > maxFolderTime then
                    maxFolderTime = attr.modification
                    latestSubfolder = fullSub
                end
            end
        end
    end
    if not latestSubfolder then return nil, 'subfolder_not_found' end

    local targetFile, maxFileTime = nil, 0
    for fileName in lfs.dir(latestSubfolder) do
        if fileName:find('%.jpg$') or fileName:find('%.png$') or fileName:find('%.jpeg$') then
            local fullFile = latestSubfolder .. '\\' .. fileName
            local attr = lfs.attributes(fullFile)
            if attr and attr.mode == 'file' and attr.modification > maxFileTime then
                maxFileTime = attr.modification
                targetFile = fullFile
            end
        end
    end
    if not targetFile then return nil, 'file_not_found' end

    return targetFile, nil, maxFileTime
end

function VIP_SCR.loadHistory()
    VIP_SCR.list = {}
    local f = io.open(VIP_SCR.HISTORY_FILE, 'r')
    if not f then return end
    for line in f:lines() do
        line = line:gsub('\r', '')

        local ts, nick, ptype, path, url = line:match('^(%d+)\t(.-)\t(.-)\t(.-)\t(.*)$')
        if not ts then
            ts, nick, ptype, path = line:match('^(%d+)\t(.-)\t(.-)\t(.*)$')
            url = nil
        end
        if url == '' then url = nil end
        if ts then

            table.insert(VIP_SCR.list, 1, {time = tonumber(ts), nick = nick, ptype = ptype, path = path, uploadedUrl = url})
        end
    end
    f:close()
end

function VIP_SCR.rewriteHistoryFile()
    local f = io.open(VIP_SCR.HISTORY_FILE, 'w')
    if not f then return end

    for i = #VIP_SCR.list, 1, -1 do
        local shot = VIP_SCR.list[i]
        f:write(string.format('%d\t%s\t%s\t%s\t%s\n', shot.time, shot.nick or '', shot.ptype or '', shot.path, shot.uploadedUrl or ''))
    end
    f:close()
end

function VIP_SCR.saveRecord(nick, ptype, path)
    local ts, f = os.time(), io.open(VIP_SCR.HISTORY_FILE, 'a')
    if f then
        f:write(string.format('%d\t%s\t%s\t%s\t\n', ts, nick or '', ptype or '', path))
        f:close()
    end
    table.insert(VIP_SCR.list, 1, {time = ts, nick = nick, ptype = ptype, path = path, uploadedUrl = nil})
end

function VIP_SCR.autoDetectRootOnStartup()
    if VIP_SCR.loadCachedRoot() then return end

    lua_thread.create(function()
        local root, err = VIP_SCR.resolveRoot()
        if root then
        elseif err ~= 'no_lfs' then
            sampAddChatMessage('[VIP] {FFA500}Не удалось автоматически найти папку со скриншотами Arizona. Она будет искаться снова при следующей выдаче наказания (F8)', 0xFFA500)
        end
    end)
end

function vipShellExecuteWorker(file, params)
    pcall(function()
        local ffi = require('ffi')
        pcall(ffi.cdef, [[
            typedef void* HINSTANCE;
            HINSTANCE ShellExecuteA(void* hwnd, const char* lpOperation, const char* lpFile, const char* lpParameters, const char* lpDirectory, int nShowCmd);
        ]])
        local okShell, shell32 = pcall(ffi.load, 'shell32')
        if not okShell then return end
        local SW_SHOWNORMAL = 1
        shell32.ShellExecuteA(nil, 'open', file, params, nil, SW_SHOWNORMAL)
    end)
end

function vipShellExecute(file, params)
    if effil then
        local okThread, thread = pcall(effil.thread, vipShellExecuteWorker)
        if okThread then
            pcall(thread, file, params)
            return
        end
    end
    vipShellExecuteWorker(file, params)
end

function vipOpenUrl(url)
    if not url or url == '' then return end
    vipShellExecute(url, nil)
end

function VIP_SCR.openFolder(path)
    if not path or path == '' then return end
    if doesFileExist(path) then
        vipShellExecute('explorer.exe', string.format('/select,"%s"', path))
        return
    end
    local folder = path:match('^(.*)\\[^\\]+$')
    if folder then
        vipShellExecute(folder, nil)
    end
end

function vipCopyToClipboard(text)
    if not text or text == '' then return false end

    local ffi = require('ffi')
    pcall(ffi.cdef, [[
        typedef void* HGLOBAL;
        HGLOBAL GlobalAlloc(unsigned int uFlags, size_t dwBytes);
        void* GlobalLock(HGLOBAL hMem);
        int GlobalUnlock(HGLOBAL hMem);
        int OpenClipboard(void* hWndNewOwner);
        int EmptyClipboard(void);
        void* SetClipboardData(unsigned int uFormat, void* hMem);
        int CloseClipboard(void);
    ]])

    local okUser, user32 = pcall(ffi.load, 'user32')
    local okKernel, kernel32 = pcall(ffi.load, 'kernel32')
    if not okUser or not okKernel then return false end

    local GMEM_MOVEABLE, CF_TEXT = 0x0002, 1

    local size = #text + 1
    local hMem = kernel32.GlobalAlloc(GMEM_MOVEABLE, size)
    if hMem == nil then return false end

    local ptr = kernel32.GlobalLock(hMem)
    if ptr == nil then return false end
    ffi.copy(ptr, text, #text)
    ffi.cast('char*', ptr)[#text] = 0
    kernel32.GlobalUnlock(hMem)

    if user32.OpenClipboard(nil) == 0 then return false end
    user32.EmptyClipboard()
    user32.SetClipboardData(CF_TEXT, hMem)
    user32.CloseClipboard()
    return true
end

function vipUploadImageWorker(path, apiKey, resultChannel)
    local ok, err = pcall(function()
        local ffi = require('ffi')

        local function base64Encode(data)
            local chars, out, len, i =
                'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/', {}, #data, 1
            while i <= len do
                local b1, b2, b3 = data:byte(i), data:byte(i + 1), data:byte(i + 2)
                local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
                local c1, c2, c3, c4 =
                    math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64
                out[#out + 1] = chars:sub(c1 + 1, c1 + 1)
                out[#out + 1] = chars:sub(c2 + 1, c2 + 1)
                out[#out + 1] = b2 and chars:sub(c3 + 1, c3 + 1) or '='
                out[#out + 1] = b3 and chars:sub(c4 + 1, c4 + 1) or '='
                i = i + 3
            end
            return table.concat(out)
        end

        local function urlEncode(s)
            return (s:gsub('[^%w%-%.%_%~]', function(c)
                return string.format('%%%02X', c:byte())
            end))
        end

        local f = io.open(path, 'rb')
        if not f then
            resultChannel:push({false, 'Не удалось открыть файл скриншота'})
            return
        end
        local raw = f:read('*a')
        f:close()

        local b64 = base64Encode(raw)
        local body = 'key=' .. urlEncode(apiKey) .. '&source=' .. urlEncode(b64) .. '&format=json'

        pcall(ffi.cdef, [[
            typedef void* HINTERNET;
            HINTERNET InternetOpenA(const char* lpszAgent, unsigned long dwAccessType, const char* lpszProxy, const char* lpszProxyBypass, unsigned long dwFlags);
            HINTERNET InternetConnectA(HINTERNET hInternet, const char* lpszServerName, unsigned short nServerPort, const char* lpszUserName, const char* lpszPassword, unsigned long dwService, unsigned long dwFlags, unsigned long dwContext);
            HINTERNET HttpOpenRequestA(HINTERNET hConnect, const char* lpszVerb, const char* lpszObjectName, const char* lpszVersion, const char* lpszReferer, void* lplpszAcceptTypes, unsigned long dwFlags, unsigned long dwContext);
            int HttpSendRequestA(HINTERNET hRequest, const char* lpszHeaders, unsigned long dwHeadersLength, void* lpOptional, unsigned long dwOptionalLength);
            int InternetReadFile(HINTERNET hFile, void* lpBuffer, unsigned long dwNumberOfBytesToRead, unsigned long* lpdwNumberOfBytesRead);
            int InternetCloseHandle(HINTERNET hInternet);
        ]])

        local okWinInet, wininet = pcall(ffi.load, 'wininet')
        if not okWinInet then
            resultChannel:push({false, 'Не удалось загрузить wininet.dll'})
            return
        end

        local INTERNET_SERVICE_HTTP, INTERNET_FLAG_SECURE, INTERNET_FLAG_RELOAD, INTERNET_DEFAULT_HTTPS_PORT =
            3, 0x00800000, 0x80000000, 443

        local hInternet = wininet.InternetOpenA('VIPScanner', 0, nil, nil, 0)
        if hInternet == nil then
            resultChannel:push({false, 'InternetOpenA failed'})
            return
        end

        local hConnect = wininet.InternetConnectA(hInternet, 'freeimage.host', INTERNET_DEFAULT_HTTPS_PORT, nil, nil, INTERNET_SERVICE_HTTP, 0, 0)
        if hConnect == nil then
            wininet.InternetCloseHandle(hInternet)
            resultChannel:push({false, 'InternetConnectA failed'})
            return
        end

        local hRequest = wininet.HttpOpenRequestA(hConnect, 'POST', '/api/1/upload', nil, nil, nil, INTERNET_FLAG_SECURE + INTERNET_FLAG_RELOAD, 0)
        if hRequest == nil then
            wininet.InternetCloseHandle(hConnect)
            wininet.InternetCloseHandle(hInternet)
            resultChannel:push({false, 'HttpOpenRequestA failed'})
            return
        end

        local headers, bodyBuf = 'Content-Type: application/x-www-form-urlencoded\r\n', ffi.new('char[?]', #body)
        ffi.copy(bodyBuf, body, #body)

        local sent = wininet.HttpSendRequestA(hRequest, headers, #headers, bodyBuf, #body)
        if sent == 0 then
            wininet.InternetCloseHandle(hRequest)
            wininet.InternetCloseHandle(hConnect)
            wininet.InternetCloseHandle(hInternet)
            resultChannel:push({false, 'HttpSendRequestA failed (проверьте API-ключ и интернет)'})
            return
        end

        local chunks, buf, bytesRead = {}, ffi.new('char[8192]'), ffi.new('unsigned long[1]')
        while true do
            local okRead = wininet.InternetReadFile(hRequest, buf, 8192, bytesRead)
            if okRead == 0 or bytesRead[0] == 0 then break end
            chunks[#chunks + 1] = ffi.string(buf, bytesRead[0])
        end

        wininet.InternetCloseHandle(hRequest)
        wininet.InternetCloseHandle(hConnect)
        wininet.InternetCloseHandle(hInternet)

        local respText = table.concat(chunks)

        local statusCode = tonumber(respText:match('"status_code"%s*:%s*(%d+)'))
        local errMsg = respText:match('"error"%s*:%s*{.-"message"%s*:%s*"(.-)"')

        if statusCode and statusCode ~= 200 then
            resultChannel:push({false, 'Ошибка freeimage.host (' .. statusCode .. '): ' .. (errMsg or respText:sub(1, 200))})
            return
        end

        local url = respText:match('"image"%s*:%s*{.-"url"%s*:%s*"(.-)"') or respText:match('"url"%s*:%s*"(.-)"')
        if url then
            url = url:gsub('\\/', '/')
            resultChannel:push({true, url})
        else
            resultChannel:push({false, 'Не удалось разобрать ответ freeimage.host: ' .. respText:sub(1, 300)})
        end
    end)

    if not ok then
        resultChannel:push({false, 'Ошибка воркера загрузки: ' .. tostring(err)})
    end
end

function vipStartImageUpload(shot)
    if not shot or shot.uploadPending then return end

    if not effil then
        sampAddChatMessage('[VIP] {FF0000}Загрузка скриншотов требует библиотеку effil, которая не найдена', 0xFF0000)
        return
    end

    local apiKey = VIP_SCR.freeimageApiKey or ''
    if apiKey == '' then

        return
    end

    local okChan, channel = pcall(effil.channel)
    if not okChan or not channel then
        sampAddChatMessage('[VIP] {FF0000}Не удалось создать effil.channel', 0xFF0000)
        return
    end

    local okThread, thread = pcall(effil.thread, vipUploadImageWorker)
    if not okThread then
        sampAddChatMessage('[VIP] {FF0000}Не удалось создать поток загрузки (effil.thread)', 0xFF0000)
        return
    end

    local okRun, runner = pcall(thread, shot.path, apiKey, channel)
    if not okRun then
        sampAddChatMessage('[VIP] {FF0000}Не удалось запустить поток загрузки', 0xFF0000)
        return
    end

    shot.uploadPending = true
    table.insert(VIP_SCR.uploadChannels, {channel = channel, shot = shot, runner = runner})
end

function vipPollUploadChannels()
    if #VIP_SCR.uploadChannels == 0 then return end
    for i = #VIP_SCR.uploadChannels, 1, -1 do
        local task = VIP_SCR.uploadChannels[i]
        local okPop, result = pcall(function() return task.channel:pop(0) end)
        if okPop and result then
            task.shot.uploadPending = false
            if result[1] then
                task.shot.uploadedUrl = result[2]
                VIP_SCR.rewriteHistoryFile()
                vipCopyToClipboard(task.shot.uploadedUrl)
                sampAddChatMessage('[VIP] {A2DAC1}Скриншот загружен, ссылка скопирована в буфер обмена', 0xA2DAC1)
            else
                sampAddChatMessage('[VIP] {FF0000}Ошибка загрузки скриншота: ' .. tostring(result[2]), 0xFF0000)
            end
            table.remove(VIP_SCR.uploadChannels, i)
        end
    end
end

function vipPressF8(nick, ptype)
    pcall(ffi.cdef, [[
        void keybd_event(unsigned char bVk, unsigned char bScan, unsigned long dwFlags, unsigned long dwExtraInfo);
    ]])

    local okLoad, user32 = pcall(ffi.load, 'user32')
    if not okLoad then return end

    local VK_F8, KEYEVENTF_KEYUP = 0x77, 0x0002

    lua_thread.create(function()
        local _, baselineErr, baselineTime = VIP_SCR.findLatest()
        baselineTime = baselineTime or 0

        pcall(function() user32.keybd_event(VK_F8, 0, 0, 0) end)
        wait(50)
        pcall(function() user32.keybd_event(VK_F8, 0, KEYEVENTF_KEYUP, 0) end)

        if baselineErr == 'root_not_found' or baselineErr == 'no_lfs' then
            return
        end

        local waited = 0
        while waited < VIP_SCR.MAX_WAIT do
            wait(VIP_SCR.POLL_INTERVAL)
            waited = waited + VIP_SCR.POLL_INTERVAL

            local candidate, _, candidateTime = VIP_SCR.findLatest()
            if candidate and (candidateTime or 0) > baselineTime then
                VIP_SCR.saveRecord(nick, ptype, candidate)
                break
            end
        end
    end)
end

function vipApplyPunishment(nick, ptype, time, reason)

    if not nick or nick == '' or nick == '?' then
        sampAddChatMessage('[VIP] {FF0000}Не удалось определить ник для наказания', 0xFF0000)
        return
    end

    local cmdWord = PUNISH_CMD_BY_TYPE[ptype]
    if not cmdWord then

        if reason and reason:sub(1, 1) == '/' then

            local decodedReason = encoding.UTF8:decode(reason)
            local cmdToSend = decodedReason:gsub('#', function() return nick end)
            sampSendChat(cmdToSend)
            vipPressF8(nick, 'Custom')
            sampAddChatMessage(string.format('[VIP] {A2DAC1}Отправлена кастомная команда: {FFFFFF}%s', cmdToSend), 0xA2DAC1)
        else
            sampAddChatMessage('[VIP] {FF0000}Для Custom без готовой команды укажите её, начиная с "/" (используйте # вместо ника)', 0xFF0000)
        end
        return
    end

    local parts = {'/' .. cmdWord, nick}
    if time and time ~= '' then table.insert(parts, time) end

    if reason and reason ~= '' then
        local decodedReason = encoding.UTF8:decode(reason)
        table.insert(parts, decodedReason)
    end

    local cmdStr = table.concat(parts, ' ')

    sampSendChat(cmdStr)
    vipPressF8(nick, ptype)

    local displayReason = (reason and reason ~= '') and encoding.UTF8:decode(reason) or ''

    sampAddChatMessage(string.format('[VIP] {A2DAC1}Наказание отправлено: {FFFFFF}/%s %s %s %s',
        cmdWord, nick, time or '', displayReason), 0xA2DAC1)
end

function vipUnflagEntry(entry)
    if not entry or not entry.origText then return end
    entry.text = entry.origText
    entry.origText = nil
    entry.flagType = nil
    entry.flagNick = nil
    entry.matWords = nil
    vipRewriteLogFile()
end

function vipTextContainsBadWord(text)
    local lower = cp1251Lower(text)
    for _, w in ipairs(badWords) do
        if lower:find(w, 1, true) then return true end
    end
    return false
end

local function vipLoadBadWords()
    badWords = {}
    local f = io.open(BAD_WORDS_FILE, "r")
    if not f then return end
    for line in f:lines() do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            table.insert(badWords, cp1251Lower(line))
        end
    end
    f:close()
end

local function vipThreadDownloadFile(url, path)
    local ffi = require('ffi')
    local ok = pcall(ffi.cdef, [[
        typedef long HRESULT;
        HRESULT URLDownloadToFileA(void* pCaller, const char* szURL, const char* szFileName, unsigned long dwReserved, void* lpfnCB);
    ]])
    local okLoad, urlmon = pcall(ffi.load, 'urlmon')
    if not okLoad then return false, 'urlmon load failed' end

    -- cache-busting: URLDownloadToFileA использует системный кэш WinINet и может отдать
    -- старую закэшированную версию файла, если URL не изменился с прошлого раза.
    -- Добавляем всегда уникальный параметр, чтобы гарантированно ходить на сервер за свежими данными.
    math.randomseed(os.time() + os.clock() * 1000)
    local sep = url:find('?', 1, true) and '&' or '?'
    local cacheBustedUrl = url .. sep .. '_vipcb=' .. tostring(os.time()) .. tostring(math.random(100000, 999999))

    local hr = urlmon.URLDownloadToFileA(nil, cacheBustedUrl, path, 0, nil)
    return (hr == 0), tostring(hr)
end

local vipPendingTasks = {}

local function vipRunAsync(fn, onDone, ...)
    if not effil then
        local ok, a, b = pcall(fn, ...)
        if onDone then onDone(ok and a, b) end
        return
    end
    local ok, thread = pcall(effil.thread, fn)
    if not ok then
        if onDone then onDone(false, 'effil.thread failed') end
        return
    end
    local okRun, runner = pcall(thread, ...)
    if not okRun then
        if onDone then onDone(false, 'effil run failed') end
        return
    end
    table.insert(vipPendingTasks, {runner = runner, onDone = onDone})
end

local function vipPollAsyncTasks()
    if #vipPendingTasks == 0 then return end
    for i = #vipPendingTasks, 1, -1 do
        local task = vipPendingTasks[i]
        local status = task.runner:status()
        if status == 'completed' then
            local ok, a, b = task.runner:get()
            if task.onDone then task.onDone(ok, a, b) end
            table.remove(vipPendingTasks, i)
        elseif status == 'canceled' or status == 'error' then
            if task.onDone then task.onDone(false, status) end
            table.remove(vipPendingTasks, i)
        end
    end
end

local function vipSetupBadWords()
    if doesFileExist(BAD_WORDS_FILE) then
        vipLoadBadWords()
    end

    local tmpPath = VIP_LOG_DIR .. '\\words_remote_tmp.txt'
    vipRunAsync(vipThreadDownloadFile, function(ok)
        if not ok then
            os.remove(tmpPath)
            if #badWords == 0 then
                sampAddChatMessage('[VIP] {FF0000}Не удалось скачать words.txt', 0xFF0000)
            end
            return
        end

        local tf = io.open(tmpPath, 'rb')
        local remoteContent = tf and tf:read('*a') or ''
        if tf then tf:close() end
        os.remove(tmpPath)

        local existing = {}
        local ef = io.open(BAD_WORDS_FILE, 'r')
        if ef then
            for line in ef:lines() do
                local clean = line:gsub("\r", "")
                if clean ~= "" then existing[clean] = true end
            end
            ef:close()
        end

        local newLines = {}
        remoteContent = remoteContent:gsub("\r\n", "\n"):gsub("\r", "\n")
        for line in (remoteContent .. "\n"):gmatch("(.-)\n") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" and not line:match("^#") and not existing[line] then
                existing[line] = true
                table.insert(newLines, line)
            end
        end

        if #newLines > 0 then
            local af = io.open(BAD_WORDS_FILE, 'a')
            if af then
                for _, l in ipairs(newLines) do
                    af:write(l .. "\n")
                end
                af:close()
            end
            vipLoadBadWords()
            sampAddChatMessage(string.format('[VIP] {A2DAC1}words.txt: добавлено новых слов: %d', #newLines), 0xA2DAC1)
        elseif #badWords == 0 then
            vipLoadBadWords()
        end
    end, VIP_WORDS_URL, tmpPath)
end

local function vipSetupWhitelist()
    if doesFileExist(WHITELIST_FILE) then
        vipLoadWhitelist()
    end

    local tmpPath = VIP_LOG_DIR .. '\\whitelist_remote_tmp.txt'
    vipRunAsync(vipThreadDownloadFile, function(ok)
        if not ok then
            os.remove(tmpPath)
            if next(whitelist) == nil then
                sampAddChatMessage('[VIP] {FF0000}Не удалось скачать whitelist.txt', 0xFF0000)
            end
            return
        end

        local tf = io.open(tmpPath, 'rb')
        local remoteContent = tf and tf:read('*a') or ''
        if tf then tf:close() end
        os.remove(tmpPath)

        local existing = {}
        local ef = io.open(WHITELIST_FILE, 'r')
        if ef then
            for line in ef:lines() do
                local clean = line:gsub("\r", "")
                if clean ~= "" then existing[clean] = true end
            end
            ef:close()
        end

        local newLines = {}
        remoteContent = remoteContent:gsub("\r\n", "\n"):gsub("\r", "\n")
        for line in (remoteContent .. "\n"):gmatch("(.-)\n") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" and not existing[line] then
                existing[line] = true
                table.insert(newLines, line)
            end
        end

        if #newLines > 0 then
            local af = io.open(WHITELIST_FILE, 'a')
            if af then
                for _, l in ipairs(newLines) do
                    af:write(l .. "\n")
                end
                af:close()
            end
            vipLoadWhitelist()
            sampAddChatMessage(string.format('[VIP] {A2DAC1}whitelist.txt: добавлено новых слов: %d', #newLines), 0xA2DAC1)
        elseif next(whitelist) == nil then
            vipLoadWhitelist()
        end
    end, VIP_WHITELIST_URL, tmpPath)
end

local function vipUnescapeImgString(s)
    return (s:gsub('\\x(%x%x)', function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function vipParseImgData(content)
    if not content then return end
    for name, str in content:gmatch('([%w_]+)%s*=%s*"(.-)"') do
        VIP_IMG_DATA[name] = vipUnescapeImgString(str)
    end
end

local function vipSetupImgData()
    vipRunAsync(vipThreadDownloadFile, function(ok)
        if not ok then
            sampAddChatMessage('[VIP] {FF0000}Не удалось скачать img.txt', 0xFF0000)
            return
        end

        local f = io.open(VIP_IMG_TMP_FILE, 'rb')
        if f then
            local content = f:read('*a')
            f:close()
            vipParseImgData(content)
            emojiTextures = {}
        end
        os.remove(VIP_IMG_TMP_FILE)

        local count = 0
        for _ in pairs(VIP_IMG_DATA) do count = count + 1 end

        if count == 0 then
            sampAddChatMessage('[VIP] {FF0000}img.txt скачан, но не удалось разобрать данные картинок', 0xFF0000)
        end
    end, VIP_IMG_URL, VIP_IMG_TMP_FILE)
end

local function vipIsValidFontFile(path)
    local f = io.open(path, 'rb')
    if not f then return false end
    local head = f:read(4)
    f:close()
    if not head or #head < 4 then return false end
    return head == '\0\1\0\0' or head == 'true' or head == 'OTTO' or head == 'ttcf'
end

local function vipSetupCustomFont()
    if doesFileExist(VIP_FONT_TTF_PATH) then
        if not vipIsValidFontFile(VIP_FONT_TTF_PATH) then
            os.remove(VIP_FONT_TTF_PATH)
            sampAddChatMessage('[VIP] {FF0000}Файл шрифта vipscaner.ttf повреждён, удалил, качаю заново', 0xFF0000)
        else
            return
        end
    end
    vipRunAsync(vipThreadDownloadFile, function(ok)
        if not ok then
            sampAddChatMessage('[VIP] {FF0000}Не удалось скачать шрифт vipscaner.ttf (ошибка загрузки)', 0xFF0000)
            return
        end
        if not vipIsValidFontFile(VIP_FONT_TTF_PATH) then
            os.remove(VIP_FONT_TTF_PATH)
            sampAddChatMessage('[VIP] {FF0000}Шрифт vipscaner.ttf скачался, но это не похоже на настоящий TTF-файл (проверьте ссылку на файл в репозитории)', 0xFF0000)
        end
    end, VIP_FONT_TTF_URL, VIP_FONT_TTF_PATH)
end

function vipSetupApiKey()
    local apiKeyUrl, tmpPath = 'https://gitverse.ru/api/repos/Nehto/VipScaner/raw/branch/master/api.txt', VIP_LOG_DIR .. '\\api_tmp.txt'
    vipRunAsync(vipThreadDownloadFile, function(ok)
        if not ok then
            os.remove(tmpPath)
            sampAddChatMessage('[VIP] {FF0000}Не удалось скачать API-ключ (api.txt)', 0xFF0000)
            return
        end

        local f = io.open(tmpPath, 'rb')
        local content = f and f:read('*a') or ''
        if f then f:close() end
        os.remove(tmpPath)

        content = content:gsub("\r", ""):gsub("\n", ""):gsub("^%s+", ""):gsub("%s+$", "")

        if content ~= '' then
            VIP_SCR.freeimageApiKey = content
        else
            sampAddChatMessage('[VIP] {FF0000}api.txt скачан, но пуст', 0xFF0000)
        end
    end, apiKeyUrl, tmpPath)
end

local function vipLoadItemsCache()
    itemNames = {}
    local f = io.open(ITEMS_CACHE_FILE, "r")
    if not f then return end
    for line in f:lines() do
        line = line:gsub("\r", "")
        local id, name = line:match("^(%d+)\t(.*)$")
        if id and name then
            itemNames[id] = name
        end
    end
    f:close()
end

local function vipSaveItemToCache(id, name)
    local f = io.open(ITEMS_CACHE_FILE, "a")
    if f then
        f:write(id .. "\t" .. name .. "\n")
        f:close()
    end
end

local itemFallbackData, itemFallbackPending = {}, {}

local function vipParseItemFallbackContent(content)
    local result = {}
    if not content then return result end
    for key, str in content:gmatch('([%w_]+)%s*=%s*"(.-)"') do
        if key == 'icon' then
            result.iconData = vipUnescapeImgString(str)
        elseif key == 'name' then
            result.name = str
        end
    end
    return result
end

local function vipFetchItemFallback(id, onDone)
    if itemFallbackData[id] then
        onDone(itemFallbackData[id])
        return
    end
    if itemFallbackPending[id] then
        table.insert(itemFallbackPending[id], onDone)
        return
    end
    itemFallbackPending[id] = {onDone}

    local url, tmpPath = VIP_ITEM_FALLBACK_BASE_URL .. id .. '.txt', VIP_ITEM_TMP_DIR .. '\\' .. id .. '_fallback.txt'
    vipRunAsync(vipThreadDownloadFile, function(ok)
        local data = {failed = true}
        if ok then
            local f = io.open(tmpPath, 'rb')
            if f then
                local content = f:read('*a')
                f:close()
                local parsed = vipParseItemFallbackContent(content)
                if parsed.name or parsed.iconData then
                    data = parsed
                    data.failed = false
                end
            end
        end
        os.remove(tmpPath)

        itemFallbackData[id] = data
        local callbacks = itemFallbackPending[id] or {}
        itemFallbackPending[id] = nil
        for _, cb in ipairs(callbacks) do
            cb(data)
        end
    end, url, tmpPath)
end

local function vipParseItemName(jsonText, id)
    local idPattern = '"id"%s*:%s*"' .. id .. '"'
    local idPos = jsonText:find(idPattern)
    if idPos then
        local objStart, objEnd = jsonText:sub(1, idPos):match(".*()%{"), jsonText:find("}", idPos)
        if objStart and objEnd then
            local objText = jsonText:sub(objStart, objEnd)
            local name = objText:match('"item_name"%s*:%s*"(.-)"')
            if name then return name end
        end
    end
    return jsonText:match('"item_name"%s*:%s*"(.-)"')
end

vipFetchItemName = function(id)
    if itemNames[id] ~= nil or itemFetchPending[id] then return end
    itemFetchPending[id] = true

    local url, tmpPath = VIP_ITEMS_API_URL .. '?id=' .. id, VIP_ITEM_TMP_DIR .. '\\' .. id .. '.json'

    vipRunAsync(vipThreadDownloadFile, function(ok)
        local resolvedName = nil
        if ok then
            local f = io.open(tmpPath, 'rb')
            if f then
                local content = f:read('*a')
                f:close()
                local rawName = vipParseItemName(content, id)
                if rawName and rawName ~= "" then
                    local okDec, decoded = pcall(function() return u8:decode(rawName) end)
                    resolvedName = (okDec and decoded) or rawName
                end
            end
        end
        os.remove(tmpPath)

        if resolvedName then
            itemFetchPending[id] = nil
            itemNames[id] = resolvedName
            vipSaveItemToCache(id, itemNames[id])
            return
        end

        vipFetchItemFallback(id, function(data)
            itemFetchPending[id] = nil
            local fallbackName = (not data.failed and data.name and data.name ~= "") and data.name or nil
            itemNames[id] = fallbackName or ('[Предмет ' .. id .. ']')
            vipSaveItemToCache(id, itemNames[id])
        end)
    end, url, tmpPath)
end

vipFetchItemIcon = function(id)
    local cached = itemIconTextures[id]
    if cached and cached.attempted then return end

    cached = cached or {}
    cached.attempted = true
    itemIconTextures[id] = cached

    local url, tmpPath = VIP_ITEM_ICON_BASE_URL .. id .. '.png', VIP_ITEM_TMP_DIR .. '\\' .. id .. '_icon.png'

    local function tryFallback()
        vipFetchItemFallback(id, function(data)
            if data.failed or not data.iconData or data.iconData == "" then
                cached.error = cached.error or ('не удалось скачать иконку (и резервный источник недоступен): ' .. tostring(id))
                return
            end

            local fw, fh = vipGetPngSizeFromMemory(data.iconData)
            if not fw or not fh or fw == 0 or fh == 0 then
                cached.error = 'не удалось прочитать резервный PNG из памяти: ' .. tostring(id)
                return
            end

            local okTex, tex = pcall(imgui.CreateTextureFromFileInMemory, imgui.new('const char*', data.iconData), #data.iconData)
            if not okTex or not tex then
                cached.error = tostring(tex)
                return
            end

            cached.texture, cached.w, cached.h = tex, fw, fh
        end)
    end

    vipRunAsync(vipThreadDownloadFile, function(ok)
        if not ok then
            os.remove(tmpPath)
            tryFallback()
            return
        end

        local w, h = vipGetPngSize(tmpPath)
        if not w or not h or w == 0 or h == 0 then
            os.remove(tmpPath)
            tryFallback()
            return
        end

        local okTex, tex = pcall(imgui.CreateTextureFromFile, tmpPath)
        os.remove(tmpPath)

        if not okTex or not tex then
            tryFallback()
            return
        end

        cached.texture, cached.w, cached.h = tex, w, h
    end, url, tmpPath)
end

local function vipFindBadWord(text, startPos)
    startPos = startPos or 1
    if #badWords == 0 then return nil end
    local lowerText = cp1251Lower(text)
    local bestS, bestE
    for _, word in ipairs(badWords) do
        local s, e = lowerText:find(word, startPos, true)
        if s and (not bestS or s < bestS) then
            bestS, bestE = s, e
        end
    end
    return bestS, bestE
end

local WORD_BOUNDARY_BYTES = {
    [0x20] = true, [0x09] = true, [0x0A] = true, [0x0D] = true,
    [0x2C] = true, [0x2E] = true, [0x21] = true, [0x3F] = true,
    [0x3A] = true, [0x3B] = true,
    [0x22] = true, [0x27] = true,
    [0x28] = true, [0x29] = true, [0x5B] = true, [0x5D] = true,
    [0x7B] = true, [0x7D] = true,
    [0x2D] = true, [0x2F] = true, [0x5C] = true,
    [0x2A] = true, [0x40] = true, [0x23] = true, [0x25] = true,
    [0x5E] = true, [0x26] = true, [0x2B] = true, [0x3D] = true,
    [0x7C] = true, [0x7E] = true, [0x60] = true,
    [0x3C] = true, [0x3E] = true,
}

local function isWordBoundaryByte(b)
    if not b then return true end
    return WORD_BOUNDARY_BYTES[b] == true
end

local function vipExpandToWordBounds(text, s, e)
    while s > 1 and not isWordBoundaryByte(text:byte(s - 1)) do
        s = s - 1
    end
    while e < #text and not isWordBoundaryByte(text:byte(e + 1)) do
        e = e + 1
    end
    return s, e
end

local function vipFindNextTradeRange(text, fromPos)
    local s, e = vipFindTradeWord(text, fromPos or 1)
    if not s then return nil end
    return vipExpandToWordBounds(text, s, e)
end

local function vipFindNextBadWordRange(text, fromPos)
    local searchFrom = fromPos or 1
    while true do
        local s, e = vipFindBadWord(text, searchFrom)
        if not s then return nil end
        local ws, we = vipExpandToWordBounds(text, s, e)
        local word = cp1251Lower(text:sub(ws, we))
        if not whitelist[word] then
            return ws, we
        end
        searchFrom = we + 1
    end
end

local function vipFindAllBadWordRanges(text, startPos)
    local ranges, pos = {}, startPos or 1
    while true do
        local s, e = vipFindNextBadWordRange(text, pos)
        if not s then break end
        table.insert(ranges, {s = s, e = e})
        pos = e + 1
    end
    return ranges
end

local function isUpperLetterByte(b)
    if not b then return false end
    return (b >= 0x41 and b <= 0x5A)
        or (b >= 0xC0 and b <= 0xDF)
        or (b == 0xA8)
end

function vipIsCapsPattern(text)
    if #text < CAPS_MIN_LEN then return false end
    for i = 1, #text do
        if not isUpperLetterByte(text:byte(i)) then return false end
    end
    return true
end

local function vipScanCapsRun(text, startPos)
    local i, n = startPos or 1, #text
    while i <= n do
        local c = text:sub(i, i)
        if c == "{" then
            local closePos = text:find("}", i + 1, true)
            i = closePos and (closePos + 1) or (i + 1)
        elseif isUpperLetterByte(text:byte(i)) then
            local runStart, j = i, i
            while j <= n do
                local cj = text:sub(j, j)
                if cj == "{" then break end
                if isUpperLetterByte(text:byte(j)) then
                    j = j + 1
                else
                    break
                end
            end
            local runEnd = j - 1
            if (runEnd - runStart + 1) >= CAPS_MIN_LEN then
                return runStart, runEnd
            end
            i = j
        else
            i = i + 1
        end
    end
    return nil
end

local function vipFindNextCapsRange(text, fromPos)
    local searchFrom = fromPos or 1
    while true do
        local s, e = vipScanCapsRun(text, searchFrom)
        if not s then return nil end
        local word = cp1251Lower(text:sub(s, e))
        if not whitelist[word] then
            return s, e
        end
        searchFrom = e + 1
    end
end

local function vipRestoreTagBefore(text, pos, baseColor)
    local prefix = text:sub(1, pos - 1)
    local lastTag = prefix:match(".*({[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]?[0-9a-fA-F]?})")
    if lastTag then
        local hex = lastTag:match("{([0-9a-fA-F]+)}")
        return "{" .. hex:sub(1, 6) .. "}"
    end
    return "{" .. normalizeColor(baseColor) .. "}"
end

local function vipFindMessageStart(text)
    local colonPos = text:find(":", 1, true)
    if colonPos then
        return colonPos + 1
    end
    return 1
end

local function vipSkipLeadingSpaces(text, pos)
    while pos <= #text and text:sub(pos, pos) == " " do
        pos = pos + 1
    end
    return pos
end

local function vipMakeFullRedText(originalText, msgStart, colorHex)
    colorHex = colorHex or "FF0000"
    local start = vipSkipLeadingSpaces(originalText, msgStart)
    if start > #originalText then return originalText end

    local prefix, msgPart = originalText:sub(1, start - 1), originalText:sub(start):gsub("{[0-9a-fA-F]+}", "")

    return prefix .. "{" .. colorHex .. "}" .. msgPart
end

local function vipPluralRu(n, one, few, many)
    local n100, n10 = n % 100, n % 10
    if n100 >= 11 and n100 <= 14 then return many end
    if n10 == 1 then return one end
    if n10 >= 2 and n10 <= 4 then return few end
    return many
end

local function vipBuildIntervalsStr(msTimestamps)
    local parts = {}
    for i = 1, #msTimestamps - 1 do
        local diff = math.floor(msTimestamps[i + 1] - msTimestamps[i])
        table.insert(parts, string.format("%dмс", diff))
    end
    return table.concat(parts, " {A2DAC1}/{FFFFFF} ")
end

local function vipRegisterFloodEntry(nick, entry)
    if not nick or nick == "" or not entry then return end
    local key = nick:lower()
    if floodWhitelist[key] then return end
    local now = os.time()

    local rec = floodHistory[key]
    if not rec or (now - rec.windowStart) > FLOOD_WINDOW_SEC then
        rec = {windowStart = now, entries = {}, msTimestamps = {}}
        floodHistory[key] = rec
    end

    table.insert(rec.entries, entry)
    table.insert(rec.msTimestamps, os.clock() * 1000)

    if #rec.entries > FLOOD_MAX_MSGS then
        for _, e in ipairs(rec.entries) do
            e.origText = e.origText or e.text
            e.flagType = 'flood'
            e.flagNick = nick
            local msgStart = vipFindMessageStart(e.text)
            e.text = vipMakeFullRedText(e.text, msgStart, FLOOD_COLOR)
        end
        vipLogFlush.mark()

        local count = #rec.entries
        local msgWord, intervalsStr =
            vipPluralRu(count, "сообщение", "сообщения", "сообщений"), vipBuildIntervalsStr(rec.msTimestamps)
        sampAddChatMessage(string.format("[VIP] {FFFFFF}%s {A2DAC1}| {FFFFFF}флуд %d %s {A2DAC1}| {FFFFFF}интервалы: %s", nick, count, msgWord, intervalsStr), 0xA2DAC1)
        vipShowViolationNotify(nick)

        floodHistory[key] = nil
    end
end

local function vipRegisterMatEntry(nick, entry, badWords)
    if not nick or nick == "" or not entry then return end
    local key = nick:lower()

    local rec = matHistory[key]
    if not rec then
        rec = {items = {}}
        matHistory[key] = rec
    end

    table.insert(rec.items, {entry = entry, words = badWords or {}})
    while #rec.items > MAT_WINDOW_MSGS do
        table.remove(rec.items, 1)
    end

    local totalWords = {}
    for _, item in ipairs(rec.items) do
        for _, w in ipairs(item.words) do
            table.insert(totalWords, w)
        end
    end

    if #totalWords >= MAT_TRIGGER_COUNT then
        for _, item in ipairs(rec.items) do
            if #item.words > 0 then
                item.entry.origText = item.entry.origText or item.entry.text
                item.entry.flagType = 'matwindow'
                item.entry.flagNick = nick
                item.entry.matWords = item.words
                local msgStart = vipFindMessageStart(item.entry.text)
                item.entry.text = vipMakeFullRedText(item.entry.text, msgStart, MATWINDOW_COLOR)
            end
        end
        vipLogFlush.mark()

        local wordsStr = table.concat(totalWords, " {A2DAC1}/{FFFFFF} ")
        sampAddChatMessage(string.format("[VIP] {FFFFFF}%s {A2DAC1}| {FFFFFF}мат: %s", nick, wordsStr), 0xA2DAC1)
        vipShowViolationNotify(nick)

        matHistory[key] = nil
    end
end

local function vipRegisterCapsEntry(nick, capsWord)
    if not nick or nick == "" or not capsWord or capsWord == "" then return end
    sampAddChatMessage(string.format("[VIP] {FFFFFF}%s {A2DAC1}| {FFFFFF}капс: %s", nick, capsWord), 0xA2DAC1)
    vipShowViolationNotify(nick)
end

local function vipRegisterTradeEntry(nick, tradeWord)
    if not nick or nick == "" or not tradeWord or tradeWord == "" then return end
    sampAddChatMessage(string.format("[VIP] {FFFFFF}%s {A2DAC1}| {FFFFFF}обход рекламы: %s", nick, tradeWord), 0xA2DAC1)
    vipShowViolationNotify(nick)
end

local function vipFindAllHighlightRanges(text, startPos, includeTrade)
    local ranges, pos = {}, startPos or 1
    while true do
        local bs, be = vipFindNextBadWordRange(text, pos)
        local cs, ce = vipFindNextCapsRange(text, pos)
        local ts, te
        if includeTrade then
            ts, te = vipFindNextTradeRange(text, pos)
        end

        local s, e, color
        local function consider(ns, ne, ncolor)
            if ns and (not s or ns < s) then
                s, e, color = ns, ne, ncolor
            end
        end
        consider(bs, be, BAD_WORD_COLOR)
        consider(cs, ce, CAPS_COLOR)
        consider(ts, te, TRADE_HIGHLIGHT_COLOR)

        if not s then break end
        table.insert(ranges, {s = s, e = e, color = color})
        pos = e + 1
    end
    return ranges
end

local function censorTextMultiple(originalText, baseColor, ranges)
    if #ranges == 0 then return originalText end
    local out, cursor = {}, 1
    for _, r in ipairs(ranges) do
        table.insert(out, originalText:sub(cursor, r.s - 1))
        table.insert(out, "{" .. (r.color or 'FF0000') .. "}")
        table.insert(out, originalText:sub(r.s, r.e))
        table.insert(out, vipRestoreTagBefore(originalText, r.s, baseColor))
        cursor = r.e + 1
    end
    table.insert(out, originalText:sub(cursor))
    return table.concat(out)
end

local function vipInitSettingsUI()
    uiColorBadWord = new.float[3](vipColorFromHex6(BAD_WORD_COLOR))
    uiColorCaps = new.float[3](vipColorFromHex6(CAPS_COLOR))
    uiColorTrade = new.float[3](vipColorFromHex6(TRADE_HIGHLIGHT_COLOR))
    uiColorFlood = new.float[3](vipColorFromHex6(FLOOD_COLOR))
    uiColorMatWindow = new.float[3](vipColorFromHex6(MATWINDOW_COLOR))

    uiFloodWindow = new.int(FLOOD_WINDOW_SEC)
    uiFloodMax = new.int(FLOOD_MAX_MSGS)
    uiMatWindow = new.int(MAT_WINDOW_MSGS)
    uiMatTrigger = new.int(MAT_TRIGGER_COUNT)
    uiCapsMin = new.int(CAPS_MIN_LEN)

    uiTheme.color = new.float[3](VIP_ACCENT[1], VIP_ACCENT[2], VIP_ACCENT[3])
end

local function vipFloat3ToHex(col)
    local function to255(v)
        v = math.floor(v * 255 + 0.5)
        if v < 0 then v = 0 end
        if v > 255 then v = 255 end
        return v
    end
    return string.format("%02X%02X%02X", to255(col[0]), to255(col[1]), to255(col[2]))
end

local function vipClampIntPtr(ptr, minVal)
    if ptr[0] < minVal then ptr[0] = minVal end
end

local function vipSettingIntInline(id, label, ptr, minVal, tooltip, width)
    imgui.AlignTextToFramePadding()
    imgui.TextColored(imgui.ImVec4(0.75, 0.77, 0.82, 1), u8(label))
    imgui.SameLine(0, 8)
    imgui.SetNextItemWidth(width or 120)
    local changed = imgui.InputInt('##' .. id, ptr)
    if tooltip and imgui.IsItemHovered() then
        imgui.SetTooltip(u8(tooltip))
    end
    vipClampIntPtr(ptr, minVal)
    return changed
end

function vipAvipUI.cardBegin(id, w, h, accentCol)
    imgui.BeginGroup()
    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.125, 0.13, 0.165, 1.0))
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(accentCol[1], accentCol[2], accentCol[3], 0.30))
    imgui.BeginChild('card_' .. id, imgui.ImVec2(w, h), true)
    local dl, pos = imgui.GetWindowDrawList(), imgui.GetWindowPos()
    dl:AddRectFilled(
        imgui.ImVec2(pos.x, pos.y), imgui.ImVec2(pos.x + 3, pos.y + imgui.GetWindowHeight()),
        vipPackColor(accentCol[1], accentCol[2], accentCol[3], 0.95))
end

function vipAvipUI.cardEnd()
    imgui.EndChild()
    imgui.PopStyleColor(2)
    imgui.EndGroup()
end

function vipAvipUI.cardTitle(icon, label, accentCol)
    local dl, textH = imgui.GetWindowDrawList(), imgui.GetTextLineHeight()
    local screenPos = imgui.GetCursorScreenPos()
    local r = textH * 0.32
    local cx, cy = screenPos.x + r, screenPos.y + textH / 2

    if icon == 'square' then
        dl:AddRectFilled(imgui.ImVec2(cx - r, cy - r), imgui.ImVec2(cx + r, cy + r),
            vipPackColor(accentCol[1], accentCol[2], accentCol[3], 1), 3)
    elseif icon == 'diamond' then
        dl:AddCircleFilled(imgui.ImVec2(cx, cy), r, vipPackColor(accentCol[1], accentCol[2], accentCol[3], 1), 4)
    else
        dl:AddCircleFilled(imgui.ImVec2(cx, cy), r, vipPackColor(accentCol[1], accentCol[2], accentCol[3], 1), 12)
    end

    imgui.SetCursorPosX(imgui.GetCursorPosX() + r * 2 + 8)
    imgui.TextColored(imgui.ImVec4(0.88, 0.90, 0.98, 1), u8(label))
    imgui.Dummy(imgui.ImVec2(0, 3))
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, 4))
end

function vipAvipUI.cardTitleInline(icon, label, desc, accentCol)
    local dl, textH = imgui.GetWindowDrawList(), imgui.GetTextLineHeight()
    local screenPos = imgui.GetCursorScreenPos()
    local r = textH * 0.32
    local cx, cy = screenPos.x + r, screenPos.y + textH / 2

    if icon == 'square' then
        dl:AddRectFilled(imgui.ImVec2(cx - r, cy - r), imgui.ImVec2(cx + r, cy + r),
            vipPackColor(accentCol[1], accentCol[2], accentCol[3], 1), 3)
    elseif icon == 'diamond' then
        dl:AddCircleFilled(imgui.ImVec2(cx, cy), r, vipPackColor(accentCol[1], accentCol[2], accentCol[3], 1), 4)
    else
        dl:AddCircleFilled(imgui.ImVec2(cx, cy), r, vipPackColor(accentCol[1], accentCol[2], accentCol[3], 1), 12)
    end

    imgui.SetCursorPosX(imgui.GetCursorPosX() + r * 2 + 8)
    imgui.TextColored(imgui.ImVec4(0.88, 0.90, 0.98, 1), u8(label))
    if desc and desc ~= '' then
        imgui.SameLine(0, 10)
        imgui.TextColored(imgui.ImVec4(0.55, 0.57, 0.62, 1), u8(desc))
    end
    imgui.Dummy(imgui.ImVec2(0, 6))
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, 8))
end

function vipAvipUI.colorSwatchRow(id, label, colorPtr, desc, innerW)
    local changed = imgui.ColorEdit3('##vipsw_' .. id, colorPtr, imgui.ColorEditFlags.NoInputs)
    imgui.SameLine(0, 8)
    imgui.TextColored(imgui.ImVec4(0.90, 0.91, 0.95, 1), u8(label))
    if desc then
        imgui.Dummy(imgui.ImVec2(0, 3))
        imgui.PushTextWrapPos(imgui.GetCursorPosX() + (innerW or 220))
        imgui.TextColored(imgui.ImVec4(0.55, 0.57, 0.62, 1), u8(desc))
        imgui.PopTextWrapPos()
    end
    return changed
end

function vipAvipUI.navItem(id, label, isActive, w)
    local h, dl = 42, imgui.GetWindowDrawList()
    local screenPos = imgui.GetCursorScreenPos()

    if isActive then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(VIP_ACCENT[1] * 0.32, VIP_ACCENT[2] * 0.32, VIP_ACCENT[3] * 0.32, 1))
    else
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
    end
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(VIP_ACCENT[1] * 0.22, VIP_ACCENT[2] * 0.22, VIP_ACCENT[3] * 0.22, 1))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(VIP_ACCENT[1] * 0.45, VIP_ACCENT[2] * 0.45, VIP_ACCENT[3] * 0.45, 1))

    local clicked = imgui.Button('##avipnav_' .. id, imgui.ImVec2(w, h))
    vipHoverHighlight(6)
    imgui.PopStyleColor(3)

    if isActive then
        dl:AddRectFilled(imgui.ImVec2(screenPos.x, screenPos.y + 6), imgui.ImVec2(screenPos.x + 3, screenPos.y + h - 6),
            vipPackColor(VIP_ACCENT[1], VIP_ACCENT[2], VIP_ACCENT[3], 1), 2)
    end

    local labelU8, textCol = u8(label), isActive and imgui.ImVec4(0.95, 0.96, 1, 1) or imgui.ImVec4(0.72, 0.74, 0.80, 1)
    local textSize = imgui.CalcTextSize(labelU8)
    dl:AddText(imgui.ImVec2(screenPos.x + 18, screenPos.y + (h - textSize.y) / 2),
        vipPackColor(textCol.x, textCol.y, textCol.z, 1), labelU8)

    return clicked
end

function vipAvipUI.drawColors(contentW)
    local changed, gap, colW = false, 12, 0
    colW = (contentW - gap) / 2

    vipAvipUI.cardBegin('theme_base', contentW, 130, {VIP_ACCENT[1], VIP_ACCENT[2], VIP_ACCENT[3]})
    do
        local innerW = imgui.GetContentRegionAvail().x
        local themeChanged = vipAvipUI.colorSwatchRow('theme_base', 'Цвет темы окна', uiTheme.color,
            'Основной цвет оформления окна — оттенки для градиентов и обводок подбираются автоматически', innerW)

        imgui.Dummy(imgui.ImVec2(0, 6))

        if themeChanged then
            vipApplyThemeColor(uiTheme.color[0], uiTheme.color[1], uiTheme.color[2])
            vipSaveSettings()
        end
    end
    vipAvipUI.cardEnd()

    imgui.Dummy(imgui.ImVec2(0, 4))

    local COLOR_ROWS = {
        {id = 'badword', label = 'Мат-слова', ptr = uiColorBadWord,
            desc = 'Подсветка нецензурного слова прямо в тексте сообщения'},
        {id = 'caps', label = 'КАПС', ptr = uiColorCaps,
            desc = 'Подсветка слова, написанного заглавными буквами'},
        {id = 'trade', label = 'Реклама/объявления', ptr = uiColorTrade,
            desc = 'Слово-триггер объявления: "продам", "куплю" и т.п.'},
        {id = 'flood', label = 'Флуд (строка)', ptr = uiColorFlood,
            desc = 'Вся строка, если игрок шлёт слишком много сообщений подряд'},
        {id = 'matwindow', label = 'Мат-окно (строка)', ptr = uiColorMatWindow,
            desc = 'Вся строка, если мат встречался несколько раз подряд'},
    }

    for i, row in ipairs(COLOR_ROWS) do
        vipAvipUI.cardBegin(row.id, colW, 116, {row.ptr[0], row.ptr[1], row.ptr[2]})
        local innerW = imgui.GetContentRegionAvail().x
        if vipAvipUI.colorSwatchRow(row.id, row.label, row.ptr, row.desc, innerW) then changed = true end
        vipAvipUI.cardEnd()

        if i % 2 == 1 and i < #COLOR_ROWS then
            imgui.SameLine(0, gap)
        else
            imgui.Dummy(imgui.ImVec2(0, 4))
        end
    end

    if changed then
        BAD_WORD_COLOR = vipFloat3ToHex(uiColorBadWord)
        CAPS_COLOR = vipFloat3ToHex(uiColorCaps)
        TRADE_HIGHLIGHT_COLOR = vipFloat3ToHex(uiColorTrade)
        FLOOD_COLOR = vipFloat3ToHex(uiColorFlood)
        MATWINDOW_COLOR = vipFloat3ToHex(uiColorMatWindow)
        vipSaveSettings()
    end
end

function vipAvipUI.drawDetect(contentW)
    local changed, gap, cardH = false, 10, 122

    local function fieldsRow(fields)
        for i, f in ipairs(fields) do
            if i > 1 then imgui.SameLine(0, 28) end
            if vipSettingIntInline(f.id, f.label, f.ptr, f.minVal, f.tooltip) then
                changed = true
            end
        end
    end

    vipAvipUI.cardBegin('flood_card', contentW, cardH, VIP_DANGER)
    vipAvipUI.cardTitleInline('diamond', 'Флуд', 'Слишком много сообщений подряд', VIP_DANGER)
    fieldsRow({
        {id = 'flood_win', label = 'Окно, сек', ptr = uiFloodWindow, minVal = 1,
            tooltip = 'За сколько секунд считаются сообщения игрока'},
        {id = 'flood_max', label = 'Макс. сообщ.', ptr = uiFloodMax, minVal = 1,
            tooltip = 'После скольки сообщений это считается флудом'},
    })
    vipAvipUI.cardEnd()

    imgui.Dummy(imgui.ImVec2(0, gap))

    vipAvipUI.cardBegin('mat_card', contentW, cardH, VIP_WARNING)
    vipAvipUI.cardTitleInline('square', 'Мат-окно', 'Мат в нескольких сообщениях подряд', VIP_WARNING)
    fieldsRow({
        {id = 'mat_win', label = 'Окно, сообщ.', ptr = uiMatWindow, minVal = 1,
            tooltip = 'Сколько последних сообщений учитывается'},
        {id = 'mat_trig', label = 'Триггер, слов', ptr = uiMatTrigger, minVal = 1,
            tooltip = 'Сколько матных слов нужно набрать'},
    })
    vipAvipUI.cardEnd()

    imgui.Dummy(imgui.ImVec2(0, gap))

    vipAvipUI.cardBegin('caps_card', contentW, cardH, VIP_ACCENT2)
    vipAvipUI.cardTitleInline('dot', 'Капс', 'Слово ЗАГЛАВНЫМИ буквами', VIP_ACCENT2)
    fieldsRow({
        {id = 'caps_min', label = 'Мин. длина', ptr = uiCapsMin, minVal = 1,
            tooltip = 'Минимальная длина слова из заглавных букв'},
    })
    vipAvipUI.cardEnd()

    if changed then
        FLOOD_WINDOW_SEC = uiFloodWindow[0]
        FLOOD_MAX_MSGS = uiFloodMax[0]
        MAT_WINDOW_MSGS = uiMatWindow[0]
        MAT_TRIGGER_COUNT = uiMatTrigger[0]
        CAPS_MIN_LEN = uiCapsMin[0]
        vipSaveSettings()
    end
end

local PUNISHMENT_BADGE_COLORS = {
    Ban    = {0.90, 0.28, 0.32},
    Mute   = {0.92, 0.62, 0.25},
    Rmute  = {0.88, 0.82, 0.30},
    Jail   = {0.62, 0.45, 0.92},
    Custom = {0.55, 0.58, 0.65},
}

local function vipDrawPunishmentsTab(contentW)
    vipAvipUI.cardBegin('newpun_card', contentW, 280, VIP_ACCENT)
    vipAvipUI.cardTitle('dot', 'Новое наказание', VIP_ACCENT)
    local innerW = imgui.GetContentRegionAvail().x

    local isCustomType = (PUNISHMENT_TYPES_RAW[punTypeIdx[0] + 1] == 'Custom')
    local fieldW = (innerW - 2 * 16) / 3

    imgui.BeginGroup()
    imgui.Text(u8'Название')
    imgui.SetNextItemWidth(fieldW)
    imgui.InputText('##pun_name', punNameBuf, ffi.sizeof(punNameBuf))
    imgui.EndGroup()
    imgui.SameLine(0, 16)

    imgui.BeginGroup()
    imgui.Text(u8'Тип')
    imgui.SetNextItemWidth(fieldW)
    local punTypeComboOpen = imgui.BeginCombo('##pun_type', PUNISHMENT_TYPES_U8[punTypeIdx[0] + 1])
    vipHoverHighlight(imgui.GetStyle().FrameRounding)
    if punTypeComboOpen then
        for i, label in ipairs(PUNISHMENT_TYPES_U8) do
            local isSelected = (punTypeIdx[0] == i - 1)
            if vipSelectable(label, isSelected) then
                punTypeIdx[0] = i - 1
            end
            if isSelected then
                imgui.SetItemDefaultFocus()
            end
        end
        imgui.EndCombo()
    end
    imgui.EndGroup()

    if not isCustomType then
        imgui.SameLine(0, 16)
        imgui.BeginGroup()
        imgui.Text(u8'Время')
        imgui.SetNextItemWidth(fieldW)
        imgui.InputText('##pun_time', punTimeBuf, ffi.sizeof(punTimeBuf), imgui.InputTextFlags.CharsDecimal)
        imgui.EndGroup()
    end

    imgui.Dummy(imgui.ImVec2(0, 6))
    if isCustomType then
        imgui.Text(u8'Команда (вместо ника укажите #), например: /mute # 10 Тест')
    else
        imgui.Text(u8'Причина')
    end
    imgui.SetNextItemWidth(innerW)
    imgui.InputText('##pun_reason', punReasonBuf, ffi.sizeof(punReasonBuf))

    imgui.Dummy(imgui.ImVec2(0, 10))
    if vipAnimatedButton('create_pun', u8'+  Создать наказание', 220, 32,
        {0.34, 0.50, 0.90}, {0.46, 0.62, 1.00}, {0.26, 0.40, 0.78}) then
        local name = ffi.string(punNameBuf)
        if name ~= "" then
            table.insert(vipPunishments, {
                name = name,
                ptype = PUNISHMENT_TYPES_RAW[punTypeIdx[0] + 1],
                time = isCustomType and '' or ffi.string(punTimeBuf),
                reason = ffi.string(punReasonBuf)
            })
            vipSavePunishments()
            punNameBuf[0] = 0
            punTimeBuf[0] = 0
            punReasonBuf[0] = 0
            punTypeIdx[0] = 0
        end
    end
    vipAvipUI.cardEnd()

    imgui.Dummy(imgui.ImVec2(0, 12))
    vipAvipUI.cardTitle('square', 'Список наказаний (' .. #vipPunishments .. ')', VIP_ACCENT2)

    do local r, g, b = vipTintBg(0.085, 0.09, 0.115, 0.07) imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(r, g, b, 1.0)) end
    imgui.BeginChild('pun_list', imgui.ImVec2(0, 0), true)

    if #vipPunishments == 0 then
        imgui.TextColored(imgui.ImVec4(0.55, 0.57, 0.62, 1), u8'Пока нет ни одного сохранённого наказания.')
    end

    local removeIdx, delBtnW, delBtnMargin = nil, 80, 8
    for i, p in ipairs(vipPunishments) do
        local reasonText, timeText, badge =
            (p.reason ~= "" and p.reason) or p.name, (p.time ~= "" and p.time) or '-', PUNISHMENT_BADGE_COLORS[p.ptype] or {0.6, 0.6, 0.6}

        local rowPos, dl = imgui.GetCursorScreenPos(), imgui.GetWindowDrawList()
        local rowAvailW = imgui.GetContentRegionAvail().x
        local rowH, textH = 30, imgui.GetTextLineHeight()
        dl:AddCircleFilled(imgui.ImVec2(rowPos.x + 6, rowPos.y + rowH / 2), 4,
            vipPackColor(badge[1], badge[2], badge[3], 1), 12)

        imgui.SetCursorScreenPos(imgui.ImVec2(rowPos.x + 18, rowPos.y + (rowH - textH) / 2))
        imgui.TextColored(imgui.ImVec4(badge[1], badge[2], badge[3], 1), p.ptype)
        imgui.SameLine(0, 10)
        imgui.TextColored(imgui.ImVec4(0.90, 0.91, 0.95, 1), p.name)
        imgui.SameLine(0, 10)
        imgui.TextColored(imgui.ImVec4(0.55, 0.57, 0.62, 1), timeText .. '  |  ' .. reasonText)

        imgui.SetCursorScreenPos(imgui.ImVec2(rowPos.x + rowAvailW - delBtnW - delBtnMargin, rowPos.y))
        if vipAnimatedButton('pun_del_' .. i, u8'Удалить', delBtnW, rowH - 4,
            {0.30, 0.16, 0.18}, {0.75, 0.24, 0.28}, {0.55, 0.16, 0.19}) then
            removeIdx = i
        end

        imgui.SetCursorScreenPos(imgui.ImVec2(rowPos.x, rowPos.y + rowH))
        if i < #vipPunishments then
            imgui.Separator()
        end
    end
    if removeIdx then
        table.remove(vipPunishments, removeIdx)
        vipSavePunishments()
    end
    imgui.EndChild()
    imgui.PopStyleColor(1)
end

imgui.OnFrame(function() return PUN.windowOpen[0] and vipWindowOpen[0] end, function(self)
    local usingUiFont = vipFontUI and vipFontUI ~= false
    if usingUiFont then imgui.PushFont(vipFontUI) end

    local nColors, savedVars = vipPushModernStyle()

    imgui.SetNextWindowPos(imgui.ImVec2(PUN.lastMainPos.x + 1020 + 10, PUN.lastMainPos.y), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(260, 0), imgui.Cond.FirstUseEver)
    imgui.Begin('###punwnd', PUN.windowOpen, imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoMove)

    do
        local punWinPos, punWinSize = imgui.GetWindowPos(), imgui.GetWindowSize()
        PUN.lastPunPos.x, PUN.lastPunPos.y = punWinPos.x, punWinPos.y
        PUN.lastPunSize.x, PUN.lastPunSize.y = punWinSize.x, punWinSize.y
    end

    if #vipPunishments == 0 then
        imgui.TextColored(imgui.ImVec4(0.55, 0.57, 0.62, 1),
            u8'Нет сохранённых наказаний.')
        imgui.Dummy(imgui.ImVec2(0, 4))
    else
        for i, p in ipairs(vipPunishments) do
            local badge = PUNISHMENT_BADGE_COLORS[p.ptype] or {0.6, 0.6, 0.6}
            if vipAnimatedButton('punbtn_' .. i, p.name, 220, 34,
                {badge[1] * 0.30, badge[2] * 0.30, badge[3] * 0.30},
                {badge[1] * 0.55, badge[2] * 0.55, badge[3] * 0.55},
                {badge[1] * 0.75, badge[2] * 0.75, badge[3] * 0.75}) then
                PUN.confirmPending = {label = p.name, ptype = p.ptype, time = p.time, reason = p.reason}
            end
            if imgui.IsItemHovered() then
                local target = PUN.targetOverride or vipCurrentFilter or '?'
                imgui.SetTooltip(vipBuildPunishPreview(target, p.ptype, p.time, p.reason))
            end
        end
    end

    if vipAnimatedButton('punbtn_custom', u8'Custom', 220, 34,
        {0.28, 0.20, 0.34}, {0.46, 0.30, 0.58}, {0.20, 0.14, 0.26}) then
        PUN.customWindowOpen[0] = true
    end

    imgui.End()

    if not PUN.windowOpen[0] then
        PUN.targetOverride = nil
        PUN.customWindowOpen[0] = false
        PUN_HIST.windowOpen[0] = false
    end

    vipRestoreStyleVars(savedVars)
    imgui.PopStyleColor(nColors)

    if usingUiFont then imgui.PopFont() end
end)

imgui.OnFrame(function() return PUN_HIST.windowOpen[0] and PUN.windowOpen[0] and vipWindowOpen[0] end, function(self)
    local usingUiFont = vipFontUI and vipFontUI ~= false
    if usingUiFont then imgui.PushFont(vipFontUI) end

    local nColors, savedVars = vipPushModernStyle()

    imgui.SetNextWindowPos(imgui.ImVec2(PUN.lastMainPos.x, PUN.lastMainPos.y + 520 + 10), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(1020, 0), imgui.Cond.Always)
    imgui.Begin('###punhistwnd', PUN_HIST.windowOpen, imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoMove)

    if #PUN_HIST.lines == 0 then
        imgui.TextColored(imgui.ImVec4(0.55, 0.57, 0.62, 1), u8'За последние 7 дней наказаний нет.')
    else
        local PUN_HIST_VISIBLE_ROWS, rowH = 5, imgui.GetTextLineHeightWithSpacing()
        local visibleRows = math.min(#PUN_HIST.lines, PUN_HIST_VISIBLE_ROWS)
        local childH = rowH * visibleRows + imgui.GetStyle().WindowPadding.y

        do local r, g, b = vipTintBg(0.085, 0.09, 0.115, 0.07) imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(r, g, b, 1.0)) end
        imgui.BeginChild('punhist_scroll', imgui.ImVec2(0, childH), true)
        for _, entry in ipairs(PUN_HIST.lines) do
            imgui.Text(u8(entry.text))
        end
        imgui.EndChild()
        imgui.PopStyleColor(1)
    end

    imgui.End()

    vipRestoreStyleVars(savedVars)
    imgui.PopStyleColor(nColors)

    if usingUiFont then imgui.PopFont() end
end)

imgui.OnFrame(function() return PUN.customWindowOpen[0] and PUN.windowOpen[0] and vipWindowOpen[0] end, function(self)
    local usingUiFont = vipFontUI and vipFontUI ~= false
    if usingUiFont then imgui.PushFont(vipFontUI) end

    local nColors, savedVars = vipPushModernStyle()

    imgui.SetNextWindowSize(imgui.ImVec2(420, 0), imgui.Cond.FirstUseEver)
    imgui.Begin('###puncustomwnd', PUN.customWindowOpen, imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoCollapse)

    imgui.Text(u8'Тип:')
    imgui.SetNextItemWidth(160)
    local punApplyComboOpen = imgui.BeginCombo('##punapply_type', PUNISHMENT_TYPES_U8[PUN.applyTypeIdx[0] + 1])
    vipHoverHighlight(imgui.GetStyle().FrameRounding)
    if punApplyComboOpen then
        for i, label in ipairs(PUNISHMENT_TYPES_U8) do
            local isSelected = (PUN.applyTypeIdx[0] == i - 1)
            if vipSelectable(label, isSelected) then
                PUN.applyTypeIdx[0] = i - 1
            end
            if isSelected then
                imgui.SetItemDefaultFocus()
            end
        end
        imgui.EndCombo()
    end

    local isCustomApply = (PUNISHMENT_TYPES_RAW[PUN.applyTypeIdx[0] + 1] == 'Custom')

    if not isCustomApply then
        imgui.Text(u8'Время:')
        imgui.SetNextItemWidth(160)
        imgui.InputText('##punapply_time', PUN.applyTimeBuf, ffi.sizeof(PUN.applyTimeBuf), imgui.InputTextFlags.CharsDecimal)
    end

    if isCustomApply then
        imgui.Text(u8'Команда (вместо ника укажите #):')
    else
        imgui.Text(u8'Причина:')
    end
    imgui.SetNextItemWidth(300)
    imgui.InputText('##punapply_reason', PUN.applyReasonBuf, ffi.sizeof(PUN.applyReasonBuf))

    imgui.Dummy(imgui.ImVec2(0, 8))
    if vipAnimatedButton('punapply_custom_go', u8'Выдать', 150, 34,
        {0.20, 0.55, 0.30}, {0.28, 0.75, 0.42}, {0.16, 0.42, 0.24}) then
        PUN.confirmPending = {
            label = 'Custom',
            ptype = PUNISHMENT_TYPES_RAW[PUN.applyTypeIdx[0] + 1],
            time = isCustomApply and '' or ffi.string(PUN.applyTimeBuf),
            reason = ffi.string(PUN.applyReasonBuf),
        }
    end

    imgui.End()

    vipRestoreStyleVars(savedVars)
    imgui.PopStyleColor(nColors)

    if usingUiFont then imgui.PopFont() end
end)

imgui.OnFrame(function() return PUN.confirmPending ~= nil end, function(self)
    local usingUiFont = vipFontUI and vipFontUI ~= false
    if usingUiFont then imgui.PushFont(vipFontUI) end

    local nColors, savedVars = vipPushModernStyle()
    local style = imgui.GetStyle()
    local prevTitleAlign = imgui.ImVec2(style.WindowTitleAlign.x, style.WindowTitleAlign.y)
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)

    if not PUN.confirmOpened then
        imgui.OpenPopup(u8'Подтверждение выдачи')
        PUN.confirmOpened = true
    end

    imgui.SetNextWindowSize(imgui.ImVec2(380, 0), imgui.Cond.Always)
    if imgui.BeginPopupModal(u8'Подтверждение выдачи', nil, imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoResize) then
        local target, p = PUN.targetOverride or vipCurrentFilter or '?', PUN.confirmPending
        local msg = u8('Выдать "') .. p.label .. u8('" игроку ') .. u8(target) .. u8('?')
        local msgSize = imgui.CalcTextSize(msg)
        imgui.SetCursorPosX((imgui.GetWindowWidth() - msgSize.x) / 2)
        imgui.Text(msg)
        imgui.Dummy(imgui.ImVec2(0, 10))

        local modalW = imgui.GetWindowWidth() - imgui.GetStyle().WindowPadding.x * 2
        local btnW = (modalW - 10) / 2

        if vipAnimatedButton('pun_conf_no', u8'Отмена', btnW, 34,
            {0.20, 0.22, 0.28}, {0.40, 0.44, 0.54}, {0.15, 0.16, 0.20}) then
            PUN.confirmPending = nil
            PUN.confirmOpened = false
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine(0, 10)
        if vipAnimatedButton('pun_conf_yes', u8'Выдать', btnW, 34,
            {0.20, 0.55, 0.30}, {0.28, 0.75, 0.42}, {0.16, 0.42, 0.24}) then
            vipApplyPunishment(target, p.ptype, p.time, p.reason)
            PUN.confirmPending = nil
            PUN.confirmOpened = false
            PUN.customWindowOpen[0] = false
            PUN.applyTimeBuf[0] = 0
            PUN.applyReasonBuf[0] = 0
            imgui.CloseCurrentPopup()
        end
        imgui.EndPopup()
    end

    style.WindowTitleAlign = prevTitleAlign
    vipRestoreStyleVars(savedVars)
    imgui.PopStyleColor(nColors)

    if usingUiFont then imgui.PopFont() end
end)

vipAvipUI.sections = {
    {id = 'colors', label = 'Цвета выделения'},
    {id = 'detect', label = 'Автоопределение'},
    {id = 'punish', label = 'Наказания'},
}

imgui.OnFrame(function() return avipWindowOpen[0] end, function(self)
    local usingUiFont = vipFontUI and vipFontUI ~= false
    if usingUiFont then imgui.PushFont(vipFontUI) end

    local nColors, savedVars = vipPushModernStyle()

    imgui.SetNextWindowSize(imgui.ImVec2(860, 640), imgui.Cond.Always)
    imgui.Begin(u8'Настройки VIPScanner###avipwnd', avipWindowOpen,
        imgui.WindowFlags.NoResize + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoCollapse
        + imgui.WindowFlags.NoScrollbar)

    local winW, winPos, dl = imgui.GetWindowWidth(), imgui.GetWindowPos(), imgui.GetWindowDrawList()

    dl:AddRectFilledMultiColor(
        imgui.ImVec2(winPos.x, winPos.y),
        imgui.ImVec2(winPos.x + winW, winPos.y + 3),
        vipPackColor(VIP_ACCENT[1], VIP_ACCENT[2], VIP_ACCENT[3], 0.9),
        vipPackColor(VIP_ACCENT2[1], VIP_ACCENT2[2], VIP_ACCENT2[3], 0.9),
        vipPackColor(VIP_ACCENT2[1], VIP_ACCENT2[2], VIP_ACCENT2[3], 0.2),
        vipPackColor(VIP_ACCENT[1], VIP_ACCENT[2], VIP_ACCENT[3], 0.2)
    )

    local btnSize, topY = 24, 9

    imgui.SetCursorPos(imgui.ImVec2(winW - btnSize - 12, topY))
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0, 0, 0, 0))
    local btnScreenPos, closeClicked =
        imgui.GetCursorScreenPos(), imgui.Button(u8'##avipclose', imgui.ImVec2(btnSize, btnSize))
    local closeHovered = imgui.IsItemHovered()
    imgui.PopStyleColor(3)

    vipDrawImageButton(btnScreenPos, btnSize, 'close', 'closebutton', closeHovered)

    if closeClicked then
        avipWindowOpen[0] = false
    end

    local titleLabel = u8'Настройки VIPScanner'
    imgui.SetCursorPos(imgui.ImVec2(20, topY + (btnSize - imgui.CalcTextSize(titleLabel).y) / 2))
    imgui.TextColored(imgui.ImVec4(0.72, 0.80, 0.98, 1), titleLabel)

    imgui.SetCursorPosY(topY + btnSize + 14)

    local bodyY = imgui.GetCursorPosY()
    local navW, gap = 210, 16
    local bodyH = imgui.GetWindowHeight() - bodyY - imgui.GetStyle().WindowPadding.y

    do local r, g, b = vipTintBg(0.085, 0.09, 0.115, 0.07) imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(r, g, b, 1.0)) end
    imgui.BeginChild('avip_nav', imgui.ImVec2(navW, bodyH), true)
    imgui.Dummy(imgui.ImVec2(0, 4))
    for _, sec in ipairs(vipAvipUI.sections) do
        if vipAvipUI.navItem(sec.id, sec.label, vipAvipUI.activeSection == sec.id, navW - 24) then
            vipAvipUI.activeSection = sec.id
        end
        imgui.Dummy(imgui.ImVec2(0, 3))
    end
    imgui.EndChild()
    imgui.PopStyleColor(1)

    imgui.SameLine(0, gap)

    do local r, g, b = vipTintBg(0.075, 0.08, 0.10, 0.07) imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(r, g, b, 1.0)) end
    imgui.BeginChild('avip_content', imgui.ImVec2(0, bodyH), false)
    local contentW = imgui.GetContentRegionAvail().x

    if vipAvipUI.activeSection == 'colors' then
        vipAvipUI.drawColors(contentW)
    elseif vipAvipUI.activeSection == 'detect' then
        vipAvipUI.drawDetect(contentW)
    elseif vipAvipUI.activeSection == 'punish' then
        vipDrawPunishmentsTab(contentW)
    end

    imgui.EndChild()
    imgui.PopStyleColor(1)

    imgui.End()

    vipRestoreStyleVars(savedVars)
    imgui.PopStyleColor(nColors)

    if usingUiFont then imgui.PopFont() end
end)

imgui.OnFrame(function() return VIP_SCR.windowOpen[0] and vipWindowOpen[0] end, function(self)
    local usingUiFont = vipFontUI and vipFontUI ~= false
    if usingUiFont then imgui.PushFont(vipFontUI) end

    local nColors, savedVars = vipPushModernStyle()

    local uiStyle, minContentW = imgui.GetStyle(), 260
    local maxContentW = minContentW
    for _, shot in ipairs(VIP_SCR.list) do
        local nickStr, typeStr, timeStr =
            (shot.nick and shot.nick ~= '') and shot.nick or '?', (shot.ptype and shot.ptype ~= '') and shot.ptype or '-', os.date('%d.%m.%Y %H:%M:%S', shot.time)
        local lineU8 = u8(timeStr .. '   ' .. nickStr .. '  |  ' .. typeStr)
        local lineW = imgui.CalcTextSize(lineU8).x
        if lineW > maxContentW then maxContentW = lineW end
    end

    local scrollbarAllowance = uiStyle.ScrollbarSize + 12
    local scrWinW = maxContentW + uiStyle.WindowPadding.x * 4 + scrollbarAllowance
    if scrWinW < 300 then scrWinW = 300 end
    if scrWinW > 600 then scrWinW = 600 end

    imgui.SetNextWindowPos(imgui.ImVec2(PUN.lastMainPos.x - scrWinW - 10, PUN.lastMainPos.y), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(scrWinW, 440), imgui.Cond.Always)
    imgui.Begin('###vipscreenswnd', VIP_SCR.windowOpen,
        imgui.WindowFlags.NoResize + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoMove)

    if #VIP_SCR.list == 0 then
        imgui.TextColored(imgui.ImVec4(0.55, 0.57, 0.62, 1),
            u8'Скриншотов пока нет. Они появляются здесь автоматически после каждой выдачи наказания (F8).')
    else
        do local r, g, b = vipTintBg(0.085, 0.09, 0.115, 0.07) imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(r, g, b, 1.0)) end
        imgui.BeginChild('vip_screens_list', imgui.ImVec2(0, 0), true)

        local rowBtnW = imgui.GetContentRegionAvail().x
        for i, shot in ipairs(VIP_SCR.list) do
            local timeStr, nickStr, typeStr =
                os.date('%d.%m.%Y %H:%M:%S', shot.time), (shot.nick and shot.nick ~= '') and shot.nick or '?', (shot.ptype and shot.ptype ~= '') and shot.ptype or '-'

            imgui.TextColored(imgui.ImVec4(0.72, 0.80, 0.98, 1), u8(timeStr))
            imgui.SameLine(0, 10)
            imgui.TextColored(imgui.ImVec4(0.93, 0.94, 0.97, 1), u8(string.format('%s  |  %s', nickStr, typeStr)))

            if vipAnimatedButton('vip_shot_open_' .. i, u8'Открыть в папке', rowBtnW, 28,
                {0.20, 0.22, 0.28}, {0.34, 0.50, 0.90}, {0.26, 0.40, 0.78}) then
                VIP_SCR.openFolder(shot.path)
            end

            local hasApiKey = VIP_SCR.freeimageApiKey and VIP_SCR.freeimageApiKey ~= ''
            local needsApiKey, copyLabel =
                not shot.uploadedUrl and not hasApiKey and not shot.uploadPending, shot.uploadPending and u8'Загрузка...' or u8'Копировать URL'

            if needsApiKey then pcall(imgui.BeginDisabled, true) end
            local copyClicked = vipAnimatedButton('vip_shot_copy_' .. i, copyLabel, rowBtnW, 28,
                {0.20, 0.22, 0.28}, {0.34, 0.50, 0.90}, {0.26, 0.40, 0.78})
            local copyHovered = imgui.IsItemHovered()
            if needsApiKey then pcall(imgui.EndDisabled) end

            if copyClicked and not needsApiKey and not shot.uploadPending then
                if shot.uploadedUrl then
                    vipCopyToClipboard(shot.uploadedUrl)
                    sampAddChatMessage('[VIP] {A2DAC1}Ссылка скопирована в буфер обмена', 0xA2DAC1)
                else
                    vipStartImageUpload(shot)
                end
            end

            if copyHovered then
                if needsApiKey then
                    imgui.SetTooltip(u8'API-ключ freeimage.host ещё не получен, попробуйте позже')
                elseif shot.uploadedUrl then
                    imgui.SetTooltip(u8(shot.uploadedUrl))
                end
            end

            if not doesFileExist(shot.path) then
                imgui.TextColored(imgui.ImVec4(0.92, 0.30, 0.34, 1), u8'файл не найден')
            end

            imgui.Dummy(imgui.ImVec2(0, 4))
            imgui.Separator()
            imgui.Dummy(imgui.ImVec2(0, 4))
        end
        imgui.EndChild()
        imgui.PopStyleColor(1)
    end

    imgui.End()

    vipRestoreStyleVars(savedVars)
    imgui.PopStyleColor(nColors)

    if usingUiFont then imgui.PopFont() end
end)

imgui.OnFrame(function()

    if VIP_NOTIFY.active and os.clock() >= VIP_NOTIFY.untilClock then
        VIP_NOTIFY.active = false
        VIP_NOTIFY.nick = nil
    end

    return VIP_NOTIFY.active or (VIP_NOTIFY.animT or 0) > 0
end, function(self)
    local usingUiFont = vipFontUI and vipFontUI ~= false
    if usingUiFont then imgui.PushFont(vipFontUI) end

    local dt = imgui.GetIO().DeltaTime
    if VIP_NOTIFY.active then
        VIP_NOTIFY.animT = math.min((VIP_NOTIFY.animT or 0) + dt * 6.0, 1.0)
    else
        VIP_NOTIFY.animT = math.max((VIP_NOTIFY.animT or 0) - dt * 6.0, 0.0)
    end

    local enterDownNow = vipIsKeyDownNow(0x0D)
    if enterDownNow and not VIP_NOTIFY.enterWasDown then
        if not vipIsAnyGameInterfaceActive() then
            local nick = VIP_NOTIFY.nick
            VIP_NOTIFY.active = false
            VIP_NOTIFY.enterWasDown = false
            if nick then
                vipCurrentFilter = nick
                vipViewingFile = nil
                vipLines = vipLoadLines(nick)
                vipWindowOpen[0] = true
                PUN.targetOverride = nil
                PUN.windowOpen[0] = true
                vipRequestPunishHistory(nick)
            end
        else
            -- какой-то интерфейс SAMP открыт (например, чат) — не перехватываем Enter,
            -- просто запоминаем, что клавиша нажата, чтобы не сработать повторно на этом же нажатии
            VIP_NOTIFY.enterWasDown = enterDownNow
        end
    else
        VIP_NOTIFY.enterWasDown = enterDownNow
    end

    local animT = VIP_NOTIFY.animT or 0
    if animT > 0 then

        local eased = 1 - (1 - animT) ^ 3
        local overshoot = math.sin(animT * math.pi) * 5
        local slideOffset = (1 - eased) * 60 - overshoot
        local alpha = eased

        local dispIO = imgui.GetIO()
        local screenW, screenH = dispIO.DisplaySize.x, dispIO.DisplaySize.y

        local titleU8, subU8 = u8'Есть нарушение!', u8'Наказать:'
        local titleSize, subSize = imgui.CalcTextSize(titleU8), imgui.CalcTextSize(subU8)

        local padX, iconD = 14, 20
        local gapIconText, gapTitleSub, gapSubEnter = 10, 18, 8
        local enterW, enterH = 48, 15.4
        local rounding = 14

        local barH, barMarginX, barMarginBottom, gapTextToBar = 4, 12, 9, 10

        local rowH = math.max(titleSize.y, subSize.y, enterH)
        local winH = 12 + rowH + gapTextToBar + barH + barMarginBottom
        local winW = padX + iconD + gapIconText + titleSize.x + gapTitleSub
            + subSize.x + gapSubEnter + enterW + padX

        imgui.SetNextWindowPos(
            imgui.ImVec2(screenW / 2, screenH - 46 + slideOffset),
            imgui.Cond.Always,
            imgui.ImVec2(0.5, 1.0)
        )
        imgui.SetNextWindowSize(imgui.ImVec2(winW, winH), imgui.Cond.Always)
        imgui.SetNextWindowBgAlpha(0)

        local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoInputs
            + imgui.WindowFlags.NoNav + imgui.WindowFlags.NoFocusOnAppearing
            + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoSavedSettings
            + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoBackground
            + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse

        local notifyStyle = imgui.GetStyle()
        local prevNotifyBorderSize = notifyStyle.WindowBorderSize
        local prevWindowPadding = notifyStyle.WindowPadding
        local prevWindowRounding = notifyStyle.WindowRounding
        local prevFramePadding = notifyStyle.FramePadding
        local prevGrabMinSize = notifyStyle.GrabMinSize

        notifyStyle.WindowBorderSize = 0
        notifyStyle.WindowPadding = imgui.ImVec2(0, 0)
        notifyStyle.WindowRounding = 0
        notifyStyle.FramePadding = imgui.ImVec2(0, 0)
        notifyStyle.GrabMinSize = 0

        imgui.Begin('###vipnotifywnd', nil, flags)

        self.HideCursor = true

        do
            local capIO = imgui.GetIO()
            capIO.WantCaptureMouse = false
            capIO.WantCaptureKeyboard = false
        end

        local pos, dl = imgui.GetWindowPos(), imgui.GetWindowDrawList()

        local x0, y0 = pos.x, pos.y
        local x1, y1 = x0 + winW, y0 + winH

        dl:AddRectFilled(imgui.ImVec2(x0, y0), imgui.ImVec2(x1, y1),
            vipPackColor(0.07, 0.075, 0.095, 0.98 * alpha), rounding)

        dl:AddRectFilled(imgui.ImVec2(x0 + 1, y0 + 1), imgui.ImVec2(x1 - 1, y1 - 1),
            vipPackColor(0.05, 0.055, 0.075, 0.4 * alpha), rounding - 1)

        dl:AddRectFilled(imgui.ImVec2(x0 + 2, y0 + 1), imgui.ImVec2(x1 - 2, y0 + 2),
            vipPackColor(1, 1, 1, 0.05 * alpha), rounding - 2)

        local stripInset = rounding * 0.7
        local stripY0, stripY1 = y0 + 1, y0 + 3

        dl:AddRectFilledMultiColor(
            imgui.ImVec2(x0 + stripInset, stripY0),
            imgui.ImVec2(x1 - stripInset, stripY1),
            vipPackColor(VIP_ACCENT[1], VIP_ACCENT[2], VIP_ACCENT[3], 0.9 * alpha),
            vipPackColor(VIP_ACCENT2[1], VIP_ACCENT2[2], VIP_ACCENT2[3], 0.9 * alpha),
            vipPackColor(VIP_ACCENT2[1], VIP_ACCENT2[2], VIP_ACCENT2[3], 0.2 * alpha),
            vipPackColor(VIP_ACCENT[1], VIP_ACCENT[2], VIP_ACCENT[3], 0.2 * alpha)
        )

        local cursorX, centerY = x0 + padX, y0 + 12 + rowH / 2

        local pulse = 0.5 + 0.5 * math.sin(imgui.GetTime() * 5.0)
        local iconCx, iconCy, iconR = cursorX + iconD / 2, centerY, iconD / 2 - 1
        dl:AddCircleFilled(imgui.ImVec2(iconCx, iconCy), iconR + 6,
            vipPackColor(VIP_DANGER[1], VIP_DANGER[2], VIP_DANGER[3], 0.18 * pulse * alpha), 20)
        dl:AddTriangleFilled(
            imgui.ImVec2(iconCx, iconCy - iconR),
            imgui.ImVec2(iconCx - iconR * 0.95, iconCy + iconR * 0.8),
            imgui.ImVec2(iconCx + iconR * 0.95, iconCy + iconR * 0.8),
            vipPackColor(VIP_DANGER[1], VIP_DANGER[2], VIP_DANGER[3], alpha))
        dl:AddLine(imgui.ImVec2(iconCx, iconCy - 3), imgui.ImVec2(iconCx, iconCy + 2),
            vipPackColor(0.07, 0.075, 0.095, alpha), 1.6)
        dl:AddCircleFilled(imgui.ImVec2(iconCx, iconCy + 4.5), 1.0,
            vipPackColor(0.07, 0.075, 0.095, alpha), 8)
        cursorX = cursorX + iconD + gapIconText

        dl:AddText(imgui.ImVec2(cursorX, centerY - titleSize.y / 2),
            vipPackColor(VIP_DANGER[1], VIP_DANGER[2], VIP_DANGER[3], alpha), titleU8)
        cursorX = cursorX + titleSize.x + gapTitleSub

        dl:AddText(imgui.ImVec2(cursorX, centerY - subSize.y / 2),
            vipPackColor(0.93, 0.94, 0.97, alpha), subU8)
        cursorX = cursorX + subSize.x + gapSubEnter

        local enterTex = vipLoadEmojiTexture('enter')
        if enterTex.texture then
            local p0 = imgui.ImVec2(cursorX, centerY - enterH / 2)
            local p1 = imgui.ImVec2(p0.x + enterW, p0.y + enterH)
            dl:AddImage(enterTex.texture, p0, p1)
        else
            dl:AddText(imgui.ImVec2(cursorX, centerY - subSize.y / 2),
                vipPackColor(0.55, 0.57, 0.62, alpha), u8'[Enter]')
        end

        local remain = 0
        if VIP_NOTIFY.active then
            remain = (VIP_NOTIFY.untilClock - os.clock()) / VIP_NOTIFY.holdSec
            if remain < 0 then remain = 0 elseif remain > 1 then remain = 1 end
        end

        local trackX0, trackX1 = x0 + barMarginX, x1 - barMarginX
        local barY0, barY1 = y1 - barMarginBottom - barH, y1 - barMarginBottom
        local barRounding = barH / 2

        dl:AddRectFilled(imgui.ImVec2(trackX0, barY0), imgui.ImVec2(trackX1, barY1),
            vipPackColor(1, 1, 1, 0.08 * alpha), barRounding)
        if remain > 0 then
            local barX1 = trackX0 + (trackX1 - trackX0) * remain
            dl:AddRectFilled(imgui.ImVec2(trackX0, barY0), imgui.ImVec2(barX1, barY1),
                vipPackColor(VIP_DANGER[1] + (VIP_WARNING[1] - VIP_DANGER[1]) * (1 - remain),
                    VIP_DANGER[2] + (VIP_WARNING[2] - VIP_DANGER[2]) * (1 - remain),
                    VIP_DANGER[3] + (VIP_WARNING[3] - VIP_DANGER[3]) * (1 - remain), 0.95 * alpha), barRounding)
            dl:AddRectFilled(imgui.ImVec2(math.max(trackX0, barX1 - 3), barY0), imgui.ImVec2(barX1, barY1),
                vipPackColor(1, 1, 1, 0.55 * alpha), barRounding)
        end

        imgui.End()

        notifyStyle.WindowBorderSize = prevNotifyBorderSize
        notifyStyle.WindowPadding = prevWindowPadding
        notifyStyle.WindowRounding = prevWindowRounding
        notifyStyle.FramePadding = prevFramePadding
        notifyStyle.GrabMinSize = prevGrabMinSize
    end

    if usingUiFont then imgui.PopFont() end
end)

function sampev.onServerMessage(color, text)
    if vipIsDuplicateRawMessage(color, text) then
        return false
    end

    local matchedPrefix = vipGetMatchedPrefix(text)
    if matchedPrefix then
        local msgStart, includeTrade = vipFindMessageStart(text), not TRADE_EXCLUDED_PREFIXES[matchedPrefix]
        local ranges = vipFindAllHighlightRanges(text, msgStart, includeTrade)

        local badWordTexts = {}
        for _, r in ipairs(vipFindAllBadWordRanges(text, msgStart)) do
            table.insert(badWordTexts, text:sub(r.s, r.e))
        end

        local capsS, capsE = vipFindNextCapsRange(text, msgStart)
        local capsText = capsS and text:sub(capsS, capsE) or nil

        local tradeText = nil
        if includeTrade then
            local tradeS, tradeE = vipFindNextTradeRange(text, msgStart)
            tradeText = tradeS and text:sub(tradeS, tradeE) or nil
        end

        local savedText, overrideChat = text, false
        if #ranges > 0 then
            savedText = censorTextMultiple(text, color, ranges)
            sampAddChatMessage(savedText, convertSampColorToRGB(color))
            overrideChat = true
        end

        local entry = vipSaveLine(color, savedText)
        if entry then
            local nick = vipParseNickId(text)
            vipRegisterFloodEntry(nick, entry)
            vipRegisterMatEntry(nick, entry, badWordTexts)
            if capsText then
                vipRegisterCapsEntry(nick, capsText)
            end
            if tradeText then
                vipRegisterTradeEntry(nick, tradeText)
            end
        end

        if overrideChat then
            return false
        end
    end
end

function sampev.onShowDialog(dialogId, style, caption, button1, button2, text)

    local capClean = (caption or ''):gsub("^{%x%x%x%x%x%x}", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not capClean:find(PUN_HIST.title, 1, true) then

        if capClean:find('наказ', 1, true) then
            sampAddChatMessage('[VIP] {FFA500}Диалог с "наказ" не распознан как история. Заголовок: {FFFFFF}[' .. capClean .. ']', 0xFFA500)
        end
        return
    end

    if (os.clock() - PUN_HIST.lastCheckTime) > PUN_HIST.matchWindow then
        return
    end

    local cutoff, filtered, normalized = os.time() - PUN_HIST.windowSec, {}, (text or ''):gsub('\r\n', '\n')
    for line in (normalized .. '\n'):gmatch("(.-)\n") do
        if line ~= "" then
            local ts = vipParsePunishHistDate(line)
            if ts and ts >= cutoff then
                local cleanLine = line:gsub("{%x%x%x%x%x%x}", "")
                table.insert(filtered, {text = cleanLine, time = ts})
            end
        end
    end
    table.sort(filtered, function(a, b) return a.time > b.time end)

    PUN_HIST.lines = filtered
    PUN_HIST.windowOpen[0] = true

    return false
end

addEventHandler('onScriptTerminate', function(scr, quitGame)
    if scr == thisScript() and vipLogFlush.dirty then
        vipRewriteLogFile()
    end
    if scr == thisScript() and vipChatEmoji and vipChatEmojiTexLoaded then
        pcall(vipChatEmoji.unload)
    end
end)

addEventHandler('onWindowMessage', function(msg, wparam, lparam)
    local wm = require 'windows.message'
    if wparam == 27 then
        if vipWindowOpen[0] or avipWindowOpen[0] then
            if msg == wm.WM_KEYDOWN then
                consumeWindowMessage(true, false)
            end
            if msg == wm.WM_KEYUP then
                vipWindowOpen[0] = false
                avipWindowOpen[0] = false
            end
        end
    end
end)

-- Вспомогательные функции для main()
local function vipToUtf8(s)
    if not s or s == "" then return s end
    local ok, converted = pcall(function() return u8(s) end)
    return (ok and converted) or s
end

local function vipParsePunishmentsFile(content)
    local result = {}
    if not content then return result end
    content = content:gsub("\r\n", "\n"):gsub("\r", "\n")

    for line in (content .. "\n"):gmatch("(.-)\n") do
        if line ~= "" and line ~= "[PUNISHMENTS]" then
            local name, ptype, time, reason = line:match("^(.-)	(.-)	(.-)	(.*)$")
            if name and name ~= "" then
                table.insert(result, {
                    name = vipToUtf8(name),
                    ptype = ptype,
                    time = time,
                    reason = vipToUtf8(reason),
                })
            end
        end
    end
    return result
end

local function vipHandleVipCommand(param)
    param = (param or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local filter, notFound = param ~= "" and param or nil, false

    if filter and filter:match("^%d+$") then
        local requestedId = filter
        local nick = vipFindNickById(requestedId)
        if nick then
            filter = nick
        else
            sampAddChatMessage(("[VIP]   id " .. requestedId .. "    ."), 0xFF0000)
            notFound = true
        end
    end

    if notFound then
        return
    end

    vipCurrentFilter = filter
    vipViewingFile = nil
    vipLines = vipLoadLines(filter)
    vipWindowOpen[0] = true

    PUN.targetOverride = nil
    PUN.windowOpen[0] = (filter ~= nil)
    if PUN.windowOpen[0] then
        vipRequestPunishHistory(filter)
    end
end

function main()
    while not isSampAvailable() do wait(100) end
    vipSetupBadWords()
    vipSetupWhitelist()
    vipSetupImgData()
    vipSetupCustomFont()
    vipSetupApiKey()
    vipSetupChatEmojiLib()
    vipLoadFloodWhitelist()
    vipLoadItemsCache()
    vipInitTradeWords()
    vipLoadSettingsFile()
    vipInitSettingsUI()
    VIP_SCR.loadHistory()
    VIP_SCR.autoDetectRootOnStartup()

    if #vipPunishments == 0 then
        local function parsePunishmentsFile(content)
            local result = {}
            if not content then return result end
            content = content:gsub("\r\n", "\n"):gsub("\r", "\n")

            local function toUtf8(s)
                if not s or s == "" then return s end
                local ok, converted = pcall(function() return u8(s) end)
                return (ok and converted) or s
            end

            for line in (content .. "\n"):gmatch("(.-)\n") do
                if line ~= "" and line ~= "[PUNISHMENTS]" then
                    local name, ptype, time, reason = line:match("^(.-)\t(.-)\t(.-)\t(.*)$")
                    if name and name ~= "" then
                        table.insert(result, {
                            name = toUtf8(name),
                            ptype = ptype,
                            time = time,
                            reason = toUtf8(reason),
                        })
                    end
                end
            end
            return result
        end

        local defPunUrl, defPunTmpPath =
            'https://gitverse.ru/api/repos/Nehto/VipScaner/raw/branch/master/punishments.txt',
            VIP_LOG_DIR .. '\\punishments_tmp.txt'

        vipRunAsync(vipThreadDownloadFile, function(ok)
            if not ok then
                sampAddChatMessage('[VIP] {FF0000}Не удалось скачать список наказаний по умолчанию (punishments.txt)', 0xFF0000)
                os.remove(defPunTmpPath)
                return
            end

            local f = io.open(defPunTmpPath, 'rb')
            if not f then
                sampAddChatMessage('[VIP] {FF0000}Не удалось открыть скачанный файл наказаний', 0xFF0000)
                os.remove(defPunTmpPath)
                return
            end
            local content = f:read('*a')
            f:close()
            os.remove(defPunTmpPath)

            local parsed = parsePunishmentsFile(content)
            if #parsed == 0 then
                sampAddChatMessage('[VIP] {FF0000}Файл наказаний по умолчанию пуст или повреждён', 0xFF0000)
                return
            end

            if #vipPunishments == 0 then
                vipPunishments = parsed
                vipSavePunishments()
                sampAddChatMessage(string.format('[VIP] {A2DAC1}Загружено %d наказаний по умолчанию', #parsed), 0xA2DAC1)
            end
        end, defPunUrl, defPunTmpPath)
    end

    sampRegisterChatCommand('avip', function()
        avipWindowOpen[0] = true
    end)

    sampRegisterChatCommand('vipss', function()
        VIP_SCR.windowOpen[0] = not VIP_SCR.windowOpen[0]
    end)

    sampRegisterChatCommand('tw', function()
        vipShowViolationNotify('Test_Player')
    end)

    sampRegisterChatCommand('vip', function(param)
        param = (param or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local filter, notFound = param ~= "" and param or nil, false

        if filter and filter:match("^%d+$") then
            local requestedId = filter
            local nick = vipFindNickById(requestedId)
            if nick then
                filter = nick
            else
                sampAddChatMessage(("[VIP] Игрок с id " .. requestedId .. " сейчас не в сети."), 0xFF0000)
                notFound = true
            end
        end

        if notFound then
            return
        end

        vipCurrentFilter = filter
        vipViewingFile = nil
        vipLines = vipLoadLines(filter)
        vipWindowOpen[0] = true

        PUN.targetOverride = nil
        PUN.windowOpen[0] = (filter ~= nil)
        if PUN.windowOpen[0] then
            vipRequestPunishHistory(filter)
        end
    end)

    while true do
        vipPollAsyncTasks()
        vipPollCheckPunishQueue()
        vipPollUploadChannels()
        vipLogFlush.poll()
        wait(0)
    end
end