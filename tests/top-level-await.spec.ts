await new Promise((resolve) => {
  setTimeout(() => {
    resolve();
  }, 200);
});

test("this a real test, but it won't run because of the top-level await", () => {
  expect(2).toBe(2);
});
