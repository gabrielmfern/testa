test("hang with async work", async () => {
  function wait(time: number) {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        console.log('this will still fire because we can\'t clear timeouts');
        resolve();
      }, time);
    });
  }
  await wait(5500);
});

test("hang with sync work", () => {
  while(true) { }
});

test("hang with async work in 100ms", async () => {
  function wait(time: number) {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        console.log('this will still fire because we can\'t clear timeouts');
        resolve();
      }, time);
    });
  }
  await wait(200);
}, 100);

test("hang with sync work in 100ms", () => {
  while(true) { }
}, 100);

