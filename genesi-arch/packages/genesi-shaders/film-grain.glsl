// Genesi — film grain. A fine static noise over the picture.
#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

const float AMOUNT = 0.055;

// Cheap hash. A screen shader runs on every pixel of every frame, so this is
// deliberately arithmetic rather than a texture lookup.
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    vec2 size = vec2(textureSize(tex, 0));

    // Seeded from the pixel, not from time: Hyprland gives the shader no clock,
    // and a grain that cannot animate is better still than one that flickers
    // between two frames at random.
    float n = hash(floor(v_texcoord * size)) - 0.5;

    // Grain is most visible in midtones and almost absent in blacks, the way
    // real film behaves.
    float luma = dot(pixColor.rgb, vec3(0.2126, 0.7152, 0.0722));
    float weight = 1.0 - abs(luma - 0.5) * 2.0;

    fragColor = vec4(clamp(pixColor.rgb + n * AMOUNT * weight, 0.0, 1.0), pixColor.a);
}
