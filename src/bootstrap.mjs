// ESM entry point (LoadEnvironment with ModuleFormat::kModule). Embedded node
// only resolves `node:` builtins for us, not files — so we run user tests with
// vm.SourceTextModule and resolve their imports off the filesystem ourselves.
// This gives real ESM semantics, in-process, no bundler, no subprocess. Modules
// evaluate on the current context, where test()/expect() (installed natively
// from Zig) live as globals. No file watching. No test/expect defined here.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const args = process.argv.slice(1).filter((a) => a && !a.startsWith('-'));
const targets = args.length ? args : ['.'];

function collect(p, out) {
  if (fs.statSync(p).isDirectory()) {
    for (const e of fs.readdirSync(p)) collect(path.join(p, e), out);
  } else if (p.endsWith('.test.js')) {
    out.push(p);
  }
  return out;
}

const files = [];
for (const t of targets) collect(t, files);

const cache = new Map();
function load(file) {
  let mod = cache.get(file);
  if (!mod) {
    mod = new vm.SourceTextModule(fs.readFileSync(file, 'utf8'), { identifier: file });
    cache.set(file, mod);
  }
  return mod;
}
// ponytail: resolves relative specifiers only; bare/builtin specifiers in user
// tests aren't handled yet (playground has none). Add node: + node_modules when needed.
function linker(specifier, ref) {
  return load(path.resolve(path.dirname(ref.identifier), specifier));
}

for (const f of files) {
  const mod = load(path.resolve(f));
  await mod.link(linker);
  await mod.evaluate();
}
