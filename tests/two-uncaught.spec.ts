test.fails("two uncaught errors in one test", () => {
  queueMicrotask(() => {
    throw new Error("first");
  });
  queueMicrotask(() => {
    throw new Error("second");
  });
});
