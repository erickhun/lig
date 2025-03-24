# Linear Issue GitFlow (lig)

`lig`  integration between Linear (project management tool) and Git. Quickly create branches from issues assigned to you, view issues, and update issue statuses directly from the terminal.

![Demo of the project](lig-demo.gif)


## Features

- 🌿 **Branch Creation**: Easily create Git branches from Linear issues
- 👀 **Issue Viewing**: Open Linear issues directly from the terminal
- 🔄 **Status Updates**: Update issue statuses with an interactive workflow

## Prerequisites

- `fzf` ([fuzzy finder](https://github.com/junegunn/fzf?tab=readme-ov-file#installation))
- [Linear](https://linear.app/) API key (Settings-> Security & Access -> Personal API Keys)

## Installation

0. Get your [Linear](https://linear.app/) API key (Settings-> Security & Access -> Personal API Keys))
1. `git clone git@github.com:erickhun/lig.git`
2. Source the script in your shell configuration (`.bashrc` or `.zshrc`):

   ```bash
   export LINEAR_KEY="your_api_key"
   source /path/to/lig.sh
   ```

## Usage

### `lig-branch`

Create a new Git branch from a Linear issue.

```bash
# Fetch your assigned issues (limit to 50)
lig-branch

# Customize number of issues fetched
lig-branch me 100

# Fetch all teams issues
lig-branch all
```


### Open a Linear issue in your default browser.

```bash
# Open issue by ID
lig-view ABC-123

# Open issue from current branch name
lig-view
```

### Update the status of a Linear issue.

```bash
# Update status for a specific issue
lig-status ABC-123

# Update status for current branch's issue
lig-status
```


## Diclaimer
This tool was create with the help of Claude