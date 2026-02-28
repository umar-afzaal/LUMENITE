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


        Filename   : lumenite_SSR.fx
        Version    : 2026.02.28
        Author     : Afzaal (Kaidō)
        Description: Screen Space Reflections.
        License    : AGNYA License (https://github.com/nvb-uy/AGNYA-License)

        ========================================================================
*/


#include "ReShade.fxh"
#include "./include/lumenite_Projections.fxh"

/*------------------.
| :: DEFINITIONS :: |
'------------------*/

// Core
#define PI 3.14159265359
#define EPSILON 1e-6
#define FOV 60.0
#define REF_WIDTH 2560.0  // Don't change
#define REF_HEIGHT 1440.0 // Same
#define WIDTH_SCALE (BUFFER_WIDTH / REF_WIDTH)
#define HEIGHT_SCALE (BUFFER_HEIGHT / REF_HEIGHT)

// Backbuffer preprocessing
#define SPEC_AMBIENT_REMOVAL 0.7

// HiZ Acceleration
#define HiZ_MAX_RAY_STEPS 100
#define HiZ_RAY_LEAP_FACTOR 0.2

// Specular
#define SPEC_INTENSITY_SCALER 5.0
#define SPEC_MAX_MARCHING_STEPS 1000
#define SPEC_RAY_LENGTH_SCALE 9.0
#define SPEC_TAIL_FEATHERING_SCALER 5.0
#define SPEC_METALLICNESS_SCALER 5.0
#define SPEC_KERNEL_SIZE_H ((int)(1 * WIDTH_SCALE))
#define SPEC_KERNEL_SIZE_V ((int)(1 * HEIGHT_SCALE))
#define SPEC_SPATIAL_WEIGHT_SCALE_H (8.0 * WIDTH_SCALE)
#define SPEC_SPATIAL_WEIGHT_SCALE_V (8.0 * HEIGHT_SCALE)
#define SPEC_NORMAL_WEIGHT_SCALE_H (8.0 * WIDTH_SCALE)
#define SPEC_NORMAL_WEIGHT_SCALE_V (8.0 * HEIGHT_SCALE)

// Temporal Blending
#define HISTORY_BLEND 0.95
#define MOTION_CONFIDENCE_BOOST 0.3

// Normals
#define TEX_NORMAL_STRENGTH 2.0
#define TEX_DETAIL_SENSITIVITY 5.0

// Highlight protection
#define HIGHLIGHT_PROTECTION_LOG_POWER 2.5
#define HIGHLIGHT_PROTECTION_SCALER 4.0

/*---------------.
| :: UNIFORMS :: |
'---------------*/

uniform bool DEBUG_VIEW <
    ui_label = "Show SSR Mask";
    ui_tooltip = "Debug view for SSR.";
    ui_category = "SSR";
> = 0;


uniform float depthBoundary <
    ui_type = "slider";
    ui_min = 0.001; ui_max = 0.999; ui_step = 0.001;
    ui_label = "Effect Range";
    ui_tooltip = "The Z+ range/depth in which the effect is applied.";
    ui_category = "SSR";
    hidden = false;
> = 0.6;

uniform float DepthFadeStart <
    ui_type = "slider";
    ui_min = 0.1; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Z+ Fade Start (%)";
    ui_tooltip = "Z+ fraction where effect starts fading out (relative to Z+ boundary)";
    ui_category = "SSR";
    hidden = true;
> = 0.75;

uniform float specularMetallicness <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.001;
    ui_label = "Metallicness";
    ui_tooltip = "How metallic the reflections should be.";
    ui_category = "SSR";
> = 1.0;

uniform float SpecularIntensity <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Specular Intensity";
    ui_category = "SSR";
    ui_tooltip = "Controls the intensity of the specular light.";
    hidden = true;
> = 1.0;

uniform float SpecularTailFeathering <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.001;
    ui_label = "Tail Feathering";
    ui_tooltip = "Softens the tail-end of the reflections.";
    ui_category = "SSR";
> = 0.0;

uniform int SpecularBlur <
    ui_type = "slider";
    ui_items = "Disable Blur\0Enable Blur\0";
    ui_label = "Blur";
    ui_category = "SSR";
    ui_tooltip = "Blurs the SSR mask.";
> = 0;

uniform int ChromaticDistortionSpecular <
    ui_type = "slider";
    ui_items = "Disable Distortion\0Enable Distortion\0";
    ui_label = "Chromatic Distortion";
    ui_tooltip = "Distorts the SSR chroma.";
    ui_category = "SSR";
> = 0;

uniform int TexNormalsRayStartPos <
    ui_type = "slider";
    ui_items = "Disable\0Enable\0";
    ui_label = "Scattering";
    ui_category = "SSR";
    hidden = true;
> = 0;

uniform float specularContrast <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.1;
    ui_label = "Floor Contrast (Experimental)";
    ui_tooltip = "Extra darkening for pixels that receive weak Specular light";
    ui_category = "SSR";
    hidden = true;
> = 0.0;

/*--------------.
| :: IMPORTS :: |
'--------------*/

//=== Optical Flow
texture2D tLumaFlow { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = RG16F; };
sampler2D sLumaFlow { Texture = tLumaFlow; MagFilter = POINT; MinFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP; };

texture2D tFlowConfidence { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = R16F; };
sampler2D sFlowConfidence { Texture = tFlowConfidence; MagFilter = POINT; MinFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP; };

//=== Surface Normals
texture tKernelNormals { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sKernelNormals { Texture = tKernelNormals; };

namespace LumeniteSSR {

/*---------------------.
| :: RENDER TARGETS :: |
'---------------------*/

texture lumenite_NormalHTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; }; // RGB = normal, A = depth
sampler NormalHSampler { Texture = lumenite_NormalHTex; };

texture lumenite_TexturedNormalTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; }; // RGB = normal, A = depth
sampler TexturedNormalSampler { Texture = lumenite_TexturedNormalTex; };

//=== Specular
texture lumenite_PreprocessSpecularTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler PreprocessSpecularSampler { Texture = lumenite_PreprocessSpecularTex; };

texture lumenite_SpecularTex { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; };
sampler SpecularSampler { Texture = lumenite_SpecularTex; AddressU = CLAMP; AddressV = CLAMP; };

texture lumenite_SpecularHTex { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; };
sampler SpecularHSampler { Texture = lumenite_SpecularHTex; AddressU = CLAMP; AddressV = CLAMP; };

//=== Temporal Smoothing
// A = Validity Flag (1.0 = valid)
texture lumenite_PrevSpecularTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler PrevSpecularSampler { Texture = lumenite_PrevSpecularTex; AddressU = CLAMP; AddressV = CLAMP; };

texture lumenite_PrevFrameColorTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler PrevFrameColorSampler { Texture = lumenite_PrevFrameColorTex; AddressU = CLAMP; AddressV = CLAMP; };

//=== HiZ Acceleration
// Single texture chain storing min depth in R channel
texture HiZ_Mip0 { Width = BUFFER_WIDTH;    Height = BUFFER_HEIGHT;    Format = R16F; };
texture HiZ_Mip1 { Width = BUFFER_WIDTH/2;  Height = BUFFER_HEIGHT/2;  Format = R16F; };
texture HiZ_Mip2 { Width = BUFFER_WIDTH/4;  Height = BUFFER_HEIGHT/4;  Format = R16F; };
texture HiZ_Mip3 { Width = BUFFER_WIDTH/8;  Height = BUFFER_HEIGHT/8;  Format = R16F; };
texture HiZ_Mip4 { Width = BUFFER_WIDTH/16; Height = BUFFER_HEIGHT/16; Format = R16F; };
texture HiZ_Mip5 { Width = BUFFER_WIDTH/32; Height = BUFFER_HEIGHT/32; Format = R16F; };

sampler HiZ_Sampler0 { Texture = HiZ_Mip0; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };
sampler HiZ_Sampler1 { Texture = HiZ_Mip1; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };
sampler HiZ_Sampler2 { Texture = HiZ_Mip2; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };
sampler HiZ_Sampler3 { Texture = HiZ_Mip3; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };
sampler HiZ_Sampler4 { Texture = HiZ_Mip4; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };
sampler HiZ_Sampler5 { Texture = HiZ_Mip5; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };

/*----------------------.
| :: DATA STRUCTURES :: |
'----------------------*/

struct HiZData
{
    float min_depth;
};

/*-----------------------.
| :: HELPER FUNCTIONS :: |
'-----------------------*/

float GetLuminance(float3 color)
{
    return dot(color, float3(0.2126, 0.7152, 0.0722));  // ITU-R BT.709 (sRGB/HDTV)
}

float3 GetColor(float2 uv)
{
    float3 color = tex2D(ReShade::BackBuffer, uv).rgb;
    // Optionally, do some processing and then return
    return color;
}

float GetDepth(float2 uv)
{
	return ReShade::GetLinearizedDepth(uv);
}

//=== HiZ Acceleration
HiZData Sample2x2_FromScene(float2 current_uv)
{
    float2 texel_size = ReShade::PixelSize;
    float2 block_origin_uv = floor(current_uv / (texel_size * 2.0)) * (texel_size * 2.0);

    float2 uvs[4] = {
        block_origin_uv + texel_size * float2(0.5, 0.5),
        block_origin_uv + texel_size * float2(1.5, 0.5),
        block_origin_uv + texel_size * float2(0.5, 1.5),
        block_origin_uv + texel_size * float2(1.5, 1.5)
    };

    float depths[4];
    [unroll]
    for (int i = 0; i < 4; i++) {
        depths[i] = ReShade::GetLinearizedDepth(uvs[i]);
    }

    HiZData result;
    result.min_depth = min(min(depths[0], depths[1]), min(depths[2], depths[3]));
    return result;
}

HiZData SampleFromPreviousHiZ(float2 center_uv, sampler s, int source_mip_level)
{
    float2 source_texel_size = ReShade::PixelSize * pow(2, source_mip_level);

    float2 offsets[4] = {
        float2(-0.5, -0.5) * source_texel_size,
        float2( 0.5, -0.5) * source_texel_size,
        float2(-0.5,  0.5) * source_texel_size,
        float2( 0.5,  0.5) * source_texel_size
    };

    float min_depth = 1.0;

    [unroll]
    for(int i = 0; i < 4; i++) {
        float2 sample_uv = center_uv + offsets[i];
        float hiz_data = tex2D(s, sample_uv).r;
        min_depth = min(min_depth, hiz_data);
    }

    HiZData result;
    result.min_depth = min_depth;
    return result;
}

//=== Normals
float3 ExtractTexturedNormals(float2 uv, float3 geometricNormal)
{
    // Extract textured normals from color gradients
    float2 texelSize = ReShade::PixelSize;

    // Sample color in cross pattern for texture gradient analysis
    float3 colorCenter = GetColor(uv);
    float3 colorLeft   = GetColor(uv + float2(-texelSize.x, 0));
    float3 colorRight  = GetColor(uv + float2(texelSize.x, 0));
    float3 colorUp     = GetColor(uv + float2(0, -texelSize.y));
    float3 colorDown   = GetColor(uv + float2(0, texelSize.y));

    // Convert to luminance for gradient calculation
    float lumCenter = GetLuminance(colorCenter);
    float lumLeft   = GetLuminance(colorLeft);
    float lumRight  = GetLuminance(colorRight);
    float lumUp     = GetLuminance(colorUp);
    float lumDown   = GetLuminance(colorDown);

    // Calculate texture gradients (Sobel-like)
    float gradX = (lumRight - lumLeft) * 0.5;
    float gradY = (lumDown - lumUp) * 0.5;

    // Enhanced gradient detection using color channel differences
    float3 colorGradX = (colorRight - colorLeft) * 0.5;
    float3 colorGradY = (colorDown - colorUp) * 0.5;

    // Use saturation changes to detect texture detail
    float satCenter = length(colorCenter - lumCenter);
    float satLeft   = length(colorLeft - lumLeft);
    float satRight  = length(colorRight - lumRight);
    float satUp     = length(colorUp - lumUp);
    float satDown   = length(colorDown - lumDown);

    float satGradX = (satRight - satLeft) * 0.5;
    float satGradY = (satDown - satUp) * 0.5;

    // Combine luminance and saturation gradients
    float finalGradX = (gradX + satGradX * 0.5) * TEX_DETAIL_SENSITIVITY;
    float finalGradY = (gradY + satGradY * 0.5) * TEX_DETAIL_SENSITIVITY;

    // Convert gradients to normal perturbation
    float3 texturedNormal = float3(
        finalGradX * TEX_NORMAL_STRENGTH,
        finalGradY * TEX_NORMAL_STRENGTH,
        1.0
    );

    texturedNormal = normalize(texturedNormal);

    // Blend texture normal with geometric normal
    // Preserves the surface shape while adding texture detail
    float3 blendedNormal = normalize(float3(
        geometricNormal.xy + texturedNormal.xy * TEX_NORMAL_STRENGTH,
        geometricNormal.z * texturedNormal.z
    ));

    return blendedNormal;
}

//=== Specular
bool IsFloor(float3 normal, float3 surfacePos)
{
    // Check if surface normal points mostly upward (Y+ is up in view space)
    float upwardness = dot(normal, float3(0, 1, 0));

    // Basic floor check
    bool isBasicFloor = (upwardness > 0.7); // Relaxed threshold

    // Fast coherence check - if looking down at floor, be more permissive
    // Check if we're in a "floor-dominant" view by sampling center normal
    float3 centerNormal = tex2D(sKernelNormals, float2(0.5, 0.5)).rgb;
    float centerUpwardness = dot(centerNormal, float3(0, 1, 0));
    bool floorDominantView = (centerUpwardness > 0.6);

    // In floor-dominant views, lower the threshold
    float threshold = floorDominantView ? 0.4 : 0.7;

    return (upwardness > threshold);
}

//=== Surface Reflectance Functions
float CalculateSpecularBRDF(float3 normal, float3 lightDir, float3 viewDir)
{
    float NdotL = saturate(dot(normal, lightDir));
    float NdotV = saturate(dot(normal, viewDir));

    if (NdotL < 0.001 || NdotV < 0.001) return NdotL; // Fallback to Lambert

    // Darkening factor with safety checks
    float product = max(NdotL * NdotV, 0.001); // Prevent zero base
    float exponent = 2.0 - 1.0;

    // Handle negative exponents safely
    float darkening;
    if (exponent < 0.0) {
        darkening = pow(product, exponent); // For negative exponents, clamp result to prevent extreme values
        darkening = min(darkening, 10.0); // Prevent extreme brightening
    } else {
        darkening = pow(product, exponent);
    }

    return NdotL * darkening;
}

//=== Core Settings
float CalculateDepthFade(float depth)
{
    float fadeStartDepth = depthBoundary * DepthFadeStart;
    float fadeRange = depthBoundary - fadeStartDepth;

    if (depth <= fadeStartDepth) {
        return 1.0; // Full strength
    } else if (depth >= depthBoundary) {
        return 0.0; // No contribution
    } else {
        // Linear fade from 1.0 to 0.0
        return 1.0 - ((depth - fadeStartDepth) / fadeRange);
    }
}

/*--------------------.
| :: PIXEL SHADERS :: |
'--------------------*/

//=== HiZ Acceleration
// Since min depth cannot be provided by hardware generated mipmaps - We cook the sauce ourselves
float PS_GenerateMip0(VSOUT input) : SV_Target
{
    HiZData data = Sample2x2_FromScene(input.uv);

    // If the closest object is already beyond our tracing boundary, treat it as being at the far plane to ensure
    // rays don't get intersection information from culled areas.
    if (data.min_depth > depthBoundary) data.min_depth = 1.0;
    return float(data.min_depth);
}

float PS_ReduceMip1(VSOUT input) : SV_Target
{
    HiZData data = SampleFromPreviousHiZ(input.uv, HiZ_Sampler0, 0);
    return float(data.min_depth);
}

float PS_ReduceMip2(VSOUT input) : SV_Target
{
    HiZData data = SampleFromPreviousHiZ(input.uv, HiZ_Sampler1, 1);
    return float(data.min_depth);
}

float PS_ReduceMip3(VSOUT input) : SV_Target
{
    HiZData data = SampleFromPreviousHiZ(input.uv, HiZ_Sampler2, 2);
    return float(data.min_depth);
}

float PS_ReduceMip4(VSOUT input) : SV_Target
{
    HiZData data = SampleFromPreviousHiZ(input.uv, HiZ_Sampler3, 3);
    return float(data.min_depth);
}

float PS_ReduceMip5(VSOUT input) : SV_Target
{
    HiZData data = SampleFromPreviousHiZ(input.uv, HiZ_Sampler4, 4);
    return float(data.min_depth);
}

//=== Normals
float4 PS_ReconstructNormals(VSOUT input) : SV_Target
{
    float4 gbuffer = tex2D(sKernelNormals, input.uv);
    float3 geoNormal = gbuffer.rgb;
    float depth = gbuffer.a;
    return float4(ExtractTexturedNormals(input.uv, geoNormal), depth);
}

// This is more of a Normal smoothing of Edges. Helps specular a lot at edges with Optical Flow (Jittery Depth buffer scenario)
float4 PS_SmoothNormals_H(VSOUT input) : SV_Target
{
    float4 centerData = tex2D(TexturedNormalSampler, input.uv);
    float3 centerNormal = centerData.rgb;
    float centerDepth = centerData.a;

    if (centerDepth > depthBoundary) {
        return centerData;
    }

    float3 weightedNormal = centerNormal;
    float totalWeight = 1.0;

    [unroll]
    for (int x = -5; x <= 5; x++) {
        //if (x == 0) continue; // Skip center

        float2 sampleUV = input.uv + ReShade::PixelSize * float2(x, 0);
        float4 sampleData = tex2Dlod(TexturedNormalSampler, float4(sampleUV, 0, 0));
        float3 sampleNormal = sampleData.rgb;
        float sampleDepth = sampleData.a;

        // Similarity weight based on normal dot product
        float normalWeight = saturate(dot(centerNormal, sampleNormal));

        // Spatial weight (Gaussian)
        float spatialWeight = exp(-(x * x) / 8.0);

        float weight = normalWeight * spatialWeight;

        weightedNormal += sampleNormal * weight;
        totalWeight += weight;
    }

    return float4(normalize(weightedNormal / totalWeight), centerDepth);
}

float4 PS_SmoothNormals_V(VSOUT input) : SV_Target
{
    float4 centerData = tex2D(NormalHSampler, input.uv);
    float3 centerNormal = centerData.rgb;
    float centerDepth = centerData.a;

    if (centerDepth > depthBoundary) {
        return centerData;
    }

    float3 weightedNormal = centerNormal;
    float totalWeight = 1.0;

    [unroll]
    for (int y = -5; y <= 5; y++) {
        //if (y == 0) continue; // Skip center

        float2 sampleUV = input.uv + ReShade::PixelSize * float2(0, y);
        float4 sampleData = tex2Dlod(NormalHSampler, float4(sampleUV, 0, 0));
        float3 sampleNormal = sampleData.rgb;
        float sampleDepth = sampleData.a;

        // Similarity weight based on normal dot product
        float normalWeight = saturate(dot(centerNormal, sampleNormal));

        // Spatial weight (Gaussian)
        float spatialWeight = exp(-(y * y) / 8.0);

        float weight = normalWeight * spatialWeight;

        weightedNormal += sampleNormal * weight;
        totalWeight += weight;
    }

    return float4(normalize(weightedNormal / totalWeight), centerDepth);
}

//=== Preprocessing
float4 PS_Preprocess(VSOUT input) : SV_Target
{
    float3 color = GetColor(input.uv);
    float lum = GetLuminance(color);
    // Avoid processing very dark colors to prevent division by zero
    if (lum < 0.001)
        return float4(color, 1.0);

    // Calculate ambient estimate
    float avgChannel = (color.r + color.g + color.b) / 3.0;
    float minChannel = min(min(color.r, color.g), color.b);
    float ambientEstimate = lerp(minChannel, avgChannel, 0.7);

    // Ambient correction. Pure only: Multiplicative scaling (preserves hue)
    float specularReductionAmount = ambientEstimate * SPEC_AMBIENT_REMOVAL;
    float specularScaleFactor = saturate(1.0 - specularReductionAmount / lum);
    float3 specularResult = color * specularScaleFactor;

    return float4(specularResult, 1.0);
}



//=== Specular
float4 PS_TraceSpecular(VSOUT input) : SV_Target
{

    float4 gbuffer;

    if (TexNormalsRayStartPos)
        gbuffer = tex2D(TexturedNormalSampler, input.uv);
    else
        gbuffer = tex2D(sKernelNormals, input.uv);


    float3 N = gbuffer.rgb;
    float depth = gbuffer.a;

    if (depth == 0 || depth > depthBoundary) return float4(0, 0, 0, 1);

    float3 StartPos = UVToViewSpace(input.uv, depth, input);
    float3 viewDir = normalize(-StartPos); // Camera at origin, -StartPos points surface-to-camera

    // Estimate surface material
    float3 surfaceColor = tex2D(PreprocessSpecularSampler, input.uv).rgb;

    // 'rayLengthScale' controls how far the ray should travel relative to the pixel's distance.
    // We calculate the total ray length, but use min() to cap it at the remaining distance
    // to the far plane (1.0 - depth). This ensures rays stay within the visible scene.
    float dynamicRayLengthNormalized = min(SPEC_RAY_LENGTH_SCALE * depth, 1.0 - depth);

    // To get the size of a single step in normalized view-space, we divide the total
    // normalized length by the number of steps. This is the final value needed by the ray marcher.
    float stepSize = dynamicRayLengthNormalized / SPEC_MAX_MARCHING_STEPS;

    float3 currentDir = reflect(-viewDir, N); // Use simple mirror reflection

    // Skip this ray if no valid reflection
    if (dot(currentDir, currentDir) < 0.001) {
        return float4(0, 0, 0, 1);
    }

    float3 currentPos = StartPos + N * stepSize; // Match step size- prefer smaller offset, precision reflections or energy concentration
    float3 rayEnergy = float3(1.0, 1.0, 1.0);
    float3 specularLight = 0.0;
    float t = 0.0;
    bool hitFound = false;
    int iterations = 0; // Safety counter to prevent infinite loops

    while (t < dynamicRayLengthNormalized && !hitFound && iterations < HiZ_MAX_RAY_STEPS)
    {
        float hiz_min_depth;
        float2 uv_hit = ViewSpaceToUV(currentPos, input);

        if (any(uv_hit < 0.0) || any(uv_hit > 1.0)) break;

        // Calculate ideal mip based on ray's projected footprint
        float2 ray_screen_velocity = abs(currentDir.xy / currentPos.z) * float2(BUFFER_WIDTH, BUFFER_HEIGHT);
        float footprint_pixels = max(ray_screen_velocity.x, ray_screen_velocity.y) * max(stepSize / currentPos.z, 1.0);
        int mip_level = clamp(log2(max(footprint_pixels, 1.0)), 0, 5);

        // Sample from the dynamically chosen mip level
             if (mip_level == 5) hiz_min_depth = tex2Dlod(HiZ_Sampler5, float4(uv_hit, 0, 0)).r;
        else if (mip_level == 4) hiz_min_depth = tex2Dlod(HiZ_Sampler4, float4(uv_hit, 0, 0)).r;
        else if (mip_level == 3) hiz_min_depth = tex2Dlod(HiZ_Sampler3, float4(uv_hit, 0, 0)).r;
        else if (mip_level == 2) hiz_min_depth = tex2Dlod(HiZ_Sampler2, float4(uv_hit, 0, 0)).r;
        else if (mip_level == 1) hiz_min_depth = tex2Dlod(HiZ_Sampler1, float4(uv_hit, 0, 0)).r;
        else                     hiz_min_depth = tex2Dlod(HiZ_Sampler0, float4(uv_hit, 0, 0)).r;

        // Decide step size: Leap if space is empty, or a small precise step if near a surface
        float currentStepSize = (currentPos.z < hiz_min_depth) ? (hiz_min_depth - currentPos.z) * HiZ_RAY_LEAP_FACTOR : stepSize;

        // Advance the ray, ensuring we always move at least a small amount
        currentPos += currentDir * max(stepSize, currentStepSize);
        t += max(stepSize, currentStepSize);

        // Intersection Test & Hit Processing
        // Recalculate uv_hit for the ray's NEW position before the intersection test
        uv_hit = ViewSpaceToUV(currentPos, input);
        if (any(uv_hit < 0.0) || any(uv_hit > 1.0)) break; // Check bounds again after step

        float sceneDepth = ReShade::GetLinearizedDepth(uv_hit);
        if (sceneDepth > depthBoundary) continue; // jump to next iteration if invalid depth

        float3 scenePos = UVToViewSpace(uv_hit, sceneDepth, input);
        float dynamicThickness = currentPos.z * 0.232 * 0.5;

        if (currentPos.z > scenePos.z && (currentPos.z - scenePos.z) < dynamicThickness) {

            // Hit Logic
            float3 hitColor = tex2Dlod(PreprocessSpecularSampler, float4(saturate(uv_hit), 0, 0)).rgb;

            if (ChromaticDistortionSpecular) {
                float4 texturedData = tex2Dlod(TexturedNormalSampler, float4(uv_hit, 0, 0));
                float3 textureInfluence = (texturedData.rgb * 2.0 - 1.0) * TEX_NORMAL_STRENGTH * 0.2;
                hitColor *= (1.0 + textureInfluence);
            }

            float4 hitNormalDepthData = tex2Dlod(sKernelNormals, float4(uv_hit, 0, 0));
            float3 hitNormal = hitNormalDepthData.rgb;

            // Specular BRDF with Fresnel
            float3 lightDir = -currentDir;
            float3 viewDir = normalize(-StartPos);
            float NdotL = CalculateSpecularBRDF(hitNormal, lightDir, viewDir);
            float NdotV = saturate(dot(viewDir, N));
            float fresnel = pow(1.0 - NdotV, 5.0);

            // Metallic workflow
            float3 F0 = lerp(0.04, surfaceColor, specularMetallicness * SPEC_METALLICNESS_SCALER);
            float3 specularResponse = F0 + (1.0 - F0) * fresnel;
            float attenuation = exp(-t * 2.0);

            // Distance fade based on how far we've traveled (t) vs the max possible distance.
            // This is more accurate than using the iteration count.
            float distance_ratio = t / dynamicRayLengthNormalized;
            float max_distance_fade = pow(saturate(1.0 - distance_ratio), (SpecularTailFeathering * SPEC_TAIL_FEATHERING_SCALER) + EPSILON);

            specularLight += hitColor * specularResponse * attenuation * NdotL * max_distance_fade;

            hitFound = true;
        }

        iterations++; // safety counter
    }

    return float4(specularLight, 1.0);
}

float4 PS_BlurSpecular_H(VSOUT input) : SV_Target
{
    if (!SpecularBlur) {
        discard;
    }

    float2 texelSize = float2(1.0 / (BUFFER_WIDTH / 4), 0);
    float3 result = 0;
    float totalWeight = 0;
    float3 centerNormal = tex2D(sKernelNormals, input.uv).rgb;

    [unroll]
    for (int x = -SPEC_KERNEL_SIZE_H; x <= SPEC_KERNEL_SIZE_H; x++) {
        //if (x == 0) continue;
        float2 sampleUV = input.uv + texelSize * x;
        float3 sampleNormal = tex2D(sKernelNormals, sampleUV).rgb;

        float spatialWeight = exp(-(x * x) / SPEC_SPATIAL_WEIGHT_SCALE_H);
        float normalWeight = pow(saturate(dot(centerNormal, sampleNormal)), SPEC_NORMAL_WEIGHT_SCALE_H);
        float weight = spatialWeight * normalWeight;

        result += tex2D(SpecularSampler, sampleUV).rgb * weight;
        totalWeight += weight;
    }

    return float4(result / (totalWeight + EPSILON), 1.0);
}

float4 PS_BlurSpecular_V(VSOUT input) : SV_Target
{
    if (!SpecularBlur) {
        discard;
    }

    float2 texelSize = float2(0, 1.0 / (BUFFER_HEIGHT / 4));
    float3 result = 0;
    float totalWeight = 0;
    float3 centerNormal = tex2D(sKernelNormals, input.uv).rgb;

    [unroll]
    for (int y = -SPEC_KERNEL_SIZE_V; y <= SPEC_KERNEL_SIZE_V; y++) {
        //if (y == 0) continue;
        float2 sampleUV = input.uv + texelSize * y;
        float3 sampleNormal = tex2D(sKernelNormals, sampleUV).rgb;

        float spatialWeight = exp(-(y * y) / SPEC_SPATIAL_WEIGHT_SCALE_V);
        float normalWeight = pow(saturate(dot(centerNormal, sampleNormal)), SPEC_NORMAL_WEIGHT_SCALE_V);
        float weight = spatialWeight * normalWeight;

        result += tex2D(SpecularHSampler, sampleUV).rgb * weight;
        totalWeight += weight;
    }

    return float4(result / (totalWeight + EPSILON), 1.0);
}

//=== Composition
float4 PS_TemporalBlend(VSOUT input) : SV_Target
{
    float3 current = tex2D(SpecularSampler, input.uv).rgb;
    float2 flow = tex2D(sLumaFlow, input.uv).xy;
    float confidence = tex2D(sFlowConfidence, input.uv).x;
    confidence = saturate(confidence + log2(2.0 - confidence) * MOTION_CONFIDENCE_BOOST);

    // Look at the previous frame texture at the position 'offset by flow'
    float4 historyData = tex2D(PrevSpecularSampler, input.uv + flow);
    float3 historyColor = historyData.rgb;
    float historyValidity = historyData.a; // Check Alpha: 0 = Empty, 1 = Valid

    // If validity is 0 (first frame), weight is 0 (use 100% current).
    // Otherwise use Confidence * HISTORY_BLEND.
    float blendWeight = (historyValidity < 0.5) ? 0.0 : (confidence * HISTORY_BLEND);

    float3 blended = lerp(current, historyColor, blendWeight);

    // Return blended color. Alpha 1.0 ensures we are writing valid data to the target.
    return float4(blended, 1.0);
}

float4 PS_StoreHistory(VSOUT input) : SV_Target
{
    float3 finalColor = tex2D(SpecularHSampler, input.uv).rgb;
    return float4(finalColor, 1.0); // Store it with Alpha 1.0 to say "I have data"
}

float4 PS_Blend(VSOUT input) : SV_Target
{
    float3 base = GetColor(input.uv);
    float4 gbuffer = tex2D(sKernelNormals, input.uv);
    float3 normal = gbuffer.rgb;
    float depth = gbuffer.a;
    float3 surface_pos = UVToViewSpace(input.uv, depth, input);
    float depthFade = CalculateDepthFade(depth);

    float3 normal_delta = tex2D(TexturedNormalSampler, input.uv).rgb - normal;
    float bump_detail = length(normal_delta);
    // Perturb uv based on normal direction (simulate reflection or light scattering from bumps)
    float2 perturbation = normal_delta.xy * 0.01 * bump_detail;
    float3 specular = tex2D(SpecularHSampler, input.uv).rgb;
    float3 perturbed_specular = tex2D(SpecularHSampler, input.uv + perturbation).rgb;
    specular = lerp(specular, perturbed_specular, saturate(bump_detail));
    specular *= depthFade;
    specular *= SpecularIntensity * SPEC_INTENSITY_SCALER;
    specular = saturate(specular);

    if (DEBUG_VIEW)
        return float4(specular * depthFade, 1.0);

    if (specularContrast > 0.0) {
        bool isFloorPixel = IsFloor(normal, surface_pos);

        if (isFloorPixel) {
            float specularMagnitude = GetLuminance(specular);
            float darkening = (1.0 - saturate(specularMagnitude / 0.1)) * specularContrast * depthFade;
            base *= (1.0 - darkening);
        }
    }

    // Highlight protection
    float highlightMask = 1.0 / (1.0 + pow(GetLuminance(base), HIGHLIGHT_PROTECTION_LOG_POWER) * (HIGHLIGHT_PROTECTION_SCALER));
    specular *= highlightMask;

    return float4(saturate(base+specular), 1.0);

}


/*----------------.
| :: TECHNIQUE :: |
'----------------*/
technique LUMENITE_SSR <
    ui_label = "LUMENITE: SSR";
    ui_tooltip = "Screen Space Reflections.";
>
{
    // HiZ Acceleration
    pass { VertexShader = VS; PixelShader = PS_GenerateMip0; RenderTarget = HiZ_Mip0; }
    pass { VertexShader = VS; PixelShader = PS_ReduceMip1;   RenderTarget = HiZ_Mip1; }
    pass { VertexShader = VS; PixelShader = PS_ReduceMip2;   RenderTarget = HiZ_Mip2; }
    pass { VertexShader = VS; PixelShader = PS_ReduceMip3;   RenderTarget = HiZ_Mip3; }
    pass { VertexShader = VS; PixelShader = PS_ReduceMip4;   RenderTarget = HiZ_Mip4; }
    pass { VertexShader = VS; PixelShader = PS_ReduceMip5;   RenderTarget = HiZ_Mip5; }

    // Normals
    pass { VertexShader = VS; PixelShader = PS_ReconstructNormals; RenderTarget = lumenite_TexturedNormalTex; }
    pass { VertexShader = VS; PixelShader = PS_SmoothNormals_H; RenderTarget = lumenite_NormalHTex; }
    pass { VertexShader = VS; PixelShader = PS_SmoothNormals_V; RenderTarget = lumenite_TexturedNormalTex; }

    // Color Preprocessing
    pass { VertexShader = VS; PixelShader = PS_Preprocess; RenderTarget = lumenite_PreprocessSpecularTex; }

    // Specular Path
    pass { VertexShader = VS; PixelShader = PS_TraceSpecular; RenderTarget = lumenite_SpecularTex; }
    pass { VertexShader = VS; PixelShader = PS_BlurSpecular_H; RenderTarget = lumenite_SpecularHTex; }
    pass { VertexShader = VS; PixelShader = PS_BlurSpecular_V; RenderTarget = lumenite_SpecularTex; }

    pass { VertexShader = VS; PixelShader = PS_TemporalBlend; RenderTarget = lumenite_SpecularHTex; }
    pass { VertexShader = VS; PixelShader = PS_Blend; }
    pass { VertexShader = VS; PixelShader = PS_StoreHistory; RenderTarget = lumenite_PrevSpecularTex; }
}

}
