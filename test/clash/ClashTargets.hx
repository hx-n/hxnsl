#if macro
/** Adds `MSL`, which the built-in msl target also adds. **/
class Twin extends hxnsl.Target {
	public function new() {
		super("twin");
	}

	override public function build(s:hxnsl.Compiled):Array<haxe.macro.Expr.Field> {
		return [s.field("MSL", null, macro "", "A second MSL.")];
	}
}

class ClashTargets {
	public static function register() {
		hxnsl.Targets.register(new hxnsl.targets.Msl(), "Clash");
		hxnsl.Targets.register(new Twin(), "Clash");
	}
}
#end
