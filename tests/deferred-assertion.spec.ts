test.fails("queueMicrotask", () => {
  queueMicrotask(() => expect(1).toBe(2));
});

test.fails("promise then, not returned", () => {
  Promise.resolve().then(() => expect(1).toBe(2));
});

test.fails("async function, not awaited", () => {
  (async () => {
    await Promise.resolve();
    expect(1).toBe(2);
  })();
});

test.fails("process.nextTick", () => {
  process.nextTick(() => expect(1).toBe(2));
});

test.fails("async test, queueMicrotask before return", async () => {
  queueMicrotask(() => expect(1).toBe(2));
});
