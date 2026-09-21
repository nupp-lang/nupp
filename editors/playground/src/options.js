export const DEFAULT_OPTIONS = Object.freeze({strict: true, optimize: true, dialect: 'luajit'});
function record(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value : {};
}
export function restoreOptions(params = {}, saved = {}) {
  params = record(params);
  saved = record(saved);
  const options = {...DEFAULT_OPTIONS};
  for (const key of ['strict', 'optimize']) {
    if (typeof saved[key] === 'boolean') options[key] = saved[key];
    if (params[key] !== undefined) options[key] = params[key] === '1';
  }
  // An old explicit runtime link does not select a lowerer anymore, but it
  // must not inherit an unrelated compatibility preference from the reader.
  const legacyDialect = params.dialect === 'luajit' || params.dialect === 'lua51';
  const compat = params.compat !== undefined ? params.compat : legacyDialect ? undefined : saved.compat;
  if (compat === 'lua51') {
    options.compat = compat;
  }
  return options;
}
export function sourceFragment(source, options = DEFAULT_OPTIONS) {
  const restored = restoreOptions({}, options);
  // Defaults are explicit so the recipient's saved preferences cannot change
  // the program's behavior. Empty compat also clears a saved compatibility mode.
  return '#source=' + encodeURIComponent(source) +
    `&strict=${restored.strict ? '1' : '0'}&optimize=${restored.optimize ? '1' : '0'}` +
    `&compat=${restored.compat || ''}`;
}
export function storedOptions() {
  try { return record(JSON.parse(localStorage.getItem('nupp-playground-options-v1') || '{}')); }
  catch { return {}; }
}
export function saveOptions(options) {
  try { localStorage.setItem('nupp-playground-options-v1', JSON.stringify(options)); } catch {}
}
