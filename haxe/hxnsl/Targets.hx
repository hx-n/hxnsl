package hxnsl;

#if macro
import haxe.macro.Context;
import haxe.macro.Type.ClassType;

/** The targets registered for this compilation, and which of them a shader gets. **/
class Targets {
	static var registered:Array<{target:Target, family:Null<String>}> = [];

	/**
		Adds `target` to every shader, or with `family` to the shaders that
		implement or extend that interface or class. Call it from an init
		macro, before any shader is typed.
	**/
	public static function register(target:Target, ?family:String) {
		registered.push({target: target, family: family});
	}

	/** hxnsl's own: MSL, HLSL, SPIR-V and GLSL ES with their slots. **/
	static function builtins():Array<Target> {
		return [
			new hxnsl.targets.Msl(),
			new hxnsl.targets.Hlsl(),
			new hxnsl.targets.Spirv(),
			new hxnsl.targets.Glsl()
		];
	}

	/**
		The targets of the shader class `c`: those registered for its
		families, in the order they were registered. A shader no target is
		registered for gets the default set, `-D hxnsl_targets=` when given,
		else hxnsl's four.
	**/
	public static function of(c:ClassType):Array<Target> {
		var families = Extensions.families(c);
		var chosen:Array<Target> = [];
		for (r in registered)
			if ((r.family == null || families.exists(r.family)) && !Lambda.exists(chosen, t -> t.name == r.target.name))
				chosen.push(r.target);
		return chosen.length > 0 ? chosen : defaults();
	}

	static var named:Null<Array<Target>>;

	static function defaults():Array<Target> {
		var own = builtins();
		var value = Context.definedValue("hxnsl_targets");
		if (value == null || value == "" || value == "1")
			return own;
		if (named != null)
			return named;
		var known = own.concat([for (r in registered) r.target]);
		named = [];
		for (n in value.split(",")) {
			var name = StringTools.trim(n);
			var t = Lambda.find(known, t -> t.name == name);
			if (t == null) {
				var names = [];
				for (k in known)
					if (names.indexOf(k.name) < 0)
						names.push(k.name);
				Context.fatalError('hxnsl_targets names $name; the targets are ${names.join(", ")}', Context.currentPos());
			}
			if (!Lambda.exists(named, x -> x.name == name))
				named.push(t);
		}
		return named;
	}
}
#end
