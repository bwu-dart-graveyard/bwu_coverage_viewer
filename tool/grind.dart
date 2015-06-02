library bwu_coverage_viewer.tool.grind;

import 'dart:io' as io;
import 'dart:async' show Future, Stream;
import 'package:grinder/grinder.dart';
import 'package:bwu_utils_dev/grinder.dart';
import 'package:bwu_utils_dev/testing_server.dart';

// TODO(zoechi) check if version was incremented
// TODO(zoechi) check if CHANGELOG.md contains version

main(List<String> args) => grind(args);

//@Task('Delete build directory')
//void clean() => defaultClean(context);

const existingSourceDirs = const ['bin', 'lib', 'test', 'tool'];

@Task('Run analyzer')
analyze() => _analyze();

@Task('Runn all tests')
test() => _test(
// TODO(zoechi) fix to support other browsers
    [
  'vm',
  'content-shell', /*'dartium', 'chrome', 'phantomjs', 'firefox',*/
], runPubServe: true);

@Task('Run all VM tests')
testIo() => _test(['vm']);

@Task('Run all browser tests')
testHtml() => _test(['chrome'], runPubServe: false);

@DefaultTask('Check everything')
@Depends(analyze, checkFormat, lint, test)
check() => _check();

@Task('Check source code format')
checkFormat() => checkFormatTask(['.']);

/// format-all - fix all formatting issues
@Task('Fix all source format issues')
format() => _format();

@Task('Run lint checks')
lint() => _lint();

@Task('Travis')
@Depends(check, coverage)
travis() {}

@Task('Gather and send coverage data.')
coverage() => _coverage();


_analyze() => Pub.global.run('tuneup', arguments: ['check']);

_check() => run('pub', arguments: ['publish', '-n']);

_coverage() {
  final String coverageToken = io.Platform.environment['REPO_TOKEN'];

  if (coverageToken != null) {
    PubApp coverallsApp = new PubApp.global('dart_coveralls');
    coverallsApp.run([
      'report',
      '--token',
      coverageToken,
      '--retry',
      '2',
      '--exclude-test-files',
      'test/all.dart'
    ]);
  } else {
    log('Skipping coverage task: no environment variable `REPO_TOKEN` found.');
  }
}

_format() => new PubApp.global('dart_style').run(
    ['-w']..addAll(existingSourceDirs), script: 'format');

_lint() => new PubApp.global('linter')
    .run(['--stats', '-ctool/lintcfg.yaml']..addAll(existingSourceDirs));

Future _test(List<String> platforms,
    {bool runPubServe: false, bool runSelenium: false}) async {
  if (runPubServe || runSelenium) {
    final seleniumJar = io.Platform.environment['SELENIUM_JAR'];

    var pubServe;
    var selenium;
    final servers = <Future<RunProcess>>[];

    try {
      if (runPubServe) {
        pubServe = new PubServe();
        print('start pub serve');
        servers.add(pubServe.start(directories: const ['test']).then((_) {
          pubServe.stdout.listen((e) => io.stdout.add(e));
          pubServe.stderr.listen((e) => io.stderr.add(e));
        }));
      }
      if (runSelenium) {
        selenium = new SeleniumStandaloneServer();
        print('start Selenium standalone server');
        servers.add(selenium.start(seleniumJar, args: []).then((_) {
          selenium.stdout.listen((e) => io.stdout.add(e));
          selenium.stderr.listen((e) => io.stderr.add(e));
        }));
      }

      await Future.wait(servers);

      new PubApp.local('test')
        ..run(['--pub-serve=${pubServe.directoryPorts['test']}']
          ..addAll(platforms.map((p) => '-p${p}')));
    } finally {
      if (pubServe != null) {
        pubServe.stop();
      }
      if (selenium != null) {
        selenium.stop();
      }
    }
  } else {
    new PubApp.local('test').run(platforms.map((p) => '-p${p}').toList());
  }
}

//  final chromeBin = '-Dwebdriver.chrome.bin=/usr/bin/google-chrome';
//  final chromeDriverBin = '-Dwebdriver.chrome.driver=/usr/local/apps/webdriver/chromedriver/2.15/chromedriver_linux64/chromedriver';
