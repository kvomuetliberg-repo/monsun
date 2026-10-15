-- monsun
-- 16-tap rhythm delay and
-- 64-tooth comb resonator
-- after the Rainmaker
--
-- grid 128 + arc 4
--
-- E1 page  E2 select  E3 value
-- K2 freeze  K3 ping
--
-- grid row 8:
-- pages TAPS RHYTHM COMB
-- PRESETS, page keys, RAMP,
-- RANDOM, PING, FREEZE,
-- REVERSE, ALT
--
-- MIDI notes play the comb

engine.name = "Monsun"

---------------------------------------------------------------------------
-- tables
---------------------------------------------------------------------------
local NT = 16
local PHI = (1 + math.sqrt(5)) / 2
local function frac(x) return x - math.floor(x) end
local function hash(n, seed) return frac(math.sin(n * 127.1 + seed * 311.7) * 43758.5453) end
local function sign(x) return x < 0 and -1 or 1 end

-- grooves: tap n (1-16) -> time in grid spacings
local GROOVES = {
  {"straight", function(n) return n end},
  {"swing", function(n) return n + (n % 2 == 0 and 1 / 3 or 0) end},
  {"hard swing", function(n) return n + (n % 2 == 0 and 0.5 or 0) end},
  {"reverse swing", function(n) return n - (n % 2 == 0 and 1 / 3 or 0) end},
  {"alt swing", function(n) return n + (n % 4 == 2 and 1 / 3 or (n % 4 == 0 and -0.25 or 0)) end},
  {"accelerando", function(n) return 16 * (n / 16) ^ 0.62 end},
  {"ritardando", function(n) return 16 * (n / 16) ^ 1.55 end},
  {"waltz", function(n) return (math.floor((n - 1) / 3) * 4 + ((n - 1) % 3) + 1) * 16 / 21 end},
  {"half swing", function(n) return n + (n % 2 == 0 and 1 / 6 or 0) end},
  {"roller coaster", function(n) return n + 0.45 * math.sin(2 * math.pi * n / 8) end},
  {"quintuple", function(n) return n * 0.8 + math.floor((n - 1) / 5) * 0.8 end},
  {"random A", function(n) return n + (hash(n, 1) - 0.5) * 0.9 end},
  {"random B", function(n) return n + (hash(n, 2) - 0.5) * 0.9 end},
  {"random C", function(n) return n + (hash(n, 3) - 0.5) * 0.9 end},
  {"early refl", function(n) return 16 * (n / 16) ^ 2 end},
  {"late refl", function(n) return 16 * (1 - (1 - n / 16) ^ 2) end},
}
local GROOVE_NAMES = {}
for i, g in ipairs(GROOVES) do GROOVE_NAMES[i] = g[1] end

-- comb tooth patterns: tooth k (1-64) -> fraction of the comb size
local FIB = {}
do
  local s, c = 0, {}
  for k = 1, 64 do
    local d = (math.floor((k + 1) / PHI) - math.floor(k / PHI)) ~= 0 and PHI or 1
    s = s + d; c[k] = s
  end
  for k = 1, 64 do FIB[k] = c[k] / s end
end
local BASEPAT = {
  {"uniform", function(k) return k / 64 end},
  {"flat middle", function(k) local u = 2 * k / 64 - 1; return 0.5 + 0.5 * sign(u) * u * u end},
  {"early", function(k) return (k / 64) ^ 2 end},
  {"fibonacci", function(k) return FIB[k] end},
  {"flat comb", function(k) local g, j = math.floor((k - 1) / 8), (k - 1) % 8; return (g + 0.6 + 0.4 * j / 7) / 8 end},
  {"late", function(k) return 1 - (1 - k / 64) ^ 2 end},
  {"rev fibonacci", function(k) return k == 64 and 1 or 1 - FIB[64 - k] end},
  {"ess", function(k) local u = 2 * k / 64 - 1; return 0.5 + 0.5 * sign(u) * math.sqrt(math.abs(u)) end},
}
local COMBPAT = {}
for i, p in ipairs(BASEPAT) do COMBPAT[i] = p end
for i, p in ipairs(BASEPAT) do
  local f = p[2]
  COMBPAT[8 + i] = {"rand " .. p[1], function(k)
    if k == 64 then return 1 end
    local a, b, c = f(math.max(1, k - 1)), f(k), f(math.min(64, k + 1))
    return util.clamp(b + (hash(k, 7 + i) - 0.5) * 0.8 * (c - a) / 2, 0.001, 1)
  end}
end
local COMB_NAMES = {}
for i, p in ipairs(COMBPAT) do COMB_NAMES[i] = p[1] end
local SLOPES = {
  function() return 1 end,
  function(x) return 0.15 + 0.85 * x end,
  function(x) return 1 - 0.85 * x end,
  function(x) return 0.15 + 0.85 * (1 - math.abs(2 * x - 1)) end,
}

local GRIDS = {1, 2, 3, 4, 6, 8, 12, 16}
local BEAT_MULT = {0.25, 1 / 3, 0.5, 2 / 3, 1, 1.5, 2, 4}
local BEAT_NAMES = {"1/4", "1/3", "1/2", "2/3", "1", "3/2", "2", "4"}
local STACKS = {1, 2, 4, 8}
local GRAINS = {0.005, 0.010, 0.021, 0.042, 0.084, 0.168, 0.336, 0.671}
local GRAIN_NAMES = {"5 ms", "10 ms", "21 ms", "42 ms", "84 ms", "168 ms", "336 ms", "671 ms"}
local LFO_WAVES = {"off", "sine", "triangle", "vibrato 1", "vibrato 2", "down chirp", "up chirp", "random"}
local FTYPES = {"off", "low pass", "band pass", "high pass"}
local FB_PITCHES = {-12, -7, -5, -3, 0, 3, 4, 5, 7, 12, 19, 24}
local ROUTINGS = {"delay > comb", "comb > delay", "parallel", "split L|R"}
local CTYPES = {"guitar", "sitar", "clarinet", "raw"}
local SOURCES = {"line in", "file", "demo"}
local MORPH = {"off", "1/2 beat", "1 beat", "1 bar", "4 bars"}
local MORPH_BEATS = {0, 0.5, 1, 4, 16}
local TAP_PARAMS = {"level", "pan", "cut", "q", "pitch", "ftype"}
local TAP_PARAM_NAMES = {"LEVEL", "PAN", "CUTOFF", "Q", "PITCH", "TYPE"}
local NOTE_NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local RND_DEST = {"groove times", "tap mutes", "tap levels", "tap pans", "filter cutoffs", "filter Qs", "tap pitches",
  "comb", "delay globals", "all taps", "all delay", "taps + delay", "comb + delay", "everything", "any one"}

-- tap fader rows 1-6 for each tap parameter
local FADER = {
  level = {15, 12, 9, 6, 3, 0},
  pan = {7, 4, 0, 0, -4, -7},
  cut = {12000, 6000, 3000, 1500, 600, 200},
  q = {15, 12, 9, 6, 3, 0},
  pitch = {12, 7, 5, 0, -5, -12},
  ftype = {nil, nil, 4, 3, 2, 1},      -- rows 3-6: high, band, low pass, off
}

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------
local g = grid.connect()
local a = arc.connect()
local midi_in
local gpage = 1                 -- grid / arc page: 1 TAPS, 2 RHYTHM, 3 COMB, 4 PRESETS
local spage = 1                 -- screen page: 1 TAPS, 2 RHYTHM, 3 COMB, 4 MIX
local ssel = {1, 1, 1, 1}
local tap_param = 1
local sel_tap = 1
local alt = false
local held = {}                 -- held keys "x,y"
local key_oct = 2
local frozen, reversed = false, false
local tap_t = {}
for i = 1, NT do tap_t[i] = (i) * 0.125 end
local presets = {}
local factory = {}
local current_preset = nil
local slot_a, slot_b = nil, nil
local morph_clock, morph_progress = nil, nil
local ramp_i = 0
local polls = {in_db = -90, dly_db = -90, cmb_db = -90, out_db = -90}
local onset_t, last_in = -10, -90
local message, message_t = nil, 0
local dirty_times, dirty_comb = true, true
local arc_acc = {0, 0, 0, 0}
local suspend = false           -- set while presets are applied in bulk
local tap_tempo_presses = {}

local function now() return util.time() end
local function msg(t) message = t; message_t = now() end
local function P(id) return params:lookup_param(id) end
local function tid(i, name) return "t" .. i .. "_" .. name end
local function note_name(n) n = math.floor(n + 0.5); return NOTE_NAMES[n % 12 + 1] .. (math.floor(n / 12) - 1) end

---------------------------------------------------------------------------
-- engine updates
---------------------------------------------------------------------------
local function beat_sec()
  if params:get("sync") == 1 then return clock.get_beat_sec() * BEAT_MULT[params:get("beat")] end
  return params:get("free_time")
end
local function spacing() return beat_sec() / GRIDS[params:get("grid")] end

local function compute_times()
  local sp, st = spacing(), STACKS[params:get("stack")]
  local gf, amt = GROOVES[params:get("groove")][2], params:get("groove_amt")
  for n = 1, NT do
    local m = math.floor((n - 1) / st) * st + st
    local pos = (1 - amt) * m + amt * gf(m)
    tap_t[n] = util.clamp(pos * sp, 0.001, 19.5)
  end
end

local function comb_size()
  if params:get("size_src") == 2 then return util.clamp(tap_t[1], 0.0005, 2) end
  return 1 / musicutil_note_hz(params:get("comb_note"))
end
function musicutil_note_hz(n) return 440 * 2 ^ ((n - 69) / 12) end

local function fb_time()
  local s = params:get("fb_tap")
  if s <= NT then return util.clamp(tap_t[s] + params:get("slip") * spacing() / 16, 0.001, 19.5)
  elseif s == NT + 1 then return tap_t[NT]
  else return comb_size() end
end

local function send_times()
  compute_times()
  for i = 1, NT do engine.tap_time(i, tap_t[i]) end
  local s = params:get("fb_tap")
  engine.fb_all(s == NT + 1 and 1 or 0)
  engine.fb_time(fb_time())
  if params:get("size_src") == 2 then engine.comb_size(comb_size()) end
end

local function send_comb()
  local f = COMBPAT[params:get("comb_pattern")][2]
  local sl = SLOPES[params:get("comb_slope")]
  local d = params:get("comb_density")
  local sum = 0
  local gains = {}
  for k = 1, 64 do
    -- density keeps the latest teeth: tooth 64 (the comb size, which sets the pitch) always sounds
    local on = (k > 64 - d) and 1 or 0
    gains[k] = on * sl(k / 64)
    sum = sum + gains[k]
  end
  local norm = sum > 0 and 1 / (sum ^ 0.75) or 0
  for k = 1, 64 do engine.comb_tooth(k, f(k), gains[k] * norm) end
end

local function tap_amp(i)
  if params:get(tid(i, "mute")) == 2 then return 0 end
  local l = params:get(tid(i, "level"))
  return l <= 0 and 0 or util.dbamp((l - 15) * 2.5)
end
local function tap_pitch(i)
  return params:get(tid(i, "pitch")) + params:get(tid(i, "detune")) / 100 + params:get("glob_pitch")
end
local function send_tap(i)
  engine.tap_level(i, tap_amp(i))
  engine.tap_pan(i, params:get(tid(i, "pan")) / 7)
  engine.tap_ftype(i, params:get(tid(i, "ftype")) - 1)
  engine.tap_cut(i, params:get(tid(i, "cut")))
  engine.tap_q(i, params:get(tid(i, "q")) / 15)
  engine.tap_pitch(i, tap_pitch(i))
end

---------------------------------------------------------------------------
-- params
---------------------------------------------------------------------------
local function mark_times() dirty_times = true end
local function mark_comb() dirty_comb = true end

local function add_params()
  params:add_separator("monsun_sep", "MONSUN")

  params:add_group("m_rhythm", "RHYTHM", 9)
  params:add_option("sync", "time source", {"clock", "free"}, 1)
  params:set_action("sync", mark_times)
  params:add_option("beat", "beat length", BEAT_NAMES, 5)
  params:set_action("beat", mark_times)
  params:add_control("free_time", "free beat time", controlspec.new(0.01, 4, "exp", 0, 0.5, "s"))
  params:set_action("free_time", mark_times)
  params:add_option("grid", "grid (taps/beat)", GRIDS, 4)
  params:set_action("grid", mark_times)
  params:add_option("groove", "groove", GROOVE_NAMES, 1)
  params:set_action("groove", mark_times)
  params:add_control("groove_amt", "groove amount", controlspec.new(0, 1, "lin", 0, 1, ""))
  params:set_action("groove_amt", mark_times)
  params:add_option("stack", "stack", STACKS, 1)
  params:set_action("stack", mark_times)
  params:add_number("glob_pitch", "global pitch", -24, 24, 0)
  params:set_action("glob_pitch", function() for i = 1, NT do engine.tap_pitch(i, tap_pitch(i)) end end)
  params:add_option("grain", "grain size", GRAIN_NAMES, 5)
  params:set_action("grain", function(v) engine.grain(GRAINS[v]) end)

  params:add_group("m_fb", "FEEDBACK", 7)
  params:add_control("fb", "feedback", controlspec.new(0, 1, "lin", 0, 0.35, ""))
  params:set_action("fb", function(v) engine.fb(v) end)
  local fbt = {}
  for i = 1, NT do fbt[i] = "tap " .. i end
  fbt[NT + 1] = "ALL"; fbt[NT + 2] = "comb size"
  params:add_option("fb_tap", "feedback tap", fbt, NT)
  params:set_action("fb_tap", mark_times)
  params:add_number("slip", "slip", -8, 7, 0)
  params:set_action("slip", mark_times)
  params:add_number("fb_pitch", "feedback pitch", -24, 24, 0)
  params:set_action("fb_pitch", function() engine.fb_pitch(params:get("fb_pitch") + params:get("fb_detune") / 100) end)
  params:add_number("fb_detune", "feedback detune", -50, 50, 0)
  params:set_action("fb_detune", function() engine.fb_pitch(params:get("fb_pitch") + params:get("fb_detune") / 100) end)
  params:add_control("fb_tone", "feedback tone", controlspec.new(-1, 1, "lin", 0, 0, ""))
  params:set_action("fb_tone", function(v) engine.fb_tone(v) end)
  params:add_option("delay_on", "delay", {"bypass", "on"}, 2)
  params:set_action("delay_on", function(v) engine.delay_on(v - 1) end)

  params:add_group("m_tlfo", "TIME LFO", 3)
  params:add_option("tlfo_wave", "waveform", LFO_WAVES, 1)
  params:set_action("tlfo_wave", function(v) engine.tlfo_wave(v - 1) end)
  params:add_control("tlfo_depth", "depth", controlspec.new(0, 10, "lin", 0, 2, "ms"))
  params:set_action("tlfo_depth", function(v) engine.tlfo_depth(v / 1000) end)
  params:add_control("tlfo_rate", "rate", controlspec.new(0.05, 20, "exp", 0, 0.5, "Hz"))
  params:set_action("tlfo_rate", function(v) engine.tlfo_rate(v) end)

  for i = 1, NT do
    params:add_group("m_tap" .. i, "TAP " .. i, 8)
    params:add_number(tid(i, "level"), "level", 0, 15, 15 - math.floor((i - 1) * 0.6))
    params:set_action(tid(i, "level"), function() engine.tap_level(i, tap_amp(i)) end)
    params:add_number(tid(i, "pan"), "pan", -7, 7, (i % 2 == 0) and 4 or -4)
    params:set_action(tid(i, "pan"), function(v) engine.tap_pan(i, v / 7) end)
    params:add_option(tid(i, "ftype"), "filter", FTYPES, 1)
    params:set_action(tid(i, "ftype"), function(v) engine.tap_ftype(i, v - 1) end)
    params:add_control(tid(i, "cut"), "cutoff", controlspec.new(40, 16000, "exp", 0, 3000, "Hz"))
    params:set_action(tid(i, "cut"), function(v) engine.tap_cut(i, v) end)
    params:add_number(tid(i, "q"), "Q", 0, 15, 4)
    params:set_action(tid(i, "q"), function(v) engine.tap_q(i, v / 15) end)
    params:add_number(tid(i, "pitch"), "pitch", -16, 15, 0)
    params:set_action(tid(i, "pitch"), function() engine.tap_pitch(i, tap_pitch(i)) end)
    params:add_number(tid(i, "detune"), "detune (cents)", -50, 50, 0)
    params:set_action(tid(i, "detune"), function() engine.tap_pitch(i, tap_pitch(i)) end)
    params:add_option(tid(i, "mute"), "mute", {"on", "muted"}, 1)
    params:set_action(tid(i, "mute"), function() engine.tap_level(i, tap_amp(i)) end)
  end

  params:add_group("m_comb", "COMB", 12)
  params:add_control("comb_note", "comb pitch", controlspec.new(12, 108, "lin", 0, 45, ""),
    function(p) local n = p:get(); return note_name(n) .. string.format(" %.1f Hz", musicutil_note_hz(n)) end)
  params:set_action("comb_note", function() if params:get("size_src") == 1 then engine.comb_size(comb_size()) end; mark_times() end)
  params:add_option("size_src", "size source", {"pitch / keys", "follow delay"}, 1)
  params:set_action("size_src", function() engine.comb_size(comb_size()); mark_times() end)
  params:add_control("comb_glide", "glide", controlspec.new(0, 1, "lin", 0, 0, "s"))
  params:set_action("comb_glide", function(v) engine.comb_glide(v) end)
  params:add_option("comb_pattern", "tooth pattern", COMB_NAMES, 1)
  params:set_action("comb_pattern", mark_comb)
  params:add_number("comb_density", "density", 1, 64, 8)
  params:set_action("comb_density", mark_comb)
  params:add_option("comb_slope", "slope", {"flat", "rising", "falling", "rise/fall"}, 1)
  params:set_action("comb_slope", mark_comb)
  params:add_control("comb_fb", "comb feedback", controlspec.new(0, 0.999, "lin", 0, 0.94, ""))
  params:set_action("comb_fb", function(v) engine.comb_fb(v) end)
  params:add_option("comb_type", "feedback type", CTYPES, 1)
  params:set_action("comb_type", function(v) engine.comb_type(v - 1) end)
  params:add_option("exciter", "exciter", {"noise burst", "smooth pulse"}, 1)
  params:set_action("exciter", function(v) engine.exciter(v - 1) end)
  params:add_option("slfo_wave", "size LFO", LFO_WAVES, 1)
  params:set_action("slfo_wave", function(v) engine.slfo_wave(v - 1) end)
  params:add_control("slfo_depth", "size LFO depth", controlspec.new(0, 1, "lin", 0, 0.1, ""))
  params:set_action("slfo_depth", function(v) engine.slfo_depth(v * 0.1) end)
  params:add_control("slfo_rate", "size LFO rate", controlspec.new(0.05, 20, "exp", 0, 0.3, "Hz"))
  params:set_action("slfo_rate", function(v) engine.slfo_rate(v) end)

  params:add_group("m_mix", "MIX / SOURCE", 11)
  params:add_option("routing", "routing", ROUTINGS, 1)
  params:set_action("routing", function(v) engine.routing(v - 1) end)
  params:add_control("mix", "dry/wet", controlspec.new(0, 1, "lin", 0, 0.5, ""))
  params:set_action("mix", function(v) engine.mix(v) end)
  params:add_control("balance", "delay <> comb", controlspec.new(0, 1, "lin", 0, 0, ""))
  params:set_action("balance", function(v) engine.balance(v) end)
  params:add_option("comb_on", "comb", {"bypass", "on"}, 2)
  params:set_action("comb_on", function(v) engine.comb_on(v - 1) end)
  params:add_control("in_gain", "input gain", controlspec.new(-24, 12, "lin", 0, 0, "dB"))
  params:set_action("in_gain", function(v) engine.in_gain(v) end)
  params:add_control("out_level", "output level", controlspec.new(-24, 6, "lin", 0, 0, "dB"))
  params:set_action("out_level", function(v) engine.out_level(v) end)
  params:add_option("source", "source", SOURCES, 1)
  params:set_action("source", function(v) engine.source(v - 1) end)
  params:add_file("file", "audio file", _path.audio)
  params:set_action("file", function(f)
    if f and f ~= "" and f ~= "-" and string.sub(f, -1) ~= "/" then engine.file(f); params:set("source", 2) end
  end)
  params:add_control("ping_amp", "ping level", controlspec.new(0, 1, "lin", 0, 1, ""))
  params:add_option("morph_time", "preset morph", MORPH, 2)
  params:add_control("ab", "A <> B", controlspec.new(0, 1, "lin", 0, 0, ""))
  params:set_action("ab", function() ab_apply() end)
  params:set_save("ab", false)

  params:add_group("m_midi", "MIDI", 4)
  params:add_number("midi_dev", "midi device", 1, 16, 1)
  params:set_action("midi_dev", function(v) if midi_in then midi_in.event = nil end; midi_in = midi.connect(v); midi_in.event = midi_event end)
  params:add_number("midi_ch", "midi channel", 0, 16, 0, function(p) return p:get() == 0 and "all" or p:get() end)
  params:add_option("midi_notes", "notes play comb", {"off", "on"}, 2)
  params:add_option("rnd_dest", "random destination", RND_DEST, 15)
end

---------------------------------------------------------------------------
-- presets
---------------------------------------------------------------------------
local PRESET_SKIP = {source = true, file = true, in_gain = true, out_level = true, ab = true, morph_time = true,
  midi_dev = true, midi_ch = true, midi_notes = true, rnd_dest = true, ping_amp = true}
local preset_ids = {}
local first_param = 1
local function build_preset_ids()
  for i = first_param, params.count do
    local p = params.params[i]
    if p and p.id and p.t ~= params.tSEPARATOR and p.t ~= params.tGROUP and p.t ~= params.tFILE and not PRESET_SKIP[p.id]
      and p.id ~= "clock_tempo" and p.id ~= "clock_source" then
      preset_ids[#preset_ids + 1] = p.id
    end
  end
end
local function capture()
  local t = {}
  for _, id in ipairs(preset_ids) do t[id] = params:get(id) end
  return t
end

local function factory_presets()
  local base = capture()
  local function make(name, f)
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    f(t)
    t._name = name
    factory[#factory + 1] = t
  end
  local function taps(t, field, fn) for i = 1, NT do t[tid(i, field)] = fn(i) end end
  make("drizzle", function(t)
    t.grid = 4; t.groove = 1; t.fb = 0.3; t.fb_tap = 16; t.balance = 0
    taps(t, "level", function(i) return 15 - math.floor(i * 0.7) end)
    taps(t, "ftype", function() return 2 end); taps(t, "cut", function(i) return 6000 - i * 300 end)
  end)
  make("swing dub", function(t)
    t.grid = 2; t.groove = 2; t.fb = 0.62; t.fb_tap = 8; t.fb_tone = -0.45; t.mix = 0.45
    taps(t, "mute", function(i) return ({1, 2, 1, 1, 2, 1, 2, 1, 2, 2, 2, 2, 2, 2, 2, 2})[i] end)
    taps(t, "ftype", function() return 3 end); taps(t, "cut", function() return 1200 end); taps(t, "q", function() return 6 end)
  end)
  make("octave rain", function(t)
    t.grid = 8; t.fb = 0.45; t.fb_pitch = 12; t.fb_tap = 16; t.fb_tone = -0.2; t.mix = 0.5
    taps(t, "pitch", function(i) return i % 2 == 0 and 12 or 0 end)
    taps(t, "pan", function(i) return i % 2 == 0 and 7 or -7 end)
  end)
  make("chord stack", function(t)
    t.grid = 2; t.stack = 3; t.fb = 0.4; t.fb_tap = 16; t.mix = 0.45
    taps(t, "pitch", function(i) return ({0, 4, 7, 11})[(i - 1) % 4 + 1] - (i > 8 and 12 or 0) end)
    taps(t, "pan", function(i) return ({-6, -2, 2, 6})[(i - 1) % 4 + 1] end)
  end)
  make("accelerando", function(t)
    t.grid = 2; t.groove = 6; t.fb = 0.2
    taps(t, "level", function(i) return 6 + math.floor(i * 9 / 16) end)
    taps(t, "ftype", function() return 3 end); taps(t, "q", function() return 9 end)
    taps(t, "cut", function(i) return 300 * (8000 / 300) ^ ((i - 1) / 15) end)
  end)
  make("filter sweep", function(t)
    t.grid = 8; t.fb = 0.35; t.fb_tap = 16
    taps(t, "ftype", function() return 3 end); taps(t, "q", function() return 12 end)
    taps(t, "cut", function(i) return 8000 * (200 / 8000) ^ ((i - 1) / 15) end)
    taps(t, "pan", function(i) return math.floor(7 * math.sin(i * 0.8) + 0.5) end)
  end)
  make("random dust", function(t)
    t.grid = 16; t.groove = 12; t.fb = 0.5; t.fb_tap = 17; t.tlfo_wave = 8; t.tlfo_depth = 4; t.tlfo_rate = 3
    taps(t, "level", function(i) return 6 + math.floor(hash(i, 9) * 9) end)
    taps(t, "pitch", function(i) return ({-12, -5, 0, 0, 7, 12})[math.floor(hash(i, 4) * 6) + 1] end)
    taps(t, "pan", function(i) return math.floor((hash(i, 5) - 0.5) * 14) end)
  end)
  make("waltz echo", function(t)
    t.grid = 3; t.groove = 8; t.fb = 0.45; t.fb_tap = 12; t.fb_tone = -0.3
    taps(t, "level", function(i) return (i - 1) % 3 == 0 and 15 or 9 end)
  end)
  make("comb strings", function(t)
    t.routing = 3; t.balance = 1; t.comb_note = 45; t.comb_type = 1; t.comb_fb = 0.995; t.comb_pattern = 1; t.comb_density = 1
    t.fb = 0.25; t.mix = 0.8
  end)
  make("sitar drone", function(t)
    t.routing = 1; t.balance = 0.7; t.comb_note = 38; t.comb_type = 2; t.comb_fb = 0.99; t.comb_pattern = 4; t.comb_density = 32
    t.grid = 2; t.fb = 0.3; t.mix = 0.6
  end)
  make("clarinet reed", function(t)
    t.routing = 3; t.balance = 0.8; t.comb_note = 50; t.comb_type = 3; t.comb_fb = 0.97; t.comb_slope = 3; t.comb_density = 6; t.mix = 0.6
  end)
  make("cloud comb", function(t)
    t.routing = 1; t.balance = 0.6; t.comb_note = 13; t.comb_pattern = 12; t.comb_slope = 4; t.comb_fb = 0.6; t.comb_type = 4; t.comb_density = 64
    t.grid = 4; t.groove = 2; t.fb = 0.4; t.mix = 0.6; t.slfo_wave = 2; t.slfo_depth = 0.2
  end)
end

local function preset(i) return presets[i] or factory[i] end
local function preset_name(i)
  local p = preset(i)
  if not p then return nil end
  return p._name or ("preset " .. i)
end

local function presets_path() return norns.state.data .. "presets.data" end
local function save_presets()
  pcall(function()
    if util.make_dir then util.make_dir(norns.state.data) end
    tab.save(presets, presets_path())
  end)
end
local function load_presets()
  local ok, t = pcall(tab.load, presets_path())
  if ok and type(t) == "table" then presets = t end
end

local function is_option(id) return P(id).t == params.tOPTION end
local function is_number(id) return P(id).t == params.tNUMBER end

-- set many params at once; engine updates for times and comb are coalesced
local function set_many(t)
  suspend = true
  for id, v in pairs(t) do if id ~= "_name" and params.lookup[id] then params:set(id, v) end end
  suspend = false
  dirty_times = true; dirty_comb = true
end

local function morph_to(target)
  if morph_clock then clock.cancel(morph_clock); morph_clock = nil; morph_progress = nil end
  local beats = MORPH_BEATS[params:get("morph_time")]
  local secs = beats * clock.get_beat_sec()
  if secs < 0.05 then set_many(target); return end
  local from, to, opts = {}, {}, {}
  for id, v in pairs(target) do
    if id ~= "_name" and params.lookup[id] then
      if is_option(id) then opts[id] = v
      elseif is_number(id) then from[id] = params:get(id); to[id] = v
      else from[id] = params:get_raw(id); to[id] = P(id).controlspec:unmap(v) end
    end
  end
  morph_clock = clock.run(function()
    local t0 = now()
    local switched = false
    while true do
      local f = util.clamp((now() - t0) / secs, 0, 1)
      morph_progress = f
      local e = f * f * (3 - 2 * f)
      suspend = true
      for id, r in pairs(to) do
        local x = from[id] + (r - from[id]) * e
        if is_number(id) then
          local v = math.floor(x + 0.5)
          if v ~= params:get(id) then params:set(id, v) end
        else params:set_raw(id, x) end
      end
      if not switched and f >= 0.5 then for id, v in pairs(opts) do params:set(id, v) end; switched = true end
      suspend = false
      dirty_times = true; dirty_comb = true
      if f >= 1 then break end
      clock.sleep(1 / 25)
    end
    set_many(target)
    morph_clock = nil; morph_progress = nil
  end)
end

local function recall(i)
  local p = preset(i)
  if not p then msg("slot " .. i .. " is empty"); return end
  morph_to(p)
  current_preset = i
  msg(preset_name(i))
end
local function store(i)
  local t = capture()
  t._name = "preset " .. i
  presets[i] = t
  save_presets()
  current_preset = i
  msg("saved " .. i)
end

-- A <> B crossfade on arc ring 1 of the PRESETS page
function ab_apply()
  if not (slot_a and slot_b) then return end
  local A, B = preset(slot_a), preset(slot_b)
  if not (A and B) then return end
  local x = params:get("ab")
  local t = {}
  for id, va in pairs(A) do
    local vb = B[id]
    if id ~= "_name" and vb ~= nil and params.lookup[id] then
      if is_option(id) then t[id] = x < 0.5 and va or vb
      elseif is_number(id) then t[id] = math.floor(va + (vb - va) * x + 0.5)
      else
        local cs = P(id).controlspec
        t[id] = cs:map(cs:unmap(va) + (cs:unmap(vb) - cs:unmap(va)) * x)
      end
    end
  end
  set_many(t)
end

---------------------------------------------------------------------------
-- ramps and random
---------------------------------------------------------------------------
local RAMPS = {
  {"rising", function(x) return x end},
  {"falling", function(x) return 1 - x end},
  {"V", function(x) return math.abs(2 * x - 1) end},
  {"peak", function(x) return 1 - math.abs(2 * x - 1) end},
  {"odd / even", function(_, i) return i % 2 == 0 and 1 or 0 end},
  {"saw x2", function(x) return frac(x * 2 * 15 / 16) * 16 / 15 end},
  {"saw x4", function(x) return frac(x * 4 * 15 / 16) * 16 / 15 end},
  {"random walk", nil},
}
local function set_tap_norm(i, name, u)
  local id = tid(i, name)
  if name == "ftype" then params:set(id, util.clamp(math.floor(u * 3.999) + 1, 1, 4))
  elseif name == "cut" then params:set(id, 100 * (12000 / 100) ^ u)
  elseif name == "pan" then params:set(id, math.floor(-7 + 14 * u + 0.5))
  elseif name == "pitch" then params:set(id, ({-12, -7, -5, 0, 5, 7, 12})[util.clamp(math.floor(u * 7) + 1, 1, 7)])
  else params:set(id, math.floor(15 * u + 0.5)) end
end
local function ramp()
  ramp_i = ramp_i % #RAMPS + 1
  local name = TAP_PARAMS[tap_param]
  local r = RAMPS[ramp_i]
  local w = math.random()
  for i = 1, NT do
    local x = (i - 1) / (NT - 1)
    local u
    if r[2] then u = r[2](x, i) else w = util.clamp(w + (math.random() - 0.5) * 0.35, 0, 1); u = w end
    set_tap_norm(i, name, u)
  end
  msg(TAP_PARAM_NAMES[tap_param]:lower() .. " ramp: " .. r[1])
end

local function rnd_taps(name, prob)
  for i = 1, NT do
    if name == "mute" then params:set(tid(i, "mute"), math.random() < (prob or 0.3) and 2 or 1)
    else set_tap_norm(i, name, math.random()) end
  end
end
local randomize_inner
local function randomize(dest)
  local ok, err = pcall(randomize_inner, dest)
  suspend = false
  dirty_times = true; dirty_comb = true
  if not ok then print("monsun random: " .. tostring(err)) end
end
randomize_inner = function(dest)
  suspend = true
  local function delay_globals()
    params:set("groove", math.random(1, 16)); params:set("groove_amt", math.random())
    params:set("grid", math.random(2, 6)); params:set("fb", math.random() * 0.7)
    params:set("fb_tap", math.random(1, 17)); params:set("fb_pitch", ({0, 0, 0, 12, -12, 7, 5})[math.random(1, 7)])
    params:set("fb_tone", (math.random() - 0.5) * 1.4)
  end
  local function comb()
    params:set("comb_pattern", math.random(1, 16)); params:set("comb_density", math.random(8, 64))
    params:set("comb_slope", math.random(1, 4)); params:set("comb_type", math.random(1, 4))
    params:set("comb_fb", 0.5 + math.random() * 0.49); params:set("comb_note", math.random(30, 70))
  end
  local function all_taps() for _, n in ipairs({"level", "pan", "cut", "q", "pitch", "ftype"}) do rnd_taps(n) end; rnd_taps("mute", 0.2) end
  if dest == 15 then dest = math.random(1, 14) end
  if dest == 1 then params:set("groove", math.random(1, 16)); params:set("groove_amt", 0.3 + math.random() * 0.7)
  elseif dest == 2 then rnd_taps("mute")
  elseif dest == 3 then rnd_taps("level")
  elseif dest == 4 then rnd_taps("pan")
  elseif dest == 5 then rnd_taps("cut")
  elseif dest == 6 then rnd_taps("q")
  elseif dest == 7 then rnd_taps("pitch")
  elseif dest == 8 then comb()
  elseif dest == 9 then delay_globals()
  elseif dest == 10 then all_taps()
  elseif dest == 11 then delay_globals(); rnd_taps("mute", 0.25); params:set("stack", math.random(1, 4))
  elseif dest == 12 then all_taps(); delay_globals()
  elseif dest == 13 then comb(); delay_globals()
  else all_taps(); delay_globals(); comb() end
  suspend = false
  dirty_times = true; dirty_comb = true
  msg("random: " .. RND_DEST[dest])
end

---------------------------------------------------------------------------
-- actions
---------------------------------------------------------------------------
local function ping()
  engine.ping(params:get("ping_amp"))
  onset_t = now()
end
local function pluck(vel)
  engine.pluck(vel or params:get("ping_amp"))
end
local function play_note(n, vel)
  params:set("comb_note", n)
  if params:get("size_src") ~= 1 then params:set("size_src", 1) end
  -- playing the comb should always be heard: bring it into the mix if it is bypassed or mixed out
  if params:get("comb_on") ~= 2 then params:set("comb_on", 2) end
  if params:get("balance") < 0.5 and params:get("routing") ~= 4 then params:set("balance", 0.5); msg("comb in the mix: 50%") end
  if params:get("comb_fb") < 0.9 then params:set("comb_fb", 0.94) end
  if params:get("mix") < 0.5 then params:set("mix", 0.5) end
  pluck(vel)
end
local function set_freeze(v) frozen = v; engine.freeze(v and 1 or 0) end
local function set_reverse(v) reversed = v; engine.reverse(v and 1 or 0) end
local function clear() engine.clear(); msg("cleared") end
local function tap_tempo()
  local t = now()
  if #tap_tempo_presses > 0 and t - tap_tempo_presses[#tap_tempo_presses] > 2.5 then tap_tempo_presses = {} end
  table.insert(tap_tempo_presses, t)
  while #tap_tempo_presses > 4 do table.remove(tap_tempo_presses, 1) end
  if #tap_tempo_presses >= 2 then
    local d = (tap_tempo_presses[#tap_tempo_presses] - tap_tempo_presses[1]) / (#tap_tempo_presses - 1)
    params:set("sync", 2); params:set("free_time", d)
    msg(string.format("tap %.0f ms", d * 1000))
  end
end

---------------------------------------------------------------------------
-- MIDI
---------------------------------------------------------------------------
function midi_event(data)
  local m = midi.to_msg(data)
  local ch = params:get("midi_ch")
  if ch > 0 and m.ch and m.ch ~= ch then return end
  if m.type == "note_on" and params:get("midi_notes") == 2 then
    play_note(m.note, (m.vel or 100) / 127)
  end
end

---------------------------------------------------------------------------
-- grid
---------------------------------------------------------------------------
local function tap_row_level(i, name, row)
  -- brightness of fader row (1-6) for tap i, drawn from the same rows the keys set
  local v = params:get(tid(i, name))
  local rows = FADER[name]
  if name == "ftype" then
    if row < 3 then return 0 end
    return rows[row] == v and 13 or 1
  end
  local best, bd = 1, math.huge
  for r = 1, 6 do
    local d = name == "cut" and math.abs(math.log(rows[r] / v)) or math.abs(rows[r] - v)
    if (name == "pan" or name == "pitch") and v ~= 0 then
      if (v > 0 and r >= 4) or (v < 0 and r <= 3) then d = math.huge end   -- keep the sign: positive above centre, negative below
    end
    if d < bd then bd = d; best = r end
  end
  if name == "pan" or name == "pitch" then
    if v == 0 then return (row == 3 or row == 4) and 5 or 0 end
    if best <= 3 then
      if row == best then return 13 elseif row > best and row <= 3 then return 5 end
    else
      if row == best then return 13 elseif row < best and row >= 4 then return 5 end
    end
    return 0
  end
  if row == best then return 13 elseif row > best then return 5 end
  return 0
end

local function grid_taps()
  local name = TAP_PARAMS[tap_param]
  local t = now() - onset_t
  for x = 1, NT do
    for row = 1, 6 do
      local l = tap_row_level(x, name, row)
      if x == sel_tap and l == 0 then l = 1 end
      g:led(x, row, l)
    end
    local muted = params:get(tid(x, "mute")) == 2
    local l = muted and 1 or 6
    if not muted and t >= tap_t[x] and t < tap_t[x] + 0.09 then l = 15 end
    g:led(x, 7, l)
  end
  for i = 1, 6 do g:led(i + 4, 8, tap_param == i and 12 or 3) end
end

local function grid_rhythm()
  for x = 1, 16 do
    g:led(x, 1, params:get("groove") == x and 13 or 3)
    local ga = math.floor(params:get("groove_amt") * 15 + 0.5) + 1
    g:led(x, 2, x <= ga and (x == ga and 13 or 5) or 1)
    if x <= 8 then g:led(x, 3, params:get("grid") == x and 13 or 3)
    else g:led(x, 3, params:get("beat") == x - 8 and 13 or 3) end
    if x <= 4 then g:led(x, 4, params:get("stack") == x and 13 or 3)
    elseif x >= 9 then g:led(x, 4, params:get("tlfo_wave") == x - 8 and 13 or 3) end
    local ft = params:get("fb_tap")
    g:led(x, 5, ft == x and 13 or ((ft == 17) and 8 or ((ft == 18) and 2 or 3)))
    if x <= 12 then g:led(x, 6, params:get("fb_pitch") == FB_PITCHES[x] and 13 or (FB_PITCHES[x] == 0 and 5 or 3)) end
    local s = params:get("slip")
    g:led(x, 7, (x - 9) == s and 13 or (x == 9 and 5 or 2))
  end
  g:led(5, 8, 5)
  g:led(6, 8, params:get("sync") == 1 and 12 or 3)
  g:led(7, 8, 4)
  g:led(8, 8, params:get("delay_on") == 2 and 10 or 2)
  g:led(9, 8, 4)
  g:led(10, 8, 4)
end

local function key_note(x, y) return 12 * (key_oct + 1) + (x - 1) + (7 - y) * 5 end

local function grid_comb()
  for x = 1, 16 do
    g:led(x, 1, params:get("comb_pattern") == x and 13 or 3)
    local d = math.ceil(params:get("comb_density") / 4)
    g:led(x, 2, x <= d and (x == d and 13 or 5) or 1)
    local sel = {params:get("comb_slope"), 4 + params:get("comb_type"), 8 + params:get("routing"), 12 + params:get("size_src")}
    local l = 3
    for _, s in ipairs(sel) do if s == x then l = 13 end end
    if x == 15 then l = params:get("comb_glide") > 0 and 10 or 3 end
    if x == 16 then l = 5 end
    g:led(x, 3, l)
    local cur = math.floor(params:get("comb_note") + 0.5)
    for y = 4, 7 do
      local n = key_note(x, y)
      local k = n % 12
      local lv = (k == 0) and 5 or ((k == 2 or k == 4 or k == 5 or k == 7 or k == 9 or k == 11) and 2 or 1)
      if n == cur then lv = 15 end
      g:led(x, y, lv)
    end
  end
  g:led(5, 8, 4); g:led(6, 8, 4)
  g:led(7, 8, 4)
  g:led(8, 8, params:get("exciter") == 1 and 8 or 12)
  g:led(9, 8, params:get("comb_on") == 2 and 10 or 2)
  g:led(10, 8, 4)
end

local function grid_presets()
  for y = 1, 6 do for x = 1, 16 do
    local i = (y - 1) * 16 + x
    local l = preset(i) and (presets[i] and 6 or 4) or 1
    if i == slot_a or i == slot_b then l = 9 end
    if i == current_preset then l = 14 end
    g:led(x, y, l)
  end end
  for x = 1, 15 do g:led(x, 7, params:get("rnd_dest") == x and 12 or 3) end
  local mt = params:get("morph_time")
  g:led(5, 8, morph_progress and math.floor(4 + morph_progress * 11) or (mt == 1 and 2 or 3 + mt * 2))
  g:led(6, 8, held["6,8"] and 15 or (slot_a and 8 or 3))
  g:led(7, 8, held["7,8"] and 15 or (slot_b and 8 or 3))
  g:led(8, 8, 4)
  g:led(10, 8, held["10,8"] and 15 or 4)
end

function grid_redraw()
  g:all(0)
  if gpage == 1 then grid_taps() elseif gpage == 2 then grid_rhythm() elseif gpage == 3 then grid_comb() else grid_presets() end
  for i = 1, 4 do g:led(i, 8, gpage == i and 14 or 4) end
  g:led(11, 8, 5); g:led(12, 8, 5)
  g:led(13, 8, (now() - onset_t < 0.12) and 15 or 6)
  g:led(14, 8, frozen and 15 or 4)
  g:led(15, 8, reversed and 15 or 4)
  g:led(16, 8, alt and 15 or 3)
  g:refresh()
end

local function grid_key_taps(x, y)
  local name = TAP_PARAMS[tap_param]
  if y <= 6 then
    sel_tap = x
    local v = FADER[name][y]
    if v ~= nil then params:set(tid(x, name), v) end
  elseif y == 7 then
    if alt then sel_tap = x; msg("tap " .. x)
    else params:set(tid(x, "mute"), params:get(tid(x, "mute")) == 2 and 1 or 2) end
  elseif y == 8 and x >= 5 and x <= 10 then
    tap_param = x - 4
  end
end

local function grid_key_rhythm(x, y)
  if y == 1 then params:set("groove", x)
  elseif y == 2 then params:set("groove_amt", (x - 1) / 15)
  elseif y == 3 then if x <= 8 then params:set("grid", x) else params:set("beat", x - 8) end
  elseif y == 4 then if x <= 4 then params:set("stack", x) elseif x >= 9 then params:set("tlfo_wave", x - 8) end
  elseif y == 5 then
    if alt then params:set("fb_tap", NT + 2); msg("feedback: comb size")
    elseif params:get("fb_tap") == x then params:set("fb_tap", NT + 1); msg("feedback: all taps")
    else params:set("fb_tap", x) end
  elseif y == 6 then if x <= 12 then params:set("fb_pitch", FB_PITCHES[x]) end
  elseif y == 7 then params:set("slip", x - 9)
  elseif y == 8 then
    if x == 5 then tap_tempo()
    elseif x == 6 then params:set("sync", params:get("sync") == 1 and 2 or 1); msg(params:get("sync") == 1 and "clock sync" or "free time")
    elseif x == 7 then
      for i = 1, NT do params:set(tid(i, "pan"), (i % 2 == 0) and 7 or -7) end; msg("pans: left / right")
    elseif x == 8 then params:set("delay_on", params:get("delay_on") == 2 and 1 or 2)
    elseif x == 9 then params:set("fb", 0); msg("feedback 0")
    elseif x == 10 then params:set("glob_pitch", 0); msg("global pitch 0") end
  end
end

local function grid_key_comb(x, y)
  if y == 1 then params:set("comb_pattern", x)
  elseif y == 2 then params:set("comb_density", x * 4)
  elseif y == 3 then
    if x <= 4 then params:set("comb_slope", x)
    elseif x <= 8 then params:set("comb_type", x - 4)
    elseif x <= 12 then params:set("routing", x - 8)
    elseif x <= 14 then params:set("size_src", x - 12)
    elseif x == 15 then params:set("comb_glide", params:get("comb_glide") > 0 and 0 or 0.08)
    else pluck() end
  elseif y >= 4 and y <= 7 then
    local n = key_note(x, y)
    if alt then params:set("comb_note", n); params:set("size_src", 1) else play_note(n) end
  elseif y == 8 then
    if x == 5 then key_oct = util.clamp(key_oct - 1, 0, 5); msg("keys from " .. note_name(key_note(1, 7)))
    elseif x == 6 then key_oct = util.clamp(key_oct + 1, 0, 5); msg("keys from " .. note_name(key_note(1, 7)))
    elseif x == 7 then pluck()
    elseif x == 8 then params:set("exciter", params:get("exciter") == 1 and 2 or 1); msg(params:string("exciter"))
    elseif x == 9 then params:set("comb_on", params:get("comb_on") == 2 and 1 or 2)
    elseif x == 10 then params:set("comb_fb", 0); msg("comb feedback 0") end
  end
end

local function grid_key_presets(x, y)
  if y <= 6 then
    local i = (y - 1) * 16 + x
    if held["6,8"] then slot_a = i; msg("A = " .. (preset_name(i) or i)); ab_apply()
    elseif held["7,8"] then slot_b = i; msg("B = " .. (preset_name(i) or i)); ab_apply()
    elseif held["10,8"] or alt then store(i)
    else recall(i) end
  elseif y == 7 then
    if x <= 15 then params:set("rnd_dest", x); msg("random: " .. RND_DEST[x]) end
  elseif y == 8 then
    if x == 5 then params:set("morph_time", params:get("morph_time") % #MORPH + 1); msg("morph " .. MORPH[params:get("morph_time")])
    elseif x == 8 then clear() end
  end
end

g.key = function(x, y, z)
  local k = x .. "," .. y
  held[k] = (z == 1) or nil
  if x == 16 and y == 8 then alt = (z == 1); return end
  if z == 0 then return end
  if y == 8 and x <= 4 then gpage = x; spage = x == 4 and spage or x; arc_acc = {0, 0, 0, 0}; return end
  if y == 8 and x == 11 then ramp(); return end
  if y == 8 and x == 12 then
    if gpage == 1 and not alt then rnd_taps(TAP_PARAMS[tap_param]); msg("random " .. TAP_PARAM_NAMES[tap_param]:lower())
    else randomize(params:get("rnd_dest")) end
    return
  end
  if y == 8 and x == 13 then if alt then clear() elseif gpage == 3 then pluck() else ping() end; return end
  if y == 8 and x == 14 then set_freeze(not frozen); return end
  if y == 8 and x == 15 then set_reverse(not reversed); return end
  if gpage == 1 then grid_key_taps(x, y)
  elseif gpage == 2 then grid_key_rhythm(x, y)
  elseif gpage == 3 then grid_key_comb(x, y)
  else grid_key_presets(x, y) end
end

---------------------------------------------------------------------------
-- arc
---------------------------------------------------------------------------
local ARC = {
  {"tap", "tap value", "global pitch", "mix"},
  {"beat time", "groove amount", "feedback", "tone"},
  {"comb pitch", "comb feedback", "density", "delay <> comb"},
  {"A <> B", "LFO depth", "LFO rate", "grain size"},
}
local function arc_id(n)
  if gpage == 1 then
    if n == 1 then return nil
    elseif n == 2 then return tid(sel_tap, TAP_PARAMS[tap_param])
    elseif n == 3 then return "glob_pitch" else return "mix" end
  elseif gpage == 2 then
    if n == 1 then return params:get("sync") == 1 and "beat" or "free_time" end
    return ({nil, "groove_amt", "fb", "fb_tone"})[n]
  elseif gpage == 3 then return ({"comb_note", "comb_fb", "comb_density", "balance"})[n]
  else return ({"ab", "tlfo_depth", "tlfo_rate", "grain"})[n] end
end

a.delta = function(n, d)
  local fine = alt and 4 or 1
  if gpage == 1 and n == 1 then
    arc_acc[1] = arc_acc[1] + d
    if math.abs(arc_acc[1]) >= 40 then sel_tap = util.clamp(sel_tap + (arc_acc[1] > 0 and 1 or -1), 1, NT); arc_acc[1] = 0 end
    return
  end
  local id = arc_id(n)
  if not id then return end
  local p = P(id)
  if p.t == params.tOPTION or p.t == params.tNUMBER then
    arc_acc[n] = arc_acc[n] + d
    local step = (p.t == params.tOPTION and 50 or 24) * fine
    if math.abs(arc_acc[n]) >= step then params:delta(id, arc_acc[n] > 0 and 1 or -1); arc_acc[n] = 0 end
  else
    params:delta(id, d / (8 * fine))
  end
end

local function ring_pos(i) return ((40 + i) % 64) + 1 end
function arc_redraw()
  for n = 1, 4 do
    for i = 1, 64 do a:led(n, i, 0) end
    if gpage == 1 and n == 1 then
      for i = 1, 64 do
        local seg = math.floor((i - 1) / 4) + 1
        a:led(n, i, seg == sel_tap and 14 or ((i - 1) % 4 == 0 and 3 or 1))
      end
    else
      local id = arc_id(n)
      local p = P(id)
      local raw
      if p.t == params.tOPTION then raw = (params:get(id) - 1) / math.max(1, p.count - 1)
      elseif p.t == params.tNUMBER then
        local lim = math.max(math.abs(p.min), math.abs(p.max))
        if p.min < 0 then raw = 0.5 + 0.5 * params:get(id) / lim else raw = (params:get(id) - p.min) / math.max(1, p.max - p.min) end
      else raw = params:get_raw(id) end
      local bipolar = id == "fb_tone" or id == "glob_pitch" or string.find(id, "_pan") or string.find(id, "_pitch")
      if bipolar then
        local v = raw * 2 - 1
        local span = math.floor(math.abs(v) * 24 + 0.5)
        for i = 0, span do a:led(n, ((v >= 0 and i or -i) % 64) + 1, i == span and 15 or 5) end
        a:led(n, 1, 9)
      else
        local tip = math.floor(raw * 47 + 0.5)
        for i = 0, 47 do a:led(n, ring_pos(i), i < tip and 5 or (i == tip and 15 or 1)) end
      end
    end
    if frozen then a:led(n, math.floor(now() * 16 + n * 16) % 64 + 1, 10) end
  end
  a:refresh()
end

---------------------------------------------------------------------------
-- norns keys, encoders, screen
---------------------------------------------------------------------------
local LISTS = {
  nil,
  {"groove", "groove_amt", "grid", "stack", "sync", "beat", "free_time", "fb", "fb_tap", "slip", "fb_pitch", "fb_detune",
   "fb_tone", "glob_pitch", "grain", "tlfo_wave", "tlfo_depth", "tlfo_rate"},
  {"comb_note", "comb_pattern", "comb_density", "comb_slope", "comb_fb", "comb_type", "size_src", "comb_glide", "exciter",
   "slfo_wave", "slfo_depth", "slfo_rate"},
  {"routing", "mix", "balance", "in_gain", "out_level", "source", "delay_on", "comb_on", "morph_time", "ping_amp"},
}
local SHORT = {groove = "groove", groove_amt = "amount", grid = "grid", stack = "stack", sync = "time", beat = "beat",
  free_time = "free time", fb = "feedback", fb_tap = "fb tap", slip = "slip", fb_pitch = "fb pitch", fb_detune = "fb detune",
  fb_tone = "fb tone", glob_pitch = "all pitch", grain = "grain", tlfo_wave = "lfo", tlfo_depth = "lfo depth",
  tlfo_rate = "lfo rate", comb_note = "pitch", comb_pattern = "pattern", comb_density = "density", comb_slope = "slope",
  comb_fb = "feedback", comb_type = "type", size_src = "size", comb_glide = "glide", exciter = "exciter",
  slfo_wave = "size lfo", slfo_depth = "lfo depth", slfo_rate = "lfo rate", routing = "routing", mix = "dry/wet",
  balance = "dly<>cmb", in_gain = "input", out_level = "output", source = "source", delay_on = "delay",
  comb_on = "comb", morph_time = "morph", ping_amp = "ping"}

local function pstr(id)
  local s = params:string(id)
  if id == "fb_tone" then local v = params:get(id); return math.abs(v) < 0.02 and "flat" or string.format("%s %d%%", v < 0 and "LP" or "HP", math.floor(math.abs(v) * 100 + 0.5)) end
  if id == "fb" or id == "comb_fb" or id == "mix" or id == "balance" or id == "groove_amt" or id == "ping_amp" or id == "slfo_depth" then
    return string.format("%d%%", math.floor(params:get(id) * 100 + 0.5))
  end
  return string.gsub(s, " (%a+)$", "%1")
end

function enc(n, d)
  if n == 1 then spage = util.clamp(spage + d, 1, 4); return end
  if spage == 1 then
    if n == 2 then sel_tap = util.clamp(sel_tap + d, 1, NT)
    else params:delta(tid(sel_tap, TAP_PARAMS[tap_param]), d) end
    return
  end
  local list = LISTS[spage]
  if n == 2 then ssel[spage] = util.clamp(ssel[spage] + d, 1, #list)
  else params:delta(list[ssel[spage]], d) end
end

function key(n, z)
  if z == 0 then return end
  if n == 2 then set_freeze(not frozen); msg(frozen and "freeze" or "freeze off")
  elseif n == 3 then if spage == 3 then pluck() else ping() end end
end

local function header(title, right)
  screen.level(15); screen.move(0, 7); screen.text(title)
  local flags = (frozen and "FRZ " or "") .. (reversed and "REV" or "")
  if flags ~= "" then screen.level(15); screen.move(127, 7); screen.text_right(flags)
  elseif right then screen.level(6); screen.move(127, 7); screen.text_right(right) end
  if morph_progress then screen.level(10); screen.rect(0, 9, 128 * morph_progress, 1); screen.fill()
  else screen.level(2); screen.move(0, 9.5); screen.line(128, 9.5); screen.stroke() end
end

local function draw_list(list, s, y0, rows)
  local first = util.clamp(s - math.floor(rows / 2), 1, math.max(1, #list - rows + 1))
  for r = 0, rows - 1 do
    local id = list[first + r]
    if not id then break end
    local y = y0 + r * 8
    screen.level(first + r == s and 15 or 4); screen.move(0, y); screen.text(SHORT[id] or id)
    screen.move(127, y); screen.text_right(pstr(id))
  end
end

local function draw_taps()
  header("TAPS " .. TAP_PARAM_NAMES[tap_param]:lower(), params:get("sync") == 1 and string.format("%d bpm", math.floor(clock.get_tempo() + 0.5)) or string.format("%d ms", math.floor(beat_sec() * 1000)))
  local mx = 0
  for i = 1, NT do mx = math.max(mx, tap_t[i]) end
  mx = math.max(mx, 0.001)
  local fbs = params:get("fb_tap")
  local t = now() - onset_t
  for i = 1, NT do
    local x = 3 + math.floor(tap_t[i] / mx * 120 + 0.5)
    local muted = params:get(tid(i, "mute")) == 2
    local h = muted and 1 or math.floor(params:get(tid(i, "level")) / 15 * 24 + 0.5)
    local lit = (t >= tap_t[i] and t < tap_t[i] + 0.09)
    screen.level(i == sel_tap and 15 or (lit and 12 or (muted and 2 or 6)))
    screen.rect(x, 40 - h, 1, math.max(1, h)); screen.fill()
    screen.level(4); screen.pixel(x + math.floor(params:get(tid(i, "pan")) / 7 * 2 + 0.5), 40 - h - 3); screen.fill()
    if fbs == i then screen.level(10); screen.rect(x - 1, 42, 3, 1); screen.fill() end
  end
  screen.level(2); screen.move(0, 41.5); screen.line(128, 41.5); screen.stroke()
  screen.level(15); screen.move(0, 52); screen.text("tap " .. sel_tap)
  screen.level(8); screen.move(127, 52)
  screen.text_right("lvl " .. params:get(tid(sel_tap, "level")) .. "  pan " .. params:get(tid(sel_tap, "pan")))
  screen.level(6); screen.move(0, 61)
  local ft = params:get(tid(sel_tap, "ftype"))
  screen.text(ft == 1 and "no filter" or (({"", "LP", "BP", "HP"})[ft] .. " " .. pstr(tid(sel_tap, "cut")) .. " q" .. params:get(tid(sel_tap, "q"))))
  local p = params:get(tid(sel_tap, "pitch"))
  screen.move(127, 61); screen.text_right((p > 0 and "+" or "") .. p .. " st")
end

local function draw_comb()
  if params:get("size_src") == 2 then header("COMB", string.format("delay %.1f Hz", 1 / math.max(comb_size(), 0.0005)))
  else header("COMB", note_name(params:get("comb_note")) .. string.format(" %.1f Hz", musicutil_note_hz(params:get("comb_note")))) end
  local f = COMBPAT[params:get("comb_pattern")][2]
  local sl = SLOPES[params:get("comb_slope")]
  local d = params:get("comb_density")
  for k = 1, 64 do
    local x = 2 + math.floor(f(k) * 123 + 0.5)
    local h = math.floor(sl(k / 64) * 14 + 0.5)
    screen.level(k == 64 and 15 or (k > 64 - d and 7 or 1))
    screen.rect(x, 27 - h, 1, h); screen.fill()
  end
  draw_list(LISTS[3], ssel[3], 37, 4)
end

local function draw_mix()
  header("MIX", ROUTINGS[params:get("routing")])
  local m = {{"in", polls.in_db}, {"dly", polls.dly_db}, {"cmb", polls.cmb_db}, {"out", polls.out_db}}
  for i, v in ipairs(m) do
    local x = 2 + (i - 1) * 9
    local h = math.floor(util.clamp((v[2] + 60) / 60, 0, 1) * 22 + 0.5)
    screen.level(2); screen.rect(x, 13, 5, 22); screen.fill()
    screen.level(12); screen.rect(x, 35 - h, 5, h); screen.fill()
  end
  screen.level(4); screen.move(40, 20); screen.text("in dly cmb out")
  screen.move(40, 30); screen.level(8); screen.text(SOURCES[params:get("source")])
  draw_list(LISTS[4], ssel[4], 45, 3)
end

function redraw()
  screen.clear()
  screen.font_face(1); screen.font_size(8)
  if spage == 1 then draw_taps()
  elseif spage == 2 then
    header("RHYTHM", params:get("sync") == 1 and ("sync " .. BEAT_NAMES[params:get("beat")]) or "free")
    draw_list(LISTS[2], ssel[2], 19, 6)
  elseif spage == 3 then draw_comb()
  else draw_mix() end
  if message and now() - message_t < 1.3 then
    screen.level(0); screen.rect(10, 22, 108, 15); screen.fill()
    screen.level(15); screen.rect(10.5, 22.5, 107, 14); screen.stroke()
    screen.move(64, 32); screen.text_center(message)
  end
  screen.update()
end

---------------------------------------------------------------------------
-- init
---------------------------------------------------------------------------
function init()
  first_param = params.count + 1     -- presets only hold the script's own params, not the system ones
  add_params()
  build_preset_ids()
  params:bang()
  factory_presets()
  load_presets()
  engine.demo(_path.code .. "monsun/audio/monsun-demo.wav")
  send_comb(); send_times()
  for i = 1, NT do send_tap(i) end
  engine.grain(GRAINS[params:get("grain")])

  for _, name in ipairs({"in_db", "dly_db", "cmb_db", "out_db"}) do
    local p = poll.set(name, function(v)
      polls[name] = v
      if name == "in_db" then
        -- onset: a jump of 6 dB over a peak-held envelope (instant attack, ~45 dB/s release),
        -- so a decaying sound never re-triggers; the taps flash relative to it
        if v > -45 and v > last_in + 6 and now() - onset_t > 0.08 then onset_t = now() end
        last_in = math.max(v, last_in - 1.5)
      end
    end)
    if p then p.time = 1 / 30; p:start() end
  end
  clock.tempo_change_handler = function() dirty_times = true end

  clock.run(function()
    while true do
      clock.sleep(1 / 30)
      if not suspend then
        if dirty_times then dirty_times = false; send_times() end
        if dirty_comb then dirty_comb = false; send_comb() end
      end
      redraw(); grid_redraw(); arc_redraw()
    end
  end)
  recall_factory_default()
end

function recall_factory_default()
  -- start on the first factory preset, without morphing
  set_many(preset(1)); current_preset = 1
  msg("monsun")
end

function cleanup()
  save_presets()
end
