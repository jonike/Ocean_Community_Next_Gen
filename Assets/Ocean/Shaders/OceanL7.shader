// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Mobile/OceanL7" {
	Properties {
	    _SurfaceColor ("SurfaceColor", Color) = (1,1,1,1)
	    _WaterColor ("WaterColor", Color) = (1,1,1,1)

		_Specularity ("Specularity", Range(0.01,8)) = 0.3
		_SpecPower("Specularity Power", Range(0,1)) = 1

		[HideInInspector] _SunColor ("SunColor", Color) = (1,1,0.901,1)

		_Refraction ("Refraction (RGB)", 2D) = "white" {}
		_Reflection ("Reflection (RGB)", 2D) = "white" {}
		_Bump ("Bump (RGB)", 2D) = "bump" {}
		_Foam("Foam (RGB)", 2D) = "white" {}
		_FoamFactor("Foam Factor", Range(0,3)) = 1.8
		
		_Size ("UVSize", Float) = 0.015625//this is the best value (1/64) to have the same uv scales of normal and foam maps on all ocean sizes
		_FoamSize ("FoamUVSize", Float) = 2//tiling of the foam texture
		[HideInInspector] _SunDir ("SunDir", Vector) = (0.3, -0.6, -1, 0)

		[NoScaleOffset] _FoamGradient ("Foam gradient ", 2D) = "white" {}
		_ShoreDistance("Shore Distance", Range(0,20)) = 4
		_ShoreStrength("Shore Strength", Range(1,4)) = 1.5

		_Translucency("Transucency Factor", Range(0,6)) = 2.5
		_DistanceCancellation ("Distance Cancellation", Float) = 2000

	}

	//water bump/foam/reflection/refraction/translucency
	SubShader {
	    Tags { "RenderType" = "Opaque" "Queue"="Geometry"}
		LOD 8
    	Pass {
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			//#pragma multi_compile_fog
			#pragma multi_compile SHORE_ON SHORE_OFF
			#pragma multi_compile FOGON FOGOFF
			#pragma multi_compile DCON	DCOFF

			#pragma target 2.0

			#include "UnityCG.cginc"

			struct v2f {
    			float4 pos : SV_POSITION;
    			half4  projTexCoord : TEXCOORD0;
    			float3  bumpTexCoord : TEXCOORD1;
				#ifdef SHORE_ON
				float4 ref : TEXCOORD2;
				#endif
    			half4  objSpaceNormal : TEXCOORD3;
    			half3  lightDir : TEXCOORD4;
				float2 buv : TEXCOORD5;
				half3 normViewDir : TEXCOORD6;
				//UNITY_FOG_COORDS(7)
				#ifdef FOGON
				half2 dist : TEXCOORD7;
				#endif
			};

			half _Size;
			half _FoamFactor;
			half4 _SunDir;
			half _Translucency;
			#ifdef FOGON
 			uniform half4 unity_FogStart;
			uniform half4 unity_FogEnd;
			uniform half4 unity_FogDensity;
			#ifdef DCON
			half _DistanceCancellation;
			#endif
			#endif

			v2f vert (appdata_tan v) {
    			v2f o;
				UNITY_INITIALIZE_OUTPUT(v2f, o);

    			o.bumpTexCoord.xy = v.vertex.xz*_Size;

    			o.pos = UnityObjectToClipPos (v.vertex);

				o.bumpTexCoord.z = v.tangent.w * _FoamFactor;

  				half4 projSource = half4(v.vertex.x, 0.0, v.vertex.z, 1.0);
    			half4 tmpProj = UnityObjectToClipPos( projSource);

				o.projTexCoord.xy = 0.5 * tmpProj.xy * half2(1, _ProjectionParams.x) / tmpProj.w + half2(0.5, 0.5);

    			half3 objSpaceViewDir = ObjSpaceViewDir(v.vertex);
    			half3 binormal = cross( normalize(v.normal), normalize(v.tangent.xyz) );
				half3x3 rotation = half3x3( v.tangent.xyz, binormal, v.normal );
    
    			o.objSpaceNormal.xyz = v.normal;
    			half3 viewDir = mul(rotation, objSpaceViewDir);
    			o.lightDir = mul(rotation, half3(_SunDir.xyz));

				float tt = _SinTime.x * 0.3;//hack to stay within the 64 instructions limit
				o.buv = float2(o.bumpTexCoord.x + tt, o.bumpTexCoord.y + tt);

				o.normViewDir = normalize(viewDir);

				half3 transLightDir = -o.lightDir + v.normal;

				o.objSpaceNormal.w = pow ( max (0, dot ( o.normViewDir, -transLightDir ) ), 1 ) * 0.5 * _Translucency;

   	  			#ifdef SHORE_ON
				o.ref = ComputeScreenPos(o.pos);
				#endif

				#ifdef FOGON
				//manual fog
				half fogDif = 1.0/(unity_FogEnd.x - unity_FogStart.x);
				o.dist.x = (unity_FogEnd.x - length(o.pos.xyz)) * fogDif;
				#ifdef DCON
				o.dist.y = (unity_FogEnd.x - _DistanceCancellation) * fogDif;
				#endif
                #endif

				//autofog
				//UNITY_TRANSFER_FOG(o, o.pos);

    			return o;
			}

			sampler2D _Refraction;
			sampler2D _Reflection;
			sampler2D _Bump;
			sampler2D _Foam;
			half _FoamSize;
			#ifdef SHORE_ON
			uniform sampler2D _CameraDepthTexture;
			half _ShoreDistance;
			half _ShoreStrength;
			#endif
			
			half4 _SurfaceColor;
			half4 _WaterColor;
			half _Specularity;
			half _SpecPower;
			half4 _SunColor;
			//half4 _FakeUnderwaterColor;


			half4 frag (v2f i) : COLOR {
				#ifdef FOGON
				#ifdef DCON
				if(i.dist.x>i.dist.y){
				#endif
				#endif
					//foam
					half _foam = tex2D(_Foam, -i.buv.xy  *_FoamSize).r;
					half foam = clamp(_foam - 0.5, 0.0, 1.0) * i.bumpTexCoord.z;
					//-----------------------------------------------------------------------------------------------------------------------------------------------------------

					//bumps			
					half3 tangentNormal0 = (tex2D(_Bump, i.buv.xy) * 2.4) -1;
					half3 tangentNormal = normalize(tangentNormal0);

					half2 bumpSampleOffset = (i.objSpaceNormal.xz  + tangentNormal.xy) * 0.05  + i.projTexCoord.xy;

					//-----------------------------------------------------------------------------------------------------------------------------------------------------------

					//fresnel
					half fresnelTerm = 1.0 - saturate(dot (i.normViewDir, tangentNormal0));
					half3 floatVec = normalize(i.normViewDir - normalize(i.lightDir));
					//-----------------------------------------------------------------------------------------------------------------------------------------------------------

					 //specular
					half specular = pow(max(dot(floatVec,  tangentNormal) , 0.0), 250.0 * _Specularity ) * _SpecPower;// *(1.2-foam);

					 //-----------------------------------------------------------------------------------------------------------------------------------------------------------
					 //translucency
					half3 wc = _WaterColor.rgb * i.objSpaceNormal.w * _SunColor.rgb;//* floatVec.z 

					half4 result = half4(wc.x , wc.y , wc.z, 1);
					//-----------------------------------------------------------------------------------------------------------------------------------------------------------
					//reflection refraction
					half3 reflection = tex2D( _Reflection,  bumpSampleOffset) * _SurfaceColor ;
					half3 refraction = tex2D( _Refraction,  bumpSampleOffset ) * _WaterColor ;//*_FakeUnderwaterColor

					//-----------------------------------------------------------------------------------------------------------------------------------------------------------
					//SHORELINES
					#ifdef SHORE_ON
					//UNITY5.5
					//#if defined(UNITY_REVERSED_Z)
						//float zdepth = 1.0f - LinearEyeDepth (tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(i.ref)).r);
					//#else
						float zdepth = LinearEyeDepth (tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(i.ref)).r);
					//#endif
                    float intensityFactor = 1 - saturate((zdepth - i.ref.w) / _ShoreDistance);
					foam += _ShoreStrength * intensityFactor * _foam;
					#endif

					//-----------------------------------------------------------------------------------------------------------------------------------------------------------
					//half4 result = half4(0 , 0 , 0, 1);
					//method2
					result.rgb += lerp(refraction, reflection, fresnelTerm)*_SunColor.rgb + clamp(foam, 0.0, 1.0)*_SunColor.b + specular*_SunColor.rgb;

					//fog
					//UNITY_APPLY_FOG(i.fogCoord, result); 

					#ifdef FOGON
					//manual fog (linear) (reduces instructions on d3d9)
					float ff = saturate(i.dist.x);
					result.rgb = lerp(unity_FogColor.rgb, result.rgb, ff);
					#endif

    				return result;
				#ifdef FOGON
				#ifdef DCON
				}else{
					return unity_FogColor;
				}
				#endif
				#endif
			}

			ENDCG
		}
    }

 
        
	
		   
}
