await new Promise((resolve) => {
  setTimeout(() => {
    resolve();
  }, 200);
});

test("top-level await shouldn't break tests", () => {
  expect(2).toBe(2);
});
