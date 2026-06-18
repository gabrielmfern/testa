// C ABI shim over esbuild's public pkg/api. Built as a c-archive (.a + .h) and
// linked straight into the Zig binary — no subprocess, no Node. We don't touch
// esbuild's internals; this only wraps api.Transform.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"strings"
	"unsafe"

	"github.com/evanw/esbuild/pkg/api"
)

func loaderFor(sourcefile string) api.Loader {
	switch {
	case strings.HasSuffix(sourcefile, ".ts"):
		return api.LoaderTS
	case strings.HasSuffix(sourcefile, ".tsx"):
		return api.LoaderTSX
	case strings.HasSuffix(sourcefile, ".jsx"):
		return api.LoaderJSX
	case strings.HasSuffix(sourcefile, ".json"):
		return api.LoaderJSON
	default:
		return api.LoaderJS
	}
}

// esbuild_transform transpiles a single file's `contents` to an ES module (no
// bundling, no resolution — imports are left intact for the caller's own module
// loader). The loader is picked from `sourcefile`'s extension; `sourcefile` also
// labels the file in error messages. Returns a C string the caller must release
// with esbuild_free. On success *ok is 1 and the string is the transpiled JS; on
// failure *ok is 0 and the string is the formatted errors.
//
//export esbuild_transform
func esbuild_transform(contents *C.char, sourcefile *C.char, ok *C.int) *C.char {
	name := C.GoString(sourcefile)
	result := api.Transform(C.GoString(contents), api.TransformOptions{
		Loader:     loaderFor(name),
		Sourcefile: name,
		Format:     api.FormatESModule,
		Platform:   api.PlatformNode,
	})

	if len(result.Errors) > 0 {
		*ok = 0
		msgs := api.FormatMessages(result.Errors, api.FormatMessagesOptions{Kind: api.ErrorMessage})
		var buf []byte
		for _, m := range msgs {
			buf = append(buf, m...)
		}
		return C.CString(string(buf))
	}

	*ok = 1
	return C.CString(string(result.Code))
}

//export esbuild_free
func esbuild_free(s *C.char) {
	C.free(unsafe.Pointer(s))
}

func main() {}
