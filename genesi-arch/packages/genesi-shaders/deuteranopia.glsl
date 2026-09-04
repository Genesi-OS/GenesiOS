// Genesi — deuteranopia aid. Shifts red/green apart for green-blind vision.
#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    vec3 c = pixColor.rgb;

    // Simulate what a deuteranope sees (Machado et al. 2009), then push the
    // error back into channels they CAN separate. Simply recolouring the
    // screen would help one pair of colours and break another; correcting the
    // difference keeps everything else where it was.
    vec3 sim = vec3(
        dot(c, vec3(0.367322, 0.860646, -0.227968)),
        dot(c, vec3(0.280085, 0.672501, 0.047413)),
        dot(c, vec3(-0.011820, 0.042940, 0.968881)));

    vec3 err = c - sim;
    vec3 fix = vec3(
        0.0,
        err.r * 0.7 + err.g * 1.0,
        err.r * 0.7 + err.b * 1.0);

    fragColor = vec4(clamp(c + fix, 0.0, 1.0), pixColor.a);
}
