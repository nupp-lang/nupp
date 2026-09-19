export const DEFAULT_OPTIONS = Object.freeze({strict: true, optimize: true, dialect: 'luajit'});
export function restoreOptions(params = {}, saved = {}) {
  const options = {...DEFAULT_OPTIONS};
  for (const key of ['strict', 'optimize']) {
    if (typeof saved[key] === 'boolean') options[key] = saved[key];
    if (params[key] !== undefined) options[key] = params[key] === '1';
  }
  const dialect = params.dialect ?? saved.dialect;
  if (dialect === 'luajit' || dialect === 'lua51') options.dialect = dialect;
  const compat = params.compat ?? saved.compat;
  if (compat === 'lua51') { options.compat = compat; options.dialect = 'luajit'; }
  return options;
}
export function storedOptions() {
  try { return JSON.parse(localStorage.getItem('nupp-playground-options-v1') || '{}'); }
  catch { return {}; }
}
export function saveOptions(options) {
  try { localStorage.setItem('nupp-playground-options-v1', JSON.stringify(options)); } catch {}
}
