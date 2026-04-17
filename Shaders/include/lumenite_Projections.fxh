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


        Filename   : lumenite_Projections.fxh
        Version    : 2026.04.11
        Author     : Afzaal (Kaidō)
        Description: Camera projection functions for Lumenite shaders.
        License    : AGNYA License (https://github.com/nvb-uy/AGNYA-License)

        ========================================================================
*/

#pragma once

#include "ReShade.fxh"

/*--------------.
| :: HELPERS :: |
'--------------*/
//VERTEX SHADER
struct VSOUT
{
    float4 vpos              : SV_Position;
    float2 uv                : TEXCOORD0;
    float tan_half_fov_x     : TEXCOORD1;
    float tan_half_fov_y     : TEXCOORD2;
    float inv_tan_half_fov_x : TEXCOORD3;
    float inv_tan_half_fov_y : TEXCOORD4;
    float near_ratio         : TEXCOORD5;
    float diff_ratio         : TEXCOORD6;
};

#define TAN_HALF_FOV_Y tan(radians(FOV * 0.5))
#define ASPECT_RATIO_X_OVER_Y ((float)BUFFER_WIDTH / (float)BUFFER_HEIGHT)
#define TAN_HALF_FOV_X TAN_HALF_FOV_Y * ASPECT_RATIO_X_OVER_Y
#define INV_TAN_HALF_FOV_X rcp(TAN_HALF_FOV_X)
#define INV_TAN_HALF_FOV_Y rcp(TAN_HALF_FOV_Y)

VSOUT VS(uint id : SV_VertexID)
{
    VSOUT o;
    o.uv.x = (id == 2) ? 2.0 : 0.0;
    o.uv.y = (id == 1) ? 2.0 : 0.0;
    o.vpos = float4(mad(o.uv.x, 2.0, -1.0), mad(o.uv.y, -2.0, 1.0), 0.0, 1.0);
    o.tan_half_fov_x = TAN_HALF_FOV_X;
    o.tan_half_fov_y = TAN_HALF_FOV_Y;
    o.inv_tan_half_fov_x = INV_TAN_HALF_FOV_X;
    o.inv_tan_half_fov_y = INV_TAN_HALF_FOV_Y;
    o.near_ratio = NEAR_PLANE / RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
    o.diff_ratio = 1.0 - o.near_ratio; //lerp(a,b,t) = (a+t * (b-a)), precompute (b-a) or (1.0-near_ratio) here
    return o;
}

//PROJECTION FUNCTIONS
//normalized frustum
//left-handed viewspace
//normals point outwards
//Z+ goes into the screen
float3 UVToViewSpace(float2 uv, float linear_depth_vs, VSOUT ps_input)
{
    float projection_scale = mad(linear_depth_vs, ps_input.diff_ratio, ps_input.near_ratio); //faster lerp: a+t * diff
    float3 view_pos;
    float ndc_x = mad(uv.x, 2.0, -1.0);
    float ndc_y = mad(uv.y, -2.0, 1.0);
    view_pos.x = ndc_x * ps_input.tan_half_fov_x * projection_scale;
    view_pos.y = ndc_y * ps_input.tan_half_fov_y * projection_scale;
    view_pos.z = linear_depth_vs;
    return view_pos;
}

float2 ViewSpaceToUV(float3 view_pos, VSOUT ps_input)
{
    float inv_projection_scale = rcp(mad(view_pos.z, ps_input.diff_ratio, ps_input.near_ratio));
    float2 ndc;
    ndc.x = view_pos.x * ps_input.inv_tan_half_fov_x * inv_projection_scale;
    ndc.y = view_pos.y * ps_input.inv_tan_half_fov_y * inv_projection_scale;
    float2 uv;
    uv.x = mad(ndc.x, 0.5, 0.5);
    uv.y = mad(ndc.y, -0.5, 0.5);
    return uv;
}
