// C ABI for the vendored esbuild c-archive (vendor/esbuild/cabi). Mirrors the
// //export signatures in esbuild_cabi.go. Kept hand-written (instead of using
// the go-generated header) so the build doesn't depend on a sibling output path.
#ifndef ESBUILD_H
#define ESBUILD_H

#ifdef __cplusplus
extern "C" {
#endif

// Transpile a single file's `contents` to an ES module (no bundling, no
// resolution — imports stay intact for the caller's module loader). The loader
// is chosen from `sourcefile`'s extension, which also labels errors. Returns a
// heap string the caller must release with esbuild_free. On success *ok == 1 and
// the string is the transpiled JS; on failure *ok == 0 and it is the errors.
char *esbuild_transform(char *contents, char *sourcefile, int *ok);
void esbuild_free(char *s);

#ifdef __cplusplus
}
#endif

#endif
