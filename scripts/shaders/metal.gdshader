shader_type canvas_item;

// Parameters you can adjust in the Inspector
uniform vec4 base_color : source_color = vec4(0.6, 0.62, 0.65, 1.0); // Basic steel grey
uniform float shine_strength : hint_range(0.0, 1.0) = 0.2; // How bright the reflection is
uniform float grain_amount : hint_range(0.0, 1.0) = 0.05; // Texture roughness
uniform float texture_stretch : hint_range(1.0, 100.0) = 30.0; // Stretches noise to look like "brushed" metal
uniform float shine_speed : hint_range(0.0, 2.0) = 0.1; // Speed of the moving shine

// Random noise function
float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
    // 1. Create the "Brushed" texture
    // We stretch the UV coordinates in one direction to make the noise look like lines
    vec2 stretched_uv = UV;
    stretched_uv.x *= texture_stretch; 
    float noise_value = random(floor(stretched_uv));
    
    // 2. Create a moving shine (sheen)
    // This makes a diagonal light pass over the metal
    float sheen = sin((UV.x + UV.y) * 10.0 + TIME * shine_speed);
    sheen = smoothstep(0.0, 1.0, sheen); // Soften the edge of the shine
    
    // 3. Mix the colors
    vec4 final_color = base_color;
    
    // Darken areas based on noise (the grain)
    final_color.rgb -= noise_value * grain_amount; 
    
    // Add the shine
    final_color.rgb += sheen * shine_strength;
    
    COLOR = final_color;
}