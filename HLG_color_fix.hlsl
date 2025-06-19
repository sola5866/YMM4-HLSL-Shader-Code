Texture2D InputTexture : register(t0);
SamplerState InputSampler : register(s0);
cbuffer constants : register(b0)
{
    float time : packoffset(c0.x);
    float duration : packoffset(c0.y);
    float value0 : packoffset(c0.z);
    float value1 : packoffset(c0.w);
    float value2 : packoffset(c1.x);
    float value3 : packoffset(c1.y);
    float left : packoffset(c1.z);
    float top : packoffset(c1.w);
    float right : packoffset(c2.x);
    float bottom : packoffset(c2.y);
};

// リミテッドレンジ(16–235)→フルレンジ(0–255)変換
float4 LimitedToFull(float4 limited)
{
    limited.rgb = (limited.rgb * 255 - 16) / 219;
    return limited;
}

// BT.709 RGB→YUV変換
float4 RGBToYuvBT709(float4 color)
{
    float3 rgb = color.rgb;
    float Y = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b;
    float U = -0.1146 * rgb.r - 0.3854 * rgb.g + 0.5000 * rgb.b;
    float V = 0.5000 * rgb.r - 0.4542 * rgb.g - 0.0458 * rgb.b;
    return float4(Y, U, V, color.a);
}

// BT.2020 YUV→RGB変換
float4 YuvToRgbBT2020(float4 yuv)
{
    float Y = yuv.x, U = yuv.y, V = yuv.z;
    float R = Y + 1.4746 * V;
    float G = Y - 0.16455 * U - 0.57135 * V;
    float B = Y + 1.8814 * U;
    return float4(R, G, B, yuv.w);
}

// HLG EOTF
float HLGEOTF(float hlg)
{
    const float A = 0.17883277, B = 0.28466892, C = 0.55991073;
    hlg = max(hlg, 0.0);
    return saturate((hlg <= 0.5) ? pow(hlg, 2) / 3.0 : (exp((hlg - C) / A) + B) / 12.0);
}

// HLG→リニア変換（アルファはそのまま、value0は明るさ調整、value1はHLGのシステムガンマ）
float4 HLGToLinear(float4 hlg)
{
    const float gain = value0, sysGamma = value1;
    float3 hlgRgb = float3(HLGEOTF(hlg.r), HLGEOTF(hlg.g), HLGEOTF(hlg.b));
    float hlgY = dot(hlgRgb, float3(0.2627, 0.6780, 0.0593));
    return float4(pow(hlgY, sysGamma - 1.0) * hlgRgb * gain, hlg.a);
}

// BT.2020→BT.709変換（value3はフィルターの強度）
float4 BT2020ToBT709(float4 linearColor)
{
    const float4x4 M = float4x4(
        1.66049100, -0.58764114, -0.07284986, 0.0,
        -0.12455047, 1.13289990, -0.00834942, 0.0,
        -0.01815076, -0.10057890, 1.11872966, 0.0,
        0.0, 0.0, 0.0, 1.0);
    const float strength = value3;
    float4 filtered = mul(M, linearColor);
    return float4(lerp(linearColor.rgb, filtered.rgb, strength), linearColor.a);
}

// SDR OETF（value2 はSDRのガンマ）
float SDROETF(float sdr)
{
    return saturate(sdr == 0 ? 0 : pow(max(sdr, 0.0), 1 / value2));
}

// リニア→SDR変換（アルファはそのまま）
float4 LinearToSDR(float4 linearColor)
{
    return float4(SDROETF(linearColor.r), SDROETF(linearColor.g), SDROETF(linearColor.b), linearColor.a);
}

float4 main(float4 pos : SV_POSITION, float4 posScene : SCENE_POSITION, float4 uv : TEXCOORD0) : SV_Target
{
    float4 color = InputTexture.Sample(InputSampler, uv.xy);
    color = LimitedToFull(color);
    color = RGBToYuvBT709(color);
    color = YuvToRgbBT2020(color);
    color = HLGToLinear(color);
    color = BT2020ToBT709(color);
    color = LinearToSDR(color);
    return color;
}
