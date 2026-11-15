package hxnsl.targets;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/** `MSL` and `MSL_SLOTS`. **/
class Msl extends hxnsl.Target {
	public function new() {
		super("msl");
	}

	override public function build(s:hxnsl.Compiled):Array<Field> {
		return [
			s.field("MSL", null, macro $v{s.msl}, "The shader as Metal Shading Language 2.1."),
			s.field("MSL_SLOTS", macro :Array<hxnsl.Layout.MslEntry>, Context.makeExpr(s.native.msl, s.pos),
				"Each entry point's Metal argument indices for the layout's bindings.")
		];
	}
}
#end
