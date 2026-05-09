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


        Filename   : lumenite_Compute.fxh
        Version    : 2026.05.09
        Author     : Afzaal (Kaidō)
        Description: Header file for supporting compute enabled platforms.
        License    : AGNYA License (https://github.com/nvb-uy/AGNYA-License)

        ========================================================================
*/

#pragma once

#include "ReShade.fxh"

/*------------------.
| :: DEFINITIONS :: |
'------------------*/
#define D3D9   0x9000
#define D3D10  0xa000
#define D3D11  0xb000
#define D3D12  0xc000
#define OPENGL 0x10000
#define VULKAN 0x20000

#if __RENDERER__ >= D3D11
    #define _COMPUTE_ENABLED_ 1
#else
    #define _COMPUTE_ENABLED_ 0
#endif

struct CSInput
{
    uint3 dispatchID : SV_DispatchThreadID; //global pixel coord  (x, y, 0)
    uint3 groupID    : SV_GroupID;          //which tile/group in grid
    uint3 localID    : SV_GroupThreadID;    //thread inside group [0..CS_W-1]
    uint  flatIndex  : SV_GroupIndex;       //localID flattened: y*CS_W + x
};
