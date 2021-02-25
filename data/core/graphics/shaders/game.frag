#version 330

layout(std140) uniform fsConstants
{
    vec2 zoom_to_world_params;
    float timer;
    float lutSize;
    vec2 resolution;
    float lutAlpha;
    float lightMul;
    float lightAdd;
    uint debugShowLut;
} _80;

uniform sampler2D gameview;
uniform sampler3D lut1;
uniform sampler2D lightmap;
uniform sampler2D detailLightmap;

in vec2 vUV;
layout(location = 0) out vec4 fragColor;

vec3 colorToLut16Index(vec3 inputColor)
{
    return (inputColor * 0.9375) + vec3(0.03125);
}

void main()
{
    vec2 uv = vUV;
    vec4 color = texture(gameview, uv);
    vec3 param = color.xyz;
    vec3 lookupIndex = colorToLut16Index(param);
    vec4 sunlitColor = vec4(textureLod(lut1, lookupIndex, 0.0).xyz, color.w);
    vec4 light = texture(lightmap, uv) + texture(detailLightmap, uv);
    light = clamp(light, vec4(0.0), vec4(1.0));
    vec3 _92 = (light.xyz * vec3(_80.lightMul)) + vec3(_80.lightAdd);
    light = vec4(_92.x, _92.y, _92.z, light.w);
    vec4 finalColor = mix(sunlitColor, color, light);
    fragColor = finalColor;
}

