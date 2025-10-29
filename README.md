# Files

A fast and efficient command-line tool for comparing two directories and finding differences.

## Features

- **Recursive directory comparison** - Scan subdirectories automatically
- **Multiple output formats** - Text, JSON, or summary output
- **Fast concurrent processing** - Uses Swift's modern concurrency for optimal performance
- **Smart file comparison** - Quickly identifies identical, modified, and unique files
- **Clear exit codes** - Easy integration with scripts and CI/CD pipelines

## Installation

TBD

## Usage

```bash
files <left-directory> <right-directory> [options]
```

### Options

- `--recursive` / `--no-recursive` - Scan subdirectories recursively (default: recursive)
- `--verbose`, `-v` - Show detailed output with all file paths
- `--format FORMAT` - Output format: `text` (default), `json`, `summary`
- `--help`, `-h` - Show help message
- `--version` - Show version information

### Exit Codes

- `0` - Directories are identical
- `1` - Differences found
- `2` - Error occurred (invalid directory, access denied, etc.)

## Examples

### Basic comparison

```bash
files /path/to/dir1 /path/to/dir2
```

Output:
```
✗ Directories differ

Only in LEFT (3):
  Use --verbose to see file list

Only in RIGHT (2):
  Use --verbose to see file list

Modified (1):
  Use --verbose to see file list

Summary: 3 left-only, 2 right-only, 1 modified, 10 unchanged
```

### Verbose output

```bash
files /path/to/dir1 /path/to/dir2 --verbose
```

Output:
```
✗ Directories differ

Only in LEFT (3):
  - old-file.txt
  - deprecated/config.json
  - temp/data.csv

Only in RIGHT (2):
  + new-feature.swift
  + assets/logo.png

Modified (1):
  ~ config.yaml

Summary: 3 left-only, 2 right-only, 1 modified, 10 unchanged
```

### JSON output

```bash
files /path/to/dir1 /path/to/dir2 --format json
```

Output:
```json
{
  "onlyInLeft": [
    "old-file.txt",
    "deprecated/config.json"
  ],
  "onlyInRight": [
    "new-feature.swift"
  ],
  "modified": [
    "config.yaml"
  ],
  "common": [
    "README.md",
    "main.swift"
  ],
  "summary": {
    "onlyInLeftCount": 2,
    "onlyInRightCount": 1,
    "modifiedCount": 1,
    "commonCount": 2,
    "identical": false
  }
}
```

### Summary output

```bash
files /path/to/dir1 /path/to/dir2 --format summary
```

Output:
```
Identical: no
Only in left: 3
Only in right: 2
Modified: 1
Unchanged: 10
Total files: 16
```

### Non-recursive comparison

Compare only top-level files without scanning subdirectories:

```bash
files /path/to/dir1 /path/to/dir2 --no-recursive
```

### Use in scripts

```bash
#!/bin/bash

if files /backup /current --format summary; then
    echo "Backup is up to date"
else
    echo "Backup needs updating"
fi
```


LICENSE: MIT
