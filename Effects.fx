
// Vertex Shader
struct VS_INPUT
{
	float3 vPosition : POSITION;
	float3 vNormal: NORMAL;
	float2 vUVCoords: TEXCOORD;
};

struct PS_INPUT
{
	float4 vPosition : SV_POSITION;
	float2 vUVCoords : TEXCOORD0;
};

cbuffer SceneConstantBuffer : register(b0)
{
	float4x4 vp_matrix;
	float4x4 model_matrix;
};

SamplerState g_SamplerState : register(s0);
Texture2D g_Texture : register(t0);


PS_INPUT VS( VS_INPUT i )
{
	PS_INPUT o;
	o.vPosition = mul( mul(vp_matrix, model_matrix), float4( i.vPosition, 1.0 ) );
	o.vUVCoords = i.vUVCoords;
	return o;
}

float4 PS( PS_INPUT i ) : SV_TARGET
{
	float4 vColor = g_Texture.Sample( g_SamplerState, i.vUVCoords );
	return vColor;
}