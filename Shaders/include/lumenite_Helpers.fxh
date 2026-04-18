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
        Version    : 2026.04.19
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

#define D3D9   0x9000
#define D3D10  0xa000
#define D3D11  0xb000
#define D3D12  0xc000
#define OPENGL 0x10000
#define VULKAN 0x20000

#if __RENDERER__ >= D3D11
 #define _GPGPU_ 1
#else
 #define _GPGPU_ 0
#endif

/*--------------.
| :: UNIFORMS ::|
'--------------*/
uniform float TIMER < source = "timer"; >;
uniform float FRAME_TIME < source = "frametime"; >;
uniform uint FRAME_COUNT < source = "framecount"; >;

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
