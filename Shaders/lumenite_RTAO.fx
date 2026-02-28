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


        Filename   : lumenite_RTAO.fx
        Version    : 2026.02.28
        Author     : Afzaal (Kaidō)
        Description: Ray Traced Ambient Occlusion.
        License    : AGNYA License (https://github.com/nvb-uy/AGNYA-License)

        ========================================================================
*/

#include "ReShade.fxh"
#include "./include/lumenite_Projections.fxh"
#include "./include/lumenite_Helpers.fxh"
#include "./include/lumenite_ColorManagement.fxh"

/*------------------.
| :: DEFINITIONS :: |
'------------------*/

#ifndef RESOLUTION_SCALING
  #define RESOLUTION_SCALING 1
#endif

#define INITIAL_STEP_SCALE 0.9 //how small the very first step is (as a fraction of the avg. step size).
#define STEP_GROWTH_FACTOR 1.2
#define AO_MAX_MARCH_STEPS 15
#define AO_RADIUS 0.02
#define ATROUS_DEPTH_WEIGHT_SCALE 800.0
#define ATROUS_NORMAL_WEIGHT_SCALE 13.0

#if RESOLUTION_SCALING
    #define ATROUS_DILATION_1 2
    #define ATROUS_DILATION_2 4
#else
    #define ATROUS_DILATION_1 1
    #define ATROUS_DILATION_2 2
#endif

/*---------------.
| :: UNIFORMS :: |
'---------------*/

uniform bool DEBUG_VIEW <
    ui_label = "Show AO Mask";
    ui_tooltip = "Debug view for the AO. Shows raw AO.";
    ui_category = "Ambient Occlusion";
> = 0;

uniform bool CHECKERBOARD_RENDERING <
    ui_label = "Half-framerate AO Rendering";
    ui_tooltip = "Skips half the pixels to render faster. Minor temporal lag of the AO Mask.";
    ui_category = "Ambient Occlusion";
> = 1;

uniform float DEPTH_BOUNDARY <
    ui_type = "slider";
    ui_min = 0.001; ui_max = 0.999; ui_step = 0.001;
    ui_label = "AO Range";
    ui_tooltip = "The Z+ range/depth in which the effect is applied.";
    ui_category = "Ambient Occlusion";
    hidden = false;
> = 0.6;

uniform float DEPTH_FADE_START <
    ui_type = "slider";
    ui_min = 0.1; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Z+ Fade Start (%)";
    ui_tooltip = "Z+ fraction where effect starts fading out (relative to AO Range)";
    ui_category = "Ambient Occlusion";
    hidden = true;
> = 0.75;

uniform float AO_INTENSITY <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0;
    ui_label = "AO Strength";
    ui_tooltip = "Controls the intensity of the ambient occlusion effect.";
    ui_category = "Ambient Occlusion";
> = 1.0;

uniform int USER_GUIDE <
ui_type = "radio";
    ui_category = "";
    ui_label = " ";
    ui_text =  "RESOLUTION_SCALING:\n0: Renders AO at full-resolution.\n1: Renders AO at half-resolution.";
>;

/*--------------.
| :: IMPORTS :: |
'--------------*/

//===optical flow
texture2D tLumaFlow { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = RG16F; };
sampler2D sLumaFlow { Texture = tLumaFlow; MagFilter = POINT; MinFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP; };

texture2D tFlowConfidence { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = R16F; };
sampler2D sFlowConfidence { Texture = tFlowConfidence; MagFilter = POINT; MinFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP; };

//===surface normals
texture tKernelNormals { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sKernelNormals { Texture = tKernelNormals; };

namespace LumeniteRTAO {

/*---------------------.
| :: RENDER TARGETS :: |
'---------------------*/

#if RESOLUTION_SCALING
    texture tAOTrace { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = R16F; };
    sampler sAOTrace { Texture = tAOTrace; AddressU = CLAMP; AddressV = CLAMP; };
#endif

texture tAO1 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sAO1 { Texture = tAO1; AddressU = CLAMP; AddressV = CLAMP; };

texture tAO2 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sAO2 { Texture = tAO2; AddressU = CLAMP; AddressV = CLAMP; };

texture tPrevAO { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sPrevAO { Texture = tPrevAO; AddressU = CLAMP; AddressV = CLAMP; };

texture tBlueNoise < source = "lumenite_bluenoise256.png"; > { Width = 256; Height = 256; Format = R8; };
sampler sBlueNoise { Texture = tBlueNoise; AddressU = REPEAT; AddressV = REPEAT; };

/*--------------.
| :: HELPERS :: |
'--------------*/

//===hemisphere sampling
void BuildOrthonormalBasis(float3 n, out float3 b1, out float3 b2)
{
    if (n.z < -0.9999999) {
        b1 = float3(0.0, -1.0, 0.0);
        b2 = float3(-1.0, 0.0, 0.0);
    } else {
        float a = rcp(1.0 + n.z);
        float b = -n.x * n.y * a;
        b1 = float3(mad(-n.x * n.x, a, 1.0), b, -n.x);
        b2 = float3(b, mad(-n.y * n.y, a, 1.0), -n.y);
    }
}

float3 GenerateHemisphereDirection(float3 normal, float2 rand, float3 tangent, float3 bitangent)
{
    float phi = rand.x * 6.28318530718; //2.0 * PI as constant
    float sinPhi, cosPhi;
    sincos(phi, sinPhi, cosPhi);
    float cosTheta = sqrt(1.0 - rand.y);
    float sinTheta = sqrt(rand.y);
    float3 result = normal * cosTheta;
    result = mad(bitangent, sinTheta * sinPhi, result);
    result = mad(tangent, sinTheta * cosPhi, result);
    return result;
}

//===core Settings
float CalculateDepthFade(float depth)
{
    float fadeStartDepth = DEPTH_BOUNDARY * DEPTH_FADE_START;
    float fadeRange = DEPTH_BOUNDARY - fadeStartDepth;
    return 1.0 - saturate((depth - fadeStartDepth) / fadeRange);
}

//===atrous helpers
float ComputeATrousWeight(float centerDepth, float3 centerNormal, float sampleDepth, float3 sampleNormal)
{
    float depthDiff = abs(centerDepth - sampleDepth);
    float depthWeight = exp(-depthDiff * ATROUS_DEPTH_WEIGHT_SCALE);
    float normalDot = saturate(dot(centerNormal, sampleNormal));
    float normalWeight = pow(normalDot, ATROUS_NORMAL_WEIGHT_SCALE);
    return depthWeight * normalWeight;
}

float ATrousFilter(float2 uv, sampler SourceSampler, int Dilation)
{
    float4 gbuffer = tex2D(sKernelNormals, uv);
    float3 centerNormal = gbuffer.rgb;
    float centerDepth = gbuffer.a;
    if (centerDepth == 0 || centerDepth >= DEPTH_BOUNDARY) discard;

    float centerAO = tex2Dlod(SourceSampler, float4(uv, 0, 0)).r;
    float sum = centerAO;
    float totalWeight = 1.0;

    for (int y = -1; y <= 1; y++)
    {
        for (int x = -1; x <= 1; x++)
        {
            float2 sampleUV = uv + float2(x, y) * Dilation * ReShade::PixelSize;
            float sampleAO = tex2Dlod(SourceSampler, float4(sampleUV, 0, 0)).r;
            gbuffer = tex2Dlod(sKernelNormals, float4(sampleUV, 0, 0));
            float3 sampleNormal = gbuffer.rgb;
            float sampleDepth = gbuffer.a;
            float weight = ComputeATrousWeight(centerDepth, centerNormal, sampleDepth, sampleNormal);
            sum += sampleAO * weight;
            totalWeight += weight;
        }
    }
    return sum / (totalWeight + EPSILON);
}

/*--------------------.
| :: PIXEL SHADERS :: |
'--------------------*/

//===ambient occlusion
float PS_TraceAO(VSOUT input) : SV_Target
{
    if (CHECKERBOARD_RENDERING) {
        #if RESOLUTION_SCALING
            if(CheckerboardSkip(uint2(input.vpos.xy), 2.0)) discard;
        #else
            if(CheckerboardSkip(uint2(input.vpos.xy), 1.0)) discard;
        #endif
    }

    float4 gbuffer = tex2D(sKernelNormals, input.uv);
    float3 normal = gbuffer.rgb;
    float depth = gbuffer.a;

    if (depth == 0 || depth >= DEPTH_BOUNDARY) discard;

    float3 startPos = UVToViewSpace(input.uv, depth, input);
    float3 tangent, bitangent;
    BuildOrthonormalBasis(normal, tangent, bitangent);
    float2 rand = float2(
        tex2Dlod(sBlueNoise, float4(frac((input.vpos.xy + float(FRAME_COUNT % 256)) / 256.0), 0, 0)).r,
        tex2Dlod(sBlueNoise, float4(frac((input.vpos.xy + float(FRAME_COUNT % 256) * 1.618) / 256.0), 0, 0)).r
    );
    float3 rayDir = GenerateHemisphereDirection(normal, rand, tangent, bitangent);
    float invDepth = rcp(depth);
    float totalRayLength = AO_RADIUS * depth;
    float initialStepScale = INITIAL_STEP_SCALE * rcp((float)AO_MAX_MARCH_STEPS);
    float stepSize = totalRayLength * initialStepScale;
    float3 rayPos = mad(rayDir, stepSize * 0.5, startPos);
    float occlusion = 0.0;

    [loop]
    for (int step = 0; step < AO_MAX_MARCH_STEPS; step++) {
        float2 sampleUV = ViewSpaceToUV(rayPos, input);
        float sceneDepth = ReShade::GetLinearizedDepth(sampleUV);
        float depthDiff = rayPos.z - sceneDepth;
        [branch]
        if (depthDiff > 0.0 && depthDiff < rayPos.z) {
            float3 scenePos = UVToViewSpace(sampleUV, sceneDepth, input);
            float hitDistance = length(scenePos - startPos);
            float normalizedDistance = hitDistance * invDepth;
            occlusion = exp(-normalizedDistance * 15.0);
            break;
        }
        stepSize *= STEP_GROWTH_FACTOR;
        rayPos = mad(rayDir, stepSize, rayPos);
    }

    float aoFactor = 1.0 - saturate(occlusion * AO_INTENSITY);
    return aoFactor;
}

//===atrous filtering
float PS_ATrousPass(VSOUT input) : SV_Target
{
    #if RESOLUTION_SCALING
        return ATrousFilter(input.uv, sAOTrace, ATROUS_DILATION_1);
    #else
        return ATrousFilter(input.uv, sAO1, ATROUS_DILATION_1);
    #endif
}

//===composition
float PS_Blend(VSOUT input) : SV_Target
{
    float depth = tex2D(sKernelNormals, input.uv).a;
    //overwrite noise at boundary with clean White, preventing gaps
    if (depth >= DEPTH_BOUNDARY) return 1.0;
    if (depth == 0) discard;
    float ao = ATrousFilter(input.uv, sAO2, ATROUS_DILATION_2);
    ao = lerp(1.0, ao, CalculateDepthFade(depth));
    float2 flow = tex2D(sLumaFlow, input.uv).xy;
    float confidence = tex2D(sFlowConfidence, input.uv).x;
    confidence = saturate(confidence + log2(2.0 - confidence) * 0.35); //logarithmically boost confidence: compresses its range to allow a bit more blend
    float rawHistory = tex2D(sPrevAO, input.uv + flow).r; //history stores "1.0 - AO". 0.0 (Black Texture) -> Reads as 1.0 (White).
    float prevAO = 1.0 - rawHistory;
    float blendVal = (rawHistory == 0.0) ? 0.0 : (confidence * 0.98);
    ao = lerp(ao, prevAO, blendVal);
    //max(..., 0.001) to ensure we NEVER write exactly 0.0 again.
    //this tells the next frame "I contain data".
    return max(ao, 0.001);
}

float4 PS_Display(VSOUT input) : SV_Target
{
    float depth = tex2D(sKernelNormals, input.uv).a;
    float ao = tex2D(sAO1, input.uv).r; //stable AO mask (fades to 1.0)
    if (DEBUG_VIEW) {
        #if BUFFER_COLOR_SPACE > 1
            return float4(ToOutputColorspace(ao.xxx), 1.0);
        #else
            return float4(ao.xxx, 1.0);
        #endif
    }
    if (depth == 0 || depth >= DEPTH_BOUNDARY) discard;
    float3 base = GetLinearColor(input.uv);
    base *= ao;
    return float4(ToOutputColorspace(base), 1.0);
}

float PS_StoreAO(VSOUT input) : SV_Target
{
    //we must prevent history collision here
    //if we store exactly 0.0 (means White), the next frame's blend pass thinks
    //history is empty and resets it, causing shimmer
    //so we clamp to 0.0001 so the system knows "This is valid history data"
    return max(1.0 - tex2D(sAO1, input.uv).r, 0.0001);
}

/*----------------.
| :: TECHNIQUE :: |
'----------------*/
technique Lumenite_RTAO <
    ui_label = "LUMENITE: RTAO";
    ui_tooltip = "Ray Traced Ambient Occlusion.";
>
{
    #if RESOLUTION_SCALING
        pass { VertexShader = VS; PixelShader = PS_TraceAO; RenderTarget = tAOTrace; }
    #else
        pass { VertexShader = VS; PixelShader = PS_TraceAO; RenderTarget = tAO1; }
    #endif
    pass { VertexShader = VS; PixelShader = PS_ATrousPass; RenderTarget = tAO2; }

    pass { VertexShader = VS; PixelShader = PS_Blend; RenderTarget = tAO1; }
    pass { VertexShader = VS; PixelShader = PS_Display; }
    pass { VertexShader = VS; PixelShader = PS_StoreAO; RenderTarget = tPrevAO; }
}

}
