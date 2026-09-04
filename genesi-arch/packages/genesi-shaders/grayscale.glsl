#version 300 es
precision highp float;

// Genesi — grayscale. Colour removed, brightness kept.

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    // Rec. 709 luma weights: a plain average of R, G and B would make reds
    // look far brighter than they are and greens far darker.
    float luma = dot(pixColor.rgb, vec3(0.2126, 0.7152, 0.0722));
    fragColor = vec4(vec3(luma), pixColor.a);
}
