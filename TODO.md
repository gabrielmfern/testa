# TODO

Vitest API surface, one signature per line, grouped by area. Reference for what testa-jai does not yet support.

## Test definition

- [x] `test(name: string, fn: () => void | Promise<void>, timeout?: number): void`
- [ ] `test.skip(name: string, fn: Function): void`
- [ ] `test.only(name: string, fn: Function): void`
- [ ] `test.todo(name: string): void`
- [ ] `test.fails(name: string, fn: Function): void`
- [ ] `test.concurrent(name: string, fn: Function): void`
- [ ] `test.sequential(name: string, fn: Function): void`
- [ ] `test.each(cases: ReadonlyArray<T>)(name: string, fn: (...args: T[]) => void): void`
- [ ] `test.for(cases: ReadonlyArray<T>)(name: string, fn: (arg: T, ctx: TestContext) => void): void`
- [ ] `test.extend(fixtures: Fixtures): TestAPI`
- [ ] `test.runIf(condition: boolean)(name: string, fn: Function): void`
- [ ] `test.skipIf(condition: boolean)(name: string, fn: Function): void`
- [ ] `it(name: string, fn: () => void | Promise<void>, timeout?: number): void` (alias of `test`)

## Suite definition

- [ ] `describe(name: string, fn: () => void): void`
- [ ] `describe.skip(name: string, fn: () => void): void`
- [ ] `describe.only(name: string, fn: () => void): void`
- [ ] `describe.todo(name: string): void`
- [ ] `describe.concurrent(name: string, fn: () => void): void`
- [ ] `describe.sequential(name: string, fn: () => void): void`
- [ ] `describe.shuffle(name: string, fn: () => void): void`
- [ ] `describe.each(cases: ReadonlyArray<T>)(name: string, fn: (...args: T[]) => void): void`
- [ ] `describe.runIf(condition: boolean)(name: string, fn: () => void): void`
- [ ] `describe.skipIf(condition: boolean)(name: string, fn: () => void): void`

## Hooks

- [ ] `beforeAll(fn: () => void | Promise<void>, timeout?: number): void`
- [ ] `afterAll(fn: () => void | Promise<void>, timeout?: number): void`
- [ ] `beforeEach(fn: (ctx: TestContext) => void | Promise<void>, timeout?: number): void`
- [ ] `afterEach(fn: (ctx: TestContext) => void | Promise<void>, timeout?: number): void`
- [ ] `onTestFailed(fn: (ctx: TestContext) => void): void`
- [ ] `onTestFinished(fn: (ctx: TestContext) => void): void`

## expect — core

- [x] `expect(actual: unknown): Assertion`
- [ ] `expect.soft(actual: unknown): Assertion`
- [ ] `expect.unreachable(message?: string): never`
- [ ] `expect.assertions(count: number): void`
- [ ] `expect.hasAssertions(): void`
- [ ] `.not: Assertion`
- [ ] `.resolves: Assertion`
- [ ] `.rejects: Assertion`

## expect — equality matchers

- [ ] `.toBe(expected: unknown): void`
- [ ] `.toEqual(expected: unknown): void`
- [ ] `.toStrictEqual(expected: unknown): void`
- [ ] `.toBeCloseTo(expected: number, numDigits?: number): void`

## expect — truthiness matchers

- [ ] `.toBeTruthy(): void`
- [ ] `.toBeFalsy(): void`
- [ ] `.toBeNull(): void`
- [ ] `.toBeUndefined(): void`
- [ ] `.toBeDefined(): void`
- [ ] `.toBeNaN(): void`

## expect — type/instance matchers

- [ ] `.toBeTypeOf(type: string): void`
- [ ] `.toBeInstanceOf(constructor: Function): void`

## expect — number matchers

- [ ] `.toBeGreaterThan(expected: number | bigint): void`
- [ ] `.toBeGreaterThanOrEqual(expected: number | bigint): void`
- [ ] `.toBeLessThan(expected: number | bigint): void`
- [ ] `.toBeLessThanOrEqual(expected: number | bigint): void`

## expect — string/array/object matchers

- [ ] `.toContain(item: unknown): void`
- [ ] `.toContainEqual(item: unknown): void`
- [ ] `.toHaveLength(length: number): void`
- [ ] `.toHaveProperty(keyPath: string | string[], value?: unknown): void`
- [ ] `.toMatch(pattern: string | RegExp): void`
- [ ] `.toMatchObject(object: object | array): void`

## expect — snapshot matchers

- [ ] `.toMatchSnapshot(hint?: string): void`
- [ ] `.toMatchInlineSnapshot(snapshot?: string): void`
- [ ] `.toThrowErrorMatchingSnapshot(hint?: string): void`
- [ ] `.toThrowErrorMatchingInlineSnapshot(snapshot?: string): void`
- [ ] `.toMatchFileSnapshot(filepath: string): void`

## expect — exception matchers

- [ ] `.toThrow(expected?: string | RegExp | Error | Function): void`
- [ ] `.toThrowError(expected?: string | RegExp | Error | Function): void` (alias of `toThrow`)

## expect — mock/spy matchers

- [ ] `.toHaveBeenCalled(): void`
- [ ] `.toHaveBeenCalledTimes(times: number): void`
- [ ] `.toHaveBeenCalledWith(...args: unknown[]): void`
- [ ] `.toHaveBeenCalledExactlyOnceWith(...args: unknown[]): void`
- [ ] `.toHaveBeenLastCalledWith(...args: unknown[]): void`
- [ ] `.toHaveBeenNthCalledWith(n: number, ...args: unknown[]): void`
- [ ] `.toHaveReturned(): void`
- [ ] `.toHaveReturnedTimes(times: number): void`
- [ ] `.toHaveReturnedWith(value: unknown): void`
- [ ] `.toHaveLastReturnedWith(value: unknown): void`
- [ ] `.toHaveNthReturnedWith(n: number, value: unknown): void`

## expect — DOM matchers

- [ ] `.toBeVisible(): void`
- [ ] `.toBeDisabled(): void`
- [ ] `.toBeEnabled(): void`
- [ ] `.toBeEmptyDOMElement(): void`
- [ ] `.toBeInTheDocument(): void`
- [ ] `.toBeInvalid(): void`
- [ ] `.toBeValid(): void`
- [ ] `.toBeRequired(): void`
- [ ] `.toContainElement(element: HTMLElement | null): void`
- [ ] `.toContainHTML(htmlText: string): void`
- [ ] `.toHaveAccessibleDescription(description?: string | RegExp): void`
- [ ] `.toHaveAccessibleName(name?: string | RegExp): void`
- [ ] `.toHaveAttribute(attr: string, value?: unknown): void`
- [ ] `.toHaveClass(...classNames: string[]): void`
- [ ] `.toHaveFocus(): void`
- [ ] `.toHaveFormValues(values: Record<string, unknown>): void`
- [ ] `.toHaveStyle(css: string | Record<string, unknown>): void`
- [ ] `.toHaveTextContent(text: string | RegExp): void`
- [ ] `.toHaveValue(value?: string | string[] | number): void`
- [ ] `.toHaveDisplayValue(value: string | RegExp | Array<string | RegExp>): void`
- [ ] `.toBeChecked(): void`
- [ ] `.toBePartiallyChecked(): void`
- [ ] `.toHaveErrorMessage(message?: string | RegExp): void`

## expect — asymmetric matchers

- [ ] `expect.anything(): AsymmetricMatcher`
- [ ] `expect.any(constructor: Function): AsymmetricMatcher`
- [ ] `expect.arrayContaining(array: unknown[]): AsymmetricMatcher`
- [ ] `expect.objectContaining(object: object): AsymmetricMatcher`
- [ ] `expect.stringContaining(string: string): AsymmetricMatcher`
- [ ] `expect.stringMatching(pattern: string | RegExp): AsymmetricMatcher`
- [ ] `expect.closeTo(number: number, numDigits?: number): AsymmetricMatcher`
- [ ] `expect.addSnapshotSerializer(plugin: SnapshotSerializer): void`
- [ ] `expect.extend(matchers: Record<string, MatcherFn>): void`
- [ ] `expect.addEqualityTesters(testers: Array<Tester>): void`

## vi — mocking

- [ ] `vi.fn(implementation?: Function): Mock`
- [ ] `vi.spyOn(object: object, method: string, accessType?: 'get' | 'set'): MockInstance`
- [ ] `vi.mock(path: string, factory?: () => unknown): void`
- [ ] `vi.unmock(path: string): void`
- [ ] `vi.doMock(path: string, factory?: () => unknown): void`
- [ ] `vi.doUnmock(path: string): void`
- [ ] `vi.hoisted(factory: () => T): T`
- [ ] `vi.importActual(path: string): Promise<T>`
- [ ] `vi.importMock(path: string): Promise<T>`
- [ ] `vi.mocked(item: T, options?: { partial?: boolean; deep?: boolean }): MaybeMockedDeep<T>`
- [ ] `vi.isMockFunction(fn: unknown): boolean`
- [ ] `vi.clearAllMocks(): void`
- [ ] `vi.resetAllMocks(): void`
- [ ] `vi.restoreAllMocks(): void`
- [ ] `vi.resetModules(): void`
- [ ] `vi.stubGlobal(name: string, value: unknown): void`
- [ ] `vi.unstubAllGlobals(): void`
- [ ] `vi.stubEnv(name: string, value: string): void`
- [ ] `vi.unstubAllEnvs(): void`

## vi — fake timers

- [ ] `vi.useFakeTimers(config?: FakeTimerInstallOpts): void`
- [ ] `vi.useRealTimers(): void`
- [ ] `vi.isFakeTimers(): boolean`
- [ ] `vi.advanceTimersByTime(ms: number): void`
- [ ] `vi.advanceTimersByTimeAsync(ms: number): Promise<void>`
- [ ] `vi.advanceTimersToNextTimer(): void`
- [ ] `vi.advanceTimersToNextTimerAsync(): Promise<void>`
- [ ] `vi.runAllTimers(): void`
- [ ] `vi.runAllTimersAsync(): Promise<void>`
- [ ] `vi.runOnlyPendingTimers(): void`
- [ ] `vi.runOnlyPendingTimersAsync(): Promise<void>`
- [ ] `vi.getTimerCount(): number`
- [ ] `vi.clearAllTimers(): void`
- [ ] `vi.setSystemTime(date: number | Date): void`
- [ ] `vi.getMockedSystemTime(): Date | null`
- [ ] `vi.getRealSystemTime(): number`

## vi — misc

- [ ] `vi.waitFor(callback: () => T, options?: WaitForOptions): Promise<T>`
- [ ] `vi.waitUntil(callback: () => T, options?: WaitForOptions): Promise<T>`
- [ ] `vi.setConfig(config: RuntimeConfig): void`
- [ ] `vi.resetConfig(): void`
- [ ] `vi.dynamicImportSettled(): Promise<void>`

## Mock instance (returned by `vi.fn`/`vi.spyOn`)

- [ ] `.mockImplementation(fn: Function): Mock`
- [ ] `.mockImplementationOnce(fn: Function): Mock`
- [ ] `.mockReturnValue(value: unknown): Mock`
- [ ] `.mockReturnValueOnce(value: unknown): Mock`
- [ ] `.mockResolvedValue(value: unknown): Mock`
- [ ] `.mockResolvedValueOnce(value: unknown): Mock`
- [ ] `.mockRejectedValue(value: unknown): Mock`
- [ ] `.mockRejectedValueOnce(value: unknown): Mock`
- [ ] `.mockReturnThis(): Mock`
- [ ] `.mockName(name: string): Mock`
- [ ] `.mockClear(): Mock`
- [ ] `.mockReset(): Mock`
- [ ] `.mockRestore(): Mock`
- [ ] `.getMockName(): string`

## Test context / lifecycle

- [ ] `ctx.skip(condition?: boolean, note?: string): void`
- [ ] `ctx.expect: Assertion` (scoped `expect` on the test context)
- [ ] `ctx.task: RunnerTestCase`
- [ ] `ctx.signal: AbortSignal`
- [ ] `ctx.onTestFailed(fn: () => void): void`
- [ ] `ctx.onTestFinished(fn: () => void): void`

## CLI / config surface

- [ ] `assertType<T>(value: T): void`
- [ ] `expectTypeOf(value: T): ExpectTypeOf<T>`
- [ ] `bench(name: string, fn: () => void, options?: BenchOptions): void`
- [ ] `suite(name: string, fn: () => void): void` (alias of `describe`)
