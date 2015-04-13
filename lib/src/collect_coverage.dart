library bwu_coverage_viewer.src.collect_coverage;

import 'dart:io' as io;
import 'dart:async' show Completer, Future, Stream;
import 'dart:convert' show UTF8;
import 'package:bwu_utils/bwu_utils_server.dart';
import 'package:coverage/src/devtools.dart';
import 'package:coverage/src/util.dart';

Future<Map> collectCoverage(String script) async {
  final defaultTimeout = new Duration(seconds: 120);
  final port = await getNextFreeIpPort();

  onTimeout() {
    var timeout = defaultTimeout.inSeconds;
    throw 'Failed to collect coverage within ${timeout}s';
  }
  print('Current working directory: "${io.Directory.current.path}/${script}"');

  await startProcess(script, port);

  Future connected = retry(
      () => VMService.connect('localhost', port.toString()), retryInterval);
  final vmService =
      await connected.timeout(defaultTimeout, onTimeout: onTimeout);

  Future ready = waitIsolatesPaused(vmService);
  ready.timeout(defaultTimeout, onTimeout: onTimeout);
  await ready;
  final result = await getAllCoverage(vmService);
  await resumeIsolates(vmService);
  await vmService.close();
  return result;
}

Future resumeIsolates(VMService service) {
  return service
      .getVM()
      .then((vm) => vm.isolates.map((i) => service.resume(i.id)))
      .then(Future.wait);
}

Future<Map> getAllCoverage(VMService service) {
  return service
      .getVM()
      .then((vm) {
        return vm.isolates.map((i) => service.getCoverage(i.id));
      })
      .then(Future.wait)
      .then((responses) {
    // flatten response lists
    var allCoverage = responses.expand((c) => c.coverage).toList();
    return {'type': 'CodeCoverage', 'coverage': allCoverage,};
  });
}

const retryInterval = const Duration(milliseconds: 1000);

Future waitIsolatesPaused(VMService service) {
  allPaused() => service
      .getVM()
      .then((vm) => vm.isolates.map((i) => service.getIsolate(i.id)))
      .then(Future.wait)
      .then((isolates) => isolates.every((i) => i.paused))
      .then((paused) => paused ? paused : new Future.error(paused));
  return retry(allPaused, retryInterval);
}

Future startProcess(String script, int port) async {
  Completer completer = new Completer();
  final io.Process process = await io.Process
      .start('dart', ['--observe=${port}', '--pause_isolates_on_exit', script]);
  process.exitCode.then((exitCode) =>
      print('Script exit - code: ${exitCode}'));
  process.stdout.transform(UTF8.decoder).listen((data) {
    print(data);
    if(data.contains('All tests passed!')) {
      completer.complete();
    }
  });
  process.stderr.transform(UTF8.decoder).listen((data) {
    print(data);
  });
  return completer.future;
//    if (process.exitCode == 0) {
//      print('Script execution completed.');
//      print(process.stdout);
//      print(process.stderr);
//    } else {
//      print(process.stdout);
//      print(process.stderr);
//      throw 'Script execution failed with exit code ${process.exitCode}.';
//    }
//  });

}
