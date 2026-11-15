# hxnsl

[![CI](https://github.com/hx-n/hxnsl/actions/workflows/ci.yml/badge.svg)](https://github.com/hx-n/hxnsl/actions/workflows/ci.yml)

Shaders for Haxe, written in [HXSL](https://heaps.io/documentation/hxsl.html),
the shader language of the Heaps game engine, and compiled during the Haxe
build to WGSL, Metal Shading Language (MSL), HLSL, SPIR-V and GLSL ES. Each
GPU API gets the shader in its own language, so nothing is translated at run
time.

## How it differs from Heaps

Heaps checks an HXSL shader when the program compiles, then links it with the
other shaders of a render pass and writes the GPU API's source while the
program runs. hxnsl checks, links and writes each shader during the build. A
shader's makeup is therefore fixed when the program compiles: one class, with
the shaders it imports or extends. hxnsl does not combine shaders at run time.

The other differences:

- Every shader class carries WGSL (WebGPU), MSL (Metal), HLSL (Direct3D 12),
  SPIR-V (Vulkan) and GLSL ES (WebGL2). No HXSL linker or translator ships in
  the program. The GPU API still compiles its own language at load time,
  unless a [target](#targets) does that in the build too.
- Uniform offsets, bind groups and per-language binding slots are generated as
  constants, so host code binds by constant instead of reflecting on the
  shader.
- The output is plain source plus layout data, with no renderer attached. Use
  it from any GPU API directly, or from a driver: a Haxe library on hxnsl that
  wraps one GPU API.
- Compute shaders work, with storage buffers and workgroup sizes, on every
  language but GLSL ES, since WebGL2 has no compute stage.
- `@const` becomes a WGSL `override` that WebGPU sets at pipeline creation. For
  the other languages, the class supplies the values.
- Frameworks (libraries whose shaders share globals and functions) can extend
  HXSL with their own functions, globals and bind groups.
- Drivers can hook their own build steps and fields into the shaders they
  handle, such as compiling MSL to a Metal library at build time.

The language is Heaps' HXSL, and the type checker is ported from Heaps. See
the [HXSL docs](https://heaps.io/documentation/hxsl.html) for the syntax.

## A shader

A shader is a class that implements `hxnsl.Shader` and declares its HXSL in
`static var SRC`:

```haxe
class Textured implements hxnsl.Shader {
	static var SRC = {
		@input var input : { position : Vec2, uv : Vec2 };
		var output : { position : Vec4, color : Vec4 };
		@param var image : Sampler2D;
		@param var tint : Vec4;
		var calculatedUV : Vec2;

		function vertex() {
			calculatedUV = input.uv;
			output.position = vec4(input.position, 0, 1);
		}

		function fragment() {
			output.color = image.get(calculatedUV) * tint;
		}
	};
}
```

```sh
haxelib install hxnsl
haxe -lib hxnsl -main Main -hl main.hl
```

hxnsl is tested with Haxe 4.3.6. A shader error is a Haxe compile error on
the shader's line. After the build, each language is a static member of the
class:

```haxe
var webgpu:String = Textured.WGSL;
var metal:String = Textured.MSL;
var direct3d:String = Textured.HLSL;
var vulkan:haxe.io.Bytes = Textured.spirv();
var webgl2:Array<String> = [Textured.GLSL_VERTEX, Textured.GLSL_FRAGMENT];
```

| Field | Holds |
|---|---|
| `WGSL` | WGSL, for WebGPU. |
| `MSL`, `MSL_SLOTS` | MSL 2.1, and each entry point's buffer, texture and sampler indices. |
| `HLSL`, `HLSL_SLOTS` | HLSL for shader model 5.1, and each binding's register or sampler index. |
| `spirv()` | SPIR-V 1.0, read from a Haxe resource. Its descriptor set numbers are the bind group numbers, and its binding numbers are the WGSL bindings. |
| `GLSL_VERTEX`, `GLSL_FRAGMENT`, `GLSL_BINDINGS` | GLSL ES 3.00 for WebGL2, and the uniform names each stage binds its textures and uniform buffers by. |
| `GLSL_MISSING` | Only when WebGL2 cannot run the shader (a compute shader, or one with storage buffers): a string saying why. The GLSL fields are then absent. |
| `LAYOUT` | Each bind group's bindings, with the stages that use them, as WebGPU's `layout: "auto"` derives them. A bind group number the shader skips is an empty array. |
| `ENTRY_POINTS` | Each entry point's name, stage and workgroup size. The names are `vertex_main`, `fragment_main` and `compute_main`, and every language keeps them. |
| `PARAMS_SIZE`, `PARAMS_<name>` | The uniform buffer that holds the `@param` values: its size, and each value's offset, in bytes. |
| `PARAMS_GROUP`, `PARAMS_BINDING` | That buffer's bind group and binding. |
| `TEXTURE_<name>`, `TEXTURE_<name>_GROUP` | A texture's binding and bind group. Its sampler has the next binding. |
| `BUFFER_<name>`, `BUFFER_<name>_GROUP` | A storage buffer's binding and bind group. |
| `INPUT_<name>`, `TARGET_<name>` | A vertex input's location, and an `output` field's color target. |
| `CONST_<name>` | A `@const`'s pipeline constant key, a string. |

`hxnsl.Layout` (`haxe/hxnsl/Layout.hx`) defines the types of `LAYOUT`,
`ENTRY_POINTS` and the slot fields.

## Layout as constants

With the offsets, host code writes the uniform buffer, and with the slots it
finds where each language reads a resource:

```haxe
var params = haxe.io.Bytes.alloc(Textured.PARAMS_SIZE);
for (i in 0...4)
	params.setFloat(Textured.PARAMS_tint + i * 4, 1.0);

// Where Metal's fragment stage reads `image`.
var fragment = Lambda.find(Textured.MSL_SLOTS, e -> e.entryPoint == "fragment_main");
var image = Lambda.find(fragment.resources,
	r -> r.group == Textured.TEXTURE_image_GROUP && r.binding == Textured.TEXTURE_image);
trace(image.kind, image.index); // texture, 0: index 0 of Metal's texture table
```

Slot numbering comes from [russl](https://github.com/project-blinc/russl),
the compiler behind hxnsl's tool. russl documents it per language and keeps it
stable within a minor version; hxnsl uses russl 0.3.2.

## Compute shaders

```haxe
class Tripled implements hxnsl.Shader {
	static var SRC = {
		@param var data : RWBuffer<Int>;

		function main() {
			setLayout(16); // the workgroup size
			var i = computeVar.globalInvocation.x;
			data[i] = data[i] * 3 + 1;
		}
	};
}
```

`Tripled.ENTRY_POINTS[0].workgroup` is `[16, 1, 1]`, and `data` is a
read-write storage buffer at binding `Tripled.BUFFER_data` of bind group
`Tripled.BUFFER_data_GROUP`. The class has `GLSL_MISSING` and no GLSL.

## Pipeline constants

WebGPU sets a WGSL `override` when it creates the pipeline. MSL, HLSL, SPIR-V
and GLSL ES are written with each one fixed, and an HXSL `@const` has no
default, so the class gives the values with `@:constants`:

```haxe
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
```

`Fogged.WGSL` declares `override fog: bool;`, and a WebGPU program passes its
value under the key `Fogged.CONST_fog` when it creates the pipeline.
`Fogged.MSL` declares `constant bool fog = true;`. The
build fails if a `@const` has no value, unless `-D hxnsl_wgsl_only` leaves
WGSL as the only language.

## Framework extensions

A framework's shaders implement an interface of its own that extends
`hxnsl.Shader`. Its extension subclasses `hxnsl.Extension`, and registers
itself for that interface, its family of shaders, from an init macro:

```haxe
interface FrameworkShader extends hxnsl.Shader {}
```

```haxe
class Framework extends hxnsl.Extension {
	public static function register() {
		hxnsl.Extensions.register(new Framework(), "FrameworkShader");
	}

	// Every FrameworkShader can read `exposure`, a value the framework sets.
	override function prelude() {
		return macro {
			@global var exposure : Float;
		};
	}

	// Globals go in a uniform buffer named `frame`; null leaves a value in `params`.
	override function block(v:hxnsl.Ast.TVar, path:String) {
		return v.kind == Global ? "frame" : null;
	}

	// `frame` goes in bind group 1; null leaves a buffer in group 0.
	override function group(name:String) {
		return name == "frame" ? 1 : null;
	}
}
```

The framework's haxelib runs the init macro from its `extraParams.hxml`, so a
program that adds the haxelib gets the extension:

```
--macro Framework.register()
```

`Extension` has more hooks: `functions` adds functions with their own WGSL,
`transform` runs a pass over each checked shader, and `output` gives an
`output` field a role other than a color target. `haxe/hxnsl/Extension.hx`
documents each. Shaders that do not implement `FrameworkShader` do not get
the extension.

## Targets

A target turns the compiled shader into fields of its class. hxnsl's own
targets are `hxnsl.targets.Msl`, `Hlsl`, `Spirv` and `Glsl`, named `msl`,
`hlsl`, `spirv` and `glsl`. `WGSL`, the layout constants, `LAYOUT` and
`ENTRY_POINTS` come with every shader whatever its targets, except under
`-D hxnsl_wgsl_only`.

A driver registers targets for its family of shaders, an interface extending
`hxnsl.Shader` as with extensions. Those shaders then get the driver's targets
and none of hxnsl's. This target compiles the MSL into a Metal library during
the build:

```haxe
class MetalLibrary extends hxnsl.Target {
	public function new() {
		super("metallib"); // the name -D hxnsl_targets and errors use
	}

	override public function build(s:hxnsl.Compiled) {
		// Runs again only when the key, "metal 2.1", or the inputs change.
		var out = s.step("metal 2.1", ["shader.metal" => haxe.io.Bytes.ofString(s.msl)], dir -> {
			Sys.command("xcrun", ["-sdk", "macosx", "metal", "-std=macos-metal2.1", "-c", '$dir/shader.metal', "-o", '$dir/shader.air']);
			Sys.command("xcrun", ["-sdk", "macosx", "metallib", '$dir/shader.air', "-o", '$dir/shader.metallib']);
		}, ["shader.metallib"]);
		var resource = s.resource("shader.metallib", out.get("shader.metallib"));
		return [s.field("METALLIB", null, macro $v{resource}, "The resource holding the Metal library.")];
	}
}
```

It runs `xcrun`, so it builds on macOS only. Elsewhere the step writes no
library and the build fails. The driver's init macro registers it. Registering hxnsl's `msl` target as well
keeps `MSL` and `MSL_SLOTS` on those shaders:

```haxe
hxnsl.Targets.register(new MetalLibrary(), "MetalShader");
hxnsl.Targets.register(new hxnsl.targets.Msl(), "MetalShader");
```

`hxnsl.Compiled` (`haxe/hxnsl/Compiled.hx`) is what `build` receives: `wgsl`,
`msl`, `hlsl`, `spirv` and `glsl`, the layout, the slots and the `@const`
values, and `step`, `resource` and `field`. A step that does not write each of
its outputs fails the build, as do two targets that add the same field.

## Defines

- `-D hxnsl_targets=msl,spirv` gives these targets to shaders that no driver
  has registered targets for. It takes hxnsl's target names and registered
  ones. Without it, those shaders get all four of hxnsl's.
- `-D hxnsl_wgsl_only` skips the tool and every target. Shaders get `WGSL` and
  the `PARAMS_`, `TEXTURE_`, `BUFFER_`, `INPUT_`, `TARGET_` and `CONST_`
  constants, but no `LAYOUT` or `ENTRY_POINTS`. It suits a WebGPU-only
  program.

## The tool

The build compiles each shader's WGSL to the other languages with the
`hxnsl` command-line tool, which runs russl's compiler. The haxelib ships it
prebuilt for macOS on Apple silicon and Intel, Linux on x86-64 and ARM64, and
Windows on x86-64.

The build runs the tool at the path in the `HXNSL_TOOL` environment variable,
else the haxelib's `bin/<host>/hxnsl`, else `target/release` or
`target/debug` in a clone of this repository. On another host, build it with
`cargo build --release` and point `HXNSL_TOOL` at it.

Tool results and target build steps are cached in the directory named by the
`HXNSL_CACHE` environment variable, or in `hxnsl` under the system's temporary
directory. Deleting it clears the cache.

## Tests

From a clone of this repository, with Rust and Haxe:

```sh
cargo build
haxelib dev hxnsl .
haxelib dev hxnsl-framework test/framework
haxe -lib hxnsl-framework -cp test --interp -main Main
```

`test/framework` is a stand-in framework with an extension and a target.
`Main` throws at the first check that fails and prints nothing when all pass.
`cargo test` tests the tool. The tool validates each shader's WGSL with Naga,
and CI puts the other languages through their own compilers: spirv-val,
glslangValidator, DXC and Apple's Metal compiler. CI builds the test shaders
for the Haxe interpreter and for JavaScript.

## Agent skill

[`skills/hxnsl/SKILL.md`](https://github.com/hx-n/hxnsl/blob/main/skills/hxnsl/SKILL.md) describes the library for coding
agents. The haxelib includes it.

## License

MIT. The HXSL front end is adapted from Heaps, whose license is
[`haxe/hxnsl/LICENSE.heaps`](haxe/hxnsl/LICENSE.heaps).
