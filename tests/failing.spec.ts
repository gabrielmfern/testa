test.failing("failing test", () => {
  expect(2).toBe(0);
});

test.failing("throwing an Error", () => {
  throw new Error("this is my error, this test should fail");
});

test.failing("throwing an Error async", async () => {
  throw new Error("this is my error, this test should fail");
});
