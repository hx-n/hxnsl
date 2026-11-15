package hxnsl.targets;

#if macro
import haxe.macro.Expr;

/** `spirv()`, reading the SPIR-V from a resource. **/
class Spirv extends hxnsl.Target {
	public function new() {
		super("spirv");
	}

	override public function build(s:hxnsl.Compiled):Array<Field> {
		var resource = s.resource("shader.spv", s.spirv);
		return [{
			name: "spirv",
			doc: "The shader as SPIR-V 1.0. The descriptor set is the group, and the binding the binding.",
			access: [APublic, AStatic],
			kind: FFun({args: [], ret: macro :haxe.io.Bytes, expr: macro return haxe.Resource.getBytes($v{resource})}),
			pos: s.pos
		}];
	}
}
#end
