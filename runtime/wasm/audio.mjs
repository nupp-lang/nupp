// Audio for a packaged Nupp browser application, shipped as `nupp-audio.mjs`.
//
// The application sends interleaved 32-bit float samples on an outbound
// `nupp.host` stream; this answers that stream on the page, where audio lives,
// and plays it through an AudioWorklet that keeps `bufferAheadMs` queued. No
// SharedArrayBuffer and no cross-origin isolation are needed: each chunk is
// transferred to the worklet once.
//
//   import {run} from "./nupp-browser-app.mjs";
//   import {audioStream} from "./nupp-audio.mjs";
//   const audio = await audioStream({kind: "app.audio"});
//   await run({host: {handlers: {...audio.handlers}}});
//
// The buffer-ahead is the latency: what the application sends now is heard that
// much later. It is also what a stalled frame can spend before the queue runs
// dry, because samples arrive only as fast as the application makes them.

/**
 * Opens an audio stream answering `kind`.
 *
 * @param {object} options
 * @param {string} options.kind the outbound stream the application sends on
 * @param {number} [options.channels=2] interleaved channels per frame
 * @param {number} [options.bufferAheadMs=50] how far ahead playback stays; below 50 ms the
 *     real guest underran even without a stalled frame
 * @param {AudioContext} [options.context] an existing context to play through
 */
export async function audioStream(options = {}) {
  const {kind, channels = 2, bufferAheadMs = 50} = options;
  if (typeof kind !== "string") throw new Error("an audio stream needs the kind the application sends on");
  if (!Number.isInteger(channels) || channels < 1 || channels > 8) throw new Error("audio channels must be 1 to 8");
  if (!(bufferAheadMs > 0)) throw new Error("bufferAheadMs must be positive");
  const context = options.context || new AudioContext();
  await context.audioWorklet.addModule(new URL("./nupp-audio-worklet.mjs", import.meta.url));
  const node = new AudioWorkletNode(context, "nupp-stream", {
    numberOfInputs: 0,
    outputChannelCount: [channels],
    processorOptions: {channels, bufferAheadFrames: Math.round(context.sampleRate * bufferAheadMs / 1000)},
  });
  node.connect(context.destination);
  let pending = null;
  node.port.onmessage = (event) => {
    pending?.(event.data);
    pending = null;
  };
  return {
    context,
    node,
    sampleRate: context.sampleRate,
    handlers: {
      [kind]([bytes]) {
        if (!(bytes instanceof Uint8Array) || bytes.byteLength % (4 * channels) !== 0) {
          throw new Error(`audio stream ${kind} sends whole frames of ${channels} float samples`);
        }
        // Copy into its own buffer, aligned, and hand the buffer over.
        const samples = new Float32Array(bytes.byteLength / 4);
        new Uint8Array(samples.buffer).set(bytes);
        node.port.postMessage(samples, [samples.buffer]);
      },
    },
    /** Underruns so far, and the frames queued and played. */
    stats() {
      return new Promise((resolve) => {
        pending = resolve;
        node.port.postMessage("stats");
      });
    },
    close() {
      node.disconnect();
      return options.context ? undefined : context.close();
    },
  };
}
