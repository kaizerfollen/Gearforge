#!/usr/bin/env python3
"""Load Factorio 1.1 base prototype data (Lua) via lupa and dump data.raw to JSON (graphics/sound stripped)."""
import sys, json
import lupa.lua52 as L  # Factorio uses Lua 5.2

ROOT = sys.argv[1]  # path to factorio-data checkout
OUT = sys.argv[2]

lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
ROOT = ...
''') if False else None
g = lua.globals()
g.FROOT = ROOT

lua.execute(r'''
local ROOT = FROOT
local mod_stack = {"core"}
local function try(path)
  local f = io.open(path, "r")
  if f then f:close(); return path end
end
local function resolve(name)
  local modname, rest = name:match("^__(%w+)__/(.*)$")
  local mod = modname or mod_stack[#mod_stack]
  rest = rest or name
  rest = rest:gsub("%.lua$", "")
  local cands = {}
  local dotted = rest:gsub("%.", "/")
  for _, r in ipairs({rest, dotted}) do
    table.insert(cands, ROOT .. "/" .. mod .. "/" .. r .. ".lua")
    table.insert(cands, ROOT .. "/core/lualib/" .. r .. ".lua")
    table.insert(cands, ROOT .. "/" .. mod .. "/lualib/" .. r .. ".lua")
  end
  for _, c in ipairs(cands) do if try(c) then return c, mod end end
  return nil
end
local loaded = {}
function require(name)
  local path, mod = resolve(name)
  if not path then if name:find("menu%-simulations") then return {} end error("cannot resolve " .. name) end
  if loaded[path] ~= nil then return loaded[path] end
  local chunk = assert(loadfile(path))
  table.insert(mod_stack, mod)
  local r = chunk()
  table.remove(mod_stack)
  if r == nil then r = true end
  loaded[path] = r
  return r
end
function set_mod(m) mod_stack = {m} end

local function auto() return setmetatable({}, {__index = function(t,k) local v = auto(); rawset(t,k,v); return v end}) end
defines = auto()
defines.direction = {north=0, northeast=1, east=2, southeast=3, south=4, southwest=5, west=6, northwest=7}
log = function() end
localised_print = function() end
table_size = function(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
mods = {base = "1.1.110", core = "1.1.110"}
settings = {startup = {}}
feature_flags = {}
serpent = {block = function() return "" end, line = function() return "" end}
''')
g.set_mod("core")
lua.execute('require("dataloader")')
g.set_mod("core")
lua.execute('require("data")')
g.set_mod("base")
lua.execute('require("data")')
g.set_mod("base")
lua.execute('require("data-updates")')

SKIP_KEYS = {
    'icon','icons','icon_size','icon_mipmaps','pictures','picture','animation','animations','sprite','sprites',
    'working_sound','sound','sounds','open_sound','close_sound','vehicle_impact_sound','mined_sound','build_sound',
    'graphics_set','idle_animation','working_visualisations','integration_patch','water_reflection','corpse',
    'dying_explosion','damaged_trigger_effect','circuit_wire_connection_points','circuit_connector_sprites',
    'circuit_wire_connection_point','belt_animation_set','structure','structure_patch','horizontal_animation',
    'vertical_animation','platform_picture','base_picture','shadow','light','connection_sprites','heat_glow_sprites',
    'wire_shadow_picture','radius_visualisation_picture','overlay','flash','recharging_animation','in_motion',
    'folded_animation','preparing_animation','prepared_animation','attacking_animation','ending_attack_animation',
    'folding_animation','energy_glow_animation','glow_light_intensity','pipe_covers','pipe_picture','heat_pipe_covers',
    'connection_patches_connected','connection_patches_disconnected','heat_connection_patches_connected',
    'heat_connection_patches_disconnected','picture_off','picture_on','fluid_box_pictures','fire_pictures',
    'smoke','stream','shadow_animations','run_animation','attack_parameters_graphics','cannon_base_pictures',
    'cannon_barrel_pictures','base_picture_secondary_draw_order','animation_shadow','charge_animation',
    'discharge_animation','arm_01_back_animation','arm_02_right_animation','door_back_sprite','door_front_sprite',
    'hole_sprite','hole_light_sprite','rocket_shadow_overlay_sprite','rocket_glow_overlay_sprite','satellite_animation',
    'shadow_sprite','base_day_sprite','base_front_sprite','red_lights_back_sprites','red_lights_front_sprites',
    'base_light','base_engine_light','door_back_open_offset','frozen_patch','top_animations','tip','pictures_on',
    'pictures_off','frozen_patch','stateless_visualisation','visualisation','heat_buffer_glow','lower_layer_picture',
    'patch','sound_minimum_speed','idle_sound','charge_sound','discharge_sound','resource_patch_search_radius_dummy',
    'wet_mining_graphics_set','input_fluid_patch_shadow_sprites','output_fluid_patch_shadow_sprites',
    'starved_sound','moving_sound','attack_target_mask_dummy','connection_patches','fluid_animation',
    'gas_flow','window_background','water_reflection','layers','filename','hr_version','stripes','damaged_trigger_effect',
    'repair_sound','drawing_box','fast_replaceable_group_dummy','alert_icon_shift','smoke_dummy','pumpjack_dummy',
    'animation_speed_coefficient', 'emissions_dummy', 'effect_animation_period_dummy', 'trigger_target_mask_dummy',
    'shooting_cursor_size','variants','transitions','transitions_between_transitions','walking_sound','build_sound','effect_color','effect_color_secondary','trigger_effect','autoplace', 'minimap_representation', 'selected_minimap_representation', 'rocket_parts_dummy',
}

def conv(v, depth=0):
    if depth > 12:
        return None
    if L.lua_type(v) == 'table':
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys)+1)):
            return [conv(v[k], depth+1) for k in sorted(keys)]
        d = {}
        for k in keys:
            if isinstance(k, str) and k in SKIP_KEYS:
                continue
            d[str(k)] = conv(v[k], depth+1)
        return d
    if L.lua_type(v) == 'function':
        return '<function>'
    return v

import lupa
raw = g.data.raw
out = {}
for t in raw.keys():
    if t in ('font','gui-style','noise-expression','noise-layer','utility-sprites','utility-sounds','sprite','sound',
             'ambient-sound','optimized-decorative','optimized-particle','tile-effect','tips-and-tricks-item',
             'tips-and-tricks-item-category','tutorial','explosion','particle-source','corpse','smoke-with-trigger',
             'trivial-smoke','mouse-cursor','custom-input','achievement','build-entity-achievement',
             'construct-with-robots-achievement','deconstruct-with-robots-achievement','deliver-by-robots-achievement',
             'dont-build-entity-achievement','dont-craft-manually-achievement','dont-use-entity-in-energy-production-achievement',
             'finish-the-game-achievement','group-attack-achievement','kill-achievement','player-damaged-achievement',
             'produce-achievement','produce-per-hour-achievement','research-achievement','train-path-achievement',
             'decorative','utility-constants','map-gen-presets','editor-controller','god-controller','spectator-controller'):
        continue
    out[t] = {}
    for n in raw[t].keys():
        out[t][n] = conv(raw[t][n])
with open(OUT, 'w') as f:
    json.dump(out, f, indent=1, default=str)
print('types:', len(out), 'protos:', sum(len(v) for v in out.values()))
