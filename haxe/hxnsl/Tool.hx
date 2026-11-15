package hxnsl;

#if macro
import haxe.io.Path;
import haxe.macro.Context;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/** A shader as the tool wrote it for every target: the parsed `shader.json`, and the SPIR-V. **/
typedef Translated = {
	var json:Dynamic;
	var spirv:haxe.io.Bytes;
}

/**
	Runs the `hxnsl` tool over a shader's WGSL at compile time. Results
	are kept by a hash of the tool's path and modification time, the constants
	and the WGSL, in `HXNSL_CACHE`, or in a
	directory under the system's temporary directory.
**/
class Tool {
	static var tool:Null<String>;
	static var looked = false;

	/**
		The tool: `HXNSL_TOOL`, else the one this haxelib ships for the host
		under `bin/`, else a build of it in this checkout's `target/`.
	**/
	public static function find():Null<String> {
		if (looked)
			return tool;
		looked = true;
		var env = Sys.getEnv("HXNSL_TOOL");
		if (env != null && env != "") {
			if (!FileSystem.exists(env))
				Context.fatalError('HXNSL_TOOL names $env, which does not exist', Context.currentPos());
			return tool = env;
		}
		var exe = Sys.systemName() == "Windows" ? "hxnsl.exe" : "hxnsl";
		// This file is haxe/hxnsl/Tool.hx in the package.
		var root = Path.normalize(FileSystem.absolutePath(Path.directory(Context.resolvePath("hxnsl/Tool.hx"))) + "/../..");
		var shipped = '$root/bin/${host()}/$exe';
		if (FileSystem.exists(shipped)) {
			// haxelib's unzip leaves the file without its executable bit.
			if (Sys.systemName() != "Windows")
				Sys.command("chmod", ["+x", shipped]);
			return tool = shipped;
		}
		for (candidate in ['$root/target/release/$exe', '$root/target/debug/$exe'])
			if (FileSystem.exists(candidate))
				return tool = candidate;
		return null;
	}

	/** The host as release archives name it: `macos-aarch64`, `linux-x86_64`, `windows-x86_64`. **/
	static function host():String {
		var os = switch (Sys.systemName()) {
			case "Windows": "windows";
			case "Mac": "macos";
			default: "linux";
		}
		var arch = if (os == "windows") {
			Sys.getEnv("PROCESSOR_ARCHITECTURE") == "ARM64" ? "aarch64" : "x86_64";
		} else {
			var p = new Process("uname", ["-m"]);
			var m = StringTools.trim(p.stdout.readAll().toString());
			p.close();
			m == "arm64" ? "aarch64" : m;
		}
		return '$os-$arch';
	}

	/** The cache: `HXNSL_CACHE`, else `hxnsl` under the system's temporary directory. **/
	public static function cache():String {
		var dir = Sys.getEnv("HXNSL_CACHE");
		if (dir == null || dir == "") {
			var temp = Sys.getEnv(Sys.systemName() == "Windows" ? "TEMP" : "TMPDIR");
			dir = (temp == null || temp == "" ? "/tmp" : temp) + "/hxnsl";
		}
		return FileSystem.absolutePath(dir);
	}

	/**
		Translates `wgsl` with each pipeline constant fixed by `constants`, as
		`key=value`; fails compilation with the tool's report if it rejects it.
	**/
	public static function translate(name:String, wgsl:String, constants:Array<String>, tool:String, pos:haxe.macro.Expr.Position):Translated {
		var root = cache();
		// Another build of the tool can write different output for the same WGSL.
		var stamp = FileSystem.stat(tool).mtime.getTime();
		var dir = '$root/' + haxe.crypto.Md5.encode('$tool $stamp ${constants.join(" ")}\n$wgsl');
		if (!FileSystem.exists('$dir/shader.json')) {
			FileSystem.createDirectory(dir);
			File.saveContent('$dir/shader.wgsl', wgsl);
			var p = new Process(tool, ['$dir/shader.wgsl', dir].concat(constants));
			var errors = p.stderr.readAll().toString();
			var code = p.exitCode();
			p.close();
			if (code != 0)
				Context.fatalError('$name: the WGSL hxnsl wrote does not compile for every target: $errors', pos);
		}
		return {
			json: haxe.Json.parse(File.getContent('$dir/shader.json')),
			spirv: File.getBytes('$dir/shader.spv')
		};
	}
}
#end
