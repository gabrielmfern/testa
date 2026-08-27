test.fails("hang with async work", async () => {
  function wait(time: number) {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        console.log('this will not fire because we clear leaks');
        resolve();
      }, time);
    });
  }
  await wait(5500);
});

test.fails("hang with sync work", () => {
  while(true) { }
});

test.fails("hang with async work in 100ms", async () => {
  function wait(time: number) {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        console.log('this async work will not fire beacuse we clear leaks');
        resolve();
      }, time);
    });
  }
  await wait(200);
}, 100);

test.fails("hang with sync work in 100ms", () => {
  while(true) { }
}, 100);

test.fails("hang in a microtask after a sync return", () => {
  queueMicrotask(() => { while(true) { } });
}, 100);

test("still runs after a microtask hang", () => {
  expect(1).toBe(1);
});

test.fails("hang in a nextTick after a sync return", () => {
  process.nextTick(() => { while(true) { } });
}, 100);

test("still runs after a nextTick hang", () => {
  expect(1).toBe(1);
});

