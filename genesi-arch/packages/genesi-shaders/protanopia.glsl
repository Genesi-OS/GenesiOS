#version 300 es
precision highp float;

// Genesi — protanopia aid. Shifts red/green apart for red-blind vision.

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    vec3 c = pixColor.rgb;

    // Same approach as the deuteranopia shader, with the protanope matrix:
    // simulate, take the difference, and redistribute it into channels that
    // still carry information for this viewer.
    vec3 sim = vec3(
        dot(c, vec3(0.152286, 1.052583, -0.204868)),
        dot(c, vec3(0.114503, 0.786281, 0.099216)),
        dot(c, vec3(-0.003882, -0.048116, 1.051998)));

    vec3 err = c - sim;
    vec3 fix = vec3(
        0.0,
        err.r * 0.7 + err.g * 1.0,
        err.r * 0.7 + err.b * 1.0);

    fragColor = vec4(clamp(c + fix, 0.0, 1.0), pixColor.a);
}
