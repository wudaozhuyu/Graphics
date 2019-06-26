//-----------------------------------------------------------------------------
// SurfaceData and BSDFData
//-----------------------------------------------------------------------------
// SurfaceData is defined in Fabric.cs which generates Fabric.cs.hlsl
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Eye/Eye.cs.hlsl"
// Those define allow to include desired SSS/Transmission functions
#define MATERIAL_INCLUDE_SUBSURFACESCATTERING
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/SubsurfaceScattering/SubsurfaceScattering.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/NormalBuffer.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/VolumeRendering.hlsl"

//-----------------------------------------------------------------------------
// Texture and constant buffer declaration
//-----------------------------------------------------------------------------

#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/LTCAreaLight/LTCAreaLight.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/PreIntegratedFGD/PreIntegratedFGD.hlsl"

// #define FABRIC_DISPLAY_REFERENCE_IBL

//-----------------------------------------------------------------------------
// Helper functions/variable specific to this material
//-----------------------------------------------------------------------------

float3 GetNormalForShadowBias(BSDFData bsdfData)
{
    return bsdfData.geomNormalWS;
}

float GetAmbientOcclusionForMicroShadowing(BSDFData bsdfData)
{
    return bsdfData.ambientOcclusion;
}

void ClampRoughness(inout BSDFData bsdfData, float minRoughness)
{
    bsdfData.roughness = max(minRoughness, bsdfData.roughness);
}

// This function is use to help with debugging and must be implemented by any lit material
// Implementer must take into account what are the current override component and
// adjust SurfaceData properties accordingdly
void ApplyDebugToSurfaceData(float3x3 tangentToWorld, inout SurfaceData surfaceData)
{
#ifdef DEBUG_DISPLAY
    // Override value if requested by user
    // this can be use also in case of debug lighting mode like diffuse only
    bool overrideAlbedo = _DebugLightingAlbedo.x != 0.0;
    bool overrideSmoothness = _DebugLightingSmoothness.x != 0.0;
    bool overrideNormal = _DebugLightingNormal.x != 0.0;

    if (overrideAlbedo)
    {
        float3 overrideAlbedoValue = _DebugLightingAlbedo.yzw;
        surfaceData.baseColor = overrideAlbedoValue;
    }

    if (overrideSmoothness)
    {
        float overrideSmoothnessValue = _DebugLightingSmoothness.y;
        surfaceData.perceptualSmoothness = overrideSmoothnessValue;
    }

    if (overrideNormal)
    {
        surfaceData.normalWS = tangentToWorld[2];
    }

    // PBR validator isn't supported
    if (_DebugFullScreenMode == FULLSCREENDEBUGMODE_VALIDATE_DIFFUSE_COLOR)
    {
        surfaceData.baseColor = float3(1.0, 0.0, 1.0);
    }
    else if (_DebugFullScreenMode == FULLSCREENDEBUGMODE_VALIDATE_SPECULAR_COLOR)
    {
        surfaceData.baseColor = float3(1.0, 0.0, 1.0);
    }

#endif
}

// This function is similar to ApplyDebugToSurfaceData but for BSDFData
// Note: This will be available and used in ShaderPassForward.hlsl since in Fabric.shader,
// just before including the core code of the pass (ShaderPassForward.hlsl) we include
// Material.hlsl (or Lighting.hlsl which includes it) which in turn includes us,
// Fabric.shader, via the #if defined(UNITY_MATERIAL_*) glue mechanism.
void ApplyDebugToBSDFData(inout BSDFData bsdfData)
{
#ifdef DEBUG_DISPLAY
    // Override value if requested by user
    // this can be use also in case of debug lighting mode like specular only
    bool overrideSpecularColor = _DebugLightingSpecularColor.x != 0.0;

    if (overrideSpecularColor)
    {
        float3 overrideSpecularColor = _DebugLightingSpecularColor.yzw;
        bsdfData.fresnel0 = overrideSpecularColor;
    }
#endif
}

NormalData ConvertSurfaceDataToNormalData(SurfaceData surfaceData)
{
    NormalData normalData;
    normalData.normalWS = surfaceData.normalWS;
    normalData.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(surfaceData.perceptualSmoothness);
    return normalData;
}

SSSData ConvertSurfaceDataToSSSData(SurfaceData surfaceData)
{
    SSSData sssData;

    sssData.diffuseColor = surfaceData.baseColor;
    sssData.subsurfaceMask = surfaceData.subsurfaceMask;
    sssData.diffusionProfileIndex = FindDiffusionProfileIndex(surfaceData.diffusionProfileHash);

    return sssData;
}

//-----------------------------------------------------------------------------
// conversion function for forward
//-----------------------------------------------------------------------------

BSDFData ConvertSurfaceDataToBSDFData(uint2 positionSS, SurfaceData surfaceData)
{
    BSDFData bsdfData;
    ZERO_INITIALIZE(BSDFData, bsdfData);

    bsdfData.materialFeatures = surfaceData.materialFeatures;

    bsdfData.diffuseColor = surfaceData.baseColor;
    bsdfData.specularOcclusion = surfaceData.specularOcclusion;
    bsdfData.normalWS = surfaceData.normalWS;
    bsdfData.diffuseNormalWS = surfaceData.irisNormalWS;
    bsdfData.geomNormalWS = surfaceData.geomNormalWS;

    bsdfData.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(lerp(surfaceData.perceptualSmoothness, surfaceData.corneaPerceptualSmoothness, surfaceData.mask.x));
    
    bsdfData.fresnel0 = IorToFresnel0(lerp(surfaceData.scleraIOR, surfaceData.corneaIOR, surfaceData.mask.x)).xxx;
    bsdfData.ambientOcclusion = surfaceData.ambientOcclusion;

    bsdfData.mask = surfaceData.mask;

    // Note: we have ZERO_INITIALIZE the struct so bsdfData.anisotropy == 0.0
    // Note: DIFFUSION_PROFILE_NEUTRAL_ID is 0

    // In forward everything is statically know and we could theorically cumulate all the material features. So the code reflect it.
    // However in practice we keep parity between deferred and forward, so we should constrain the various features.
    // The UI is in charge of setuping the constrain, not the code. So if users is forward only and want unleash power, it is easy to unleash by some UI change

    bsdfData.diffusionProfileIndex = FindDiffusionProfileIndex(surfaceData.diffusionProfileHash);

    if (HasFlag(surfaceData.materialFeatures, MATERIALFEATUREFLAGS_EYE_SUBSURFACE_SCATTERING))
    {
        // Assign profile id and overwrite fresnel0
        FillMaterialSSS(bsdfData.diffusionProfileIndex, surfaceData.subsurfaceMask, bsdfData);
    }

    bsdfData.roughness = ClampRoughnessForAnalyticalLights(PerceptualRoughnessToRoughness(bsdfData.perceptualRoughness));

    ApplyDebugToBSDFData(bsdfData);

    return bsdfData;
}

//-----------------------------------------------------------------------------
// Debug method (use to display values)
//-----------------------------------------------------------------------------

// This function call the generated debug function and allow to override the debug output if needed
void GetSurfaceDataDebug(uint paramId, SurfaceData surfaceData, inout float3 result, inout bool needLinearToSRGB)
{
    GetGeneratedSurfaceDataDebug(paramId, surfaceData, result, needLinearToSRGB);
}

// This function call the generated debug function and allow to override the debug output if needed
void GetBSDFDataDebug(uint paramId, BSDFData bsdfData, inout float3 result, inout bool needLinearToSRGB)
{
    GetGeneratedBSDFDataDebug(paramId, bsdfData, result, needLinearToSRGB);
}

void GetPBRValidatorDebug(SurfaceData surfaceData, inout float3 result)
{
    result = surfaceData.baseColor;
}

//-----------------------------------------------------------------------------
// PreLightData
//
// Make sure we respect naming conventions to reuse ShaderPassForward as is,
// ie struct (even if opaque to the ShaderPassForward) name is PreLightData,
// GetPreLightData prototype.
//-----------------------------------------------------------------------------

// Precomputed lighting data to send to the various lighting functions
struct PreLightData
{
    float NdotV;        // Could be negative due to normal mapping, use ClampNdotV()
    float partLambdaV;

    // IBL
    float3 iblR;                     // Reflected specular direction, used for IBL in EvaluateBSDF_Env()
    float  iblPerceptualRoughness;

    float3 specularFGD;              // Store preintegrated BSDF for both specular and diffuse
    float  diffuseFGD;
};

// This function is call to precompute heavy calculation before lightloop
PreLightData GetPreLightData(float3 V, PositionInputs posInput, inout BSDFData bsdfData)
{
    PreLightData preLightData;
    ZERO_INITIALIZE(PreLightData, preLightData);

    float3 N = bsdfData.normalWS;
    preLightData.NdotV = dot(N, V);
    preLightData.iblPerceptualRoughness = bsdfData.perceptualRoughness;

    float clampedNdotV = ClampNdotV(preLightData.NdotV);

    // Handle IBL + area light + multiscattering.
    // Note: use the not modified by anisotropy iblPerceptualRoughness here.
    float specularReflectivity;
    GetPreIntegratedFGDGGXAndDisneyDiffuse(clampedNdotV, preLightData.iblPerceptualRoughness, bsdfData.fresnel0, preLightData.specularFGD, preLightData.diffuseFGD, specularReflectivity);
    preLightData.diffuseFGD = 1.0;

    float3 iblN;
    preLightData.partLambdaV = GetSmithJointGGXPartLambdaV(clampedNdotV, bsdfData.roughness);
    iblN = N;

    preLightData.iblR = reflect(-V, iblN);

    return preLightData;
}

//-----------------------------------------------------------------------------
// bake lighting function
//-----------------------------------------------------------------------------

// This define allow to say that we implement a ModifyBakedDiffuseLighting function to be call in PostInitBuiltinData
#define MODIFY_BAKED_DIFFUSE_LIGHTING

void ModifyBakedDiffuseLighting(float3 V, PositionInputs posInput, SurfaceData surfaceData, inout BuiltinData builtinData)
{
    // To get the data we need to do the whole process - compiler should optimize everything
    BSDFData bsdfData = ConvertSurfaceDataToBSDFData(posInput.positionSS, surfaceData);
    PreLightData preLightData = GetPreLightData(V, posInput, bsdfData);

    // For SSS we need to take into account the state of diffuseColor
    if (HasFlag(bsdfData.materialFeatures, MATERIALFEATUREFLAGS_EYE_SUBSURFACE_SCATTERING))
    {
        bsdfData.diffuseColor = GetModifiedDiffuseColorForSSS(bsdfData);
    }

    // Premultiply (back) bake diffuse lighting information with DisneyDiffuse pre-integration
    // Note: When baking reflection probes, we approximate the diffuse with the fresnel0
    builtinData.bakeDiffuseLighting *= preLightData.diffuseFGD * bsdfData.diffuseColor;
}

//-----------------------------------------------------------------------------
// light transport functions
//-----------------------------------------------------------------------------

LightTransportData GetLightTransportData(SurfaceData surfaceData, BuiltinData builtinData, BSDFData bsdfData)
{
    LightTransportData lightTransportData;

    // DiffuseColor for lightmapping
    lightTransportData.diffuseColor = bsdfData.diffuseColor;
    lightTransportData.emissiveColor = builtinData.emissiveColor;

    return lightTransportData;
}

//-----------------------------------------------------------------------------
// LightLoop related function (Only include if required)
// HAS_LIGHTLOOP is define in Lighting.hlsl
//-----------------------------------------------------------------------------

#ifdef HAS_LIGHTLOOP

//-----------------------------------------------------------------------------
// BSDF share between directional light, punctual light and area light (reference)
//-----------------------------------------------------------------------------

bool IsNonZeroBSDF(float3 V, float3 L, PreLightData preLightData, BSDFData bsdfData)
{
    float NdotL = dot(bsdfData.normalWS, L);

    return NdotL > 0.0;
}

// This function apply BSDF. Assumes that NdotL is positive.
CBSDF EvaluateBSDF(float3 V, float3 L, PreLightData preLightData, BSDFData bsdfData)
{
    CBSDF cbsdf;
    ZERO_INITIALIZE(CBSDF, cbsdf);

    float3 N = bsdfData.normalWS;

    float NdotV = preLightData.NdotV;
    float clampedNdotV = ClampNdotV(NdotV);

    float NdotL = dot(N, L);
    float clampedNdotL = saturate(NdotL);

    float LdotV, NdotH, LdotH, invLenLV;
    GetBSDFAngle(V, L, NdotL, NdotV, LdotV, NdotH, LdotH, invLenLV);

    float3 F = F_Schlick(bsdfData.fresnel0, LdotH);
    // We use abs(NdotL) to handle the none case of double sided
    float DV = DV_SmithJointGGX(NdotH, abs(NdotL), clampedNdotV, bsdfData.roughness, preLightData.partLambdaV);

    cbsdf.specR = F * DV * clampedNdotL;

    // Use diffuse normal map for diffuse

    N = bsdfData.diffuseNormalWS;
    clampedNdotL = saturate(dot(N, L));

    cbsdf.diffR = Lambert() * clampedNdotL * (1 - F);

    // We don't multiply by 'bsdfData.diffuseColor' here. It's done only once in PostEvaluateBSDF().
    return cbsdf;
}

//-----------------------------------------------------------------------------
// Surface shading (all light types) below
//-----------------------------------------------------------------------------

# include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/LightEvaluation.hlsl"
# include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/MaterialEvaluation.hlsl"
# include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/SurfaceShading.hlsl"

//-----------------------------------------------------------------------------
// EvaluateBSDF_Directional
//-----------------------------------------------------------------------------

DirectLighting EvaluateBSDF_Directional(LightLoopContext lightLoopContext,
                                        float3 V, PositionInputs posInput, PreLightData preLightData,
                                        DirectionalLightData lightData, BSDFData bsdfData,
                                        BuiltinData builtinData)
{
    return ShadeSurface_Directional(lightLoopContext, posInput, builtinData,
                                    preLightData, lightData, bsdfData, V);
}

//-----------------------------------------------------------------------------
// EvaluateBSDF_Punctual (supports spot, point and projector lights)
//-----------------------------------------------------------------------------

DirectLighting EvaluateBSDF_Punctual(LightLoopContext lightLoopContext,
                                     float3 V, PositionInputs posInput,
                                     PreLightData preLightData, LightData lightData,
                                     BSDFData bsdfData, BuiltinData builtinData)
{
    return ShadeSurface_Punctual(lightLoopContext, posInput, builtinData,
                                 preLightData, lightData, bsdfData, V);
}

//-----------------------------------------------------------------------------
// EvaluateBSDF_Line
//-----------------------------------------------------------------------------

DirectLighting EvaluateBSDF_Line(   LightLoopContext lightLoopContext,
                                    float3 V, PositionInputs posInput,
                                    PreLightData preLightData, LightData lightData, BSDFData bsdfData, BuiltinData builtinData)
{
    DirectLighting lighting;
    ZERO_INITIALIZE(DirectLighting, lighting);

    // TODO

    return lighting;
}

//-----------------------------------------------------------------------------
// EvaluateBSDF_Rect
//-----------------------------------------------------------------------------

DirectLighting EvaluateBSDF_Rect(   LightLoopContext lightLoopContext,
                                    float3 V, PositionInputs posInput,
                                    PreLightData preLightData, LightData lightData, BSDFData bsdfData, BuiltinData builtinData)
{
    DirectLighting lighting;
    ZERO_INITIALIZE(DirectLighting, lighting);

    // TODO

    return lighting;
}

DirectLighting EvaluateBSDF_Area(LightLoopContext lightLoopContext,
    float3 V, PositionInputs posInput,
    PreLightData preLightData, LightData lightData,
    BSDFData bsdfData, BuiltinData builtinData)
{
    if (lightData.lightType == GPULIGHTTYPE_TUBE)
    {
        return EvaluateBSDF_Line(lightLoopContext, V, posInput, preLightData, lightData, bsdfData, builtinData);
    }
    else
    {
        return EvaluateBSDF_Rect(lightLoopContext, V, posInput, preLightData, lightData, bsdfData, builtinData);
    }
}

//-----------------------------------------------------------------------------
// EvaluateBSDF_SSLighting for screen space lighting
// ----------------------------------------------------------------------------

IndirectLighting EvaluateBSDF_ScreenSpaceReflection(PositionInputs posInput,
                                                    PreLightData   preLightData,
                                                    BSDFData       bsdfData,
                                                    inout float    reflectionHierarchyWeight)
{
    IndirectLighting lighting;
    ZERO_INITIALIZE(IndirectLighting, lighting);

    // TODO: this texture is sparse (mostly black). Can we avoid reading every texel? How about using Hi-S?
    float4 ssrLighting = LOAD_TEXTURE2D_X(_SsrLightingTexture, posInput.positionSS);

    // Note: RGB is already premultiplied by A.
    // TODO: we should multiply all indirect lighting by the FGD value only ONCE.
    lighting.specularReflected = ssrLighting.rgb /* * ssrLighting.a */ * preLightData.specularFGD;
    reflectionHierarchyWeight = ssrLighting.a;

    return lighting;
}

IndirectLighting EvaluateBSDF_ScreenspaceRefraction(LightLoopContext lightLoopContext,
                                                    float3 V, PositionInputs posInput,
                                                    PreLightData preLightData, BSDFData bsdfData,
                                                    EnvLightData envLightData,
                                                    inout float hierarchyWeight)
{
    IndirectLighting lighting;
    ZERO_INITIALIZE(IndirectLighting, lighting);

    // No refraction

    return lighting;
}

//-----------------------------------------------------------------------------
// EvaluateBSDF_Env
// ----------------------------------------------------------------------------

// _preIntegratedFGD and _CubemapLD are unique for each BRDF
IndirectLighting EvaluateBSDF_Env(  LightLoopContext lightLoopContext,
                                    float3 V, PositionInputs posInput,
                                    PreLightData preLightData, EnvLightData lightData, BSDFData bsdfData,
                                    int influenceShapeType, int GPUImageBasedLightingType,
                                    inout float hierarchyWeight)
{
    IndirectLighting lighting;
    ZERO_INITIALIZE(IndirectLighting, lighting);

    float3 envLighting;
    float3 positionWS = posInput.positionWS;
    float weight = 1.0;

    float3 R = preLightData.iblR;

    // Note: using influenceShapeType and projectionShapeType instead of (lightData|proxyData).shapeType allow to make compiler optimization in case the type is know (like for sky)
    EvaluateLight_EnvIntersection(positionWS, bsdfData.normalWS, lightData, influenceShapeType, R, weight);

    float3 F = preLightData.specularFGD;

    float iblMipLevel;
    // TODO: We need to match the PerceptualRoughnessToMipmapLevel formula for planar, so we don't do this test (which is specific to our current lightloop)
    // Specific case for Texture2Ds, their convolution is a gaussian one and not a GGX one - So we use another roughness mip mapping.
    if (IsEnvIndexTexture2D(lightData.envIndex))
    {
        // Empirical remapping
        iblMipLevel = PlanarPerceptualRoughnessToMipmapLevel(preLightData.iblPerceptualRoughness, _ColorPyramidScale.z);
    }
    else
    {
        iblMipLevel = PerceptualRoughnessToMipmapLevel(preLightData.iblPerceptualRoughness);
    }

    float4 preLD = SampleEnv(lightLoopContext, lightData.envIndex, R, iblMipLevel);
    weight *= preLD.a; // Used by planar reflection to discard pixel

    envLighting = F * preLD.rgb;

    UpdateLightingHierarchyWeights(hierarchyWeight, weight);
    envLighting *= weight * lightData.multiplier;

    lighting.specularReflected = envLighting;

    return lighting;
}

//-----------------------------------------------------------------------------
// PostEvaluateBSDF
// ----------------------------------------------------------------------------

void PostEvaluateBSDF(  LightLoopContext lightLoopContext,
                        float3 V, PositionInputs posInput,
                        PreLightData preLightData, BSDFData bsdfData, BuiltinData builtinData, AggregateLighting lighting,
                        out float3 diffuseLighting, out float3 specularLighting)
{
    AmbientOcclusionFactor aoFactor;
    GetScreenSpaceAmbientOcclusionMultibounce(posInput.positionSS, preLightData.NdotV, bsdfData.perceptualRoughness, bsdfData.ambientOcclusion, bsdfData.specularOcclusion, bsdfData.diffuseColor, bsdfData.fresnel0, aoFactor);
    ApplyAmbientOcclusionFactor(aoFactor, builtinData, lighting);

    // Subsurface scattering mode
    float3 modifiedDiffuseColor = GetModifiedDiffuseColorForSSS(bsdfData);

    // Apply the albedo to the direct diffuse lighting (only once). The indirect (baked)
    // diffuse lighting has already multiply the albedo in ModifyBakedDiffuseLighting().
    diffuseLighting = modifiedDiffuseColor * lighting.direct.diffuse + builtinData.bakeDiffuseLighting + builtinData.emissiveColor;
    specularLighting = lighting.direct.specular + lighting.indirect.specularReflected;

#ifdef DEBUG_DISPLAY
    PostEvaluateBSDFDebugDisplay(aoFactor, builtinData, lighting, bsdfData.diffuseColor, diffuseLighting, specularLighting);
#endif
}

#endif // #ifdef HAS_LIGHTLOOP
