// Async closures: the runner must await the returned promise — pumping
// microtasks and the event loop — before judging the test. Every assertion here
// lands after an await, so they only run if the runner actually waits. The timer
// case forces a real libuv loop turn (its reported duration is >= the delay), and
// the last case proves stdout written after an await is still captured.

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

test("awaits a resolved microtask", async () => {
  const value = await Promise.resolve(42);
  expect(value).toBe(42);
});

test("awaits a macrotask timer", async () => {
  let ticked = false;
  await delay(5);
  ticked = true;
  expect(ticked).toBe(true);
});

test("sees assertions after multiple awaits", async () => {
  let steps = 0;
  await Promise.resolve();
  steps += 1;
  await delay(1);
  steps += 1;
  expect(steps).toBe(2);
});

test("captures stdout written after an await", async () => {
  await delay(1);
  console.log("logged from inside an async test, after the await");
  expect(1).toBe(1);
});

// test.fails passes precisely because the closure rejects after an await — the
// runner has to await the promise to see the rejection at all.
test.fails("an async test that rejects is an expected failure", async () => {
  await delay(1);
  throw new Error("expected boom");
});
