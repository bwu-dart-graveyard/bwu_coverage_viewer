library bwu_coverage_viewer.tool.grind;

import 'package:grinder/grinder.dart';
import 'package:bwu_utils_dev/grinder/default_tasks.dart';

main(List<String> args) => grind(args);

const existingSourceDirs = const ['bin', 'lib', 'test', 'tool'];

@analyzeDesc analyze() => analyzeTask();
@testDesc test() => testTask(['vm', 'content-shell']);
@testVmDesc testVm() => testTask(['vm']);
@testWebDesc testWeb() => testTask(['content-shell']);
@Depends(analyze, checkFormat, lint, test)
@checkDesc check() => checkTask();
@checkFormatDesc checkFormat() => checkFormatTask();
@formatDesc format() => formatTask();
@lintDesc lint() => lintTask();
@Depends(check, coverage)
@travisDesc travis() => travisTask();
@coverageDesc coverage() => coverageTask();
