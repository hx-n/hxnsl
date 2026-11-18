//!     hxnsl <shader.wgsl> <out dir> [key=value ...]
//!
//! Writes `shader.json` (MSL, HLSL, GLSL ES, the bind group layout, entry points and each
//! target's binding slots) and `shader.spv`. Each `key=value` sets a pipeline constant, by the
//! key naga looks it up by; `true` and `false` are 1 and 0. The Haxe build macro runs this for
//! each shader.

use std::path::Path;
use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [wgsl, out, constants @ ..] = args.as_slice() else {
        hxn::log::error!(target: "hxnsl", "usage: hxnsl <shader.wgsl> <out dir> [key=value ...]");
        return ExitCode::from(2);
    };
    let constants: Vec<(&str, f64)> = match constants.iter().map(|c| constant(c)).collect() {
        Ok(c) => c,
        Err(message) => {
            hxn::log::error!(target: "hxnsl", "{message}");
            return ExitCode::from(2);
        }
    };
    match run(Path::new(wgsl), Path::new(out), &constants) {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            hxn::log::error!(target: "hxnsl", "{message}");
            ExitCode::FAILURE
        }
    }
}

fn constant(arg: &str) -> Result<(&str, f64), String> {
    let (key, value) = arg
        .split_once('=')
        .ok_or_else(|| format!("{arg}: a constant is key=value"))?;
    let value = match value {
        "true" => 1.0,
        "false" => 0.0,
        v => v
            .parse()
            .map_err(|_| format!("{arg}: {v} is not a number or a boolean"))?,
    };
    Ok((key, value))
}

fn run(wgsl: &Path, out: &Path, constants: &[(&str, f64)]) -> Result<(), String> {
    let source = std::fs::read_to_string(wgsl).map_err(|e| format!("{}: {e}", wgsl.display()))?;
    let output = hxnsl::translate(&source, constants)?;
    std::fs::create_dir_all(out).map_err(|e| format!("{}: {e}", out.display()))?;
    let write = |name: &str, bytes: &[u8]| {
        let path = out.join(name);
        std::fs::write(&path, bytes).map_err(|e| format!("{}: {e}", path.display()))
    };
    // The SPIR-V first: the macro takes shader.json as the sign that both are written.
    write("shader.spv", &output.spirv)?;
    write("shader.json", output.json.to_string().as_bytes())
}
