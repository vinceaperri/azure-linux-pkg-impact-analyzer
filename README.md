# Azure Linux Package Impact Analyzer

Analyzes the transitive removal impact of RPM packages on Azure Linux systems. For each installed
package, it computes which other packages would be removed if that package were uninstalled.

## Features

- Builds a complete reverse dependency graph from installed RPM packages
- Computes transitive dependencies for each package
- Calculates individual and cumulative package sizes
- Outputs results in CSV format for easy analysis

## Requirements

- Bash 4.0+
- RPM-based Linux distribution (Azure Linux, RHEL, Fedora, etc.)
- `rpm` command available

## Usage

```bash
./analyze-pkg-impact.sh [-g|--graph GRAPH_FILE] [-r|--refresh] OUTPUT_FILE
```

### Arguments

| Argument | Description |
|----------|-------------|
| `OUTPUT_FILE` | CSV file for analysis results (required) |
| `-g`, `--graph` | Path to save the dependency graph file (optional) |
| `-r`, `--refresh` | Regenerate the graph even if it already exists (optional) |

### Example

```bash
# Basic usage
./analyze-pkg-impact.sh results.csv

# Save dependency graph to a file
./analyze-pkg-impact.sh -g pkg-graph.txt results.csv

# Force regeneration of an existing graph
./analyze-pkg-impact.sh -g pkg-graph.txt -r results.csv
```

## Output Format

The script generates a CSV file with the following columns:

| Column | Description |
|--------|-------------|
| `Name` | Package name |
| `Package Size` | Human-readable size of the package itself |
| `Package Size (Bytes)` | Size of the package in bytes |
| `Total Removal Size` | Human-readable total size of all packages that would be removed |
| `Total Removal Size (Bytes)` | Total removal size in bytes |
| `Would Also Remove` | Semicolon-separated list of other packages that would be removed |

## How It Works

1. **Phase 1 - Graph Building**: Queries all installed packages and builds a reverse dependency
   graph (packages that require each package)
2. **Phase 2 - Analysis**: For each package, traverses the graph to find all transitively
   dependent packages and calculates cumulative sizes

## License

MIT
