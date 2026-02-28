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


        Filename   : lumenite_Kernel.fx
        Version    : 2026.02.28
        Author     : Afzaal (Kaidō)
        Description: Pre-effect for various LumeniteFX shaders.
        License    : AGNYA License (https://github.com/nvb-uy/AGNYA-License)

        ========================================================================
*/

#include "ReShade.fxh"
#include "./include/LUMENITE_Projections.fxh"
#include "./include/LUMENITE_Helpers.fxh"

#ifndef DEBUG_KERNEL
#define DEBUG_KERNEL 0
#endif

/*---------------.
| :: UNIFORMS :: |
'---------------*/

#if DEBUG_KERNEL
uniform int DEBUG_VIEW <
    ui_type = "combo";
    ui_items = "Debug Off\0"
               "Normals/Depth\0"
               "Optical Flow\0"
               "Motion Vectors\0"
               "Motion Confidence\0"
               ;
    ui_label = "Debug View";
    ui_category = "Kernel";
> = 0;
#endif

/*-------------.
| :: EXPORT :: |
'-------------*/

//optical flow
texture2D tLumaFlow { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = RG16F; };
sampler2D sLumaFlow { Texture = tLumaFlow; MagFilter = POINT; MinFilter = POINT; };

texture2D tFlowConfidence { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = R16F; };
sampler2D sFlowConfidence { Texture = tFlowConfidence; MagFilter = POINT; MinFilter = POINT; };

//surface normals
texture tKernelNormals { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sKernelNormals { Texture = tKernelNormals; };

namespace LumeniteKernel {

/*---------------------.
| :: RENDER TARGETS :: |
'---------------------*/

//=== Motion vectors
texture2D tCurrLuma { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; MipLevels = 8; };
sampler2D sCurrLuma { Texture = tCurrLuma; MagFilter = LINEAR; MinFilter = LINEAR; MipFilter = LINEAR; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP; };

texture2D tPrevLuma { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; MipLevels = 8; };
sampler2D sPrevLuma { Texture = tPrevLuma; MagFilter = LINEAR; MinFilter = LINEAR; MipFilter = LINEAR; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP; };

texture2D tLumaFlow128 { Width = BUFFER_WIDTH/128; Height = BUFFER_HEIGHT/128; Format = RG16F; };
sampler2D sLumaFlow128 { Texture = tLumaFlow128; MagFilter = POINT; MinFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP; };

texture2D tLumaFlow64A { Width = BUFFER_WIDTH/64; Height = BUFFER_HEIGHT/64; Format = RG16F; };
sampler2D sLumaFlow64A { Texture = tLumaFlow64A; MagFilter = POINT; MinFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP; };
texture2D tLumaFlow64B { Width = BUFFER_WIDTH/64; Height = BUFFER_HEIGHT/64; Format = RG16F; };
sampler2D sLumaFlow64B { Texture = tLumaFlow64B; MagFilter = POINT; MinFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP; };

texture2D tLumaFlow32A { Width = BUFFER_WIDTH/32; Height = BUFFER_HEIGHT/32; Format = RG16F; };
sampler2D sLumaFlow32A { Texture = tLumaFlow32A; MagFilter = POINT; MinFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP; };
texture2D tLumaFlow32B { Width = BUFFER_WIDTH/32; Height = BUFFER_HEIGHT/32; Format = RG16F; };
sampler2D sLumaFlow32B { Texture = tLumaFlow32B; MagFilter = POINT; MinFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP; };

texture2D tLumaFlow16A { Width = BUFFER_WIDTH/16; Height = BUFFER_HEIGHT/16; Format = RG16F; };
sampler2D sLumaFlow16A { Texture = tLumaFlow16A; MagFilter = POINT; MinFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP; };
texture2D tLumaFlow16B { Width = BUFFER_WIDTH/16; Height = BUFFER_HEIGHT/16; Format = RG16F; };
sampler2D sLumaFlow16B { Texture = tLumaFlow16B; MagFilter = POINT; MinFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP; };

texture2D tLumaFlow8 { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = RG16F; };
sampler2D sLumaFlow8 { Texture = tLumaFlow8; MagFilter = POINT; MinFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP; };

texture2D tPrevFrameFlow { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = RG16F; };
sampler2D sPrevFrameFlow { Texture = tPrevFrameFlow; MagFilter = POINT; MinFilter = POINT; };

texture2D tPrevConfidence { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = R16F; };
sampler2D sPrevConfidence { Texture = tPrevConfidence; };

/*--------------.
| :: HELPERS :: |
'--------------*/

float3 GetColor(float2 uv)
{
    return tex2Dlod(ReShade::BackBuffer, float4(uv, 0, 0)).rgb;
}

float3 DepthColorMap(float t)
{
    //white → yellow/orange → red → dark purple
    t = saturate(1.0 - t);  //close=bright, far=dark
    const float3 c0 = float3(0.050383, 0.029803, 0.527975);
    const float3 c1 = float3(0.196881, 0.018803, 0.590027);
    const float3 c2 = float3(0.314956, 0.017695, 0.604805);
    const float3 c3 = float3(0.429345, 0.047208, 0.576190);
    const float3 c4 = float3(0.535574, 0.101812, 0.508287);
    const float3 c5 = float3(0.639213, 0.169051, 0.417812);
    const float3 c6 = float3(0.741388, 0.247236, 0.317808);
    const float3 c7 = float3(0.838008, 0.343882, 0.215553);
    const float3 c8 = float3(0.924797, 0.462077, 0.136061);
    const float3 c9 = float3(0.987622, 0.617099, 0.104282);
    const float3 c10 = float3(0.940015, 0.975158, 0.131326);
    float3 color;
    if (t < 0.999) {
        float t10 = t * 10.0;
        int idx = clamp(int(t10), 0, 9);
        float fracT = frac(t10);
        if      (idx == 0) color = lerp(c0, c1,  fracT);
        else if (idx == 1) color = lerp(c1, c2,  fracT);
        else if (idx == 2) color = lerp(c2, c3,  fracT);
        else if (idx == 3) color = lerp(c3, c4,  fracT);
        else if (idx == 4) color = lerp(c4, c5,  fracT);
        else if (idx == 5) color = lerp(c5, c6,  fracT);
        else if (idx == 6) color = lerp(c6, c7,  fracT);
        else if (idx == 7) color = lerp(c7, c8,  fracT);
        else if (idx == 8) color = lerp(c8, c9,  fracT);
        else               color = lerp(c9, c10, fracT);
    } else {
        float whiteProgress = (t - 0.999) / 0.001;
        color = lerp(c10, float3(1.0, 1.0, 1.0), whiteProgress);
    }
    return color;
}

// float3 MotionToColor(float2 motion)
// {
//     float angle = atan2(-motion.y, -motion.x) / 6.283 + 0.5;
//     float rawLength = length(motion) / (15.0 * ReShade::PixelSize.x);
//     float compressed = rawLength / (1.0 + rawLength * 1.4);  //asymptotic squash
//     float boosted = pow(compressed, 0.5);  //lift shadows
//     float magnitude = saturate(lerp(compressed, boosted, saturate(rawLength * 3.0)));
//     float3 hsv = float3(angle, 1, magnitude);
//     float4 K = float4(1, 2/3.0, 1/3.0, 3);
//     float3 p = abs(frac(hsv.xxx + K.xyz) * 6 - K.www);
//     return hsv.z * lerp(K.xxx, clamp(p - K.xxx, 0, 1), hsv.y) + 0.1;
// }

float3 MotionToColor(float2 motion, float2 uv)
{
    //physics & noise gate
    float dt = max(FRAME_TIME * 0.001, 0.001);
    float2 velocity = motion / dt;
    float gate = saturate(pow(length(motion) / (2.0 * BUFFER_PIXEL_SIZE.x), 3.0));
    //asymptotic squash
    float mag = length(velocity) * 5.0;
    mag = mag / (1.0 + mag);
    mag *= gate;
    //anisotropic hatching
    float2 angleDir = normalize(motion + 1e-9);
    float grid = frac(dot(uv * BUFFER_SCREEN_SIZE, angleDir) * 0.2);
    float streaks = smoothstep(0.0, 0.1, grid) * smoothstep(0.2, 0.1, grid);
    //dynamic rainbow palette
    float angle = atan2(-motion.y, -motion.x) / 6.283 + 0.5;
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 hue = abs(frac(angle.xxx + K.xyz) * 6.0 - K.www);
    hue = saturate(hue - K.xxx);
    //spectral tiers
    float3 colorLow  = hue * 0.3;
    float3 colorMid  = hue;
    float3 colorHigh = lerp(hue, 1.0, 0.5);
    float3 baseCloud = lerp(colorLow, colorMid, mag);
    baseCloud = lerp(baseCloud, colorHigh, pow(mag, 2.0));
    float3 motionColor = baseCloud + (streaks * mag * 0.5);
    return lerp(0.1, motionColor, mag);
}

float4 DrawMotionVectors(float2 uv)
{
    static const float ARROW_THICKNESS = 1.0;
    static const int GRID_STEP = 2;
    static const float ARROWHEAD_LENGTH = 4.0; //pixels back from tip
    static const float WING_ANGLE = 0.6; //approx. 35 degrees from shaft axis

    float3 baseColor = tex2Dlod(ReShade::BackBuffer, float4(uv, 0, 0)).rgb;
    float2 motionTexelSize = BUFFER_PIXEL_SIZE * 8.0;
    float2 motionGrid = floor(uv / motionTexelSize / GRID_STEP) * motionTexelSize * GRID_STEP + motionTexelSize * GRID_STEP * 0.5;
    float2 gridPixelPos = motionGrid * BUFFER_SCREEN_SIZE;
    float2 motion = tex2D(sLumaFlow, motionGrid).xy;
    float2 motionPixels = motion * BUFFER_SCREEN_SIZE;
    float motionMag = length(motionPixels);
    if (motionMag < 0.5 || GetDepth(motionGrid) >= 0.999) return float4(baseColor, 1.0);
    float arrowLength = clamp(motionMag * 3.0, 8.0, 48.0);
    float2 arrowDir = normalize(-motionPixels + float2(EPSILON, EPSILON)); //negate for forward motion
    float2 arrowTip = gridPixelPos + arrowDir * arrowLength;

    //shaft (stop before arrowhead starts)
    float2 pixelPos = uv * BUFFER_SCREEN_SIZE;
    float2 toPixel = pixelPos - gridPixelPos;
    float proj = dot(toPixel, arrowDir);
    float2 closestShaft = arrowDir * clamp(proj, 0, arrowLength - ARROWHEAD_LENGTH);
    float distShaft = length(toPixel - closestShaft);
    bool onShaft = (distShaft < ARROW_THICKNESS) && (proj > 0) && (proj < arrowLength - ARROWHEAD_LENGTH);

    //arrowhead wings: angled back from tip
    float2 backDir = -arrowDir;

    //left wing (rotate backDir by -WING_ANGLE)
    float2 wingLeftDir = float2(
        backDir.x * cos(WING_ANGLE) + backDir.y * sin(WING_ANGLE),
        -backDir.x * sin(WING_ANGLE) + backDir.y * cos(WING_ANGLE)
    );

    //right wing (rotate backDir by +WING_ANGLE)
    float2 wingRightDir = float2(
        backDir.x * cos(WING_ANGLE) - backDir.y * sin(WING_ANGLE),
        backDir.x * sin(WING_ANGLE) + backDir.y * cos(WING_ANGLE)
    );

    //distance to left wing
    float2 toTip = pixelPos - arrowTip;
    float projLeft = dot(toTip, wingLeftDir);
    float2 closestLeft = wingLeftDir * clamp(projLeft, 0, ARROWHEAD_LENGTH);
    float distLeft = length(toTip - closestLeft);
    bool onLeft = (distLeft < ARROW_THICKNESS) && (projLeft > 0) && (projLeft < ARROWHEAD_LENGTH);

    //distance to right wing
    float projRight = dot(toTip, wingRightDir);
    float2 closestRight = wingRightDir * clamp(projRight, 0, ARROWHEAD_LENGTH);
    float distRight = length(toTip - closestRight);
    bool onRight = (distRight < ARROW_THICKNESS) && (projRight > 0) && (projRight < ARROWHEAD_LENGTH);

    float3 arrowColor = MotionToColor(motion, uv);
    return float4((onShaft || onLeft || onRight) ? arrowColor : baseColor, 1.0);
}

float ZMSAD(sampler2D currLumaSrc, sampler2D prevLumaSrc, float2 posA, float2 posB, float2 texelSize, uint mip)
{
    static const int2 offsets[9] = {
                                int2(0, 3),
                                int2(0, 1),
        int2(-3,0), int2(-1,0), int2(0, 0), int2(1,0), int2(3,0),
                                int2(0,-1),
                                int2(0,-3)
    };

    //gather samples and calculate the mean for each patch
    float samplesA[9], samplesB[9];
    float meanA = 0.0, meanB = 0.0;

    [unroll]
    for(int i = 0; i < 9; i++)
    {
        float2 offset = float2(offsets[i]) * texelSize;
        samplesA[i] = tex2Dlod(currLumaSrc, float4(posA + offset, 0, mip)).r;
        samplesB[i] = tex2Dlod(prevLumaSrc, float4(posB + offset, 0, mip)).r;
        meanA += samplesA[i];
        meanB += samplesB[i];
    }
    meanA /= 9.0;
    meanB /= 9.0;

    //SAD on the normalized samples
    float err = 0.0;
    [unroll]
    for(int i = 0; i < 9; i++)
    {
        err += abs((samplesA[i] - meanA) - (samplesB[i] - meanB));
    }

    return ((err / 9.0) + EPSILON);
}

float2 Median9(sampler2D flowSrc, float2 uv, float2 texelSize, uint mip)
{
    float2 v[9];
    int idx = 0;
    [unroll] for(int dy = -1; dy <= 1; dy++) {
        [unroll] for(int dx = -1; dx <= 1; dx++) {
            v[idx++] = tex2Dlod(flowSrc, float4(uv + float2(dx, dy) * texelSize, 0, mip)).xy;
        }
    }
    //bubble sort ensures the Median lands in v[4], only needs 5 passes
    //indices 4,5,6,7,8 contain the 5 largest items, so v[4] is the median
    float2 temp;
    [unroll] for(int k = 0; k < 5; k++) {
        [unroll] for(int i = 0; i < 8 - k; i++) { //checks decrease as right side gets sorted
            float2 a = v[i];
            float2 b = v[i+1];
            v[i]   = min(a, b);
            v[i+1] = max(a, b);
        }
    }

    return v[4];
}

float2 BilateralBlur(sampler2D motionSrc, sampler2D lumaSrc, float2 uv, float2 texelSize, uint mip)
{
    float centerDepth = GetDepth(uv);
    if(centerDepth >= 0.999) return float2(0, 0);

    static const float LUMA_SIGMA = 0.1;
    static const float SPATIAL_SIGMA = 1.5;
    static const float DISOCCLUSION_THRESHOLD = 0.01;
    static const float INV_SPATIAL_SIGMA_SQ = -0.5 / (SPATIAL_SIGMA * SPATIAL_SIGMA);
    static const float INV_LUMA_SIGMA_SQ = -0.5 / (LUMA_SIGMA * LUMA_SIGMA);

    float2 centerFlow  = tex2Dlod(motionSrc, float4(uv, 0, 0)).xy;
    float  centerLuma  = tex2Dlod(lumaSrc, float4(uv, 0, mip)).r;
    float2 flowSum     = 0.0;
    float  weightSum   = 0.0;

    for (int y = -2; y <= 2; ++y) for (int x = -2; x <= 2; ++x) {
            float2 offset = float2(x, y) * texelSize;
            float2 sampleUV = uv + offset;
            float2 neighborFlow  = tex2Dlod(motionSrc, float4(sampleUV, 0, 0)).xy;
            float  neighborLuma  = tex2Dlod(lumaSrc,   float4(sampleUV, 0, mip)).r;
            float  neighborDepth = GetDepth(sampleUV);
            //spatial weight (Gaussian falloff)
            float spatialDistSq = dot(float2(x, y), float2(x, y));
            float spatialWeight = exp(spatialDistSq * INV_SPATIAL_SIGMA_SQ);
            //luma similarity weight
            float lumaDiff   = centerLuma - neighborLuma;
            float lumaWeight = exp(lumaDiff * lumaDiff * INV_LUMA_SIGMA_SQ);
            //cutoff at depth discontinuities
            float absDepthDiff = abs(centerDepth - neighborDepth);
            float disocclusionGate = (absDepthDiff < DISOCCLUSION_THRESHOLD) ? 1.0 : 0.0;
            //combine
            float totalWeight = spatialWeight * lumaWeight * disocclusionGate;
            //accumulate
            flowSum += neighborFlow * totalWeight;
            weightSum += totalWeight;
    }
    return flowSum / weightSum;
}

float2 RefineFlow(sampler2D coarseSrc, sampler2D currLumaSrc, sampler2D prevLumaSrc, float2 uv, float2 texelSize, uint mip)
{
    if(FRAME_COUNT == 0) return float2(0, 0);

    float2 coarseTexelSize = rcp(tex2Dsize(coarseSrc, 0));
    //pool candidates for tournament selection. order matters here
    float2 candidates[11];
    candidates[0]  = tex2D(coarseSrc, uv).xy ;
    candidates[1]  = tex2D(coarseSrc, uv + float2(0, -coarseTexelSize.y)).xy ;
    candidates[2]  = tex2D(coarseSrc, uv + float2(0,  coarseTexelSize.y)).xy ;
    candidates[3]  = tex2D(coarseSrc, uv - float2(coarseTexelSize.x, 0)).xy ;
    candidates[4]  = tex2D(coarseSrc, uv + float2(coarseTexelSize.x, 0)).xy ;
    candidates[5]  = tex2D(coarseSrc, uv + float2(-coarseTexelSize.x, -coarseTexelSize.y)).xy ;
    candidates[6]  = tex2D(coarseSrc, uv + float2( coarseTexelSize.x, -coarseTexelSize.y)).xy ;
    candidates[7]  = tex2D(coarseSrc, uv + float2(-coarseTexelSize.x,  coarseTexelSize.y)).xy ;
    candidates[8]  = tex2D(coarseSrc, uv + float2(coarseTexelSize.x, coarseTexelSize.y)).xy ;
    candidates[9]  = float2(0, 0);
    candidates[10] = tex2D(sPrevFrameFlow, uv).xy;

    float minCost = 1e6;
    float2 prediction = candidates[0];
    [loop] for (int i = 0; i < 11; i++) {
        float cost = ZMSAD(currLumaSrc, prevLumaSrc, uv, uv + candidates[i], texelSize, mip);
        if (cost < minCost) {
            minCost = cost;
            prediction = candidates[i];
        }
    }

    //refinement with parabolic fitting
    float costLeft   = ZMSAD(currLumaSrc, prevLumaSrc, uv, uv + prediction - float2(texelSize.x, 0), texelSize, mip);
    float costRight  = ZMSAD(currLumaSrc, prevLumaSrc, uv, uv + prediction + float2(texelSize.x, 0), texelSize, mip);
    float costDown   = ZMSAD(currLumaSrc, prevLumaSrc, uv, uv + prediction - float2(0, texelSize.y), texelSize, mip);
    float costUp     = ZMSAD(currLumaSrc, prevLumaSrc, uv, uv + prediction + float2(0, texelSize.y), texelSize, mip);
    //sub-pixel offset (parabolic fitting)
    float2 subpixelOffset;
    subpixelOffset.x = (costLeft - costRight) / (4.0 * (costLeft + costRight - 2.0 * minCost) + EPSILON); //EPSILON for flat surface handling
    subpixelOffset.y = (costDown - costUp)    / (4.0 * (costDown + costUp    - 2.0 * minCost) + EPSILON);
    //clamp offset to a reasonable range
    subpixelOffset = clamp(subpixelOffset, -0.5, 0.5);

    return (prediction+subpixelOffset*texelSize);
}

/*--------------------.
| :: PIXEL SHADERS :: |
'--------------------*/

float PS_CurrLuma(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    static const int2 offsets[13] = {
                             int2(0,-2),
                 int2(-1,-1),int2(0,-1),int2(1,-1),
      int2(-2,0),int2(-1,0), int2(0,0), int2(1,0), int2(2,0),
                 int2(-1,1), int2(0,1), int2(1,1),
                             int2(0,2)
    };
    float lumaSum = 0.0;
    float weightSum = 0.0;
    //gaussian (ish) weights for a dense 13-point pattern
    float weights[13] = {
                    1,              //(0,-2)
             3,     4,     3,       //diagonals, cardinal, diagonal
        1,   4,     6,     4,   1,  //far, cardinals, center, cardinals, far
             3,     4,     3,       //diagonals, cardinal, diagonal
                    1               //(0,2)
    };

    [loop] for(int i = 0; i < 13; i++) {
        float2 sampleUV = uv + float2(offsets[i]) * BUFFER_PIXEL_SIZE;
        float3 color = GetColor(sampleUV);
        float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
        luma = luma * rcp(1.0 + luma); //reinhard compression for HDR stability
        float weight = weights[i];
        lumaSum += luma * weight;
        weightSum += weight;
    }

    return lumaSum / weightSum;
}

float2 PS_ComputeFlow128(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    if(FRAME_COUNT == 0) return float2(0, 0);

    static const int SEARCH_RADIUS = 3;
    static const uint mip = 5;
    float2 texelSize = BUFFER_PIXEL_SIZE * exp2(mip);

    //candidate seeds for the coarsest level
    float2 prevSeed   = tex2D(sPrevFrameFlow, uv).xy;
    float2 zeroSeed   = float2(0, 0);

    float prevCost   = ZMSAD(sCurrLuma, sPrevLuma, uv, uv + prevSeed,   texelSize, mip);
    float zeroCost   = ZMSAD(sCurrLuma, sPrevLuma, uv, uv + zeroSeed,   texelSize, mip);

    //pick better candidate as seed
    float2 seed = (zeroCost < prevCost) ? zeroSeed : prevSeed;

    //start by assuming seed is the best
    float2 bestFlow = seed;
    float minCost = ZMSAD(sCurrLuma, sPrevLuma, uv, uv+seed, texelSize, mip);

    //search in a grid AROUND the seed
    for (int y = -SEARCH_RADIUS; y <= SEARCH_RADIUS; ++y) for (int x = -SEARCH_RADIUS; x <= SEARCH_RADIUS; ++x) {
            if (x == 0 && y == 0) continue;

            float2 candidateFlow = seed + float2(x, y) * texelSize;
            float cost = ZMSAD(sCurrLuma, sPrevLuma, uv, uv + candidateFlow, texelSize, mip);
            if (cost < minCost)
            {
                minCost = cost;
                bestFlow = candidateFlow;
                if (minCost < 0.01) //near-perfect match found
                    return bestFlow;
            }
    }
    return bestFlow;
}

float2 PS_RefineFlow64(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return RefineFlow(sLumaFlow128, sCurrLuma, sPrevLuma, uv, BUFFER_PIXEL_SIZE*16.0, 4);
}

float2 PS_FilterFlow64(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return Median9(sLumaFlow64A, uv, BUFFER_PIXEL_SIZE*64.0, 6);
}

float2 PS_RefineFlow32(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return RefineFlow(sLumaFlow64B, sCurrLuma, sPrevLuma, uv, BUFFER_PIXEL_SIZE*8.0, 3);
}

float2 PS_FilterFlow32(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return Median9(sLumaFlow32A, uv, BUFFER_PIXEL_SIZE*32.0, 5);
}

float2 PS_RefineFlow16(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return RefineFlow(sLumaFlow32B, sCurrLuma, sPrevLuma, uv, BUFFER_PIXEL_SIZE*4.0, 2);
}

float2 PS_FilterFlow16(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return Median9(sLumaFlow16A, uv, BUFFER_PIXEL_SIZE*16.0, 4);
}

float2 PS_RefineFlow8(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return RefineFlow(sLumaFlow16B, sCurrLuma, sPrevLuma, uv, BUFFER_PIXEL_SIZE*2.0, 1);
}

float2 PS_FilterFlow8A(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return Median9(sLumaFlow8, uv, BUFFER_PIXEL_SIZE*8.0, 3);
}

float2 PS_FilterFlow8B(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return Median9(sLumaFlow, uv, BUFFER_PIXEL_SIZE*8.0, 3);
}

float2 PS_BlurFlow(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return BilateralBlur(sLumaFlow8, sCurrLuma, uv, BUFFER_PIXEL_SIZE*8.0, 3);
}

float PS_ComputeConfidence(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    if(FRAME_COUNT == 0) return 0.0; //no confidence

    float2 flow = tex2D(sLumaFlow, uv).xy;
    float2 prevUV = uv + flow; //warp prev frame forward
    if(IsOOB(prevUV)) return 0.0;

    float currLuma = tex2Dlod(sCurrLuma, float4(uv, 0, 0)).r; //full res sharp luma feature for photometric err.
    float prevLuma = tex2Dlod(sPrevLuma, float4(prevUV, 0, 0)).r;
    float lumaError = abs(currLuma - prevLuma);

    //looks at the local contrast for pattern confidence
    float sumX = 0, sumX2 = 0, sumY = 0, sumY2 = 0;
    float2 lumaTexSize = BUFFER_PIXEL_SIZE * 4.0;
    static const float2 offsets[5] = {
                      float2(0, 1),
        float2(-1,0), float2(0, 0), float2(1,0),
                      float2(0,-1)
    };
    [unroll]
    for(int i = 0; i < 5; i++) {
        float valCurr = tex2Dlod(sCurrLuma, float4(uv + offsets[i] * lumaTexSize, 0, 2)).r;
        float valPrev = tex2Dlod(sPrevLuma, float4(prevUV + offsets[i] * lumaTexSize, 0, 2)).r;
        sumX += valCurr; sumX2 += valCurr * valCurr;
        sumY += valPrev; sumY2 += valPrev * valPrev;
    }
    float varCurr = max(0.0, (sumX2 / 5.0) - (sumX / 5.0 * sumX / 5.0));
    float varPrev = max(0.0, (sumY2 / 5.0) - (sumY / 5.0 * sumY / 5.0));
    float patternConf = 1.0 - saturate(abs(sqrt(varCurr) - sqrt(varPrev)) / (sqrt(varCurr) + 0.01));

    //look at neighborhood flow for spatial consistency
    float2 flowTexelSize = BUFFER_PIXEL_SIZE * 8.0;
    float2 flowN = tex2Dlod(sLumaFlow, float4(uv + float2(0, -flowTexelSize.y), 0, 0)).xy;
    float2 flowS = tex2Dlod(sLumaFlow, float4(uv + float2(0,  flowTexelSize.y), 0, 0)).xy;
    float2 flowE = tex2Dlod(sLumaFlow, float4(uv + float2( flowTexelSize.x, 0), 0, 0)).xy;
    float2 flowW = tex2Dlod(sLumaFlow, float4(uv + float2(-flowTexelSize.x, 0), 0, 0)).xy;
    float2 avgNeighborFlow = (flowN + flowS + flowE + flowW) * 0.25;
    float spatialDiff = distance(flow, avgNeighborFlow);
    float spatialThreshold = length(flow) * 0.5 + BUFFER_PIXEL_SIZE.x;
    float spatialConfidence = saturate(1.0 - (spatialDiff / (spatialThreshold + EPSILON)));

    //motion length penalty
    float subpixelThreshold = length(BUFFER_PIXEL_SIZE);
    float flowMagnitude = length(flow);
    float lengthConfidence = (flowMagnitude <= subpixelThreshold) ? 1.0 : rcp((flowMagnitude / subpixelThreshold) * 0.05 + 1.0);

    //photometric confidence - use spatial/pattern trust to decide how much to care about the luma error
    float strictness = lengthConfidence * spatialConfidence * patternConf;
    float photometricConfidence = exp(-lumaError * 12.0 * strictness);

    //current frame final confidence
    float currentConf = photometricConfidence * spatialConfidence * lengthConfidence * patternConf;

    //stability filter/temporal hysteresis
    float historyConf = tex2D(sPrevConfidence, prevUV).r;

    return lerp(historyConf, currentConf, 0.15); //low alpha makes conf. stable while a high alpha (e.g 0.5) makes it react to changes quickly
}

float2 PS_StoreFlow(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return tex2D(sLumaFlow, uv).xy;
}

float PS_StoreLuma(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return tex2D(sCurrLuma, uv).r;
}

float PS_StoreConfidence(float4 pos : SV_Position, float2 uv : TEXCOORD): SV_Target
{
    return tex2D(sFlowConfidence, uv).r;
}

float4 PS_ReconstructNormals(VSOUT input) : SV_Target
{
    float depthC = ReShade::GetLinearizedDepth(input.uv);

    const float2 offsetX = float2(BUFFER_PIXEL_SIZE.x, 0);
    const float2 offsetY = float2(0, BUFFER_PIXEL_SIZE.y);

    float3 pC = UVToViewSpace(input.uv, depthC, input);
    float3 pL = UVToViewSpace(input.uv - offsetX, ReShade::GetLinearizedDepth(input.uv - offsetX), input);
    float3 pR = UVToViewSpace(input.uv + offsetX, ReShade::GetLinearizedDepth(input.uv + offsetX), input);
    float3 pT = UVToViewSpace(input.uv - offsetY, ReShade::GetLinearizedDepth(input.uv - offsetY), input);
    float3 pB = UVToViewSpace(input.uv + offsetY, ReShade::GetLinearizedDepth(input.uv + offsetY), input);

    float3 diffX2 = pR - pC;
    float3 diffX1 = pC - pL;
    float3 diffY2 = pB - pC;
    float3 diffY1 = pC - pT;

    float lenSqX2 = dot(diffX2, diffX2);
    float lenSqX1 = dot(diffX1, diffX1);
    float lenSqY2 = dot(diffY2, diffY2);
    float lenSqY1 = dot(diffY1, diffY1);

    float3 ddx = lenSqX2 < lenSqX1 ? diffX2 : diffX1;
    float3 ddy = lenSqY2 < lenSqY1 ? diffY2 : diffY1;
    float3 geoNormal = normalize(cross(ddx, ddy));
    return float4(geoNormal, depthC);
}

#if DEBUG_KERNEL
float4 PS_Debug(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 sceneColor = tex2D(ReShade::BackBuffer, uv).rgb;
    switch(DEBUG_VIEW)
    {
        case 0: discard;
        case 1: {
            float4 gbuffer = tex2D(sKernelNormals, uv);
            float3 normal = gbuffer.rgb;
            float depth = gbuffer.a;
            bool isLeftHalf = uv.x < 0.5;
            float4 dbg;
            if (isLeftHalf)
                dbg = float4(normal * 0.5 + 0.5, 1.0); //left: normals
            else
                dbg = float4(DepthColorMap(depth), 1.0); //right: depth gradient
            return dbg;
        }
        case 2:  return float4(MotionToColor(tex2D(sLumaFlow, uv).xy, uv), 1);
        case 3:  return DrawMotionVectors(uv);
        case 4:
        {
            float confidence = tex2D(sFlowConfidence, uv).x;
            float3 confidenceColor;
            if (confidence < 0.5)
                confidenceColor = lerp(float3(1.0, 0.0, 0.0), float3(1.0, 1.0, 0.0), confidence * 2.0);
            else
                confidenceColor = lerp(float3(1.0, 1.0, 0.0), float3(0.0, 1.0, 0.0), (confidence - 0.5) * 2.0);
            return float4(lerp(sceneColor, confidenceColor, 0.9), 1.0);
        }
        default: return float4(sceneColor, 1.0);
    }
}
#endif

/*----------------.
| :: TECHNIQUE :: |
'----------------*/

technique Lumenite_Kernel <
    ui_label = "LUMENITE: Kernel";
    ui_tooltip = "Pre-effect for LumeniteFX shaders.";
>
{
    //optical flow
    pass { VertexShader = PostProcessVS; PixelShader = PS_CurrLuma;          RenderTarget = tCurrLuma;       }
    pass { VertexShader = PostProcessVS; PixelShader = PS_ComputeFlow128;    RenderTarget = tLumaFlow128;    }
    pass { VertexShader = PostProcessVS; PixelShader = PS_RefineFlow64;      RenderTarget = tLumaFlow64A;    }
    pass { VertexShader = PostProcessVS; PixelShader = PS_FilterFlow64;      RenderTarget = tLumaFlow64B;    }
    pass { VertexShader = PostProcessVS; PixelShader = PS_RefineFlow32;      RenderTarget = tLumaFlow32A;    }
    pass { VertexShader = PostProcessVS; PixelShader = PS_FilterFlow32;      RenderTarget = tLumaFlow32B;    }
    pass { VertexShader = PostProcessVS; PixelShader = PS_RefineFlow16;      RenderTarget = tLumaFlow16A;    }
    pass { VertexShader = PostProcessVS; PixelShader = PS_FilterFlow16;      RenderTarget = tLumaFlow16B;    }
    pass { VertexShader = PostProcessVS; PixelShader = PS_RefineFlow8;       RenderTarget = tLumaFlow8;      }
    pass { VertexShader = PostProcessVS; PixelShader = PS_FilterFlow8A;      RenderTarget = tLumaFlow;       }
    pass { VertexShader = PostProcessVS; PixelShader = PS_FilterFlow8B;      RenderTarget = tLumaFlow8;      }
    pass { VertexShader = PostProcessVS; PixelShader = PS_BlurFlow;          RenderTarget = tLumaFlow;       }
    pass { VertexShader = PostProcessVS; PixelShader = PS_ComputeConfidence; RenderTarget = tFlowConfidence; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_StoreFlow;         RenderTarget = tPrevFrameFlow;  }
    pass { VertexShader = PostProcessVS; PixelShader = PS_StoreLuma;         RenderTarget = tPrevLuma;       }
    pass { VertexShader = PostProcessVS; PixelShader = PS_StoreConfidence;   RenderTarget = tPrevConfidence; }

    //normals
    pass { VertexShader = VS; PixelShader = PS_ReconstructNormals; RenderTarget = tKernelNormals; }

    //debug views
    #if DEBUG_KERNEL
    pass { VertexShader = PostProcessVS; PixelShader = PS_Debug; }
    #endif
}

}
