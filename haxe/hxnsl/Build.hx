package hxnsl;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

class Build {
	/** The targets `-D hxnsl_targets=msl,hlsl,spirv,glsl` names; all four by default. **/
	static function targets():Array<String> {
		var all = ["msl", "hlsl", "spirv", "glsl"];
		var named = Context.definedValue("hxnsl_targets");
		if (named == null || named == "" || named == "1")
			return all;
		var chosen = [for (t in named.split(",")) StringTools.trim(t)];
		for (t in chosen)
			if (all.indexOf(t) < 0)
				Context.fatalError('hxnsl_targets names $t; the targets are ${all.join(", ")}', Context.currentPos());
		return chosen;
	}

	/** The source of the shader class `path`, for `@:import` and `@:extends`. **/
	static function source(path:String):Ast.Expr {
		switch (Context.follow(Context.getType(path))) {
			case TInst(c, _):
				for (m in c.get().meta.get())
					if (m.name == ":src")
						return new MacroParser().parseExpr(m.params[0]);
			default:
		}
		throw '$path is not an hxnsl shader';
	}

	/**
		The value `@:constants({name: value})` gives each `@const`, as the
		tool's `key=value`: the native targets are written with every
		pipeline constant fixed.
	**/
	static function constants(local:haxe.macro.Type.ClassType, overrides:Array<{name:String, key:String}>):Array<String> {
		var given = new Map<String, {value:String, pos:Position}>();
		for (m in local.meta.extract(":constants")) {
			var fields = switch (m.params) {
				case [{expr: EObjectDecl(f)}]: f;
				default: Context.fatalError("@:constants takes one object: @:constants({fog: true, lights: 4})", m.pos);
			}
			for (f in fields) {
				var value = switch (f.expr.expr) {
					case EConst(CInt(v)) | EConst(CFloat(v)): v;
					case EUnop(OpNeg, false, {expr: EConst(CInt(v)) | EConst(CFloat(v))}): '-$v';
					case EConst(CIdent(b = "true" | "false")): b;
					default: Context.fatalError('${f.field}: a constant is a number or a boolean', f.expr.pos);
				}
				if (!Lambda.exists(overrides, o -> o.name == f.field))
					Context.fatalError('${f.field} is not a @const of this shader; it has ${[for (o in overrides) o.name].join(", ")}', f.expr.pos);
				given.set(f.field, {value: value, pos: f.expr.pos});
			}
		}
		var missing = [for (o in overrides) if (!given.exists(o.name)) o.name];
		if (missing.length > 0)
			Context.fatalError('the native targets need a value for each @const: give ${missing.join(", ")} in @:constants({...}), or define hxnsl_wgsl_only',
				local.pos);
		return [for (o in overrides) '${o.key}=${given.get(o.name).value}'];
	}

	/** Adds each target's source, the layout, entry points and the targets' binding slots. **/
	static function native(fields:Array<Field>, local:haxe.macro.Type.ClassType, wgsl:String, overrides:Array<{name:String, key:String}>, pos:Position) {
		var name = local.pack.concat([local.name]).join(".");
		var tool = Tool.find();
		if (tool == null)
			Context.fatalError("hxnsl: no hxnsl tool to compile shaders with: set HXNSL_TOOL to its path, or define hxnsl_wgsl_only to emit WGSL alone",
				pos);
		var translated = Tool.translate(name, wgsl, constants(local, overrides), tool, pos);
		var out = translated.json;
		function add(name:String, type:ComplexType, value:Expr, doc:String)
			fields.push({
				name: name,
				doc: doc,
				access: [APublic, AStatic, AFinal],
				kind: FVar(type, value),
				pos: pos
			});

		var groups:Array<{group:Int, entries:Array<Dynamic>}> = out.groups;
		var last = -1;
		for (g in groups)
			if (g.group > last)
				last = g.group;
		// A group the shader leaves out still takes its place, empty.
		var layout = [
			for (i in 0...last + 1) {
				var found = Lambda.find(groups, g -> g.group == i);
				found == null ? [] : found.entries;
			}
		];
		add("LAYOUT", macro :Array<Array<hxnsl.Layout.LayoutEntry>>, Context.makeExpr(layout, pos),
			"Each bind group's bindings, with the stages that use them.");
		add("ENTRY_POINTS", macro :Array<hxnsl.Layout.EntryPoint>, Context.makeExpr(out.entryPoints, pos), "The shader's entry points.");

		var wanted = targets();
		if (wanted.indexOf("msl") >= 0) {
			add("MSL", null, macro $v{(out.msl : String)}, "The shader as Metal Shading Language 2.1.");
			add("MSL_SLOTS", macro :Array<hxnsl.Layout.MslEntry>, Context.makeExpr(out.native.msl, pos),
				"Each entry point's Metal argument indices for the layout's bindings.");
		}
		if (wanted.indexOf("hlsl") >= 0) {
			add("HLSL", null, macro $v{(out.hlsl : String)}, "The shader as HLSL, shader model 5.1.");
			add("HLSL_SLOTS", macro :Array<hxnsl.Layout.HlslBinding>, Context.makeExpr(out.native.hlsl, pos),
				"Each binding's HLSL register, or its sampler index.");
		}
		if (wanted.indexOf("spirv") >= 0) {
			var resource = 'hxnsl/$name.spv';
			Context.addResource(resource, translated.spirv);
			fields.push({
				name: "spirv",
				doc: "The shader as SPIR-V 1.0. The descriptor set is the group, and the binding the binding.",
				access: [APublic, AStatic],
				kind: FFun({args: [], ret: macro :haxe.io.Bytes, expr: macro return haxe.Resource.getBytes($v{resource})}),
				pos: pos
			});
		}
		if (wanted.indexOf("glsl") >= 0) {
			var missing:Null<String> = out.glslMissing;
			if (missing != null)
				add("GLSL_MISSING", null, macro $v{missing}, "Why WebGL2 cannot run this shader, which has no GLSL.");
			else {
				for (g in (out.glsl : Array<{entryPoint:String, stage:String, source:String}>))
					add('GLSL_${g.stage.toUpperCase()}', null, macro $v{g.source}, 'The ${g.stage} stage as GLSL ES 3.00, for WebGL2.');
				add("GLSL_BINDINGS", macro :Array<hxnsl.Layout.GlslBindings>, Context.makeExpr(out.native.glsl, pos),
					"What each GLSL stage binds by name: its combined samplers and uniform blocks.");
			}
		}
	}

	public static function shader():Array<Field> {
		var fields = Context.getBuildFields();
		var src = Lambda.find(fields, f -> f.name == "SRC");
		// A framework's shader interface or base class has no source of its own.
		if (src == null || Context.getLocalClass().get().isInterface)
			return fields;
		var expr = switch (src.kind) {
			case FVar(_, e) if (e != null): e;
			default: Context.error("SRC is the shader's source", src.pos);
		}
		var local = Context.getLocalClass().get();
		local.meta.add(":src", [expr], expr.pos);
		fields.remove(src);
		var exts = Extensions.of(local);
		var preludes = [for (x in exts) x.prelude()].filter(p -> p != null);
		var full = preludes.length == 0 ? expr : {expr: EBlock(preludes.concat([expr])), pos: expr.pos};
		try {
			var compiled = Compiler.compile(local.name, full, source, (msg, pos) -> Context.warning(msg, pos), exts);
			// Only helpers: a module other shaders import, with nothing to print.
			if (compiled == null)
				return fields;
			var wgsl = compiled.wgsl;
			var pos = expr.pos;
			function constant(name:String, value:Expr, doc:String)
				fields.push({
					name: name,
					doc: doc,
					// Final rather than inline: other languages read the field at run time.
					access: [APublic, AStatic, AFinal],
					kind: FVar(null, value),
					pos: pos
				});
			constant("WGSL", macro $v{wgsl}, "The shader as WGSL, for WebGPU.");
			var l = compiled.layout;
			for (b in l.blocks) {
				var B = b.name.toUpperCase();
				constant('${B}_SIZE', macro $v{b.size}, 'Bytes of the `${b.name}` uniform buffer.');
				constant('${B}_GROUP', macro $v{b.group}, 'Bind group of the `${b.name}` uniform buffer.');
				constant('${B}_BINDING', macro $v{b.binding}, 'Binding of the `${b.name}` uniform buffer.');
				for (m in b.members)
					constant('${B}_${m.name}', macro $v{m.offset}, 'Byte offset of `${m.name}` in the `${b.name}` uniform buffer.');
			}
			for (t in l.textures) {
				constant('TEXTURE_${t.name}', macro $v{t.binding}, 'Binding of `${t.name}`; its sampler is the next binding.');
				constant('TEXTURE_${t.name}_GROUP', macro $v{t.group}, 'Bind group of `${t.name}` and its sampler.');
			}
			for (b in l.buffers) {
				constant('BUFFER_${b.name}', macro $v{b.binding}, 'Binding of `${b.name}`.');
				constant('BUFFER_${b.name}_GROUP', macro $v{b.group}, 'Bind group of `${b.name}`.');
			}
			for (i in l.inputs)
				constant('INPUT_${i.name}', macro $v{i.location}, 'Vertex attribute location of `${i.name}`.');
			for (t in l.targets)
				constant('TARGET_${t.name}', macro $v{t.location}, 'Color target of `${t.name}`.');
			for (o in l.overrides)
				constant('CONST_${o.name}', macro $v{o.key}, 'Pipeline constant key of `@const ${o.name}`.');
			// Every other target's source is written here, so the program compiles no shader.
			if (!Context.defined("hxnsl_wgsl_only"))
				native(fields, local, wgsl, l.overrides, pos);
		} catch (e:Ast.Error) {
			Context.error(e.msg, e.pos);
		}
		return fields;
	}
}
#end
