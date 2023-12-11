import 'dart:collection';

import 'package:github/github.dart';

/// Returns a stream of subdirectories in [repo] that are a Dart or Flutter
/// package (i.e. they contain `pubspec.yaml`). Uses the provided
/// [github] instance.
///
/// Goes at most to [maxDepth]. For example, when [maxDepth] is `2`
/// and a `pubspec.yaml` exists at path `a/b/c/pubspec.yaml`, then
/// that project will not be returned. This is an important optimization because
/// crawling a full GitHub repo is slow, and many repos have very large
/// directory structures.
///
/// This also returns `"/"` if the root of the repository has a `pubspec.yaml`
/// in it.
Stream<String> getPubspecDirectories(GitHub github, RepositorySlug repo,
    {required int maxDepth}) async* {
  const root = '/';

  var open = Queue<String>.from([root]);
  while (open.isNotEmpty) {
    var path = open.removeFirst();

    if (path.split('/').length > maxDepth) {
      // Path is too deep. Ignoring.
      continue;
    }

    var contents = await github.repositories.getContents(repo, path);
    assert(contents.isDirectory);

    var isPackage = _isPackage(contents);
    if (isPackage) {
      yield path;
    }

    // Only explore subdirectories if this is the root (`/`) of the repository
    // or if this is _not_ a package directory itself (e.g. `templates/`).
    if (path == root || !isPackage) {
      for (var content in contents.tree!) {
        if (content.type == 'dir') {
          open.add(content.path!);
        }
      }
    }
  }
}

bool _isPackage(RepositoryContents contents) {
  assert(contents.isDirectory);

  for (var content in contents.tree!) {
    if (content.name == 'pubspec.yaml') {
      return true;
    }
  }
  return false;
}
