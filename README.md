# Files

A fast and efficient command-line tool for comparing and synchronizing directories.

## Features

### Directory Comparison
- **Recursive directory comparison** - Scan subdirectories automatically
- **Multiple output formats** - Text, JSON, or summary output
- **Fast concurrent processing** - Uses Swift's modern concurrency for optimal performance
- **Smart file comparison** - Quickly identifies identical, modified, and unique files
- **Fuzzy filename matching** - Match files with similar names using configurable precision threshold
- **Clear exit codes** - Easy integration with scripts and CI/CD pipelines
- **Pattern-based file filtering** - Use .filesignore to exclude files from operations

### Directory Synchronization
- **One-way sync** - Mirror source directory to destination
- **Two-way sync** - Bidirectional synchronization with conflict resolution
- **Conflict resolution strategies** - Keep newest, source, destination, or skip
- **Dry-run mode** - Preview changes before applying them
- **Safe operations** - Creates intermediate directories and validates paths

## Installation

### Download Pre-built Binary

The latest macOS build can be downloaded from the [GitHub Releases](https://github.com/velocityzen/Files/releases) page.

### Build from Source

See the [Building](#building) section below for instructions on building from source.

## File Filtering with .filesignore

Files supports `.filesignore` files to exclude certain files and directories from comparison and sync operations. This works similarly to `.gitignore`.

### .filesignore File Locations

The tool automatically looks for `.filesignore` files in three locations (in order):

1. **User home directory**: `~/.filesignore` - Global patterns for all operations
2. **Source/left directory**: `<source-dir>/.filesignore`
3. **Destination/right directory**: `<dest-dir>/.filesignore`

Patterns from all found files are merged together.

### Pattern Syntax

- `*` - Matches any characters except `/`
- `?` - Matches a single character except `/`
- `**` - Matches zero or more directories
- `/` at start - Pattern is relative to directory root
- `/` at end - Pattern matches directories only
- `!` - Negates a pattern (includes files that were previously excluded)
- `#` - Comment line
- Empty lines are ignored

### Default Ignored Files

By default, `.filesignore` files themselves are always ignored and will not be copied during sync operations. This prevents the ignore configuration from being propagated to destination directories.

To explicitly include `.filesignore` in sync operations, add a negation pattern:

```
!.filesignore
```

### Example .filesignore

```
# Ignore build artifacts
*.o
*.class
build/

# Ignore dependencies
node_modules/
vendor/

# Ignore version control
.git/
.svn/

# Ignore OS files
.DS_Store
Thumbs.db

# Ignore all log files
*.log

# But keep important.log
!important.log

# Ignore config.json only at root
/config.json

# Ignore all .txt files in build directory and subdirectories
build/**/*.txt
```

### Disabling .filesignore

You can disable `.filesignore` pattern matching with the `--no-ignore` flag:

```bash
files compare dir1 dir2 --no-ignore
files sync source dest --no-ignore
```

## Usage

Files has three main commands: `compare` (default), `sync`, and `cp`.

### Compare Command

Compare two directories and report differences:

```bash
files compare <left-directory> <right-directory> [options]
# or simply (compare is the default command):
files <left-directory> <right-directory> [options]
```

#### Options

- `--recursive` / `--no-recursive` - Scan subdirectories recursively (default: recursive)
- `--match-precision THRESHOLD` - Fuzzy filename matching threshold from 0.0 to 1.0 (default: 1.0 for exact matching). Lower values enable matching files with similar names using Levenshtein distance
- `--verbose`, `-v` - Show detailed output with all file paths
- `--format FORMAT` - Output format: `text` (default), `json`, `summary`
- `--no-ignore` - Disable .filesignore pattern matching
- `--help`, `-h` - Show help message
- `--version` - Show version information

#### Exit Codes

- `0` - Directories are identical
- `1` - Differences found
- `2` - Error occurred (invalid directory, access denied, etc.)

### Copy Command

Copy new and modified files from source to destination (without deletions):

```bash
files cp <source-directory> <destination-directory> [options]
```

This is a convenience command equivalent to `files sync --no-deletions` with one-way mode. It's useful for updating a destination directory with new and changed files from source while preserving any extra files in the destination.

#### Options

- `--show-more-right` - Scan leaf directories on the right side for additional diff information
- `--match-precision THRESHOLD` - Fuzzy filename matching threshold from 0.0 to 1.0 (default: 1.0 for exact matching)
- `--dry-run` - Preview changes without applying them
- `--verbose`, `-v` - Show detailed output with all operations
- `--format FORMAT` - Output format: `text` (default), `json`, `summary`
- `--no-ignore` - Disable .filesignore pattern matching

#### Example

```bash
# Preview what would be copied
files cp /source /backup --dry-run --verbose

# Copy new and modified files
files cp /source /backup --verbose
```

### Sync Command

Synchronize two directories:

```bash
files sync <source-directory> <destination-directory> [options]
```

#### Options

- `--two-way` - Enable bidirectional sync (default: one-way)
- `--conflict-resolution STRATEGY` - For two-way sync: `newest` (default), `source`, `destination`, `skip`
- `--recursive` / `--no-recursive` - Scan subdirectories recursively (default: recursive)
- `--deletions` - Delete files in destination that don't exist in source (one-way sync only, default: false)
- `--show-more-right` - Scan leaf directories on the right side for additional diff information (one-way sync without deletions only)
- `--match-precision THRESHOLD` - Fuzzy filename matching threshold from 0.0 to 1.0 (default: 1.0 for exact matching). Lower values enable matching files with similar names using Levenshtein distance
- `--dry-run` - Preview changes without applying them
- `--verbose`, `-v` - Show detailed output with all operations
- `--format FORMAT` - Output format: `text` (default), `json`, `summary`
- `--no-ignore` - Disable .filesignore pattern matching

#### Sync Modes

**One-way sync** (default): Copies and updates files from source to destination
- Copies files that exist only in source
- Updates files that differ between source and destination
- By default, does NOT delete files that exist only in destination
- Use `--deletions` flag to delete extra files in destination (mirrors source exactly)

**Two-way sync** (`--two-way`): Bidirectional synchronization
- Copies files that exist only in either directory to the other
- Never deletes files (syncs in both directions)
- Resolves conflicts for modified files based on `--conflict-resolution` strategy

#### Conflict Resolution Strategies

- `newest` - Keep the file with the most recent modification time (default)
- `source` - Always prefer the source file
- `destination` - Always prefer the destination file
- `skip` - Skip conflicting files, leave both unchanged

## Fuzzy Filename Matching

The `--match-precision` option enables fuzzy matching of filenames using Levenshtein distance algorithm. This is useful when comparing directories with files that may have typos, slight variations, or systematic naming differences.

### How It Works

- **Threshold value**: A number from 0.0 to 1.0
  - `1.0` (default): Only exact filename matches
  - `0.8`: Allows ~20% character differences (recommended for typo detection)
  - `0.5`: Allows ~50% character differences (very permissive)
  - `0.0`: Matches any files (not recommended)

- **Matching is based on filename only**, not the full path
- **Exact matches are always preferred** over fuzzy matches
- **One-to-one mapping**: Each right file can only match one left file

### Use Cases

1. **Typo detection**: Find files with misspelled names (e.g., "report.txt" vs "reprot.txt")
2. **Version variations**: Match files with version numbers (e.g., "file_v1.txt" vs "file_v2.txt")
3. **Renamed files**: Identify files that were slightly renamed between directories
4. **Import cleanup**: Find near-duplicate files from different sources

### Examples

#### Detect typos in filenames

```bash
# Compare with fuzzy matching (80% similarity threshold)
files /backup /current --match-precision 0.8 --verbose
```

Output shows fuzzy-matched files as "modified":
```
Modified (2):
  ~ report.txt (matched with: reprot.txt)
  ~ document.txt (matched with: documnet.txt)
```

#### Sync with fuzzy matching

```bash
# Sync files even if names have minor differences
files sync /source /dest --match-precision 0.8 --verbose
```

This will:
- Match "report.txt" (source) with "reprot.txt" (destination)
- Update the file with correct content
- Create new "report.txt" in destination

#### Conservative fuzzy matching

```bash
# Use higher threshold (90%) for stricter matching
files /dir1 /dir2 --match-precision 0.9
```

Only files with very similar names will match (e.g., "file1.txt" and "file2.txt" won't match, but "report.txt" and "reprot.txt" will).

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

#### Basic one-way sync (without deletions)

Copy and update files from source to destination (extra files in destination are kept):

```bash
files sync /source/dir /backup/dir --dry-run --verbose
```

Output:
```
🔍 DRY RUN - No changes will be made

Would perform 4 operation(s)

Copy (3):
  would copy new-file.txt
  would copy docs/guide.md
  would copy src/main.swift

Update (1):
  would update config.yaml
```

Execute the sync:

```bash
files sync /source/dir /backup/dir --verbose
```

Output:
```
Performed 4 operation(s)

Copy (3):
  copied new-file.txt
  copied docs/guide.md
  copied src/main.swift

Update (1):
  updated config.yaml

Summary: 4 succeeded, 0 failed, 0 skipped
```

#### One-way sync with deletions

Mirror source to destination exactly (deletes extra files in destination):

```bash
files sync /source/dir /backup/dir --deletions --dry-run --verbose
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
files sync /source/dir /backup/dir --deletions --verbose
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

# Mirror production to backup with exact mirroring (including deletions)
echo "Checking what would change..."
files sync /production /backup --deletions --dry-run --format summary

read -p "Proceed with sync? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    files sync /production /backup --deletions --verbose
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

# Building

```
swift build -c release \
  -Xswiftc -O \
  -Xswiftc -whole-module-optimization \
  -Xswiftc -cross-module-optimization
```

# Installation

You can copy it to your PATH:

```bash
cp .build/release/files /usr/local/bin/
```

Or create a symlink:

```bash
ln -s $(pwd)/.build/release/files /usr/local/bin/files
```

LICENSE: MIT
