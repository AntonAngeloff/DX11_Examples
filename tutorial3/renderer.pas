unit Renderer;

{$IFDEF FPC}
{$MODE DELPHI}
{$ENDIF}

interface

uses
  Windows, SysUtils, {$IFDEF FPC}Graphics{$ELSE}Vcl.Graphics{$ENDIF}, Shader, Model,

  //Include D3D11 and DXGI units
  DX12.D3D11, DX12.DXGI, DX12.D3DCommon,

  //We have to use DX10 unit for the matrix manipulation functions
  DX12.D3DX10;

const
  Z_NEAR      = 1;
  Z_FAR       = 100;

type
  TDXVertex = record
    position: TFloatArray3;
    color: TFloatArray4;
  end;

  { TDXRenderer }
  TDXRenderer = class
    private
      { D3D11 Device and Device Context }
      FDevice: ID3D11Device;
      FDeviceContext: ID3D11DeviceContext;
      FCurrentFeatureLevel: TD3D_FEATURE_LEVEL;

      { Swapchain }
      FSwapchain: IDXGISwapChain;
      FRenderTargetView: ID3D11RenderTargetView;

      { Depth, stencil and raster states }
      FDepthStencilBuffer: ID3D11Texture2D;
      FDepthStencilState: ID3D11DepthStencilState;
      FDepthStencilView: ID3D11DepthStencilView;
      FRasterizerState: ID3D11RasterizerState;
      FViewport: TD3D11_VIEWPORT;

      { Matrices }
      FProjMatrix,
      FViewMatrix,
      FModelMatrix: TD3DMATRIX;

      { Flag which signalizes that renderer is initialized }
      FReady,
      FEnableVSync: Boolean;

      { Shader program }
      FShader: TDXTextureShader;

      { Our quad model }
      FQuad: TDXModel;

      { Wood texture }
      FTexture: ID3D11Texture2D;
      FTextureSRV: ID3D11ShaderResourceView;

      Function Initialize(aHWND: HWND; aWidth, aHeight: Integer): HRESULT;
      Function Uninitialize: HRESULT;
      Function InitializeTexture: HRESULT;
    public
      Constructor Create(aHWND: HWND; aWidth, aHeight: Integer);
      Destructor Destroy; override;

      Function Clear(aColor: TFloatArray4): HRESULT;
      Function Render: HRESULT;
      Function Present: HRESULT;
  end;

  Procedure Convert24bppTo32bpp(src: TBitmap; target: Pointer);

implementation

procedure Convert24bppTo32bpp(src: TBitmap; target: Pointer);
var
  i, j, w, h: integer;
  psrc, pdst: pbyte;
begin
  pdst := target;
  w := src.Width;
  h := src.Height;

  for j:=0 to h-1 do begin
    psrc := src.ScanLine[j];

    for i:=0 to w-1 do Begin
      pdst^ := psrc^; inc(psrc); inc(pdst);
      pdst^ := psrc^; inc(psrc); inc(pdst);
      pdst^ := psrc^; inc(psrc); inc(pdst);
      pdst^ := 255; inc(pdst);
    end;
  end;
end;

{ TDXRenderer }

function TDXRenderer.Initialize(aHWND: HWND; aWidth, aHeight: Integer): HRESULT;
var
  feature_level: Array[0..0] of TD3D_FEATURE_LEVEL;
  pBackbuffer: ID3D11Texture2D;

  swapchain_desc: TDXGI_SWAP_CHAIN_DESC;
  depth_desc: TD3D11_TEXTURE2D_DESC;
  depth_state_desc: TD3D11_DEPTH_STENCIL_DESC;
  depth_view_desc: TD3D11_DEPTH_STENCIL_VIEW_DESC;
  rast_state_desc: TD3D11_RASTERIZER_DESC;
begin
  //If we are already initialized, then call Uninitialize() before proceeding.
  If FReady then Begin
    Result := Uninitialize;
    If Failed(Result) then Exit;
  end;

  //Configure swapchain descriptor
  {$HINTS off}
  FillChar(swapchain_desc, SizeOf(TDXGI_SWAP_CHAIN_DESC), 0);
  {$HINTS on}
  With swapchain_desc do Begin
    BufferCount := 1;

    BufferDesc.Width := aWidth;
    BufferDesc.Height := aHeight;
    BufferDesc.Format := DXGI_FORMAT_R8G8B8A8_UNORM;
    BufferDesc.RefreshRate.Numerator := 0;
    BufferDesc.RefreshRate.Denominator := 1;
    BufferDesc.ScanlineOrdering := DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED;
    BufferDesc.Scaling := DXGI_MODE_SCALING_UNSPECIFIED;

    BufferUsage := DXGI_USAGE_RENDER_TARGET_OUTPUT;
    OutputWindow := aHWND;
    SampleDesc.Count := 1;
    SampleDesc.Quality := 0;
    Windowed := True;

    SwapEffect := DXGI_SWAP_EFFECT_DISCARD;
    Flags := 0;
  End;

  //Decide feature level
  feature_level[0] := D3D_FEATURE_LEVEL_11_0;

  //Create Direct3D 11 device and a swap chain
  Result := D3D11CreateDeviceAndSwapChain(
      nil,
      D3D_DRIVER_TYPE_HARDWARE,
      0,
      0,
      @feature_level[0],
      1,
      D3D11_SDK_VERSION,
      @swapchain_desc,
      FSwapchain,
      FDevice,
      FCurrentFeatureLevel,
      FDeviceContext
  );
  If Failed(Result) then Exit;

  //Get first backbuffer from the chain
  Result := FSwapchain.GetBuffer(0, ID3D11Texture2D, pBackbuffer);
  If Failed(Result) then Exit;

  //Create render target view from backbuffer
  Result := FDevice.CreateRenderTargetView(pBackbuffer, nil, FRenderTargetView);
  If Failed(Result) then Exit;

  //Release backbuffer reference
  pBackbuffer := nil;

  //Setup a depth buffer desc
  {$HINTS off}
  FillChar(depth_desc, SizeOf(depth_desc), 0);
  {$HINTS on}
  With depth_desc do Begin
    Width := aWidth;
    Height := aHeight;
    MipLevels := 1;
    ArraySize := 1;
    Format := DXGI_FORMAT_D24_UNORM_S8_UINT;
    SampleDesc.Count := 1;
    SampleDesc.Quality := 0;
    Usage := D3D11_USAGE_DEFAULT;
    BindFlags := Ord(D3D11_BIND_DEPTH_STENCIL);
    CPUAccessFlags := 0;
    MiscFlags := 0;
  End;

  //Create depth buffer
  Result := FDevice.CreateTexture2D(depth_desc, nil, FDepthStencilBuffer);
  If Failed(Result) then Exit;

  //Setup depth-stencil state desc
  {$HINTS off}
  FillChar(depth_state_desc, SizeOf(depth_state_desc), 0);
  {$HINTS on}
  With depth_state_desc do Begin
    DepthEnable := True;
    DepthWriteMask := D3D11_DEPTH_WRITE_MASK_ALL;
    DepthFunc := D3D11_COMPARISON_LESS;

    StencilEnable := True;
    StencilReadMask := $FF;
    StencilWriteMask := $FF;

    FrontFace.StencilFailOp := D3D11_STENCIL_OP_KEEP;
    FrontFace.StencilDepthFailOp := D3D11_STENCIL_OP_INCR;
    FrontFace.StencilPassOp := D3D11_STENCIL_OP_KEEP;
    FrontFace.StencilFunc := D3D11_COMPARISON_ALWAYS;

    BackFace.StencilFailOp := D3D11_STENCIL_OP_KEEP;
    BackFace.StencilDepthFailOp := D3D11_STENCIL_OP_DECR;
    BackFace.StencilPassOp := D3D11_STENCIL_OP_KEEP;
    BackFace.StencilFunc := D3D11_COMPARISON_ALWAYS;
  End;

  //Create depth-stencil state object
  Result := FDevice.CreateDepthStencilState(depth_state_desc, FDepthStencilState);
  If Failed(Result) then Exit;

  //Set depth-stencil state
  FDeviceContext.OMSetDepthStencilState(FDepthStencilState, 1);

  //Setup depth-stencil view desc
  {$HINTS off}
  FillChar(depth_view_desc, SizeOf(depth_view_desc), 0);
  {$HINTS on}
  With depth_view_desc do Begin
    Format := DXGI_FORMAT_D24_UNORM_S8_UINT;
    ViewDimension := D3D11_DSV_DIMENSION_TEXTURE2D;
    Texture2D.MipSlice := 0;
  End;

  //Create depth-stencil view
  Result := FDevice.CreateDepthStencilView(FDepthStencilBuffer, @depth_view_desc, FDepthStencilView);
  If Failed(Result) then Exit;

  //Bind render target view and depth-stencil view to pipeline
  FDeviceContext.OMSetRenderTargets(1, @FRenderTargetView, FDepthStencilView);

  //Setup rasterizer state desc
  {$HINTS off}
  FillChar(rast_state_desc, SizeOf(rast_state_desc), 0);
  {$HINTS on}
  With rast_state_desc do Begin
    AntialiasedLineEnable := True;
    CullMode := D3D11_CULL_BACK;
    DepthBias := 0;
    DepthBiasClamp := 0;
    DepthClipEnable := True;
    FillMode := D3D11_FILL_SOLID;
    FrontCounterClockwise := False;
    MultisampleEnable := False;
    ScissorEnable := False;
    SlopeScaledDepthBias := 0;
  End;

  //Create rasterizer state object
  Result := FDevice.CreateRasterizerState(rast_state_desc, FRasterizerState);
  If Failed(Result) then Exit;

  //Set rasterizer state to device context
  FDeviceContext.RSSetState(FRasterizerState);

  //Set up viewport
  {$HINTS off}
  FillChar(FViewport, SizeOf(FViewport), 0);
  {$HINTS on}
  With FViewport do Begin
    Width := aWidth;
    Height := aHeight;
    MinDepth := 0;
    MaxDepth := 1;
    TopLeftX := 0;
    TopLeftY := 0;
  End;

  //Set viewport
  FDeviceContext.RSSetViewports(1, @FViewport);

  //Initialize vertex/index buffers
  FQuad := TDXModel.CreateQuad(FDeviceContext);

  //Create projection matrix
  D3DXMatrixPerspectiveFovLH(@FProjMatrix, PI/4, aWidth/aHeight, Z_NEAR, Z_FAR);
  D3DXMatrixLookAtLH(@FViewMatrix, D3DXVector3f(0, 0, -3), D3DXVector3f(0, 0, 0), D3DXVector3f(0, 1, 0));
  D3DXMatrixIdentity(@FModelMatrix);

  //Create instance of our shader class
  FShader := TDXTextureShader.Create(
      FDevice,
      'shaders/tutorial3.vs',
      'shaders/tutorial3.ps'
  );

  //Create texture
  Result := InitializeTexture;
  If Failed(Result) then Exit;

  //Set matrices to shader
  Result := FShader.SetMatrices(FDeviceContext, FModelMatrix, FViewMatrix, FProjMatrix);
  If Failed(Result) then Exit;

  //Set texture to shader
  Result := FShader.SetTexture(FDeviceContext, FTextureSRV);
  If Failed(Result) then Exit;

  //Activate shader, so to be used by the device context when rendering
  Result := FShader.Activate(FDeviceContext);
  If Failed(Result) then Exit;

  //Set ready flag
  FReady := True;
end;

function TDXRenderer.Uninitialize: HRESULT;
begin
  If not FReady then
     Exit(E_FAIL);

  { Release vertex/index buffers }
  FQuad.Free;
  FShader.Free;

  { Release references to every interface we hold }
  FRasterizerState := nil;
  FDepthStencilState := nil;
  FDepthStencilView := nil;
  FDepthStencilBuffer := nil;

  FRenderTargetView := nil;
  FDeviceContext := nil;
  FDevice := nil;

  FSwapchain := nil;

  FTexture := nil;
  FTextureSRV := nil;

  { Clear ready flag }
  FReady := False;

  { Success }
  Result := S_OK;
end;

function TDXRenderer.InitializeTexture: HRESULT;
var
  desc: TD3D11_TEXTURE2D_DESC;
  srv_desc: TD3D11_SHADER_RESOURCE_VIEW_DESC;

  bitmap: TBitmap;
  w, h, size: integer;
  image: PBYTE;
begin
  //We will use TBitmap class to load the texture image from file
  bitmap := TBitmap.Create;

  Try
    bitmap.LoadFromFile('texture.bmp');

    w := bitmap.Width;
    h := bitmap.Height;

    Case bitmap.PixelFormat of
      pf24bit: size := w * h * 4;
      else Exit(E_FAIL);
    end;

    image := AllocMem(size);

    Try
      Convert24bppTo32bpp(bitmap, image);
    Except
      FreeMem(image);
      image := nil;
    end;
  Finally
    bitmap.Free;
  End;

  If image=nil then Begin
    Result := E_FAIL;
    Exit;
  end;

  Try
    //Populate texture2d desc
    With desc do Begin
      Width := w;
      Height := h;
      MipLevels := 0;
      ArraySize := 1;
      Format := DXGI_FORMAT_B8G8R8A8_UNORM;
      SampleDesc.Count := 1;
      SampleDesc.Quality := 0;
      Usage := D3D11_USAGE_DEFAULT;
      BindFlags := Ord(D3D11_BIND_SHADER_RESOURCE) or Ord(D3D11_BIND_RENDER_TARGET);
      CPUAccessFlags := 0;
      MiscFlags := Ord(D3D11_RESOURCE_MISC_GENERATE_MIPS);
    End;

    //Create texture
    FDevice.CreateTexture2D(desc, nil, FTexture);

    //Copy texture image from memory to video memory
    FDeviceContext.UpdateSubresource(FTexture, 0, nil, image, w*4, 0);

    //Populate shader resource view desc
    With srv_desc do Begin
      Format := desc.Format;
      ViewDimension := D3D11_SRV_DIMENSION_TEXTURE2D;
      Texture2D.MostDetailedMip := 0;
      Texture2D.MipLevels := 1;
    End;

    //Create srv
    Result := FDevice.CreateShaderResourceView(FTexture, @srv_desc, FTextureSRV);

    //Generate mipmaps
    FDeviceContext.GenerateMips(FTextureSRV);
  finally
    Freemem(image);
  end;
end;

constructor TDXRenderer.Create(aHWND: HWND; aWidth, aHeight: Integer);
begin
  Inherited Create;

  FReady := False;
  FEnableVSync := True;

  { Try to initialize Direct3D device and related resources.
    If we fail, we will emit an exception, which will automatically
    invoke the destructor and destroy the object
  }
  If Failed(Initialize(aHWND, aWidth, aHeight)) then
     Raise Exception.Create('Failed to initialize Direct3D 11!');
end;

destructor TDXRenderer.Destroy;
begin
  Uninitialize;
  Inherited;
end;

function TDXRenderer.Clear(aColor: TFloatArray4): HRESULT;
begin
  If not FReady then Begin
    Result := E_FAIL;
    Exit;
  end;

  //Clear the render target view (frame buffer)
  FDeviceContext.ClearRenderTargetView(FRenderTargetView, aColor);

  //Clear depth buffer
  FDeviceContext.ClearDepthStencilView(FDepthStencilView, Ord(D3D11_CLEAR_DEPTH), 1, 0);

  { Success }
  Result := S_OK;
end;

function TDXRenderer.Render: HRESULT;
begin
  //Check if we are initialized
  If not FReady then Begin
    Result := E_FAIL;
    Exit;
  End;

  //Render our model
  Result := FQuad.Render(FDeviceContext);
end;

function TDXRenderer.Present: HRESULT;
begin
  If not FReady then Begin
    Result := E_FAIL;
    Exit;
  End;

  If FEnableVSync then Begin
    //Enforce vertical blank refresh rate
    FSwapchain.Present(1, 0);
  end else Begin
    //Present as soon as possible
    FSwapchain.Present(0, 0);
  end;

  Result := S_OK;
end;

end.

