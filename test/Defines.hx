import Shaders;

/** Run with `-D hxnsl_wgsl_only` or `-D hxnsl_targets=msl`: the class has those targets' fields alone. **/
class Defines {
	static function main() {
		#if hxnsl_wgsl_only
		var present = ["WGSL", "PARAMS_SIZE"];
		var absent = ["LAYOUT", "MSL", "HLSL", "spirv", "GLSL_VERTEX"];
		#else
		var present = ["WGSL", "LAYOUT", "ENTRY_POINTS", "MSL", "MSL_SLOTS"];
		var absent = ["HLSL", "HLSL_SLOTS", "spirv", "GLSL_VERTEX", "GLSL_BINDINGS", "GLSL_MISSING"];
		#end
		for (f in present)
			if (Reflect.field(Tinted, f) == null)
				throw 'Tinted has no $f';
		for (f in absent)
			if (Reflect.field(Tinted, f) != null)
				throw 'Tinted has $f';
	}
}
