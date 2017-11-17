//----------------------------------------------------------.
// 共通して使用する関数など.
//----------------------------------------------------------.
#ifndef _SAO_COMMON_
#define _SAO_COMMON_

#include "UnityCG.cginc"

#define EPSILON 1e-7
#define UNITY_PI2 (UNITY_PI * 2.0)

// depth値を取得.
float getDepth (float2 uv) {
	return SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);
}

// LinearのZ値を計算.
float getLinearDepth (float depth) {
    // 以下は微妙に値がずれるのでコメントアウト.
	//return LinearEyeDepth(depth);

	float isOrtho = unity_OrthoParams.w;
	float isPers = 1.0 - unity_OrthoParams.w;
	depth *= _ZBufferParams.x;
	return (1.0 - isOrtho * depth) / (isPers * depth + _ZBufferParams.y);
}

// ビュー座標でのZ距離を取得.
float getViewZ (float depth) {
	// Z値(depth)を線形に変換.
	float z = getLinearDepth(depth);
				
	// ビュー座標でのZ距離に変換.
	float dist = z * _ProjectionParams.z;
	dist -= _ProjectionParams.y;

	return dist;
}

// ビュー座標での位置.
float3 getViewPosition (float2 uv, float liearDepth) {
	float2 p11_22 = float2(unity_CameraProjection._11, unity_CameraProjection._22);
    return float3((uv * 2.0 - 1.0) / p11_22, 1.0) * liearDepth;
}

// ビューでのdepthと法線を取得.
float getDepthNormal (float2 uv, out float3 normal) {
	float2 uv2 = UnityStereoScreenSpaceUVAdjust(uv, _CameraDepthTexture_ST);
	float4 cdn = tex2D(_CameraDepthNormalsTexture, uv2);
	normal = DecodeViewNormalStereo(cdn) * float3(1.0, 1.0, -1.0);		// 法線.
	return DecodeFloatRG(cdn.zw);			// Depth.
}

// ランダムな値を返す.
float rand2 (float2 co) {
	return frac(sin(dot(co.xy, float2(12.9898,78.233))) * 43758.5453);
}

#endif
