// C ABI for the vendored esbuild c-archive (vendor/esbuild/cabi). Mirrors the
// //export signatures in esbuild_cabi.go. Kept hand-written (instead of using
// the go-generated header) so the build doesn't depend on a sibling output path.
#ifndef ESBUILD_H
#define ESBUILD_H

#ifdef __cplusplus
extern "C" {
#endif

// Bundle `contents` (a synthetic entry module) into a single ES module; imports
// inside it resolve relative to `resolve_dir`. Returns a heap string the caller
// must release with esbuild_free. On success *ok == 1 and the string is the
// bundled JS; on failure *ok == 0 and the string is the formatted errors.
char *esbuild_bundle(char *contents, char *resolve_dir, int *ok);
void esbuild_free(char *s);

#ifdef __cplusplus
}
#endif

#endif
