export const DEFAULT_OPTIONS = Object.freeze({strict: true, optimize: true, dialect: 'luajit'});
function record(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value : {};
}
function validDialect(value) {
  return value === 'luajit' || value === 'lua51' ? value : undefined;
}
export function restoreOptions(params = {}, saved = {}) {
  params = record(params);
  saved = record(saved);
  const options = {...DEFAULT_OPTIONS};
  for (const key of ['strict', 'optimize']) {
    if (typeof saved[key] === 'boolean') options[key] = saved[key];
    if (params[key] !== undefined) options[key] = params[key] === '1';
  }
  const linkedDialect = validDialect(params.dialect);
  options.dialect = linkedDialect ?? validDialect(saved.dialect) ?? options.dialect;
  // Old source-only links inherit preferences. An explicit runtime link starts
  // with that runtime's defaults, and an explicit legacy link stays a rollback.
  const compat = params.compat !== undefined ? params.compat : linkedDialect ? undefined : saved.compat;
  if (compat === 'lua51' && linkedDialect !== 'lua51' &&
      (params.compat === 'lua51' || options.dialect !== 'lua51')) {
    options.compat = compat;
    options.dialect = 'luajit';
  }
  return options;
}
export function sourceFragment(source, options = DEFAULT_OPTIONS) {
  const restored = restoreOptions({}, options);
  // Defaults are explicit so the recipient's saved preferences cannot change
  // the program's behavior. Empty compat also clears a saved compatibility mode.
  return '#source=' + encodeURIComponent(source) +
    `&strict=${restored.strict ? '1' : '0'}&optimize=${restored.optimize ? '1' : '0'}` +
    `&dialect=${restored.dialect}&compat=${restored.compat || ''}`;
}
export function storedOptions() {
  try { return record(JSON.parse(localStorage.getItem('nupp-playground-options-v1') || '{}')); }
  catch { return {}; }
}
export function saveOptions(options) {
  try { localStorage.setItem('nupp-playground-options-v1', JSON.stringify(options)); } catch {}
}
