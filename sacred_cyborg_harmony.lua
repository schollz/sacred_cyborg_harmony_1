music = require 'musicutil'
include('lib/passencorn')

engine.name = "TheMachine"
SCALE_NAMES = {}
for i, v in pairs(music.SCALES) do
  SCALE_NAMES[i] = v["name"]
end

scale = nil
scaleSet = {}
activePitchClasses = {}
sungNote = nil

function set_scale()
  scale = music.generate_scale(params:get("root") - 12, scale_name(), 10)
  scaleSet = {}
  for i, note in ipairs(scale) do
    scaleSet[note % 12] = true
  end
end

function scale_name()
  return SCALE_NAMES[params:get("scale")]
end



function redraw()
  screen.clear()
  local x, y
  for i=0,11,1 do
    if scaleSet[i] ~= nil then
      screen.level(15)
    else
      screen.level(0)
    end
    x = 64 - 35*math.sin(2 * math.pi * (i/12))
    y = 32 + 25*math.cos(2 * math.pi * (i/12))
    screen.circle(x, y, 2)
    screen.fill()
    if sungNote ~= nil and sungNote % 12 == i then
      screen.move(64, 32)
      screen.line(x, y)
      screen.stroke()
    end
  end
  screen.level(8)
  local count = 0
  for i=0,11,1 do
    if activePitchClasses[i] == true then
      x = 64 - 35*math.sin(2 * math.pi * (i/12))
      y = 32 + 25*math.cos(2 * math.pi * (i/12))
      if count == 0 then
        screen.move(x, y)
      else
        screen.line(x, y)
      end
      count = count + 1
    end
  end
  if count > 1 then
    screen.close()
    screen.stroke()
  elseif count == 1 then
    screen.circle(x, y, 6)
    screen.stroke()
  end
  if unquantizedSungNote ~= nil then
    local i = unquantizedSungNote % 12
    local x = 64 - 10*math.sin(2 * math.pi * (i/12))
    local y = 32 + 7*math.cos(2 * math.pi * (i/12))
    screen.level(8)
    screen.move(64, 32)
    screen.line(x, y)
    screen.stroke()
  end
  screen.update()
end

function init()
  osc.event = osc_in
  screen_redraw_clock = clock.run(
    function()
      while true do
        clock.sleep(1/15) 
        if screen_dirty == true then
          redraw()
          screen_dirty = false
        end
      end
    end
  )
  params:add_separator("lead cyborg")
  params:add_number("root","root",24,35,24, 
    function(param) return music.note_num_to_name(param:get()) end,
    true
    )
  params:set_action("root", set_scale)
  params:add_option("scale", "scale", SCALE_NAMES, 1)
  params:set_action("scale", set_scale)
  local pull_spec = controlspec.UNIPOLAR:copy()
  pull_spec.default = 1
  params:add_control("pull", "quantize amount", pull_spec)
  local amp_spec = controlspec.AMP:copy()
  amp_spec.default = 1  
  params:add_control("lead amp", "lead amp", amp_spec)
  
  params:add_separator("cyborg chorus")
  local my_delay = controlspec.DELAY:copy()
  my_delay.default = 0.02
  params:add_control("delay", "max random delay", my_delay)
  params:add_control("vibrato", "vibrato amount", controlspec.UNIPOLAR)
  params:add_control("vibrato speed", "vibrato speed", controlspec.LOFREQ)
  params:add_control("chorus amp", "chorus amp", amp_spec)
  
  midi_device = {} -- container for connected midi devices
  midi_device_names = {}
  target = 1

  for i = 1,#midi.vports do -- query all ports
    midi_device[i] = midi.connect(i) -- connect each device
    local full_name = 
    table.insert(midi_device_names,"port "..i..": "..util.trim_string_to_width(midi_device[i].name,40)) -- register its name
  end
  
  
  params:add_separator("midi")
  params:add_option("midi target", "midi target",midi_device_names,1)
  params:set_action("midi target", midi_target)

  params:bang()
end

active_notes = {}

function midi_target(x)
  midi_device[target].event = nil
  target = x
  midi_device[target].event = process_midi
end

function process_midi(data)
  local d = midi.to_msg(data)
  if d.type == "note_on" then
    -- global
    note = d.note
    active_notes[d.note] = true
    activePitchClasses[d.note % 12] = true
    engine.noteOn(music.note_num_to_freq(d.note), params:get("chorus amp")*d.vel/127, math.random()*params:get("delay"), params:get("vibrato"), params:get("vibrato speed"), d.note)
    screen_dirty = true
    -- print("on", d.note)
  elseif d.type == "note_off" then
    active_notes[d.note] = false
    activePitchClasses[d.note % 12] = nil
    engine.noteOff(d.note)
    screen_dirty = true
    -- print("off", d.note)
  -- elseif d.type == "pitchbend" then
  --   local bend_st = (util.round(d.val / 2)) / 8192 * 2 -1 -- Convert to -1 to 1
  --   set_pitch_bend(d.ch, bend_st * params:get("bend_range"))
  end
end

function osc_in(path, args, from)

  if path == "/measuredPitch" then
    local pitch = args[1]
    unquantizedSungNote = freq_to_note_num_float(pitch)
    screen_dirty = true
    if scale == nil then
      return
    end
    -- Introduce a little bit of hysteresis if we're near
    if scale ~= nil then
      local newNote = quantize(scale, pitch, sungNote)
      if sungNote ~= newNote then
        sungNote = newNote
        engine.acceptQuantizedPitch(music.note_num_to_freq(sungNote), params:get("pull"), params:get("lead amp"))
      end
    end
  end
end
