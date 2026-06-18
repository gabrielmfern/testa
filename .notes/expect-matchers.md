# expect() surface — what Vitest supports, what testa needs

Goal: enumerate the full `expect()` API so we can decide what to support.
Reference: Vitest v4.1 (`docs/api/expect.md`). Jest-compatible, Chai under the hood.

## What testa supports today

- `expect(actual).toBe(expected)` — strict identity via v8 `SameValue` (`Object.is`).
  Implemented as a Zig v8 callback in `src/main.zig` (`toBeCallback` / `expectCallback`).

That's it. Everything below is missing.

## Implementation note (read before the lists)

In `testa` every matcher is currently a hand-written Zig v8 callback. That does
**not** scale to ~80 matchers. The cheaper path: inject a small JS prelude that
defines `expect` in pure JS and implements all matchers there. Only a few
operations need a v8/Zig primitive:

- identity → `Object.is` (already a JS builtin, no Zig needed)
- deep equality → a JS `equals()` walk (or steal Vitest/Chai's, but we want minimal)
- pretty-printing the diff on failure

So the realistic plan is: **one JS prelude, matchers in JS, throw an Error on
failure** (the test harness already turns a thrown error into a failed test).
Zig stays responsible for module loading, timing, and reporting — not assertions.

Legend: ✅ have · ⬜ missing · `async` = needs promise handling.

---

## 1. Core matchers — `expect(x).matcher()`

### Equality
- ✅ `toBe(value)` — `Object.is`
- ⬜ `toEqual(value)` — deep recursive equality (ignores `undefined` props)
- ⬜ `toStrictEqual(value)` — deep + checks class, `undefined` keys, sparse arrays
- ⬜ `toMatchObject(subset)` — received contains the subset (recursive)

### Truthiness / nullish
- ⬜ `toBeTruthy()`
- ⬜ `toBeFalsy()`
- ⬜ `toBeNull()`
- ⬜ `toBeUndefined()`
- ⬜ `toBeDefined()`
- ⬜ `toBeNaN()`

### Numbers
- ⬜ `toBeGreaterThan(n)`
- ⬜ `toBeGreaterThanOrEqual(n)`
- ⬜ `toBeLessThan(n)`
- ⬜ `toBeLessThanOrEqual(n)`
- ⬜ `toBeCloseTo(n, numDigits = 2)` — floating-point compare

### Containment / shape / pattern
- ⬜ `toContain(item)` — string substring, array member (`Object.is`-ish), DOM classList
- ⬜ `toContainEqual(item)` — array member by deep equality
- ⬜ `toHaveLength(n)` — checks `.length`
- ⬜ `toHaveProperty(keyPath, value?)` — `keyPath` is dot/array path
- ⬜ `toMatch(string | RegExp)` — string contains / matches
- ⬜ `toMatchObject(subset)` (also listed under equality)

### Type
- ⬜ `toBeTypeOf('string'|'number'|...)` — `typeof`
- ⬜ `toBeInstanceOf(Class)` — `instanceof`

### Misc value
- ⬜ `toBeOneOf([a, b, c])` — equals one of
- ⬜ `toSatisfy(fn, message?)` — predicate returns truthy

### Errors
- ⬜ `toThrow(expected?)` — receiver must be a `() => ...`; `expected` is
  string (substring), RegExp, Error class, or Error instance (message match)
- ⬜ `toThrowError(expected?)` — alias of `toThrow`

---

## 2. Modifiers — chain before the matcher

- ⬜ `.not` — inverts the next matcher
- ⬜ `.resolves` `async` — awaits a resolving promise, then applies matcher to value
- ⬜ `.rejects` `async` — awaits a rejecting promise, then applies matcher to reason

These compose: `await expect(p).resolves.not.toBe(1)`.

---

## 3. Snapshot matchers

Need on-disk `.snap` files + a serializer + an update mode (`--update`).
Heaviest feature group; probably the last to do.

- ⬜ `toMatchSnapshot(hint?)` / `toMatchSnapshot(propertiesMatcher?, hint?)`
- ⬜ `toMatchInlineSnapshot(snapshot?)` — writes the snapshot back into the test source
- ⬜ `toThrowErrorMatchingSnapshot(hint?)`
- ⬜ `toThrowErrorMatchingInlineSnapshot(snapshot?)`
- ⬜ `toMatchFileSnapshot(filepath, hint?)` `async`

---

## 4. Mock / spy matchers — `expect(spy).matcher()`

Blocked on first shipping a mock primitive (`vi.fn()` / `vi.spyOn()`), which
testa does not have. List for completeness.

### Calls
- ⬜ `toHaveBeenCalled()`
- ⬜ `toHaveBeenCalledTimes(n)`
- ⬜ `toHaveBeenCalledWith(...args)`
- ⬜ `toHaveBeenCalledExactlyOnceWith(...args)`
- ⬜ `toHaveBeenLastCalledWith(...args)`
- ⬜ `toHaveBeenNthCalledWith(n, ...args)`

### Returns (sync)
- ⬜ `toHaveReturned()`
- ⬜ `toHaveReturnedTimes(n)`
- ⬜ `toHaveReturnedWith(value)`
- ⬜ `toHaveLastReturnedWith(value)`
- ⬜ `toHaveNthReturnedWith(n, value)`

### Resolves (async mocks)
- ⬜ `toHaveResolved()`
- ⬜ `toHaveResolvedTimes(n)`
- ⬜ `toHaveResolvedWith(value)`
- ⬜ `toHaveLastResolvedWith(value)`
- ⬜ `toHaveNthResolvedWith(n, value)`

---

## 5. Asymmetric matchers — used *inside* other matchers

Returned by `expect.*`, matched structurally inside `toEqual`/`toHaveBeenCalledWith`/etc.
Each also has an `expect.not.*` negated form.

- ⬜ `expect.anything()` — anything except `null`/`undefined`
- ⬜ `expect.any(Constructor)` — `instanceof` / primitive wrapper
- ⬜ `expect.closeTo(n, numDigits?)`
- ⬜ `expect.arrayContaining([...])` / `expect.not.arrayContaining`
- ⬜ `expect.objectContaining({...})` / `expect.not.objectContaining`
- ⬜ `expect.stringContaining(str)` / `expect.not.stringContaining`
- ⬜ `expect.stringMatching(str | RegExp)` / `expect.not.stringMatching`

Implementing these well means the deep-`equals()` walk must recognize an
"asymmetric matcher" marker and delegate to its `.asymmetricMatch(received)`.
Design `equals()` with this hook from the start.

---

## 6. `expect.*` statics — utilities, not value matchers

- ⬜ `expect.extend({...})` — register custom matchers (also makes asymmetric versions)
- ⬜ `expect.assertions(n)` — fail unless exactly `n` assertions ran this test
- ⬜ `expect.hasAssertions()` — fail unless ≥1 assertion ran
- ⬜ `expect.soft(value)` — assertion that records failure but doesn't stop the test
- ⬜ `expect.poll(fn, { interval, timeout })` `async` — retry until matcher passes
  (note: no snapshot or mock matchers allowed on `poll`)
- ⬜ `expect.unreachable(message?)` — always throws; marks a branch unreachable
- ⬜ `expect.addEqualityTesters([...])` — custom equality for `toEqual` & friends
- ⬜ `expect.addSnapshotSerializer(...)` — custom snapshot serialization
- ⬜ `expect.getState()` / `expect.setState({...})` — matcher state (current test, etc.)

`assertions`/`hasAssertions`/`soft` need a per-test counter the harness owns —
the prelude increments on each matcher call; `testCallback` reads/resets it.

---

## Suggested order to support (cheapest → heaviest)

1. **Group 1 core matchers** in a JS prelude — pure JS, no new Zig. Biggest win.
   Needs a `equals()` deep-compare and a value pretty-printer.
2. **`.not`** — trivial once matchers are JS (flip the pass/fail).
3. **`.resolves` / `.rejects`** — promise plumbing; harness must `await` test bodies.
4. **Asymmetric matchers + `expect.extend`** — once `equals()` has the hook.
5. **`expect.assertions` / `soft` / `unreachable`** — per-test counter in harness.
6. **Mock matchers** — gated on building `vi.fn()` first.
7. **Snapshots** — gated on `.snap` storage + update mode.
