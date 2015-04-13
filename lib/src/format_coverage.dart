library bwu_coverage_viewer.src.format_coverage;

import 'dart:async' show Future, Stream, StreamConsumer, Completer;
import 'package:coverage/coverage.dart' as cv;

/// [Environment] stores gathered arguments information.
class Environment {
  String sdkRoot;
  String pkgRoot = '.';
  String input;
  Map output;
  int workers;
  bool expectMarkers;
  bool verbose = false;
}

Future<Environment> formatCoverage(Environment env, Map json) async {
  int start = new DateTime.now().millisecondsSinceEpoch;
  if (env.verbose) {
    print('Environment:');
    //print('  # files: ${files.length}');
    print('  # workers: ${env.workers}');
    print('  sdk-root: ${env.sdkRoot}');
    print('  package-root: ${env.pkgRoot}');
  }

  final hitmap = cv.createHitmap(json['coverage']);
  // All workers are done. Process the data.
  if (env.verbose) {
    final end = new DateTime.now().millisecondsSinceEpoch;
    print('Done creating a global hitmap. Took ${end - start} ms.');
  }

  //Future out;
  var resolver =
      new cv.Resolver(packageRoot: env.pkgRoot, sdkRoot: env.sdkRoot);
  var loader = new cv.Loader();

  env.output = await new DataFormatter(resolver, loader).format(hitmap);

  env.output['end'] = new DateTime.now().millisecondsSinceEpoch;
  env.output['start'] = start;
  return env;
}

/// Converts the given hitmap to a pretty-print format and appends the result
/// to env.output.
///
/// Returns a [Future] that completes as soon as all map entries have been
/// emitted.
class DataFormatter {
  final cv.Resolver resolver;
  final cv.Loader loader;
  DataFormatter(this.resolver, this.loader);

  Future<Map> format(Map hitMap) {
    var buf = {};
    var emitOne = (key) {
      var v = hitMap[key];
      var c = new Completer();
      var uri = resolver.resolve(key);
      if (uri == null) {
        c.complete();
      } else {
        loader.load(uri).then((lines) {
          if (lines == null) {
            c.complete();
            return;
          }
          buf['uri'] = uri;
          final resultLines = [];
          buf['lines'] = resultLines;
          for (var line = 1; line <= lines.length; line++) {
            final resultLine = {};
            if (v.containsKey(line)) {
              resultLine['count'] = v[line];
            }
            resultLine['code'] = lines[line - 1];
            resultLines.add(resultLine);
          }
          c.complete();
        });
      }
      return c.future;
    };
    return Future.forEach(hitMap.keys, emitOne).then((_) => buf);
  }
}
