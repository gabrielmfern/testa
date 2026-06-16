const publicRequire = require('module').createRequire(process.cwd() + '/');
globalThis.require = publicRequire;
require('vm').runInThisContext(process.argv[1]);
