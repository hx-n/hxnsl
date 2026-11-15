package hxnsl;

#if macro
import haxe.macro.Expr;

/**
	What consumes a compiled shader for a GPU driver, adding the fields its
	run time reads. Subclass it, override `build`, and register it
	from the driver's init macro with `Targets.register`. An `Extension`
	changes the language; a target takes what it compiles to.
**/
class Target {
	/** Unique among one shader's targets; it prefixes the target's resources and errors. **/
	public final name:String;

	public function new(name:String) {
		this.name = name;
	}

	/** The fields this target adds to one shader class. **/
	public function build(shader:Compiled):Array<Field> {
		return [];
	}
}
#end
