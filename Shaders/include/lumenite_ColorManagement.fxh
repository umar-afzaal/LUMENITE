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


        Filename   : lumenite_ColorManagement.fxh
        Version    : 2026.02.28
        Author     : Afzaal (Kaidō)
        Description: Provides color management including color space detection,
                     color space transfers and tonemapping.
                     Supported colorbuffers:
                     - SDR (sRGB)
                     - HDR (scRGB / Linear)
                     - HDR (PQ / ST.2084)
                     - HDR (HLG)
        License    : AGNYA License (https://github.com/nvb-uy/AGNYA-License)

        ========================================================================
*/

#pragma once

/*-------------------.
| :: PREPROCESSOR :: |
'-------------------*/

#define HDR_WHITELEVEL 203

#if BUFFER_COLOR_SPACE > 0
    //already defined by ReShade
#else
    #if BUFFER_COLOR_BIT_DEPTH == 8
        #undef BUFFER_COLOR_SPACE
        #define BUFFER_COLOR_SPACE 1 //sRGB
    #elif BUFFER_COLOR_BIT_DEPTH == 16
        #undef BUFFER_COLOR_SPACE
        #define BUFFER_COLOR_SPACE 2 //scRGB
    #elif __RENDERER__ < 0xb000
        #undef BUFFER_COLOR_SPACE
        #define BUFFER_COLOR_SPACE 1 //D3D9/10 usually SDR
    #endif
#endif

/*------------------.
| :: UI UNIFORMS :: |
'------------------*/

// uniform int SHOW_COLOR_SPACE <
//     ui_category = "Color Management";
//     ui_type = "combo";
//     ui_label = "Colorspace";
//     ui_tooltip = "Shows the detected color space.\n1=sRGB, 2=scRGB, 3=PQ, 4=HLG";
//     hidden = true;
//     #if BUFFER_COLOR_SPACE == 1
//         ui_items = "sRGB (Detected)\0";
//     #elif BUFFER_COLOR_SPACE == 2
//         ui_items = "scRGB (Detected)\0";
//     #elif BUFFER_COLOR_SPACE == 3
//         ui_items = "PQ / ST.2084 (Detected)\0";
//     #elif BUFFER_COLOR_SPACE == 4
//         ui_items = "HLG (Detected)\0";
//     #else
//         ui_items = "Unknown (Defaulting to sRGB)\0";
//     #endif
// > = 0;

#if BUFFER_COLOR_BIT_DEPTH > 8 || BUFFER_COLOR_SPACE > 1
    #define COLORSPACE_CONVERSION 1 //use approx. transfer function; 0 for accurate
#else
    #define COLORSPACE_CONVERSION 2 //N/A for 8-bit
#endif

#if BUFFER_COLOR_SPACE == 1
    #define TONEMAPPER 1 //reinhard tonemapper workflow for SDR (sRGB) colorbuffer; 0 for None
#else
    #define TONEMAPPER 0
#endif

/*-------------------------.
| :: TRANSFER FUNCTIONS :: |
'-------------------------*/

//=== sRGB
float3 sRGBtoLinearAccurate(float3 r) {
    return (r <= 0.04045) ? (r / 12.92) : pow(abs(r + 0.055) / 1.055, 2.4);
}

float3 sRGBtoLinearFast(float3 r) {
    return max(r / 12.92, r * r); //gamma 2.0 approx
}

float3 sRGBtoLinear(float3 r) {
    if (COLORSPACE_CONVERSION == 1) return sRGBtoLinearFast(r);
    else return sRGBtoLinearAccurate(r);
}

float3 linearToSRGBAccurate(float3 r) {
    return (r <= 0.0031308) ? (r * 12.92) : (1.055 * pow(abs(r), 1.0 / 2.4) - 0.055);
}

float3 linearToSRGBFast(float3 r) {
    return min(r * 12.92, sqrt(r)); //gamma 2.0 approx
}

float3 linearToSRGB(float3 r) {
    if (COLORSPACE_CONVERSION == 1) return linearToSRGBFast(r);
    else return linearToSRGBAccurate(r);
}

//=== PQ (ST.2084)
float3 PQtoLinearAccurate(float3 r) {
    const float m1 = 1305.0/8192.0;
    const float m2 = 2523.0/32.0;
    const float c1 = 107.0/128.0;
    const float c2 = 2413.0/128.0;
    const float c3 = 2392.0/128.0;
    float3 powr = pow(max(r, 0), 1.0/m2);
    r = pow(max(max(powr - c1, 0) / (c2 - c3 * powr), 0), 1.0/m1);
    //scale 10,000 nits down so Paper White (HDR_WHITELEVEL) maps to 1.0
    return r * 10000.0 / HDR_WHITELEVEL;
}

float3 PQtoLinearFast(float3 r) {
    float3 square = r * r;
    float3 quad = square * square;
    float3 oct = quad * quad;
    r = max(max(square / 340.0, quad / 6.0), oct);
    return r * 10000.0 / HDR_WHITELEVEL;
}

float3 PQtoLinear(float3 r) {
    if (COLORSPACE_CONVERSION == 1) return PQtoLinearFast(r);
    else return PQtoLinearAccurate(r);
}

float3 linearToPQAccurate(float3 r) {
    const float m1 = 1305.0/8192.0;
    const float m2 = 2523.0/32.0;
    const float c1 = 107.0/128.0;
    const float c2 = 2413.0/128.0;
    const float c3 = 2392.0/128.0;

    r = r * (HDR_WHITELEVEL / 10000.0); //rescale 1.0 back to nits
    float3 powr = pow(max(r, 0), m1);
    r = pow(max((c1 + c2 * powr) / (1 + c3 * powr), 0), m2);
    return r;
}

float3 linearToPQFast(float3 r) {
    r = r * (HDR_WHITELEVEL / 10000.0);
    float3 squareroot = sqrt(r);
    float3 quadroot = sqrt(squareroot);
    float3 octroot = sqrt(quadroot);
    r = min(octroot, min(sqrt(sqrt(6.0))*quadroot, sqrt(340.0)*squareroot));
    return r;
}

float3 linearToPQ(float3 r) {
    if (COLORSPACE_CONVERSION == 1) return linearToPQFast(r);
    else return linearToPQAccurate(r);
}

//=== HLG (Hybrid Log Gamma)
float3 linearToHLG(float3 r) {
    r = r * HDR_WHITELEVEL / 1000.0;
    const float a = 0.17883277;
    const float b = 0.28466892;
    const float c = 0.55991073;
    float3 s = sqrt(3 * r);
    return (s < 0.5) ? s : (log(12 * r - b) * a + c);
}

float3 HLGtoLinear(float3 r) {
    const float a = 0.17883277;
    const float b = 0.28466892;
    const float c = 0.55991073;
    r = (r < 0.5) ? (r * r / 3.0) : ((exp((r - c) / a) + b) / 12.0);
    return r * 1000.0 / HDR_WHITELEVEL;
}

//=== YCoCg
float3 linearToYCoCg(float3 r) {
    float y  = (r.r + 2.0 * r.g + r.b) * 0.25;
    float co = (r.r - r.b) * 0.5;
    float cg = (r.g - (r.r + r.b) * 0.5) * 0.5;
    return float3(y, co, cg);
}

float3 YCoCgToLinear(float3 r) {
    float y  = r.x;
    float co = r.y;
    float cg = r.z;
    float g = y + cg;
    float rOut = y + co - cg;
    float b = y - co - cg;
    return float3(rOut, g, b);
}

/*--------------.
| :: HELPERS :: |
'--------------*/

float3 ToLinearColorspace(float3 r, bool tonemap) {
    if (BUFFER_COLOR_SPACE == 2) r = r * (80.0 / HDR_WHITELEVEL); //scRGB
    else if (BUFFER_COLOR_SPACE == 3) r = PQtoLinear(r);
    else if (BUFFER_COLOR_SPACE == 4) r = HLGtoLinear(r);
    else {
        r = sRGBtoLinear(r);
        if (TONEMAPPER == 1 && tonemap) r = r / max(1.0 - r, 0.001); //inverse reinhard
    }
    return r;
}

float3 ToOutputColorspace(float3 r, bool tonemap) {
    if (BUFFER_COLOR_SPACE == 2) r = r * (HDR_WHITELEVEL / 80.0); //scRGB
    else if (BUFFER_COLOR_SPACE == 3) r = linearToPQ(r);
    else if (BUFFER_COLOR_SPACE == 4) r = linearToHLG(r);
    else {
        if (TONEMAPPER == 1 && tonemap) r = r / (1.0 + r); //forward reinhard
        r = linearToSRGB(r);
    }
    return r;
}

//read the theoretical max value of the buffer (in linear scale)
float GetMaxColorValue() {
    if (BUFFER_COLOR_SPACE == 4) return 1000.0 / HDR_WHITELEVEL;
    if (BUFFER_COLOR_SPACE >= 2) return 10000.0 / HDR_WHITELEVEL;
    return 1.0;
}

float GetLuminance(float3 color)
{
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

float3 GetLinearColor(float2 uv, bool tonemap)
{
    float3 color = tex2Dlod(ReShade::BackBuffer, float4(uv, 0, 0)).rgb;
    return ToLinearColorspace(color, tonemap);
}
