shader_type spatial;
render_mode cull_disabled;

uniform float wind_strength : hint_range(0.0, 1.0) = 0.25;
uniform float wind_speed = 3.5;
uniform vec4 cloth_color : source_color = vec4(0.8, 0.1, 0.1, 1.0);

void vertex() {
    float height_factor = UV.y; // 0 — плечи, 1 — низ (подол)
    float wave = sin(TIME * wind_speed + VERTEX.x * 3.0 + VERTEX.z * 3.0) * wind_strength * height_factor;
    VERTEX += NORMAL * wave;
}

void fragment() {
    ALBEDO = cloth_color.rgb;
    ROUGHNESS = 0.8;
}
