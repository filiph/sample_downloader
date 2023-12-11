# sample_downloader

A command-line tool for easy extraction of Dart & Flutter projects
from GitHub repositories.

![Screencast of the CLI tool in action](https://raw.githubusercontent.com/filiph/sample_downloader/main/doc/sample_downloader_demo.gif)

**NOTE:** This is an experimental project by a single developer.
I cannot guarantee any level of support at this point.


## Installation

```shell
$ dart pub global activate sample_downloader
```


## Usage

```shell
$ sample_downloader
```

Currently, this fetches projects from 
[`flutter/games`](https://github.com/flutter/games)
by default. You can provide other repositories like this:

```shell
$ sample_downloader --from brianegan/flutter_architecture_samples
```


## Development

To install the latest development version of this tool to your path,
`cd` into this project's directory and run this command:

```shell
dart pub global activate --source path .
```
