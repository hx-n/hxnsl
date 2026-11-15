class Tinted implements hxnsl.Shader {
	static var SRC = {
		@input var input : { position : Vec2 };
		var output : { position : Vec4, color : Vec4 };
		@param var tint : Vec4;

		function vertex() {
			output.position = vec4(input.position, 0, 1);
		}

		function fragment() {
			output.color = tint;
		}
	};
}

class Textured implements hxnsl.Shader {
	static var SRC = {
		@input var input : { position : Vec2, uv : Vec2 };
		var output : { position : Vec4, color : Vec4 };
		@param var image : Sampler2D;
		var calculatedUV : Vec2;

		function vertex() {
			calculatedUV = input.uv;
			output.position = vec4(input.position, 0, 1);
		}

		function fragment() {
			output.color = image.get(calculatedUV);
		}
	};
}

/** Outputs take their color targets in the order `output` declares them, whatever order the linker finds them in. **/
class Targets implements hxnsl.Shader {
	static var SRC = {
		@input var input : { position : Vec2 };
		var output : { position : Vec4, color : Vec4, velocity : Vec4, glow : Vec4, normal : Vec4, albedo : Vec4, emissive : Vec4 };

		function vertex() {
			output.position = vec4(input.position, 0, 1);
		}

		function fragment() {
			output.color = vec4(1, 0, 0, 1);
			output.velocity = vec4(0, 0, 0, 0);
			output.glow = vec4(0, 1, 0, 1);
			output.normal = vec4(0, 0, 1, 1);
			output.albedo = vec4(1, 1, 1, 1);
			output.emissive = vec4(0, 0, 0, 1);
		}
	};
}

/** A framework's shader: its `exposure` global and `luma` come from the framework's extension. **/
class Exposed implements FrameworkShader {
	static var SRC = {
		var output : { position : Vec4, color : Vec4 };
		@param var tint : Vec4;

		function vertex() {
			output.position = vec4(0, 0, 0, 1);
		}

		function fragment() {
			output.color = vec4(vec3(luma(tint.rgb) * exposure), 1);
		}
	};
}

class Tripled implements hxnsl.Shader {
	static var SRC = {
		@param var data : RWBuffer<Int>;

		function main() {
			setLayout(16);
			var i = computeVar.globalInvocation.x;
			data[i] = data[i] * 3 + 1;
		}
	};
}

/** Its `@const` takes the value `@:constants` gives in the native targets. **/
@:constants({fog: true})
class Fogged implements hxnsl.Shader {
	static var SRC = {
		@input var input : { position : Vec2 };
		var output : { position : Vec4, color : Vec4 };
		@const var fog : Bool;

		function vertex() {
			output.position = vec4(input.position, 0, 1);
		}

		function fragment() {
			output.color = vec4(1, 1, 1, 1);
			if (fog)
				output.color = vec4(0.25, 0.25, 0.25, 1);
		}
	};
}
