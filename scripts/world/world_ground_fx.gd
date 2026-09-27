class_name WorldGroundFx
extends Node3D
## Ground detail of the acts (child "GroundFx" of the World's level root):
##   - ground_material(style): the act ground's shader. Per vertex it gets the generator's colour
##     (COLOR) and four material weights (UV, UV2 = WorldActGen.ground_detail); per pixel it draws
##     procedural texture: forest = soil grain, gravel, mud and puddles, leaf litter, moss and
##     needles; desert = sand ripples and grain, pebbles, cracked sandstone slabs, half-buried sand
##     bricks, dried cracked mud; gothic = grimy dirt, wet mud, puddles, dead leaves, soot.
##   - details: flat decals (MultiMesh quads, one procedural shape per kind: leaves, twigs, needles,
##     pebbles, wood splinters, blood, puddles, broken glass, brick rubble, cracks, sand drifts, moss,
##     stains, straw, bones) lying on the ground or on paving, chunked.
##   - grass: tufts (MultiMesh) that sway in the wind and bend away from the player and monsters
##     (a shared pusher list, updated every frame: current positions plus fading trail points, so
##     the grass springs back after they pass), chunked.
## Detail / grass entries come from WorldActGen.add_detail / add_grass (layout "details", "grass").
## OWNER: world.

## Kinds of details (WorldActGen.add_detail(kind, ...)).
const DETAIL_KINDS := {"leaf": 0, "leaves": 1, "twigs": 2, "pebbles": 3, "splinters": 4, "blood": 5, "puddle": 6,
	"glass": 7, "bricks": 8, "cracks": 9, "sand": 10, "moss": 11, "stain": 12, "straw": 13, "needles": 14, "bones": 15}
## Kinds of grass tufts (WorldActGen.add_grass(..., kind)).
const GRASS_KINDS := {"grass": 0, "reeds": 1}
const CHUNK := 24.0
const DETAIL_RANGE := 70.0
const GRASS_RANGE := 58.0
## Height of the details above the ground (m): above paving too (tiles top out at ~0.01).
const DETAIL_LIFT := 0.018
## Grass pushers sent to the shader (actors and their fading trails).
const MAX_PUSHERS := 32
const PUSH_REACH := 30.0
const TRAIL_STEP := 0.35
const TRAIL_LIFE := 1.1

const COMMON_GLSL := """
float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec2 h22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1.0, 0.0)), u.x), mix(h12(i + vec2(0.0, 1.0)), h12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	return vn(p) * 0.6 + vn(p * 2.07 + 5.3) * 0.28 + vn(p * 4.3 - 2.1) * 0.12;
}
// Nearest jittered grid point: x = distance, y = cell hash; rel = the vector from it.
vec2 vor(vec2 p, out vec2 rel) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float best = 8.0;
	vec2 bc = vec2(0.0);
	vec2 br = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + h22(ip + g) * 0.8 + 0.1 - fp;
			float d = dot(r, r);
			if (d < best) {
				best = d;
				bc = ip + g;
				br = r;
			}
		}
	}
	rel = br;
	return vec2(sqrt(best), h12(bc));
}
// Distance to the nearest Voronoi cell border (cracks, slab joints); id = the cell's hash.
float vor_edge(vec2 p, out float id) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + h22(ip + g) - fp;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}
	id = h12(ip + mg);
	md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 r = g + h22(ip + g) - fp;
			vec2 dd = r - mr;
			if (dot(dd, dd) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(dd)));
			}
		}
	}
	return md;
}
// The top-most of the elongated stamps (leaves, needles) scattered on a jittered grid of `cell`
// metres (chance `dens` per cell): x = coverage, y = pick (0..1), zw = the local position along /
// across the stamp (normalised by its half length).
vec4 stamps(vec2 p, float cell, float dens, float pxm, float len0, float len1, float aspect, float taper) {
	vec2 q = p / cell;
	vec2 ip = floor(q);
	float pxc = pxm / cell;
	vec4 top = vec4(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = ip + vec2(float(i), float(j));
			vec2 hh = h22(c + 17.0);
			if (hh.x > dens) {
				continue;
			}
			vec2 d = q - (c + 0.15 + h22(c) * 0.7);
			float ang = hh.y * 6.2832;
			float ca = cos(ang);
			float sa = sin(ang);
			vec2 l = vec2(ca * d.x + sa * d.y, -sa * d.x + ca * d.y);
			float len = len0 + len1 * h12(c + 3.3);
			float u = l.x / len;
			if (abs(u) > 1.05) {
				continue;
			}
			float wid = len * aspect * (0.8 + 0.4 * h12(c + 8.1));
			float edge = abs(l.y) - wid * (1.0 - taper * u * u) * (1.0 + 0.2 * u);
			float a = 1.0 - smoothstep(-pxc, pxc, edge);
			if (a > 0.01) {
				top = vec4(a, h12(c + 21.7), u, l.y / len);
			}
		}
	}
	return top;
}
"""

## The act ground: vertex colour + procedural material layers (weights in UV / UV2).
const GROUND_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
varying vec3 v_world;
varying vec4 v_w;
varying vec3 v_col;
%COMMON%
vec3 bump(vec3 n, vec3 pos, float h) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	return normalize(abs(det) * n - grad);
}
void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_w = vec4(UV, UV2);
	v_col = COLOR.rgb;
}
void fragment() {
	vec2 p = v_world.xz;
	vec4 w = clamp(v_w, 0.0, 1.0);
	vec3 col = v_col;
	float rough = 0.92;
	float spec = 0.3;
	float h = 0.0;
	vec2 fw = fwidth(p);
	float px = max(fw.x, fw.y);
	float fade = 1.0 - smoothstep(0.05, 0.14, px);
	float g1 = vn(p * 2.3);
	float g2 = vn(p * 9.0 + 7.0);
	float g3 = vn(p * 31.0 - 3.0);
#ifdef STYLE_FOREST
	// soil and grass grain
	col *= 0.84 + 0.24 * g1 + (0.16 * (g2 - 0.5) + 0.14 * (g3 - 0.5)) * fade;
	h += ((g2 - 0.5) * 0.004 + (g3 - 0.5) * 0.002) * fade;
	// darker clods of earth
	col *= 1.0 - 0.18 * smoothstep(0.62, 0.8, vn(p * 1.7 + 31.0)) * fade;
	if (w.x > 0.01) {
		// gravel on the trails
		float cov = smoothstep(0.3, 0.7, w.x + (vn(p * 0.8) - 0.5) * 0.7);
		vec2 rel;
		vec2 v = vor(p * 8.5, rel);
		float R = 0.3 + 0.16 * h12(vec2(v.y * 91.0, 3.0));
		float d = v.x / R;
		float aa = px * 8.5 / R;
		float keep = step(0.22, h12(vec2(v.y, 29.0)));
		float stone = (1.0 - smoothstep(1.0 - aa, 1.0 + aa, d)) * cov * keep * fade;
		// stones in the ground's own brightness range: greyish, a little lighter than the dirt
		float lum = dot(col, vec3(0.3, 0.55, 0.15));
		vec3 grey = mix(vec3(1.0, 0.97, 0.92), vec3(1.05, 0.9, 0.72), h12(vec2(v.y, 7.0)));
		vec3 sc = grey * lum * (1.05 + 0.5 * h12(vec2(v.y, 13.0)));
		float dome = sqrt(max(0.0, 1.0 - d * d));
		col = mix(col * (1.0 - 0.08 * cov), sc * (0.9 + 0.15 * dome), stone);
		h += stone * dome * R / 8.5 * 0.3;
		rough = mix(rough, 0.7, stone);
	}
	if (w.y > 0.01) {
		// mud, wet ruts and puddles
		float m = smoothstep(0.25, 0.7, w.y + (fbm(p * 0.45) - 0.5) * 0.8);
		vec3 mud = mix(col * vec3(0.5, 0.4, 0.28), vec3(0.045, 0.032, 0.02), 0.35) * (0.75 + 0.5 * g2);
		col = mix(col, mud, m * 0.85);
		rough = mix(rough, 0.45, m);
		spec = mix(spec, 0.5, m);
		h += m * (vn(p * 5.0) - 0.5) * 0.012;
		float pd = smoothstep(0.64, 0.67, fbm(p * 0.9 + 11.0) * 0.75 + m * 0.3) * m;
		col = mix(col, col * 0.25 + vec3(0.008, 0.01, 0.01), pd * 0.85);
		rough = mix(rough, 0.16, pd);
		spec = mix(spec, 0.5, pd);
		h = mix(h, -0.004, pd);
	}
	if (w.z > 0.01) {
		// autumn leaf litter (birch yellow, orange, brown, red)
		float dens = clamp(w.z * w.z * (0.35 + 1.1 * fbm(p * 0.3 + 3.0)), 0.0, 0.92);
		vec4 lf = stamps(p, 0.13, dens, px, 0.42, 0.34, 0.36, 1.0);
		if (lf.x > 0.0) {
			vec3 lc = mix(vec3(0.3, 0.17, 0.018), vec3(0.28, 0.09, 0.02), step(0.45, lf.y));
			lc = mix(lc, vec3(0.1, 0.05, 0.018), step(0.72, lf.y));
			lc = mix(lc, vec3(0.2, 0.035, 0.018), step(0.9, lf.y));
			lc *= 0.72 + 0.4 * h12(vec2(lf.y * 51.0, 2.0));
			lc *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.06, abs(lf.w))) * step(abs(lf.z), 0.85);
			col = mix(col, lc, lf.x * fade);
			h += lf.x * 0.003 * fade;
			rough = mix(rough, 0.8, lf.x);
		}
	}
	if (w.w > 0.01) {
		// moss and fallen needles under the conifers
		float mo = smoothstep(0.42, 0.78, fbm(p * 0.9 - 4.0) + w.w * 0.35 - 0.15) * w.w;
		col = mix(col, vec3(0.04, 0.085, 0.012) * (0.7 + 0.6 * g3), mo * 0.8);
		vec4 nd = stamps(p, 0.05, w.w * 0.55, px, 0.45, 0.3, 0.07, 0.2);
		col = mix(col, vec3(0.1, 0.042, 0.014) * (0.7 + 0.5 * nd.y), nd.x * (1.0 - mo) * fade);
		h += nd.x * 0.0015 * fade;
	}
#endif
#ifdef STYLE_DESERT
	float other = clamp(w.x + w.y + w.z + w.w, 0.0, 1.0);
	// wind ripples and grain on the open sand
	float warp = fbm(p * 0.11) * 5.0 + vn(p * 0.55) * 0.9;
	float rip = sin(dot(p, vec2(0.83, 0.56)) * 21.0 + warp * 4.0) * 0.5 + 0.5;
	rip = rip * rip;
	float rip_on = (1.0 - other) * smoothstep(0.3, 0.7, vn(p * 0.22 + 9.0) + 0.15) * fade;
	rip_on *= 1.0 - clamp((v_col.g - v_col.r) * 12.0, 0.0, 1.0);
	h += rip * 0.007 * rip_on;
	col *= 0.93 + 0.1 * g1 + 0.1 * (vn(p * 47.0) - 0.5) * fade + 0.05 * rip * rip_on;
	if (w.x > 0.01) {
		// pebbles and gravel, half sunk in the sand
		float cov = smoothstep(0.3, 0.7, w.x + (vn(p * 0.7 + 2.0) - 0.5) * 0.8);
		vec2 rel;
		vec2 v = vor(p * 10.0, rel);
		float R = 0.26 + 0.18 * h12(vec2(v.y * 57.0, 1.0));
		float d = v.x / R;
		float aa = px * 10.0 / R;
		float keep = step(0.3, h12(vec2(v.y, 4.0)));
		float stone = (1.0 - smoothstep(1.0 - aa, 1.0 + aa, d)) * cov * keep * fade;
		float lum = dot(col, vec3(0.3, 0.55, 0.15));
		vec3 sc = mix(vec3(1.05, 0.82, 0.62), vec3(0.95, 0.62, 0.42), h12(vec2(v.y, 9.0)));
		sc = mix(sc, vec3(0.85, 0.84, 0.82), step(0.75, h12(vec2(v.y, 19.0))));
		sc *= lum * (0.72 + 0.4 * h12(vec2(v.y, 23.0)));
		float dome = sqrt(max(0.0, 1.0 - d * d));
		col = mix(col, sc * (0.85 + 0.2 * dome), stone);
		h += stone * dome * R / 10.0 * 0.3;
		rough = mix(rough, 0.72, stone);
	}
	if (w.y > 0.01) {
		// sandstone slabs: cracked, layered, sand in the joints
		float cov = smoothstep(0.3, 0.65, w.y + (fbm(p * 0.35 + 5.0) - 0.5) * 0.7);
		float id;
		float e = vor_edge(p * 0.95, id);
		float joint = 1.0 - smoothstep(0.02, 0.05 + px, e);
		vec3 slab = mix(vec3(0.55, 0.36, 0.2), vec3(0.62, 0.45, 0.28), id) * (0.85 + 0.2 * g2);
		slab *= 0.93 + 0.08 * sin(p.y * 9.0 + fbm(p * 0.8) * 6.0);
		float fine;
		float cr = vor_edge(p * 3.2 + 7.0, fine);
		slab *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.03 + px * 3.2, cr)) * step(0.5, fine) * fade;
		col = mix(col, mix(slab, col * 0.9, joint), cov);
		h += cov * ((1.0 - joint) * 0.015 - (1.0 - smoothstep(0.0, 0.04, cr)) * step(0.5, fine) * 0.003);
		rough = mix(rough, 0.85, cov);
	}
	if (w.z > 0.01) {
		// sand bricks: running bond, worn, some missing, drifted over by sand
		vec2 b = p / vec2(0.38, 0.19);
		float row = floor(b.y);
		b.x += mod(row, 2.0) * 0.5;
		vec2 cell = floor(b);
		vec2 f = fract(b);
		vec2 ed = min(f, 1.0 - f) * vec2(0.38, 0.19);
		float edge = min(ed.x, ed.y);
		float mortar = 1.0 - smoothstep(0.01, 0.016 + px, edge);
		float hb = h12(cell + 3.0);
		float drift = smoothstep(0.42, 0.62, fbm(p * 0.45 + 13.0) + (1.0 - w.z) * 0.8 - 0.25);
		float brick = (1.0 - drift) * step(0.1, hb);
		vec3 bc = mix(vec3(0.6, 0.42, 0.24), vec3(0.47, 0.3, 0.16), h12(cell + 7.0)) * (0.82 + 0.25 * g3);
		bc *= 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.035, edge));
		col = mix(col, mix(bc, vec3(0.3, 0.22, 0.14), mortar), brick);
		h += brick * (smoothstep(0.0, 0.03, edge) * 0.012);
		rough = mix(rough, 0.82, brick);
	}
	if (w.w > 0.01) {
		// dried, cracked mud by the water (wet and dark right at the edge)
		float cov = smoothstep(0.25, 0.6, w.w);
		float id;
		float e = vor_edge(p * 3.6, id);
		float crack = 1.0 - smoothstep(0.015, 0.045 + px * 3.6, e);
		vec3 mud = mix(vec3(0.3, 0.22, 0.14), vec3(0.24, 0.18, 0.12), id) * (0.85 + 0.2 * g2);
		col = mix(col, mix(mud, vec3(0.06, 0.045, 0.03), crack), cov);
		h += cov * (1.0 - crack) * 0.006;
		float wet = smoothstep(0.75, 1.0, w.w);
		col *= 1.0 - 0.45 * wet;
		rough = mix(rough, 0.35, wet);
	}
#endif
#ifdef STYLE_GOTHIC
	// grimy dirt with soot and old snow-melt stains
	col *= 0.8 + 0.28 * g1 + (0.14 * (g2 - 0.5) + 0.14 * (g3 - 0.5)) * fade;
	col *= 1.0 - 0.3 * smoothstep(0.58, 0.82, vn(p * 0.9 + 21.0));
	h += (g3 - 0.5) * 0.003 * fade;
	if (w.x > 0.01) {
		// wet mud and cart ruts
		float m = smoothstep(0.25, 0.7, w.x + (fbm(p * 0.5) - 0.5) * 0.8);
		col = mix(col, vec3(0.022, 0.019, 0.016) * (0.8 + 0.4 * g2), m * 0.9);
		rough = mix(rough, 0.4, m);
		spec = mix(spec, 0.5, m);
		h += m * (vn(p * 4.0) - 0.5) * 0.012;
	}
	if (w.y > 0.01) {
		// puddles
		float pd = smoothstep(0.5, 0.54, fbm(p * 0.5 + 3.0) * 0.8 + w.y * 0.45 - 0.2);
		col = mix(col, vec3(0.006, 0.008, 0.011), pd * 0.9);
		rough = mix(rough, 0.06, pd);
		spec = mix(spec, 0.8, pd);
		h = mix(h, -0.003, pd);
	}
	if (w.z > 0.01) {
		// dead, discoloured leaves
		float dens = clamp(w.z * w.z * (0.35 + 1.1 * fbm(p * 0.35 + 8.0)), 0.0, 0.9);
		vec4 lf = stamps(p, 0.14, dens, px, 0.42, 0.32, 0.36, 1.0);
		if (lf.x > 0.0) {
			vec3 lc = mix(vec3(0.1, 0.07, 0.035), vec3(0.08, 0.075, 0.04), step(0.4, lf.y));
			lc = mix(lc, vec3(0.13, 0.08, 0.025), step(0.7, lf.y));
			lc = mix(lc, vec3(0.03, 0.025, 0.02), step(0.88, lf.y));
			lc *= 0.75 + 0.4 * h12(vec2(lf.y * 31.0, 5.0));
			// holes in the rotten ones
			float hole = step(0.6, vn(vec2(lf.z, lf.w) * 6.0 + lf.y * 40.0)) * step(0.55, lf.y);
			col = mix(col, lc, lf.x * (1.0 - hole) * fade);
			h += lf.x * 0.002 * fade;
		}
	}
	if (w.w > 0.01) {
		// soot and grime stains
		float st = smoothstep(0.45, 0.8, fbm(p * 0.7 + 17.0) + w.w * 0.3 - 0.1) * w.w;
		col *= 1.0 - 0.55 * st;
	}
#endif
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	NORMAL = bump(NORMAL, VERTEX, h * 2.2);
}
"""

## Flat details (MultiMesh quads): INSTANCE_CUSTOM.x = kind, .y = seed; COLOR = tint (a = opacity).
const DETAIL_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
varying vec4 v_custom;
varying vec4 v_tint;
%COMMON%
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float t = clamp(dot(pa, ba) / max(dot(ba, ba), 0.00001), 0.0, 1.0);
	return length(pa - ba * t);
}
vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x + s * v.y, -s * v.x + c * v.y);
}
void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_tint = COLOR;
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	vec2 fq = fwidth(q);
	float aa = max(fq.x, fq.y) * 1.2;
	int kind = int(v_custom.x + 0.5);
	float sd = v_custom.y * 173.0;
	vec3 tint = v_tint.rgb;
	vec3 col = tint;
	float a = 0.0;
	float rough = 0.85;
	float spec = 0.35;
	vec3 emis = vec3(0.0);
	if (kind == 0 || kind == 1) {
		// one leaf / a cluster of leaves
		int n = kind == 0 ? 1 : 7;
		for (int k = 0; k < 7; k++) {
			if (k >= n) {
				break;
			}
			vec2 hk = h22(vec2(sd, float(k) * 7.1));
			vec2 c = kind == 0 ? vec2(0.0) : (hk - 0.5) * 1.25;
			float s = kind == 0 ? 0.92 : 0.26 + 0.14 * h12(vec2(sd + 3.0, float(k)));
			vec2 l = rot(q - c, h12(vec2(sd + 9.0, float(k))) * 6.2832) / s;
			float u = l.x;
			float edge = abs(l.y) - 0.4 * (1.0 - u * u) * (1.0 + 0.2 * u);
			float la = (1.0 - smoothstep(-aa / s, aa / s, edge)) * step(abs(u), 1.0);
			vec3 lc = tint * (0.7 + 0.5 * h12(vec2(sd, float(k) + 0.5)));
			lc = mix(lc, lc.gbr * 0.6 + lc * 0.5, step(0.7, hk.y) * 0.5);
			lc *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.05, abs(l.y))) * step(abs(u), 0.85);
			float stalk = (1.0 - smoothstep(0.0, 0.04 + aa / s, seg(l, vec2(-1.0, 0.0), vec2(-1.25, 0.03)))) * 0.9;
			la = max(la, stalk);
			col = mix(col, lc, la);
			a = max(a, la);
		}
		rough = 0.8;
	} else if (kind == 2 || kind == 14 || kind == 13) {
		// twigs / needles / straw: thin strokes
		int n = kind == 2 ? 5 : (kind == 14 ? 16 : 14);
		float wid = kind == 2 ? 0.035 : (kind == 14 ? 0.014 : 0.018);
		for (int k = 0; k < 16; k++) {
			if (k >= n) {
				break;
			}
			vec2 hk = h22(vec2(sd + 1.0, float(k) * 3.7));
			vec2 c = (hk - 0.5) * 1.1;
			float ang = h12(vec2(sd, float(k) * 5.3)) * 6.2832;
			float len = kind == 2 ? 0.45 + 0.4 * hk.y : 0.18 + 0.16 * hk.y;
			vec2 dir = vec2(cos(ang), sin(ang));
			float d = seg(q, c - dir * len, c + dir * len);
			float sa = 1.0 - smoothstep(wid, wid + aa, d);
			if (kind == 2) {
				vec2 fk = c + dir * len * 0.3;
				vec2 fd = rot(dir, 0.6) * len * 0.4;
				sa = max(sa, 1.0 - smoothstep(wid * 0.7, wid * 0.7 + aa, seg(q, fk, fk + fd)));
			}
			col = mix(col, tint * (0.7 + 0.5 * hk.x), sa);
			a = max(a, sa);
		}
	} else if (kind == 3 || kind == 15) {
		// pebbles / bone bits: small shaded stones with a soft contact shadow
		int n = kind == 3 ? 8 : 4;
		float sh = 0.0;
		for (int k = 0; k < 8; k++) {
			if (k >= n) {
				break;
			}
			vec2 hk = h22(vec2(sd + 2.0, float(k) * 4.3));
			vec2 c = (hk - 0.5) * 1.2;
			float r = kind == 3 ? 0.1 + 0.13 * h12(vec2(sd, float(k))) : 0.07;
			vec2 d = q - c;
			if (kind == 15) {
				d = rot(d, hk.y * 6.2832);
				float bone = min(seg(d, vec2(-0.25, 0.0), vec2(0.25, 0.0)) - 0.035,
					min(length(d - vec2(0.27, 0.03)) - 0.06, length(d - vec2(-0.27, -0.03)) - 0.06));
				float ba = 1.0 - smoothstep(0.0, aa, bone);
				col = mix(col, tint * (0.85 + 0.2 * hk.x), ba);
				a = max(a, ba);
				continue;
			}
			d.y *= 1.0 + 0.4 * hk.y;
			float dl = length(d) / r;
			float sa = 1.0 - smoothstep(1.0 - aa / r, 1.0 + aa / r, dl);
			float shade = 0.72 + 0.42 * clamp(dot(d / r, vec2(-0.55, -0.65)), -1.0, 1.0) * sqrt(max(0.0, 1.0 - dl * dl));
			vec3 sc = tint * (0.72 + 0.45 * h12(vec2(sd + 5.0, float(k)))) * shade;
			col = mix(col, sc, sa);
			a = max(a, sa);
			sh = max(sh, (1.0 - smoothstep(0.9, 1.5, length(q - c - vec2(0.03, 0.05)) / r)) * 0.45);
		}
		col = mix(vec3(0.0), col, max(a, 0.001) / max(a, max(sh, 0.001)));
		a = max(a, sh);
		rough = 0.75;
	} else if (kind == 4) {
		// wood splinters
		for (int k = 0; k < 6; k++) {
			vec2 hk = h22(vec2(sd + 4.0, float(k) * 2.9));
			vec2 c = (hk - 0.5) * 1.0;
			vec2 l = rot(q - c, h12(vec2(sd, float(k) * 1.3)) * 6.2832);
			float len = 0.3 + 0.45 * hk.y;
			float wid = 0.035 + 0.04 * h12(vec2(sd + 1.0, float(k)));
			float u = l.x / len;
			float jag = 0.35 * (0.5 + 0.5 * sin(l.y * 90.0 + float(k)));
			float e = max(abs(l.y) - wid * (1.0 - smoothstep(0.6 - jag, 1.0, abs(u))), abs(u) - 1.0);
			float sa = 1.0 - smoothstep(0.0, aa, e);
			vec3 wc = tint * (0.75 + 0.35 * hk.x) * (0.9 + 0.12 * sin(l.x * 70.0 + hk.y * 9.0));
			wc *= 1.0 - 0.3 * smoothstep(wid * 0.4, wid, abs(l.y));
			col = mix(col, wc, sa);
			a = max(a, sa);
		}
		rough = 0.8;
	} else if (kind == 5) {
		// blood: a pool, droplets and a few streaks
		float ang = atan(q.y, q.x);
		float r0 = 0.42 + 0.06 * sin(ang * 3.0 + sd) + 0.04 * sin(ang * 7.0 + sd * 2.0) + 0.03 * sin(ang * 11.0 + sd);
		float bd = length(q) - r0;
		for (int k = 0; k < 10; k++) {
			vec2 hk = h22(vec2(sd + 6.0, float(k) * 1.9));
			float an = hk.x * 6.2832;
			vec2 dir = vec2(cos(an), sin(an));
			float dist = 0.5 + 0.42 * hk.y;
			float rr = 0.025 + 0.05 * h12(vec2(sd, float(k) + 0.3));
			bd = min(bd, length(q - dir * dist) - rr);
			if (k < 4) {
				bd = min(bd, seg(q, dir * 0.3, dir * (0.45 + 0.3 * hk.y)) - 0.03 * (1.0 - hk.y * 0.5));
			}
		}
		a = (1.0 - smoothstep(-aa, aa, bd)) * 0.92;
		col = tint * (0.55 + 0.45 * smoothstep(-0.3, 0.0, bd));
		rough = 0.22;
		spec = 0.55;
	} else if (kind == 6) {
		// a puddle: dark still water, a wet rim
		float ang = atan(q.y, q.x);
		float r0 = 0.66 + 0.08 * sin(ang * 2.0 + sd) + 0.06 * sin(ang * 5.0 + sd * 1.7) + 0.035 * sin(ang * 9.0 + sd * 2.3);
		float pd = length(q) - r0;
		float inside = 1.0 - smoothstep(-aa, aa, pd);
		float rim = (1.0 - smoothstep(0.0, 0.16, pd)) * (1.0 - inside);
		// the tint is the water's look (reflected sky / murk): the rim is wet, darker ground
		col = mix(tint * 0.35, tint * (0.8 + 0.25 * smoothstep(-0.5, 0.0, pd)), inside);
		a = inside * 0.9 + rim * 0.4;
		rough = mix(0.5, 0.12, inside);
		spec = mix(0.4, 0.55, inside);
	} else if (kind == 7) {
		// broken glass: shards that glint
		for (int k = 0; k < 7; k++) {
			vec2 hk = h22(vec2(sd + 7.0, float(k) * 3.1));
			vec2 c = (hk - 0.5) * 1.3;
			float s = 0.1 + 0.12 * hk.y;
			vec2 p0 = c + (h22(vec2(sd, float(k) + 0.1)) - 0.5) * s * 2.0;
			vec2 p1 = c + (h22(vec2(sd, float(k) + 0.2)) - 0.5) * s * 2.0;
			vec2 p2 = c + (h22(vec2(sd, float(k) + 0.3)) - 0.5) * s * 2.0;
			vec2 e0 = p1 - p0;
			vec2 e1 = p2 - p1;
			vec2 e2 = p0 - p2;
			float o = sign(e0.x * e2.y - e0.y * e2.x);
			vec2 v0 = q - p0;
			vec2 v1 = q - p1;
			vec2 v2 = q - p2;
			float d0 = o * (e0.x * v0.y - e0.y * v0.x) / max(length(e0), 0.0001);
			float d1 = o * (e1.x * v1.y - e1.y * v1.x) / max(length(e1), 0.0001);
			float d2 = o * (e2.x * v2.y - e2.y * v2.x) / max(length(e2), 0.0001);
			float inside = min(d0, min(d1, d2));
			float sa = smoothstep(-aa, aa, inside);
			float tw = pow(max(0.0, sin(TIME * (1.3 + hk.x) + sd + float(k) * 2.1)), 40.0);
			col = mix(col, tint * (0.8 + 0.4 * hk.x), sa);
			emis = max(emis, vec3(1.0, 0.97, 0.9) * tw * sa * 1.8);
			a = max(a, sa * 0.8);
		}
		rough = 0.05;
		spec = 0.9;
	} else if (kind == 8) {
		// broken bricks and chips
		for (int k = 0; k < 7; k++) {
			vec2 hk = h22(vec2(sd + 8.0, float(k) * 2.3));
			vec2 c = (hk - 0.5) * 1.2;
			bool chip = k >= 3;
			vec2 hs = chip ? vec2(0.05 + 0.04 * hk.y) : vec2(0.26, 0.13) * (0.7 + 0.4 * hk.y);
			vec2 l = rot(q - c, h12(vec2(sd, float(k) * 0.7)) * 6.2832);
			vec2 dd = abs(l) - hs;
			float box = length(max(dd, 0.0)) + min(max(dd.x, dd.y), 0.0);
			float cut = dot(l, normalize(h22(vec2(sd + 1.0, float(k))) - 0.5)) - hs.x * 0.6;
			box = max(box, chip ? box : cut);
			float sa = 1.0 - smoothstep(0.0, aa, box);
			vec3 bc = tint * (0.75 + 0.35 * hk.x) * (1.0 - 0.3 * smoothstep(-0.04, 0.0, box));
			col = mix(col, bc, sa);
			a = max(a, sa);
		}
		rough = 0.85;
	} else if (kind == 9) {
		// cracks: dark branching lines from the centre
		float d = 9.0;
		for (int k = 0; k < 4; k++) {
			float an = h12(vec2(sd + 9.0, float(k))) * 6.2832;
			vec2 prev = vec2(0.0);
			for (int s = 0; s < 4; s++) {
				an += (h12(vec2(sd, float(k * 4 + s))) - 0.5) * 1.2;
				vec2 nxt = prev + vec2(cos(an), sin(an)) * (0.2 + 0.1 * h12(vec2(sd + 2.0, float(k * 4 + s))));
				d = min(d, seg(q, prev, nxt) / (1.0 - float(s) * 0.2));
				prev = nxt;
			}
		}
		a = (1.0 - smoothstep(0.012, 0.012 + aa, d)) * 0.85;
		col = tint;
	} else if (kind == 10 || kind == 11 || kind == 12) {
		// soft patches: a sand drift / moss / a stain
		float n = fbm(q * 2.4 + sd);
		float r = length(q) + (n - 0.5) * 0.7;
		a = 1.0 - smoothstep(0.35, 0.95, r);
		if (kind == 10) {
			col = tint * (0.9 + 0.12 * sin(rot(q, sd).x * 26.0 + n * 6.0) + 0.08 * (vn(q * 30.0) - 0.5));
			a *= 0.92;
		} else if (kind == 11) {
			col = tint * (0.6 + 0.6 * vn(q * 22.0 + sd)) * (0.8 + 0.3 * n);
			a *= 0.9;
			rough = 0.95;
		} else {
			col = tint * (0.8 + 0.3 * n);
			a *= 0.55;
		}
	}
	if (a < 0.01) {
		discard;
	}
	ALBEDO = col;
	ALPHA = clamp(a * v_tint.a, 0.0, 1.0);
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = emis;
}
"""

## Grass tufts: wind sway, bent away from the pushers (actors and their fading trails).
const GRASS_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords;
uniform vec4 pushers[32];
uniform int pusher_count = 0;
uniform float wind = 0.07;
uniform float bend = 0.95;
varying float v_t;
varying vec3 v_col;
void vertex() {
	float t = UV.y;
	v_t = t;
	v_col = COLOR.rgb;
	vec3 root = MODEL_MATRIX[3].xyz;
	float hv = max(VERTEX.y - root.y, 0.0);
	float full = hv / max(t, 0.12);
	float ph = root.x * 0.37 + root.z * 0.23;
	vec2 wv = vec2(sin(TIME * 1.35 + ph) + 0.35 * sin(TIME * 2.9 + ph * 1.7), sin(TIME * 1.1 + ph * 1.31)) * wind;
	vec2 push = vec2(0.0);
	for (int i = 0; i < 32; i++) {
		if (i >= pusher_count) {
			break;
		}
		vec4 pu = pushers[i];
		vec2 d = VERTEX.xz - pu.xy;
		float dist = length(d);
		float f = pu.w * (1.0 - smoothstep(pu.z * 0.45, pu.z, dist));
		push += d / max(dist, 0.05) * f;
	}
	float pl = length(push);
	push = pl > 1.0 ? push / pl : push;
	float k = t * t;
	VERTEX.xz += (wv + push * bend) * k * full;
	VERTEX.y -= min(pl, 1.0) * 0.5 * k * full;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	vec3 c = v_col * mix(0.4, 1.12, v_t);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = c * 0.3;
}
"""

static var _ground_shaders := {}
static var _detail_shader: Shader = null
static var _grass_shader: Shader = null
static var _quad: Mesh = null
static var _tufts := {}

var world: Node = null
var detail_count := 0
var grass_count := 0
var grass_material: ShaderMaterial = null
var detail_material: ShaderMaterial = null
## [Vector2 pos, radius, time] trail points of moving actors.
var _trail: Array = []
## Actor instance id -> the position of its last trail point.
var _last: Dictionary = {}
var _clock := 0.0
## The pushers sent last frame (tests).
var last_pushers: PackedVector4Array = PackedVector4Array()


## The ground material for an act style ("forest", "desert", "gothic"); null for other styles.
static func ground_material(style: String) -> ShaderMaterial:
	if not style in ["forest", "desert", "gothic"]:
		return null
	if not _ground_shaders.has(style):
		var sh := Shader.new()
		sh.code = GROUND_SHADER.replace("%COMMON%", COMMON_GLSL).replace("shader_type spatial;", "shader_type spatial;\n#define STYLE_%s" % style.to_upper())
		_ground_shaders[style] = sh
	var m := ShaderMaterial.new()
	m.shader = _ground_shaders[style]
	return m


## Build the details and the grass of a layout under this node.
func build(p_world: Node, details: Array, grass: Array) -> void:
	world = p_world
	name = "GroundFx"
	_build_details(details)
	_build_grass(grass)
	set_process(grass_count > 0)


# ------------------------------------------------------------------ details

## details: [kind id, x, z, yaw, size x, size z, tint Color, lift] (WorldActGen.add_detail).
func _build_details(details: Array) -> void:
	detail_count = details.size()
	if details.is_empty():
		return
	if _detail_shader == null:
		_detail_shader = Shader.new()
		_detail_shader.code = DETAIL_SHADER.replace("%COMMON%", COMMON_GLSL)
	detail_material = ShaderMaterial.new()
	detail_material.shader = _detail_shader
	if _quad == null:
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.0, 1.0)
		_quad = pm
	var chunks := {}
	for d in details:
		var key := Vector2i(floori(float(d[1]) / CHUNK), floori(float(d[2]) / CHUNK))
		if not chunks.has(key):
			chunks[key] = []
		(chunks[key] as Array).append(d)
	for key in chunks:
		var list: Array = chunks[key]
		var cx := (float(key.x) + 0.5) * CHUNK
		var cz := (float(key.y) + 0.5) * CHUNK
		var buf := PackedFloat32Array()
		buf.resize(list.size() * 20)
		var o := 0
		for d in list:
			var yaw := float(d[3])
			var c := cos(yaw)
			var s := sin(yaw)
			var sx := float(d[4])
			var sz := float(d[5])
			var tint: Color = d[6]
			buf[o] = c * sx
			buf[o + 1] = 0.0
			buf[o + 2] = s * sz
			buf[o + 3] = float(d[1]) - cx
			buf[o + 4] = 0.0
			buf[o + 5] = 1.0
			buf[o + 6] = 0.0
			buf[o + 7] = DETAIL_LIFT + float(d[7])
			buf[o + 8] = -s * sx
			buf[o + 9] = 0.0
			buf[o + 10] = c * sz
			buf[o + 11] = float(d[2]) - cz
			buf[o + 12] = tint.r
			buf[o + 13] = tint.g
			buf[o + 14] = tint.b
			buf[o + 15] = tint.a
			buf[o + 16] = float(d[0])
			buf[o + 17] = fposmod(float(d[1]) * 0.137 + float(d[2]) * 0.071, 1.0)
			buf[o + 18] = 0.0
			buf[o + 19] = 0.0
			o += 20
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _quad
		mm.instance_count = list.size()
		mm.buffer = buf
		var mi := MultiMeshInstance3D.new()
		mi.name = "Details"
		mi.position = Vector3(cx, 0.0, cz)
		mi.multimesh = mm
		mi.material_override = detail_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = DETAIL_RANGE
		mi.visibility_range_end_margin = 8.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mi)


# ------------------------------------------------------------------ grass

## grass: [x, z, yaw, scale, tint Color, kind id] (WorldActGen.add_grass).
func _build_grass(grass: Array) -> void:
	grass_count = grass.size()
	if grass.is_empty():
		return
	if _grass_shader == null:
		_grass_shader = Shader.new()
		_grass_shader.code = GRASS_SHADER
	grass_material = ShaderMaterial.new()
	grass_material.shader = _grass_shader
	var chunks := {}
	for g in grass:
		var key := Vector3i(floori(float(g[0]) / CHUNK), floori(float(g[1]) / CHUNK), int(g[5]))
		if not chunks.has(key):
			chunks[key] = []
		(chunks[key] as Array).append(g)
	for key in chunks:
		var list: Array = chunks[key]
		var cx := (float(key.x) + 0.5) * CHUNK
		var cz := (float(key.y) + 0.5) * CHUNK
		var buf := PackedFloat32Array()
		buf.resize(list.size() * 16)
		var o := 0
		for g in list:
			var yaw := float(g[2])
			var sc := float(g[3])
			var c := cos(yaw) * sc
			var s := sin(yaw) * sc
			var tint: Color = g[4]
			buf[o] = c
			buf[o + 1] = 0.0
			buf[o + 2] = s
			buf[o + 3] = float(g[0]) - cx
			buf[o + 4] = 0.0
			buf[o + 5] = sc
			buf[o + 6] = 0.0
			buf[o + 7] = 0.0
			buf[o + 8] = -s
			buf[o + 9] = 0.0
			buf[o + 10] = c
			buf[o + 11] = float(g[1]) - cz
			buf[o + 12] = tint.r
			buf[o + 13] = tint.g
			buf[o + 14] = tint.b
			buf[o + 15] = 1.0
			o += 16
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = tuft_mesh(key.z)
		mm.instance_count = list.size()
		mm.buffer = buf
		var mi := MultiMeshInstance3D.new()
		mi.name = "Grass"
		mi.position = Vector3(cx, 0.0, cz)
		mi.multimesh = mm
		mi.material_override = grass_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = GRASS_RANGE
		mi.visibility_range_end_margin = 8.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		# The blades bend: grow the bounds so they are not culled while leaning out.
		mi.extra_cull_margin = 1.0
		add_child(mi)


## A grass tuft (kind 0: 9 thin blades ~0.45 m; kind 1: 6 tall reeds ~1.1 m), blades built from
## 3 segments and a tip; UV.y = height fraction (the shader bends by it).
static func tuft_mesh(kind: int) -> ArrayMesh:
	if _tufts.has(kind):
		return _tufts[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + kind * 31
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var blades := 16 if kind == 0 else 7
	for b in blades:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.24 if kind == 0 else 0.1)
		var base := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var yaw := rng.randf() * TAU
		var side := Vector3(cos(yaw), 0.0, sin(yaw))
		var lean := Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(0.1, 0.35) + Vector3(side.z, 0.0, -side.x) * rng.randf_range(-0.15, 0.15)
		var height := rng.randf_range(0.28, 0.55) if kind == 0 else rng.randf_range(0.8, 1.25)
		var width := rng.randf_range(0.028, 0.042) if kind == 0 else rng.randf_range(0.03, 0.045)
		var first := verts.size()
		for sgi in 3:
			var t := float(sgi) / 3.0
			var c := base + lean * height * t * t + Vector3.UP * height * t
			var wdt := width * (1.0 - t * 0.7)
			verts.append(c - side * wdt)
			verts.append(c + side * wdt)
			uvs.append(Vector2(0.0, t))
			uvs.append(Vector2(1.0, t))
		verts.append(base + lean * height + Vector3.UP * height)
		uvs.append(Vector2(0.5, 1.0))
		for sgi in 2:
			var a := first + sgi * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
		var l := first + 4
		idx.append_array([l, l + 1, first + 6])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_tufts[kind] = mesh
	return mesh


## Pushers each frame: the player and the monsters near them (plus the fading trail points they
## leave), nearest first, at most MAX_PUSHERS.
func _process(delta: float) -> void:
	if grass_material == null or world == null or not is_instance_valid(world):
		return
	_clock += delta
	var p := GameState.player
	if p == null or not is_instance_valid(p) or not world.is_ancestor_of(p) or not p.is_inside_tree():
		grass_material.set_shader_parameter("pusher_count", 0)
		return
	var focus := p.global_position
	var live: Array = []
	var actors: Array = [p]
	actors.append_array(EnemyDB.get_enemies(world as World))
	for a in actors:
		var act := a as Actor
		if act == null or act.dead or not act.is_inside_tree():
			continue
		var pos := act.global_position
		if CombatQuery.distance_xz(pos, focus) > PUSH_REACH:
			continue
		var r := clampf(act.get_collision_radius() * 1.7 + 0.35, 0.65, 3.2)
		live.append([Vector2(pos.x, pos.z), r, 1.0])
		var id := act.get_instance_id()
		var last: Variant = _last.get(id)
		if last == null or (last as Vector2).distance_to(Vector2(pos.x, pos.z)) > TRAIL_STEP:
			_trail.append([Vector2(pos.x, pos.z), r, _clock])
			_last[id] = Vector2(pos.x, pos.z)
	var keep: Array = []
	for t in _trail:
		var age := _clock - float(t[2])
		if age < TRAIL_LIFE:
			keep.append(t)
			var f := 1.0 - age / TRAIL_LIFE
			live.append([t[0], float(t[1]) * 0.85, f * f])
	_trail = keep
	var fxz := Vector2(focus.x, focus.z)
	live.sort_custom(func(x: Array, y: Array) -> bool:
		return (x[0] as Vector2).distance_squared_to(fxz) < (y[0] as Vector2).distance_squared_to(fxz))
	var n := mini(live.size(), MAX_PUSHERS)
	var arr := PackedVector4Array()
	arr.resize(MAX_PUSHERS)
	for i in n:
		var e: Array = live[i]
		var v: Vector2 = e[0]
		arr[i] = Vector4(v.x, v.y, float(e[1]), float(e[2]))
	last_pushers = arr.slice(0, n)
	grass_material.set_shader_parameter("pushers", arr)
	grass_material.set_shader_parameter("pusher_count", n)
