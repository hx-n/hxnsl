/** Fails to build: two of its targets add `MSL`. Built with `--macro ClashTargets.register()`. **/
class Clash implements hxnsl.Shader {
	static var SRC = {
		var output : { position : Vec4, color : Vec4 };

		function vertex() {
			output.position = vec4(0, 0, 0, 1);
		}

		function fragment() {
			output.color = vec4(1, 1, 1, 1);
		}
	};

	static function main() {}
}
