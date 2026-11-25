#version 300 es
precision highp float;

// Genesi — sepia. The warm brown of an old photograph.

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

const float STRENGTH = 0.85;

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    vec3 c = pixColor.rgb;
    vec3 sepia = vec3(
        dot(c, vec3(0.393, 0.769, 0.189)),
        dot(c, vec3(0.349, 0.686, 0.168)),
        dot(c, vec3(0.272, 0.534, 0.131)));
    fragColor = vec4(mix(c, clamp(sepia, 0.0, 1.0), STRENGTH), pixColor.a);
}
