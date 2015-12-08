unit Shader;

{$IFDEF FPC}
{$MODE DELPHI}
{$ENDIF}

interface

uses
  Windows, SysUtils, Classes,
  DX12.D3D10, DX12.D3DX10, DX12.D3D11, DX12.D3DCommon, DX12.D3DCompiler, DX12.DXGI;

type
  { TDXAbstractShader }
  TDXAbstractShader = class
    private
      Function DumpErrorMessages(aFilename: string; pErrorBuffer: ID3DBlob): HRESULT;
      Function Initialize(pDevice: ID3D11Device; aPSName, aVSName: string): HRESULT;
      Function Uninitialize: HRESULT;
    protected
      FDevice: ID3D11Device;
      FInputLayout: ID3D11InputLayout;

      { Vertex and pixel shader objects }
      FVS: ID3D11VertexShader;
      FPS: ID3D11PixelShader;

      //Input layout
      FLayoutArray: Array[0..100] of TD3D11_INPUT_ELEMENT_DESC;
      FLayoutCount: Integer;

      //Following methods should be overriden by successor classes
      Function DecideInputLayout: HRESULT; virtual;
      Function OnInitialize: HRESULT; virtual;
      Function OnUninitialize: HRESULT; virtual;
    public
      Constructor Create(pDevice: ID3D11Device; aVSFilename, aPSFilename: string);
      Destructor Destroy; override;

      Function Activate(pDC: ID3D11DeviceContext): HRESULT;
  end;

  PDXColorShaderCB = ^TDXColorShaderCB;
  TDXColorShaderCB = record
    proj, view, model: TD3DMATRIX;
  end;

  { TDXColorShader }
  TDXColorShader = class(TDXAbstractShader)
    protected
      //We use this buffer to send the three matrices
      //to the shader program
      FConstantBuffer: ID3D11Buffer;

      //Sets number/names/types of the generic attributes
      Function DecideInputLayout: HRESULT; override;
      Function OnInitialize: HRESULT; override;
      Function OnUninitialize: HRESULT; override;
    public
      Function SetMatrices(pDC: ID3D11DeviceContext; aModel, aView, aProjection: TD3DMATRIX): HRESULT;
  end;

implementation

{ TDXColorShader }

function TDXColorShader.DecideInputLayout: HRESULT;
begin
  //We have only 2 attributes
  FLayoutCount := 2;

  //First is position
  FLayoutArray[0].SemanticName := 'POSITION';
  FLayoutArray[0].SemanticIndex := 0;
  FLayoutArray[0].Format := DXGI_FORMAT_R32G32B32_FLOAT;
  FLayoutArray[0].InputSlot := 0;
  FLayoutArray[0].AlignedByteOffset := 0;
  FLayoutArray[0].InputSlotClass := D3D11_INPUT_PER_VERTEX_DATA;
  FLayoutArray[0].InstanceDataStepRate := 0;

  //Second is color
  FLayoutArray[1].SemanticName := 'COLOR';
  FLayoutArray[1].SemanticIndex := 0;
  FLayoutArray[1].Format := DXGI_FORMAT_R32G32B32A32_FLOAT;
  FLayoutArray[1].InputSlot := 0;
  FLayoutArray[1].AlignedByteOffset := D3D11_APPEND_ALIGNED_ELEMENT;
  FLayoutArray[1].InputSlotClass := D3D11_INPUT_PER_VERTEX_DATA;
  FLayoutArray[1].InstanceDataStepRate := 0;

  //Success
  Result := S_OK;
end;

function TDXColorShader.OnInitialize: HRESULT;
var
  buffer_desc: TD3D11_BUFFER_DESC;
begin
  With buffer_desc do Begin
    Usage := D3D11_USAGE_DYNAMIC;
    ByteWidth := SizeOf(TD3DMATRIX) * 3;
    BindFlags := Ord(D3D11_BIND_CONSTANT_BUFFER);
    CPUAccessFlags := Ord(D3D11_CPU_ACCESS_WRITE);
    MiscFlags := 0;
    StructureByteStride := 0;
  End;

  //Create constant buffer
  Result := FDevice.CreateBuffer(buffer_desc, nil, FConstantBuffer);
end;

function TDXColorShader.OnUninitialize: HRESULT;
begin
  FConstantBuffer := nil;
  Result := S_OK;
end;

function TDXColorShader.SetMatrices(pDC: ID3D11DeviceContext; aModel, aView,
  aProjection: TD3DMATRIX): HRESULT;
var
  mapped_res: TD3D11_MAPPED_SUBRESOURCE;
  buf: PDXColorShaderCB;
begin
  //Map constant buffer
  Result := pDC.Map(FConstantBuffer, 0, D3D11_MAP_WRITE_DISCARD, 0, mapped_res);
  If Failed(Result) then Exit;

  //Get pointer to constant buffer's data
  buf := mapped_res.pData;

  //Transpose matrices
  D3DXMatrixTranspose(@aProjection, @aProjection);
  D3DXMatrixTranspose(@aView, @aView);
  D3DXMatrixTranspose(@aModel, @aModel);

  //Copy matrices to constant buffer
  buf^.proj := aProjection;
  buf^.view := aView;
  buf^.model := aModel;

  //Unmap
  pDC.Unmap(FConstantBuffer, 0);

  //Set constant buffer to (vertex) shader
  pDC.VSSetConstantBuffers(0, 1, @FConstantBuffer);
end;

{ TDXAbstractShader }

function TDXAbstractShader.DumpErrorMessages(aFilename: string;
  pErrorBuffer: ID3DBlob): HRESULT;
var
  f: TextFile;
  str: AnsiString;
  pErrBuff: PAnsiChar;
begin
  Try
    AssignFile(f, aFilename);
    Rewrite(f);

    Try
      pErrBuff := PAnsiChar(pErrorBuffer.GetBufferPointer());
      SetString(str, pErrBuff, pErrorBuffer.GetBufferSize());

      Writeln(f, AnsiString(pErrBuff));
    Finally
      CloseFile(f);
    End;

    Result := S_OK;
  Except
    Result := E_FAIL;
  End;
end;

function TDXAbstractShader.Initialize(pDevice: ID3D11Device; aPSName,
  aVSName: string): HRESULT;
var
  pPSBlob,
  pVSBlob,
  pErrorMsgs: ID3DBlob;
begin
  //Compile vertex shader
  Result := D3DCompileFromFile(
      PWideChar(WideString(aVSName)),
      nil,
      nil,
      'VSEntry',
      'vs_5_0',
      D3D10_SHADER_ENABLE_STRICTNESS,
      0,
      pVSBlob,
      pErrorMsgs
  );

  If Failed(Result) then Begin
    //If previous function has failed either the shader couldn't compile
    //or the shader file doesn't exist.

    If pErrorMsgs = nil then Begin
      //Shader file doesn't exist
      OutputDebugString(PChar(Format('Shader file "%s" not found.', [aVSName])));
      Exit;
    End;

    //Print error messages to file
    DumpErrorMessages('errors-vs.txt', pErrorMsgs);
    OutputDebugString(PChar(Format('Failed to compile vertex shader "%s". See file "errors-vs.txt" for more details.', [aVSName])));
    Exit;
  End;

  //Compile pixel shader
  Result := D3DCompileFromFile(
      PWideChar(WideString(aPSName)),
      nil,
      nil,
      'PSEntry',
      'ps_5_0',
      D3D10_SHADER_ENABLE_STRICTNESS,
      0,
      pPSBlob,
      pErrorMsgs
  );

  If Failed(Result) then Begin
    //If previous function has failed either the shader couldn't compile
    //or the shader file doesn't exist.

    If pErrorMsgs = nil then Begin
      //Shader file doesn't exist
      OutputDebugString(PChar(Format('Shader file "%s" not found.', [aVSName])));
      Exit;
    End;

    //Print error messages to file
    DumpErrorMessages('errors-ps.txt', pErrorMsgs);
    OutputDebugString(PChar(Format('Failed to compile pixel shader "%s". See file "errors-ps.txt" for more details.', [aPSName])));
    Exit;
  End;

  //Create vertex shader object from blob
  Result := pDevice.CreateVertexShader(pVSBlob.GetBufferPointer(), pVSBlob.GetBufferSize(), nil, FVS);
  If Failed(Result) then Exit;

  //Create pixel shader from blob
  Result := pDevice.CreatePixelShader(pPSBlob.GetBufferPointer(), pPSBlob.GetBufferSize(), nil, FPS);
  If Failed(Result) then Exit;

  //Set layout for the generic attributes (like vertox position, color, normals, etc)
  //Since the layout is different for particular shader programs, we invoke
  //successor-implemented method to decide the layout
  Result := DecideInputLayout;
  If Failed(Result) then Exit;

  //Create input layout object
  Result := pDevice.CreateInputLayout(
      @FLayoutArray[0],
      FLayoutCount,
      pVSBlob.GetBufferPointer(),
      pVSBlob.GetBufferSize(),
      FInputLayout
  );
  If Failed(Result) then Exit;

  //We don't need the blobs further
  pVSBlob := nil;
  pPSBlob := nil;

  //Get reference to D3D11 device
  FDevice := pDevice;

  //Invoke successor class' initialization routine
  Result := OnInitialize;
end;

function TDXAbstractShader.Uninitialize: HRESULT;
begin
  FInputLayout := nil;
  FVS := nil;
  FPS := nil;

  Result := OnUninitialize;
  FDevice := nil;
end;

function TDXAbstractShader.DecideInputLayout: HRESULT;
begin
  Result := E_NOTIMPL;
end;

function TDXAbstractShader.OnInitialize: HRESULT;
begin
  Result := S_OK;
end;

function TDXAbstractShader.OnUninitialize: HRESULT;
begin
  Result := S_OK;
end;

constructor TDXAbstractShader.Create(pDevice: ID3D11Device; aVSFilename,
  aPSFilename: string);
begin
  Inherited Create();

  If Failed(Initialize(pDevice, aPSFilename, aVSFilename)) then
    Raise Exception.Create('Failed to initialize shader(s).');
end;

destructor TDXAbstractShader.Destroy;
begin
  Uninitialize;

  inherited Destroy;
end;

function TDXAbstractShader.Activate(pDC: ID3D11DeviceContext): HRESULT;
begin
  //Set input layout
  pDC.IASetInputLayout(FInputLayout);

  //Set shaders
  pDC.VSSetShader(FVS, nil, 0);
  pDC.PSSetShader(FPS, nil, 0);

  //Success (hopefully)
  Result := S_OK;
end;

end.

