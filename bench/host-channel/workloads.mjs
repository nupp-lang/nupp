// The browser workloads `run.mjs bench` runs, in order. Packet sizes come from
// HC-0's measurement of a real Tecs frame; see the plan's evidence.
export const workloads = [
  {name: "W1 call latency", program: "latency", options: {batch: 50, batches: 30}},
  {name: "frame, channel stubbed", program: "frames", options: {frames: 300, stub: true}},
  {name: "W2 input only", program: "frames", options: {frames: 300, events: 17}},
  {name: "W4 small packet", program: "frames", options: {frames: 300, events: 17, packetBytes: 16 * 1024}},
  {name: "W4 typical packet", program: "frames", options: {frames: 300, events: 17, packetBytes: 128 * 1024}},
  {name: "W4 large packet", program: "frames", options: {frames: 300, events: 17, packetBytes: 1024 * 1024}},
  {name: "W5 representative frame", program: "frames",
    options: {frames: 600, events: 17, packetBytes: 128 * 1024, assetEvery: 60}},
  {name: "W3b bulk 4 MiB", program: "bulk", options: {size: 4 * 1024 * 1024, repeats: 5}},
];
