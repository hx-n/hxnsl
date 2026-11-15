package hxnsl;

/** One binding of a shader's bind group layout, as WebGPU's `layout: "auto"` derives it. **/
typedef LayoutEntry = {
	var binding:Int;
	/** GPUShaderStage bits: 1 vertex, 2 fragment, 4 compute. **/
	var visibility:Int;
	/** uniform, storage, read-only-storage, sampler, comparison-sampler, texture or storage-texture. **/
	var type:String;
	/** float, sint, uint or depth. **/
	var ?sampleType:String;
	/** 1d, 2d, 2d-array, cube, cube-array or 3d. **/
	var ?viewDimension:String;
	var ?multisampled:Bool;
	/** A storage texture's format as WGSL names it: `rgba8unorm`. **/
	var ?format:String;
	/** read-only, write-only or read-write. **/
	var ?access:String;
}

typedef EntryPoint = {
	var name:String;
	/** vertex, fragment or compute. **/
	var stage:String;
	var workgroup:Array<Int>;
}

/** A resource's Metal argument index in one entry point. **/
typedef MslResource = {
	var group:Int;
	var binding:Int;
	/** buffer, texture or sampler: the argument table it is in. **/
	var kind:String;
	var index:Int;
}

typedef MslEntry = {
	var entryPoint:String;
	var resources:Array<MslResource>;
	/** The buffer index of the lengths of runtime-sized arrays, when the stage has one. **/
	var sizesBuffer:Null<Int>;
}

/**
	A resource's HLSL binding. A `register` is `register(<registerClass><index>, space<space>)`.
	A `sampler-index` is `index` into the group's sampler index buffer at
	`t<group>, space255`, which selects from the sampler heap.
**/
typedef HlslBinding = {
	var group:Int;
	var binding:Int;
	var kind:String;
	var index:Int;
	/** b, t or u. **/
	var ?registerClass:String;
	var ?space:Int;
}

typedef GlslTexture = {
	/** The combined sampler's uniform name. **/
	var name:String;
	var group:Int;
	var binding:Int;
	var sampler:Null<{group:Int, binding:Int}>;
}

/** What one GLSL ES entry point binds by name. **/
typedef GlslBindings = {
	var entryPoint:String;
	var textures:Array<GlslTexture>;
	var uniformBlocks:Array<{name:String, group:Int, binding:Int}>;
}
