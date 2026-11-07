import {adoptPortEndpoint} from "../../../../../runtime/wasm/channel.mjs";

let endpoint;
let total;
function wait(requiredBytes = 0) {
  return new Promise(resolve => endpoint.subscribe(resolve, requiredBytes));
}
async function run() {
  if (endpoint.direction === "sender") {
    for (let index = 0; index < total; index++) {
      const payload = new Uint8Array(4);
      new DataView(payload.buffer).setUint32(0, index, true);
      while (endpoint.trySend(payload).status === "full") await wait(4);
    }
    endpoint.close();
    self.postMessage({type: "finished", role: "sender", count: total, finishedAt: Date.now()});
    return;
  }
  let count = 0;
  while (true) {
    const message = endpoint.tryReceive();
    if (message.status === "empty") {
      await wait();
      continue;
    }
    if (message.status === "closed") break;
    if (new DataView(message.value.buffer, message.value.byteOffset, 4).getUint32(0, true) !== count) {
      throw new Error("direct port delivery lost FIFO order");
    }
    count++;
  }
  endpoint.close();
  self.postMessage({type: "finished", role: "receiver", count, finishedAt: Date.now()});
}
self.addEventListener("message", event => {
  if (event.data.type === "setup") {
    endpoint = adoptPortEndpoint(event.data.endpoint);
    total = event.data.total;
    self.postMessage({type: "ready"});
  } else if (event.data.type === "go") {
    run().catch(error => self.postMessage({type: "failed", error: String(error.stack || error)}));
  }
});
