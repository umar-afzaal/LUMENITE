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


        Filename   : lumenite_AnamorphicBloom.fx
        Version    : 2026.05.17
        Author     : Afzaal (Kaidō)
        Description: Artistic bloom approximating the Anamorphic lens aesthetic.
        License    : AGNYA License (https://github.com/nvb-uy/AGNYA-License)

        ========================================================================
*/

/*------------------.
| :: DEFINITIONS :: |
'------------------*/
#ifndef ANAMORPHIC_BLOOM
    #define ANAMORPHIC_BLOOM 1
#endif

#ifndef ANAMORPHIC_STREAKS
    #define ANAMORPHIC_STREAKS 0
#endif

#ifndef COLOR_FRINGING
    #define COLOR_FRINGING 0
#endif

#define BLOOM_THRESHOLD_SCALER 10.0

/*--------------.
| :: HEADERS :: |
'--------------*/
#include "ReShade.fxh"
#include "./include/lumenite_ColorManagement.fxh"
#include "./include/lumenite_Helpers.fxh"

/*---------------.
| :: UNIFORMS :: |
'---------------*/
#if ANAMORPHIC_BLOOM
    uniform bool BLOOM_SKIP_SKYBOX <
        ui_type = "radio";
        ui_label = "Exclude Skybox (Bloom)";
        ui_tooltip = "Prevents sky pixels from contributing to bloom.";
        ui_category = "Anamorphic Bloom";
    > = false;

    uniform bool BLOOM_SHARP <
        ui_type = "radio";
        ui_label = "Add More Definition to Bloom Shape (Experimental)";
        ui_tooltip = "Enables a sharper 1D horizontal kernel. May flicker with camera movement.";
        ui_category = "Anamorphic Bloom";
    > = false;

    uniform float BLOOM_INTENSITY <
        ui_type = "drag";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
        ui_label = "Bloom Intensity";
        ui_tooltip = "Scales the intensity of the Bloom effect.";
        ui_category = "Anamorphic Bloom";
    > = 1.0;

    uniform float BLOOM_THRESHOLD <
        ui_type = "drag";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
        ui_label = "Bloom Threshold";
        ui_tooltip = "Higher values bloom more of the scene.";
        ui_category = "Anamorphic Bloom";
    > = 0.7;

    uniform float BLOOM_STRETCH <
        ui_type = "drag";
        ui_min = 0.0; ui_max = 7.5; ui_step = 0.01;
        ui_label = "Bloom Stretch";
        ui_tooltip = "Adjusts the horizontal elongation of the Bloom effect.";
        ui_category = "Anamorphic Bloom";
    > = 7.5;

    #if COLOR_FRINGING
        uniform float BLOOM_CA <
            ui_type = "drag";
            ui_min = 0.0; ui_max = 10.0; ui_step = 0.01;
            ui_label = "Bloom Chromatic Shift";
            ui_tooltip = "Shifts R/B channels within the bloom passes.";
            ui_category = "Anamorphic Bloom";
        > = 10.0;
    #endif
#endif

#if ANAMORPHIC_STREAKS
    uniform bool STREAK_SKIP_SKYBOX <
        ui_type = "radio";
        ui_label = "Exclude Skybox (Streaks)";
        ui_tooltip = "Prevents sky pixels from contributing to light streaks.";
        ui_category = "Anamorphic Streaks";
    > = false;

    uniform float STREAK_INTENSITY <
        ui_type = "drag";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
        ui_label = "Streak Intensity";
        ui_tooltip = "Scales the intensity of the light streaks.";
        ui_category = "Anamorphic Streaks";
    > = 1.0;

    uniform float STREAK_THRESHOLD <
        ui_type = "drag";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
        ui_label = "Streak Threshold";
        ui_tooltip = "Higher values considers more of the scene.";
        ui_category = "Anamorphic Streaks";
    > = 0.5;

    uniform float STREAK_STRETCH <
        ui_type = "drag";
        ui_min = 0.0; ui_max = 10.0; ui_step = 0.01;
        ui_label = "Streak Stretch";
        ui_tooltip = "Adjusts the horizontal elongation of the light streaks.";
        ui_category = "Anamorphic Streaks";
    > = 10.0;

    uniform float3 STREAK_TINT <
        ui_type = "color";
        ui_label = "Tint";
        ui_tooltip = "Tints the light streaks with chosen color. Set to white (1, 1, 1) for pass-through.";
        ui_category = "Anamorphic Streaks";
    > = float3(0.55, 0.55, 1.0);

    #if COLOR_FRINGING
        uniform float STREAK_CA <
            ui_type = "drag";
            ui_min = 0.0; ui_max = 10.0; ui_step = 0.01;
            ui_label = "Streak Chromatic Shift";
            ui_tooltip = "Shifts R/B channels of the light streaks.";
            ui_category = "Anamorphic Streaks";
        > = 10.0;
    #endif
#endif

uniform int USER_GUIDE <
ui_type = "radio";
    ui_category = "";
    ui_label = " ";
    ui_text =  "Exclude Skybox: Requires access to properly configured depth buffer.";
>;

namespace LumeniteAnamorphicBloom {

/*-------------.
| :: MACROS :: |
'-------------*/
#if ANAMORPHIC_BLOOM
    #define BLOOM_SHIFT (float2(BLOOM_CA * BUFFER_PIXEL_SIZE.x, 0.0)) //once per pass

    #if COLOR_FRINGING
        #define SAMPLE_BLOOM_TEX(s, uv) float3( \
            tex2D(s, (uv) - BLOOM_SHIFT).r,     \
            tex2D(s, (uv)).g,                   \
            tex2D(s, (uv) + BLOOM_SHIFT).b      \
        )
    #else
        #define SAMPLE_BLOOM_TEX(s, uv) tex2D(s, uv).rgb
    #endif
#endif

#if ANAMORPHIC_STREAKS
    #define STREAK_SHIFT (STREAK_CA * BUFFER_PIXEL_SIZE.x)

    #if COLOR_FRINGING
        #define SAMPLE_STREAK_TEX(s, uv, o) float3(            \
            tex2D(s, uv + float2(o - STREAK_SHIFT, 0.0)).r, \
            tex2D(s, uv + float2(o, 0.0)).g,                \
            tex2D(s, uv + float2(o + STREAK_SHIFT, 0.0)).b  \
        )
    #else
        #define SAMPLE_STREAK_TEX(s, uv, o) tex2D(s, uv + float2(o, 0.0)).rgb
    #endif
#endif

/*---------------------.
| :: RENDER TARGETS :: |
'---------------------*/
texture2D tUnpackedColor { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler2D sUnpackedColor { Texture = tUnpackedColor; };

#if ANAMORPHIC_BLOOM
    texture2D tBloomDown0 { Width = BUFFER_WIDTH/2;  Height = BUFFER_HEIGHT/2;  Format = RGBA16F; };
    sampler2D sBloomDown0 { Texture = tBloomDown0; };

    texture2D tBloomDown1 { Width = BUFFER_WIDTH/4;  Height = BUFFER_HEIGHT/4;  Format = RGBA16F; };
    sampler2D sBloomDown1 { Texture = tBloomDown1; };

    texture2D tBloomDown2 { Width = BUFFER_WIDTH/8;  Height = BUFFER_HEIGHT/8;  Format = RGBA16F; };
    sampler2D sBloomDown2 { Texture = tBloomDown2; };

    texture2D tBloomDown3 { Width = BUFFER_WIDTH/16; Height = BUFFER_HEIGHT/16; Format = RGBA16F; };
    sampler2D sBloomDown3 { Texture = tBloomDown3; };

    texture2D tBloomDown4 { Width = BUFFER_WIDTH/32; Height = BUFFER_HEIGHT/32; Format = RGBA16F; };
    sampler2D sBloomDown4 { Texture = tBloomDown4; };

    texture2D tBloomUp3 { Width = BUFFER_WIDTH/16; Height = BUFFER_HEIGHT/16; Format = RGBA16F; };
    sampler2D sBloomUp3 { Texture = tBloomUp3; };

    texture2D tBloomUp2 { Width = BUFFER_WIDTH/8;  Height = BUFFER_HEIGHT/8;  Format = RGBA16F; };
    sampler2D sBloomUp2 { Texture = tBloomUp2; };

    texture2D tBloomUp1 { Width = BUFFER_WIDTH/4;  Height = BUFFER_HEIGHT/4;  Format = RGBA16F; };
    sampler2D sBloomUp1 { Texture = tBloomUp1; };

    texture2D tBloomUp0 { Width = BUFFER_WIDTH/2;  Height = BUFFER_HEIGHT/2;  Format = RGBA16F; };
    sampler2D sBloomUp0 { Texture = tBloomUp0; };

    texture2D tBloomUp4 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
    sampler2D sBloomUp4 { Texture = tBloomUp4; };
#endif

#if ANAMORPHIC_STREAKS
    texture2D tStreakDown0 { Width = BUFFER_WIDTH/2;  Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
    sampler2D sStreakDown0 { Texture = tStreakDown0; };

    texture2D tStreakDown1 { Width = BUFFER_WIDTH/4;  Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
    sampler2D sStreakDown1 { Texture = tStreakDown1; };

    texture2D tStreakDown2 { Width = BUFFER_WIDTH/8;  Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
    sampler2D sStreakDown2 { Texture = tStreakDown2; };

    texture2D tStreakDown3 { Width = BUFFER_WIDTH/16; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
    sampler2D sStreakDown3 { Texture = tStreakDown3; };

    texture2D tStreakDown4 { Width = BUFFER_WIDTH/32; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
    sampler2D sStreakDown4 { Texture = tStreakDown4; };

    texture2D tStreakUp3 { Width = BUFFER_WIDTH/16; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
    sampler2D sStreakUp3 { Texture = tStreakUp3; };

    texture2D tStreakUp2 { Width = BUFFER_WIDTH/8;  Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
    sampler2D sStreakUp2 { Texture = tStreakUp2; };

    texture2D tStreakUp1 { Width = BUFFER_WIDTH/4;  Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
    sampler2D sStreakUp1 { Texture = tStreakUp1; };

    texture2D tStreakUp0 { Width = BUFFER_WIDTH/2;  Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
    sampler2D sStreakUp0 { Texture = tStreakUp0; };
#endif

/*--------------.
| :: HELPERS :: |
'--------------*/
#if ANAMORPHIC_BLOOM
    float3 TentFilter13Anisotropic(sampler2D src, float2 uv, float2 radius)
    {
        float dx = radius.x;
        float dy = radius.y;

        [branch] if (BLOOM_SHARP)
        {
            float3 center     = SAMPLE_BLOOM_TEX(src, uv);
            float3 innerLeft  = SAMPLE_BLOOM_TEX(src, uv + float2(-dx,   0));
            float3 innerRight = SAMPLE_BLOOM_TEX(src, uv + float2( dx,   0));
            float3 outerLeft  = SAMPLE_BLOOM_TEX(src, uv + float2(-2*dx, 0));
            float3 outerRight = SAMPLE_BLOOM_TEX(src, uv + float2( 2*dx, 0));
            return center * 0.25 + (innerLeft + innerRight) * 0.25 + (outerLeft + outerRight) * 0.125;
        }

        float3 a = SAMPLE_BLOOM_TEX(src, uv + float2(-2*dx,  2*dy)).rgb;
        float3 b = SAMPLE_BLOOM_TEX(src, uv + float2( 0,     2*dy)).rgb;
        float3 c = SAMPLE_BLOOM_TEX(src, uv + float2( 2*dx,  2*dy)).rgb;
        float3 d = SAMPLE_BLOOM_TEX(src, uv + float2(-2*dx,  0)).rgb;
        float3 e = SAMPLE_BLOOM_TEX(src, uv + float2( 0,     0)).rgb;
        float3 f = SAMPLE_BLOOM_TEX(src, uv + float2( 2*dx,  0)).rgb;
        float3 g = SAMPLE_BLOOM_TEX(src, uv + float2(-2*dx, -2*dy)).rgb;
        float3 h = SAMPLE_BLOOM_TEX(src, uv + float2( 0,    -2*dy)).rgb;
        float3 i = SAMPLE_BLOOM_TEX(src, uv + float2( 2*dx, -2*dy)).rgb;
        float3 j = SAMPLE_BLOOM_TEX(src, uv + float2(-dx,    dy)).rgb;
        float3 k = SAMPLE_BLOOM_TEX(src, uv + float2( dx,    dy)).rgb;
        float3 l = SAMPLE_BLOOM_TEX(src, uv + float2(-dx,   -dy)).rgb;
        float3 m = SAMPLE_BLOOM_TEX(src, uv + float2( dx,   -dy)).rgb;

        return e * 0.125 + (a + c + g + i) * 0.03125 + (b + d + f + h) * 0.0625 + (j + k + l + m) * 0.125;
    }

    float3 TentFilter9Anisotropic(sampler2D src, float2 uv, float2 radius)
    {
        float dx = radius.x;
        float dy = radius.y;

        [branch] if (BLOOM_SHARP)
        {
            float3 center = SAMPLE_BLOOM_TEX(src, uv);
            float3 left   = SAMPLE_BLOOM_TEX(src, uv + float2(-dx, 0));
            float3 right  = SAMPLE_BLOOM_TEX(src, uv + float2( dx, 0));
            return center * 0.5 + (left + right) * 0.25;
        }

        float3 a = SAMPLE_BLOOM_TEX(src, uv + float2(-dx,  dy)).rgb;
        float3 b = SAMPLE_BLOOM_TEX(src, uv + float2( 0,   dy)).rgb;
        float3 c = SAMPLE_BLOOM_TEX(src, uv + float2( dx,  dy)).rgb;
        float3 d = SAMPLE_BLOOM_TEX(src, uv + float2(-dx,  0)).rgb;
        float3 e = SAMPLE_BLOOM_TEX(src, uv + float2( 0,   0)).rgb;
        float3 f = SAMPLE_BLOOM_TEX(src, uv + float2( dx,  0)).rgb;
        float3 g = SAMPLE_BLOOM_TEX(src, uv + float2(-dx, -dy)).rgb;
        float3 h = SAMPLE_BLOOM_TEX(src, uv + float2( 0,  -dy)).rgb;
        float3 i = SAMPLE_BLOOM_TEX(src, uv + float2( dx, -dy)).rgb;

        return (e * 4.0 + (b + d + f + h) * 2.0 + (a + c + g + i)) * 0.0625;
    }
#endif

#if ANAMORPHIC_STREAKS
    float3 StreakFilter(sampler2D src, float2 uv, float radius)
    {
        float dx = BUFFER_PIXEL_SIZE.x * radius;
        return SAMPLE_STREAK_TEX(src, uv, -dx * 2.0) * 0.1  +
               SAMPLE_STREAK_TEX(src, uv, -dx)       * 0.25 +
               SAMPLE_STREAK_TEX(src, uv, 0.0)       * 0.3  +
               SAMPLE_STREAK_TEX(src, uv, dx)        * 0.25 +
               SAMPLE_STREAK_TEX(src, uv, dx * 2.0)  * 0.1;
    }
#endif

/*--------------.
| :: SHADERS :: |
'--------------*/
float4 PS_StoreUnpackedColor(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return float4(GetLinearColor(uv, false), 1);
}

#if ANAMORPHIC_BLOOM
    //downsample with anisotropic blur (13-tap)
    float4 PS_BloomDownsample0(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float2 radius = float2(BLOOM_STRETCH, 1.0) * BUFFER_PIXEL_SIZE;
        float3 downsample = TentFilter13Anisotropic(sUnpackedColor, uv, radius);
        if (BLOOM_SKIP_SKYBOX) downsample *= (GetDepth(uv) < 1.0);
        downsample = downsample * smoothstep(0.0, max(1.0 - BLOOM_THRESHOLD, 0.07)*BLOOM_THRESHOLD_SCALER, GetLuminance(downsample));
        return float4(downsample, 1);
    }

    float4 PS_BloomDownsample1(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float2 radius = float2(BLOOM_STRETCH, 1.0) * BUFFER_PIXEL_SIZE * 2.0;
        return float4(TentFilter13Anisotropic(sBloomDown0, uv, radius), 1);
    }

    float4 PS_BloomDownsample2(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float2 radius = float2(BLOOM_STRETCH, 1.0) * BUFFER_PIXEL_SIZE * 4.0;
        return float4(TentFilter13Anisotropic(sBloomDown1, uv, radius), 1);
    }

    float4 PS_BloomDownsample3(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float2 radius = float2(BLOOM_STRETCH, 1.0) * BUFFER_PIXEL_SIZE * 8.0;
        return float4(TentFilter13Anisotropic(sBloomDown2, uv, radius), 1);
    }

    float4 PS_BloomDownsample4(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float2 radius = float2(BLOOM_STRETCH, 1.0) * BUFFER_PIXEL_SIZE * 16.0;
        return float4(TentFilter13Anisotropic(sBloomDown3, uv, radius), 1);
    }

    //upsample with anisotropic blur (9-tap)
    float4 PS_BloomUpsample0(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float2 radius = float2(BLOOM_STRETCH, 0.0) * BUFFER_PIXEL_SIZE * 32.0 * float2(1.0, rcp(BUFFER_ASPECT_RATIO));
        float3 upsample = TentFilter9Anisotropic(sBloomDown4, uv, radius);
        float3 previous = tex2D(sBloomDown3, uv).rgb;
        return float4(upsample + previous, 1);
    }

    float4 PS_BloomUpsample1(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float2 radius = float2(BLOOM_STRETCH, 0.0) * BUFFER_PIXEL_SIZE * 16.0 * float2(1.0, rcp(BUFFER_ASPECT_RATIO));
        float3 upsample = TentFilter9Anisotropic(sBloomUp3, uv, radius);
        float3 previous = tex2D(sBloomDown2, uv).rgb;
        return float4(upsample + previous, 1);
    }

    float4 PS_BloomUpsample2(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float2 radius = float2(BLOOM_STRETCH, 0.0) * BUFFER_PIXEL_SIZE * 8.0 * float2(1.0, rcp(BUFFER_ASPECT_RATIO));
        float3 upsample = TentFilter9Anisotropic(sBloomUp2, uv, radius);
        float3 previous = tex2D(sBloomDown1, uv).rgb;
        return float4(upsample + previous, 1);
    }

    float4 PS_BloomUpsample3(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float2 radius = float2(BLOOM_STRETCH, 0.0) * BUFFER_PIXEL_SIZE * 4.0 * float2(1.0, rcp(BUFFER_ASPECT_RATIO));
        float3 upsample = TentFilter9Anisotropic(sBloomUp1, uv, radius);
        float3 previous = tex2D(sBloomDown0, uv).rgb;
        return float4(upsample + previous, 1);
    }

    float4 PS_BloomUpsample4(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float2 radius = float2(BLOOM_STRETCH, 0.0) * BUFFER_PIXEL_SIZE * 2.0 * float2(1.0, rcp(BUFFER_ASPECT_RATIO));
        float3 upsample = TentFilter9Anisotropic(sBloomUp0, uv, radius);
        float3 previous = tex2D(sBloomDown0, uv).rgb;
        return float4(upsample + previous, 1);
    }
#endif

#if ANAMORPHIC_STREAKS
    //thresholding pass
    float4 PS_Prefilter(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float3 color = tex2D(sUnpackedColor, uv).rgb;
        if (STREAK_SKIP_SKYBOX) color *= (GetDepth(uv) < 1.0);
        float br = max(color.r, max(color.g, color.b));
        float nm = max(0.0, br - (1.0 - STREAK_THRESHOLD));
        return float4(color * (nm / max(br, 0.0001)), 1.0);
    }

    float4 PS_StreakDownsample0(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(StreakFilter(sStreakDown0, uv, 1.0 * STREAK_STRETCH), 1); }
    float4 PS_StreakDownsample1(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(StreakFilter(sStreakDown1, uv, 2.0 * STREAK_STRETCH), 1); }
    float4 PS_StreakDownsample2(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(StreakFilter(sStreakDown2, uv, 4.0 * STREAK_STRETCH), 1); }
    float4 PS_StreakDownsample3(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(StreakFilter(sStreakDown3, uv, 8.0 * STREAK_STRETCH), 1); }

    float4 PS_StreakUpsample0(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(StreakFilter(sStreakUp3,   uv, 8.0  * STREAK_STRETCH) + tex2D(sStreakDown2, uv).rgb, 1); }
    float4 PS_StreakUpsample1(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(StreakFilter(sStreakUp2,   uv, 4.0  * STREAK_STRETCH) + tex2D(sStreakDown1, uv).rgb, 1); }
    float4 PS_StreakUpsample2(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(StreakFilter(sStreakUp1,   uv, 2.0  * STREAK_STRETCH) + tex2D(sStreakDown0, uv).rgb, 1); }
    float4 PS_StreakUpsample3(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(StreakFilter(sStreakDown4, uv, 16.0 * STREAK_STRETCH) + tex2D(sStreakDown3, uv).rgb, 1); }
#endif

float4 PS_ToDisplay(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 unpackedColor = tex2D(sUnpackedColor, uv).rgb;
    float3 light = 0;

    #if ANAMORPHIC_BLOOM
        light = tex2D(sBloomUp4, uv).rgb * BLOOM_INTENSITY;
    #endif

    #if ANAMORPHIC_STREAKS
        light = max(light, tex2D(sStreakUp0, uv).rgb * STREAK_TINT * STREAK_INTENSITY);
    #endif

    float3 toDisplay;
    #if (BUFFER_COLOR_SPACE == 1)
        //sRGB colorspace
        toDisplay = 1.0 - (1.0 - unpackedColor) * (1.0 - light);
    #else
        toDisplay = unpackedColor + light;
    #endif

    toDisplay = ToOutputColorspace(toDisplay, false);
    return float4(toDisplay, 1);
}

/*----------------.
| :: TECHNIQUE :: |
'----------------*/
technique Lumenite_AnamorphicBloom <
    ui_label = "LUMENITE: Anamorphic Bloom";
    ui_tooltip = "Artistic bloom & Lens Flare approximating the Anamorphic lens aesthetic.";
>
{
    pass { VertexShader = PostProcessVS; PixelShader = PS_StoreUnpackedColor; RenderTarget = tUnpackedColor; }

    //bloom pyramid
    #if ANAMORPHIC_BLOOM
        pass { VertexShader = PostProcessVS; PixelShader = PS_BloomDownsample0; RenderTarget = tBloomDown0; }
        pass { VertexShader = PostProcessVS; PixelShader = PS_BloomDownsample1; RenderTarget = tBloomDown1; }
        pass { VertexShader = PostProcessVS; PixelShader = PS_BloomDownsample2; RenderTarget = tBloomDown2; }
        pass { VertexShader = PostProcessVS; PixelShader = PS_BloomDownsample3; RenderTarget = tBloomDown3; }
        pass { VertexShader = PostProcessVS; PixelShader = PS_BloomDownsample4; RenderTarget = tBloomDown4; }

        pass { VertexShader = PostProcessVS; PixelShader = PS_BloomUpsample0; RenderTarget = tBloomUp3; }
        pass { VertexShader = PostProcessVS; PixelShader = PS_BloomUpsample1; RenderTarget = tBloomUp2; }
        pass { VertexShader = PostProcessVS; PixelShader = PS_BloomUpsample2; RenderTarget = tBloomUp1; }
        pass { VertexShader = PostProcessVS; PixelShader = PS_BloomUpsample3; RenderTarget = tBloomUp0; }
        pass { VertexShader = PostProcessVS; PixelShader = PS_BloomUpsample4; RenderTarget = tBloomUp4; }
    #endif

    //streak pyramid
    #if ANAMORPHIC_STREAKS
        pass { VertexShader = PostProcessVS; PixelShader = PS_Prefilter;         RenderTarget = tStreakDown0; }
        pass { VertexShader = PostProcessVS; PixelShader = PS_StreakDownsample0; RenderTarget = tStreakDown1; }
        pass { VertexShader = PostProcessVS; PixelShader = PS_StreakDownsample1; RenderTarget = tStreakDown2; }
        pass { VertexShader = PostProcessVS; PixelShader = PS_StreakDownsample2; RenderTarget = tStreakDown3; }
        pass { VertexShader = PostProcessVS; PixelShader = PS_StreakDownsample3; RenderTarget = tStreakDown4; }

        pass { VertexShader = PostProcessVS; PixelShader = PS_StreakUpsample3;   RenderTarget = tStreakUp3;   }
        pass { VertexShader = PostProcessVS; PixelShader = PS_StreakUpsample0;   RenderTarget = tStreakUp2;   }
        pass { VertexShader = PostProcessVS; PixelShader = PS_StreakUpsample1;   RenderTarget = tStreakUp1;   }
        pass { VertexShader = PostProcessVS; PixelShader = PS_StreakUpsample2;   RenderTarget = tStreakUp0;   }
    #endif

    pass { VertexShader = PostProcessVS; PixelShader = PS_ToDisplay; }
}

}
