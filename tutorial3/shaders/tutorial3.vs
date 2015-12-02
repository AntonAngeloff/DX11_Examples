//Constant buffer structure
cbuffer MatrixBuffer
{
    matrix ProjMatrix;
    matrix ViewMatrix;
    matrix ModelMatrix;
};

//Vertex data, as defined by the input layout
struct VSInput
{
    float4 position : POSITION;
    float2 texcoords : TEXCOORD0;
};

//Pixel shader's input structure (same as vertex shader's)
struct PSInput
{
    float4 position : SV_POSITION;
    float2 texcoords : TEXCOORD0;
};

//Shader's main function
PSInput VSEntry(VSInput input)
{
    PSInput output;
    
    //Set w component to 1
    input.position.w = 1.0f;

    //Transform vertex position with model, view and projection matrices
    output.position = mul(input.position, ModelMatrix);
    output.position = mul(output.position, ViewMatrix);
    output.position = mul(output.position, ProjMatrix);
   
    //Forward color value to pixel shader
    output.texcoords = input.texcoords;
    
    return output;
}