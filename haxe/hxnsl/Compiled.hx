package hxnsl;

#if macro
import haxe.io.Bytes;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.ClassType;
import sys.FileSystem;
import sys.io.File;

/** One compiled shader, as a `Target` sees it. **/
@:allow(hxnsl.Build)
class Compiled {
	/** The shader class's dotted path. **/
	public final name:String;

	public final cls:ClassType;
	public final pos:Position;
	public final wgsl:String;

	/** The front end's layout: uniform blocks, textures, buffers, inputs, targets and `@const`s. **/
	public final layout:WgslOut.WgslLayout;

	/** Each `@const`, its pipeline constant key and the value `@:constants` gives it. **/
	public final constants:Array<{name:String, key:String, value:String}>;

	/** `LAYOUT`'s data: each bind group's entries, empty for a group the shader leaves out. **/
	public final groups:Array<Array<Dynamic>>;

	/** `ENTRY_POINTS`'s data. **/
	public final entryPoints:Array<Dynamic>;

	/** Metal Shading Language 2.1. **/
	public final msl:String;

	/** HLSL, shader model 5.1. **/
	public final hlsl:String;

	/** SPIR-V 1.0. **/
	public final spirv:Bytes;

	/** GLSL ES 3.00 for each vertex and fragment entry point; empty when `glslMissing` names why. **/
	public final glsl:Array<{entryPoint:String, stage:String, source:String}>;

	public final glslMissing:Null<String>;

	/** Each target's binding slots, as `hxnsl.Layout`'s types: `msl`, `hlsl` and `glsl`. **/
	public final native:{msl:Array<Dynamic>, hlsl:Array<Dynamic>, glsl:Array<Dynamic>};

	/** The target being built, which names its resources and prefixes its errors. **/
	var target:Target;

	function new(cls, pos, wgsl, layout, constants, tool:Dynamic, spirv) {
		this.cls = cls;
		this.name = cls.pack.concat([cls.name]).join(".");
		this.pos = pos;
		this.wgsl = wgsl;
		this.layout = layout;
		this.constants = constants;
		var groups:Array<{group:Int, entries:Array<Dynamic>}> = tool.groups;
		var last = -1;
		for (g in groups)
			if (g.group > last)
				last = g.group;
		this.groups = [
			for (i in 0...last + 1) {
				var found = Lambda.find(groups, g -> g.group == i);
				found == null ? [] : found.entries;
			}
		];
		this.entryPoints = tool.entryPoints;
		this.msl = tool.msl;
		this.hlsl = tool.hlsl;
		this.spirv = spirv;
		this.glsl = tool.glsl;
		this.glslMissing = tool.glslMissing;
		this.native = tool.native;
	}

	/** Fails compilation at the shader, naming the target. **/
	public function error(message:String):Dynamic {
		return Context.fatalError('$name: ${target.name}: $message', pos);
	}

	/** Adds `bytes` as the resource `hxnsl/<shader>/<target>/<suffix>`, and returns its name. **/
	public function resource(suffix:String, bytes:Bytes):String {
		var id = 'hxnsl/$name/${target.name}/$suffix';
		Context.addResource(id, bytes);
		return id;
	}

	/** A public static final field of the shader class, at the shader. **/
	public function field(name:String, type:Null<ComplexType>, value:Expr, doc:String):Field {
		return {
			name: name,
			doc: doc,
			access: [APublic, AStatic, AFinal],
			kind: FVar(type, value),
			pos: pos
		};
	}

	/**
		A build step, run once for each `key` and set of `inputs`: the inputs
		are written by name to a directory of the cache, `run` is called with
		that directory, and the files `outputs` names are read back. `key`
		carries whatever else changes the result, such as the version of the
		external compiler `run` calls.
	**/
	public function step(key:String, inputs:Map<String, Bytes>, run:String->Void, outputs:Array<String>):Map<String, Bytes> {
		var names = [for (n in inputs.keys()) n];
		names.sort(Reflect.compare);
		var hash = new StringBuf();
		hash.add('${target.name}\n$key');
		for (n in names)
			hash.add('\n$n ${haxe.crypto.Md5.make(inputs.get(n)).toHex()}');
		var dir = Tool.cache() + "/steps/" + haxe.crypto.Md5.encode(hash.toString());
		// Written last, so a step that failed partway runs again.
		var done = '$dir/.done';
		if (!FileSystem.exists(done)) {
			FileSystem.createDirectory(dir);
			for (n in names)
				File.saveBytes('$dir/$n', inputs.get(n));
			run(dir);
			var missing = [for (o in outputs) if (!FileSystem.exists('$dir/$o')) o];
			if (missing.length > 0)
				error('the build step left out ${missing.join(", ")}');
			File.saveContent(done, "");
		}
		return [for (o in outputs) o => File.getBytes('$dir/$o')];
	}
}
#end
