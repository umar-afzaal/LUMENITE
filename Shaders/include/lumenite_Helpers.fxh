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


        Filename   : lumenite_Helpers.fxh
        Version    : 2026.05.09
        Author     : Afzaal (Kaidō)
        Description: Helper functions for Lumenite shaders.
        License    : AGNYA License (https://github.com/nvb-uy/AGNYA-License)

        ========================================================================
*/

#pragma once

#include "ReShade.fxh"

/*------------------.
| :: DEFINITIONS :: |
'------------------*/
#define PI 3.14159265359
#define EPSILON 1e-6
//R2 sequence constants
static const float PHI_2 = 1.324717957244746;
static const float2 R2_CONSTANT = float2(1.0/PHI_2, 1.0/(PHI_2*PHI_2));

/*--------------.
| :: UNIFORMS ::|
'--------------*/
uniform float  TIMER       < source = "timer"; >; //ms since launch
uniform float  FRAME_TIME  < source = "frametime"; >; //ms last frame
uniform uint   FRAME_COUNT < source = "framecount"; >;
uniform float2 MOUSE_POS   < source = "mousepoint";  >;  //in screen px
uniform bool   MOUSE_DOWN  < source = "mousebutton"; min = 0; max = 0; >;

/*--------------.
| :: HELPERS :: |
'--------------*/
bool CheckerboardSkip(uint2 currentPos, float scale)
{
    //map current buffer pixel to full screen pixel.
    //floor() to ensure we snap to the integer grid of the full screen
    uint2 fullScreenPos = uint2(floor(currentPos.x * scale), floor(currentPos.y * scale));
    return (((fullScreenPos.x + fullScreenPos.y + (FRAME_COUNT & 1)) & 1) == 1);
}

float GetDepth(float2 uv)
{
	return ReShade::GetLinearizedDepth(uv);
}

bool IsOOB(float2 uv) {
    return any(uv < 0.0) || any(uv > 1.0);
}

//QUASI-MONTE CARLO SEQUENCE
//fast Hilbert curve math (a 1D index from 2D coords)
uint HilbertIndex(uint x, uint y) {
    uint index = 0;
    [unroll] for (uint s = 64 / 2; s > 0; s /= 2) {
        uint rx = (x & s) > 0;
        uint ry = (y & s) > 0;
        index += s * s * ((3 * rx) ^ ry);
        if (ry == 0) {
            if (rx == 1) {
                x = 64 - 1 - x;
                y = 64 - 1 - y;
            }
            uint t = x; x = y; y = t;
        }
    }
    return index;
}

float2 GetStratifiedNoise(float2 vpos) {
    uint2 screenPos = uint2(vpos.xy) % 64; //64x64 tiled pixel coords
    uint hIndex = HilbertIndex(screenPos.x, screenPos.y); //Hilbert index (spatial)
    uint totalIndex = hIndex + (uint(FRAME_COUNT % 64) * 288); //temporal offset: 288
    return frac(float(totalIndex) * R2_CONSTANT);
}
