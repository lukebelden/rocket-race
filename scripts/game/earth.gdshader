shader_type canvas_item;
// Earth, drawn per pixel so it stays sharp from the huge horizon on the launch pad down to the
// ball you leave behind: oceans, continents, ice caps, drifting clouds, sun glint, a soft
// terminator and a glowing atmosphere around the edge. game.gd draws it on a square sprite
// centred on the planet; the sprite's half-width is `extent` planet radii (the extra is sky).

uniform float extent = 1.2;        // sprite half-size / planet radius (> 1: room for the atmosphere)
uniform float radius_px = 600.0;   // planet radius on screen, for a crisp anti-aliased edge
uniform vec3 light_dir = vec3(-0.5, -0.65, 0.58);  // towards the light; screen x right, y down, z out
uniform float light = 1.0;         // moonlight on the pad (dim) up to full sun in orbit
uniform float spin = 0.0;          // turns the globe (radians) as you climb
uniform vec4 atmo_color : source_color = vec4(0.42, 0.72, 1.0, 1.0);
uniform float opacity = 1.0;
uniform float limb = 0.75;         // how strongly the atmosphere tints the planet's edge (weak up close)

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		sum += amp * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		amp *= 0.5;
	}
	return sum;
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * extent;
	float d = length(p);
	float aa = 1.5 / radius_px;
	vec3 L = normalize(light_dir);
	float thick = extent - 1.0;

	// Atmosphere outside the disc: bright at the limb, fading out into the sky, lit on the
	// sun side.
	float out_d = max(d - 1.0, 0.0) / max(thick, 0.0001);
	float glow = exp(-out_d * 2.4) * (1.0 - smoothstep(0.7, 1.0, out_d));
	float side = clamp(dot(normalize(vec3(p, 0.25)), L) * 0.6 + 0.55, 0.12, 1.0);
	vec4 sky = vec4(atmo_color.rgb * (0.75 + 0.5 * side), glow * side * mix(0.8, 1.0, light));

	vec4 col = sky;
	if (d < 1.0 + aa) {
		float z = sqrt(max(1.0 - d * d, 0.0));
		vec3 n = vec3(p, z);
		float cs = cos(spin);
		float sn = sin(spin);
		vec3 q = vec3(n.x * cs + n.z * sn, n.y, -n.x * sn + n.z * cs);

		// Land and sea.
		float h = fbm(q * 1.9 + vec3(3.1, 1.7, 5.2), 6);
		float land = smoothstep(0.505, 0.525, h);
		float shore = smoothstep(0.43, 0.505, h) * (1.0 - land);
		vec3 deep = vec3(0.02, 0.10, 0.26);
		vec3 shallow = vec3(0.05, 0.30, 0.45);
		vec3 ocean = mix(deep, shallow, shore);
		float lat = abs(q.y);
		float dry = fbm(q * 3.3 + vec3(8.0), 4);
		vec3 green = mix(vec3(0.10, 0.30, 0.12), vec3(0.22, 0.40, 0.16), smoothstep(0.35, 0.65, dry));
		vec3 desert = vec3(0.62, 0.50, 0.30);
		float desert_amt = smoothstep(0.52, 0.62, dry) * (1.0 - smoothstep(0.45, 0.6, lat));
		vec3 ground = mix(green, desert, desert_amt);
		ground = mix(ground, vec3(0.42, 0.38, 0.33), smoothstep(0.6, 0.7, h));  // mountains
		vec3 surface = mix(ocean, ground, land);
		float ice = smoothstep(0.80, 0.86, lat + (h - 0.5) * 0.35);
		surface = mix(surface, vec3(0.88, 0.93, 0.97), ice);

		// Clouds drift slowly.
		float c = fbm(q * 3.4 + vec3(TIME * 0.015, 0.0, TIME * 0.008), 5);
		float cloud = smoothstep(0.50, 0.72, c) * 0.9;
		surface = mix(surface, vec3(0.95, 0.97, 1.0), cloud);

		// Light: soft terminator, sun glint on open water, and the bluish limb.
		float diff = dot(n, L);
		float lit = smoothstep(-0.15, 0.5, diff);
		vec3 shaded = surface * mix(0.06, 1.05, lit) * light;
		vec3 r = reflect(-L, n);
		float glint = pow(max(r.z, 0.0), 40.0) * (1.0 - land) * (1.0 - cloud) * lit;
		shaded += vec3(1.0, 0.95, 0.85) * glint * 0.5 * light;
		float fres = pow(1.0 - z, 2.5);
		shaded = mix(shaded, atmo_color.rgb * (0.4 + 0.8 * lit) * light, fres * limb);

		float edge = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, d);
		col = vec4(mix(sky.rgb, shaded, edge), max(edge, sky.a));
	}
	COLOR = vec4(col.rgb, col.a * opacity);
}
