//! An hxnsl shader's WGSL, written for every GPU target by russl_compiler, with the bind group
//! layout and each target's binding slots, for the Haxe build macro to put on the shader class.

use naga::valid::{Capabilities, GlobalUse, ModuleInfo, ValidationFlags, Validator};
use naga::{
    AddressSpace, ImageClass, ImageDimension, Module, ScalarKind, ShaderStage, StorageAccess,
    TypeInner,
};
use russl_compiler::{GlslBindings, HlslSlot, MslSlot, NativeBindings, Stage};
use serde_json::{Value, json};
use std::collections::BTreeMap;

/// What the build gets for one shader.
pub struct Output {
    /// MSL, HLSL, GLSL ES, the layout, entry points and native slots, as `shader.json` holds them.
    pub json: Value,
    /// SPIR-V, little-endian.
    pub spirv: Vec<u8>,
}

/// Compiles `wgsl` for every target, with each pipeline constant fixed: at its value in
/// `constants`, by the key naga looks it up by, else at its default. The error is Naga's or
/// russl's report.
pub fn translate(wgsl: &str, constants: &[(&str, f64)]) -> Result<Output, String> {
    let artifacts =
        russl_compiler::compile_wgsl(wgsl, constants).map_err(|e| e.message().to_string())?;
    // compile_wgsl validated the same source, so these do not fail.
    let module = naga::front::wgsl::parse_str(wgsl).map_err(|e| e.emit_to_string(wgsl))?;
    let info = Validator::new(ValidationFlags::all(), Capabilities::all())
        .validate(&module)
        .map_err(|e| e.emit_to_string(wgsl))?;
    let glsl: Vec<Value> = artifacts
        .glsl
        .iter()
        .map(|g| json!({"entryPoint": g.entry_point, "stage": stage(g.stage), "source": g.source}))
        .collect();
    let missing = artifacts.glsl_missing.or_else(|| {
        glsl.is_empty()
            .then(|| "WebGL2 has no compute stage".to_string())
    });
    let json = json!({
        "msl": artifacts.msl,
        "hlsl": artifacts.hlsl,
        "glsl": glsl,
        "glslMissing": missing,
        "groups": layout(&module, &info)?,
        "entryPoints": entry_points(&module),
        "native": native(&artifacts.reflection.native),
    });
    let spirv = artifacts
        .spirv
        .iter()
        .flat_map(|w| w.to_le_bytes())
        .collect();
    Ok(Output { json, spirv })
}

fn stage(stage: Stage) -> &'static str {
    match stage {
        Stage::Vertex => "vertex",
        Stage::Fragment => "fragment",
        Stage::Compute => "compute",
    }
}

/// WebGPU's GPUShaderStage bits.
fn stage_bit(stage: ShaderStage) -> u32 {
    match stage {
        ShaderStage::Vertex => 1,
        ShaderStage::Fragment => 2,
        ShaderStage::Compute => 4,
        _ => 0,
    }
}

fn stage_name(stage: ShaderStage) -> &'static str {
    match stage {
        ShaderStage::Vertex => "vertex",
        ShaderStage::Fragment => "fragment",
        ShaderStage::Compute => "compute",
        _ => "other",
    }
}

fn entry_points(module: &Module) -> Vec<Value> {
    module
        .entry_points
        .iter()
        .map(|e| json!({"name": e.name, "stage": stage_name(e.stage), "workgroup": e.workgroup_size}))
        .collect()
}

/// The layout as WebGPU's `layout: "auto"` would derive it: each bound global, visible to the
/// entry points that use it, grouped and in binding order.
fn layout(module: &Module, info: &ModuleInfo) -> Result<Vec<Value>, String> {
    let mut groups: BTreeMap<u32, BTreeMap<u32, Value>> = BTreeMap::new();
    for (handle, global) in module.global_variables.iter() {
        let Some(binding) = &global.binding else {
            continue;
        };
        let mut visibility = 0;
        for (index, entry) in module.entry_points.iter().enumerate() {
            if info.get_entry_point(index)[handle] != GlobalUse::empty() {
                visibility |= stage_bit(entry.stage);
            }
        }
        let mut entry = match (global.space, &module.types[global.ty].inner) {
            (AddressSpace::Uniform, _) => json!({"type": "uniform"}),
            (AddressSpace::Storage { access }, _) => {
                let ty = if access.contains(StorageAccess::STORE) {
                    "storage"
                } else {
                    "read-only-storage"
                };
                json!({"type": ty})
            }
            (AddressSpace::Handle, TypeInner::Sampler { comparison }) => {
                json!({"type": if *comparison { "comparison-sampler" } else { "sampler" }})
            }
            (
                AddressSpace::Handle,
                TypeInner::Image {
                    dim,
                    arrayed,
                    class,
                },
            ) => {
                let view = view_dimension(*dim, *arrayed);
                match class {
                    ImageClass::Sampled { kind, multi } => {
                        let sample = match kind {
                            ScalarKind::Float => "float",
                            ScalarKind::Sint => "sint",
                            ScalarKind::Uint => "uint",
                            other => return Err(format!("a texture of {other:?}")),
                        };
                        json!({"type": "texture", "sampleType": sample, "viewDimension": view, "multisampled": multi})
                    }
                    ImageClass::Depth { multi } => {
                        json!({"type": "texture", "sampleType": "depth", "viewDimension": view, "multisampled": multi})
                    }
                    ImageClass::Storage { format, access } => {
                        let access = match (
                            access.contains(StorageAccess::LOAD),
                            access.contains(StorageAccess::STORE),
                        ) {
                            (true, true) => "read-write",
                            (true, false) => "read-only",
                            _ => "write-only",
                        };
                        let format = naga::common::wgsl::ToWgsl::to_wgsl(*format);
                        json!({"type": "storage-texture", "format": format, "access": access, "viewDimension": view})
                    }
                }
            }
            (space, _) => return Err(format!("a binding in {space:?}")),
        };
        entry["binding"] = json!(binding.binding);
        entry["visibility"] = json!(visibility);
        groups
            .entry(binding.group)
            .or_default()
            .insert(binding.binding, entry);
    }
    Ok(groups
        .into_iter()
        .map(|(group, entries)| {
            json!({"group": group, "entries": entries.into_values().collect::<Vec<_>>()})
        })
        .collect())
}

fn view_dimension(dim: ImageDimension, arrayed: bool) -> &'static str {
    match (dim, arrayed) {
        (ImageDimension::D1, _) => "1d",
        (ImageDimension::D2, false) => "2d",
        (ImageDimension::D2, true) => "2d-array",
        (ImageDimension::D3, _) => "3d",
        (ImageDimension::Cube, false) => "cube",
        (ImageDimension::Cube, true) => "cube-array",
    }
}

/// russl's binding models, which its documentation describes and a minor version keeps.
fn native(native: &NativeBindings) -> Value {
    let msl: Vec<Value> = native
        .msl
        .iter()
        .map(|e| {
            let resources: Vec<Value> = e
                .resources
                .iter()
                .map(|r| {
                    let (kind, index) = match r.slot {
                        MslSlot::Buffer(i) => ("buffer", i),
                        MslSlot::Texture(i) => ("texture", i),
                        MslSlot::Sampler(i) => ("sampler", i),
                    };
                    json!({"group": r.group, "binding": r.binding, "kind": kind, "index": index})
                })
                .collect();
            json!({"entryPoint": e.entry_point, "resources": resources, "sizesBuffer": e.sizes_buffer})
        })
        .collect();
    let hlsl: Vec<Value> = native
        .hlsl
        .iter()
        .map(|b| match b.slot {
            HlslSlot::Register {
                class,
                index,
                space,
            } => json!({
                "group": b.group, "binding": b.binding, "kind": "register",
                "registerClass": class.to_string(), "index": index, "space": space,
            }),
            HlslSlot::SamplerIndex { index } => json!({
                "group": b.group, "binding": b.binding, "kind": "sampler-index", "index": index,
            }),
        })
        .collect();
    let glsl: Vec<Value> = native.glsl.iter().map(glsl_bindings).collect();
    json!({"msl": msl, "hlsl": hlsl, "glsl": glsl})
}

fn glsl_bindings(g: &GlslBindings) -> Value {
    let textures: Vec<Value> = g
        .textures
        .iter()
        .map(|t| {
            let sampler = t
                .sampler
                .map(|(group, binding)| json!({"group": group, "binding": binding}));
            json!({"name": t.name, "group": t.texture.0, "binding": t.texture.1, "sampler": sampler})
        })
        .collect();
    let blocks: Vec<Value> = g
        .uniform_blocks
        .iter()
        .map(|(name, (group, binding))| json!({"name": name, "group": group, "binding": binding}))
        .collect();
    json!({"entryPoint": g.entry_point, "textures": textures, "uniformBlocks": blocks})
}
