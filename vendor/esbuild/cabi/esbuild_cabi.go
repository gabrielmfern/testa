// C ABI shim over esbuild's public pkg/api. Built as a c-archive (.a + .h) and
// linked straight into the Zig binary — no subprocess, no Node. We don't touch
// esbuild's internals; this only wraps api.Build.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"unsafe"

	"github.com/evanw/esbuild/pkg/api"
)

// esbuild_bundle bundles `contents` (a synthetic entry module, e.g. a list of
// imports) into a single ES module and returns it as a C string the caller must
// release with esbuild_free. Imports inside `contents` resolve relative to
// `resolveDir`. On success *ok is 1 and the string is the bundled JS; on failure
// *ok is 0 and the string is the formatted errors.
//
//export esbuild_bundle
func esbuild_bundle(contents *C.char, resolveDir *C.char, ok *C.int) *C.char {
	result := api.Build(api.BuildOptions{
		Stdin: &api.StdinOptions{
			Contents:   C.GoString(contents),
			ResolveDir: C.GoString(resolveDir),
			Loader:     api.LoaderJS,
			Sourcefile: "testa-entry.js",
		},
		Bundle:   true,
		Write:    false,
		Format:   api.FormatESModule,
		Platform: api.PlatformNode,
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
	return C.CString(string(result.OutputFiles[0].Contents))
}

//export esbuild_free
func esbuild_free(s *C.char) {
	C.free(unsafe.Pointer(s))
}

func main() {}
