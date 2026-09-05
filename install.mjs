import { existsSync, unlinkSync, symlinkSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

if (process.platform !== 'win32') {
    const binary = fileURLToPath(new URL(`dist/${process.platform}-${process.arch}/testa`, import.meta.url));
    const launcher = fileURLToPath(new URL('bin/testa.mjs', import.meta.url));
    if (existsSync(binary)) {
        unlinkSync(launcher);
        symlinkSync(`../dist/${process.platform}-${process.arch}/testa`, launcher);
    }
}
