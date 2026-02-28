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


        Filename   : lumenite_LSAO.fx
        Version    : 2026.02.28
        Author     : Afzaal (Kaidō)
        Description: Large-Scale Ray Traced Ambient Occlusion.
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

//===ambient occlusion
#define INITIAL_STEP_SCALE 0.9 //how small the very first step is (as a fraction of the avg. step size).
#define STEP_GROWTH_FACTOR 1.2
#define ATROUS_DEPTH_WEIGHT_SCALE 300.0
#define ATROUS_NORMAL_WEIGHT_SCALE 20.0
#define AO_MAX_MARCH_STEPS 100
#define AO_RADIUS 0.7

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

namespace LumeniteLSAO {

/*---------------------.
| :: RENDER TARGETS :: |
'---------------------*/

texture tAOTrace { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = R16F; }; // tracing at half-res
sampler sAOTrace { Texture = tAOTrace; AddressU = CLAMP; AddressV = CLAMP; };

texture tAO1 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sAO1 { Texture = tAO1; AddressU = CLAMP; AddressV = CLAMP; };

texture tAO2 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sAO2 { Texture = tAO2; AddressU = CLAMP; AddressV = CLAMP; };

texture tPrevAO { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sPrevAO { Texture = tPrevAO; AddressU = CLAMP; AddressV = CLAMP; };

texture tBlueNoise < source = "lumenite_bluenoise256.png"; > { Width = 256; Height = 256; Format = R8; };
sampler sBlueNoise { Texture = tBlueNoise; AddressU = REPEAT; AddressV = REPEAT; };

//===HiZ mipchain
texture tHiZMip0 { Width = BUFFER_WIDTH;    Height = BUFFER_HEIGHT;    Format = R16F; };
texture tHiZMip1 { Width = BUFFER_WIDTH/2;  Height = BUFFER_HEIGHT/2;  Format = R16F; };
texture tHiZMip2 { Width = BUFFER_WIDTH/4;  Height = BUFFER_HEIGHT/4;  Format = R16F; };
texture tHiZMip3 { Width = BUFFER_WIDTH/8;  Height = BUFFER_HEIGHT/8;  Format = R16F; };
texture tHiZMip4 { Width = BUFFER_WIDTH/16; Height = BUFFER_HEIGHT/16; Format = R16F; };
texture tHiZMip5 { Width = BUFFER_WIDTH/32; Height = BUFFER_HEIGHT/32; Format = R16F; };

sampler sHiZMip0 { Texture = tHiZMip0; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };
sampler sHiZMip1 { Texture = tHiZMip1; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };
sampler sHiZMip2 { Texture = tHiZMip2; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };
sampler sHiZMip3 { Texture = tHiZMip3; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };
sampler sHiZMip4 { Texture = tHiZMip4; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };
sampler sHiZMip5 { Texture = tHiZMip5; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };

/*--------------.
| :: HELPERS :: |
'--------------*/

//===hemisphere Sampling
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

//===core settings
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

//===HiZ passes
struct HiZData { float min_depth; };

HiZData Sample2x2FromScene(float2 current_uv) {
    float2 texel_size = ReShade::PixelSize;
    float2 block_origin_uv = floor(current_uv / (texel_size * 2.0)) * (texel_size * 2.0);
    float2 uvs[4] = { block_origin_uv + texel_size * float2(0.5, 0.5), block_origin_uv + texel_size * float2(1.5, 0.5),
                      block_origin_uv + texel_size * float2(0.5, 1.5), block_origin_uv + texel_size * float2(1.5, 1.5) };
    float d0 = ReShade::GetLinearizedDepth(uvs[0]); float d1 = ReShade::GetLinearizedDepth(uvs[1]);
    float d2 = ReShade::GetLinearizedDepth(uvs[2]); float d3 = ReShade::GetLinearizedDepth(uvs[3]);
    HiZData r;
    r.min_depth = min(min(d0, d1), min(d2, d3));
    return r;
}

HiZData SampleFromPreviousHiZ(float2 center_uv, sampler s, int source_mip_level) {
    float2 source_texel_size = ReShade::PixelSize * pow(2, source_mip_level);
    float2 offsets[4] = { float2(-0.5, -0.5), float2(0.5, -0.5), float2(-0.5, 0.5), float2(0.5, 0.5) };
    float min_depth = 1.0;
    [unroll] for(int i=0; i<4; i++)
        min_depth = min(min_depth, tex2D(s, center_uv + offsets[i] * source_texel_size).r);
    HiZData r;
    r.min_depth = min_depth;
    return r;
}

float PS_GenerateMip0(VSOUT input) : SV_Target { return Sample2x2FromScene   (input.uv).min_depth;              }
float PS_ReduceMip1  (VSOUT input) : SV_Target { return SampleFromPreviousHiZ(input.uv, sHiZMip0, 0).min_depth; }
float PS_ReduceMip2  (VSOUT input) : SV_Target { return SampleFromPreviousHiZ(input.uv, sHiZMip1, 1).min_depth; }
float PS_ReduceMip3  (VSOUT input) : SV_Target { return SampleFromPreviousHiZ(input.uv, sHiZMip2, 2).min_depth; }
float PS_ReduceMip4  (VSOUT input) : SV_Target { return SampleFromPreviousHiZ(input.uv, sHiZMip3, 3).min_depth; }
float PS_ReduceMip5  (VSOUT input) : SV_Target { return SampleFromPreviousHiZ(input.uv, sHiZMip4, 4).min_depth; }


//===ambient occlusion
float PS_TraceAO(VSOUT input) : SV_Target
{
    if (CHECKERBOARD_RENDERING)
        if(CheckerboardSkip(uint2(input.vpos.xy), 2.0)) discard;

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
    float totalRayLength = AO_RADIUS * depth;
    float baseStepSize = totalRayLength / (float)AO_MAX_MARCH_STEPS;
    float stepSize = baseStepSize;
    float3 currentPos = startPos + rayDir * stepSize;
    float occlusion = 0.0;
    float t = stepSize;
    float prevDiff = -1.0;
    float3 prevRayPos = currentPos;

    [loop]
    for (int step = 0; step < AO_MAX_MARCH_STEPS; step++) {
        if (t >= totalRayLength) break;

        float2 hitPos = ViewSpaceToUV(currentPos, input);
        if (any(hitPos < 0.0) || any(hitPos > 1.0)) break;

        //select the appropriate Mip Level
        float2 ray_screen_velocity = abs(rayDir.xy / currentPos.z) * float2(BUFFER_WIDTH, BUFFER_HEIGHT);
        float footprint = max(ray_screen_velocity.x, ray_screen_velocity.y) * max(stepSize / currentPos.z, 1.0);
        int mip = clamp(int(log2(max(footprint, 1.0))), 0, 5);

        //depth-biased step scaling: smaller steps near camera
        float depthScale = lerp(0.3, 1.5, saturate(currentPos.z / DEPTH_BOUNDARY));
        stepSize = baseStepSize * max(1.0, float(mip) * 0.5) * depthScale;

        //now sample from selected mip
        float HiZDepth;
        if      (mip==5) HiZDepth = tex2Dlod(sHiZMip5, float4(hitPos,0,0)).r;
        else if (mip==4) HiZDepth = tex2Dlod(sHiZMip4, float4(hitPos,0,0)).r;
        else if (mip==3) HiZDepth = tex2Dlod(sHiZMip3, float4(hitPos,0,0)).r;
        else if (mip==2) HiZDepth = tex2Dlod(sHiZMip2, float4(hitPos,0,0)).r;
        else if (mip==1) HiZDepth = tex2Dlod(sHiZMip1, float4(hitPos,0,0)).r;
        else             HiZDepth = tex2Dlod(sHiZMip0, float4(hitPos,0,0)).r;

        //skip empty space - larger leaps with HiZ
        if (currentPos.z < HiZDepth && (HiZDepth - currentPos.z) > stepSize) {
            float leap = (HiZDepth - currentPos.z) * 0.1;
            currentPos += rayDir * leap;
            t += leap;
            prevDiff = currentPos.z - HiZDepth;
            prevRayPos = currentPos;
            continue;
        }

        //hit test
        float sceneDepth = ReShade::GetLinearizedDepth(hitPos);
        float depthDiff = currentPos.z - sceneDepth;

        if (depthDiff > (currentPos.z * 0.005) && depthDiff < (currentPos.z * 0.2)) {
            float3 scenePos = UVToViewSpace(hitPos, sceneDepth, input);
            float hitDistance = length(scenePos - startPos);
            float normalizedDist = hitDistance / totalRayLength;
            occlusion = saturate(1.0 - normalizedDist);
            occlusion = occlusion * occlusion;
            //contact bias: darken very close hits
            float proximity = 1.0 - normalizedDist;
            float contactBias = proximity * proximity;
            occlusion *= (1.0 + contactBias * 0.5);
            break;
        }

        currentPos += rayDir * stepSize;
        t += stepSize;
        prevDiff = depthDiff;
        prevRayPos = currentPos;
    }

    float aoFactor = 1.0 - saturate(occlusion * AO_INTENSITY);
    return aoFactor;
}

//===atrous filtering
float PS_ATrousPass1(VSOUT input) : SV_Target
{
    return ATrousFilter(input.uv, sAOTrace, 2); //bilinear upsampling + hole filling
}

float PS_ATrousPass2(VSOUT input) : SV_Target
{
    return ATrousFilter(input.uv, sAO2, 4);
}

//===composition
float PS_Blend(VSOUT input) : SV_Target
{
    float depth = tex2D(sKernelNormals, input.uv).a;
    //overwrite noise at boundary with clean White, preventing gaps
    if (depth >= DEPTH_BOUNDARY) return 1.0;
    if (depth == 0) discard;
    float ao = ATrousFilter(input.uv, sAO1, 8);
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
    float ao = tex2D(sAO2, input.uv).r; //stable AO mask (fades to 1.0)
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
    return max(1.0 - tex2D(sAO2, input.uv).r, 0.0001);
}

/*----------------.
| :: TECHNIQUE :: |
'----------------*/
technique Lumenite_LSAO <
    ui_label = "LUMENITE: LSAO";
    ui_tooltip = "Large-Scale Ray Traced Ambient Occlusion.";
>
{

    pass { VertexShader = VS; PixelShader = PS_GenerateMip0; RenderTarget = tHiZMip0; }
    pass { VertexShader = VS; PixelShader = PS_ReduceMip1;   RenderTarget = tHiZMip1; }
    pass { VertexShader = VS; PixelShader = PS_ReduceMip2;   RenderTarget = tHiZMip2; }
    pass { VertexShader = VS; PixelShader = PS_ReduceMip3;   RenderTarget = tHiZMip3; }
    pass { VertexShader = VS; PixelShader = PS_ReduceMip4;   RenderTarget = tHiZMip4; }
    pass { VertexShader = VS; PixelShader = PS_ReduceMip5;   RenderTarget = tHiZMip5; }

    pass { VertexShader = VS; PixelShader = PS_TraceAO; RenderTarget = tAOTrace; }
    pass { VertexShader = VS; PixelShader = PS_ATrousPass1; RenderTarget = tAO2; }
    pass { VertexShader = VS; PixelShader = PS_ATrousPass2; RenderTarget = tAO1; }

    pass { VertexShader = VS; PixelShader = PS_Blend; RenderTarget = tAO2; }
    pass { VertexShader = VS; PixelShader = PS_Display; }
    pass { VertexShader = VS; PixelShader = PS_StoreAO; RenderTarget = tPrevAO; }
}

}
