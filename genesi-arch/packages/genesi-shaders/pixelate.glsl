#version 300 es
precision highp float;

// Genesi — pixelate. Snaps the screen to a coarse grid.

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

// Edge of one block, in screen pixels.
const float BLOCK = 6.0;

void main() {
    // Hyprland hands the shader no resolution uniform, so it comes from the
    // texture itself. Snapping in texel space rather than in 0..1 keeps blocks
    // square on any monitor and identical across a mixed-DPI desk.
    vec2 size = vec2(textureSize(tex, 0));
    vec2 blocks = size / BLOCK;
    vec2 snapped = (floor(v_texcoord * blocks) + 0.5) / blocks;
    fragColor = texture(tex, snapped);
}
