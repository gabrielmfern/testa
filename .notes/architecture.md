I want this to be the simplest test runner that has ever existed. I want a single module to be created, I want that to be ran, and to go through all of the tests defined by the user.

For the purposes of experimentation, and for a very initial version, this will only support:

```js
test(..., () => {
  expect(...).toBe(...);
});
```

With just `toBe` as an available option here. Test doesn't really need to register anything, I think it can run at the exact moment this code is evaluated, because we're not doing any sort of scheduling work here, so we can just call it directly there. It could be as simple as

```js
function test(name, closure) {
  console.info('-> running ', name);
  closure();
}
```

This also means we're not running these tests in parallel here. But I think
running in parallel can easily be achieved by simply generating multiple
modules, as "shards", one for each thread and then simply run each of those
threads.

We are going to use the [embedded Node.js API](https://nodejs.org/api/embedding.html) here.

For this to actually be useful for something, we will also need to do some bundling. I do not want to spawn a shell and a subproces to do this, so we need something that has a C ABI or anything else that I can use directly calling from code with Zig, C or C++. Possible options:
- esbuild (maybe not, unless we patch it somehow, perhaps?)
- swc (maybe not, unsure if they do bundling)
- rspack

Considering that we are calling Node.js directly here, we can also run vite to generate the javascript bundles, and then import 

We should not support CommonJS at all as an option here, it will overcomplicate things and it's needless overhead for something that should not be used by anyone, anywhere, anymore.

The core idea for this is to understand what is the baseline for test running in JavaScript. Meant to answer "What stops things from being completely instant and making feedback loops as close to nothing as possible?".

