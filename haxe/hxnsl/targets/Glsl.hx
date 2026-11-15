package hxnsl.targets;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/** `GLSL_VERTEX`, `GLSL_FRAGMENT` and `GLSL_BINDINGS`, or `GLSL_MISSING`. **/
class Glsl extends hxnsl.Target {
	public function new() {
		super("glsl");
	}

	override public function build(s:hxnsl.Compiled):Array<Field> {
		if (s.glslMissing != null)
			return [s.field("GLSL_MISSING", null, macro $v{s.glslMissing}, "Why WebGL2 cannot run this shader, which has no GLSL.")];
		var fields = [
			for (g in s.glsl)
				s.field('GLSL_${g.stage.toUpperCase()}', null, macro $v{g.source}, 'The ${g.stage} stage as GLSL ES 3.00, for WebGL2.')
		];
		fields.push(s.field("GLSL_BINDINGS", macro :Array<hxnsl.Layout.GlslBindings>, Context.makeExpr(s.native.glsl, s.pos),
			"What each GLSL stage binds by name: its combined samplers and uniform blocks."));
		return fields;
	}
}
#end
