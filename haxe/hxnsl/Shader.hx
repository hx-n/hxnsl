package hxnsl;

/**
	A shader written in HXSL. A class that implements this declares its
	source in `static var SRC = { ... }`; the build macro checks it when the
	program compiles and replaces it with each target's source, its layout
	and its binding slots.
**/
#if !macro
@:autoBuild(hxnsl.Build.shader())
#end
interface Shader {}
