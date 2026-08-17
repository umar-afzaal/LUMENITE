/*
        ========================================================================
        Copyright (c) Afzaal. All rights reserved.

    	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND
    	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    	MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    	IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    	CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    	TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    	SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

        ========================================================================

        GitHub     : https://github.com/umar-afzaal/LumeniteFX
        Discord    : https://discord.gg/deXJrW2dx6


        Filename   : lumenite_TRAA.fx
        Version    : 2026.07.28
        Author     : Afzaal (Kaidō)
        Description: Temporal Reprojection Anti-Aliasing
        License    : AGNYA License (https://github.com/nvb-uy/AGNYA-License)

        ========================================================================
*/

/*------------------.
| :: DEFINITIONS :: |
'------------------*/
#ifndef ENABLE_DLAA
    #define ENABLE_DLAA 1
#endif

/*--------------.
| :: HEADERS :: |
'--------------*/
#include "ReShade.fxh"
#include "./include/lumenite_ColorManagement.fxh"
#include "./include/lumenite_Helpers.fxh"

/*---------------.
| :: UNIFORMS :: |
'---------------*/
uniform int SHOW_STATUS <
    ui_type = "radio";
    ui_label = " ";
#if ENABLE_DLAA
    ui_text = "DLAA Prepass: Enabled.";
#else
    ui_text = "DLAA Prepass: Disabled.";
#endif
>;

#if ENABLE_DLAA
    uniform bool DEBUG_EDGES <
        ui_label = "Show Edge Mask";
        ui_tooltip = "Paints the detected edge mask over black background.";
    > = false;

    uniform int EDGE_MODE <
        ui_type = "combo";
        ui_label = "Edge Detection";
        ui_items = "Luma\0Geometric\0";
        ui_tooltip = "Luma: shading and texture edges as well; the classic DLAA mask.\n"
                     "Geometric: silhouettes only, ignores flat UI.";
    > = 0;
#endif

uniform float HISTORY_BLEND <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Temporal Blend";
    hidden = false;
> = 0.9;

uniform float SHARP_STRENGTH <
    ui_type = "drag";
    ui_min = 0; ui_max = 2.0; ui_step = 0.05;
    ui_label = "Adaptive Sharpen";
    hidden = false;
> = 1.0;

uniform float MAX_SHARP_DIFF <
    ui_type = "drag";
    ui_min = 0.05; ui_max = 0.25; ui_step = 0.01;
    ui_label = "Sharpen Guard";
    ui_tooltip = "Higher = more aggressive sharpening allowed.\nLower = tighter anti-ringing clamp.";
    hidden = true;
> = 0.1;

uniform float HFI_INTENSITY <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.1; ui_step = 0.001;
    ui_label = "High-Frequency Injection";
    ui_tooltip = "Re-injects detail lost during Temporal blend.";
> = 0.01;

/*--------------.
| :: IMPORTS :: |
'--------------*/
namespace Kernel {
    texture2D tFlow { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = RG16F; };
    sampler2D sFlow { Texture = tFlow; MagFilter = POINT; MinFilter = POINT; };

    texture2D tConfidence { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = R16F; };
    sampler2D sConfidence { Texture = tConfidence; };

    texture tNormals { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 4; };
    sampler sNormals { Texture = tNormals; };

    texture2D tDepth { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; MipLevels = 4; };
    sampler2D sDepth { Texture = tDepth; };
}

namespace LumeniteTRAA {
/*---------------------.
| :: RENDER TARGETS :: |
'---------------------*/
#if ENABLE_DLAA
texture tDLAAPreFilter { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sDLAAPreFilter { Texture = tDLAAPreFilter; MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = LINEAR; };

texture tDLAAPrePass { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sDLAAPrePass { Texture = tDLAAPrePass; MagFilter = POINT; MinFilter = POINT; };
#endif

texture tCurrHistory { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sCurrHistory { Texture = tCurrHistory; MagFilter = LINEAR; MinFilter = LINEAR; MipFilter = LINEAR; };

texture tPrevHistory { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sPrevHistory { Texture = tPrevHistory; MagFilter = LINEAR; MinFilter = LINEAR; MipFilter = LINEAR; };

/*--------------.
| :: HELPERS :: |
'--------------*/
//5-Tap 2D Catmull-Rom Filter (Brian Karis / Unreal Engine)
float3 SampleCatmullRom5Tap(sampler tex, float2 uv) {
    float2 pos = uv * float2(BUFFER_WIDTH, BUFFER_HEIGHT);
    float2 centerPos = floor(pos - 0.5) + 0.5;
    float2 f = pos - centerPos;

    //1D Catmull-Rom weights
    float2 f2 = f * f;
    float2 f3 = f2 * f;

    float2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    float2 w1 = 1.0 + f2 * (-2.5 + 1.5 * f);
    float2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    float2 w3 = f2 * (-0.5 + 0.5 * f);

    //group the inner positive lobes (w1, w2) for bilinear hardware
    float2 w12 = w1 + w2;
    float2 offset12 = w2 / (w12 + 0.00001); // Prevent div by zero

    //5-tap texture fetch in a cross pattern
    float2 texCoord0 = (centerPos - float2(1.0, 0.0) + float2(0.0, offset12.y)) * BUFFER_PIXEL_SIZE; //left
    float2 texCoord1 = (centerPos + float2(2.0, 0.0) + float2(0.0, offset12.y)) * BUFFER_PIXEL_SIZE; //right
    float2 texCoord2 = (centerPos + float2(offset12.x, -1.0)) * BUFFER_PIXEL_SIZE;                   //top
    float2 texCoord3 = (centerPos + float2(offset12.x, 2.0)) * BUFFER_PIXEL_SIZE;                    //bottom
    float2 texCoord4 = (centerPos + offset12) * BUFFER_PIXEL_SIZE;                                   //center

    //final 2D weights for the 5 taps
    float weight0 = w0.x  * w12.y; //left
    float weight1 = w3.x  * w12.y; //right
    float weight2 = w12.x * w0.y;  //top
    float weight3 = w12.x * w3.y;  //bottom
    float weight4 = w12.x * w12.y; //center

    //normalize weights because we dropped the 4 corner taps (sum would be slightly < 1.0)
    float weightSum = weight0 + weight1 + weight2 + weight3 + weight4;
    weightSum = max(weightSum, 0.0001);
    weight0 /= weightSum;
    weight1 /= weightSum;
    weight2 /= weightSum;
    weight3 /= weightSum;
    weight4 /= weightSum;

    //sample w. hw bilinear filtering (offsets take care of the interpolation)
    float3 color0 = tex2Dlod(tex, float4(texCoord0, 0, 0)).rgb;
    float3 color1 = tex2Dlod(tex, float4(texCoord1, 0, 0)).rgb;
    float3 color2 = tex2Dlod(tex, float4(texCoord2, 0, 0)).rgb;
    float3 color3 = tex2Dlod(tex, float4(texCoord3, 0, 0)).rgb;
    float3 color4 = tex2Dlod(tex, float4(texCoord4, 0, 0)).rgb;

    float3 result = color0 * weight0 + color1 * weight1 + color2 * weight2 + color3 * weight3 + color4 * weight4;
    //anti-ringing clamp
    float3 minColor = min(min(min(color0, color1), min(color2, color3)), color4);
    float3 maxColor = max(max(max(color0, color1), max(color2, color3)), color4);
    return clamp(result, minColor, maxColor);
}

//if ray misses the bounding box (tEnter > tExit), returning t = 1.0 is the safe fallback
float3 YCoCgLineBoxClip(float3 historyYCoCg, float3 meanYCoCg, float3 colorMin, float3 colorMax) {
    float3 rayDir = meanYCoCg - historyYCoCg;

    rayDir = abs(rayDir) < 0.0001 ? float3(0.0001, 0.0001, 0.0001) : rayDir; //avoid div by zero

    //compute t for intersection with min and max bounds per-channel
    float3 tMin = (colorMin - historyYCoCg) / rayDir;
    float3 tMax = (colorMax - historyYCoCg) / rayDir;

    float3 t1 = min(tMin, tMax);
    float3 t2 = max(tMin, tMax);
    tMin = t1;
    tMax = t2;

    //entry and exit points for ray-box intersection
    float tEnter = max(max(tMin.x, tMin.y), tMin.z);
    float tExit = min(min(tMax.x, tMax.y), tMax.z);

    //if ray misses the box; fallback to 1.0 (mean) to discard history
    //else, clamp the entry point to [0, 1] to clip exactly at the box edge
    float t = tEnter > tExit ? 1.0 : clamp(tEnter, 0.0, 1.0);

    return historyYCoCg + rayDir * t;
}

/*--------------.
| :: SHADERS :: |
'--------------*/
#if ENABLE_DLAA

float4 PS_DLAAPreFilter(float4 vpos : SV_Position, float2 uv : TexCoord) : SV_Target {
    float3 center = sqrt(max(GetLinearColor(uv, false), 0.0));
    float edge;
    if (!EDGE_MODE) {
        //luma edge in perceptual space; the extra sqrt fattens the mask
        float2 px = float2(BUFFER_PIXEL_SIZE.x, 0.0);
        float2 py = float2(0.0, BUFFER_PIXEL_SIZE.y);
        float3 left   = sqrt(max(GetLinearColor(uv - px, false), 0.0));
        float3 right  = sqrt(max(GetLinearColor(uv + px, false), 0.0));
        float3 top    = sqrt(max(GetLinearColor(uv - py, false), 0.0));
        float3 bottom = sqrt(max(GetLinearColor(uv + py, false), 0.0));
        float3 edges = 4.0 * abs((left + right + top + bottom) - 4.0 * center);
        edge = GetLuminance(sqrt(max(edges, 0.0))); //recursive gamma compression: do another sqrt(), fattens the edge mask
    } else {
        float4 s0 = tex2Dlod(Kernel::sNormals, float4(uv + BUFFER_PIXEL_SIZE * float2(-1,-1), 0, 0));
        float4 s1 = tex2Dlod(Kernel::sNormals, float4(uv + BUFFER_PIXEL_SIZE * float2( 0,-1), 0, 0));
        float4 s2 = tex2Dlod(Kernel::sNormals, float4(uv + BUFFER_PIXEL_SIZE * float2( 1,-1), 0, 0));
        float4 s3 = tex2Dlod(Kernel::sNormals, float4(uv + BUFFER_PIXEL_SIZE * float2(-1, 0), 0, 0));
        float4 s4 = tex2Dlod(Kernel::sNormals, float4(uv,                      0, 0));
        float4 s5 = tex2Dlod(Kernel::sNormals, float4(uv + BUFFER_PIXEL_SIZE * float2( 1, 0), 0, 0));
        float4 s6 = tex2Dlod(Kernel::sNormals, float4(uv + BUFFER_PIXEL_SIZE * float2(-1, 1), 0, 0));
        float4 s7 = tex2Dlod(Kernel::sNormals, float4(uv + BUFFER_PIXEL_SIZE * float2( 0, 1), 0, 0));
        float4 s8 = tex2Dlod(Kernel::sNormals, float4(uv + BUFFER_PIXEL_SIZE * float2( 1, 1), 0, 0));

        //3x3 depth Sobel
        float dC = s4.a;
        float sxD = -s0.a + s2.a - 2.0 * s3.a + 2.0 * s5.a - s6.a + s8.a;
        float syD = -s0.a - 2.0 * s1.a - s2.a + s6.a + 2.0 * s7.a + s8.a;
        float depthEdge = saturate(sqrt(sxD * sxD + syD * syD) / (dC + 1e-5));

        //3x3 normal Sobel
        float3 sxN = -s0.xyz + s2.xyz - 2.0 * s3.xyz + 2.0 * s5.xyz - s6.xyz + s8.xyz;
        float3 syN = -s0.xyz - 2.0 * s1.xyz - s2.xyz + s6.xyz + 2.0 * s7.xyz + s8.xyz;
        float normalEdge = saturate(length(sxN) + length(syN));

        edge = max(depthEdge, normalEdge);
    }
    return float4(center, edge);
}

#define SAMPLE_G(uv, dx, dy) tex2Dlod(sDLAAPreFilter, float4((uv) + float2(dx, dy) * BUFFER_PIXEL_SIZE, 0, 0))
float4 PS_DLAA(float4 vpos : SV_Position, float2 uv : TexCoord) : SV_Target {
    float4 center   = SAMPLE_G(uv,  0.0,  0.0);
    float4 left01   = SAMPLE_G(uv, -1.5,  0.0);
    float4 right01  = SAMPLE_G(uv,  1.5,  0.0);
    float4 top01    = SAMPLE_G(uv,  0.0, -1.5);
    float4 bottom01 = SAMPLE_G(uv,  0.0,  1.5);

    //flat-region early exit
    float localEdges = max(center.a, max(max(left01.a, right01.a), max(top01.a, bottom01.a)));
    if (localEdges < 0.05) return float4(center.xyz * center.xyz, 1.0);

    float4 wH = 2.0 * (left01 + right01);
    float4 wV = 2.0 * (top01  + bottom01);

    float4 edgeH = abs(wH - 4.0 * center) / 4.0;
    float4 edgeV = abs(wV - 4.0 * center) / 4.0;

    float4 blurredH = (wH + 2.0 * center) / 6.0;
    float4 blurredV = (wV + 2.0 * center) / 6.0;

    float edgeHLum    = GetLuminance(edgeH.xyz);
    float edgeVLum    = GetLuminance(edgeV.xyz);
    float blurredHLum = GetLuminance(blurredH.xyz);
    float blurredVLum = GetLuminance(blurredV.xyz);

    const float kLambda = 3.0;
    const float kEpsilon = 0.1;
    float edgeMaskH = saturate((kLambda * edgeHLum - kEpsilon) / (blurredVLum + 1e-5));
    float edgeMaskV = saturate((kLambda * edgeVLum - kEpsilon) / (blurredHLum + 1e-5));

    float gate = (!EDGE_MODE) ? 1.0 : center.a;
    edgeMaskH *= gate;
    edgeMaskV *= gate;

    float4 clr = center;
    clr = lerp(clr, blurredH, edgeMaskV);
    clr = lerp(clr, blurredV, edgeMaskH * 0.5);

    //skip unnecessary work on long-edges
    if (localEdges > 0.5) {
        float4 h0 = right01;
        float4 h1 = SAMPLE_G(uv,  3.5,  0.0);
        float4 h2 = SAMPLE_G(uv,  5.5,  0.0);
        float4 h3 = SAMPLE_G(uv,  7.5,  0.0);
        float4 h4 = left01;
        float4 h5 = SAMPLE_G(uv, -3.5,  0.0);
        float4 h6 = SAMPLE_G(uv, -5.5,  0.0);
        float4 h7 = SAMPLE_G(uv, -7.5,  0.0);

        float4 v0 = bottom01;
        float4 v1 = SAMPLE_G(uv,  0.0,  3.5);
        float4 v2 = SAMPLE_G(uv,  0.0,  5.5);
        float4 v3 = SAMPLE_G(uv,  0.0,  7.5);
        float4 v4 = top01;
        float4 v5 = SAMPLE_G(uv,  0.0, -3.5);
        float4 v6 = SAMPLE_G(uv,  0.0, -5.5);
        float4 v7 = SAMPLE_G(uv,  0.0, -7.5);

        float longEdgeMaskH = (h0.a + h1.a + h2.a + h3.a + h4.a + h5.a + h6.a + h7.a) / 8.0;
        float longEdgeMaskV = (v0.a + v1.a + v2.a + v3.a + v4.a + v5.a + v6.a + v7.a) / 8.0;

        longEdgeMaskH = saturate(longEdgeMaskH * 2.0 - 1.0);
        longEdgeMaskV = saturate(longEdgeMaskV * 2.0 - 1.0);

        if (abs(longEdgeMaskH - longEdgeMaskV) > 0.2) {
            float4 left   = SAMPLE_G(uv, -1.0,  0.0);
            float4 right  = SAMPLE_G(uv,  1.0,  0.0);
            float4 top    = SAMPLE_G(uv,  0.0, -1.0);
            float4 bottom = SAMPLE_G(uv,  0.0,  1.0);

            float4 longBlurredH = (h0 + h1 + h2 + h3 + h4 + h5 + h6 + h7) / 8.0;
            float4 longBlurredV = (v0 + v1 + v2 + v3 + v4 + v5 + v6 + v7) / 8.0;

            float lbHLum = GetLuminance(longBlurredH.xyz);
            float lbVLum = GetLuminance(longBlurredV.xyz);

            float centerLum = GetLuminance(center.xyz);
            float leftLum   = GetLuminance(left.xyz);
            float rightLum  = GetLuminance(right.xyz);
            float topLum    = GetLuminance(top.xyz);
            float bottomLum = GetLuminance(bottom.xyz);

            float4 clrV = center;
            float4 clrH = center;

            float hx = saturate(0.0 + (lbHLum - topLum)    / (centerLum - topLum    + 1e-6));
            float hy = saturate(1.0 + (lbHLum - centerLum) / (centerLum - bottomLum + 1e-6));
            float vx = saturate(0.0 + (lbVLum - leftLum)   / (centerLum - leftLum   + 1e-6));
            float vy = saturate(1.0 + (lbVLum - centerLum) / (centerLum - rightLum  + 1e-6));

            float4 vhxy = float4(vx, vy, hx, hy);
            vhxy.x = (vhxy.x == 0.0) ? 1.0 : vhxy.x;
            vhxy.y = (vhxy.y == 0.0) ? 1.0 : vhxy.y;
            vhxy.z = (vhxy.z == 0.0) ? 1.0 : vhxy.z;
            vhxy.w = (vhxy.w == 0.0) ? 1.0 : vhxy.w;

            clrV = lerp(left,   clrV, vhxy.x);
            clrV = lerp(right,  clrV, vhxy.y);
            clrH = lerp(top,    clrH, vhxy.z);
            clrH = lerp(bottom, clrH, vhxy.w);

            clr = lerp(clr, clrV, longEdgeMaskV);
            clr = lerp(clr, clrH, longEdgeMaskH);
        }
    }

    //highlight protection
    float4 r0 = SAMPLE_G(uv, -1.5, -1.5);
    float4 r1 = SAMPLE_G(uv,  1.5, -1.5);
    float4 r2 = SAMPLE_G(uv, -1.5,  1.5);
    float4 r3 = SAMPLE_G(uv,  1.5,  1.5);
    float4 r = (4.0 * (r0 + r1 + r2 + r3) + center + top01 + bottom01 + left01 + right01) / 25.0;

    float mask = saturate(r.a * 3.0 - 2.0);
    clr = lerp(clr, center, mask);

    return float4(clr.xyz * clr.xyz, 1.0); //store linear color here!
}

#endif

float4 PS_TRAA(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {
    //3x3 neighborhood from DLAA prepass
    static const float2 offsets[9] = {
        float2(-1, -1), float2(0, -1), float2(1, -1),
        float2(-1, 0) , float2(0, 0) , float2(1, 0),
        float2(-1, 1) , float2(0, 1) , float2(1, 1)
    };
    float3 samples[9];
    float3 samplesYCoCg[9];
    float3 meanYCoCg = float3(0, 0, 0);

    for (int i = 0; i < 9; i++) {
        float2 samplePos = texcoord + BUFFER_PIXEL_SIZE * offsets[i];
        #if ENABLE_DLAA
            samples[i] = tex2Dlod(sDLAAPrePass, float4(samplePos, 0, 0)).rgb;
        #else
            samples[i] = GetLinearColor(samplePos, false);
        #endif
        samplesYCoCg[i] = linearToYCoCg(samples[i]);
        meanYCoCg += samplesYCoCg[i];
    }
    meanYCoCg /= 9.0;

    //standard deviation per channel
    float3 stddev = float3(0, 0, 0);
    for (int i = 0; i < 9; i++) {
        float3 diff = samplesYCoCg[i] - meanYCoCg;
        stddev += diff * diff;
    }
    stddev = sqrt(stddev / 9.0);

    //variance-scaled bounding box in YCoCg
    float3 colorMin = meanYCoCg - stddev * 1.25;
    float3 colorMax = meanYCoCg + stddev * 1.25;

    float2 flow = tex2D(Kernel::sFlow, texcoord).xy;
    float confidence = tex2D(Kernel::sConfidence, texcoord).x;
    confidence = saturate(confidence + 0.11 * 4.0 * confidence * (1.0 - confidence));

    float2 historyUV = texcoord + flow;
    historyUV = clamp(historyUV, BUFFER_PIXEL_SIZE, 1.0 - BUFFER_PIXEL_SIZE);
    float3 historyRGB = SampleCatmullRom5Tap(sPrevHistory, historyUV);
    float3 historyYCoCg = linearToYCoCg(historyRGB);

    //clip history to current neighborhood bounds via line-box intersection
    float3 clippedHistoryYCoCg = YCoCgLineBoxClip(historyYCoCg, meanYCoCg, colorMin, colorMax);

    //re-inject current pixel's detail into clipped history
    float3 centerYCoCg = samplesYCoCg[4]; //blend against the center pixel (index 4 of the 3x3 grid)
    float3 injectedHistory = clippedHistoryYCoCg + (centerYCoCg - meanYCoCg) * HFI_INTENSITY;

    //blend clipped history with current in YCoCg space
    float blendVal = min(0.98, HISTORY_BLEND);
    float3 blendedYCoCg = lerp(centerYCoCg, injectedHistory, confidence * blendVal);
    float3 output = YCoCgToLinear(blendedYCoCg);
    return float4(output, 1.0);
}

float4 PS_ToDisplay(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {
    #if ENABLE_DLAA

    if (DEBUG_EDGES) {
        float edgeDbg = tex2D(sDLAAPreFilter, texcoord).a;
        static const float3 edgeTint = float3(0.125, 0.698, 0.667) * float3(0.125, 0.698, 0.667); //target color squared so lands on the real hue
        return float4(ToOutputColorspace(edgeTint * saturate(edgeDbg), false), 1.0);
    }

    #endif

    float3 c = tex2D(sCurrHistory, texcoord).rgb;
    float3 sharpened = c;

    if (SHARP_STRENGTH > 0) {
        float2 off = BUFFER_PIXEL_SIZE * 0.5;

        float3 ne = tex2D(sCurrHistory, texcoord + float2( off.x,  off.y)).rgb;
        float3 sw = tex2D(sCurrHistory, texcoord + float2(-off.x, -off.y)).rgb;
        float3 se = tex2D(sCurrHistory, texcoord + float2( off.x, -off.y)).rgb;
        float3 nw = tex2D(sCurrHistory, texcoord + float2(-off.x,  off.y)).rgb;

        //bounds for the neighborhood
        float3 local_min = min(min(min(ne, nw), min(se, sw)), c);
        float3 local_max = max(max(max(ne, nw), max(se, sw)), c);

        //high-pass
        float3 diag_max = max(max(ne, nw), max(se, sw));
        float3 diag_min = min(min(ne, nw), min(se, sw));
        float3 diff_rgb = 2.0 * c + (ne + nw + se + sw) - 3.0 * (diag_max + diag_min);

        static const float3 luma_weight = float3(0.2126, 0.7152, 0.0722);
        float luma_c = dot(c, luma_weight);
        float luma_diff = dot(diff_rgb, luma_weight);

        //rational limit
        float max_allowed = MAX_SHARP_DIFF * (luma_c + 0.1);
        luma_diff = luma_diff / (rcp(SHARP_STRENGTH) + abs(luma_diff) / max(max_allowed, 0.001));

        //lower epsilon (0.005) for more dark-area detail
        float ratio = (luma_c + luma_diff) / max(luma_c, 0.005);

        //allow up to 3x brightness for extreme highlights
        ratio = clamp(ratio, 0.3, 3.0);
        sharpened = c * ratio;

        //anti-ringing
        //instead of clamping strictly to min/max, we allow a 20% overshoot
        //perceived "sharpness" while capping fireflies
        float3 overshoot_min = local_min * 0.8;
        float3 overshoot_max = local_max * 1.2;

        sharpened = clamp(sharpened, overshoot_min, overshoot_max);
    }

    return float4(ToOutputColorspace(sharpened, false), 1.0);
}

float4 PS_StoreHistory(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {
    float3 taaResult = tex2D(sCurrHistory, texcoord).rgb;
    return float4(taaResult, 1.0);
}

/*----------------.
| :: TECHNIQUE :: |
'----------------*/

technique Lumenite_TRAA <
    ui_label = "LUMENITE: TRAA";
    ui_tooltip = "Temporal Reprojection Anti-Aliasing.";
>
{
#if ENABLE_DLAA
    pass { VertexShader = PostProcessVS; PixelShader = PS_DLAAPreFilter; RenderTarget = tDLAAPreFilter; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_DLAA;          RenderTarget = tDLAAPrePass;   } //spatial filter
#endif
    pass { VertexShader = PostProcessVS; PixelShader = PS_TRAA;          RenderTarget = tCurrHistory;   } //temporal filter
    pass { VertexShader = PostProcessVS; PixelShader = PS_ToDisplay;                                    }
    pass { VertexShader = PostProcessVS; PixelShader = PS_StoreHistory;  RenderTarget = tPrevHistory;   }
}

}
