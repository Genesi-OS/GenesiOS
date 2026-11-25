#version 300 es
precision highp float;

// Genesi — invert. Every colour flipped; readable on a bright page at night.

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    fragColor = vec4(1.0 - pixColor.rgb, pixColor.a);
}
