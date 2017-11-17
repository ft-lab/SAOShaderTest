//----------------------------------------------------------.
// AOとRGBを合成するShader.
//----------------------------------------------------------.
Shader "Hidden/sao_blend"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
		_AOTex ("Texture", 2D) = "white" {}
		_Intensity ("Intensity", float) = 1.0
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
			sampler2D _AOTex;
			float _Intensity;

			// Build-in. あらかじめ用意されているもの.
			sampler2D_float _CameraDepthTexture;		// Depth Buffer.
			sampler2D _CameraDepthNormalsTexture;		// Normal Buffer.
			float4 _CameraDepthTexture_ST;

			#include "sao_common.cginc"

			fixed4 frag (v2f i) : SV_Target
			{
				float4 col = tex2D(_MainTex, i.uv);

				// 深度値を取得 (0.0-1.0).
				float depth = getDepth(i.uv);
				if (depth >= (1.0 - EPSILON) || depth == 0.0) return col;
				
				float aoVal = lerp(1.0, tex2D(_AOTex, i.uv).r, _Intensity);

				col.rgb *= float3(aoVal, aoVal, aoVal);

				return col;
			}
			ENDCG
		}
	}
}
