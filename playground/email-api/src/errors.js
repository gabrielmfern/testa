// Errors mirror Resend's HTTP error shape: { statusCode, name, message }.
// `name` doubles as the machine-readable error code (Resend does this too).
export class ApiError extends Error {
  constructor(statusCode, name, message) {
    super(message);
    this.statusCode = statusCode;
    this.name = name;
  }

  toJSON() {
    return { statusCode: this.statusCode, name: this.name, message: this.message };
  }
}

export const validationError = (message) => new ApiError(422, "validation_error", message);
export const notFound = (message) => new ApiError(404, "not_found", message);
