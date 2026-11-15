import Shaders;

/**
	Compiled with the `hxnsl-framework` haxelib in `framework/`, whose
	extraParams.hxml registers its extension. With `HXNSL_OUT_DIR` set, every
	shader's sources are written there for the native compilers to check.
**/
class Main {
	static function check(ok:Bool, message:String) {
		if (!ok)
			throw message;
	}

	static function spirv(bytes:haxe.io.Bytes, name:String) {
		check(bytes.length > 20 && bytes.getInt32(0) == 0x07230203, '$name: the SPIR-V resource is not SPIR-V');
	}

	static function entry(layout:Array<Array<hxnsl.Layout.LayoutEntry>>, group:Int, binding:Int):hxnsl.Layout.LayoutEntry {
		var found = Lambda.find(layout[group], e -> e.binding == binding);
		check(found != null, 'no binding $binding in group $group');
		return found;
	}

	static function main() {
		frontEnd();
		render();
		textures();
		compute();
		constants();
		save();
	}

	static function frontEnd() {
		check(Tinted.WGSL.indexOf("@vertex") >= 0, "no vertex entry point in the WGSL");
		check(Tinted.WGSL.indexOf("@fragment") >= 0, "no fragment entry point in the WGSL");
		check(Tinted.PARAMS_SIZE > 0, "no uniform layout");

		check(Targets.TARGET_color == 0, 'color is target ${Targets.TARGET_color}, not 0');
		check(Targets.TARGET_velocity == 1, 'velocity is target ${Targets.TARGET_velocity}, not 1');
		check(Targets.TARGET_glow == 2, 'glow is target ${Targets.TARGET_glow}, not 2');
		var out = Targets.WGSL.substring(Targets.WGSL.indexOf("struct FragmentOutput"));
		check(out.indexOf("@location(0) color") >= 0 && out.indexOf("@location(1) velocity") >= 0 && out.indexOf("@location(2) glow") >= 0,
			"the fragment outputs are not at their declared locations");

		// The extension's global is its own block, in its own group.
		check(Exposed.FRAME_GROUP == 1, 'the frame block is in group ${Exposed.FRAME_GROUP}, not 1');
		check(Exposed.FRAME_exposure == 0, 'exposure is at ${Exposed.FRAME_exposure} in the frame block, not 0');
		check(Exposed.FRAME_SIZE >= 4, 'the frame block is ${Exposed.FRAME_SIZE} bytes');
		check(Exposed.PARAMS_GROUP == 0, 'the shader\'s own params moved to group ${Exposed.PARAMS_GROUP}');
		check(Exposed.WGSL.indexOf('@group(1) @binding(${Exposed.FRAME_BINDING})') >= 0, "the frame block is not bound at group 1");
		// The extern function prints its helper once and calls it.
		check(Exposed.WGSL.split("fn framework_luma(").length == 2, "luma's helper is not printed exactly once");
		check(Exposed.WGSL.indexOf("framework_luma(") != Exposed.WGSL.lastIndexOf("framework_luma("), "luma is never called");

		// A shader outside the family is untouched.
		check(Tinted.WGSL.indexOf("framework_luma") < 0, "luma reached a shader outside the family");
		check(Tinted.WGSL.indexOf("exposure") < 0, "exposure reached a shader outside the family");
		check(Reflect.field(Tinted, "FRAME_GROUP") == null, "the frame block reached a shader outside the family");
	}

	static function render() {
		check(Tinted.MSL.indexOf("vertex ") >= 0 && Tinted.MSL.indexOf("fragment ") >= 0, "the MSL lacks a stage");
		check(Tinted.HLSL.indexOf("SV_Position") >= 0, "the HLSL has no vertex position");
		spirv(Tinted.spirv(), "Tinted");
		check(StringTools.startsWith(Tinted.GLSL_VERTEX, "#version 300 es"), "the vertex GLSL is not GLSL ES 3.00");
		check(StringTools.startsWith(Tinted.GLSL_FRAGMENT, "#version 300 es"), "the fragment GLSL is not GLSL ES 3.00");
		check([for (e in Tinted.ENTRY_POINTS) e.stage].join(",") == "vertex,fragment", "the entry points are not a vertex and a fragment stage");

		var params = entry(Tinted.LAYOUT, Tinted.PARAMS_GROUP, Tinted.PARAMS_BINDING);
		check(params.type == "uniform", 'params is a ${params.type} binding');
		check(params.visibility == 2, 'params is visible to stages ${params.visibility}, not the fragment stage alone');
		var register = Lambda.find(Tinted.HLSL_SLOTS, b -> b.group == Tinted.PARAMS_GROUP && b.binding == Tinted.PARAMS_BINDING);
		check(register.kind == "register" && register.registerClass == "b", "params is not an HLSL constant buffer");

		// The framework's group 1 sits after the shader's own group 0.
		check(Exposed.LAYOUT.length == 2, 'Exposed has ${Exposed.LAYOUT.length} bind groups, not 2');
		check(entry(Exposed.LAYOUT, Exposed.FRAME_GROUP, Exposed.FRAME_BINDING).type == "uniform", "the frame block is not a uniform buffer");
	}

	static function textures() {
		var group = Textured.TEXTURE_image_GROUP;
		var texture = entry(Textured.LAYOUT, group, Textured.TEXTURE_image);
		check(texture.type == "texture" && texture.sampleType == "float" && texture.viewDimension == "2d", "image is not a 2D float texture");
		check(entry(Textured.LAYOUT, group, Textured.TEXTURE_image + 1).type == "sampler", "image's sampler is not the next binding");

		var fragment = Lambda.find(Textured.MSL_SLOTS, e -> e.entryPoint == "fragment");
		check(fragment != null, "no Metal slots for the fragment stage");
		function slot(binding:Int)
			return Lambda.find(fragment.resources, r -> r.group == group && r.binding == binding);
		check(slot(Textured.TEXTURE_image).kind == "texture", "image is not in Metal's texture table");
		check(slot(Textured.TEXTURE_image + 1).kind == "sampler", "image's sampler is not in Metal's sampler table");

		var glsl = Lambda.find(Textured.GLSL_BINDINGS, g -> g.entryPoint == "fragment");
		check(glsl.textures.length == 1, 'the fragment GLSL has ${glsl.textures.length} combined samplers, not 1');
		var combined = glsl.textures[0];
		check(combined.group == group && combined.binding == Textured.TEXTURE_image, "the combined sampler is not image");
		check(Textured.GLSL_FRAGMENT.indexOf(combined.name) >= 0, 'the fragment GLSL never names ${combined.name}');
	}

	static function compute() {
		check(Tripled.ENTRY_POINTS.length == 1 && Tripled.ENTRY_POINTS[0].stage == "compute", "Tripled is not one compute stage");
		check(Tripled.ENTRY_POINTS[0].workgroup.join(",") == "16,1,1", 'the workgroup is ${Tripled.ENTRY_POINTS[0].workgroup}');
		var data = entry(Tripled.LAYOUT, Tripled.BUFFER_data_GROUP, Tripled.BUFFER_data);
		check(data.type == "storage" && data.visibility == 4, "data is not a writable storage buffer for the compute stage");
		check(Tripled.MSL.indexOf("kernel void") >= 0, "the MSL has no kernel");
		var uav = Lambda.find(Tripled.HLSL_SLOTS, b -> b.binding == Tripled.BUFFER_data);
		check(uav.registerClass == "u", "data is not an HLSL unordered access view");
		spirv(Tripled.spirv(), "Tripled");
		// WebGL2 has no compute stage, so the class has no GLSL and says why.
		check(Tripled.GLSL_MISSING.length > 0, "no reason given for the missing GLSL");
		check(Reflect.field(Tripled, "GLSL_FRAGMENT") == null, "a compute shader has GLSL");
	}

	static function constants() {
		check(Fogged.CONST_fog == "fog", 'fog is pipeline constant ${Fogged.CONST_fog}');
		// WebGPU sets it when it makes the pipeline; every other target was written with it.
		check(Fogged.WGSL.indexOf("override fog: bool;") >= 0, "the WGSL does not leave fog to the pipeline");
		check(Fogged.MSL.indexOf("fog = true") >= 0, "the MSL is not written with fog set");
	}

	static function save() {
		#if sys
		var dir = Sys.getEnv("HXNSL_OUT_DIR");
		if (dir == null)
			return;
		sys.FileSystem.createDirectory(dir);
		function write(name:String, wgsl:String, msl:String, hlsl:String, spv:haxe.io.Bytes) {
			sys.io.File.saveContent('$dir/$name.wgsl', wgsl);
			sys.io.File.saveContent('$dir/$name.metal', msl);
			sys.io.File.saveContent('$dir/$name.hlsl', hlsl);
			sys.io.File.saveBytes('$dir/$name.spv', spv);
		}
		write("Tinted", Tinted.WGSL, Tinted.MSL, Tinted.HLSL, Tinted.spirv());
		write("Textured", Textured.WGSL, Textured.MSL, Textured.HLSL, Textured.spirv());
		write("Targets", Targets.WGSL, Targets.MSL, Targets.HLSL, Targets.spirv());
		write("Exposed", Exposed.WGSL, Exposed.MSL, Exposed.HLSL, Exposed.spirv());
		write("Tripled", Tripled.WGSL, Tripled.MSL, Tripled.HLSL, Tripled.spirv());
		write("Fogged", Fogged.WGSL, Fogged.MSL, Fogged.HLSL, Fogged.spirv());
		for (g in [["Tinted", Tinted.GLSL_VERTEX, Tinted.GLSL_FRAGMENT], ["Textured", Textured.GLSL_VERTEX, Textured.GLSL_FRAGMENT],
			["Fogged", Fogged.GLSL_VERTEX, Fogged.GLSL_FRAGMENT]
		]) {
			sys.io.File.saveContent('$dir/${g[0]}.vert', g[1]);
			sys.io.File.saveContent('$dir/${g[0]}.frag', g[2]);
		}
		#end
	}
}
