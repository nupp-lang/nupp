export function loweredEntryName(name) {
  return name.replace(/[A-Z]/g, letter => '_' + letter.toLowerCase()).replace(/_+/g, '_');
}
