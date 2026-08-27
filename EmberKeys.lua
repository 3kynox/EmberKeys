-- EmberKeys
--
-- The Emberveil client resolves keys that produce a non-ASCII character
-- (é è ç à on AZERTY, umlauts, Cyrillic letters...) to dynamic engine key ids
-- "UNKNOWNCHARCODE_<code>", where <code> is the UPPERCASE character code
-- (É=201, È=200, Ç=199, À=192). Unreal only registers such a key at the FIRST
-- press of the key within the client session; before that, the name resolves
-- to no known key: loading Keybinds.ini silently drops the binding and
-- SetBinding is an equally silent no-op. After one press, SetBinding works
-- and the binding holds until the client closes.
--
-- Strategy: remember those bindings in SavedVariables (the game's own file
-- cannot retain them) and quietly re-apply them in a loop until each key has
-- been pressed once. No keyboard capture: keyboard-enabled frames confiscate
-- all input on this client.
--
-- This addon is a workaround. Once the developers fix the client (bug
-- reported), it becomes obsolete and can simply be deleted.

local ADDON_VERSION = "0.9.0"

-- Known layouts. `digits`: uppercase char code -> digit printed on the
-- physical key (for button corner labels). `defaults`: bindings installed
-- when the preset is applied.
local LAYOUT_PRESETS = {
  azerty = {
    title = "AZERTY (fr)",
    digits = { [201] = "2", [200] = "7", [199] = "9", [192] = "0" },
    defaults = {
      ["UNKNOWNCHARCODE_201"] = "ACTIONBUTTON2",
      ["UNKNOWNCHARCODE_200"] = "ACTIONBUTTON7",
      ["UNKNOWNCHARCODE_199"] = "ACTIONBUTTON9",
      ["UNKNOWNCHARCODE_192"] = "ACTIONBUTTON10",
    },
  },
}

-- Digits of every preset merged, for display.
local DIGIT_LABEL = {}
do
  local _, preset, code, digit
  for _, preset in pairs(LAYOUT_PRESETS) do
    for code, digit in pairs(preset.digits) do DIGIT_LABEL[code] = digit end
  end
end

-- Static engine names that both UIs render poorly (truncated).
-- LEFTPARANTHESES is intentionally absent: unrealUI already renders it
-- correctly ("5"); overriding it here would be a regression.
local ENGINE_LABEL = {
  ["RIGHTPARANTHESES"] = ")",
}

-- ---------------------------------------------------------------------------
-- Localization: English by default, French on frFR clients.
-- ---------------------------------------------------------------------------

local L = {
  RESTORED       = "re-attached: ",
  ALL_ACTIVE     = "all your bindings are active.",
  PRESS_ONCE_1   = "press each of these keys once: ",
  PRESS_ONCE_2   = " - the bindings will re-attach on their own"
                .. " (pressing them at the character-select screen works too).",
  ACTION         = "Action ",
  SELF_ACTION    = "Self Action ",
  BAR            = "Bar ",
  BUTTON         = " button ",
  ST_VERSION     = " - remembered bindings:",
  ST_WAITING     = "waiting for its first key press",
  ST_ACTIVE      = "active",
  ST_INACTIVE    = "inactive",
  ST_NONE        = "  (none - bind your keys normally in the UI,"
                .. " EmberKeys will remember them)",
  ST_HELP        = "commands: /ek default (installs the AZERTY digit row), "
                .. "/ek reset (clears the memory), /ek diag",
  PRESET_UNKNOWN = "unknown layout - available: ",
  PRESET_WAIT    = ": bindings stored; press once: ",
  PRESET_DONE    = ": bindings stored and active.",
  RESET_DONE     = "memory cleared. Keys already active stay so until the"
                .. " game closes; bindings you make in the UI from now on"
                .. " will be remembered again.",
}

local isFR = false
do
  local ok, loc = pcall(GetLocale)
  isFR = ok and loc == "frFR"
end

if isFR then
  L.RESTORED       = "rebranché : "
  L.ALL_ACTIVE     = "tous les raccourcis sont actifs."
  L.PRESS_ONCE_1   = "appuyez une fois sur chaque touche à réactiver : "
  L.PRESS_ONCE_2   = " ; les raccourcis se rebrancheront tout seuls"
                  .. " (ces frappes marchent aussi dès l'écran de personnages)."
  L.ACTION         = "Action "
  L.SELF_ACTION    = "Self Action "
  L.BAR            = "Barre "
  L.BUTTON         = " bouton "
  L.ST_VERSION     = " ; liaisons mémorisées :"
  L.ST_WAITING     = "en attente d'une première frappe"
  L.ST_ACTIVE      = "active"
  L.ST_INACTIVE    = "inactive"
  L.ST_NONE        = "  (aucune ; liez vos touches normalement dans"
                  .. " l'interface, EmberKeys les retiendra)"
  L.ST_HELP        = "commandes : /ek defaut (pose la rangée AZERTY), "
                  .. "/ek raz (vide la mémoire), /ek diag"
  L.PRESET_UNKNOWN = "disposition inconnue ; disponibles : "
  L.PRESET_WAIT    = " : liaisons posées ; appuyez une fois sur : "
  L.PRESET_DONE    = " : liaisons posées et actives."
  L.RESET_DONE     = "mémoire vidée. Les touches déjà actives le restent"
                  .. " jusqu'à la fermeture du jeu ; les prochaines liaisons"
                  .. " faites dans l'interface seront mémorisées à nouveau."
end

-- ---------------------------------------------------------------------------
-- State and helpers
-- ---------------------------------------------------------------------------

local pending = {}     -- key -> command, waiting for a first key press
local live = {}        -- key -> true once the binding existed this session
local announced = false

local function Msg(text)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99EmberKeys|r : " .. text)
  end
end

-- uppercase char code -> lowercase character, UTF-8 encoded for the chat
local function CodeToChar(code)
  local c = code
  if c >= 192 and c <= 222 and c ~= 215 then c = c + 32 end
  if c >= 1040 and c <= 1071 then c = c + 32 end   -- Cyrillic
  if c < 128 then return string.char(c) end
  if c < 2048 then
    return string.char(192 + math.floor(c / 64), 128 + math.mod(c, 64))
  end
  return string.char(224 + math.floor(c / 4096),
                     128 + math.mod(math.floor(c / 64), 64),
                     128 + math.mod(c, 64))
end

local function SplitKey(key)
  local _, _, prefix, code = string.find(key, "^(.-)UNKNOWNCHARCODE_(%d+)$")
  if not code then return nil, nil end
  return prefix, tonumber(code)
end

local function IsUnknownKey(key)
  local _, code = SplitKey(key)
  return code ~= nil
end

-- Keys worth watching: UNKNOWNCHARCODE ids, but also keys named by their
-- literal non-ASCII character (² on AZERTY) whose persistence across restarts
-- is not guaranteed either. If the client does reload them, the addon finds
-- them already active and stays silent.
local function NeedsBabysitting(key)
  if IsUnknownKey(key) then return true end
  return string.find(key, "[\128-\255]") ~= nil
end

-- GetBindingAction on a key name the engine does not know yet must never
-- derail the ticker: everything goes through here.
local function SafeAction(key)
  if type(GetBindingAction) ~= "function" then return nil end
  local ok, cur = pcall(GetBindingAction, key)
  if not ok then return nil end
  return cur
end

-- This client returns ALL chords of a command, not only two (documented at
-- emberveil.org/wiki/lua): capture up to six.
local function SafeBindingKeys(command)
  if type(GetBindingKey) ~= "function" then return end
  local ok, a, b, c, d, e, f = pcall(GetBindingKey, command)
  if not ok then return end
  return a, b, c, d, e, f
end

local function ShortModifiers(prefix)
  prefix = string.gsub(prefix, "CTRL%-", "C-")
  prefix = string.gsub(prefix, "SHIFT%-", "S-")
  prefix = string.gsub(prefix, "ALT%-", "A-")
  return prefix
end

-- Short label for a button corner: the digit printed on the physical key
-- when known, the character itself otherwise.
local function LabelForKey(key)
  local prefix, code = SplitKey(key)
  if not code then return nil end
  local base = DIGIT_LABEL[code] or CodeToChar(code)
  if prefix and prefix ~= "" then return ShortModifiers(prefix) .. base end
  return base
end

-- Readable key name for chat messages.
local function DisplayKey(key)
  local prefix, code = SplitKey(key)
  if not code then return key end
  return (prefix or "") .. CodeToChar(code)
end

local function CommandLabel(cmd)
  local _, _, n = string.find(cmd, "^ACTIONBUTTON(%d+)$")
  if n then return L.ACTION .. n end
  _, _, n = string.find(cmd, "^SELFACTIONBUTTON(%d+)$")
  if n then return L.SELF_ACTION .. n end
  local _, _, bar, btn = string.find(cmd, "^MULTIACTIONBAR(%d+)BUTTON(%d+)$")
  if bar then return L.BAR .. bar .. L.BUTTON .. btn end
  return cmd
end

local function EnsureDB()
  if type(EmberKeysDB) ~= "table" then EmberKeysDB = {} end
  local db = EmberKeysDB
  if type(db.bindings) ~= "table" then db.bindings = {} end
  -- One-time seeding: the four AZERTY digit-row keys, only on a French
  -- client and only into an EMPTY database - never over existing bindings
  -- (migrated or already customized). Other layouts rely on capture or on
  -- /ek default.
  if not db.seeded then
    db.seeded = true
    if isFR and next(db.bindings) == nil then
      local key, cmd
      for key, cmd in pairs(LAYOUT_PRESETS.azerty.defaults) do
        db.bindings[key] = cmd
      end
    end
  end
  return db
end

local function HasPending()
  local k
  for k in pairs(pending) do return true end
  return false
end

-- Physical base key of a binding: "ALT-UNKNOWNCHARCODE_201" -> "é". Engine
-- registration is per key, not per chord: pressing é unlocks both é and
-- alt+é, so the welcome list only shows keys.
local function BaseChar(key)
  local _, code = SplitKey(key)
  if code then return CodeToChar(code) end
  local _, _, base = string.find(key, "%-([^%-]+)$")
  return base or key
end

local function PendingList()
  local uniq, chars = {}, {}
  local key
  for key in pairs(pending) do
    local c = BaseChar(key)
    if not uniq[c] then
      uniq[c] = true
      table.insert(chars, c)
    end
  end
  table.sort(chars)
  local out = ""
  local i
  for i = 1, table.getn(chars) do
    if out ~= "" then out = out .. "  " end
    out = out .. chars[i]
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Button labels
--
-- hooks[] keeps (fontstring, command, original SetText). The wrapper rewrites
-- on every write where interception works; since it measurably does not on
-- this client, an overlay FontString does the real work for unrealUI labels
-- and a fast enforcement lane covers the rest.
-- ---------------------------------------------------------------------------

local hooks = {}
local hookedFS = {}

-- unrealUI bars -> command prefix (BINDING_PREFIX in its actionbar.lua).
local UUI_PREFIX = {
  [1] = "ACTIONBUTTON",
  [2] = "MULTIACTIONBAR3BUTTON",
  [3] = "MULTIACTIONBAR4BUTTON",
  [4] = "MULTIACTIONBAR2BUTTON",
  [5] = "MULTIACTIONBAR1BUTTON",
}

local NATIVE_PREFIX = {
  ["ActionButton"] = "ACTIONBUTTON",
  ["BonusActionButton"] = "ACTIONBUTTON",
  ["MultiBarBottomLeftButton"] = "MULTIACTIONBAR1BUTTON",
  ["MultiBarBottomRightButton"] = "MULTIACTIONBAR2BUTTON",
  ["MultiBarRightButton"] = "MULTIACTIONBAR3BUTTON",
  ["MultiBarLeftButton"] = "MULTIACTIONBAR4BUTTON",
}

local function BestLabel(command)
  local chords = { SafeBindingKeys(command) }
  local i
  for i = 1, table.getn(chords) do
    local k = chords[i]
    if type(k) == "string" and IsUnknownKey(k) then return LabelForKey(k) end
  end
  local k1 = chords[1]
  if type(k1) == "string" and ENGINE_LABEL[k1] then return ENGINE_LABEL[k1] end
  return nil
end

-- Overlay for unrealUI labels: their periodic driver keeps rewriting "UNKN"
-- and reassigning SetText has no effect on this client (widget methods are
-- dispatched outside the Lua table; measured: intercepted = 0). So we draw
-- OUR FontString anchored on theirs, same font and color, and set theirs to
-- alpha 0: their periodic Show() does not restore alpha, so their rewrites
-- stay invisible with no race and no visible polling.
local function UpdateOverlay(entry)
  local fs = entry.fs
  if entry.label then
    if not entry.overlay then
      local parent = nil
      if fs.GetParent then
        local okP, p = pcall(fs.GetParent, fs)
        if okP then parent = p end
      end
      if not (parent and parent.CreateFontString) then return end
      -- inherit at creation time: the only reliable way to get a valid font
      -- on this client (SetFontObject is not guaranteed)
      local okC, ov = pcall(parent.CreateFontString, parent, nil, "OVERLAY",
                            "GameFontNormalSmall")
      if not okC or not ov then
        okC, ov = pcall(parent.CreateFontString, parent, nil, "OVERLAY")
        if not okC or not ov then return end
        pcall(ov.SetFontObject, ov, "GameFontNormalSmall")
      end
      pcall(ov.SetPoint, ov, "CENTER", fs, "CENTER", 0, 0)
      entry.overlay = ov
      if not pcall(fs.SetAlpha, fs, 0) then entry.noAlpha = true end
    end
    local ov = entry.overlay
    if entry.noAlpha then
      -- no alpha control: an overlay would double the text, fall back to the
      -- fast rewrite lane (EnforceLabel) on their FontString.
      if ov.Hide then ov:Hide() end
      return
    end
    if fs.GetFont then
      local okF, f, h, fl = pcall(fs.GetFont, fs)
      if okF and type(f) == "string" and f ~= ""
          and type(h) == "number" and h > 0 then
        if string.find(f, "[/\\]") then
          -- a real file path: SetFont accepts it
          pcall(ov.SetFont, ov, f, h, fl)
        else
          -- GetFont returns a font OBJECT name on this client: feeding it to
          -- SetFont breaks the font (invisible text)
          local obj = type(getglobal) == "function" and getglobal(f)
          if obj and ov.SetFontObject then pcall(ov.SetFontObject, ov, obj) end
        end
      end
      -- safety net: if the font got broken along the way, fall back to the
      -- inherited template
      local okV, vf = pcall(ov.GetFont, ov)
      if not (okV and type(vf) == "string" and vf ~= "") then
        pcall(ov.SetFontObject, ov, "GameFontNormalSmall")
      end
    end
    if fs.GetTextColor then
      local okT, r, g, b, a = pcall(fs.GetTextColor, fs)
      if okT and type(r) == "number" then
        if type(a) ~= "number" or a <= 0 then a = 1 end
        pcall(ov.SetTextColor, ov, r, g, b, a)
      end
    end
    if not (ov.GetText and ov:GetText() == entry.label) then
      ov:SetText(entry.label)
    end
    if ov.Show then ov:Show() end
  elseif entry.overlay then
    if entry.overlay.Hide then entry.overlay:Hide() end
    if not entry.noAlpha then pcall(fs.SetAlpha, fs, 1) end
  end
end

-- Recompute the wanted label of an entry (costly: GetBindingKey) then impose
-- it. The fast EnforceLabel lane only compares against the cache.
local function ApplyLabel(entry)
  entry.label = BestLabel(entry.cmd)
  if entry.uui then
    UpdateOverlay(entry)
    if not (entry.label and entry.overlay and not entry.noAlpha) then
      -- overlay unavailable: direct rewrite as a fallback
      if entry.label then
        local cur = entry.fs.GetText and entry.fs:GetText()
        if cur ~= entry.label then
          entry.orig(entry.fs, entry.label)
          if entry.fs.Show then entry.fs:Show() end
        end
      end
    end
    return
  end
  if entry.label then
    local cur = entry.fs.GetText and entry.fs:GetText()
    if cur ~= entry.label then
      entry.orig(entry.fs, entry.label)
      if entry.fs.Show then entry.fs:Show() end
    end
  end
end

local function EnforceLabel(entry)
  if not entry.label then return end
  -- a healthy overlay has nothing to defend: nobody writes into it
  if entry.uui and entry.overlay and not entry.noAlpha then return end
  local cur = entry.fs.GetText and entry.fs:GetText()
  if cur ~= entry.label then
    entry.orig(entry.fs, entry.label)
    if entry.fs.Show then entry.fs:Show() end
  end
end

local function HookFS(fs, command, isUui)
  if not fs or hookedFS[fs] then return end
  local orig = fs.SetText
  if type(orig) ~= "function" then return end
  hookedFS[fs] = true
  local entry = { fs = fs, cmd = command, orig = orig, uui = isUui }
  table.insert(hooks, entry)
  local wrapper = function(self, text)
    local better = BestLabel(command)
    if better then
      orig(self, better)
    else
      orig(self, text)
    end
  end
  fs.SetText = wrapper
  -- On this client reassigning a widget method can be a no-op (dispatch
  -- outside the Lua table): measure it instead of assuming, and let the
  -- ticker's fast lane cover non-intercepted cases.
  entry.intercepted = (fs.SetText == wrapper)
  ApplyLabel(entry)
end

local function InstallHooks()
  if type(getglobal) ~= "function" then return end
  local i, prefix, cmdPrefix, bar
  for i = 1, 12 do
    for prefix, cmdPrefix in pairs(NATIVE_PREFIX) do
      HookFS(getglobal(prefix .. i .. "HotKey"), cmdPrefix .. i)
    end
    for bar = 1, 5 do
      local b = getglobal("UnrealUIActionBar" .. bar .. "Button" .. i)
      if b and b.uuiKeybind then
        HookFS(b.uuiKeybind, UUI_PREFIX[bar] .. i, true)
      end
    end
  end
end

local function RefreshHookedLabels()
  local i
  for i = 1, table.getn(hooks) do ApplyLabel(hooks[i]) end
end

local function EnforceHookedLabels()
  local i
  for i = 1, table.getn(hooks) do EnforceLabel(hooks[i]) end
end

-- ---------------------------------------------------------------------------
-- Restoration
-- ---------------------------------------------------------------------------

-- Re-apply pending bindings. A SetBinding only takes effect once the key has
-- been registered by a press, so success is verified afterwards with
-- GetBindingAction, never through the return value.
local function TryApply()
  if type(SetBinding) ~= "function" then return end
  local applied = nil
  local key, cmd
  for key, cmd in pairs(pending) do
    local cur = SafeAction(key)
    if cur == cmd then
      -- already in place (reloaded by the client itself): nothing to say
      pending[key] = nil
      live[key] = true
    elseif type(cur) == "string" and cur ~= "" then
      -- The key currently belongs to another command: do not steal it, but
      -- STAY pending. The conflict is often transient (key grabbed by a
      -- misfired quick binding then released); we re-attach as soon as it
      -- becomes free again.
    else
      pcall(SetBinding, key, cmd)
      cur = SafeAction(key)
      if cur == cmd then
        pending[key] = nil
        live[key] = true
        applied = applied or {}
        applied[key] = cmd
      end
    end
  end
  if applied then
    local out = ""
    for key, cmd in pairs(applied) do
      if out ~= "" then out = out .. ", " end
      out = out .. DisplayKey(key) .. " (" .. CommandLabel(cmd) .. ")"
    end
    Msg(L.RESTORED .. out)
    if announced and not HasPending() then
      Msg(L.ALL_ACTIVE)
    end
    RefreshHookedLabels()
  end
end

-- Inventory the babysat bindings actually in place (set by us, by the Key
-- Bindings panel or by unrealUI's quick bindings) and remember them. A key
-- seen active this session then gone was unbound on purpose: it leaves the
-- database.
local function Rescan()
  local db = EnsureDB()
  if type(GetNumBindings) ~= "function" or type(GetBinding) ~= "function" then
    return
  end
  local okN, n = pcall(GetNumBindings)
  n = okN and tonumber(n) or 0
  local seen = {}
  local i
  for i = 1, n do
    local ok, cmd = pcall(GetBinding, i)
    if ok and type(cmd) == "string" and cmd ~= "" then
      local chords = { SafeBindingKeys(cmd) }
      local c
      for c = 1, table.getn(chords) do
        local k = chords[c]
        if type(k) == "string" and NeedsBabysitting(k) then seen[k] = cmd end
      end
    end
  end
  local key, cmd
  for key, cmd in pairs(seen) do
    db.bindings[key] = cmd
    live[key] = true
    -- The key is alive: a pending entry aiming at another command is
    -- obsolete (the user reassigned it), follow their choice.
    if pending[key] and pending[key] ~= cmd then pending[key] = nil end
  end
  for key in pairs(db.bindings) do
    if live[key] and not seen[key] and not pending[key] then
      db.bindings[key] = nil
      live[key] = nil
    end
  end
end

local function LoadPending()
  local db = EnsureDB()
  local key, cmd
  for key, cmd in pairs(db.bindings) do
    if not live[key] then pending[key] = cmd end
  end
end

-- ---------------------------------------------------------------------------
-- Events and cadence
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame", "EmberKeysEventFrame")
pcall(events.RegisterEvent, events, "VARIABLES_LOADED")
pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
pcall(events.RegisterEvent, events, "PLAYER_LOGOUT")
pcall(events.RegisterEvent, events, "UPDATE_BINDINGS")

events:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    LoadPending()
  elseif event == "PLAYER_ENTERING_WORLD" then
    LoadPending()
    InstallHooks()
    TryApply()
    if not announced then
      announced = true
      if HasPending() then
        Msg(L.PRESS_ONCE_1 .. PendingList() .. L.PRESS_ONCE_2)
      end
    end
  elseif event == "PLAYER_LOGOUT" then
    Rescan()
  elseif event == "UPDATE_BINDINGS" then
    Rescan()
    RefreshHookedLabels()
  end
end)

local ticker = CreateFrame("Frame", "EmberKeysTicker")
ticker:Show()
local blink, fast, slow, scanTick = 0, 0, 0, 0
ticker:SetScript("OnUpdate", function()
  blink = blink + arg1
  fast = fast + arg1
  slow = slow + arg1
  -- Anti-flicker fast lane: a plain compare against the cache, nearly free.
  -- Needed as long as SetText interception is not guaranteed on this client;
  -- only entries without a healthy overlay do any work here.
  if blink >= 0.1 then
    blink = 0
    EnforceHookedLabels()
  end
  if fast >= 0.3 then
    fast = 0
    if HasPending() then TryApply() end
  end
  if slow >= 2 then
    slow = 0
    InstallHooks()
    RefreshHookedLabels()
    scanTick = scanTick + 1
    if scanTick >= 4 then
      scanTick = 0
      Rescan()
    end
  end
end)

-- ---------------------------------------------------------------------------
-- /emberkeys, /ek (alias: /azerty)
-- ---------------------------------------------------------------------------

local function Status()
  local db = EnsureDB()
  Msg("version " .. ADDON_VERSION .. L.ST_VERSION)
  local any = false
  local key, cmd
  for key, cmd in pairs(db.bindings) do
    any = true
    local state
    if pending[key] then
      state = "|cffffcc00" .. L.ST_WAITING .. "|r"
    elseif SafeAction(key) == cmd then
      state = "|cff55ff55" .. L.ST_ACTIVE .. "|r"
    else
      state = "|cffff5555" .. L.ST_INACTIVE .. "|r"
    end
    Msg("  " .. DisplayKey(key) .. " (" .. key .. ") = " ..
        CommandLabel(cmd) .. " ; " .. state)
  end
  if not any then Msg(L.ST_NONE) end
  Msg(L.ST_HELP)
end

-- Diagnostics stay in English on purpose: their audience is bug reports and
-- the addon author, not the player.
local function Diag()
  local db = EnsureDB()
  Msg("diagnostics:")
  Msg("  SetBinding " .. type(SetBinding) ..
      ", GetBindingAction " .. type(GetBindingAction) ..
      ", GetBindingKey " .. type(GetBindingKey) ..
      ", GetNumBindings " .. type(GetNumBindings))
  if type(GetNumBindings) == "function" then
    local okN, n = pcall(GetNumBindings)
    Msg("  binding table: " .. tostring(okN and n) .. " commands")
  end
  local nInt, nOv, nVis, i = 0, 0, 0, nil
  for i = 1, table.getn(hooks) do
    local e = hooks[i]
    if e.intercepted then nInt = nInt + 1 end
    if e.overlay and not e.noAlpha then
      nOv = nOv + 1
      local okVis, vis = pcall(e.overlay.IsVisible, e.overlay)
      if okVis and vis then nVis = nVis + 1 end
    end
  end
  Msg("  label hooks: " .. table.getn(hooks) ..
      " (SetText intercepted: " .. nInt ..
      ", overlays: " .. nOv .. ", visible: " .. nVis .. ")")
  for i = 1, table.getn(hooks) do
    local e = hooks[i]
    if e.overlay then
      local _, f, h = pcall(e.overlay.GetFont, e.overlay)
      local _, w = pcall(e.overlay.GetStringWidth, e.overlay)
      local txt = e.overlay.GetText and e.overlay:GetText()
      Msg("  sample overlay (" .. e.cmd .. "): text=" .. tostring(txt) ..
          " font=" .. tostring(f) .. " size=" .. tostring(h) ..
          " width=" .. tostring(w))
      break
    end
  end
  local key, cmd
  for key, cmd in pairs(db.bindings) do
    local action = tostring(SafeAction(key))
    local k1, k2 = SafeBindingKeys(cmd)
    Msg("  " .. key .. " : GetBindingAction=" .. action ..
        " ; " .. cmd .. " -> " .. tostring(k1) .. ", " .. tostring(k2))
  end
end

local function ApplyPreset(name)
  local preset = LAYOUT_PRESETS[name]
  if not preset then
    local list = ""
    local n
    for n in pairs(LAYOUT_PRESETS) do
      if list ~= "" then list = list .. ", " end
      list = list .. n
    end
    Msg(L.PRESET_UNKNOWN .. list)
    return
  end
  local db = EnsureDB()
  local key, cmd
  for key, cmd in pairs(preset.defaults) do
    db.bindings[key] = cmd
    if not live[key] then pending[key] = cmd end
  end
  TryApply()
  if HasPending() then
    Msg(preset.title .. L.PRESET_WAIT .. PendingList())
  else
    Msg(preset.title .. L.PRESET_DONE)
  end
end

SLASH_EMBERKEYS1 = "/emberkeys"
SLASH_EMBERKEYS2 = "/ek"
SLASH_EMBERKEYS3 = "/azerty"
SlashCmdList["EMBERKEYS"] = function(msg)
  msg = string.lower(tostring(msg or ""))
  msg = string.gsub(msg, "^%s+", "")
  msg = string.gsub(msg, "%s+$", "")
  local _, _, word, rest = string.find(msg, "^(%S+)%s*(.*)$")
  if word == "defaut" or word == "défaut" or word == "default" then
    if rest == "" then rest = "azerty" end
    ApplyPreset(rest)
  elseif word == "raz" or word == "reset" then
    local db = EnsureDB()
    db.bindings = {}
    pending = {}
    Msg(L.RESET_DONE)
  elseif word == "diag" then
    Diag()
  else
    Status()
  end
end
