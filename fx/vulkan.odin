package fx

import "base:runtime"
import "core:os"

import "core:mem"
import "core:dynlib"
import vk "vendor:vulkan"

MAX_INSTANCES :: 16 * mem.Megabyte / size_of(Instance)

Gpu_Buffer :: struct {
	buffer:  vk.Buffer,
	memory:  vk.DeviceMemory,
	address: vk.DeviceAddress,
	mapped:  rawptr,
}

Push_Constants :: struct #packed {
	screen_size:    [2]f32,
	instances_addr: vk.DeviceAddress,
	curves_addr:    vk.DeviceAddress,
	stripes_addr:   vk.DeviceAddress,
}

swapchain: struct {
	swapchain: vk.SwapchainKHR,
	images: []vk.Image,
	image_views: []vk.ImageView,
	present_semaphores: []vk.Semaphore,
}

vks: struct {
	surface:           vk.SurfaceKHR,
	gpu:               vk.PhysicalDevice,
	device:            vk.Device,
	queue:             vk.Queue,

	command_buffer:    vk.CommandBuffer,
	acquire_semaphore: vk.Semaphore,
	in_flight_fence:   vk.Fence,

	pipeline:          vk.Pipeline,
	pipeline_layout:   vk.PipelineLayout,

	instance_buffer:   Gpu_Buffer,
	curve_buffer:      Gpu_Buffer,
	stripe_buffer:     Gpu_Buffer,
	clear_color:       [4]f32,
}

vk_init :: proc() {
	// Load Vulkan library
	lib := dynlib.load_library("vulkan-1.dll") or_else panic("Failed to load Vulkan library")
	vkGetInstanceProcAddr := dynlib.symbol_address(lib, "vkGetInstanceProcAddr")
	vk.load_proc_addresses(vkGetInstanceProcAddr)

 	// Create Instance
	when ODIN_DEBUG {
		layer_count := u32(1)
		val_layer := cstring("VK_LAYER_KHRONOS_validation")
		layer_names := &val_layer
	} else {
		layer_count: u32
		layer_names: ^cstring
	}

	extensions: [dynamic]cstring
	append(&extensions, vk.KHR_SURFACE_EXTENSION_NAME)
	append(&extensions, vk.KHR_WIN32_SURFACE_EXTENSION_NAME)
	when ODIN_DEBUG {
		append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}

	app_info := vk.ApplicationInfo {
		sType = .APPLICATION_INFO,
		pApplicationName = "Text Editor",
		apiVersion = vk.API_VERSION_1_3,
	}

	create_info := vk.InstanceCreateInfo {
		sType = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &app_info,
		enabledExtensionCount =  u32(len(extensions)),
		ppEnabledExtensionNames = raw_data(extensions[:]),
		enabledLayerCount = layer_count,
		ppEnabledLayerNames = layer_names,
	}

	when ODIN_DEBUG {
		debug_callback :: proc "system" (
			messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
			messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
			pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
			pUserData: rawptr,
		) -> b32 {
			context = runtime.default_context()
			when ODIN_DEBUG {
				os.write_string(os.stderr, "Vulkan Validation: ")
				if pCallbackData != nil && pCallbackData.pMessage != nil {
					os.write_string(os.stderr, string(pCallbackData.pMessage))
				}
				os.write_string(os.stderr, "\n")
			}
			return false
		}

		debug_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.WARNING, .ERROR},
			messageType = {.VALIDATION, .PERFORMANCE},
			pfnUserCallback = debug_callback,
		}

		create_info.pNext = &debug_info
	}

	instance: vk.Instance
	vk.CreateInstance(&create_info, nil, &instance)
	vk.load_proc_addresses(instance)

	when ODIN_DEBUG {
		debug_messenger: vk.DebugUtilsMessengerEXT
		vk.CreateDebugUtilsMessengerEXT(instance, &debug_info, nil, &debug_messenger)
	}

 	// Create Surface
	surface_create_info := vk.Win32SurfaceCreateInfoKHR {
		sType = .WIN32_SURFACE_CREATE_INFO_KHR,
		hinstance = window.hInstance,
		hwnd = window.hwnd,
	}
	vk.CreateWin32SurfaceKHR(instance, &surface_create_info, nil, &vks.surface)

 	// Pick Physical Device
	device_count: u32
	vk.EnumeratePhysicalDevices(instance, &device_count, nil)
	devices := make([]vk.PhysicalDevice, device_count)
	defer delete(devices)
	vk.EnumeratePhysicalDevices(instance, &device_count, &devices[0])

	vks.gpu = devices[0]
	for d in devices {
		props: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(d, &props)
		if props.deviceType == .DISCRETE_GPU {
			vks.gpu = d
			break
		}
	}

 	// Create Logical Device
	queue_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(vks.gpu, &queue_count, nil)
	queue_families := make([]vk.QueueFamilyProperties, queue_count)
	defer delete(queue_families)
	vk.GetPhysicalDeviceQueueFamilyProperties(vks.gpu, &queue_count, &queue_families[0])

	queue_family_index: u32
	for queue_family, i in queue_families {
		if .GRAPHICS in queue_family.queueFlags {
			queue_family_index = u32(i)
			break
		}
	}

	queue_priority := f32(1.0)
	queue_create_info := vk.DeviceQueueCreateInfo {
		sType = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = queue_family_index,
		queueCount = 1,
		pQueuePriorities = &queue_priority,
	}

	features_13 := vk.PhysicalDeviceVulkan13Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		dynamicRendering = true,
		synchronization2 = true,
	}

	features_12 := vk.PhysicalDeviceVulkan12Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		pNext = &features_13,
		descriptorIndexing = true,
		descriptorBindingPartiallyBound = true,
		descriptorBindingSampledImageUpdateAfterBind = true,
		runtimeDescriptorArray = true,
		shaderSampledImageArrayNonUniformIndexing = true,
		bufferDeviceAddress = true,
		scalarBlockLayout = true,
	}

	features_10 := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = &features_12,
		features = {
			shaderInt64 = true,
		},
	}

	device_extensions := [?]cstring {
		vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	}

	device_create_info := vk.DeviceCreateInfo {
		sType = .DEVICE_CREATE_INFO,
		pNext = &features_10,
		queueCreateInfoCount = 1,
		pQueueCreateInfos = &queue_create_info,
		enabledExtensionCount = len(device_extensions),
		ppEnabledExtensionNames = &device_extensions[0],
	}

	vk.CreateDevice(vks.gpu, &device_create_info, nil, &vks.device)
	vk.load_proc_addresses(vks.device)
	vk.GetDeviceQueue(vks.device, queue_family_index, 0, &vks.queue)

	pool_info := vk.CommandPoolCreateInfo {
		sType = .COMMAND_POOL_CREATE_INFO,
		flags = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = queue_family_index,
	}

	command_pool: vk.CommandPool
	vk.CreateCommandPool(vks.device, &pool_info, nil, &command_pool)


 	// Sync objects
	semaphore_info := vk.SemaphoreCreateInfo { sType = .SEMAPHORE_CREATE_INFO }
	fence_info := vk.FenceCreateInfo { sType = .FENCE_CREATE_INFO, flags = {.SIGNALED} }

	alloc_info := vk.CommandBufferAllocateInfo {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		level = .PRIMARY,
		commandPool = command_pool,
		commandBufferCount = 1,
	}
	vk.AllocateCommandBuffers(vks.device, &alloc_info, &vks.command_buffer)
	vk.CreateSemaphore(vks.device, &semaphore_info, nil, &vks.acquire_semaphore)
	vk.CreateFence(vks.device, &fence_info, nil, &vks.in_flight_fence)

 	// Buffers
	vks.instance_buffer = create_buffer(MAX_INSTANCES * size_of(Instance))
	vks.curve_buffer    = create_buffer(16 * mem.Megabyte)
	vks.stripe_buffer   = create_buffer(16 * mem.Megabyte)

 	// Create Pipeline
	vert_spv := #load("../assets/shaders/shader.vert.spv", []u32)
	frag_spv := #load("../assets/shaders/shader.frag.spv", []u32)

	push_constant_range := vk.PushConstantRange {
		stageFlags = {.VERTEX, .FRAGMENT},
		offset     = 0,
		size       = size_of(Push_Constants),
	}

	pipeline_layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 0,
		pSetLayouts            = nil,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &push_constant_range,
	}

	vk.CreatePipelineLayout(vks.device, &pipeline_layout_info, nil, &vks.pipeline_layout)

	vert_module_info := vk.ShaderModuleCreateInfo {
		sType = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(vert_spv) * 4,
		pCode = raw_data(vert_spv),
	}
	vert_module: vk.ShaderModule
	vk.CreateShaderModule(vks.device, &vert_module_info, nil, &vert_module)
	defer vk.DestroyShaderModule(vks.device, vert_module, nil)

	frag_module_info := vk.ShaderModuleCreateInfo {
		sType = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(frag_spv) * 4,
		pCode = raw_data(frag_spv),
	}
	frag_module: vk.ShaderModule
	vk.CreateShaderModule(vks.device, &frag_module_info, nil, &frag_module)
	defer vk.DestroyShaderModule(vks.device, frag_module, nil)

	stages := [?]vk.PipelineShaderStageCreateInfo {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = vert_module,
			pName = "main",
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = frag_module,
			pName = "main",
		},
	}

	vertex_input := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}

	input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_STRIP,
	}

	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount = 1,
	}

	rasterization := vk.PipelineRasterizationStateCreateInfo {
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		cullMode = {},
		frontFace = .CLOCKWISE,
		lineWidth = 1.0,
	}

	multisample := vk.PipelineMultisampleStateCreateInfo {
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}

	color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		blendEnable = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
		alphaBlendOp = .ADD,
		colorWriteMask = {.R, .G, .B, .A},
	}

	color_blend := vk.PipelineColorBlendStateCreateInfo {
		sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments = &color_blend_attachment,
	}

	dynamic_states := [?]vk.DynamicState { .VIEWPORT, .SCISSOR }
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = len(dynamic_states),
		pDynamicStates = &dynamic_states[0],
	}

	color_format := vk.Format.B8G8R8A8_UNORM
	rendering_info := vk.PipelineRenderingCreateInfo {
		sType = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount = 1,
		pColorAttachmentFormats = &color_format,
	}

	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext = &rendering_info,
		stageCount = 2,
		pStages = &stages[0],
		pVertexInputState = &vertex_input,
		pInputAssemblyState = &input_assembly,
		pViewportState = &viewport_state,
		pRasterizationState = &rasterization,
		pMultisampleState = &multisample,
		pColorBlendState = &color_blend,
		pDynamicState = &dynamic_state,
		layout = vks.pipeline_layout,
	}

	vk.CreateGraphicsPipelines(vks.device, 0, 1, &pipeline_info, nil, &vks.pipeline)

	vk_recreate_swapchain()
}

vk_recreate_swapchain :: proc() {
	vk.DeviceWaitIdle(vks.device)

	if swapchain.swapchain != 0 {
		for view in swapchain.image_views {
			vk.DestroyImageView(vks.device, view, nil)
		}
		for semaphore in swapchain.present_semaphores {
			vk.DestroySemaphore(vks.device, semaphore, nil)
		}
		delete(swapchain.images)
		delete(swapchain.image_views)
		delete(swapchain.present_semaphores)
	}

	capabilities: vk.SurfaceCapabilitiesKHR
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(vks.gpu, vks.surface, &capabilities)
	extent := vk.Extent2D{u32(window.size.x), u32(window.size.y)}

	create_info := vk.SwapchainCreateInfoKHR {
		sType = .SWAPCHAIN_CREATE_INFO_KHR,
		surface = vks.surface,
		minImageCount = capabilities.minImageCount,
		imageFormat = .B8G8R8A8_UNORM,
		imageColorSpace = .SRGB_NONLINEAR,
		imageExtent = extent,
		imageArrayLayers = 1,
		imageUsage = {.COLOR_ATTACHMENT},
		imageSharingMode = .EXCLUSIVE,
		preTransform = {.IDENTITY},
		compositeAlpha = {.OPAQUE},
		presentMode = .FIFO,
		clipped = true,
		oldSwapchain = swapchain.swapchain,
	}

	new_swapchain: vk.SwapchainKHR
	vk.CreateSwapchainKHR(vks.device, &create_info, nil, &new_swapchain)

	if swapchain.swapchain != 0 {
		vk.DestroySwapchainKHR(vks.device, swapchain.swapchain, nil)
	}

	swapchain.swapchain = new_swapchain

	image_count: u32
	vk.GetSwapchainImagesKHR(vks.device, swapchain.swapchain, &image_count, nil)

	swapchain.images = make([]vk.Image, image_count)
	swapchain.image_views = make([]vk.ImageView, image_count)
	swapchain.present_semaphores = make([]vk.Semaphore, image_count)

	vk.GetSwapchainImagesKHR(vks.device, swapchain.swapchain, &image_count, raw_data(swapchain.images))

	semaphore_info := vk.SemaphoreCreateInfo { sType = .SEMAPHORE_CREATE_INFO }
	for i in 0..<image_count {
		view_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = swapchain.images[i],
			viewType = .D2,
			format = .B8G8R8A8_UNORM,
			subresourceRange = { aspectMask = {.COLOR}, levelCount = 1, layerCount = 1 },
		}
		vk.CreateImageView(vks.device, &view_info, nil, &swapchain.image_views[i])
		vk.CreateSemaphore(vks.device, &semaphore_info, nil, &swapchain.present_semaphores[i])
	}
}

vk_render :: proc() {
	vk.WaitForFences(vks.device, 1, &vks.in_flight_fence, true, max(u64))

	image_index: u32
	res := vk.AcquireNextImageKHR(
		vks.device, swapchain.swapchain, max(u64),
		vks.acquire_semaphore,
		0, &image_index,
	)

	if res == .ERROR_OUT_OF_DATE_KHR {
		vk_recreate_swapchain()
		return
	}

	vk.ResetFences(vks.device, 1, &vks.in_flight_fence)

	cmd := vks.command_buffer
	vk.ResetCommandBuffer(cmd, {})

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	vk.BeginCommandBuffer(cmd, &begin_info)

	image_barrier(
		cmd, swapchain.images[image_index],
		.UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL,
		{.TOP_OF_PIPE}, {.COLOR_ATTACHMENT_OUTPUT},
		{}, {.COLOR_ATTACHMENT_WRITE},
	)

	color_attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = swapchain.image_views[image_index],
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = vk.ClearValue { color = { float32 = vks.clear_color } },
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = { extent = {u32(window.size.x), u32(window.size.y)} },
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
	}

	vk.CmdBeginRendering(cmd, &rendering_info)

	vk.CmdBindPipeline(cmd, .GRAPHICS, vks.pipeline)

	viewport := vk.Viewport {
		x = 0, y = 0,
		width = f32(window.size.x),
		height = f32(window.size.y),
		minDepth = 0.0, maxDepth = 1.0,
	}
	vk.CmdSetViewport(cmd, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = {u32(window.size.x), u32(window.size.y)},
	}
	vk.CmdSetScissor(cmd, 0, 1, &scissor)

	pc := Push_Constants {
		screen_size    = window_size(),
		instances_addr = vks.instance_buffer.address,
		curves_addr    = vks.curve_buffer.address,
		stripes_addr   = vks.stripe_buffer.address,
	}
	vk.CmdPushConstants(cmd, vks.pipeline_layout, {.VERTEX, .FRAGMENT}, 0, size_of(pc), &pc)

	if len(instances) > 0 {
		mem.copy(vks.instance_buffer.mapped, raw_data(instances[:]), len(instances) * size_of(Instance))
		vk.CmdDraw(cmd, 4, u32(len(instances)), 0, 0)
	}

	vk.CmdEndRendering(cmd)

	image_barrier(
		cmd, swapchain.images[image_index],
		.COLOR_ATTACHMENT_OPTIMAL, .PRESENT_SRC_KHR,
		{.COLOR_ATTACHMENT_OUTPUT}, {.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_WRITE}, {},
	)
	vk.EndCommandBuffer(cmd)

	render_finished_semaphore := &swapchain.present_semaphores[image_index]
	cmd_info := vk.CommandBufferSubmitInfo {
		sType = .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer = cmd,
	}
	wait_info := vk.SemaphoreSubmitInfo {
		sType = .SEMAPHORE_SUBMIT_INFO,
		semaphore = vks.acquire_semaphore,
		stageMask = {.COLOR_ATTACHMENT_OUTPUT},
	}
	signal_info := vk.SemaphoreSubmitInfo {
		sType = .SEMAPHORE_SUBMIT_INFO,
		semaphore = render_finished_semaphore^,
		stageMask = {.COLOR_ATTACHMENT_OUTPUT},
	}
	submit_info := vk.SubmitInfo2 {
		sType = .SUBMIT_INFO_2,
		waitSemaphoreInfoCount = 1,
		pWaitSemaphoreInfos = &wait_info,
		commandBufferInfoCount = 1,
		pCommandBufferInfos = &cmd_info,
		signalSemaphoreInfoCount = 1,
		pSignalSemaphoreInfos = &signal_info,
	}
	vk.QueueSubmit2(vks.queue, 1, &submit_info, vks.in_flight_fence)

	present_info := vk.PresentInfoKHR {
		sType = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores = render_finished_semaphore,
		swapchainCount = 1,
		pSwapchains = &swapchain.swapchain,
		pImageIndices = &image_index,
	}

	present_res := vk.QueuePresentKHR(vks.queue, &present_info)
	if present_res == .ERROR_OUT_OF_DATE_KHR || present_res == .SUBOPTIMAL_KHR || res == .SUBOPTIMAL_KHR {
		vk_recreate_swapchain()
	}
}

create_buffer :: proc(size: vk.DeviceSize) -> (buf: Gpu_Buffer) {
	create_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size = size,
		usage = {.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
		sharingMode = .EXCLUSIVE,
	}
	vk.CreateBuffer(vks.device, &create_info, nil, &buf.buffer)

	mem_reqs: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(vks.device, buf.buffer, &mem_reqs)

	mem_props: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(vks.gpu, &mem_props)

	memory_type_index := max(u32)
	properties: vk.MemoryPropertyFlags = {.HOST_VISIBLE, .HOST_COHERENT}
	for i in 0..<mem_props.memoryTypeCount {
		if (mem_reqs.memoryTypeBits & (1 << i)) != 0 && (mem_props.memoryTypes[i].propertyFlags & properties) == properties {
			memory_type_index = i
			break
		}
	}

	if memory_type_index == max(u32) {
		panic("Failed to find suitable memory type!")
	}

	alloc_flags := vk.MemoryAllocateFlagsInfo {
		sType = .MEMORY_ALLOCATE_FLAGS_INFO,
		flags = {.DEVICE_ADDRESS},
	}

	alloc_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		pNext = &alloc_flags,
		allocationSize = mem_reqs.size,
		memoryTypeIndex = memory_type_index,
	}
	vk.AllocateMemory(vks.device, &alloc_info, nil, &buf.memory)
	vk.BindBufferMemory(vks.device, buf.buffer, buf.memory, 0)
	vk.MapMemory(vks.device, buf.memory, 0, vk.DeviceSize(vk.WHOLE_SIZE), {}, &buf.mapped)

	address_info := vk.BufferDeviceAddressInfo {
		sType = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = buf.buffer,
	}
	buf.address = vk.GetBufferDeviceAddress(vks.device, &address_info)
	return
}

image_barrier :: proc(
	cmd: vk.CommandBuffer, image: vk.Image,
	old_layout, new_layout: vk.ImageLayout,
	src_stage, dst_stage: vk.PipelineStageFlags2,
	src_access, dst_access: vk.AccessFlags2,
) {
	barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask = src_stage,
		srcAccessMask = src_access,
		dstStageMask = dst_stage,
		dstAccessMask = dst_access,
		oldLayout = old_layout,
		newLayout = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			layerCount = 1,
		},
	}
	dep_info := vk.DependencyInfo {
		sType = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers = &barrier,
	}
	vk.CmdPipelineBarrier2(cmd, &dep_info)
}