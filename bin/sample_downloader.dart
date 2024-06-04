import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/args.dart';
import 'package:cli_menu/cli_menu.dart';
import 'package:cli_util/cli_logging.dart' as cli;
import 'package:github/github.dart';
import 'package:path/path.dart' as path;
import 'package:sample_downloader/src/get_pubspec_dirs.dart';

void main(List<String> args) async {
  const defaultRepos = [
    'flutter/games',
    // 'flutter/samples',
    // 'brianegan/flutter_architecture_samples',
  ];
  const defaultMaxDepth = 2;

  var parser = ArgParser(usageLineLength: 80);
  parser.addMultiOption(
    'from',
    defaultsTo: defaultRepos,
    help: "Specify one or more repositories from which to get sample projects.",
  );
  parser.addOption(
    'max-depth',
    defaultsTo: defaultMaxDepth.toString(),
    help: "The maximum level in which a project is expected. "
        "In other words, pubspec.yaml files beyond the max-depth level "
        "are ignored.",
  );
  parser.addFlag(
    'verbose',
    abbr: 'v',
    negatable: false,
    help: "Prints more information.",
  );
  parser.addFlag('help', abbr: '?', help: "Shows this help.", negatable: false);

  String getUsage() => "Usage:\n"
      "    \$ sample_downloader\n"
      "\n"
      "Options:\n"
      "${parser.usage}\n";

  ArgResults results;
  try {
    results = parser.parse(args);
  } on ArgParserException catch (e) {
    stderr.writeln("Wrong usage: $e");

    stdout.write('\n');
    stdout.write(getUsage());
    exit(2);
  }

  var help = results['help'] as bool;
  var verbose = results['verbose'] as bool;
  var repos = results['from'] as List<String>;
  var maxDepth = int.tryParse(results['max-depth']) ?? defaultMaxDepth;

  var logger = verbose ? cli.Logger.verbose() : cli.Logger.standard();

  if (help) {
    logger.stdout(getUsage());
    // Do not set error code when help is what the user wanted.
    return;
  }

  /// Convenience function that shows a progress indicator while
  /// we're waiting for something to happen.
  Future<T> doWork<T>(String message, Future<T> future) async {
    var progress = logger.progress(message);
    var result = await future;
    progress.finish(showTiming: true);
    return result;
  }

  String emphasized(String message) => logger.ansi.emphasized(message);

  String subtle(String message) => logger.ansi.subtle(message);

  logger.stdout('\nWelcome to ${emphasized('sample_downloader')}.');
  logger
      .stdout(subtle('This tool uses the GitHub API to find and download Dart\n'
          'and Flutter samples. The API is rate-limited, so it is recommended\n'
          "that you select 'Yes' below. Otherwise, the tool might fail after\n"
          'some time.\n'));
  logger.stdout(
      emphasized("Do you want to use your environment's GitHub credentials?"));
  logger
      .stdout(subtle("If you're using git from the command line, you probably\n"
          "have the credentials set up."));
  bool usingCredentials;
  {
    var menu = Menu(['Yes', 'No'], modifierKeys: ['y', 'n']);
    var authChoice = menu.choose();
    usingCredentials = authChoice.value == 'Yes';
  }
  logger.stdout('\n${usingCredentials ? 'Using' : 'Not using'} '
      'environment credentials.');

  var gitHubAuth = usingCredentials
      ? findAuthenticationFromEnvironment()
      : const Authentication.anonymous();

  var github = GitHub(auth: gitHubAuth);

  String repoFullName;

  if (repos.length == 1) {
    repoFullName = repos.single;
  } else {
    logger.stdout(
        emphasized("\nSelect repository from which to download a sample:"));
    var menu = Menu(repos);
    var repoChoice = menu.choose();
    repoFullName = repoChoice.value;
  }

  var repo = RepositorySlug.full(repoFullName);

  logger.stdout("\nLooking at ${emphasized(repo.fullName)}.");

  String defaultRef;
  try {
    defaultRef = (await doWork('  Getting default branch',
            github.repositories.getRepository(repo)))
        .defaultBranch;
    logger.trace('  Default branch is $defaultRef.');
  } on RepositoryNotFound {
    logger.stderr("Repository '${repo.fullName}' not found.");
    github.dispose();
    exit(3);
  }

  var rootContents =
      await doWork('  Fetching', github.repositories.getContents(repo, '/'));
  assert(rootContents.isDirectory);

  var projects = await doWork(
      '  Searching for samples',
      getPubspecDirectories(github, repo, maxDepth: maxDepth)
          .where((path) => path != '/')
          .toList());

  logger.stdout('  Found ${projects.length} projects.');
  projects.sort();

  logger.stdout(emphasized('\nChoose sample:'));

  String projectPath;

  {
    var menu = Menu(projects);
    var projectChoice = menu.choose();
    projectPath = projectChoice.value;
  }

  final sampleName = projectPath.split('/').last;

  logger.stdout("\nSelected ${emphasized(sampleName)}.");

  var defaultDirectoryName = '${repo.owner}-${repo.name}-$sampleName';
  String? directoryPath;

  while (directoryPath == null) {
    logger.stdout("\n${emphasized('Enter name of new directory')} "
        "${subtle('(ENTER for ')}"
        "$defaultDirectoryName"
        "${subtle('):')}");
    var path = stdin.readLineSync();
    logger.trace("Input: '$path'");
    if (path == null || path.trim().isEmpty) {
      path = defaultDirectoryName;
    }

    // Check if already exists.
    var directory = Directory(path);
    final alreadyExists = await doWork('Checking', directory.exists());
    if (alreadyExists) {
      logger.stderr("Directory '$path' already exists. "
          "Continuing would overwrite files. Please try another path.");
      continue;
    }

    logger.trace('Creating directory '
        '${emphasized(directory.path)}.');
    logger.trace('Absolute path: ${directory.absolute.path}');
    try {
      var created = await doWork('Creating', directory.create());
      directoryPath = created.path;

      logger.stdout("Created directory "
          "${emphasized(directory.path)} "
          "in "
          "${Directory.current.path}.");
    } on IOException catch (e) {
      logger.stderr("Couldn't create directory '$path'. "
          "Please try another name or hit Ctrl-C to exit. \n"
          "$e");
      continue;
    }
  }

  logger.stdout("Fetching data.");

  // Create an in-line scope so that [response] is garbage-collected
  // as soon as possible.
  InputStream zipInput;
  {
    // TODO: actually use a streamed response instead of awaiting full contents
    // Fetch the bytes.
    var response = await doWork(
      'Downloading',
      github.request(
        'GET',
        '/repos/${repo.fullName}/zipball/$defaultRef',
      ),
    );

    // TODO: put into a temp file instead - to avoid consuming memory

    zipInput = InputStream(response.bodyBytes);
  }

  // Make sure the HTTP client is closed as soon as it's not needed.
  logger.trace('Closing HTTP client.');
  github.dispose();

  // This work is synchronous but we still want to show at least some
  // 'progress' indication. Later, this could be done in an isolate.
  var decompressProgress = logger.progress('Decompressing');
  var archive = ZipDecoder().decodeBuffer(zipInput, verify: true);
  decompressProgress.finish(showTiming: true);

  var archiveNamePrefix = archive.fileName(0);
  logger.trace('Archive name: $archiveNamePrefix.');
  var projectFilePrefix = '$archiveNamePrefix$projectPath/';

  var writeProgress = logger.progress('Writing to disk');
  for (var zippedFile in archive) {
    if (!zippedFile.name.startsWith(projectFilePrefix)) {
      continue;
    }

    var filename = zippedFile.name.substring(projectFilePrefix.length);
    logger.trace('Found: $filename');

    var outputPath = path.join(directoryPath, filename);

    if (!zippedFile.isFile) {
      // A subdirectory.
      var directory = Directory(outputPath);
      await directory.create(recursive: true);
      continue;
    }

    // This is a file.
    var outputFile = OutputFileStream(outputPath);
    zippedFile.writeContent(outputFile);
  }
  writeProgress.finish(showTiming: true);

  logger.stdout('\nProject generated in '
      '${emphasized(directoryPath)}.');
  logger.stdout(
    subtle('\nTo run the project:\n\n'
        '  cd $directoryPath\n'
        '  flutter run\n\n'
        'Enjoy!'),
  );
}
