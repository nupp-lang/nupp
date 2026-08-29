// Dart isolate echo benchmark mirroring bench/workers/src/main.nupp.
//
// One persistent worker isolate echoes each message back. Sequential
// round trips measure latency, matching the Nupp benchmark's warm
// spawn():await() loops: 9 measured samples after 2 warmups, median
// reported, 1000 operations per scalar sample and 300 per payload
// sample. Throughput counts request plus response bytes.
//
// Run: dart run echo_bench.dart

import 'dart:async';
import 'dart:isolate';

class Payload {
  final int id;
  final String label;
  final String bytes;
  Payload(this.id, this.label, this.bytes);
}

const samples = 9;
const warmups = 2;
const latencyTasks = 1000;
const payloadTasks = 300;

void worker(SendPort setup) {
  final inbox = ReceivePort();
  setup.send(inbox.sendPort);
  late SendPort replyTo;
  inbox.listen((message) {
    if (message is SendPort) {
      replyTo = message;
      return;
    }
    replyTo.send(message);
  });
}

double median(List<double> values) {
  values.sort();
  return values[values.length ~/ 2];
}

Future<void> main() async {
  final setup = ReceivePort();
  await Isolate.spawn(worker, setup.sendPort);
  final setupEvents = StreamIterator<Object?>(setup.cast<Object?>());
  await setupEvents.moveNext();
  final workerPort = setupEvents.current as SendPort;
  final replies = ReceivePort();
  workerPort.send(replies.sendPort);
  final events = StreamIterator<Object?>(replies.cast<Object?>());

  Future<Object?> roundTrip(Object? message) async {
    workerPort.send(message);
    await events.moveNext();
    return events.current;
  }

  Future<void> bench(
      String name, int operations, int bytes, Object? Function(int) make) async {
    final medians = <double>[];
    for (var sample = 0; sample < samples + warmups; sample++) {
      final watch = Stopwatch()..start();
      for (var index = 0; index < operations; index++) {
        await roundTrip(make(index));
      }
      watch.stop();
      if (sample >= warmups) {
        medians.add(watch.elapsedMicroseconds / operations);
      }
    }
    final perOp = median(medians);
    final throughput =
        bytes > 0 ? bytes * 2 / perOp * 1e6 / (1024 * 1024) : 0.0;
    print('${name.padRight(18)} ${perOp.toStringAsFixed(2).padLeft(9)} us/op '
        '${throughput.toStringAsFixed(2).padLeft(9)} MiB/s');
  }

  final text = 'abcdefgh' * 512;
  await bench('scalar', latencyTasks, 0, (index) => index);
  await bench('text 4 KiB', payloadTasks, text.length, (index) => text);
  await bench('record 4 KiB', payloadTasks, text.length,
      (index) => Payload(7, 'payload', text));
  await bench('record small', payloadTasks, 0,
      (index) => Payload(7, 'payload', 'bytes'));
  replies.close();
  setup.close();
}
