package hxnsl.targets;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/** `HLSL` and `HLSL_SLOTS`. **/
class Hlsl extends hxnsl.Target {
	public function new() {
		super("hlsl");
	}

	override public function build(s:hxnsl.Compiled):Array<Field> {
		return [
			s.field("HLSL", null, macro $v{s.hlsl}, "The shader as HLSL, shader model 5.1."),
			s.field("HLSL_SLOTS", macro :Array<hxnsl.Layout.HlslBinding>, Context.makeExpr(s.native.hlsl, s.pos),
				"Each binding's HLSL register, or its sampler index.")
		];
	}
}
#end
