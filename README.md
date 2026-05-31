# :stars: Lumenite Shaders
Questions, comments or need to contact support? Join the Lumenite discord: https://discord.gg/deXJrW2dx6

## Kernel - (Reconstructed Normals, Motion vectors, etc.)
![Kernel poster](https://github.com/umar-afzaal/asset-repo/blob/mainline/lumenitefx/Kernel_poster.jpg)
Pre-effect for other LumeniteFX shaders. Computes normals, motion vectors, motion confidence, etc. once and populates the textures for subsequent use.

Shaders that support Kernel:
- JakobPCoder's [TFAA: Temporal Filter AntiAliasing](https://github.com/JakobPCoder/Reshade-Shades/blob/main/Shaders/Shades/TFAA.fx)

## RTAO/LSAO - Ray Traced Ambient Occlusion
![RTAO poster](https://github.com/umar-afzaal/asset-repo/blob/mainline/lumenitefx/RTAO_poster.jpg)
Screen-space ray traced Ambient Occlusion shaders for ReShade.

## Anamorphic Bloom
![AnamorphicBloom poster](https://github.com/umar-afzaal/asset-repo/blob/mainline/lumenitefx/AnamorphicBloom_poster.jpg)
Artistic bloom shader that creates the anamorphic lens aesthetic.

## SSSR - Stochastic Screen Space Reflections
![SSSR poster](https://github.com/umar-afzaal/asset-repo/blob/mainline/lumenitefx/SSSR_poster.jpg)
High-quality screen space reflections.

## LumaFlow - Dense Real-time Motion Estimation
![LumaFlow poster](https://github.com/umar-afzaal/asset-repo/blob/mainline/lumenitefx/LumaFlow_poster.jpg)
LumaFlow is a motion estimation shader written for ReShade. It determines where each pixel in the current frame originated from in the previous frame, providing a 'motion vector' for this tracking. These motion vectors can enable various applications: TAA, frame generation, temporal reprojection, and other motion-dependent effects like motion blur.
