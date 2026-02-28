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
        Version    : 2026.02.28
        Author     : Afzaal (Kaidō)
        Description: Horizontally-stretched artistic bloom approximating the
                     Anamorphic lens aesthetic.
        License    : AGNYA License (https://github.com/nvb-uy/AGNYA-License)

        ========================================================================
*/

#include "ReShade.fxh"
#include "./include/lumenite_ColorManagement.fxh"
#include "./include/lumenite_Helpers.fxh"

/*------------------.
| :: DEFINITIONS :: |
'------------------*/
#define HORIZONTAL_STRETCH 7.5
#define LUM_THRESHOLD_SCALER 10.0

/*---------------.
| :: UNIFORMS :: |
'---------------*/
uniform float BLOOM_STRENGTH <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Bloom Intensity";
    ui_tooltip = "Controls the intensity of the Bloom effect.";
    ui_category = "Anamorphic Bloom";
> = 1.0;

uniform float LUM_THRESHOLD <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Bloom Threshold";
    ui_tooltip = "Higher values bloom more of the scene.";
    ui_category = "Anamorphic Bloom";
> = 0.7;

namespace LumeniteAnamorphicBloom {

/*---------------------.
| :: RENDER TARGETS :: |
'---------------------*/
texture2D tUnpackedColor { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler2D sUnpackedColor { Texture = tUnpackedColor; };

//downsample chain
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

//upsample chain
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

/*--------------.
| :: HELPERS :: |
'--------------*/
float3 TentFilter13Anisotropic(sampler2D src, float2 uv, float2 radius)
{
    float x = radius.x;
    float y = radius.y;

    float3 a = tex2D(src, uv + float2(-2*x,  2*y)).rgb;
    float3 b = tex2D(src, uv + float2( 0,    2*y)).rgb;
    float3 c = tex2D(src, uv + float2( 2*x,  2*y)).rgb;
    float3 d = tex2D(src, uv + float2(-2*x,  0)).rgb;
    float3 e = tex2D(src, uv + float2( 0,    0)).rgb;
    float3 f = tex2D(src, uv + float2( 2*x,  0)).rgb;
    float3 g = tex2D(src, uv + float2(-2*x, -2*y)).rgb;
    float3 h = tex2D(src, uv + float2( 0,   -2*y)).rgb;
    float3 i = tex2D(src, uv + float2( 2*x, -2*y)).rgb;
    float3 j = tex2D(src, uv + float2(-x,    y)).rgb;
    float3 k = tex2D(src, uv + float2( x,    y)).rgb;
    float3 l = tex2D(src, uv + float2(-x,   -y)).rgb;
    float3 m = tex2D(src, uv + float2( x,   -y)).rgb;

    return e * 0.125 + (a + c + g + i) * 0.03125 + (b + d + f + h) * 0.0625 + (j + k + l + m) * 0.125;
}

float3 TentFilter9Anisotropic(sampler2D src, float2 uv, float2 radius)
{
    float3 a = tex2D(src, uv + float2(-radius.x,  radius.y)).rgb;
    float3 b = tex2D(src, uv + float2( 0,         radius.y)).rgb;
    float3 c = tex2D(src, uv + float2( radius.x,  radius.y)).rgb;
    float3 d = tex2D(src, uv + float2(-radius.x,  0)).rgb;
    float3 e = tex2D(src, uv + float2( 0,         0)).rgb;
    float3 f = tex2D(src, uv + float2( radius.x,  0)).rgb;
    float3 g = tex2D(src, uv + float2(-radius.x, -radius.y)).rgb;
    float3 h = tex2D(src, uv + float2( 0,        -radius.y)).rgb;
    float3 i = tex2D(src, uv + float2( radius.x, -radius.y)).rgb;

    float3 upsample = e * 4.0 + (b + d + f + h) * 2.0 + (a + c + g + i);
    upsample *= 1.0 / 16.0;
    return upsample;
}

/*--------------------.
| :: PIXEL SHADERS :: |
'--------------------*/
float4 PS_StoreUnpackedColor(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return float4(GetLinearColor(uv, false), 1);
}

//downsample with anisotropic blur (13-tap)
float4 PS_Downsample0(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 radius = float2(HORIZONTAL_STRETCH, 1.0) * ReShade::PixelSize;
    float3 downsample = TentFilter13Anisotropic(sUnpackedColor, uv, radius);
    downsample = downsample * smoothstep(0.0, max(1.0 - LUM_THRESHOLD, 0.07)*LUM_THRESHOLD_SCALER, GetLuminance(downsample));
    return float4(downsample, 1);
}

float4 PS_Downsample1(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 radius = float2(HORIZONTAL_STRETCH, 1.0) * ReShade::PixelSize * 2.0;
    return float4(TentFilter13Anisotropic(sBloomDown0, uv, radius), 1);
}

float4 PS_Downsample2(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 radius = float2(HORIZONTAL_STRETCH, 1.0) * ReShade::PixelSize * 4.0;
    return float4(TentFilter13Anisotropic(sBloomDown1, uv, radius), 1);
}

float4 PS_Downsample3(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 radius = float2(HORIZONTAL_STRETCH, 1.0) * ReShade::PixelSize * 8.0;
    return float4(TentFilter13Anisotropic(sBloomDown2, uv, radius), 1);
}

float4 PS_Downsample4(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 radius = float2(HORIZONTAL_STRETCH, 1.0) * ReShade::PixelSize * 16.0;
    return float4(TentFilter13Anisotropic(sBloomDown3, uv, radius), 1);
}

//upsample with anisotropic blur (9-tap)
float4 PS_Upsample3(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 radius = float2(HORIZONTAL_STRETCH, 0.0) * ReShade::PixelSize * 32.0 * float2(1.0, BUFFER_HEIGHT / (float)BUFFER_WIDTH);
    float3 upsample = TentFilter9Anisotropic(sBloomDown4, uv, radius);
    float3 previous = tex2D(sBloomDown3, uv).rgb;
    return float4(upsample + previous, 1);
}

float4 PS_Upsample2(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 radius = float2(HORIZONTAL_STRETCH, 0.0) * ReShade::PixelSize * 16.0 * float2(1.0, BUFFER_HEIGHT / (float)BUFFER_WIDTH);
    float3 upsample = TentFilter9Anisotropic(sBloomUp3, uv, radius);
    float3 previous = tex2D(sBloomDown2, uv).rgb;
    return float4(upsample + previous, 1);
}

float4 PS_Upsample1(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 radius = float2(HORIZONTAL_STRETCH, 0.0) * ReShade::PixelSize * 8.0 * float2(1.0, BUFFER_HEIGHT / (float)BUFFER_WIDTH);
    float3 upsample = TentFilter9Anisotropic(sBloomUp2, uv, radius);
    float3 previous = tex2D(sBloomDown1, uv).rgb;
    return float4(upsample + previous, 1);
}

float4 PS_Upsample0(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 radius = float2(HORIZONTAL_STRETCH, 0.0) * ReShade::PixelSize * 4.0 * float2(1.0, BUFFER_HEIGHT / (float)BUFFER_WIDTH);
    float3 upsample = TentFilter9Anisotropic(sBloomUp1, uv, radius);
    float3 previous = tex2D(sBloomDown0, uv).rgb;
    return float4(upsample + previous, 1);
}


float4 PS_Upsample4(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 radius = float2(HORIZONTAL_STRETCH, 0.0) * ReShade::PixelSize * 2.0 * float2(1.0, BUFFER_HEIGHT / (float)BUFFER_WIDTH);
    float3 upsample = TentFilter9Anisotropic(sBloomUp0, uv, radius);
    float3 previous = tex2D(sBloomDown0, uv).rgb;
    return float4(upsample + previous, 1);
}

//blend
float4 PS_Composite(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 unpackedColor = tex2D(sUnpackedColor, uv).rgb;
    float3 bloom = tex2D(sBloomUp4, uv).rgb;
    float3 toDisplay;
    #if (BUFFER_COLOR_SPACE == 1)
        //sRGB colorspace
        toDisplay = 1.0 - (1.0 - unpackedColor) * (1.0 - bloom * BLOOM_STRENGTH); //screen
    #else
        toDisplay = unpackedColor + bloom * BLOOM_STRENGTH; //additive
    #endif
    toDisplay = ToOutputColorspace(toDisplay, false);
    return float4(toDisplay, 1);
}

/*----------------.
| :: TECHNIQUE :: |
'----------------*/

technique Lumenite_AnamorphicBloom <
    ui_label = "LUMENITE: Anamorphic Bloom";
    ui_tooltip = "Horizontal artistic bloom approximating the Anamorphic lens aesthetic.";
>
{
    pass { VertexShader = PostProcessVS; PixelShader = PS_StoreUnpackedColor; RenderTarget = tUnpackedColor; }

    pass { VertexShader = PostProcessVS; PixelShader = PS_Downsample0; RenderTarget = tBloomDown0; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_Downsample1; RenderTarget = tBloomDown1; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_Downsample2; RenderTarget = tBloomDown2; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_Downsample3; RenderTarget = tBloomDown3; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_Downsample4; RenderTarget = tBloomDown4; }

    pass { VertexShader = PostProcessVS; PixelShader = PS_Upsample3; RenderTarget = tBloomUp3; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_Upsample2; RenderTarget = tBloomUp2; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_Upsample1; RenderTarget = tBloomUp1; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_Upsample0; RenderTarget = tBloomUp0; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_Upsample4; RenderTarget = tBloomUp4; }

    pass { VertexShader = PostProcessVS; PixelShader = PS_Composite; }
}

}
