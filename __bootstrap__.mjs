process._linkedBinding('testa');
import vm from 'node:vm';
import fs from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { pathToFileURL } from 'node:url';
import { createHook } from 'node:async_hooks';

// TODO: this is always on for now. it should be off in CI (detect via env
// vars like CI, GITHUB_ACTIONS) and controllable by a boolean cli flag that
// bypasses any heuristic.
const births = new Map();
createHook({
    init(asyncId, type) {
        births.set(asyncId, { type, stack: new Error().stack });
    },
    destroy(asyncId) {
        births.delete(asyncId);
    },
}).enable();

globalThis.__testa_stack = asyncId => births.get(asyncId)?.stack ?? '';

// we do this so that we can warmup the import and WASM whatever that node uses to strip types, so that if tests teardown really fast because of a short timeout, the other tests won't error during type stripping.
stripTypeScriptTypes('const x: number = 1')
// this also warms up stdout and stuff so that they don't get "leaked" in between tests
process.stdout.write('');
process.stderr.write('');

const cache = new Map();

function isTypeScript(url) {
    return url.endsWith('.ts') || url.endsWith('.mts') || url.endsWith('.cts');
}

async function loadModule(url) {
    let mod = cache.get(url);
    if (mod) return mod;
    let code = fs.readFileSync(new URL(url), 'utf8');
    if (isTypeScript(url)) code = stripTypeScriptTypes(code);
    mod = new vm.SourceTextModule(code, { identifier: url, importModuleDynamically: linker });
    cache.set(url, mod);
    await mod.link(linker);
    await mod.evaluate();
    return mod;
}

function linker(specifier, referencingModule) {
    return loadModule(new URL(specifier, referencingModule.identifier).href);
}

globalThis.__testa_run = path => loadModule(pathToFileURL(path).href);
