/** Fails to compile: the native targets need a value for `fog`. **/
class Unset implements hxnsl.Shader {
	static var SRC = {
		var output : { position : Vec4, color : Vec4 };
		@const var fog : Bool;

		function vertex() {
			output.position = vec4(0, 0, 0, 1);
		}

		function fragment() {
			output.color = vec4(1, 1, 1, 1);
			if (fog)
				output.color = vec4(0, 0, 0, 1);
		}
	};

	static function main() {}
}
