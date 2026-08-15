test.failing("failing test", () => {
  expect(2).toBe(0);
});

test.failing("throwing an Error", () => {
  throw new Error("this is my error");
});

test.failing("throwing an Error async", async () => {
  throw new Error("this is my async error");
});
