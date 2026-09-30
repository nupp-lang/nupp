// The symbol tail the compiler emits for an entry, mirroring `identifierTail` in
// src/nupp/compiler/aot/scalar.nupp. A name outside the canonical lower-camel
// form carries its source bytes in hex, so it is not recoverable by snake-casing.
export function loweredEntryName(name) {
  const bytes = Buffer.from(name, 'utf8').toString('latin1');
  const snake = bytes.replace(/([A-Z])([A-Z][a-z])/g, '$1_$2').replace(/([a-z])([A-Z])/g, '$1_$2')
    .replace(/[^A-Za-z0-9_]/g, '_').toLowerCase();
  const canonical = snake.replace(/_([a-z0-9])/g, (_, character) => character.toUpperCase());
  if (canonical === bytes) return snake;
  return `${snake}__${Buffer.from(bytes, 'latin1').toString('hex')}`;
}
