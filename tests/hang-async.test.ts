test("hang with async work", async () => {
  function wait(time: number) {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, time);
    });
  }
  await wait(5500);
});

