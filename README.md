# Files

A fast and efficient command-line tool for comparing and synchronizing directories.

## Features

### Directory Comparison
- **Recursive directory comparison** - Scan subdirectories automatically
- **Multiple output formats** - Text, JSON, or summary output
- **Fast concurrent processing** - Uses Swift's modern concurrency for optimal performance
- **Smart file comparison** - Quickly identifies identical, modified, and unique files
- **Clear exit codes** - Easy integration with scripts and CI/CD pipelines

### Directory Synchronization
- **One-way sync** - Mirror source directory to destination
- **Two-way sync** - Bidirectional synchronization with conflict resolution
- **Conflict resolution strategies** - Keep newest, source, destination, or skip
- **Dry-run mode** - Preview changes before applying them
- **Safe operations** - Creates intermediate directories and validates paths

## Installation

TBD

## Usage

Files has two main commands: `compare` (default) and `sync`.

### Compare Command

Compare two directories and report differences:

```bash
files compare <left-directory> <right-directory> [options]
# or simply (compare is the default command):
files <left-directory> <right-directory> [options]
```

#### Options

- `--recursive` / `--no-recursive` - Scan subdirectories recursively (default: recursive)
- `--verbose`, `-v` - Show detailed output with all file paths
- `--format FORMAT` - Output format: `text` (default), `json`, `summary`
- `--help`, `-h` - Show help message
- `--version` - Show version information

#### Exit Codes

- `0` - Directories are identical
- `1` - Differences found
- `2` - Error occurred (invalid directory, access denied, etc.)

### Sync Command

Synchronize two directories:

```bash
files sync <source-directory> <destination-directory> [options]
```

#### Options

- `--two-way` - Enable bidirectional sync (default: one-way)
- `--conflict-resolution STRATEGY` - For two-way sync: `newest` (default), `source`, `destination`, `skip`
- `--recursive` / `--no-recursive` - Scan subdirectories recursively (default: recursive)
- `--dry-run` - Preview changes without applying them
- `--verbose`, `-v` - Show detailed output with all operations
- `--format FORMAT` - Output format: `text` (default), `json`, `summary`

#### Sync Modes

**One-way sync** (default): Mirrors source to destination
- Copies files that exist only in source
- Deletes files that exist only in destination
- Updates files that differ between source and destination

**Two-way sync** (`--two-way`): Bidirectional synchronization
- Copies files that exist only in either directory to the other
- Resolves conflicts for modified files based on `--conflict-resolution` strategy

#### Conflict Resolution Strategies

- `newest` - Keep the file with the most recent modification time (default)
- `source` - Always prefer the source file
- `destination` - Always prefer the destination file
- `skip` - Skip conflicting files, leave both unchanged

## Examples

### Compare Examples

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

### Sync Examples

#### Basic one-way sync

Mirror source to destination (preview with dry-run):

```bash
files sync /source/dir /backup/dir --dry-run --verbose
```

Output:
```
🔍 DRY RUN - No changes will be made

Would perform 5 operation(s)

Copy (3):
  would copy new-file.txt
  would copy docs/guide.md
  would copy src/main.swift

Update (1):
  would update config.yaml

Delete (1):
  would delete old-file.txt
```

Execute the sync:

```bash
files sync /source/dir /backup/dir --verbose
```

Output:
```
Performed 5 operation(s)

Copy (3):
  copied new-file.txt
  copied docs/guide.md
  copied src/main.swift

Update (1):
  updated config.yaml

Delete (1):
  deleted old-file.txt

Summary: 5 succeeded, 0 failed, 0 skipped
```

#### Two-way sync with newest conflict resolution

Synchronize two directories bidirectionally, keeping the newest version of conflicting files:

```bash
files sync /dir1 /dir2 --two-way --conflict-resolution newest --verbose
```

Output:
```
Performed 4 operation(s)

Copy (3):
  copied unique-in-dir1.txt
  copied unique-in-dir2.txt
  copied another-file.md

Update (1):
  updated conflicting-file.txt

Summary: 4 succeeded, 0 failed, 0 skipped
```

#### Two-way sync preferring source

Always prefer the source directory for conflicts:

```bash
files sync /source /dest --two-way --conflict-resolution source
```

#### Two-way sync skipping conflicts

Sync unique files but skip conflicting files:

```bash
files sync /dir1 /dir2 --two-way --conflict-resolution skip --verbose
```

#### JSON output for automation

```bash
files sync /source /dest --dry-run --format json
```

Output:
```json
{
  "operations": [
    {
      "type": "copy",
      "path": "new-file.txt",
      "source": "/source/new-file.txt",
      "destination": "/dest/new-file.txt"
    },
    {
      "type": "update",
      "path": "modified.txt",
      "source": "/source/modified.txt",
      "destination": "/dest/modified.txt"
    }
  ],
  "summary": {
    "total": 2,
    "succeeded": 0,
    "failed": 0,
    "skipped": 2
  }
}
```

#### Backup automation script

```bash
#!/bin/bash

# Mirror production to backup with dry-run check first
echo "Checking what would change..."
files sync /production /backup --dry-run --format summary

read -p "Proceed with sync? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    files sync /production /backup --verbose
    if [ $? -eq 0 ]; then
        echo "Backup completed successfully"
    else
        echo "Backup failed!"
        exit 1
    fi
fi
```

#### Bidirectional project sync

Keep two working directories in sync:

```bash
# Sync laptop and desktop project directories
files sync ~/projects/myapp /mnt/desktop/projects/myapp --two-way --conflict-resolution newest
```


LICENSE: MIT
