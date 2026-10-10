// The browser workloads `run.mjs bench` runs, in order. Sizes come from HC-0's
// measurement of real Tecs frames (see the plan's evidence): a world-rendering
// packet is 1.3 to 2.5 KiB, and 4,000 moving shapes or a UI frame 321 KiB.
// Seventeen pointer events a frame is a 1,000 Hz mouse at 60 Hz.
//
// "Channel boundary" frames wait on a host call for the next frame, as a game
// would; "timer boundary" frames add the channel beside a separate sleep, which
// is the worst case. Compare each against "frame boundary only".
export const workloads = [
  {name: "W1 call latency", program: "latency", options: {batch: 50, batches: 30}},
  {name: "frame boundary only", program: "streamFrames", options: {frames: 300, stub: true}},
  {name: "W2 input, every event, timer boundary", program: "streamFrames", options: {frames: 300, events: 17}},
  {name: "W2 input, latest, timer boundary", program: "streamFrames",
    options: {frames: 300, events: 17, inputPolicy: "latest"}},
  {name: "W2 input, latest, channel boundary", program: "channelFrames",
    options: {frames: 300, events: 17, inputPolicy: "latest"}},
  {name: "W4 small packet", program: "channelFrames",
    options: {frames: 300, events: 17, inputPolicy: "latest", packetBytes: 2 * 1024}},
  {name: "W4 typical packet", program: "channelFrames",
    options: {frames: 300, events: 17, inputPolicy: "latest", packetBytes: 320 * 1024}},
  {name: "W4 large packet", program: "channelFrames",
    options: {frames: 300, events: 17, inputPolicy: "latest", packetBytes: 1024 * 1024 - 64}},
  {name: "W5 representative frame", program: "channelFrames",
    options: {frames: 600, events: 17, inputPolicy: "latest", packetBytes: 2 * 1024, assetEvery: 60}},
  {name: "W5 heavy frame", program: "channelFrames",
    options: {frames: 600, events: 17, inputPolicy: "latest", packetBytes: 320 * 1024, assetEvery: 60}},
  {name: "W3b bulk 4 MiB", program: "bulk", options: {size: 4 * 1024 * 1024, repeats: 5}},
];
