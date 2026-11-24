--[[
  CHAOS CAM - script OBS (Lua)
  Fait subir des effets absurdes à ta webcam :
   - effets "mouvement" (séisme, toupie, rebond DVD...)
   - effets "photomaton" façon Photo Booth (renflement, tourbillon, thermique...)
  Déclenchables par raccourci, en mode auto, ou par les viewers via le chat Twitch.

  Installation : OBS > Outils > Scripts > "+" > choisir ce fichier.
]]

obs = obslua

------------------------------------------------------------
-- Configuration
------------------------------------------------------------
local cfg = {
    source_name   = "",
    sound_name    = "",
    text_name     = "",
    duration      = 4.0,
    auto          = false,
    auto_min      = 60,
    auto_max      = 180,
    only_live     = true,
    twitch        = false,
    channel       = "",
    who           = "all",
    cooldown      = 15,
    user_cooldown = 60,
    enabled       = {},
}

local state = nil          -- effet en cours (nil = aucun)
local next_auto = 60
local hotkeys = {}

local FILTER_ID   = "chaos_cam_fx"
local FILTER_NAME = "Chaos Cam FX"

-- état partagé avec le filtre shader
local fx = { mode = 0, amount = 0, time = 0 }

------------------------------------------------------------
-- Petits outils
------------------------------------------------------------
local function rand(a, b) return a + math.random() * (b - a) end
local function now() return obs.os_gettime_ns() / 1e9 end

local function smooth(x)
    if x < 0 then x = 0 elseif x > 1 then x = 1 end
    return x * x * (3 - 2 * x)
end

local function env(p)
    local r = 0.15
    if p < r then return smooth(p / r) end
    if p > 1 - r then return smooth((1 - p) / r) end
    return 1
end

local function ease_in_out(p)
    if p < 0.5 then return 2 * p * p end
    return 1 - ((-2 * p + 2) ^ 2) / 2
end

local function log(msg) obs.script_log(obs.LOG_INFO, "[Chaos Cam] " .. msg) end

------------------------------------------------------------
-- Shader "photomaton"
------------------------------------------------------------
local SHADER = [==[
uniform float4x4 ViewProj;
uniform texture2d image;
uniform int mode;
uniform float amount;
uniform float elapsed;
uniform float aspect;
uniform float2 texel;

sampler_state def_sampler {
    Filter   = Linear;
    AddressU = Clamp;
    AddressV = Clamp;
};

struct VertData {
    float4 pos : POSITION;
    float2 uv  : TEXCOORD0;
};

VertData VSDefault(VertData v_in)
{
    VertData vert_out;
    vert_out.pos = mul(float4(v_in.pos.xyz, 1.0), ViewProj);
    vert_out.uv  = v_in.uv;
    return vert_out;
}

float4 px(float2 uv) { return image.Sample(def_sampler, uv); }
float2 to_p(float2 uv) { return (uv - 0.5) * float2(aspect, 1.0); }
float2 from_p(float2 p) { return p / float2(aspect, 1.0) + 0.5; }
float luma(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }

float2 radial(float2 uv, float power)
{
    float2 p = to_p(uv);
    float r = length(p);
    float R = 0.5;
    if (r < R && r > 0.0001) {
        float k = r / R;
        p = p * (R * pow(k, power) / r);
    }
    return from_p(p);
}

float2 twirl(float2 uv)
{
    float2 p = to_p(uv);
    float r = length(p);
    float R = 0.55;
    if (r < R) {
        float k = 1.0 - r / R;
        float ang = amount * 5.0 * k * k;
        float s = sin(ang);
        float c = cos(ang);
        p = float2(p.x * c - p.y * s, p.x * s + p.y * c);
    }
    return from_p(p);
}

float edge(float2 uv)
{
    float2 dx = float2(texel.x * 2.0, 0.0);
    float2 dy = float2(0.0, texel.y * 2.0);
    float gx = luma(px(uv + dx).rgb) - luma(px(uv - dx).rgb);
    float gy = luma(px(uv + dy).rgb) - luma(px(uv - dy).rgb);
    return length(float2(gx, gy));
}

float3 thermal(float t)
{
    float3 c1 = float3(0.0, 0.0, 0.4);
    float3 c2 = float3(0.6, 0.0, 0.8);
    float3 c3 = float3(1.0, 0.1, 0.0);
    float3 c4 = float3(1.0, 0.9, 0.0);
    float3 c5 = float3(1.0, 1.0, 1.0);
    if (t < 0.25) return lerp(c1, c2, t * 4.0);
    if (t < 0.5)  return lerp(c2, c3, (t - 0.25) * 4.0);
    if (t < 0.75) return lerp(c3, c4, (t - 0.5) * 4.0);
    return lerp(c4, c5, (t - 0.75) * 4.0);
}

float4 PSChaos(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float4 orig = px(uv);
    float a = amount;

    /* ---- déformations ---- */
    if (mode == 1) return px(radial(uv, 1.0 + 1.3 * a));          /* renflement */
    if (mode == 2) return px(radial(uv, 1.0 / (1.0 + 1.3 * a)));  /* creux */
    if (mode == 3) return px(twirl(uv));                           /* tourbillon */
    if (mode == 4) {                                               /* compression */
        float2 p = to_p(uv);
        p.x = p.x * (1.0 + 1.8 * a * exp(-p.x * p.x / 0.08));
        return px(from_p(p));
    }
    if (mode == 5) {                                               /* étirement */
        float2 p = to_p(uv);
        p.y = p.y / (1.0 + 1.5 * a * exp(-p.y * p.y / 0.06));
        return px(from_p(p));
    }
    if (mode == 6) {                                               /* jumeau */
        float2 m = uv;
        if (m.x > 0.5) m.x = 1.0 - m.x;
        return lerp(orig, px(m), a);
    }
    if (mode == 7) {                                               /* tunnel de lumière */
        float2 p = to_p(uv);
        float r = length(p);
        float R = lerp(0.9, 0.22, a);
        if (r > R) p = p * (R / r);
        return px(from_p(p));
    }
    if (mode == 8) {                                               /* fish-eye */
        float2 p = to_p(uv);
        float r = length(p);
        float f = lerp(1.0, 0.35 + 2.6 * r * r, a);
        float4 c = px(from_p(p * f));
        float mask = 1.0 - smoothstep(0.47, 0.5, r);
        c.rgb = c.rgb * lerp(1.0, mask, a);
        return c;
    }
    if (mode == 9) {                                               /* kaléidoscope */
        float2 p = to_p(uv);
        float r = length(p);
        float seg = 6.2831853 / 6.0;
        float ang = atan2(p.y, p.x) + elapsed * 0.5;
        ang = ang - seg * floor(ang / seg);
        ang = abs(ang - seg * 0.5);
        float4 k = px(from_p(float2(cos(ang), sin(ang)) * r));
        return lerp(orig, k, a);
    }

    if (mode == 15) {                                              /* donjon bdsm */
        /* coup de fouet ~ toutes les 1.25 s : secousse + flash rouge */
        float crack = exp(-frac(elapsed * 0.8) * 8.0);
        float2 suv = uv + float2(sin(elapsed * 90.0), cos(elapsed * 77.0)) * 0.015 * crack * a;
        float4 c = px(suv);
        float cl = luma(c.rgb);
        /* look cuir / latex : noir brillant et rouge */
        float3 latex = lerp(float3(0.05, 0.0, 0.02), float3(0.75, 0.0, 0.08), smoothstep(0.15, 0.7, cl));
        latex = latex + pow(saturate(cl), 6.0) * 0.9;
        latex = latex + float3(0.5, 0.0, 0.0) * crack * 0.6;
        float2 vp = to_p(uv);
        latex = latex * (1.0 - smoothstep(0.35, 0.85, length(vp)));
        /* barreaux de cachot */
        float bx = frac(uv.x * 7.0);
        float bar = smoothstep(0.42, 0.45, bx) - smoothstep(0.55, 0.58, bx);
        float3 metal = float3(0.25, 0.25, 0.28) + saturate(1.0 - abs(bx - 0.5) * 8.0) * 0.5;
        latex = lerp(latex, metal, bar);
        /* bandeau "censuré" sur les yeux */
        float band = step(abs(uv.y - 0.38), 0.06) * step(abs(uv.x - 0.5), 0.22);
        latex = lerp(latex, float3(0.0, 0.0, 0.0), band);
        return float4(lerp(c.rgb, latex, a), c.a);
    }

    /* ---- couleurs ---- */
    float3 col = orig.rgb;
    float l = luma(orig.rgb);

    if (mode == 10) {                                              /* thermique */
        col = thermal(saturate(l * 1.1));
    } else if (mode == 11) {                                       /* rayons X */
        float v = pow(saturate(1.0 - l), 1.4);
        col = float3(0.75, 0.9, 1.0) * v;
    } else if (mode == 12) {                                       /* BD */
        float3 q = floor(orig.rgb * 4.0 + 0.5) / 4.0;
        float ql = luma(q);
        q = saturate(lerp(float3(ql, ql, ql), q, 1.7));
        float2 cell = frac(uv / (texel * 7.0)) - 0.5;
        float dots = step(length(cell), (1.0 - l) * 0.6);
        q = q * (1.0 - 0.35 * dots);
        col = lerp(q, float3(0.0, 0.0, 0.0), smoothstep(0.08, 0.2, edge(uv)));
    } else if (mode == 13) {                                       /* pop art */
        float2 cellp = floor(uv * 2.0);
        float pl = luma(px(frac(uv * 2.0)).rgb);
        float idx = cellp.x + cellp.y * 2.0;
        float3 dark  = float3(0.4, 0.0, 0.6);
        float3 light = float3(1.0, 0.5, 0.7);
        if (idx < 0.5)      { dark = float3(0.9, 0.1, 0.5); light = float3(1.0, 0.9, 0.1); }
        else if (idx < 1.5) { dark = float3(0.1, 0.2, 0.8); light = float3(0.3, 1.0, 0.6); }
        else if (idx < 2.5) { dark = float3(0.9, 0.4, 0.0); light = float3(0.4, 0.8, 1.0); }
        col = lerp(dark, light, smoothstep(0.35, 0.55, pl));
    } else if (mode == 14) {                                       /* croquis */
        float v = 1.0 - 0.9 * smoothstep(0.03, 0.25, edge(uv));
        v = v * lerp(0.85, 1.0, l);
        col = float3(v, v * 0.98, v * 0.93);
    }

    return float4(lerp(orig.rgb, col, a), orig.a);
}

technique Draw
{
    pass
    {
        vertex_shader = VSDefault(v_in);
        pixel_shader  = PSChaos(v_in);
    }
}
]==]

local filter_def = {}
filter_def.id = FILTER_ID
filter_def.type = obs.OBS_SOURCE_TYPE_FILTER
filter_def.output_flags = obs.OBS_SOURCE_VIDEO

filter_def.get_name = function() return FILTER_NAME end

filter_def.create = function(settings, source)
    local d = { source = source }
    obs.obs_enter_graphics()
    d.effect = obs.gs_effect_create(SHADER, "chaos_cam_fx.effect", nil)
    obs.obs_leave_graphics()
    if d.effect == nil then
        log("Le shader n'a pas compilé : les effets photomaton seront ignorés.")
        return d
    end
    d.p_mode   = obs.gs_effect_get_param_by_name(d.effect, "mode")
    d.p_amount = obs.gs_effect_get_param_by_name(d.effect, "amount")
    d.p_time   = obs.gs_effect_get_param_by_name(d.effect, "elapsed")
    d.p_aspect = obs.gs_effect_get_param_by_name(d.effect, "aspect")
    d.p_texel  = obs.gs_effect_get_param_by_name(d.effect, "texel")
    return d
end

filter_def.destroy = function(d)
    if d and d.effect then
        obs.obs_enter_graphics()
        obs.gs_effect_destroy(d.effect)
        obs.obs_leave_graphics()
    end
end

local function target_size(d)
    local t = obs.obs_filter_get_target(d.source)
    if t == nil then return 0, 0 end
    return obs.obs_source_get_base_width(t), obs.obs_source_get_base_height(t)
end

filter_def.get_width  = function(d) local w = target_size(d); return w end
filter_def.get_height = function(d) local _, h = target_size(d); return h end

filter_def.video_render = function(d, effect)
    local w, h = target_size(d)
    if d.effect == nil or fx.mode == 0 or w == 0 or h == 0 then
        obs.obs_source_skip_video_filter(d.source)
        return
    end
    if not obs.obs_source_process_filter_begin(d.source, obs.GS_RGBA, obs.OBS_NO_DIRECT_RENDERING) then
        return
    end
    obs.gs_effect_set_int(d.p_mode, fx.mode)
    obs.gs_effect_set_float(d.p_amount, fx.amount)
    obs.gs_effect_set_float(d.p_time, fx.time)
    obs.gs_effect_set_float(d.p_aspect, w / h)
    local tx = obs.vec2(); tx.x = 1 / w; tx.y = 1 / h
    obs.gs_effect_set_vec2(d.p_texel, tx)
    obs.obs_source_process_filter_end(d.source, d.effect, w, h)
end

obs.obs_register_source(filter_def)

------------------------------------------------------------
-- Les effets
--  mouvement : fn(ctx, t, p, dt) -> dx, dy, drot, fx, fy
--  photomaton : shader = numéro du mode
------------------------------------------------------------
local EFFECTS = {
    -- Mouvement
    { id = "seisme", cmd = "seisme", name = "Séisme", fn = function(ctx, t, p)
        local e = env(p)
        local a = 45 * e
        return rand(-a, a), rand(-a, a), rand(-6, 6) * e, 1, 1
    end },
    { id = "toupie", cmd = "toupie", name = "Toupie", fn = function(ctx, t, p)
        return 0, 0, 720 * ease_in_out(p), 1, 1
    end },
    { id = "tete_en_bas", cmd = "envers", name = "Tête en bas", fn = function(ctx, t, p)
        return 0, 0, 180 * env(p), 1, 1
    end },
    { id = "grosse_tete", cmd = "grossetete", name = "Grosse tête", fn = function(ctx, t, p)
        local f = 1 + 1.6 * env(p)
        return 0, 0, 0, f, f
    end },
    { id = "mini_moi", cmd = "mini", name = "Mini-moi", fn = function(ctx, t, p)
        local f = 1 - 0.85 * env(p)
        return 0, math.sin(t * 10) * 8 * env(p), 0, f, f
    end },
    { id = "miroir", cmd = "miroirfou", name = "Miroir fou", fn = function(ctx, t, p)
        local flip = (math.floor(t * 4) % 2 == 0) and -1 or 1
        if p > 0.9 then flip = 1 end
        return 0, 0, 0, flip, 1
    end },
    { id = "gelee", cmd = "gelee", name = "Gelée", fn = function(ctx, t, p)
        local w = math.sin(t * 14) * 0.3 * env(p)
        return 0, 0, math.sin(t * 7) * 4 * env(p), 1 + w, 1 - w
    end },
    { id = "dvd", cmd = "dvd", name = "Rebond DVD", fn = function(ctx, t, p, dt)
        local e = env(p)
        local s = 1 - 0.5 * e
        local hw, hh = ctx.hw * s, ctx.hh * s
        if not ctx.x then
            ctx.x, ctx.y = ctx.cx, ctx.cy
            ctx.vx = (math.random() < 0.5 and -1 or 1) * 450
            ctx.vy = (math.random() < 0.5 and -1 or 1) * 350
        end
        ctx.x = ctx.x + ctx.vx * dt
        ctx.y = ctx.y + ctx.vy * dt
        if 2 * hw < ctx.W then
            if ctx.x - hw < 0 then ctx.x = hw; ctx.vx = math.abs(ctx.vx) end
            if ctx.x + hw > ctx.W then ctx.x = ctx.W - hw; ctx.vx = -math.abs(ctx.vx) end
        end
        if 2 * hh < ctx.H then
            if ctx.y - hh < 0 then ctx.y = hh; ctx.vy = math.abs(ctx.vy) end
            if ctx.y + hh > ctx.H then ctx.y = ctx.H - hh; ctx.vy = -math.abs(ctx.vy) end
        end
        return (ctx.x - ctx.cx) * e, (ctx.y - ctx.cy) * e, 0, s, s
    end },
    { id = "machine_a_laver", cmd = "laver", name = "Machine à laver", fn = function(ctx, t, p)
        local e = env(p)
        local a = 20 * e
        return rand(-a, a), rand(-a, a), 1440 * ease_in_out(p), 1, 1
    end },

    -- Photomaton
    { id = "bulle",      cmd = "bulle",      name = "Renflement",        shader = 1 },
    { id = "creux",      cmd = "creux",      name = "Creux",             shader = 2 },
    { id = "tourbillon", cmd = "tourbillon", name = "Tourbillon",        shader = 3 },
    { id = "compresse",  cmd = "compresse",  name = "Compression",       shader = 4 },
    { id = "etire",      cmd = "etire",      name = "Étirement",         shader = 5 },
    { id = "jumeau",     cmd = "jumeau",     name = "Jumeau (miroir)",   shader = 6 },
    { id = "tunnel",     cmd = "tunnel",     name = "Tunnel de lumière", shader = 7 },
    { id = "fisheye",    cmd = "fisheye",    name = "Fish-eye",          shader = 8 },
    { id = "kaleido",    cmd = "kaleido",    name = "Kaléidoscope",      shader = 9 },
    { id = "thermique",  cmd = "thermique",  name = "Caméra thermique",  shader = 10 },
    { id = "rayonx",     cmd = "rayonx",     name = "Rayons X",          shader = 11 },
    { id = "bd",         cmd = "bd",         name = "BD",                shader = 12 },
    { id = "popart",     cmd = "popart",     name = "Pop Art",           shader = 13 },
    { id = "croquis",    cmd = "croquis",    name = "Croquis",           shader = 14 },
    { id = "bdsm",       cmd = "bdsm",       name = "Donjon BDSM",       shader = 15, off_by_default = true },
}

local CMD_MAP = {}
for _, e in ipairs(EFFECTS) do CMD_MAP[e.cmd] = e end

------------------------------------------------------------
-- Moteur
------------------------------------------------------------
local function vec2(x, y)
    local v = obs.vec2(); v.x = x; v.y = y; return v
end

local function set_text(str)
    if cfg.text_name == "" then return end
    local src = obs.obs_get_source_by_name(cfg.text_name)
    if src then
        local d = obs.obs_data_create()
        obs.obs_data_set_string(d, "text", str)
        obs.obs_source_update(src, d)
        obs.obs_data_release(d)
        obs.obs_source_release(src)
    end
end

local function play_sound()
    if cfg.sound_name == "" then return end
    local src = obs.obs_get_source_by_name(cfg.sound_name)
    if src then
        obs.obs_source_media_restart(src)
        obs.obs_source_release(src)
    end
end

local function ensure_filter(src)
    local f = obs.obs_source_get_filter_by_name(src, FILTER_NAME)
    if f then
        obs.obs_source_release(f)
        return
    end
    f = obs.obs_source_create_private(FILTER_ID, FILTER_NAME, nil)
    if f then
        obs.obs_source_filter_add(src, f)
        obs.obs_source_release(f)
    end
end

local function apply(dx, dy, drot, fx_, fy_)
    local it, o = state.item, state.orig
    obs.obs_sceneitem_defer_update_begin(it)
    obs.obs_sceneitem_set_pos(it, vec2(state.ctx.cx + dx, state.ctx.cy + dy))
    obs.obs_sceneitem_set_rot(it, o.rot + drot)
    if o.bounds_type == obs.OBS_BOUNDS_NONE then
        obs.obs_sceneitem_set_scale(it, vec2(o.scale.x * fx_, o.scale.y * fy_))
    else
        obs.obs_sceneitem_set_bounds(it, vec2(o.bounds.x * math.abs(fx_), o.bounds.y * math.abs(fy_)))
        obs.obs_sceneitem_set_scale(it, vec2(o.scale.x * (fx_ < 0 and -1 or 1),
                                             o.scale.y * (fy_ < 0 and -1 or 1)))
    end
    obs.obs_sceneitem_defer_update_end(it)
end

local function finish()
    if not state then return end
    if state.kind == "shader" then
        fx.mode, fx.amount, fx.time = 0, 0, 0
    else
        local it, o = state.item, state.orig
        obs.obs_sceneitem_defer_update_begin(it)
        obs.obs_sceneitem_set_alignment(it, o.align)
        obs.obs_sceneitem_set_pos(it, o.pos)
        obs.obs_sceneitem_set_rot(it, o.rot)
        obs.obs_sceneitem_set_scale(it, o.scale)
        obs.obs_sceneitem_set_bounds(it, o.bounds)
        obs.obs_sceneitem_defer_update_end(it)
        obs.obs_sceneitem_release(it)
    end
    if state.who then set_text("") end
    state = nil
end

local function start_transform(effect)
    local scene_src = obs.obs_frontend_get_current_scene()
    if not scene_src then return nil end
    local scene = obs.obs_scene_from_source(scene_src)
    local item = obs.obs_scene_find_source_recursive(scene, cfg.source_name)
    if not item then
        obs.obs_source_release(scene_src)
        log("La source '" .. cfg.source_name .. "' n'est pas dans la scène actuelle.")
        return nil
    end
    obs.obs_sceneitem_addref(item)
    obs.obs_source_release(scene_src)

    local o = {}
    o.pos = obs.vec2();    obs.obs_sceneitem_get_pos(item, o.pos)
    o.scale = obs.vec2();  obs.obs_sceneitem_get_scale(item, o.scale)
    o.bounds = obs.vec2(); obs.obs_sceneitem_get_bounds(item, o.bounds)
    o.rot = obs.obs_sceneitem_get_rot(item)
    o.align = obs.obs_sceneitem_get_alignment(item)
    o.bounds_type = obs.obs_sceneitem_get_bounds_type(item)

    local m = obs.matrix4()
    obs.obs_sceneitem_get_box_transform(item, m)
    local ctx = {
        cx = m.t.x + 0.5 * (m.x.x + m.y.x),
        cy = m.t.y + 0.5 * (m.x.y + m.y.y),
        hw = 0.5 * math.sqrt(m.x.x ^ 2 + m.x.y ^ 2),
        hh = 0.5 * math.sqrt(m.y.x ^ 2 + m.y.y ^ 2),
    }
    local ovi = obs.obs_video_info()
    obs.obs_get_video_info(ovi)
    ctx.W, ctx.H = ovi.base_width, ovi.base_height

    obs.obs_sceneitem_set_alignment(item, 0) -- OBS_ALIGN_CENTER
    obs.obs_sceneitem_set_pos(item, vec2(ctx.cx, ctx.cy))

    return { kind = "transform", item = item, orig = o, ctx = ctx }
end

local function start_effect(effect, who)
    if state then return false end
    if cfg.source_name == "" then
        log("Choisis d'abord une source victime dans les paramètres du script.")
        return false
    end

    local st
    if effect.shader then
        local src = obs.obs_get_source_by_name(cfg.source_name)
        if not src then
            log("Source '" .. cfg.source_name .. "' introuvable.")
            return false
        end
        ensure_filter(src)
        obs.obs_source_release(src)
        st = { kind = "shader" }
    else
        st = start_transform(effect)
        if not st then return false end
    end

    st.effect, st.t, st.who = effect, 0, who
    state = st
    play_sound()
    if who then set_text("🌀 " .. who .. " a lancé " .. effect.name .. " !") end
    log("Effet : " .. effect.name .. (who and (" (par " .. who .. ")") or ""))
    return true
end

local function pick_random()
    local pool = {}
    for _, e in ipairs(EFFECTS) do
        if cfg.enabled[e.id] then table.insert(pool, e) end
    end
    if #pool == 0 then return nil end
    return pool[math.random(#pool)]
end

local function start_random(who)
    local e = pick_random()
    if not e then
        log("Aucun effet coché !")
        return false
    end
    return start_effect(e, who)
end

local function reset_auto_timer()
    next_auto = rand(cfg.auto_min, math.max(cfg.auto_min, cfg.auto_max))
end

------------------------------------------------------------
-- Twitch : lecture anonyme du chat (Windows, winsock via LuaJIT FFI)
------------------------------------------------------------
local net_ok, ffi, ws = false, nil, nil
do
    local ok, f = pcall(require, "ffi")
    if ok and f.os == "Windows" then
        ffi = f
        pcall(ffi.cdef, [[
            typedef uintptr_t cc_SOCKET;
            struct cc_addrinfo {
                int ai_flags; int ai_family; int ai_socktype; int ai_protocol;
                size_t ai_addrlen; char *ai_canonname; void *ai_addr;
                struct cc_addrinfo *ai_next;
            };
            typedef struct { unsigned int fd_count; cc_SOCKET fd_array[64]; } cc_fd_set;
            typedef struct { long tv_sec; long tv_usec; } cc_timeval;
            int cc_WSAStartup(unsigned short, void *) __asm__("WSAStartup");
            int cc_WSAGetLastError(void) __asm__("WSAGetLastError");
            cc_SOCKET cc_socket(int, int, int) __asm__("socket");
            int cc_connect(cc_SOCKET, const void *, int) __asm__("connect");
            int cc_send(cc_SOCKET, const char *, int, int) __asm__("send");
            int cc_recv(cc_SOCKET, char *, int, int) __asm__("recv");
            int cc_closesocket(cc_SOCKET) __asm__("closesocket");
            int cc_ioctlsocket(cc_SOCKET, long, unsigned long *) __asm__("ioctlsocket");
            int cc_select(int, cc_fd_set *, cc_fd_set *, cc_fd_set *, const cc_timeval *) __asm__("select");
            int cc_getaddrinfo(const char *, const char *, const struct cc_addrinfo *, struct cc_addrinfo **) __asm__("getaddrinfo");
            void cc_freeaddrinfo(struct cc_addrinfo *) __asm__("freeaddrinfo");
        ]])
        local okl, lib = pcall(ffi.load, "ws2_32")
        if okl then
            ws = lib
            local wsadata = ffi.new("uint8_t[1024]")
            net_ok = (ws.cc_WSAStartup(0x0202, wsadata) == 0)
        end
    end
end

local WSAEWOULDBLOCK = 10035
local FIONBIO = -2147195266   -- 0x8004667E en long signé
local INVALID_SOCKET = net_ok and ffi.cast("cc_SOCKET", -1) or nil
local rxbuf = net_ok and ffi.new("char[4096]") or nil

local tw = { sock = nil, status = "off", buf = "", retry_at = 0, started = 0, last_rx = 0 }
local last_global = -1e9
local user_last = {}

local function tw_close(reason)
    if tw.sock then ws.cc_closesocket(tw.sock); tw.sock = nil end
    if reason then log("Twitch : " .. reason) end
    tw.status, tw.buf = "off", ""
end

local function tw_retry(reason, delay)
    tw_close(reason)
    tw.retry_at = now() + (delay or 15)
end

local function tw_send(s)
    if tw.sock then ws.cc_send(tw.sock, s, #s, 0) end
end

local function tw_connect()
    tw_close()
    local hints = ffi.new("struct cc_addrinfo")
    hints.ai_family, hints.ai_socktype = 2, 1   -- AF_INET, SOCK_STREAM
    local res = ffi.new("struct cc_addrinfo *[1]")
    if ws.cc_getaddrinfo("irc.chat.twitch.tv", "6667", hints, res) ~= 0 then
        return tw_retry("impossible de trouver le serveur (pas d'internet ?)", 30)
    end
    local ai = res[0]
    local s = ws.cc_socket(ai.ai_family, ai.ai_socktype, ai.ai_protocol)
    if s == INVALID_SOCKET then
        ws.cc_freeaddrinfo(ai)
        return tw_retry("impossible de créer la connexion", 30)
    end
    local nb = ffi.new("unsigned long[1]", 1)
    ws.cc_ioctlsocket(s, FIONBIO, nb)
    local r = ws.cc_connect(s, ai.ai_addr, tonumber(ai.ai_addrlen))
    ws.cc_freeaddrinfo(ai)
    if r ~= 0 and ws.cc_WSAGetLastError() ~= WSAEWOULDBLOCK then
        ws.cc_closesocket(s)
        return tw_retry("connexion refusée", 30)
    end
    tw.sock, tw.status, tw.started = s, "connecting", now()
end

-- 0 = pas prêt, 1 = prêt, -1 = erreur
local function tw_writable()
    local w = ffi.new("cc_fd_set"); w.fd_count = 1; w.fd_array[0] = tw.sock
    local e = ffi.new("cc_fd_set"); e.fd_count = 1; e.fd_array[0] = tw.sock
    local tv = ffi.new("cc_timeval")
    local r = ws.cc_select(0, nil, w, e, tv)
    if r < 0 or e.fd_count > 0 then return -1 end
    if w.fd_count > 0 then return 1 end
    return 0
end

local function normalize_cmd(c)
    c = c:lower()
    c = c:gsub("é", "e"):gsub("è", "e"):gsub("ê", "e"):gsub("à", "a"):gsub("É", "e")
    return c
end

local function on_chat(display, login, msg, tags)
    local cmd = msg:match("^%s*!(%S+)")
    if not cmd then return end
    cmd = normalize_cmd(cmd)

    local effect
    if cmd == "chaos" then
        effect = "random"
    else
        effect = CMD_MAP[cmd]
        if not effect or not cfg.enabled[effect.id] then return end
    end

    local badges = tags.badges or ""
    local is_bc = badges:find("broadcaster/", 1, true) ~= nil
    local is_mod = is_bc or tags.mod == "1"
    local is_sub = tags.subscriber == "1" or tags.vip == "1"
        or badges:find("vip/", 1, true) ~= nil or badges:find("founder/", 1, true) ~= nil
    if cfg.who == "mods" and not is_mod then return end
    if cfg.who == "subs" and not (is_mod or is_sub) then return end

    if state then return end
    local t = now()
    if not is_bc then
        if t < last_global + cfg.cooldown then return end
        if user_last[login] and t < user_last[login] + cfg.user_cooldown then return end
    end

    if effect == "random" then effect = pick_random() end
    if not effect then return end
    if start_effect(effect, display) then
        last_global = t
        user_last[login] = t
    end
end

local function handle_line(line)
    if line:sub(1, 4) == "PING" then
        tw_send("PONG" .. line:sub(5) .. "\r\n")
        return
    end
    local tags = {}
    if line:sub(1, 1) == "@" then
        local sp = line:find(" ", 1, true)
        if not sp then return end
        for k, v in line:sub(2, sp - 1):gmatch("([^;=]+)=([^;]*)") do tags[k] = v end
        line = line:sub(sp + 1)
    end
    local login, msg = line:match("^:([^!]+)![^ ]+ PRIVMSG #[^ ]+ :(.*)$")
    if login then
        local display = tags["display-name"]
        if not display or display == "" then display = login end
        on_chat(display, login, msg, tags)
    elseif line:find(" NOTICE ", 1, true) then
        log("Twitch : " .. line)
    end
end

local function tw_tick()
    if not net_ok or not cfg.twitch or cfg.channel == "" then
        if tw.status ~= "off" then tw_close("déconnecté") end
        return
    end
    local t = now()

    if tw.status == "off" then
        if t >= tw.retry_at then tw_connect() end
        return
    end

    if tw.status == "connecting" then
        local w = tw_writable()
        if w < 0 then
            tw_retry("connexion impossible", 15)
        elseif w > 0 then
            tw_send("CAP REQ :twitch.tv/tags\r\n")
            tw_send("NICK justinfan" .. math.random(10000, 99999) .. "\r\n")
            tw_send("JOIN #" .. cfg.channel .. "\r\n")
            tw.status, tw.last_rx = "online", t
            log("Twitch : connecté au chat de " .. cfg.channel .. " !")
        elseif t - tw.started > 10 then
            tw_retry("délai de connexion dépassé", 15)
        end
        return
    end

    -- online : on lit tout ce qui est arrivé
    for _ = 1, 20 do
        local n = ws.cc_recv(tw.sock, rxbuf, 4096, 0)
        if n > 0 then
            tw.buf = tw.buf .. ffi.string(rxbuf, n)
            tw.last_rx = t
        elseif n == 0 then
            return tw_retry("connexion fermée par Twitch", 5)
        else
            local err = ws.cc_WSAGetLastError()
            if err ~= WSAEWOULDBLOCK then
                return tw_retry("erreur réseau " .. err, 5)
            end
            break
        end
    end

    while true do
        local i = tw.buf:find("\r\n", 1, true)
        if not i then break end
        local line = tw.buf:sub(1, i - 1)
        tw.buf = tw.buf:sub(i + 2)
        handle_line(line)
    end
    if #tw.buf > 65536 then tw.buf = "" end

    if t - tw.last_rx > 400 then
        tw_retry("plus de nouvelles du serveur, reconnexion", 2)
    end
end

------------------------------------------------------------
-- Boucle principale
------------------------------------------------------------
function script_tick(seconds)
    tw_tick()

    if state then
        state.t = state.t + seconds
        local p = state.t / cfg.duration
        if p >= 1 then
            finish()
        elseif state.kind == "shader" then
            fx.mode = state.effect.shader
            fx.amount = env(p)
            fx.time = state.t
        else
            apply(state.effect.fn(state.ctx, state.t, p, seconds))
        end
        return
    end

    if cfg.auto then
        if cfg.only_live and not (obs.obs_frontend_streaming_active()
                                  or obs.obs_frontend_recording_active()) then
            return
        end
        next_auto = next_auto - seconds
        if next_auto <= 0 then
            reset_auto_timer()
            start_random()
        end
    end
end

------------------------------------------------------------
-- Interface OBS
------------------------------------------------------------
local function command_list()
    local parts = { "!chaos" }
    for _, e in ipairs(EFFECTS) do table.insert(parts, "!" .. e.cmd) end
    return table.concat(parts, "  ")
end

function script_description()
    return [[<h2>🌀 Chaos Cam</h2>
<p>Fait subir des effets absurdes à ta webcam : mouvements (séisme, toupie,
rebond DVD...) et effets photomaton (renflement, tourbillon, thermique...).</p>
<p>Déclenche avec les raccourcis (Paramètres &gt; Raccourcis clavier, cherche
« Chaos Cam »), le mode auto, ou laisse ton chat Twitch s'en charger.</p>]]
end

local function fill_source_list(prop)
    obs.obs_property_list_add_string(prop, "(aucune)", "")
    local sources = obs.obs_enum_sources()
    if sources then
        for _, s in ipairs(sources) do
            local n = obs.obs_source_get_name(s)
            obs.obs_property_list_add_string(prop, n, n)
        end
        obs.source_list_release(sources)
    end
end

function script_properties()
    local props = obs.obs_properties_create()

    local p = obs.obs_properties_add_list(props, "source_name", "Source victime (webcam)",
        obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    fill_source_list(p)

    p = obs.obs_properties_add_list(props, "sound_name", "Son à jouer (source média, optionnel)",
        obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    fill_source_list(p)

    obs.obs_properties_add_float_slider(props, "duration", "Durée d'un effet (s)", 1, 15, 0.5)

    -- effets
    local g_move = obs.obs_properties_create()
    local g_photo = obs.obs_properties_create()
    for _, e in ipairs(EFFECTS) do
        local label = e.name .. "   (!" .. e.cmd .. ")"
        obs.obs_properties_add_bool(e.shader and g_photo or g_move, "fx_" .. e.id, label)
    end
    obs.obs_properties_add_group(props, "fx_move", "Effets mouvement", obs.OBS_GROUP_NORMAL, g_move)
    obs.obs_properties_add_group(props, "fx_photo", "Effets photomaton", obs.OBS_GROUP_NORMAL, g_photo)

    -- Twitch
    local g_tw = obs.obs_properties_create()
    if not net_ok then
        obs.obs_properties_add_text(g_tw, "tw_na",
            "⚠ Le chat Twitch n'est disponible que sous Windows.", obs.OBS_TEXT_INFO)
    end
    obs.obs_properties_add_text(g_tw, "channel", "Nom de ta chaîne", obs.OBS_TEXT_DEFAULT)
    local who = obs.obs_properties_add_list(g_tw, "who", "Qui peut déclencher",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(who, "Tout le monde", "all")
    obs.obs_property_list_add_string(who, "Abonnés, VIP et modos", "subs")
    obs.obs_property_list_add_string(who, "Modos seulement", "mods")
    obs.obs_properties_add_int(g_tw, "cooldown", "Délai entre deux effets (s)", 0, 3600, 1)
    obs.obs_properties_add_int(g_tw, "user_cooldown", "Délai par viewer (s)", 0, 3600, 5)
    p = obs.obs_properties_add_list(g_tw, "text_name", "Texte « qui a lancé quoi » (optionnel)",
        obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    fill_source_list(p)
    obs.obs_properties_add_text(g_tw, "cmds", "Commandes : " .. command_list(), obs.OBS_TEXT_INFO)
    obs.obs_properties_add_group(props, "twitch", "Chat Twitch (les viewers déclenchent)",
        obs.OBS_GROUP_CHECKABLE, g_tw)

    -- auto
    local g_auto = obs.obs_properties_create()
    obs.obs_properties_add_int(g_auto, "auto_min", "Intervalle min (s)", 5, 3600, 5)
    obs.obs_properties_add_int(g_auto, "auto_max", "Intervalle max (s)", 5, 3600, 5)
    obs.obs_properties_add_bool(g_auto, "only_live", "Seulement en live / enregistrement")
    obs.obs_properties_add_group(props, "auto", "Mode auto (chaos au hasard)",
        obs.OBS_GROUP_CHECKABLE, g_auto)

    -- tests
    local g_test = obs.obs_properties_create()
    obs.obs_properties_add_button(g_test, "btn_random", "🎲 Effet au hasard",
        function() start_random(); return false end)
    for _, e in ipairs(EFFECTS) do
        obs.obs_properties_add_button(g_test, "btn_" .. e.id, e.name,
            function() start_effect(e); return false end)
    end
    obs.obs_properties_add_group(props, "test_group", "Tester", obs.OBS_GROUP_NORMAL, g_test)

    return props
end

function script_defaults(settings)
    obs.obs_data_set_default_double(settings, "duration", 4.0)
    obs.obs_data_set_default_int(settings, "auto_min", 60)
    obs.obs_data_set_default_int(settings, "auto_max", 180)
    obs.obs_data_set_default_bool(settings, "only_live", true)
    obs.obs_data_set_default_bool(settings, "auto", false)
    obs.obs_data_set_default_bool(settings, "twitch", false)
    obs.obs_data_set_default_string(settings, "who", "all")
    obs.obs_data_set_default_int(settings, "cooldown", 15)
    obs.obs_data_set_default_int(settings, "user_cooldown", 60)
    for _, e in ipairs(EFFECTS) do
        obs.obs_data_set_default_bool(settings, "fx_" .. e.id, not e.off_by_default)
    end
end

local function clean_channel(s)
    s = s:lower():gsub("%s", "")
    s = s:match("([^/]+)/*$") or s   -- accepte un lien twitch.tv/xxx
    s = s:gsub("^#", ""):gsub("^@", "")
    return s
end

function script_update(settings)
    local old_channel, old_twitch = cfg.channel, cfg.twitch

    cfg.source_name   = obs.obs_data_get_string(settings, "source_name")
    cfg.sound_name    = obs.obs_data_get_string(settings, "sound_name")
    cfg.text_name     = obs.obs_data_get_string(settings, "text_name")
    cfg.duration      = math.max(0.5, obs.obs_data_get_double(settings, "duration"))
    cfg.auto          = obs.obs_data_get_bool(settings, "auto")
    cfg.auto_min      = obs.obs_data_get_int(settings, "auto_min")
    cfg.auto_max      = obs.obs_data_get_int(settings, "auto_max")
    cfg.only_live     = obs.obs_data_get_bool(settings, "only_live")
    cfg.twitch        = obs.obs_data_get_bool(settings, "twitch")
    cfg.channel       = clean_channel(obs.obs_data_get_string(settings, "channel"))
    cfg.who           = obs.obs_data_get_string(settings, "who")
    cfg.cooldown      = obs.obs_data_get_int(settings, "cooldown")
    cfg.user_cooldown = obs.obs_data_get_int(settings, "user_cooldown")
    for _, e in ipairs(EFFECTS) do
        cfg.enabled[e.id] = obs.obs_data_get_bool(settings, "fx_" .. e.id)
    end
    reset_auto_timer()

    if net_ok and (old_channel ~= cfg.channel or old_twitch ~= cfg.twitch) then
        tw_close()
        tw.retry_at = 0
    end

    -- pose le filtre photomaton tout de suite si la source existe
    if cfg.source_name ~= "" then
        local src = obs.obs_get_source_by_name(cfg.source_name)
        if src then
            ensure_filter(src)
            obs.obs_source_release(src)
        end
    end
end

local function register_hotkey(settings, key, label, action)
    local id = obs.obs_hotkey_register_frontend(key, label, function(pressed)
        if pressed then action() end
    end)
    local arr = obs.obs_data_get_array(settings, key)
    obs.obs_hotkey_load(id, arr)
    obs.obs_data_array_release(arr)
    hotkeys[key] = id
end

function script_load(settings)
    math.randomseed(os.time())
    register_hotkey(settings, "chaos_cam_random", "Chaos Cam : effet au hasard",
        function() start_random() end)
    for _, e in ipairs(EFFECTS) do
        register_hotkey(settings, "chaos_cam_" .. e.id, "Chaos Cam : " .. e.name,
            function() start_effect(e) end)
    end
    if not net_ok then log("Chat Twitch indisponible (Windows uniquement).") end
end

function script_save(settings)
    for key, id in pairs(hotkeys) do
        local arr = obs.obs_hotkey_save(id)
        obs.obs_data_set_array(settings, key, arr)
        obs.obs_data_array_release(arr)
    end
end

function script_unload()
    finish()
    if net_ok then tw_close() end
end
