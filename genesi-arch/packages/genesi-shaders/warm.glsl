// Genesi — warm. A gentler evening tint than the full blue-light filter.
#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

const vec3 TINT = vec3(1.0, 0.94, 0.84);

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    vec3 c = pixColor.rgb * TINT;

    // Tinting alone dims the picture; put the lost brightness back so the
    // screen changes colour without appearing to lose contrast.
    float before = dot(pixColor.rgb, vec3(0.2126, 0.7152, 0.0722));
    float after = dot(c, vec3(0.2126, 0.7152, 0.0722));
    c *= before / max(after, 0.0001);

    fragColor = vec4(clamp(c, 0.0, 1.0), pixColor.a);
}
