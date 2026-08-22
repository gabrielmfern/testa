// TODO: should we also somehow support fails/skipped. maybe not?? because 
// the API for this would be pretty awkward. we should actually check if vitest 
// does this somehow, their docs don't say
test.runIf(Math.random() > 0.5)("sometimes this runs and it should work", () => {
  expect(1 + 1).toBe(2);
});

test.runIf(false)("fails, but never runs so it's fine", () => {
  expect(1 + 1).toBe(3);
});

test.if(false)("*pretty* fails, but never runs so it's fine", () => {
  expect(1 + 1).toBe(3);
});

