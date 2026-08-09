test("set timeout should work", async () => {
  await new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve();
    }, 200);
  });
});

test("fetch should work", async () => {
  const response = await fetch("https://example.com");
  expect(response.ok).toBe(true);
  await response.text();
});
