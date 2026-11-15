#if macro
/**
	A stand-in for a framework built on hxnsl: its shaders implement
	`FrameworkShader`, and its extension gives them an `exposure` global in
	its own bind group and a `luma` function. Its `Probe` target is the only
	one they get. This directory is the framework's haxelib, and its
	extraParams.hxml registers both.
**/
class Framework extends hxnsl.Extension {
	public static function register() {
		hxnsl.Extensions.register(new Framework(), "FrameworkShader");
		hxnsl.Targets.register(new Probe(), "FrameworkShader");
	}

	override function functions():Array<hxnsl.Extension.ExternFunction> {
		return [{
			name: "luma",
			variants: [{args: [{name: "c", type: TVec(3, VFloat)}], ret: TFloat}],
			print: call -> {
				call.out.helper("fn framework_luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.299, 0.587, 0.114)); }");
				'framework_luma(${call.args[0]})';
			}
		}];
	}

	override function prelude():Null<haxe.macro.Expr> {
		return macro {
			@global var exposure : Float;
		};
	}

	override function block(v:hxnsl.Ast.TVar, path:String):Null<String> {
		return v.kind == Global ? "frame" : null;
	}

	override function group(name:String):Null<Int> {
		return name == "frame" ? 1 : null;
	}
}

/** A driver's target: a compile-time step over the SPIR-V, and fields from its output. **/
class Probe extends hxnsl.Target {
	public function new() {
		super("probe");
	}

	override public function build(s:hxnsl.Compiled):Array<haxe.macro.Expr.Field> {
		var ran = false;
		var out = s.step("probe 1", ["shader.spv" => s.spirv], dir -> {
			ran = true;
			sys.io.File.saveContent('$dir/length.txt', Std.string(sys.io.File.getBytes('$dir/shader.spv').length));
		}, ["length.txt"]);
		var length = Std.parseInt(out.get("length.txt").toString());
		return [
			s.field("PROBE_SPIRV_LENGTH", null, macro $v{length}, "The SPIR-V's length, as the step read it."),
			s.field("PROBE_RAN", null, macro $v{ran}, "Whether the step ran for this shader, rather than coming from the cache.")
		];
	}
}
#end
