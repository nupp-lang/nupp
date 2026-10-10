// Host handlers loaded into the application's Worker by relay.mjs.
const outbound = [];
let push = null;

export const handlers = {
  "test.echo": (args) => args,
  "test.results": () => [null, 2, null],
  "test.pushInput": ([count]) => {
    for (let index = 1; index <= count; index++) push("test.move", index, index * 10);
    push("test.key", "a", true);
    push("test.key", "b", false);
  },
  "test.packet": ([bytes]) => { outbound.push(`packet:${bytes.length}`); },
  "test.log": ([text]) => { outbound.push(`log:${text}`); },
  "test.block": ([text]) => { outbound.push(`block:${text}`); },
  "test.outbound": () => outbound.join(" "),
};

export function start(api) {
  push = api.push;
}
