declare const test: {
  (
    name: string,
    callback: (() => void) | (() => Promise<void>),
    timeoutTime?: number,
  ): void;

  todo(
    name: string,
    callback: (() => void) | (() => Promise<void>),
    timeoutTime?: number,
  ): void;

  failing(
    name: string,
    callback: (() => void) | (() => Promise<void>),
    timeoutTime?: number,
  ): void;
  fail(
    name: string,
    callback: (() => void) | (() => Promise<void>),
    timeoutTime?: number,
  ): void;
  fails(
    name: string,
    callback: (() => void) | (() => Promise<void>),
    timeoutTime?: number,
  ): void;

  skipped(
    name: string,
    callback: (() => void) | (() => Promise<void>),
    timeoutTime?: number,
  ): void;
  skip(
    name: string,
    callback: (() => void) | (() => Promise<void>),
    timeoutTime?: number,
  ): void;
  skips(
    name: string,
    callback: (() => void) | (() => Promise<void>),
    timeoutTime?: number,
  ): void;
}

declare const it: typeof test;

type Assertions<T> = {
  /**
    * Does not throw when the expectation is false.
    */
  toBe(expected: T): void;
};

declare function expect<T>(received: T): {
  not: Assertions<T>;
} & Assertions<T>;

