# hxnsl

[![CI](https://github.com/hx-n/hxnsl/actions/workflows/ci.yml/badge.svg)](https://github.com/hx-n/hxnsl/actions/workflows/ci.yml)

Shaders for Haxe, written in HXSL (the shader language of
[Heaps](https://heaps.io)) and compiled during the Haxe build to WGSL, Metal
Shading Language, HLSL, SPIR-V and GLSL ES. A program receives each GPU API's
own shader source and runs no shader compiler.

A build macro checks the shader against its Haxe source and writes it as WGSL.
The `hxnsl` tool, which ships prebuilt in the haxelib for each host, then
compiles the WGSL for the other targets with
[russl](https://github.com/project-blinc/russl)'s compiler.

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

```
haxelib install hxnsl
haxe -lib hxnsl ...
```

## Fields of a shader class

| Field | |
|---|---|
| `WGSL` | The shader as WGSL, for WebGPU. |
| `MSL`, `MSL_SLOTS` | Metal Shading Language 2.1, and each entry point's buffer, texture and sampler indices. |
| `HLSL`, `HLSL_SLOTS` | HLSL for shader model 5.1, and each binding's register or sampler index. |
| `spirv()` | SPIR-V 1.0, from a resource. The descriptor set is the group and the binding is the binding. |
| `GLSL_VERTEX`, `GLSL_FRAGMENT`, `GLSL_BINDINGS` | GLSL ES 3.00 for WebGL2, and the names each stage binds. |
| `GLSL_MISSING` | In place of the GLSL fields, when WebGL2 cannot run the shader: a compute shader, or one with storage buffers. |
| `LAYOUT` | Each bind group's bindings, with the stages that use them, as WebGPU's `layout: "auto"` derives them. A group the shader leaves out is an empty array. |
| `ENTRY_POINTS` | Each entry point's name, stage and workgroup size. |
| `PARAMS_SIZE`, `PARAMS_<name>`, `TEXTURE_<name>`, `BUFFER_<name>`, `INPUT_<name>`, `TARGET_<name>`, `CONST_<name>` | The uniform block's size and member offsets, and the bindings, vertex locations, color targets and pipeline constant keys of the shader's variables. |

`hxnsl.Layout` defines the types of `LAYOUT`, `ENTRY_POINTS` and the slot
fields. The slots follow the binding model russl documents for each target,
which russl keeps within a minor version.

## Pipeline constants

A `@const` variable is a WGSL `override`, which WebGPU sets when it creates the
pipeline. The other targets have no such step, so the shader is written for
them with each constant fixed, and the class gives the values:

```haxe
@:constants({fog: true})
class Fogged implements hxnsl.Shader {
	static var SRC = {
		@const var fog : Bool;
		...
	};
}
```

The build fails if a `@const` has no value here.

## Defines

- `-D hxnsl_targets=msl,spirv` keeps those targets' fields and leaves out the
  others, so a program carries only the sources its GPU API uses. The default
  is all four: `msl`, `hlsl`, `spirv` and `glsl`.
- `-D hxnsl_wgsl_only` writes WGSL and the layout constants alone, without
  running the tool.

## The tool

The macro runs `HXNSL_TOOL` if it is set, else the haxelib's
`bin/<host>/hxnsl`, else a build in this checkout's `target/release` or
`target/debug`. `cargo build` makes one. Results are cached by the tool's build
and the WGSL in `HXNSL_CACHE`, or under the system's temporary directory.

## Tests

```
cargo build
haxelib dev hxnsl .
haxelib dev hxnsl-framework test/framework
haxe -lib hxnsl-framework -cp test --interp -main Main
```

`cargo test` tests the tool. CI also compiles every target's output with
spirv-val, glslangValidator, DXC and Apple's Metal compiler.

## License

MIT. The HXSL front end is adapted from Heaps, whose license is
[`haxe/hxnsl/LICENSE.heaps`](haxe/hxnsl/LICENSE.heaps).
