unit Model;

{$IFDEF FPC}
{$MODE DELPHI}
{$ENDIF}

interface

uses
  Windows, SysUtils,
  DX12.D3D11, DX12.D3DX10, DX12.DXGI, DX12.D3DCommon;

type
  { Note that this vertex layout is bound to our custom shader's input
    vertex layout, so you can't use this model class with shaders which
    accept different vertex layout than this.

    Creating a generic model class, which is not dependant on shader
    input layout is a bit more complicated, and we may do it in further
    tutorials.
  }
  TDXVertex = record
    position: TFloatArray3;
    texcoords: TFloatArray2;
  end;

  { TDXModel }

  TDXModel = class
    private
      { Number of entries in index buffer }
      FIndexCount: Integer;

      { Vertex and index buffers for model }
      FVertexBuffer,
      FIndexBuffer: ID3D11Buffer;

      Function Initialize(pDevice: ID3D11Device; aVertexBufferSize, aIndexBufferSize: Integer): HRESULT;
      Function Uninitialize: HRESULT;
    public
      Constructor CreateQuad(pDeviceContext: ID3D11DeviceContext);
      Destructor Destroy; override;

      Function Render(pDeviceContext: ID3D11DeviceContext): HRESULT;
  end;

  Function D3DColor4f(r, g, b, a: single): TFloatArray4;
  Function D3DColor3f(r, g, b: single): TFloatArray3;

  Function D3DVector2f(x, y: single): TFloatArray2;
  Function D3DVector3f(x, y, z: single): TFloatArray3;
  Function D3DVector4f(x, y, z, w: single): TFloatArray4;

  Function D3DXVector3f(x, y, z: Single): TD3DXVECTOR3;

implementation

function D3DColor4f(r, g, b, a: single): TFloatArray4;
begin
  Result[0] := r;
  Result[1] := g;
  Result[2] := b;
  Result[3] := a;
end;

function D3DColor3f(r, g, b: single): TFloatArray3;
begin
  Result[0] := r;
  Result[1] := g;
  Result[2] := b;
end;

function D3DVector2f(x, y: single): TFloatArray2;
begin
  Result[0] := x;
  Result[1] := y;
end;

function D3DVector3f(x, y, z: single): TFloatArray3;
begin
  Result[0] := x;
  Result[1] := y;
  Result[2] := z;
end;

function D3DVector4f(x, y, z, w: single): TFloatArray4;
begin
  Result[0] := x;
  Result[1] := y;
  Result[2] := z;
  Result[3] := w;
end;

function D3DXVector3f(x, y, z: Single): TD3DXVECTOR3;
begin
  Result.x := x;
  Result.y := y;
  Result.z := z;
end;

{ TDXModel }

function TDXModel.Initialize(pDevice: ID3D11Device; aVertexBufferSize,
  aIndexBufferSize: Integer): HRESULT;
var
  vert_buffer_desc,
  index_buffer_desc: TD3D11_BUFFER_DESC;
begin
  //Set up vertex buffer desc
  With vert_buffer_desc do Begin
    Usage := D3D11_USAGE_DYNAMIC;
    ByteWidth := aVertexBufferSize;
    BindFlags := Ord(D3D11_BIND_VERTEX_BUFFER);
    CPUAccessFlags := Ord(D3D11_CPU_ACCESS_WRITE);
    MiscFlags := 0;
    StructureByteStride := 0;
  End;

  //Create vertex buffer
  Result := pDevice.CreateBuffer(vert_buffer_desc, nil, FVertexBuffer);
  If Failed(Result) then Exit;

  //Set up index buffer desc
  With index_buffer_desc do Begin
    Usage := D3D11_USAGE_DYNAMIC;
    ByteWidth := aIndexBufferSize;
    BindFlags := Ord(D3D11_BIND_INDEX_BUFFER);
    CPUAccessFlags := Ord(D3D11_CPU_ACCESS_WRITE);
    MiscFlags := 0;
    StructureByteStride := 0;
  End;

  //Create vertex buffer
  Result := pDevice.CreateBuffer(index_buffer_desc, nil, FIndexBuffer);
end;

function TDXModel.Uninitialize: HRESULT;
begin
  FVertexBuffer := nil;
  FIndexBuffer := nil;

  Result := S_OK;
end;

constructor TDXModel.CreateQuad(pDeviceContext: ID3D11DeviceContext);
var
  pDevice: ID3D11Device;
  mapped_res: TD3D11_MAPPED_SUBRESOURCE;

  vertices: Array[0..3] of TDXVertex;
  indices: Array[0..6] of Word;
begin
  Inherited Create;

  //Get device
  pDeviceContext.GetDevice(pDevice);

  //Create vertex/index buffers
  If Failed(Initialize(pDevice, SizeOf(vertices), SizeOf(indices))) then
     Raise Exception.Create('Failed to create model.');

  //Create quad
  pDeviceContext.Map(FVertexBuffer, 0, D3D11_MAP_WRITE_DISCARD, 0, mapped_res);

  Try
    //Generate quad
    vertices[0].position := D3DVector3f(-1.0, -1.0, 0.0);
    vertices[1].position := D3DVector3f( 1.0,  1.0, 0.0);
    vertices[2].position := D3DVector3f(-1.0,  1.0, 0.0);
    vertices[3].position := D3DVector3f( 1.0, -1.0, 0.0);

    vertices[0].texcoords := D3DVector2f(0, 0);
    vertices[1].texcoords := D3DVector2f(1, 1);
    vertices[2].texcoords := D3DVector2f(0, 1);
    vertices[3].texcoords := D3DVector2f(1, 0);

    //Copy to vertex buffer
    Move(vertices[0], mapped_res.pData^, SizeOf(vertices));
  Finally
    pDeviceContext.Unmap(FVertexBuffer, 0);
  End;

  //Create quad
  pDeviceContext.Map(FIndexBuffer, 0, D3D11_MAP_WRITE_DISCARD, 0, mapped_res);

  Try
    //Populate index buffer
    indices[0] := 0;
    indices[1] := 2;
    indices[2] := 1;

    indices[3] := 0;
    indices[4] := 1;
    indices[5] := 3;

    //Copy to vertex buffer
    Move(indices[0], mapped_res.pData^, SizeOf(indices));
  Finally
    pDeviceContext.Unmap(FIndexBuffer, 0);
  End;

  FIndexCount := 6;
end;

destructor TDXModel.Destroy;
begin
  Uninitialize;
  inherited Destroy;
end;

function TDXModel.Render(pDeviceContext: ID3D11DeviceContext): HRESULT;
var
  stride, offset: UINT;
begin
  //Get vertex stride
  stride := SizeOf(TDXVertex);
  offset := 0;

  //Bind vertex buffer
  pDeviceContext.IASetVertexBuffers(0, 1, @FVertexBuffer, @stride, @offset);

  //Bind index buffer
  pDeviceContext.IASetIndexBuffer(FIndexBuffer, DXGI_FORMAT_R16_UINT, 0);

  //Tell device context that we want to draw triangle list
  pDeviceContext.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

  //Draw
  pDeviceContext.DrawIndexed(FIndexCount, 0, 0);

  Result := S_OK;
end;

end.

