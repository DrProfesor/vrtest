package main

import "core:sys/win32"
import "core:strings"
import "core:fmt"
import "core:math/linalg"
import "core:math"

import dx "shared:odin-dx"
import vr "shared:odin-openvr"

logln :: dx.logln;

Vec3 :: linalg.Vector3;
Vec4 :: linalg.Vector4;
Mat4 :: linalg.Matrix4;

vr_system: ^vr.VR_IVRSystem_FnTable;
vr_compositor: ^vr.VR_IVRCompositor_FnTable;
vr_render_models: ^vr.VR_IVRRenderModels_FnTable;

swap_chain        : ^dx.IDXGISwapChain;
desc              : dx.DXGI_SWAP_CHAIN_DESC;
device            : ^dx.ID3D11Device;
ctxt              : ^dx.ID3D11DeviceContext;
render_target_view: ^dx.ID3D11RenderTargetView;

depth_stencil_view: ^dx.ID3D11DepthStencilView;
depth_stencil_buffer: ^dx.ID3D11Texture2D;

constant_buffer: ^dx.ID3D11Buffer;

VS: ^dx.ID3D11VertexShader;
PS: ^dx.ID3D11PixelShader;
VS_Buffer: ^dx.ID3D10Blob;
PS_Buffer: ^dx.ID3D10Blob;

tracked_device_poses: [vr.k_unMaxTrackedDeviceCount]vr.TrackedDevicePose_t;

main :: proc() {
	dx.g_context = context;
	window, ok := dx.create_window("Main", 1920, 1080);
	dx.main_window = window;
	
	

	// Initialize DirectX
	{
		desc.BufferDesc.Width = 1920;
	    desc.BufferDesc.Height = 1080;
	    desc.BufferDesc.RefreshRate.Numerator = 60;
	    desc.BufferDesc.RefreshRate.Denominator = 1;
	    desc.BufferDesc.Format = dx.DXGI_FORMAT_B8G8R8A8_UNORM;
	    desc.BufferDesc.ScanlineOrdering = dx.DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED;
	    desc.BufferDesc.Scaling = dx.DXGI_MODE_SCALING_UNSPECIFIED;
	    desc.SampleDesc.Count = 1;
	    desc.SampleDesc.Quality = 0;
	    desc.BufferUsage = .DXGI_USAGE_RENDER_TARGET_OUTPUT;
	    desc.BufferCount = 2;
	    desc.OutputWindow = window.platform_data.window_handle;
	    desc.Windowed = true;
	    desc.SwapEffect = dx.DXGI_SWAP_EFFECT_FLIP_DISCARD;
	    desc.Flags = dx.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;

		feature_level : dx.D3D_FEATURE_LEVEL;
		res := dx.D3D11CreateDeviceAndSwapChain(
			nil,
			dx.D3D_DRIVER_TYPE_HARDWARE, 
			dx.HMODULE(nil), 
			dx.D3D11_CREATE_DEVICE_DEBUG, // flags
			nil,
			0,
			7,
			&desc,
			&swap_chain,
			&device,
			&feature_level,
			&ctxt);

		logln("Create Device and SwapChain Response: ", res == dx.S_OK ? "OK" : "FAIL");
		logln("Initialized DirectX at Feature Level: ", feature_level);

		back_buffer: ^dx.ID3D11Texture2D;
		swap_chain.GetBuffer(swap_chain, 0, dx.IID_ID3D11Texture2D, cast(^rawptr)&back_buffer);
		device.CreateRenderTargetView(device, cast(^dx.ID3D11Resource) back_buffer, nil, &render_target_view);
		ctxt.OMSetRenderTargets(ctxt, 1, &render_target_view, nil);
	}

	// Load shaders
	{
		err: ^dx.ID3D10Blob;
		f_name := win32.utf8_to_wstring("Effects.fx\x00");
		entry_vs : cstring = "VS";
		entry_ps : cstring = "PS";
		ver_vs : cstring = "vs_4_0";
		ver_ps : cstring = "ps_4_0";
		dx.D3DCompileFromFile(f_name, nil, nil, entry_vs, ver_vs, 1, 0, &VS_Buffer, &err);
	    dx.D3DCompileFromFile(f_name, nil, nil, entry_ps, ver_ps, 1, 0, &PS_Buffer, &err);

	    device.CreateVertexShader(device, VS_Buffer.GetBufferPointer(VS_Buffer), VS_Buffer.GetBufferSize(VS_Buffer), nil, &VS);
	    device.CreatePixelShader(device, PS_Buffer.GetBufferPointer(PS_Buffer), PS_Buffer.GetBufferSize(PS_Buffer), nil, &PS);

	    ctxt.VSSetShader(ctxt, VS, nil, 0);
	    ctxt.PSSetShader(ctxt, PS, nil, 0);
	}

	// depth buffer
	{
   		depth_stencil_desc: dx.D3D11_TEXTURE2D_DESC;

	    depth_stencil_desc.Width     = 1920;
	    depth_stencil_desc.Height    = 1080;
	    depth_stencil_desc.MipLevels = 1;
	    depth_stencil_desc.ArraySize = 1;
	    depth_stencil_desc.Format    = dx.DXGI_FORMAT_D24_UNORM_S8_UINT;
	    depth_stencil_desc.SampleDesc.Count   = 1;
	    depth_stencil_desc.SampleDesc.Quality = 0;
	    depth_stencil_desc.Usage          = dx.D3D11_USAGE_DEFAULT;
	    depth_stencil_desc.BindFlags      = dx.D3D11_BIND_DEPTH_STENCIL;
	    depth_stencil_desc.CPUAccessFlags = 0; 
	    depth_stencil_desc.MiscFlags      = 0;

	    device.CreateTexture2D(device, &depth_stencil_desc, nil, &depth_stencil_buffer);
	    device.CreateDepthStencilView(device, cast(^dx.ID3D11Resource) depth_stencil_buffer, nil, &depth_stencil_view);
	}

	{
	    cbbd: dx.D3D11_BUFFER_DESC;    
	    cbbd.Usage = dx.D3D11_USAGE_DEFAULT;
	    cbbd.ByteWidth = size_of(CBObj);
	    cbbd.BindFlags = dx.D3D11_BIND_CONSTANT_BUFFER;
	    cbbd.CPUAccessFlags = 0;
	    cbbd.MiscFlags = 0;

	    device.CreateBuffer(device, &cbbd, nil, &constant_buffer);
	}

	vr_error := vr.EVRInitError_VRInitError_None;
	hmd := vr.VR_InitInternal(cast(^i32) &vr_error, vr.EVRApplicationType_VRApplication_Scene);
	if vr_error != vr.EVRInitError_VRInitError_None {
		logln("Init error: ", vr.VR_GetVRInitErrorAsEnglishDescription(cast(i32)vr_error));
		return;
	}

	vr_system = cast(^vr.VR_IVRSystem_FnTable) vr.VR_GetGenericInterface(strings.clone_to_cstring(fmt.tprint("FnTable:",vr.IVRSystem_Version)), cast(^i32) &vr_error);
	if vr_error != vr.EVRInitError_VRInitError_None {
		logln("Error getting system: ", vr.VR_GetVRInitErrorAsEnglishDescription(cast(i32)vr_error));
		return;
	}

	vr_compositor = cast(^vr.VR_IVRCompositor_FnTable) vr.VR_GetGenericInterface(strings.clone_to_cstring(fmt.tprint("FnTable:",vr.IVRCompositor_Version)), cast(^i32) &vr_error);
	if vr_error != vr.EVRInitError_VRInitError_None {
		logln("Error getting compositor: ", vr.VR_GetVRInitErrorAsEnglishDescription(cast(i32)vr_error));
		return;
	}

	vr_render_models = cast(^vr.VR_IVRRenderModels_FnTable) vr.VR_GetGenericInterface(strings.clone_to_cstring(fmt.tprint("FnTable:",vr.IVRRenderModels_Version)), cast(^i32) &vr_error);
	if vr_error != vr.EVRInitError_VRInitError_None {
		logln("Error getting render models: ", vr.VR_GetVRInitErrorAsEnglishDescription(cast(i32)vr_error));
		return;
	}

	width, height: u32;
	vr_system.GetRecommendedRenderTargetSize(&width, &height);

	left_eye := create_eye(device, true, width, height);
	right_eye := create_eye(device, false, width, height);

	bounds: vr.VRTextureBounds_t;
	bounds.uMin = 0.0;
	bounds.uMax = 1.0;
	bounds.vMin = 0.0;
	bounds.vMax = 1.0;

	// viewport
	viewport: dx.D3D11_VIEWPORT;
	{
		viewport.TopLeftX = 0;
		viewport.TopLeftY = 0;
		viewport.Width = 1920;
		viewport.Height = 1080;
		viewport.MaxDepth = 1;

		ctxt.RSSetViewports(ctxt, 1, &viewport);
	}

	for {
		vr_compositor.WaitGetPoses(&tracked_device_poses[0], vr.k_unMaxTrackedDeviceCount, nil, 0);
		for nDevice in 0..16 {
			tracked_device := tracked_device_poses[nDevice];
			if tracked_device.bPoseIsValid {
				device_poses[nDevice] = convert_vr_matrix_to_odin(tracked_device.mDeviceToAbsoluteTracking);
				
				exists := false;
				for em in vr_models {
					if em.device_index == u32(nDevice) {
						exists = true;
						break;
					}
				}

				if !exists {
					model, ok := load_vr_model(cast(u32)nDevice);
					if ok do append(&vr_models, model);
				}
			}
		}

		if tracked_device_poses[vr.k_unTrackedDeviceIndex_Hmd].bPoseIsValid {
			hmd_position_matrix = linalg.matrix4_inverse(device_poses[vr.k_unTrackedDeviceIndex_Hmd]);
		}

		// TODO depth
		ctxt.OMSetRenderTargets(ctxt, 1, &left_eye.render_target, nil);
	    ctxt.ClearRenderTargetView(ctxt, left_eye.render_target, {0.1,0.5,0.8,1});
	    render_scene(left_eye.position, left_eye.projection);

	    // TODO depth
	    ctxt.OMSetRenderTargets(ctxt, 1, &right_eye.render_target, nil);
	    ctxt.ClearRenderTargetView(ctxt, right_eye.render_target, {0.1,0.5,0.8,1});
	    render_scene(right_eye.position, right_eye.projection);

		// ctxt.OMSetRenderTargets(ctxt, 1, &render_target_view, depth_stencil_view);
	 //    ctxt.ClearDepthStencilView(ctxt, depth_stencil_view, dx.D3D11_CLEAR_DEPTH | dx.D3D11_CLEAR_STENCIL, 1.0, 0);
	    ctxt.OMSetRenderTargets(ctxt, 1, &render_target_view, nil);
	    ctxt.ClearRenderTargetView(ctxt, render_target_view, {0.1,0.5,0.8,1});
	    render_scene(right_eye.position, right_eye.projection);

	    swap_chain.Present(swap_chain, 0, 0);

		left_vr_texture := vr.Texture_t{texture, vr.ETextureType_TextureType_DirectX, vr.EColorSpace_ColorSpace_Gamma};
		err := vr_compositor.Submit(vr.EVREye_Eye_Left,  &left_eye.vr_texture,  &bounds, vr.EVRSubmitFlags_Submit_Default);
		right_vr_texture := vr.Texture_t{texture, vr.ETextureType_TextureType_DirectX, vr.EColorSpace_ColorSpace_Gamma};
		err  = vr_compositor.Submit(vr.EVREye_Eye_Right, &right_eye.vr_texture, &bounds, vr.EVRSubmitFlags_Submit_Default);
		
		message: win32.Msg;
	    for win32.peek_message_a(&message, nil, 0, 0, win32.PM_REMOVE) {
	        win32.translate_message(&message);
	        win32.dispatch_message_a(&message);
	    }
	}
}

CBObj :: struct {
	vp: Mat4,
	m: Mat4,
}

vr_models : [dynamic]VR_Model;
hmd_position_matrix: linalg.Matrix4;
valid_poses := 0;
device_poses: [16]linalg.Matrix4;

render_scene :: proc(pos, proj: linalg.Matrix4) {
	for model in &vr_models {
		ctxt.IASetVertexBuffers(ctxt, 0, 1, &model.vert_buffer, &model.stride, &model.offset);
		ctxt.IASetIndexBuffer(ctxt, model.ind_buffer, dx.DXGI_FORMAT_R16_UINT, 0);
		ctxt.IASetInputLayout(ctxt, model.vert_layout);
		ctxt.IASetPrimitiveTopology(ctxt, dx.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

		ctxt.PSSetSamplers(ctxt, 0, 1, &model.sampler);
		ctxt.PSSetShaderResources(ctxt, 0, 1, &model.shader_resource);

		cbo: CBObj;
		cbo.vp = linalg.mul(linalg.mul(proj, pos),hmd_position_matrix); 
		cbo.m = device_poses[model.device_index];

	    ctxt.UpdateSubresource(ctxt, cast(^dx.ID3D11Resource) constant_buffer, 0, nil, &cbo, 0, 0);
	    ctxt.VSSetConstantBuffers(ctxt, 0, 1, &constant_buffer);

	    ctxt.DrawIndexed(ctxt, model.ind_count, 0, 0);
	}
}

controller_left_id := -1;
controller_right_id := -1;

VR_Model :: struct {
	device_name: [1024]u8,
	
	render_model: ^vr.RenderModel_t,
	render_model_texture: ^vr.RenderModel_TextureMap_t,
	
	vert_buffer: ^dx.ID3D11Buffer,
	ind_buffer: ^dx.ID3D11Buffer,
	vert_layout: ^dx.ID3D11InputLayout,
	
	shader_resource: ^dx.ID3D11ShaderResourceView,
	texture: ^dx.ID3D11Texture2D,
	sampler: ^dx.ID3D11SamplerState,
	
	role: u32,
	stride : u32,
	offset : u32,
	ind_count: u32,
	
	device_index: vr.TrackedDeviceIndex_t,
}

load_vr_model :: proc(di: vr.TrackedDeviceIndex_t) -> (VR_Model, bool) {
	device_class := vr_system.GetTrackedDeviceClass(di);
	if device_class != vr.ETrackedDeviceClass_TrackedDeviceClass_Controller do return {}, false;

	using vr_model: VR_Model;

	device_index = di;

	tp_error: vr.ETrackedPropertyError;
	rm_error: vr.EVRRenderModelError;

	vr_system.GetStringTrackedDeviceProperty(di, vr.ETrackedDeviceProperty_Prop_RenderModelName_String, &device_name[0], 1024, &tp_error);
	role = vr_system.GetInt32TrackedDeviceProperty(di, vr.ETrackedDeviceProperty_Prop_ControllerRoleHint_Int32, &tp_error);

	if role == vr.ETrackedControllerRole_TrackedControllerRole_LeftHand {
		controller_left_id = int(di);
	} else if role == vr.ETrackedControllerRole_TrackedControllerRole_RightHand {
		controller_right_id = int(di);
	}

	rm_error = vr.EVRRenderModelError_VRRenderModelError_Loading;
	for rm_error == vr.EVRRenderModelError_VRRenderModelError_Loading {
		rm_error = vr_render_models.LoadRenderModel_Async(&device_name[0], &render_model);	
	}
	
	rm_error = vr.EVRRenderModelError_VRRenderModelError_Loading;
	for rm_error == vr.EVRRenderModelError_VRRenderModelError_Loading {
		rm_error = vr_render_models.LoadTexture_Async(render_model.diffuseTextureId, &render_model_texture);	
	}

	layout := []dx.D3D11_INPUT_ELEMENT_DESC{
		{"POSITION", 0, dx.DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, dx.D3D11_INPUT_PER_VERTEX_DATA, 0},
		{"NORMAL", 0, dx.DXGI_FORMAT_R32G32B32_FLOAT, 0, 12, dx.D3D11_INPUT_PER_VERTEX_DATA, 0},
		{"TEXCOORD", 0, dx.DXGI_FORMAT_R32G32_FLOAT, 0, 20, dx.D3D11_INPUT_PER_VERTEX_DATA, 0},
	};

	vertex_buffer_desc := dx.D3D11_BUFFER_DESC {
		size_of(vr.RenderModel_Vertex_t) * render_model.unVertexCount, 
		dx.D3D11_USAGE_DEFAULT,
		dx.D3D11_BIND_VERTEX_BUFFER,
		0,
		0,
		0,
	};
	vertex_buffer_data: dx.D3D11_SUBRESOURCE_DATA;
	vertex_buffer_data.pSysMem = render_model.rVertexData;

	device.CreateBuffer(device, &vertex_buffer_desc, &vertex_buffer_data, &vert_buffer);

	stride = size_of(vr.RenderModel_Vertex_t);
	offset = 0;

	ind_count = render_model.unTriangleCount * 3;
	index_buffer_desc := dx.D3D11_BUFFER_DESC {
		size_of(u16) * ind_count, 
		dx.D3D11_USAGE_DEFAULT,
		dx.D3D11_BIND_INDEX_BUFFER,
		0,
		0,
		0,
	};

	ind_buffer_data: dx.D3D11_SUBRESOURCE_DATA;
	ind_buffer_data.pSysMem = render_model.rIndexData;

	device.CreateBuffer(device, &index_buffer_desc, &ind_buffer_data, &ind_buffer);
	device.CreateInputLayout(device, &layout[0], cast(u32) len(layout), VS_Buffer.GetBufferPointer(VS_Buffer), VS_Buffer.GetBufferSize(VS_Buffer), &vert_layout);

	texture_desc: dx.D3D11_TEXTURE2D_DESC;
	texture_desc.Width = u32(render_model_texture.unWidth);
	texture_desc.Height = u32(render_model_texture.unHeight);
	texture_desc.MipLevels = 1;
	texture_desc.ArraySize = 1;
	texture_desc.Format = dx.DXGI_FORMAT_R8G8B8A8_UNORM_SRGB;
	texture_desc.SampleDesc.Count = 1;
	texture_desc.Usage = dx.D3D11_USAGE_DEFAULT;
	texture_desc.BindFlags = dx.D3D11_BIND_SHADER_RESOURCE;
	
	texture_data: dx.D3D11_SUBRESOURCE_DATA;
	texture_data.pSysMem = render_model_texture.rubTextureMapData;
	texture_data.SysMemPitch = u32(render_model_texture.unWidth);
	
	device.CreateTexture2D(device, &texture_desc, &texture_data, &texture);

	desc := dx.D3D11_SHADER_RESOURCE_VIEW_DESC {
		dx.DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
		dx.D3D11_SRV_DIMENSION_TEXTURE2D,
		{},
	};
	desc.Texture2D = dx.D3D11_TEX2D_SRV { 0, 1 };
	device.CreateShaderResourceView(device, cast(^dx.ID3D11Resource)texture, &desc, &shader_resource);

	sampler_desc: dx.D3D11_SAMPLER_DESC;
	sampler_desc.Filter = dx.D3D11_FILTER_MIN_MAG_MIP_LINEAR;
	sampler_desc.AddressU = dx.D3D11_TEXTURE_ADDRESS_CLAMP;
	sampler_desc.AddressV = dx.D3D11_TEXTURE_ADDRESS_CLAMP;
	sampler_desc.AddressW = dx.D3D11_TEXTURE_ADDRESS_CLAMP;
	sampler_desc.MipLODBias = 0.0;
	sampler_desc.MaxAnisotropy = 1;
	sampler_desc.ComparisonFunc= dx.D3D11_COMPARISON_NEVER;
	sampler_desc.MinLOD = math.F32_MIN;
	sampler_desc.MaxLOD = math.F32_MAX;

	device.CreateSamplerState(device, &sampler_desc, &sampler);

	return vr_model, true;
}

create_eye :: proc(device: ^dx.ID3D11Device, left: bool, width, height: u32) -> Eye {
	using eye: Eye;

	is_left = left;
	projection = convert_vr_matrix_to_odin(vr_system.GetProjectionMatrix(left ? vr.EVREye_Eye_Left : vr.EVREye_Eye_Right, 0.1, 30));
	position = linalg.matrix4_inverse(convert_vr_matrix_to_odin(vr_system.GetEyeToHeadTransform(left ? vr.EVREye_Eye_Left : vr.EVREye_Eye_Right)));

	texture_desc : dx.D3D11_TEXTURE2D_DESC;
	texture_desc.Width = width;
	texture_desc.Height = height;
	texture_desc.MipLevels = 1;
	texture_desc.ArraySize = 1;
	texture_desc.Format = dx.DXGI_FORMAT_R8G8B8A8_UNORM_SRGB;
	texture_desc.SampleDesc.Count = 1;
	texture_desc.Usage = dx.D3D11_USAGE_DEFAULT;
	texture_desc.BindFlags = dx.D3D11_BIND_RENDER_TARGET | dx.D3D11_BIND_SHADER_RESOURCE;

	device.CreateTexture2D(device, &texture_desc, nil, &texture);

	render_target_dex: dx.D3D11_RENDER_TARGET_VIEW_DESC;
	render_target_dex.Format = texture_desc.Format;
	render_target_dex.ViewDimension = dx.D3D11_RTV_DIMENSION_TEXTURE2D;
	render_target_dex.Texture2D.MipSlice = 0;

	device.CreateRenderTargetView(device, cast(^dx.ID3D11Resource)texture, nil, &render_target);

	shader_resource_desc: dx.D3D11_SHADER_RESOURCE_VIEW_DESC;
	shader_resource_desc.Format = texture_desc.Format;
	shader_resource_desc.ViewDimension = dx.D3D11_SRV_DIMENSION_TEXTURE2DMS;
	shader_resource_desc.Texture2D.MostDetailedMip = 0;
	shader_resource_desc.Texture2D.MipLevels = 1;

	device.CreateShaderResourceView(device, cast(^dx.ID3D11Resource)texture, &shader_resource_desc, &shader_resource);

	return eye;
}

Eye :: struct {
	is_left: bool,
	shader_resource: ^dx.ID3D11ShaderResourceView,
	render_target: ^dx.ID3D11RenderTargetView,
	texture: ^dx.ID3D11Texture2D,

	projection: linalg.Matrix4,
	position: linalg.Matrix4,
}

convert_vr_matrix_to_odin :: proc{convert_vr_matrix_to_odin34, convert_vr_matrix_to_odin44};
convert_vr_matrix_to_odin34 :: proc(matPose: vr.HmdMatrix34_t) -> linalg.Matrix4 {
	matrixObj := linalg.Matrix4 {
		{matPose[0][0], matPose[1][0], matPose[2][0], 0.0},
		{matPose[0][1], matPose[1][1], matPose[2][1], 0.0},
		{matPose[0][2], matPose[1][2], matPose[2][2], 0.0},
		{matPose[0][3], matPose[1][3], matPose[2][3], 1.0}
	};
	return matrixObj;
}

convert_vr_matrix_to_odin44 :: proc(matPose: vr.HmdMatrix44_t) -> linalg.Matrix4 {
	matrixObj := linalg.Matrix4 {
		{matPose[0][0], matPose[1][0], matPose[2][0], matPose[3][0]},
		{matPose[0][1], matPose[1][1], matPose[2][1], matPose[3][1]},
		{matPose[0][2], matPose[1][2], matPose[2][2], matPose[3][2]},
		{matPose[0][3], matPose[1][3], matPose[2][3], matPose[3][3]}
	};
	return matrixObj;
}