// The assertions quote lines of YAML and Ruby, which are longer than 80 characters.
// ignore_for_file: lines_longer_than_80_chars

// Pure Dart: runs with `dart test test/tool`, without Flutter. The delivery files (the release
// workflow, the Fastfiles, the signing in Gradle) never run in this repository, so these checks
// keep them in step with each other, and keep a hard-coded identity, an unpinned action or a missing
// safeguard from slipping in. The rule that matters most: nothing is uploaded unless the secrets of
// the stores exist.

import 'dart:io';

import 'package:test/test.dart';

String read(String path) => File(path).readAsStringSync();

/// A file without its comment lines, so that a comment never satisfies a check, or breaks one.
String withoutComments(String text) =>
    text.replaceAll(RegExp(r'^[ \t]*#.*\n', multiLine: true), '');

/// The jobs of a workflow by id, each with its own text. A job is a key two
/// spaces in, under `jobs:`.
Map<String, String> jobsOf(String workflow) {
  final body = withoutComments(workflow)
      .split(RegExp(r'^jobs:\n', multiLine: true))[1];
  final jobs = <String, StringBuffer>{};
  StringBuffer? current;
  for (final line in body.split('\n')) {
    final id = RegExp(r'^ {2}([\w-]+):\s*$').firstMatch(line)?.group(1);
    if (id != null) {
      current = jobs[id] = StringBuffer();
    } else {
      current?.writeln(line);
    }
  }
  return {for (final entry in jobs.entries) entry.key: entry.value.toString()};
}

/// The `run: |` script of the step with this [name], unindented.
String scriptOf(String workflow, String name) {
  final lines = withoutComments(workflow).split('\n');
  final start = lines.indexWhere(
    (l) => l.trimRight().endsWith('- name: $name'),
  );
  if (start == -1) throw StateError('step "$name" not found');
  final run = lines.indexWhere((l) => l.trim() == 'run: |', start);
  final indent = lines[run].length - lines[run].trimLeft().length + 2;
  final script = <String>[];
  for (var i = run + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isNotEmpty &&
        line.length - line.trimLeft().length < indent) {
      break;
    }
    script.add(line.length >= indent ? line.substring(indent) : '');
  }
  return script.join('\n');
}

const String releasePath = '.github/workflows/release.yml';
const String iosFastfile = 'ios/fastlane/Fastfile';
const String androidFastfile = 'android/fastlane/Fastfile';

final List<String> workflowFiles = [
  for (final f in Directory('.github/workflows').listSync().whereType<File>())
    if (f.path.endsWith('.yml')) f.path,
];

void main() {
  final release = read(releasePath);
  final code = withoutComments(release);
  final jobs = jobsOf(release);

  group('every workflow', () {
    for (final file in workflowFiles) {
      test('$file pins every action to a major version', () {
        final uses = RegExp(
          r'^\s*(?:-\s+)?uses:\s*(\S+)',
          multiLine: true,
        ).allMatches(withoutComments(read(file))).map((m) => m.group(1)!);
        expect(uses, isNotEmpty);
        for (final name in uses) {
          expect(name, matches(RegExp(r'^[\w.-]+/[\w./-]+@v\d+(\.\d+)*$')));
        }
      });

      test(
        '$file declares read-only permissions and never runs a pull request with secrets',
        () {
          final text = withoutComments(read(file));
          expect(text, contains('permissions:\n  contents: read\n'));
          expect(text, isNot(contains(': write')));
          expect(text, isNot(contains('pull_request_target')));
        },
      );

      test('$file names its runners, never a -latest label', () {
        expect(withoutComments(read(file)), isNot(contains('-latest')));
      });
    }
  });

  group('release.yml', () {
    test('runs on a tag v* and by hand, and on nothing else', () {
      expect(
        code,
        contains("on:\n  push:\n    tags: ['v*']\n  workflow_dispatch:\n"),
      );
      expect(code, isNot(contains('pull_request')));
      expect(code, isNot(contains('schedule:')));
    });

    test(
      'queues a second run for the same ref instead of cutting an upload',
      () {
        expect(
          code,
          contains(
            'group: release-\${{ github.ref }}\n  cancel-in-progress: false',
          ),
        );
      },
    );

    test(
      'has the verify job and one job per platform, each with a timeout',
      () {
        expect(jobs.keys, ['verify', 'ios', 'android']);
        for (final job in jobs.values) {
          expect(
            job,
            matches(RegExp(r'^ {4}timeout-minutes: \d+$', multiLine: true)),
          );
        }
        expect(jobs['ios'], contains('runs-on: macos-15'));
        expect(jobs['android'], contains('runs-on: ubuntu-24.04'));
        expect(
          release,
          matches(
            RegExp(
              r'# .*ubuntu-24\.04.*ubuntu-latest.*Ubuntu 26.*19 October 2026',
            ),
          ),
        );
      },
    );

    test('builds and uploads a platform only when its values exist: a skipped job, not a failed one', () {
      for (final platform in ['ios', 'android']) {
        final job = jobs[platform]!;
        expect(job, contains('    needs: [verify]\n'));
        expect(
          job,
          contains(
            "    if: \${{ needs.verify.outputs.$platform == 'true' }}\n",
          ),
        );
        // No step of a platform job has a condition of its own that could let it run without the gate.
        expect(job, isNot(contains('always()')));
      }
      expect(jobs['verify'], isNot(contains('needs:')));
    });

    test('reads a secret only in the verify gate and in the steps of the gated jobs', () {
      expect(jobs['verify'], contains('secrets.'));
      // The verify job only tests presence: it never passes a secret to a command but `missing`.
      final gate = scriptOf(
        release,
        'Find out which platforms can be released',
      );
      expect(gate, isNot(contains('fastlane')));
      expect(
        gate,
        isNot(
          matches(
            RegExp(
              r'echo[^\n]*\$\{?!?(IOS|ANDROID|APPLE|APP_STORE|PLAY)_\w+\}?\s*["\x27]?\s*(>>|$)',
            ),
          ),
        ),
      );
    });

    test('runs the fastlane lanes build, then beta, for each platform, from the platform folder', () {
      final ios = jobs['ios']!;
      final android = jobs['android']!;
      expect(ios, contains('run: bundle exec fastlane ios build'));
      expect(ios, contains('run: bundle exec fastlane ios beta'));
      expect(android, contains('run: bundle exec fastlane android build'));
      expect(android, contains('run: bundle exec fastlane android beta'));
      expect(
        ios.indexOf('fastlane ios build'),
        lessThan(ios.indexOf('fastlane ios beta')),
      );
      expect(
        android.indexOf('fastlane android build'),
        lessThan(android.indexOf('fastlane android beta')),
      );
      expect(RegExp('working-directory: ios').allMatches(ios), hasLength(2));
      expect(
        RegExp('working-directory: android').allMatches(android),
        hasLength(2),
      );
    });

    test('never calls a store tool but through fastlane', () {
      for (final tool in [
        'altool',
        'xcrun notarytool',
        'bundletool',
        'gcloud',
        'curl',
      ]) {
        expect(code, isNot(contains(tool)));
      }
    });

    test('gives each platform job the secrets of the lane that needs them, no more', () {
      expect(jobs['android'], isNot(contains('APPLE_')));
      expect(jobs['android'], isNot(contains('APP_STORE_CONNECT')));
      expect(jobs['ios'], isNot(contains('ANDROID_')));
      expect(jobs['ios'], isNot(contains('PLAY_')));
    });

    group('the check of the tag against the version of the app', () {
      final script = scriptOf(
        release,
        'Check that the tag is the version of the app',
      );

      // Runs the script of the step as it is in the workflow, on a pubspec.yaml of this version.
      ProcessResult check(String tag, {String version = '1.2.0+7'}) {
        final folder = Directory.systemTemp.createTempSync('release_tag_');
        addTearDown(() => folder.deleteSync(recursive: true));
        File('${folder.path}/pubspec.yaml')
            .writeAsStringSync('name: x\nversion: $version\n');
        return Process.runSync(
          'bash',
          ['-c', script],
          workingDirectory: folder.path,
          environment: {'GITHUB_REF_NAME': tag},
        );
      }

      test('is kept for tags, before anything is built', () {
        expect(
          code,
          contains(
            "- name: Check that the tag is the version of the app\n        if: \${{ github.event_name == 'push' }}\n",
          ),
        );
        expect(code, contains('pubspec.yaml'));
      });

      for (final tag in ['v1.2.0', 'v1.2.0-rc.1', 'v1.2.0-beta']) {
        test('accepts the tag $tag', () {
          expect(check(tag).exitCode, 0);
        });
      }

      for (final tag in [
        'v1.2.1',
        'v1.3.0',
        'v1.2',
        'v1.2.0.1',
        'v1.2.0rc1',
        'vnext',
        'v',
        '1.2.0',
      ]) {
        test('refuses the tag $tag, and names it', () {
          final result = check(tag);
          expect(result.exitCode, 1);
          expect(
            result.stdout,
            contains('::error::The tag $tag is not the version of the app'),
          );
        });
      }

      test('reads the version before the build number, and refuses a pubspec with none', () {
        expect(check('v2.0.0', version: '2.0.0+31').exitCode, 0);
        expect(check('v1.0.0', version: '2.0.0+31').exitCode, 1);
      });
    });

    group('the gate on the secrets', () {
      final gate = scriptOf(
        release,
        'Find out which platforms can be released',
      );
      final env = <String>{
        for (final m
            in RegExp(
              r'^ {10}(\w+): \$\{\{ (?:secrets|vars)\.\w+ \}\}$',
              multiLine: true,
            ).allMatches(
              code
                  .split('- name: Find out which platforms')[1]
                  .split('\n  ios:')[0],
            ))
          m.group(1)!,
      };

      ({String output, String summary}) run(Map<String, String> values) {
        final folder = Directory.systemTemp.createTempSync('release_gate_');
        addTearDown(() => folder.deleteSync(recursive: true));
        final output = File('${folder.path}/output')..createSync();
        final summary = File('${folder.path}/summary')..createSync();
        final result = Process.runSync(
          'bash',
          ['-e', '-c', gate],
          environment: {
            ...values,
            'GITHUB_OUTPUT': output.path,
            'GITHUB_STEP_SUMMARY': summary.path,
          },
          includeParentEnvironment: false,
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return (
          output: output.readAsStringSync(),
          summary: summary.readAsStringSync(),
        );
      }

      test(
        'tests the names that the lanes need, and the README lists every one',
        () {
          final readme = read('README.md');
          expect(env, isNotEmpty);
          for (final name in env) {
            expect(readme, contains('`$name`'));
          }
        },
      );

      test('skips both platforms, and says why, when this repository has no secret (as it has none)', () {
        final result = run({});
        expect(result.output, contains('ios=false'));
        expect(result.output, contains('android=false'));
        expect(
          result.summary,
          contains(
            'ios: skipped, nothing is built or uploaded. Missing: IOS_BUNDLE_ID APPLE_TEAM_ID',
          ),
        );
        expect(
          result.summary,
          contains(
            'android: skipped, nothing is built or uploaded. Missing: ANDROID_PACKAGE_NAME',
          ),
        );
      });

      test('treats an empty value as missing', () {
        final result = run({for (final name in env) name: ''});
        expect(result.output, isNot(contains('=true')));
      });

      test('skips a platform with one value missing, and runs the other', () {
        final androidOnly = {
          for (final name in env.where(
            (n) => n.startsWith('ANDROID_') || n.startsWith('PLAY_'),
          ))
            name: 'x',
        };
        final result = run(androidOnly);
        expect(result.output, contains('ios=false'));
        expect(result.output, contains('android=true'));
        final almost = {...androidOnly}
          ..remove('PLAY_SERVICE_ACCOUNT_JSON_BASE64');
        expect(run(almost).output, contains('android=false'));
        expect(
          run(almost).summary,
          contains('Missing: PLAY_SERVICE_ACCOUNT_JSON_BASE64.'),
        );
      });

      test('never writes the value of a secret to the summary', () {
        final result = run({for (final name in env) name: 'sEcReT-vAlUe'});
        expect(result.output, contains('ios=true'));
        expect(result.output, contains('android=true'));
        expect(result.summary, isNot(contains('sEcReT-vAlUe')));
      });
    });
  });

  group('the Fastfiles and Appfiles', () {
    final files = {
      'ios': (
        fastfile: read(iosFastfile),
        appfile: read('ios/fastlane/Appfile'),
      ),
      'android': (
        fastfile: read(androidFastfile),
        appfile: read('android/fastlane/Appfile'),
      ),
    };

    /// The text of the lane `name`, up to the next lane or the end of the platform block.
    String laneOf(String fastfile, String name) {
      final text = withoutComments(fastfile);
      final start = text.indexOf('  lane :$name do');
      expect(start, isNot(-1));
      final next = text.indexOf(RegExp(r'\n  (desc|lane) |\nend\n'), start + 1);
      return text.substring(start, next == -1 ? text.length : next);
    }

    for (final entry in files.entries) {
      final platform = entry.key;
      final fastfile = withoutComments(entry.value.fastfile);

      group(platform, () {
        test('has the lanes ci_signing, build and beta', () {
          for (final lane in ['ci_signing', 'build', 'beta']) {
            expect(fastfile, contains('lane :$lane do'));
          }
          expect(fastfile, contains('platform :$platform do'));
        });

        test(
          'reads every secret from the environment, with no default value',
          () {
            expect(
              fastfile,
              isNot(
                matches(
                  RegExp(
                    r"ENV\.fetch\('(?:[A-Z_]*(?:PASSWORD|KEY|BASE64|TEAM)[A-Z_]*)',\s*['\x22]",
                  ),
                ),
              ),
            );
            expect(
              fastfile,
              isNot(
                matches(
                  RegExp(r"ENV\['[A-Z_]*(?:PASSWORD|BASE64)[A-Z_]*'\]\s*\|\|"),
                ),
              ),
            );
          },
        );

        test('writes no identity of an account: no team id, no bundle id, no password, no key', () {
          for (final text in [entry.value.fastfile, entry.value.appfile]) {
            expect(
              text,
              isNot(
                matches(
                  RegExp(r'\b(?=[A-Z0-9]*\d)(?=[A-Z0-9]*[A-Z])[A-Z0-9]{10}\b'),
                ),
              ),
            );
            expect(
              text,
              isNot(
                matches(
                  RegExp(
                    r'\b(?:com|org|net|io|dev)\.[a-z0-9_-]+\.[a-z0-9_.-]+\b',
                  ),
                ),
              ),
            );
            expect(text, isNot(contains('-----BEGIN')));
            expect(text, isNot(matches(RegExp(r'@[a-z0-9-]+\.(com|fr|io)'))));
          }
        });

        test('reads the identity of the app from the environment, in one line each', () {
          final lines = withoutComments(entry.value.appfile).trim().split('\n');
          expect(lines, isNotEmpty);
          for (final line in lines) {
            expect(
              line,
              matches(RegExp(r"^\w+\(ENV\.fetch\('[A-Z_]+', nil\)\)$")),
            );
          }
        });

        test(
          'stops with the name of a missing variable before it does anything',
          () {
            expect(fastfile, contains('def require_env!(*names)'));
            expect(fastfile, contains('Missing environment variable(s)'));
            for (final lane in ['ci_signing', 'beta']) {
              expect(
                laneOf(entry.value.fastfile, lane),
                contains('require_env!('),
              );
            }
          },
        );

        test('refuses to sign or upload outside CI unless forced', () {
          expect(
            fastfile,
            contains("ENV['CI'] == 'true' || ENV['FORCE_DELIVERY'] == '1'"),
          );
          for (final lane in ['ci_signing', 'beta']) {
            final text = laneOf(entry.value.fastfile, lane);
            expect(text, contains("require_ci!('$lane')"));
            // The refusal comes before the first action of the lane.
            expect(
              text.indexOf('require_ci!'),
              lessThan(text.indexOf('require_env!')),
            );
          }
        });

        test('uploads in the lane beta only, after the checks', () {
          final upload = platform == 'ios'
              ? 'upload_to_testflight'
              : 'upload_to_play_store';
          expect(RegExp(upload).allMatches(fastfile), hasLength(1));
          final beta = laneOf(entry.value.fastfile, 'beta');
          expect(beta, contains(upload));
          expect(beta.indexOf('require_ci!'), lessThan(beta.indexOf(upload)));
          expect(beta.indexOf('require_env!'), lessThan(beta.indexOf(upload)));
          for (final lane in ['ci_signing', 'build']) {
            expect(laneOf(entry.value.fastfile, lane), isNot(contains(upload)));
          }
        });

        test(
          'builds with the Flutter command and the adapters the release needs',
          () {
            final build = laneOf(entry.value.fastfile, 'build');
            expect(
              build,
              contains(
                platform == 'ios' ? "'build', 'ipa'" : "'build', 'appbundle'",
              ),
            );
            expect(fastfile, contains('--dart-define=BOARDROOM_ADAPTERS='));
            expect(build, contains('ci_signing'));
          },
        );
      });
    }

    test('uploads to the internal track of Google Play, as a draft, and to TestFlight with an API key', () {
      final android = laneOf(files['android']!.fastfile, 'beta');
      expect(android, contains("track: 'internal'"));
      expect(android, contains("release_status: 'draft'"));
      expect(android, contains('json_key_data:'));
      final ios = laneOf(files['ios']!.fastfile, 'beta');
      expect(ios, contains('app_store_connect_api_key('));
      expect(ios, isNot(contains('apple_id')));
      expect(ios, isNot(contains('FASTLANE_PASSWORD')));
    });

    test('lists every variable of the Fastfiles in the README', () {
      final readme = read('README.md');
      final names =
          {
            for (final f in files.values)
              for (final m in RegExp(
                r"ENV(?:\.fetch\(|\[)'(\w+)'",
              ).allMatches(f.fastfile))
                m.group(1)!,
          }..removeAll({
            'CI',
            'FORCE_DELIVERY',
            'BUILD_NUMBER',
            'BOARDROOM_PROFILE_NAME',
          });
      expect(names, isNotEmpty);
      for (final name in names) {
        expect(readme, contains('`$name`'), reason: name);
      }
    });

    test('the Gemfile pins fastlane to one exact version, locked', () {
      expect(
        read('Gemfile'),
        matches(RegExp(r"^gem 'fastlane', '\d+\.\d+\.\d+'$", multiLine: true)),
      );
      expect(read('Gemfile.lock'), contains('fastlane (= '));
    });

    test('are valid Ruby', () {
      final ruby = Process.runSync('ruby', ['-v']);
      if (ruby.exitCode != 0) {
        markTestSkipped('ruby is not installed');
        return;
      }
      for (final path in [
        iosFastfile,
        androidFastfile,
        'ios/fastlane/Appfile',
        'android/fastlane/Appfile',
        'Gemfile',
      ]) {
        final result = Process.runSync('ruby', ['-c', path]);
        expect(result.exitCode, 0, reason: '$path: ${result.stderr}');
      }
    });
  });

  group('the signing of the Android release', () {
    final gradle = read('android/app/build.gradle.kts');
    final gitignore = read('.gitignore');

    test('reads android/key.properties, which Git ignores, and falls back to the debug key without it', () {
      expect(gradle, contains('rootProject.file("key.properties")'));
      expect(gradle, contains('signingConfigs.getByName("debug")'));
      expect(gradle, contains('hasReleaseKey'));
      expect(gitignore, contains('/android/key.properties'));
      expect(gitignore, contains('*.jks'));
    });

    test('holds no password, alias or key path of its own', () {
      expect(
        gradle,
        isNot(matches(RegExp(r'(storePassword|keyPassword)\s*=\s*"'))),
      );
      expect(gradle, isNot(matches(RegExp(r'keyAlias\s*=\s*"'))));
      expect(gradle, isNot(contains('.jks"')));
    });

    test(
      'the key.properties that the lane writes has the keys that Gradle reads',
      () {
        final lane = read(androidFastfile);
        for (final key in [
          'storePassword',
          'keyPassword',
          'keyAlias',
          'storeFile',
        ]) {
          expect(lane, contains('$key='));
          expect(gradle, contains('"$key"'));
        }
      },
    );
  });

  group('the files of signing and the reports', () {
    test('Git ignores keystores, certificates, profiles, keys and the Bundler install', () {
      final gitignore = read('.gitignore');
      for (final pattern in [
        '*.jks',
        '*.p8',
        '*.p12',
        '*.mobileprovision',
        '/vendor/bundle/',
        '/.bundle/',
      ]) {
        expect(gitignore, contains(pattern));
      }
    });
  });
}
