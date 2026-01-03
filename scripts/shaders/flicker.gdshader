shader_type canvas_item;

// Controls how fast the flicker happens
uniform float flicker_speed : hint_range(0.0, 50.0) = 20.0;
// Controls how dark the "cut out" gets (0.0 is transparent/black, 1.0 is no change)
uniform float minimum_brightness : hint_range(0.0, 1.0) = 0.5;
// Controls the "harshness" of the cut (high values = more like a digital stutter)
uniform float sharpness : hint_range(1.0, 20.0) = 10.0;

void fragment() {
    // Get the original texture color
    vec4 color = texture(TEXTURE, UV);

    // Create a rhythmic wave based on time
    // We use sin() to get a value between -1 and 1
    float wave = sin(TIME * flicker_speed);

    // Use the pow() function to make the flicker "sharper"
    // This creates those quick "blips" instead of a smooth fade
    float flicker = clamp(pow(abs(wave), sharpness), minimum_brightness, 1.0);

    // Apply the flicker to the color channels
    color.rgb *= flicker;

    COLOR = color;
}