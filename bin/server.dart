// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:io' as io;
import 'dart:async' show Future, Stream;
import 'package:path/path.dart' as path;
import 'package:args/args.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:bwu_coverage_viewer/bwu_coverage_viewer.dart';

import 'package:logging/logging.dart' show Logger, Level;
import 'package:quiver_log/log.dart' show BASIC_LOG_FORMATTER, PrintAppender;
import 'package:stack_trace/stack_trace.dart' show Chain;

final _log = new Logger('bwu_coverage_viewer.bin.show_coverage');

void main(List<String> args) {
  Logger.root.level = Level.FINEST;
  var appender = new PrintAppender(BASIC_LOG_FORMATTER);
  appender.attachLogger(Logger.root);

  Chain.capture(() => _main(args), onError: (error, stack) {
    _log.shout(error);
    _log.shout(stack.terse);
  });
}

_main(List<String> args) async {
  var parser = new ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '9999');

  var result = parser.parse(args);

  var port = int.parse(result['port'], onError: (val) {
    io.stdout.writeln('Could not parse port value "$val" into a number.');
    io.exit(1);
  });

  var handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addHandler(requestHandler);

  io.serve(handler, 'localhost', port).then((server) {
    print('Serving at http://${server.address.host}:${server.port}');
  });
}

Future<shelf.Response> requestHandler(shelf.Request request) async {
  if (request.url.path.endsWith('favicon.ico')) {
    return new shelf.Response.notFound('Not found');
  }
  final files = await getFiles();
  final html = createPage(files);

  return new shelf.Response.ok(html,
      headers: {'Content-Type': 'text/html; charset=utf-8'});
}

Future<List<FileEntry>> getFiles() async {
  final json = await collectCoverage('test/all.dart');

  final result = <FileEntry>[];
  final fileList =
      new io.Directory(path.join(io.Directory.current.absolute.path, 'lib'))
          .list(recursive: true, followLinks: false);
  final testFileList =
      new io.Directory(path.join(io.Directory.current.absolute.path, 'test'))
          .list(recursive: true, followLinks: false);

  final pkgRoot = path.join(io.Directory.current.path, 'packages');
  await for (io.FileSystemEntity file in fileList) {
    if (file.path.endsWith('.dart')) {
      var filePath = file.path.substring(
          path.join(io.Directory.current.absolute.path, 'lib/').length);

      final cov = json['coverage']
          .where((m) =>
              m['source'] == 'package:bwu_datastore_connection/${filePath}')
          .toList();

      Environment env;
      if (cov.isNotEmpty) {
        env = await formatCoverage(new Environment()..pkgRoot = pkgRoot, {
          'type': 'CodeCoverage',
          'coverage': cov
        });
      } else {
        env = new Environment()..output = {'lines': []};
      }
      result.add(new FileEntry(path.join('lib', filePath), env.output, cov));
    }
  }

  await for (io.FileSystemEntity file in testFileList) {
    if (file.path.endsWith('.dart')) {
      var filePath = file.path.substring(
          path.join(io.Directory.current.absolute.path, 'test/').length);

      final cov = json['coverage']
          .where((m) => m['source'] == 'file://${file.path}')
          .toList();
      Environment env;
      if (cov.isNotEmpty) {
        env = await formatCoverage(new Environment()..pkgRoot = pkgRoot, {
          'type': 'CodeCoverage',
          'coverage': cov
        });
      } else {
        env = new Environment()..output = {'lines': []};
      }
      result.add(new FileEntry(path.join('test', filePath), env.output, cov));
    }
  }

  return result;
}

class FileEntry {
  final String path;
  final Map data;
  final List coverage;
  double _coveragePercent;
  double get coveragePercent {
    if (_html == null) {
      html;
    }
    return _coveragePercent;
  }

  FileEntry(this.path, this.data, this.coverage);

  String _html;
  String get html {
    if (_html == null) {
      int executableLinesCount = 0;
      int executedLinesCount = 0;

      StringBuffer buf = new StringBuffer();
      buf.write(
          '<table class="code"><thead><tr><th colspan="2"><a name="${path}">${path}</a></th><tr></thead><tbody>');
      final lines = data['lines'] != null ? data['lines'] : [];
      for (int i = 0; i < lines.length; i++) {
        //buf.write('<tr>');
        final hitCount = lines[i]['count'];
        final code = lines[i]['code'];
        String hitClass;
        if (hitCount != null) {
          executableLinesCount++;
          hitClass = 'missed';
          if (hitCount != 0) {
            executedLinesCount++;
            hitClass = 'executed';
          }
          buf.write(
              '<tr class="${hitClass}"><td class="hitcount"><pre>${hitCount}</pre></td>');
        } else {
          buf.write('<tr class="deadcode"><td class="hitcount"></td>');
        }
        buf.writeln('<td class="code"><pre>${code}</pre></td></tr>');
      }
      buf.writeln('</tbody></table>');
      if (executableLinesCount > 0 && executedLinesCount > 0) {
        _coveragePercent =
            (executedLinesCount / (executableLinesCount / 100)).roundToDouble();
      } else {
        _coveragePercent = 0.0;
      }

      _html = buf.toString();
    }
    return _html;
  }
}

String createPage(List<FileEntry> files) {
  StringBuffer pageBuf = new StringBuffer();
  StringBuffer bodyBuf = new StringBuffer();
  pageBuf.write('''
<!DOCTYPE html>
  <html>
    <head>
      <style>
        pre {
          padding-left: 7px;
          margin: 0;
        }
        div.hr {
          height: 20px;
        }
        table.filelist td.coverage-percent {
          text-align: right;
        }
        table.code th {
          background-color: cornflowerblue;
        }
        table.code td.hitcount {
          background-color: lightblue;
          text-align: right;
        }
        table.code {
          border: 0px;
          border-collapse: collapse;
          background-color: lightgray;
        }
        table.code tr.executed  td.code{
          background-color: rgba(0,255,0,0.5);
        }
        table.code tr.missed td.code {
          background-color: rgba(255,0,0,0.5);
        }

      </style>
    </head><body><table class="filelist"><thead><tr><th>File</th><th>Coverage %</th></tr></thead><tbody>''');
  files.forEach((f) {
    pageBuf.write(
        '<tr><td ><a href="#${f.path}">${f.path}</a></td><td class="coverage-percent">${f.coveragePercent}</td></tr></thead>');
    bodyBuf.write('<div class="hr"></div>');
    bodyBuf.write(f.html);
  });
  pageBuf.write('</tbody></table>');
  pageBuf.write(bodyBuf);
  pageBuf.write('</body></html>');
  return pageBuf.toString();
}
