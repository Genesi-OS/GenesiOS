#version 300 es
precision highp float;

// Genesi — posterize. Colour flattened into a few bands, like a screen print.

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

const float LEVELS = 6.0;

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    vec3 c = floor(pixColor.rgb * LEVELS + 0.5) / LEVELS;
    fragColor = vec4(clamp(c, 0.0, 1.0), pixColor.a);
}
