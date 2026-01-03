shader_type canvas_item;

uniform float speed = 0.3;
uniform vec4 color_a : source_color = vec4(1.0, 0.5, 0.8, 1.0);
uniform vec4 color_b : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform vec4 color_c : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float scale = 2.5;

void fragment() {
    // 1. Calculate the wave pattern (same as before)
    vec2 center = UV - vec2(0.5);
    float dist = length(center) * scale;
    float t = 0.5 + 0.5 * sin(dist - TIME * speed);
    vec4 wave_color = mix(color_a, color_b, t);

    // 2. Apply the wave color to the existing StyleBox color.
    // 'COLOR' is what the Panel is trying to draw (your white border).
    // By multiplying, we keep the Alpha (transparency) of the center,
    // and tint the white border with our wave.
    COLOR = COLOR * wave_color;
}