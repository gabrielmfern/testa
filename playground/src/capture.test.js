// Manual check for per-test stdout/stderr capture: the logged lines below should
// appear indented under each "ok ..." result line, in order, not interleaved
// with the rest of the run. stderr is captured too.
test("captures stdout written during a test", () => {
  console.log("captured line 1");
  console.log("captured line 2");
  expect(1).toBe(1);
});

test("captures stderr too", () => {
  console.error("captured stderr line");
  expect("a").toBe("a");
});

test("a test with no output prints nothing extra", () => {
  expect(true).toBe(true);
});
