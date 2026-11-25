#version 300 es
precision highp float;

// Genesi — vignette. Darkens the corners, like a camera lens.

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

const float RADIUS = 0.75;   // where the fade begins, 0 centre .. 1 corner
const float SOFTNESS = 0.45; // how gradual the fade is
const float STRENGTH = 0.55; // how dark the corners get

void main() {
    vec4 pixColor = texture(tex, v_texcoord);

    // Corrected for aspect, so the vignette is a circle on a wide screen
    // rather than an ellipse squashed to the monitor's shape.
    vec2 size = vec2(textureSize(tex, 0));
    float aspect = size.x / max(size.y, 1.0);
    vec2 centred = v_texcoord - 0.5;
    centred.x *= aspect;
    float dist = length(centred) / length(vec2(0.5 * aspect, 0.5));

    float fade = smoothstep(RADIUS, RADIUS + SOFTNESS, dist);
    fragColor = vec4(pixColor.rgb * (1.0 - fade * STRENGTH), pixColor.a);
}
