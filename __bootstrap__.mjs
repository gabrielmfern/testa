process._linkedBinding('testa');
import vm from 'node:vm';
import fs from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { pathToFileURL } from 'node:url';

// we do this so that we can warmup the import and WASM whatever that node uses to strip types, so that if tests teardown really fast because of a short timeout, the other tests won't error during type stripping.
stripTypeScriptTypes('const x: number = 1')

const cache = new Map();

function isTypeScript(url) {
    return url.endsWith('.ts') || url.endsWith('.mts') || url.endsWith('.cts');
}

async function createAndLink(url) {
    let mod = cache.get(url);
    if (mod) return mod;
    let code = fs.readFileSync(new URL(url), 'utf8');
    if (isTypeScript(url)) code = stripTypeScriptTypes(code);
    mod = new vm.SourceTextModule(code, { identifier: url, importModuleDynamically: dynamicLinker });
    cache.set(url, mod);
    await mod.link(linker);
    return mod;
}

function linker(specifier, referencingModule) {
    return createAndLink(new URL(specifier, referencingModule.identifier).href);
}

async function dynamicLinker(specifier, referencingModule) {
    const mod = await createAndLink(new URL(specifier, referencingModule.identifier).href);
    await mod.evaluate();
    return mod;
}

globalThis.__testa_link = path => createAndLink(pathToFileURL(path).href);
globalThis.__testa_evaluate = path => cache.get(pathToFileURL(path).href).evaluate();
