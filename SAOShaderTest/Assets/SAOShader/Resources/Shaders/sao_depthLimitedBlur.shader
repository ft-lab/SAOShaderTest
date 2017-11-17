//----------------------------------------------------------.
// GaussianによるBlur処理.
//----------------------------------------------------------.
Shader "Hidden/sao_depthLimitedBlur"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
		_DiffuseTex ("Texture", 2D) = "white" {}
		_Size ("Size", Vector) = (512, 512, 0, 0)
		_DepthCutoff ("DepthCutoff", float) = 10.0
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
			sampler2D _DiffuseTex;
			float4 _Size;
			float _DepthCutoff;
			float4 _SampleUVOffsets[16];
			float _SampleWeights[16];

			// あらかじめ用意されているもの.
			sampler2D_float _CameraDepthTexture;		// Depth Buffer.
			sampler2D _CameraDepthNormalsTexture;		// Normal Buffer.
			float4 _CameraDepthTexture_ST;

			#include "sao_common.cginc"

			#define KERNEL_RADIUS 2			// これが大きすぎるとボケが強い.
			#define DEPTH_PACKING 1
			#define PERSPECTIVE_CAMERA 1

			fixed4 frag (v2f i) : SV_Target
			{
				fixed4 col = tex2D(_MainTex, i.uv);

				// 深度値を取得 (0.0-1.0).
				float depth = getDepth(i.uv);
				if (depth >= (1.0 - EPSILON) || depth == 0.0) return float4(1, 1, 1, col.a);
				
				float centerViewZ = -getViewZ(depth);
				bool rBreak = false;
				bool lBreak = false;

				float weightSum   = _SampleWeights[0];
				float4 diffuseSum = col * weightSum;
				float2 vInvSize   = float2(1.0 / _Size.x, 1.0 / _Size.y);

				for (int j = 1; j <= KERNEL_RADIUS; j++) {
					float sampleWeight = _SampleWeights[j];
					float2 sampleUVOffset = _SampleUVOffsets[j] * vInvSize;

					float2 sampleUV = i.uv + sampleUVOffset;
					float viewZ = -getViewZ(getDepth(sampleUV));

					if (abs(viewZ - centerViewZ) > _DepthCutoff) rBreak = true;

					if (!rBreak) {
						diffuseSum += tex2D(_MainTex, sampleUV) * sampleWeight;
						weightSum += sampleWeight;
					}

					sampleUV = i.uv - sampleUVOffset;
					viewZ = -getViewZ(getDepth(sampleUV));
					if (abs(viewZ - centerViewZ) > _DepthCutoff) lBreak = true;

					if (!lBreak) {
						diffuseSum += tex2D(_MainTex, sampleUV) * sampleWeight;
						weightSum += sampleWeight;
					}
				}

				return diffuseSum / weightSum;
			}
			ENDCG
		}
	}
}
