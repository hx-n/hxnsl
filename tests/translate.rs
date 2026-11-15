use serde_json::{Value, json};

const COMPUTE: &str = "
@group(0) @binding(0) var<storage, read_write> data: array<u32>;
@group(0) @binding(1) var<uniform> scale: u32;

@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    data[id.x] = data[id.x] * scale;
}
";

const RENDER: &str = "
struct Params { tint: vec4<f32> }
@group(0) @binding(0) var<uniform> params: Params;
@group(1) @binding(0) var image: texture_2d<f32>;
@group(1) @binding(1) var image_sampler: sampler;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex
fn vertex(@location(0) position: vec2<f32>) -> VertexOutput {
    return VertexOutput(vec4<f32>(position, 0.0, 1.0), position);
}

@fragment
fn fragment(input: VertexOutput) -> @location(0) vec4<f32> {
    return textureSample(image, image_sampler, input.uv) * params.tint;
}
";

fn translate(wgsl: &str) -> (Value, Vec<u8>) {
    let out = hxnsl::translate(wgsl, &[]).unwrap_or_else(|e| panic!("{e}"));
    (out.json, out.spirv)
}

#[test]
fn a_compute_shader_has_every_target_but_glsl() {
    let (json, spirv) = translate(COMPUTE);
    assert_eq!(&spirv[..4], &0x0723_0203u32.to_le_bytes(), "SPIR-V magic");
    assert!(json["msl"].as_str().unwrap().contains("kernel void main_"));
    assert!(
        json["hlsl"]
            .as_str()
            .unwrap()
            .contains("[numthreads(64, 1, 1)]")
    );
    assert_eq!(json["glsl"], json!([]));
    assert!(
        json["glslMissing"].is_string(),
        "WebGL2 has no compute stage"
    );
    assert_eq!(
        json["entryPoints"],
        json!([{"name": "main", "stage": "compute", "workgroup": [64, 1, 1]}])
    );
}

#[test]
fn the_layout_is_each_group_in_binding_order() {
    let (json, _) = translate(COMPUTE);
    assert_eq!(
        json["groups"],
        json!([{"group": 0, "entries": [
            {"binding": 0, "visibility": 4, "type": "storage"},
            {"binding": 1, "visibility": 4, "type": "uniform"},
        ]}])
    );
}

#[test]
fn a_binding_takes_the_stages_that_use_it() {
    let (json, _) = translate(RENDER);
    let groups = &json["groups"];
    assert_eq!(
        groups[0]["entries"][0]["visibility"], 2,
        "params, fragment only"
    );
    assert_eq!(
        groups[1]["entries"][0],
        json!({"binding": 0, "visibility": 2, "type": "texture", "sampleType": "float", "viewDimension": "2d", "multisampled": false})
    );
    assert_eq!(
        groups[1]["entries"][1],
        json!({"binding": 1, "visibility": 2, "type": "sampler"})
    );
}

#[test]
fn metal_slots_count_per_stage_and_kind() {
    let (json, _) = translate(RENDER);
    let fragment = json["native"]["msl"]
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["entryPoint"] == "fragment")
        .unwrap();
    let resources = fragment["resources"].as_array().unwrap();
    let slot = |group: u32, binding: u32| {
        resources
            .iter()
            .find(|r| r["group"] == group && r["binding"] == binding)
            .map(|r| {
                (
                    r["kind"].as_str().unwrap().to_string(),
                    r["index"].as_u64().unwrap(),
                )
            })
    };
    assert_eq!(slot(0, 0), Some(("buffer".into(), 0)));
    assert_eq!(slot(1, 0), Some(("texture".into(), 0)));
    assert_eq!(slot(1, 1), Some(("sampler".into(), 0)));
}

#[test]
fn hlsl_registers_follow_group_and_binding() {
    let (json, _) = translate(RENDER);
    let hlsl = json["native"]["hlsl"].as_array().unwrap();
    let find = |group: u32, binding: u32| {
        hlsl.iter()
            .find(|b| b["group"] == group && b["binding"] == binding)
            .unwrap()
            .clone()
    };
    assert_eq!(
        find(0, 0),
        json!({"group": 0, "binding": 0, "kind": "register", "registerClass": "b", "index": 0, "space": 0})
    );
    assert_eq!(
        find(1, 0),
        json!({"group": 1, "binding": 0, "kind": "register", "registerClass": "t", "index": 0, "space": 1})
    );
    assert_eq!(
        find(1, 1),
        json!({"group": 1, "binding": 1, "kind": "sampler-index", "index": 1})
    );
}

#[test]
fn a_render_shader_has_glsl_for_each_stage() {
    let (json, _) = translate(RENDER);
    let glsl = json["glsl"].as_array().unwrap();
    let stages: Vec<&str> = glsl.iter().map(|g| g["stage"].as_str().unwrap()).collect();
    assert_eq!(stages, ["vertex", "fragment"]);
    assert!(
        glsl[1]["source"]
            .as_str()
            .unwrap()
            .starts_with("#version 300 es")
    );
    let fragment = json["native"]["glsl"]
        .as_array()
        .unwrap()
        .iter()
        .find(|g| g["entryPoint"] == "fragment")
        .unwrap();
    let texture = &fragment["textures"][0];
    assert_eq!(
        (&texture["group"], &texture["binding"]),
        (&json!(1), &json!(0))
    );
    assert_eq!(texture["sampler"], json!({"group": 1, "binding": 1}));
    assert_eq!(fragment["uniformBlocks"][0]["group"], 0);
}

#[test]
fn naga_reports_bad_wgsl() {
    let err = hxnsl::translate("fn main( {", &[]).err().expect("an error");
    assert!(err.contains("error"), "{err}");
}

const OVERRIDES: &str = "
override fog: bool;
override count: u32;
@group(0) @binding(0) var<storage, read_write> data: array<u32>;

@compute @workgroup_size(1)
fn main() {
    if fog { data[0] = count; }
}
";

#[test]
fn constants_are_fixed_in_the_native_sources() {
    let out = hxnsl::translate(OVERRIDES, &[("fog", 1.0), ("count", 7.0)]).unwrap();
    let msl = out.json["msl"].as_str().unwrap();
    assert!(msl.contains("7u"), "{msl}");
}

#[test]
fn a_constant_without_a_value_is_an_error() {
    let err = hxnsl::translate(OVERRIDES, &[("fog", 1.0)])
        .err()
        .expect("an error");
    assert!(err.contains("count") || err.contains("override"), "{err}");
}
