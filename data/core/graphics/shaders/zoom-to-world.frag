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
    float vignetteIntensity;
    float vignetteSharpness;
    float borderSize;
    float borderOffset;
    float noiseIntensity;
    uint noiseMask;
    float horizontalLinesIntensity;
    uint horizontalLinesMask;
    float scanLinesFlickerIntensity;
    uint scanLinesFlickerMask;
    float saturation;
    uint saturationMask;
    uint colorMask;
    uint curved;
    vec4 color;
    float lineWidth;
    float guiScale;
    float brightness;
    float gapBetweenLinesWidth;
    float crtEffectIntensity;
    uint crtEffectMask;
} _105;

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

vec4 fetchPixel(vec2 uv)
{
    vec4 color = texture(gameview, uv);
    vec3 param = color.xyz;
    vec3 lookupIndex = colorToLut16Index(param);
    vec4 sunlitColor = vec4(textureLod(lut1, lookupIndex, 0.0).xyz, color.w);
    vec4 light = texture(lightmap, uv) + texture(detailLightmap, uv);
    light = clamp(light, vec4(0.0), vec4(1.0));
    vec3 _266 = (light.xyz * vec3(_105.lightMul)) + vec3(_105.lightAdd);
    light = vec4(_266.x, _266.y, _266.z, light.w);
    vec4 c = mix(sunlitColor, color, light);
    return c;
}

vec4 getColor(vec2 uv)
{
    vec2 param = uv;
    return fetchPixel(param);
}

float vignette(vec2 p, float intensity, float sharpness)
{
    vec2 uv = p * (vec2(1.0) - p.yx);
    float vig = (uv.x * uv.y) * intensity;
    return clamp(pow(abs(vig), sharpness), 0.0, 1.0);
}

mat3 saturationMatrix(float saturation)
{
    vec3 luminance = vec3(0.308600008487701416015625, 0.609399974346160888671875, 0.08200000226497650146484375);
    float oneMinusSat = 1.0 - saturation;
    vec3 red = vec3(luminance.x * oneMinusSat);
    red.x += saturation;
    vec3 green = vec3(luminance.y * oneMinusSat);
    green.y += saturation;
    vec3 blue = vec3(luminance.z * oneMinusSat);
    blue.z += saturation;
    return mat3(vec3(red), vec3(green), vec3(blue));
}

float hmix(float a, float b)
{
    return fract(sin((a * 12.98980045318603515625) + b) * 43758.546875);
}

float hash3(float a, float b, float c)
{
    float param = a;
    float param_1 = b;
    float ab = hmix(param, param_1);
    float param_2 = a;
    float param_3 = c;
    float ac = hmix(param_2, param_3);
    float param_4 = b;
    float param_5 = c;
    float bc = hmix(param_4, param_5);
    float param_6 = ac;
    float param_7 = bc;
    float param_8 = ab;
    float param_9 = hmix(param_6, param_7);
    return hmix(param_8, param_9);
}

vec3 getnoise3(vec2 p)
{
    float param = p.x;
    float param_1 = p.y;
    float param_2 = floor(_105.timer / 3.0);
    return vec3(hash3(param, param_1, param_2));
}

float stripes(vec2 uv)
{
    float width = _105.lineWidth;
    float offset = 0.0;
    float y = (uv.y * _105.resolution.y) + offset;
    y = floor(y / width);
    return float(uint(y) & 1u);
}

void main()
{
    vec2 uv = vUV;
    vec2 param = uv;
    vec4 finalColor = getColor(param);
    float a1 = 0.0;
    vec2 param_1 = uv;
    float param_2 = _105.vignetteIntensity;
    float param_3 = _105.vignetteSharpness;
    float a2 = 1.0 - vignette(param_1, param_2, param_3);
    a2 = clamp(a2 * _105.zoom_to_world_params.x, 0.0, 1.0);
    float intensity = a2;
    float param_4 = mix(1.0, _105.saturation, intensity);
    vec3 _345 = saturationMatrix(param_4) * finalColor.xyz;
    finalColor = vec4(_345.x, _345.y, _345.z, finalColor.w);
    vec2 cor;
    cor.x = gl_FragCoord.x / 1.0;
    cor.y = (gl_FragCoord.y + (1.5 * mod(floor(cor.x), 2.0))) / 3.0;
    vec2 ico = floor(cor);
    vec2 fco = fract(cor);
    vec3 pix = step(vec3(1.5), mod(vec3(0.0, 1.0, 2.0) + vec3(ico.x), vec3(3.0)));
    vec2 param_5 = ((ico * 1.0) * vec2(1.0, 3.0)) / _105.resolution;
    vec3 ima = getColor(param_5).xyz;
    vec3 col = pix * dot(pix, ima);
    col *= step(abs(fco.x - 0.5), 0.4000000059604644775390625);
    col *= step(abs(fco.y - 0.5), 0.4000000059604644775390625);
    col *= 1.2000000476837158203125;
    float t = a2;
    vec3 _432 = mix(finalColor.xyz, col, vec3(t * _105.crtEffectIntensity));
    finalColor = vec4(_432.x, _432.y, _432.z, finalColor.w);
    vec2 param_6 = uv;
    vec3 _446 = mix(finalColor.xyz, getnoise3(param_6), vec3(_105.noiseIntensity * a2));
    finalColor = vec4(_446.x, _446.y, _446.z, finalColor.w);
    vec2 param_7 = uv;
    float s = stripes(param_7);
    float t_1 = a2;
    vec3 _466 = finalColor.xyz * (1.0 + ((t_1 * _105.brightness) * (1.0 - s)));
    finalColor = vec4(_466.x, _466.y, _466.z, finalColor.w);
    vec3 _479 = finalColor.xyz * (1.0 - ((t_1 * _105.horizontalLinesIntensity) * s));
    finalColor = vec4(_479.x, _479.y, _479.z, finalColor.w);
    fragColor = finalColor;
}

