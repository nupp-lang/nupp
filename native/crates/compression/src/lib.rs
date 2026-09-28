//! Bounded, allocation-free-at-the-boundary DEFLATE-family stream state.

use flate2::{Compress, Compression, Decompress, FlushCompress, FlushDecompress, Status};
use std::fmt;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Format {
    Gzip,
    Zlib,
    DeflateRaw,
}

impl Format {
    pub fn from_abi(value: u32) -> Option<Self> {
        match value {
            1 => Some(Self::Gzip),
            2 => Some(Self::Zlib),
            3 => Some(Self::DeflateRaw),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
pub enum StepStatus {
    NeedInput = 1,
    NeedOutput = 2,
    Finished = 3,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Step {
    pub consumed: usize,
    pub written: usize,
    pub status: StepStatus,
}

#[derive(Debug)]
pub struct StreamError(String);

impl StreamError {
    fn encoder(error: flate2::CompressError) -> Self {
        Self(error.to_string())
    }

    fn decoder(error: flate2::DecompressError) -> Self {
        Self(error.to_string())
    }
}

impl fmt::Display for StreamError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl std::error::Error for StreamError {}

/// Output room a flush is always given. zlib starts a fresh empty block on
/// every flush call that ends with its output full, so a flush that only
/// ever has a few bytes of room never ends; below this much room, a flush is
/// produced into a staging buffer and handed out from there.
const FLUSH_ROOM: usize = 64;

pub struct Encoder {
    stream: Compress,
    finished: bool,
    /// Flushed bytes not yet handed to the caller, and how many of them were.
    staged: Vec<u8>,
    delivered: usize,
}

impl Encoder {
    pub fn new(format: Format, level: u32) -> Self {
        let level = Compression::new(level);
        let stream = match format {
            Format::Gzip => Compress::new_gzip(level, 15),
            Format::Zlib => Compress::new(level, true),
            Format::DeflateRaw => Compress::new(level, false),
        };
        Self {
            stream,
            finished: false,
            staged: Vec::new(),
            delivered: 0,
        }
    }

    pub fn write(&mut self, input: &[u8], output: &mut [u8]) -> Result<Step, StreamError> {
        self.after_staged(input, output, FlushCompress::None)
    }

    pub fn flush(&mut self, output: &mut [u8]) -> Result<Step, StreamError> {
        if let Some(step) = self.deliver_staged(output) {
            return Ok(step);
        }
        if self.finished || output.len() >= FLUSH_ROOM {
            return self.step(&[], output, FlushCompress::Sync);
        }
        let mut room = [0u8; FLUSH_ROOM];
        loop {
            let before = self.stream.total_out();
            self.stream
                .compress(&[], &mut room, FlushCompress::Sync)
                .map_err(StreamError::encoder)?;
            let made = (self.stream.total_out() - before) as usize;
            self.staged.extend_from_slice(&room[..made]);
            if made < room.len() {
                break;
            }
        }
        Ok(self.deliver_staged(output).unwrap_or(Step {
            consumed: 0,
            written: 0,
            status: StepStatus::NeedInput,
        }))
    }

    pub fn finish(&mut self, output: &mut [u8]) -> Result<Step, StreamError> {
        self.after_staged(&[], output, FlushCompress::Finish)
    }

    /// Delivers any staged flush bytes first, then goes on with `flush` in
    /// whatever room is left.
    fn after_staged(
        &mut self,
        input: &[u8],
        output: &mut [u8],
        flush: FlushCompress,
    ) -> Result<Step, StreamError> {
        let delivered = match self.deliver_staged(output) {
            None => 0,
            Some(step) if step.status == StepStatus::NeedOutput => return Ok(step),
            Some(step) => step.written,
        };
        let mut step = self.step(input, &mut output[delivered..], flush)?;
        step.written += delivered;
        if step.status == StepStatus::NeedInput
            && step.written == output.len()
            && !output.is_empty()
        {
            step.status = StepStatus::NeedOutput;
        }
        Ok(step)
    }

    /// Hands out staged flush bytes. Until they are all delivered, every call
    /// only delivers them: needing output while some remain, and reporting
    /// the flush done once the last of them is out.
    fn deliver_staged(&mut self, output: &mut [u8]) -> Option<Step> {
        if self.delivered == self.staged.len() {
            return None;
        }
        let remaining = &self.staged[self.delivered..];
        let written = remaining.len().min(output.len());
        output[..written].copy_from_slice(&remaining[..written]);
        self.delivered += written;
        let status = if self.delivered == self.staged.len() {
            self.staged.clear();
            self.delivered = 0;
            StepStatus::NeedInput
        } else {
            StepStatus::NeedOutput
        };
        Some(Step {
            consumed: 0,
            written,
            status,
        })
    }

    fn step(
        &mut self,
        input: &[u8],
        output: &mut [u8],
        flush: FlushCompress,
    ) -> Result<Step, StreamError> {
        if self.finished {
            return Ok(Step {
                consumed: 0,
                written: 0,
                status: StepStatus::Finished,
            });
        }
        let before_in = self.stream.total_in();
        let before_out = self.stream.total_out();
        let status = self
            .stream
            .compress(input, output, flush)
            .map_err(StreamError::encoder)?;
        let consumed = (self.stream.total_in() - before_in) as usize;
        let written = (self.stream.total_out() - before_out) as usize;
        let status = if status == Status::StreamEnd {
            self.finished = true;
            StepStatus::Finished
        } else if written == output.len() && !output.is_empty() {
            StepStatus::NeedOutput
        } else {
            StepStatus::NeedInput
        };
        Ok(Step {
            consumed,
            written,
            status,
        })
    }
}

pub struct Decoder {
    format: Format,
    stream: Decompress,
    concatenated_members: bool,
    member_finished: bool,
    /// Whether a whole member has ended, so later bytes follow a complete
    /// stream rather than being part of the first one.
    completed_member: bool,
    finished: bool,
}

impl Decoder {
    pub fn new(format: Format, concatenated_members: bool) -> Self {
        Self {
            format,
            stream: Self::stream(format),
            concatenated_members: format == Format::Gzip && concatenated_members,
            member_finished: false,
            completed_member: false,
            finished: false,
        }
    }

    fn stream(format: Format) -> Decompress {
        match format {
            Format::Gzip => Decompress::new_gzip(15),
            Format::Zlib => Decompress::new(true),
            Format::DeflateRaw => Decompress::new(false),
        }
    }

    pub fn read(&mut self, input: &[u8], output: &mut [u8]) -> Result<Step, StreamError> {
        if self.finished {
            return Ok(Step {
                consumed: 0,
                written: 0,
                status: StepStatus::Finished,
            });
        }

        let mut consumed = 0;
        let mut written = 0;
        while consumed < input.len() && written < output.len() {
            if self.member_finished {
                if !self.concatenated_members {
                    self.finished = true;
                    break;
                }
                self.stream = Self::stream(self.format);
                self.member_finished = false;
            }
            let before_in = self.stream.total_in();
            let before_out = self.stream.total_out();
            let status = self
                .stream
                .decompress(
                    &input[consumed..],
                    &mut output[written..],
                    FlushDecompress::None,
                )
                .map_err(StreamError::decoder)?;
            let took = (self.stream.total_in() - before_in) as usize;
            let made = (self.stream.total_out() - before_out) as usize;
            consumed += took;
            written += made;
            if status == Status::StreamEnd {
                self.member_finished = true;
                self.completed_member = true;
                if !self.concatenated_members {
                    self.finished = true;
                    break;
                }
                continue;
            }
            if took == 0 && made == 0 {
                break;
            }
        }

        let status = if self.finished {
            StepStatus::Finished
        } else if written == output.len() && !output.is_empty() {
            StepStatus::NeedOutput
        } else {
            StepStatus::NeedInput
        };
        Ok(Step {
            consumed,
            written,
            status,
        })
    }

    pub fn finish_input(&mut self, output: &mut [u8]) -> Result<Step, StreamError> {
        if self.finished || self.member_finished {
            self.finished = true;
            return Ok(Step {
                consumed: 0,
                written: 0,
                status: StepStatus::Finished,
            });
        }
        let before_out = self.stream.total_out();
        let status = self
            .stream
            .decompress(&[], output, FlushDecompress::Finish)
            .map_err(StreamError::decoder)?;
        let written = (self.stream.total_out() - before_out) as usize;
        if status == Status::StreamEnd {
            self.finished = true;
        } else if self.completed_member && written == 0 {
            // Bytes after a complete member began another that never
            // finished. That is trailing data, not a truncated stream.
            return Err(StreamError(
                "compressed stream has trailing bytes that are not a complete member".to_owned(),
            ));
        }
        Ok(Step {
            consumed: 0,
            written,
            status: if self.finished {
                StepStatus::Finished
            } else if written == output.len() && !output.is_empty() {
                StepStatus::NeedOutput
            } else {
                StepStatus::NeedInput
            },
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn encode(format: Format, input: &[u8], chunk: usize) -> Vec<u8> {
        let mut encoder = Encoder::new(format, 6);
        let mut answer = Vec::new();
        let mut at = 0;
        while at < input.len() {
            let mut output = vec![0; chunk];
            let step = encoder.write(&input[at..], &mut output).unwrap();
            at += step.consumed;
            answer.extend_from_slice(&output[..step.written]);
        }
        loop {
            let mut output = vec![0; chunk];
            let step = encoder.finish(&mut output).unwrap();
            answer.extend_from_slice(&output[..step.written]);
            if step.status == StepStatus::Finished {
                return answer;
            }
        }
    }

    fn decode(format: Format, input: &[u8], chunk: usize) -> Vec<u8> {
        let mut decoder = Decoder::new(format, true);
        let mut answer = Vec::new();
        let mut at = 0;
        while at < input.len() {
            let mut output = vec![0; chunk];
            let step = decoder.read(&input[at..], &mut output).unwrap();
            at += step.consumed;
            answer.extend_from_slice(&output[..step.written]);
            if step.status == StepStatus::Finished {
                assert_eq!(at, input.len());
                return answer;
            }
        }
        let mut output = vec![0; chunk];
        let step = decoder.finish_input(&mut output).unwrap();
        answer.extend_from_slice(&output[..step.written]);
        assert_eq!(step.status, StepStatus::Finished);
        answer
    }

    #[test]
    fn round_trips_every_format_across_one_byte_boundaries() {
        let input = b"a bounded stream can cross any input and output boundary";
        for format in [Format::Gzip, Format::Zlib, Format::DeflateRaw] {
            let compressed = encode(format, input, 1);
            assert_eq!(decode(format, &compressed, 1), input);
        }
    }

    #[test]
    fn a_flush_finishes_with_any_output_room() {
        // Under five bytes of room, zlib starts a fresh empty block on every
        // flush call, so a flush that only ever had that much never ended.
        for room in 1..=8 {
            let mut encoder = Encoder::new(Format::Gzip, 6);
            let mut encoded = Vec::new();
            let mut output = vec![0; 64];
            let step = encoder.write(b"hello", &mut output).unwrap();
            assert_eq!(step.consumed, 5);
            encoded.extend_from_slice(&output[..step.written]);
            let mut output = vec![0; room];
            let mut calls = 0;
            loop {
                calls += 1;
                assert!(
                    calls < 1000,
                    "a flush with {room} bytes of room never finished"
                );
                let step = encoder.flush(&mut output).unwrap();
                encoded.extend_from_slice(&output[..step.written]);
                if step.status != StepStatus::NeedOutput {
                    break;
                }
            }
            let mut output = vec![0; 64];
            loop {
                let step = encoder.finish(&mut output).unwrap();
                encoded.extend_from_slice(&output[..step.written]);
                if step.status == StepStatus::Finished {
                    break;
                }
            }
            assert_eq!(decode(Format::Gzip, &encoded, 7), b"hello");
        }
    }

    #[test]
    fn bytes_staged_by_an_unfinished_flush_come_out_first() {
        let mut encoder = Encoder::new(Format::Zlib, 6);
        let mut encoded = Vec::new();
        let mut output = vec![0; 64];
        let step = encoder.write(b"hello", &mut output).unwrap();
        encoded.extend_from_slice(&output[..step.written]);
        let mut small = [0; 2];
        let step = encoder.flush(&mut small).unwrap();
        assert_eq!(step.status, StepStatus::NeedOutput);
        encoded.extend_from_slice(&small[..step.written]);
        let step = encoder.write(b"abc", &mut output).unwrap();
        assert_eq!(step.consumed, 3);
        encoded.extend_from_slice(&output[..step.written]);
        loop {
            let step = encoder.finish(&mut output).unwrap();
            encoded.extend_from_slice(&output[..step.written]);
            if step.status == StepStatus::Finished {
                break;
            }
        }
        assert_eq!(decode(Format::Zlib, &encoded, 5), b"helloabc");
    }

    #[test]
    fn bytes_after_a_complete_member_are_trailing_not_truncation() {
        let mut encoded = encode(Format::Gzip, b"hello", 64);
        encoded.push(0x1f);
        let mut decoder = Decoder::new(Format::Gzip, true);
        let mut output = [0; 64];
        let step = decoder.read(&encoded, &mut output).unwrap();
        assert_eq!(&output[..step.written], b"hello");
        assert_eq!(step.consumed, encoded.len());
        let error = decoder.finish_input(&mut output).unwrap_err();
        assert!(error.to_string().contains("trailing bytes"), "{error}");
    }

    #[test]
    fn validates_trailers_and_truncation() {
        let mut compressed = encode(Format::Gzip, b"hello", 3);
        compressed.pop();
        let mut decoder = Decoder::new(Format::Gzip, true);
        let mut output = [0; 64];
        let step = decoder.read(&compressed, &mut output).unwrap();
        assert_ne!(step.status, StepStatus::Finished);
        assert_ne!(
            decoder.finish_input(&mut output).unwrap().status,
            StepStatus::Finished
        );

        let mut damaged = encode(Format::Gzip, b"hello", 3);
        let last = damaged.len() - 1;
        damaged[last] ^= 1;
        let mut decoder = Decoder::new(Format::Gzip, true);
        assert!(decoder.read(&damaged, &mut output).is_err());
    }

    #[test]
    fn decodes_concatenated_gzip_members() {
        let mut joined = encode(Format::Gzip, b"hello", 2);
        joined.extend(encode(Format::Gzip, b" world", 2));
        assert_eq!(decode(Format::Gzip, &joined, 2), b"hello world");
    }

    #[test]
    fn decodes_independent_standard_fixtures() {
        let gzip = [
            0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xcb, 0x48, 0xcd, 0xc9,
            0xc9, 0x07, 0x00, 0x86, 0xa6, 0x10, 0x36, 0x05, 0x00, 0x00, 0x00,
        ];
        let zlib = [
            0x78, 0x9c, 0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0x07, 0x00, 0x06, 0x2c, 0x02, 0x15,
        ];
        let raw = [0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0x07, 0x00];
        assert_eq!(decode(Format::Gzip, &gzip, 2), b"hello");
        assert_eq!(decode(Format::Zlib, &zlib, 2), b"hello");
        assert_eq!(decode(Format::DeflateRaw, &raw, 2), b"hello");
    }
}
