//----------------------------------------------------------.
// SAO (Scalable Ambient Obscurance)のImage Effect.
// 参考 : three.jsのexamples/webgl_postprocessing_sao.html.
//----------------------------------------------------------.
Shader "Hidden/sao"
{

	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
		_Size ("Size", Vector) = (512, 512, 0, 0)
		_Bias ("Bias", float) = 0.5
		_Intensity ("Intensity", float) = 0.005
		_Scale ("Scale", float) = 1.0
		_KernelRadius ("KernelRadius", float) = 10.0
		_MinResolution ("MinResolution", float) = 0.0
		_Blur ("Blur", int) = 1
		_BlurRadius ("BlurRadius", float) = 8.0
		_BlurStdDev ("BlurStdDev", float) = 4.0
		_BlurDepthCutoff ("BlurDepthCutoff", float) = 0.01
		_FalloffDistance ("FalloffDistance", float) = 500.0
	}
	SubShader
	{
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass
		{
			CGPROGRAM
			#pragma target 3.0
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
			};

			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				return o;
			}
			
			sampler2D _MainTex;
			float4 _Size;
			float _Bias;
			float _Intensity;
			float _Scale;
			float _KernelRadius;
			float _MinResolution;
			float _Blur;
			float _BlurRadius;
			float _BlurStdDev;
			float _BlurDepthCutoff;
			float _FalloffDistance;

			// あらかじめ用意されているもの.
			sampler2D_float _CameraDepthTexture;		// Depth Buffer.
			sampler2D _CameraDepthNormalsTexture;		// Normal Buffer.
			float4 _CameraDepthTexture_ST;

			#include "sao_common.cginc"

			#define NUM_SAMPLES  24			// サンプリング数.
			#define NUM_RINGS  4
			#define NORMAL_TEXTURE  0
			#define DIFFUSE_TEXTURE  0
			#define DEPTH_PACKING  1
			#define PERSPECTIVE_CAMERA  1

			static const float ANGLE_STEP = UNITY_PI2 * float(NUM_RINGS) / float(NUM_SAMPLES);
			static const float INV_NUM_SAMPLES = 1.0 / float(NUM_SAMPLES);

			float getOcclusion (float3 centerViewPosition, float3 centerViewNormal, float3 sampleViewPosition, float scaleDividedByCameraFar, float minResolutionMultipliedByCameraFar) {
				float3 viewDelta = sampleViewPosition - centerViewPosition;
				float viewDistance = length(viewDelta);
				float scaledScreenDistance = scaleDividedByCameraFar * viewDistance;
				return max(0.0, (dot(centerViewNormal, viewDelta) - minResolutionMultipliedByCameraFar) / scaledScreenDistance - _Bias) / (1.0 + pow(2.0, scaledScreenDistance));
			}

			// AOの計算.
			float getAmbientOcclusion (float3 centerViewPosition, float2 uv) {
				// 距離による減衰.
				float vDistance = getViewZ(getDepth(uv));	// uv位置でのZ距離.
				if (_FalloffDistance != 0.0 && vDistance > _FalloffDistance) {
					return 0.0;
				}
				float falloffV = (_FalloffDistance == 0.0) ? 1.0 : pow(1.0 - vDistance / _FalloffDistance, 2.0);

				float cameraNear = _ProjectionParams.y;
				float cameraFar  = _ProjectionParams.z;
				float scaleDividedByCameraFar = _Scale / cameraFar;
				float minResolutionMultipliedByCameraFar = _MinResolution * cameraFar;

				float3 centerViewNormal;
				float depth = getDepthNormal(uv, centerViewNormal);

				float angle = rand2(uv) * UNITY_PI2;
				float r = _KernelRadius * INV_NUM_SAMPLES;
				float2 radius = float2(r / _Size.x, r / _Size.y);
				float2 radiusStep = radius;
				
				float occlusionSum = 0.0;
				float weightSum    = 0.0;
				for (int i = 0; i < NUM_SAMPLES; i++) {
					float2 sampleUV = uv + float2(cos(angle), sin(angle)) * radius;
					radius += radiusStep;
					angle += ANGLE_STEP;

					// sampleUVの位置でのdepth値を取得.
					float sampleDepth = getDepth(sampleUV);
					if (sampleDepth >= (1.0 - EPSILON) || sampleDepth == 0.0) continue;
					float sampleLinearDepth = getLinearDepth(sampleDepth);

					float3 sampleViewPosition = getViewPosition(sampleUV, sampleLinearDepth);
					occlusionSum += getOcclusion(centerViewPosition, centerViewNormal, sampleViewPosition, scaleDividedByCameraFar, minResolutionMultipliedByCameraFar);
					weightSum += 1.0;
				}

				if (weightSum == 0.0) return 0.0;
				return occlusionSum * (_Intensity / weightSum) * falloffV;
			}

			fixed4 frag (v2f i) : SV_Target
			{
				fixed4 col = tex2D(_MainTex, i.uv);

				// 深度値を取得 (0.0-1.0).
				float depth = getDepth(i.uv);
				if (depth >= (1.0 - EPSILON) || depth == 0.0) return float4(1, 1, 1, col.a);

				// ビュー座標での位置.
				float linearDepth = getLinearDepth(depth);
				float3 viewPos = getViewPosition(i.uv, linearDepth);

				// AO値を計算.
				float ambientOcclusion = 1.0 - getAmbientOcclusion(viewPos, i.uv);

				col.rgb = float3(ambientOcclusion, ambientOcclusion, ambientOcclusion);
				return col;
			}
			ENDCG
		}
	}
}
