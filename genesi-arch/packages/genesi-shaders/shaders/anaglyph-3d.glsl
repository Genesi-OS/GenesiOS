// Genesi — anaglyph 3D. Depth through red/cyan glasses.
#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

// Maximum separation between the two eyes, in screen pixels.
const float SEPARATION = 7.0;

void main() {
    vec2 size = vec2(textureSize(tex, 0));
    vec2 texel = 1.0 / size;

    // A desktop is a flat image: there is no second camera to take a right eye
    // from. Depth is therefore estimated from brightness -- bright areas read
    // as nearer -- and the two channels are separated by that estimate. It is
    // an illusion rather than real stereo, but it is the illusion red/cyan
    // glasses respond to, and it works on any window rather than only on
    // content shot in 3D.
    float luma = dot(texture(tex, v_texcoord).rgb, vec3(0.2126, 0.7152, 0.0722));
    float shift = (luma - 0.5) * SEPARATION;

    // Red eye looks one way, cyan eye the other.
    float r = texture(tex, v_texcoord + vec2(shift * texel.x, 0.0)).r;
    vec4 cyanSample = texture(tex, v_texcoord - vec2(shift * texel.x, 0.0));

    fragColor = vec4(r, cyanSample.g, cyanSample.b, cyanSample.a);
}
