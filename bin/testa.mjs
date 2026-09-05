#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const exe = process.platform === 'win32' ? 'testa.exe' : 'testa';
const path = fileURLToPath(new URL(`../dist/${process.platform}-${process.arch}/${exe}`, import.meta.url));
const result = spawnSync(path, process.argv.slice(2), { stdio: 'inherit' });
if (result.error) {
    console.error(`testa: no binary for ${process.platform}-${process.arch} (${result.error.message})`);
    process.exit(1);
}
process.exit(result.status ?? 1);
