#version 330

uniform usampler2D tex;

in vec2 vUV;
layout(location = 0) out vec4 fragColor;
in vec4 vTintWith565Multiplier;

vec3 unpackRGB565(int rgb5)
{
    return vec3(ivec3(rgb5) & ivec3(63488, 2016, 31));
}

void main()
{
    if (dFdx(vUV).x <= 0.00048828125)
    {
        vec2 coord = floor(vUV * 2048.0);
        int rgb5 = int(texelFetch(tex, ivec2(coord), 0).x);
        int param = rgb5;
        vec3 _69 = unpackRGB565(param) * vTintWith565Multiplier.xyz;
        fragColor = vec4(_69.x, _69.y, _69.z, fragColor.w);
    }
    else
    {
        vec2 chunkID = floor(vUV * 64.0);
        vec2 pixelOffset = (vUV * 64.0) - chunkID;
        vec2 f = (pixelOffset * 32.0) - vec2(0.5);
        vec2 uv0 = floor(f);
        vec2 uv1 = uv0 + vec2(1.0);
        f -= uv0;
        uv0 = max(uv0, vec2(0.0));
        uv1 = min(uv1, vec2(31.0));
        uv0 += (chunkID * 32.0);
        uv1 += (chunkID * 32.0);
        int c00 = int(texelFetch(tex, ivec2(int(uv0.x), int(uv0.y)), 0).x);
        int c10 = int(texelFetch(tex, ivec2(int(uv1.x), int(uv0.y)), 0).x);
        int c01 = int(texelFetch(tex, ivec2(int(uv0.x), int(uv1.y)), 0).x);
        int c11 = int(texelFetch(tex, ivec2(int(uv1.x), int(uv1.y)), 0).x);
        int param_1 = c00;
        int param_2 = c10;
        int param_3 = c01;
        int param_4 = c11;
        vec3 c = mix(mix(unpackRGB565(param_1), unpackRGB565(param_2), vec3(f.x)), mix(unpackRGB565(param_3), unpackRGB565(param_4), vec3(f.x)), vec3(f.y));
        vec3 _200 = c * vTintWith565Multiplier.xyz;
        fragColor = vec4(_200.x, _200.y, _200.z, fragColor.w);
    }
    fragColor.w = vTintWith565Multiplier.w;
}

