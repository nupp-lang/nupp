// The AudioWorklet half of `nupp-audio.mjs`: plays interleaved float samples
// the page hands it over its port, from a queue it keeps `bufferAheadMs` ahead.
//
// Playback starts once the queue holds the buffer-ahead, and starts again the
// same way after it runs dry. Each 128-frame quantum it could not fill whole is
// an underrun, counted and reported with the queue's depth.

class NuppStreamProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const {channels, bufferAheadFrames} = options.processorOptions;
    this.channels = channels;
    this.bufferAhead = bufferAheadFrames;
    this.chunks = [];
    this.offset = 0;
    this.queued = 0;
    this.playing = false;
    this.underruns = 0;
    this.played = 0;
    this.port.onmessage = (event) => {
      if (event.data === "stats") {
        this.port.postMessage({underruns: this.underruns, queuedFrames: this.queued, playedFrames: this.played});
        return;
      }
      const samples = event.data;
      this.chunks.push(samples);
      this.queued += samples.length / this.channels;
    };
  }

  process(_, outputs) {
    const output = outputs[0];
    const frames = output[0].length;
    if (!this.playing) {
      if (this.queued < this.bufferAhead) return true;
      this.playing = true;
    }
    for (let frame = 0; frame < frames; frame++) {
      if (this.chunks.length === 0) {
        this.underruns++;
        this.playing = false;
        for (const channel of output) channel.fill(0, frame);
        return true;
      }
      const chunk = this.chunks[0];
      for (let channel = 0; channel < output.length; channel++) {
        output[channel][frame] = chunk[this.offset + Math.min(channel, this.channels - 1)];
      }
      this.offset += this.channels;
      this.queued--;
      this.played++;
      if (this.offset >= chunk.length) {
        this.chunks.shift();
        this.offset = 0;
      }
    }
    return true;
  }
}

registerProcessor("nupp-stream", NuppStreamProcessor);
