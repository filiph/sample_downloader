import 'dart:collection';

import 'package:github/github.dart';

Stream<String> getPubspecDirectories(GitHub github, RepositorySlug repo,
    {required int maxDepth}) async* {
  var open = Queue<String>.from(['/']);
  while (open.isNotEmpty) {
    var path = open.removeFirst();

    if (path.split('/').length > maxDepth) {
      // Path is too deep. Ignoring.
      continue;
    }

    var contents = await github.repositories.getContents(repo, path);
    assert(contents.isDirectory);
    if (_isPackage(contents)) {
      yield path;
    } else {
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
