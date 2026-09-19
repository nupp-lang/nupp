export function describeError(error) {
  if (!(error instanceof Error)) return String(error);
  if (!error.stack) return error.message;
  return error.stack.includes(error.message)
    ? error.stack
    : `${error.message}\n${error.stack}`;
}
