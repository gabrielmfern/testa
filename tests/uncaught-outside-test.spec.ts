queueMicrotask(() => {
  throw new Error("thrown while loading the file");
});

test("runs after the file-level throw", () => {
  expect(1).toBe(1);
});
