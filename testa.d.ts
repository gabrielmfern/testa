declare const test: {
  (
    name: string, 
    callback: (() => void) | (() => Promise<void>),
    timeoutTime?: number,
  ): void;
  fails(
    name: string, 
    callback: (() => void) | (() => Promise<void>),
    timeoutTime?: number,
  ): void;
  skip(
    name: string, 
    callback: (() => void) | (() => Promise<void>),
    timeoutTime?: number,
  ): void;
}

declare function expect<T>(received: T): {
  /**
    * Does not throw when the expectation is false.
    */
  toBe(expected: T): void;
};

