#version 330

layout(std140) uniform fsConstants
{
    float width;
    float height;
    float minIntensity;
    float maxIntensity;
    float uMul;
    float vMul;
} _33;

in vec2 vUV;
layout(location = 0) out vec4 fragColor;

float vignette(vec2 p)
{
    vec2 uv = p * (vec2(1.0) - p.yx);
    float vig = (uv.x * uv.y) * _33.minIntensity;
    return pow(abs(vig), _33.maxIntensity);
}

void main()
{
    vec2 param = vUV;
    float a = vignette(param);
    fragColor = vec4(0.0, 0.0, 0.0, 1.0 - a);
}

