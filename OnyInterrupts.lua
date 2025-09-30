-- OnyInterrupts (WotLK 3.3.5) — Interrupt/CC watcher with clickable links
-- New: debounce "used while not casting" if a real interrupt/CC interrupt just landed for the same src->dst.

local f = CreateFrame("Frame")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_LOGIN")

local band = bit.band
local format = string.format
local lower = string.lower
local find = string.find
local tostring = tostring
local GetTime = GetTime
local UnitGUID = UnitGUID
local unpack = unpack
local playerGUID

-- Use high-contrast colors so OnyInterrupts stands apart from party chat hues.
local CLR_SELF_SUCCESS = {0.30, 1.00, 0.30}  -- vivid green for your interrupts
local CLR_OTHER_SUCCESS= {0.15, 0.75, 1.00}  -- bright teal for others
local CLR_FAIL         = {1.00, 0.20, 0.20}  -- intense red for failures
local CLR_NONCAST      = {1.00, 0.55, 0.10}  -- rich amber for "not casting"
local CLR_STUN_INT     = {0.75, 0.35, 1.00}  -- bold violet for stun/silence
local CLR_LOS          = {1.00, 0.35, 0.65}  -- hot pink for line-of-sight

local function msg(text, r, g, b)
  (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage(text, r or 1, g or 1, b or 1)
end

-- Configuration
local MODE_ALL      = "all"
local MODE_SELF     = "self"
local MODE_MINIMAL  = "minimal"

local MODE_LABELS = {
  [MODE_ALL]     = "all events",
  [MODE_SELF]    = "only your events",
  [MODE_MINIMAL] = "only your successful interrupts",
}

local db

local function ensureDB()
  if type(OnyInterruptsDB) ~= "table" then
    OnyInterruptsDB = {}
  end
  db = OnyInterruptsDB
  local mode = db.mode
  if mode ~= MODE_ALL and mode ~= MODE_SELF and mode ~= MODE_MINIMAL then
    db.mode = MODE_ALL
  end
  return db
end

local function currentMode()
  if not db then ensureDB() end
  return db.mode or MODE_ALL
end

local function shouldShow(kind, srcGUID)
  local mode = currentMode()
  if mode == MODE_ALL then return true end

  if srcGUID and srcGUID == playerGUID then
    if mode == MODE_SELF then return true end
    if mode == MODE_MINIMAL then
      return kind == "interrupt_success" or kind == "cc_interrupt"
    end
  end

  return false
end

local function notify(kind, srcGUID, text, r, g, b)
  if shouldShow(kind, srcGUID) then
    msg(text, r, g, b)
  end
end

local addonPrefix = "|cffffd100OnyInterrupts|r"

local function inform(text)
  msg(format("%s: %s", addonPrefix, text), 1, 0.9, 0.1)
end

local function trim(str)
  if not str then return "" end
  return str:match("^%s*(.-)%s*$") or ""
end

local function describeMode(mode)
  local label = MODE_LABELS[mode]
  if label then
    return format("%s (%s)", mode, label)
  end
  return mode or MODE_ALL
end

local function setMode(mode)
  ensureDB()
  if db.mode == mode then
    inform(format("Verbosity already set to %s.", describeMode(mode)))
    return
  end
  db.mode = mode
  inform(format("Verbosity set to %s.", describeMode(mode)))
end

local function printStatus()
  inform(format("Current verbosity: %s.", describeMode(currentMode())))
  inform("Use /onyints all, /onyints self, or /onyints minimal.")
end

SLASH_ONYINTS1 = "/onyints"
SLASH_ONYINTS2 = "/onyinterrupts"

SlashCmdList.ONYINTS = function(msg)
  local input = lower(trim(msg))
  if input == "" or input == "status" or input == "help" then
    printStatus()
    return
  end

  local normalized
  if input == "all" or input == "full" or input == "default" then
    normalized = MODE_ALL
  elseif input == "self" or input == "mine" or input == "me" then
    normalized = MODE_SELF
  elseif input == "minimal" or input == "quiet" or input == "silent" then
    normalized = MODE_MINIMAL
  end

  if normalized then
    setMode(normalized)
  else
    printStatus()
  end
end

local function typeLabel(flags)
  if not flags then return "" end
  if band(flags, COMBATLOG_OBJECT_TYPE_PLAYER)   > 0 then return "" end
  if band(flags, COMBATLOG_OBJECT_TYPE_PET)      > 0 then return " (pet)" end
  if band(flags, COMBATLOG_OBJECT_TYPE_GUARDIAN) > 0 then return " (guardian)" end
  if band(flags, COMBATLOG_OBJECT_TYPE_NPC)      > 0 then return " (NPC)" end
  return ""
end

-- Hostility helper
local REACTION_HOSTILE  = COMBATLOG_OBJECT_REACTION_HOSTILE  or 0x00000040
local function isHostile(flags)  return band(flags or 0, REACTION_HOSTILE ) > 0 end

-- LOS matcher
local function isLOSReason(reason)
  if not reason then return false end
  local r = lower(tostring(reason))
  if find(r, "line of sight", 1, true) then return true end
  if r == "los" then return true end
  if find(r, "obstruct", 1, true) then return true end -- some cores say "obstructed"
  if SPELL_FAILED_LINE_OF_SIGHT then
    local c = lower(tostring(SPELL_FAILED_LINE_OF_SIGHT))
    if c ~= "" and find(r, c, 1, true) then return true end
  end
  return false
end

-- Track casting state & last cast (id+name) by caster GUID
local castingUntil = {}      -- [casterGUID] = expiryTime
local lastCastName  = {}     -- [casterGUID] = "Fireball"
local lastCastId    = {}     -- [casterGUID] = 133

local function setCasting(casterGUID, spellId, spellName, now, duration)
  if not casterGUID then return end
  castingUntil[casterGUID] = (now or GetTime()) + (duration or 6.0)
  if spellName then lastCastName[casterGUID] = spellName end
  if spellId   then lastCastId[casterGUID]   = spellId   end
end

local function clearCasting(casterGUID)
  if not casterGUID then return end
  castingUntil[casterGUID] = nil
  lastCastName[casterGUID] = nil
  lastCastId[casterGUID]   = nil
end

local function isCasting(casterGUID, now)
  local exp = casterGUID and castingUntil[casterGUID]
  if not exp then return false end
  return (now or GetTime()) <= exp
end

local function getLastCast(casterGUID)
  return lastCastId[casterGUID], lastCastName[casterGUID]
end

-- Known interrupts (no Earth Shock/Arcane Torrent spam)
local interruptSpells = {
  [1766]  = "Kick",          -- Rogue
  [6552]  = "Pummel",        -- Warrior
  [72]    = "Shield Bash",   -- Warrior
  [2139]  = "Counterspell",  -- Mage
  [19647] = "Spell Lock",    -- Felhunter
  [19244] = "Spell Lock",    -- Felhunter alt
  [47528] = "Mind Freeze",   -- DK
  [57994] = "Wind Shear",    -- Shaman
}

-- CC that stops casts mid-cast: stuns, incapacitates, silences (name & id)
local stunSpells = {
  -- Rogue
  [408]   = "Kidney Shot",
  [1833]  = "Cheap Shot",
  [1776]  = "Gouge", [1777] = "Gouge", [8629] = "Gouge", [11285] = "Gouge", [11286] = "Gouge",
  -- Warrior
  [20253] = "Intercept Stun",
  [7922]  = "Charge Stun",
  [12809] = "Concussion Blow",
  [46968] = "Shockwave",
  -- Paladin
  [853]   = "Hammer of Justice",
  -- Druid
  [5211]  = "Bash",
  [9005]  = "Pounce",
  -- Racial / Warlock
  [20549] = "War Stomp",
  [30283] = "Shadowfury", [30413] = "Shadowfury", [30414] = "Shadowfury", [47846] = "Shadowfury", [47847] = "Shadowfury",
}

local stunNames = {
  ["gouge"] = true, ["kidney shot"] = true, ["cheap shot"] = true,
  ["intercept stun"] = true, ["charge stun"] = true, ["concussion blow"] = true,
  ["shockwave"] = true, ["hammer of justice"] = true, ["bash"] = true, ["pounce"] = true,
  ["war stomp"] = true, ["shadowfury"] = true,
}

-- Silences (IDs + name-matching; Arcane Torrent excluded per request)
local silenceSpells = {
  [15487] = "Silence",        -- Priest
  [47476] = "Strangulate", [47475] = "Strangulate", [47474] = "Strangulate",
  [47473] = "Strangulate", [47471] = "Strangulate",
  [34490] = "Silencing Shot", -- Hunter
}
local silenceNames  = {
  ["silence"] = true,
  ["strangulate"] = true,
  ["silencing shot"] = true,
  ["silenced - improved counterspell"] = true,
  ["silenced - gag order"] = true,
  ["garrote - silence"] = true,
}

local function isStunLike(spellId, spellName)
  if spellId and stunSpells[spellId] then return true end
  if spellName and stunNames[lower(spellName)] then return true end
  return false
end

local function isSilenceLike(spellId, spellName)
  if spellId and silenceSpells[spellId] then return true end
  if spellName then
    local n = lower(spellName)
    if silenceNames[n] then return true end
    if find(n, "silenc", 1, true) then return true end
  end
  return false
end

local function isCCLike(spellId, spellName) return isStunLike(spellId, spellName) or isSilenceLike(spellId, spellName) end

local function linkOrName(spellId, spellName)
  if spellId and GetSpellLink then
    local link = GetSpellLink(spellId)
    if link then return link end
  end
  if spellName then
    return format("|cff71d5ff[%s]|r", spellName)
  end
  return "|cff71d5ff[Unknown Spell]|r"
end

-- Recent ability memory for generic "Interrupt" substitution
local recentAbility = {}  -- key = srcGUID..":"..dstGUID -> {id=spellId, name=spellName, t=GetTime(), kind="interrupt"|"cc"}
local WINDOW = 2.0

local function mkKey(a,b) return (a or "nil")..":"..(b or "nil") end
local function storeRecent(kind, srcGUID, dstGUID, spellId, spellName, now)
  recentAbility[ mkKey(srcGUID, dstGUID) ] = {id=spellId, name=spellName, t=(now or GetTime()), kind=kind}
end
local function getRecent(srcGUID, dstGUID, now, maxAge)
  local v = recentAbility[ mkKey(srcGUID, dstGUID) ]
  if v and ((now or GetTime()) - v.t) <= (maxAge or WINDOW) then return v.id, v.name, v.kind end
end

-- Debounce: suppress "used on non-casting" right after a real interrupt/CC interrupt
local suppressPair = {}  -- key -> expiry
local SUPPRESS_WIN = 1.5
local function markSuppressed(srcGUID, dstGUID, now)
  suppressPair[ mkKey(srcGUID, dstGUID) ] = (now or GetTime()) + SUPPRESS_WIN
end
local function isSuppressed(srcGUID, dstGUID, now)
  local t = suppressPair[ mkKey(srcGUID, dstGUID) ]
  return t and (now or GetTime()) <= t
end

local function resetState()
  for k in pairs(castingUntil) do castingUntil[k] = nil end
  for k in pairs(lastCastName) do lastCastName[k] = nil end
  for k in pairs(lastCastId) do lastCastId[k] = nil end
  for k in pairs(recentAbility) do recentAbility[k] = nil end
  for k in pairs(suppressPair) do suppressPair[k] = nil end
end

local auraAppliedEvents = {
  SPELL_AURA_APPLIED = true,
  SPELL_AURA_REFRESH = true,
}

f:SetScript("OnEvent", function(self, event, ...)
  if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then
    if event == "PLAYER_ENTERING_WORLD" then
      playerGUID = UnitGUID("player")
      resetState()
    elseif event == "PLAYER_LOGIN" then
      ensureDB()
    end
    return
  end
  local timestamp, subevent,
        srcGUID, srcName, srcFlags,
        dstGUID, dstName, dstFlags,
        spellId, spellName, spellSchool,
        arg12, arg13, arg14 = ...

  playerGUID = playerGUID or UnitGUID("player")
  local now = GetTime()

  -- --------- CAST STATE TRACKING ---------
  if subevent == "SPELL_CAST_START" then
    setCasting(srcGUID, spellId, spellName, now, 8.0); return
  elseif subevent == "SPELL_CHANNEL_START" then
    setCasting(srcGUID, spellId, spellName, now, 8.0); return
  elseif subevent == "SPELL_CHANNEL_STOP" then
    clearCasting(srcGUID); return
  elseif subevent == "SPELL_CAST_SUCCESS" then
    if interruptSpells[spellId] then
      storeRecent("interrupt", srcGUID, dstGUID, spellId, spellName, now)
      -- If the pair is in suppression window (an interrupt just registered), skip non-cast warning entirely
      if isSuppressed(srcGUID, dstGUID, now) then return end
      local targetCasting = isCasting(dstGUID, now)
      if not targetCasting then
        local who, target = srcName or "Someone", dstName or "target"
        local srcTag, dstTag = typeLabel(srcFlags), typeLabel(dstFlags)
        local usedLink = linkOrName(spellId, spellName)
        local text
        if srcGUID == playerGUID then
          text = format("You used %s on %s%s while not casting", usedLink, target, dstTag)
        else
          text = format("%s%s used %s on %s%s while not casting", who, srcTag, usedLink, target, dstTag)
        end
        notify("noncast", srcGUID, text, unpack(CLR_NONCAST))
      end
      return
    elseif isCCLike(spellId, spellName) then
      storeRecent("cc", srcGUID, dstGUID, spellId, spellName, now)
    else
      clearCasting(srcGUID)
    end
  elseif subevent == "SPELL_CAST_FAILED" then
    -- Only enemy LOS cast-fails are reported (team moved out of LOS)
    if isHostile(srcFlags) and isLOSReason(arg12) then
      local caster  = srcName or "Enemy"
      local target  = dstName or "ally"
      local srcTag  = typeLabel(srcFlags)
      local dstTag  = typeLabel(dstFlags)
      local castLink= linkOrName(spellId, spellName)
      notify("los", srcGUID, format("%s%s %s failed (line of sight on %s%s)", caster, srcTag, castLink, target, dstTag), unpack(CLR_LOS))
      clearCasting(srcGUID); return
    end
    clearCasting(srcGUID)
  elseif subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
    clearCasting(dstGUID); return
  end

  -- Also store CC on aura application
  if auraAppliedEvents[subevent] and isCCLike(spellId, spellName) then
    storeRecent("cc", srcGUID, dstGUID, spellId, spellName, now)
  end

  -- --------- INTERRUPT SUCCESS ---------
  if subevent == "SPELL_INTERRUPT" then
    local who, target = srcName or "Someone", dstName or "target"
    local usedId, usedName   = spellId, spellName          -- may be generic "Interrupt" on private cores
    local stoppedId, stoppedName = arg12, arg13

    if not usedName or usedName == "" or usedName == "Interrupt" then
      local rid, rname = getRecent(srcGUID, dstGUID, now, WINDOW)
      if rid or rname then usedId, usedName = rid or usedId, rname or usedName end
    end

    local usedLink, stoppedLink = linkOrName(usedId, usedName), linkOrName(stoppedId, stoppedName)
    local srcTag, dstTag = typeLabel(srcFlags), typeLabel(dstFlags)

    local text
    if srcGUID == playerGUID then
      text = format("You interrupted %s on %s%s with %s", stoppedLink, target, dstTag, usedLink)
    else
      text = format("%s%s interrupted %s on %s%s with %s", who, srcTag, stoppedLink, target, dstTag, usedLink)
    end
    local color = srcGUID == playerGUID and CLR_SELF_SUCCESS or CLR_OTHER_SUCCESS
    notify("interrupt_success", srcGUID, text, unpack(color))
    markSuppressed(srcGUID, dstGUID, now)  -- suppress the immediate non-cast warning on the follow-up CAST_SUCCESS
    clearCasting(dstGUID); return
  end

  -- --------- INTERRUPT FAILS (MISSES) ---------
  if subevent == "SPELL_MISSED" and interruptSpells[spellId] then
    local who, target = srcName or "Someone", dstName or "target"
    local missType = arg12 or "failed"
    local srcTag, dstTag = typeLabel(srcFlags), typeLabel(dstFlags)
    local usedLink = linkOrName(spellId, spellName)
    local targetCasting = isCasting(dstGUID, now)

    local text, color, kind
    if srcGUID == playerGUID then
      if targetCasting then
        text = format("Your %s on %s%s %s", usedLink, target, dstTag, lower(missType))
        color, kind = CLR_FAIL, "interrupt_fail"
      else
        text = format("Your %s on %s%s while not casting (%s)", usedLink, target, dstTag, lower(missType))
        color, kind = CLR_NONCAST, "noncast"
      end
    else
      if targetCasting then
        text = format("%s%s tried %s on %s%s but it %s", who, srcTag, usedLink, target, dstTag, lower(missType))
        color, kind = CLR_FAIL, "interrupt_fail"
      else
        text = format("%s%s used %s on %s%s while not casting (%s)", who, srcTag, usedLink, target, dstTag, lower(missType))
        color, kind = CLR_NONCAST, "noncast"
      end
    end
    notify(kind, srcGUID, text, unpack(color))
    return
  end

  -- --------- CC LANDS WHILE TARGET IS CASTING (TREAT AS INTERRUPT) ---------
  if auraAppliedEvents[subevent] and isCCLike(spellId, spellName) then
    local who, target = srcName or "Someone", dstName or "target"
    local srcTag, dstTag = typeLabel(srcFlags), typeLabel(dstFlags)
    local targetCasting = isCasting(dstGUID, now)
    if targetCasting then
      local castId, castName = getLastCast(dstGUID)
      local castLink = linkOrName(castId, castName or "a spell")
      local ccLink   = linkOrName(spellId, spellName)
      local verb = isSilenceLike(spellId, spellName) and "silenced" or (isStunLike(spellId, spellName) and "stunned" or "CC'd")
      local text
      if srcGUID == playerGUID then
        text = format("You %s %s%s with %s (interrupted %s)", verb, target, dstTag, ccLink, castLink)
      else
        text = format("%s%s %s %s%s with %s (interrupted %s)", who, srcTag, verb, target, dstTag, ccLink, castLink)
      end
      notify("cc_interrupt", srcGUID, text, unpack(CLR_STUN_INT))
      markSuppressed(srcGUID, dstGUID, now) -- also suppress non-cast warning for CC-based interrupts
      clearCasting(dstGUID); return
    end
  end
end)
