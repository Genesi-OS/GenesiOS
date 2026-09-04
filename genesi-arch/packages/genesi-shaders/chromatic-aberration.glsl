#version 300 es
precision highp float;

// Genesi — chromatic aberration. Colour fringing, strongest at the edges.

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

const float STRENGTH = 2.5;   // maximum fringe at the corners, in pixels

void main() {
    vec2 size = vec2(textureSize(tex, 0));
    vec2 texel = 1.0 / size;

    // A real lens splits colour more the further from its centre you look, so
    // the offset grows with distance rather than being applied flat. Applied
    // evenly it just looks like the screen is out of focus.
    vec2 dir = v_texcoord - 0.5;
    vec2 offset = dir * STRENGTH * texel * length(dir) * 2.0;

    float r = texture(tex, v_texcoord + offset).r;
    vec4 g = texture(tex, v_texcoord);
    float b = texture(tex, v_texcoord - offset).b;

    fragColor = vec4(r, g.g, b, g.a);
}
