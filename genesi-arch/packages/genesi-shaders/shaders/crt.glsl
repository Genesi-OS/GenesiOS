// Genesi — CRT. Scanlines, a phosphor mask and curved glass.
#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

const float CURVATURE = 0.06;   // barrel distortion; 0 is a flat panel
const float SCANLINE = 0.18;    // how dark the gaps between lines are
const float MASK = 0.10;        // strength of the RGB phosphor stripes
const float BRIGHTEN = 1.15;    // scanlines cost light; give some back

void main() {
    vec2 size = vec2(textureSize(tex, 0));

    // Bend the screen outwards from the centre.
    vec2 uv = v_texcoord * 2.0 - 1.0;
    vec2 offset = uv.yx * uv.yx * uv * CURVATURE;
    uv += offset;
    uv = uv * 0.5 + 0.5;

    // Past the edge of the curved glass there is no picture, only the bezel.
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    vec4 pixColor = texture(tex, uv);
    vec3 c = pixColor.rgb * BRIGHTEN;

    // One dark line every other physical row.
    float line = mod(uv.y * size.y, 2.0);
    c *= 1.0 - SCANLINE * step(1.0, line);

    // Vertical phosphor stripes: each screen column leans red, green or blue.
    float stripe = mod(uv.x * size.x, 3.0);
    vec3 mask = vec3(
        stripe < 1.0 ? 1.0 : 1.0 - MASK,
        (stripe >= 1.0 && stripe < 2.0) ? 1.0 : 1.0 - MASK,
        stripe >= 2.0 ? 1.0 : 1.0 - MASK);
    c *= mask;

    fragColor = vec4(clamp(c, 0.0, 1.0), pixColor.a);
}
