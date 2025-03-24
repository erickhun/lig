#!/bin/bash
#
# lig.sh - Simple integration between Linear and fzf for git branch creation
# Usage: source lig.sh && lig-branch
#


# Function to check if current directory is a Git repository
check_git_repo() {
    # Check if .git directory exists or if git status works
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo "Error: Not in a Git repository."
        echo "Please navigate to a Git repository and try again."
        return 1
    fi
    return 0
}

# Function to create git branches from Linear issues using fzf
function lig-branch() {

  check_git_repo || return 1
  # Get Linear API key from environment
  local api_key=${LINEAR_KEY}
  
  if [ -z "$api_key" ]; then
    echo "LINEAR_KEY environment variable not set"
    return 1
  fi
  
  # Check current branch and git status
  local current_branch=$(git branch --show-current)
  local git_status=$(git status --porcelain)
  
  if [ -n "$git_status" ]; then
    echo "Warning: You have uncommitted changes in your working directory."
    echo "Current branch: $current_branch"
    echo ""
    echo "You may want to commit or stash your changes before switching branches."
    echo -n "Continue anyway? [y/N] "
    read continue_answer
    
    if [[ ! "$continue_answer" =~ ^[Yy]$ ]]; then
      echo "Operation cancelled. Please commit or stash your changes first."
      return 0
    fi
  fi
  
  # Process command line arguments
  local filter_type="me"  # Default filter: only my issues
  local pagination="50"   # Default pagination: 50 issues
  
  if [ "$1" = "all" ]; then
    filter_type="all"
  elif [ "$1" = "me" ]; then
    filter_type="me"
  fi
  
  # Allow setting pagination as a second argument
  if [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
    pagination="$2"
  fi
  
  # Select query based on filter type
  if [ "$filter_type" = "all" ]; then
    echo "Fetching all issues (limit: $pagination)..."
    query="{\"query\":\"query { issues(first: $pagination, orderBy: updatedAt) { nodes { identifier title state { name } dueDate priority assignee { name } } } }\"}"
  else
    echo "Fetching your assigned issues (limit: $pagination)..."
    query="{\"query\":\"query { issues(first: $pagination, orderBy: updatedAt, filter: { assignee: { isMe: { eq: true } } }) { nodes { identifier title state { name } dueDate priority } } }\"}"
  fi
  
  # Get issues from Linear API
  response=$(curl \
    --header "Content-Type: application/json" \
    --header "Authorization: $api_key" \
    --silent \
    --data "$query" \
    "https://api.linear.app/graphql")
  
  # Create a mapping file to store issue ID -> title mappings
  id_to_title_file=$(mktemp)
  display_file=$(mktemp)
  
  # Sanitize response and extract issues
  echo "$response" | tr -d '\000-\037' | grep -o '"identifier":"[^"]*","title":"[^"]*"' | 
  while read -r line; do
    # Extract identifier and title
    identifier=$(echo "$line" | grep -o '"identifier":"[^"]*"' | cut -d'"' -f4)
    title=$(echo "$line" | grep -o '"title":"[^"]*"' | cut -d'"' -f4)
    
    # Skip issues with empty titles
    if [ -z "$title" ] || [ "$title" = "null" ]; then
      continue
    fi
    
    # Get state, due date and priority from response
    state_data=$(echo "$response" | tr -d '\000-\037' | grep -o "\"identifier\":\"$identifier\",\"title\":\"[^\"]*\",\"state\":{\"name\":\"[^\"]*\"},\"dueDate\":[^,]*,\"priority\":[0-9]*")
    
    # Extract state
    state=$(echo "$state_data" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
    
    # Skip issues with "Done" state
    if [[ "$state" == "Done" ]]; then
      continue
    fi
    
    # Store mapping for non-Done issues
    echo "$identifier|$title" >> "$id_to_title_file"
    
    # Extract priority
    priority=$(echo "$state_data" | grep -o '"priority":[0-9]*' | cut -d':' -f2)
    case $priority in
      1) 
        priority_display="\033[1;31m[Urgent]\033[0m"
        sort_key="1"
        ;;
      2) 
        priority_display="\033[0;31m[High]\033[0m"
        sort_key="2"
        ;;
      3) 
        priority_display="\033[0;33m[Medium]\033[0m"
        sort_key="3"
        ;;
      4) 
        priority_display="\033[0;32m[Low]\033[0m"
        sort_key="4"
        ;;
      *) 
        priority_display="\033[0;37m[No priority]\033[0m"
        sort_key="5"
        ;;
    esac
    
    # Extract due date
    due_date=$(echo "$state_data" | grep -o '"dueDate":[^,]*' | cut -d':' -f2)
    if [ "$due_date" = "null" ]; then
      due_display="\033[0;37m[No due date]\033[0m"
      due_sort="9999-99-99"
    else
      # Remove quotes
      due_date=$(echo "$due_date" | tr -d '"')
      today=$(date +%Y-%m-%d)
      
      if [ "$due_date" = "$today" ]; then
        due_display="\033[1;33m[Today]\033[0m"
      elif [[ "$due_date" < "$today" ]]; then
        due_display="\033[1;31m[Overdue: $due_date]\033[0m"
      else
        # Check if within next week
        next_week=$(date -d "+7 days" +%Y-%m-%d 2>/dev/null || date -v+7d +%Y-%m-%d 2>/dev/null)
        if [[ "$due_date" < "$next_week" ]]; then
          due_display="\033[0;33m[Due: $due_date]\033[0m"
        else
          due_display="\033[0;32m[Due: $due_date]\033[0m"
        fi
      fi
      due_sort="$due_date"
    fi
    
    # Get assignee name if we're using the 'all' filter
    if [ "$filter_type" = "all" ]; then
      # Create display line without assignee info (simplified for 'all' filter)
      state_display="\033[0;36m[$state]\033[0m"
      echo "$sort_key|$due_sort|$priority_display $state_display $due_display $identifier - $title" >> "$display_file"
    else
      # Create display line without assignee info (for 'me' filter)
      state_display="\033[0;36m[$state]\033[0m"
      echo "$sort_key|$due_sort|$priority_display $state_display $due_display $identifier - $title" >> "$display_file"
    fi
  done
  
  # Sort issues by priority and due date
  issues_list=$(sort -t '|' -k1,1 -k2,2 "$display_file" | cut -d'|' -f3-)
  
  if [ -z "$issues_list" ]; then
    echo "No issues found or unable to parse response."
    rm "$id_to_title_file" "$display_file"
    return 1
  fi
  
  # Use fzf to select an issue with ANSI color support
  selected=$(echo "$issues_list" | fzf --height 40% --reverse --ansi)
  
  if [ -z "$selected" ]; then
    echo "No issue selected."
    rm "$id_to_title_file" "$display_file"
    return 0
  fi
  
  # Extract issue ID from selection
  issue_id=$(echo "$selected" | grep -o '[A-Z0-9]\+-[0-9]\+')
  
  if [ -z "$issue_id" ]; then
    echo "Could not extract issue ID from selection."
    rm "$id_to_title_file" "$display_file"
    return 1
  fi
  
  # Get title from mapping file
  issue_title=$(grep "^$issue_id|" "$id_to_title_file" | cut -d'|' -f2)
  
  # Clean up
  rm "$id_to_title_file" "$display_file"
  
  # Create branch name - make sure there are no newlines
  clean_title=$(echo "$issue_title" | tr -d '\n\r' | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]' '-')
  
  # Get only the raw issue ID without any date prefix
  issue_id_clean=$(echo "$issue_id" | tr -d '\n\r')
  
  # Create branch name with the pattern identifier/title
  branch_name="${issue_id_clean}/${clean_title}"
  
  echo "Creating branch for issue: $issue_id"
  echo "Title: $issue_title"
  echo "Branch name: $branch_name"
  echo -n "Continue? [Y/n] "
  read answer
  
  if [[ "$answer" =~ ^[Nn]$ ]]; then
    echo "Cancelled."
    return 0
  fi
  
  # Debug output to verify no newlines
  printf "Creating branch: '%s'\n" "$branch_name"
  
  # Check if branch already exists (locally or remotely)
  if git show-ref --verify --quiet "refs/heads/$branch_name" || git show-ref --verify --quiet "refs/remotes/origin/$branch_name"; then
    echo "Branch '$branch_name' already exists."
    
    # Ask if user wants to check out existing branch
    echo -n "Do you want to check out this existing branch? [Y/n] "
    read checkout_answer
    
    if [[ ! "$checkout_answer" =~ ^[Nn]$ ]]; then
      git checkout "$branch_name"
      if [ $? -eq 0 ]; then
        echo "Switched to branch '$branch_name'"
      else
        echo "Error checking out branch. Please check your git configuration."
      fi
    fi
    
    return 0
  fi
  
  # Create git branch - ensure the branch name is passed as a single argument
  git checkout -b "$branch_name"
  
  if [ $? -eq 0 ]; then
    echo "Branch created successfully: $branch_name"
  else
    echo "Error creating branch. Please check your git configuration."
  fi
}

# Open a Linear issue from terminal
function lig-view() {
  check_git_repo || return 1
  local issue_id
  
  # Get the issue ID from either the argument or branch name
  if [ -n "$1" ]; then
    issue_id=$1
  else
    # Try to extract from current branch name
    current_branch=$(git branch --show-current)
    issue_id=$(echo $current_branch | grep -o '^[A-Z0-9]\+-[0-9]\+' || echo "")
  fi
  
  if [ -n "$issue_id" ]; then
    # Try to open with xdg-open (Linux), open (macOS), or start (Windows)
    if command -v xdg-open &> /dev/null; then
      xdg-open "https://linear.app/issue/$issue_id"
    elif command -v open &> /dev/null; then
      open "https://linear.app/issue/$issue_id"
    elif command -v start &> /dev/null; then
      start "https://linear.app/issue/$issue_id"
    else
      echo "Cannot open browser. URL: https://linear.app/issue/$issue_id"
    fi
  else
    echo "No issue ID provided or found in branch name."
    return 1
  fi
}

# Update the status of a Linear issue
function lig-status() {
  check_git_repo || return 1
  local api_key issue_id team_id
  
  # Get the issue ID from either the argument or branch name
  if [ -n "$1" ]; then
    issue_id=$1
  else
    # Try to extract from current branch name
    current_branch=$(git branch --show-current)
    issue_id=$(echo $current_branch | grep -o '^[A-Z0-9]\+-[0-9]\+' || echo "")
  fi
  
  if [ -z "$issue_id" ]; then
    echo "No issue ID provided or found in branch name."
    return 1
  fi
  
  # Get API key from LINEAR_KEY environment variable
  api_key=${LINEAR_KEY}
  
  if [ -z "$api_key" ]; then
    echo "LINEAR_KEY environment variable not set"
    return 1
  fi
  
  # First get the issue to determine its team and other details
  echo "Fetching issue information..."
  issue_query="{\"query\":\"query { issue(id: \\\"$issue_id\\\") { id title priority dueDate assignee { name } team { id name } state { name } } }\"}"
  
  issue_response=$(curl \
    --header "Content-Type: application/json" \
    --header "Authorization: $api_key" \
    --silent \
    --data "$issue_query" \
    "https://api.linear.app/graphql")
  
  # Extract team ID with grep and sed
  team_id=$(echo "$issue_response" | grep -o '"team":{"id":"[^"]*","name":"[^"]*"}' | 
    sed 's/"team":{"id":"\([^"]*\)","name":"\([^"]*\)"}/\1/')
  
  team_name=$(echo "$issue_response" | grep -o '"team":{"id":"[^"]*","name":"[^"]*"}' | 
    sed 's/"team":{"id":"\([^"]*\)","name":"\([^"]*\)"}/\2/')
  
  # Extract issue title
  issue_title=$(echo "$issue_response" | grep -o '"title":"[^"]*"' | head -1 | sed 's/"title":"//;s/"//')
  
  # Extract current state
  current_state=$(echo "$issue_response" | grep -o '"state":{"name":"[^"]*"}' | sed 's/"state":{"name":"//;s/"}//')
  
  # Extract priority
  priority=$(echo "$issue_response" | grep -o '"priority":[0-9]*' | cut -d':' -f2)
  case $priority in
    1) priority_display="Urgent" ;;
    2) priority_display="High" ;;
    3) priority_display="Medium" ;;
    4) priority_display="Low" ;;
    *) priority_display="No priority" ;;
  esac
  
  # Extract due date
  due_date=$(echo "$issue_response" | grep -o '"dueDate":[^,}]*' | cut -d':' -f2 | tr -d '"')
  if [ "$due_date" = "null" ]; then
    due_date_display="No due date"
  else
    due_date_display="$due_date"
  fi
  
  # Extract assignee
  assignee=$(echo "$issue_response" | grep -o '"assignee":{"name":"[^"]*"}' | sed 's/"assignee":{"name":"//;s/"}//')
  if [ -z "$assignee" ] || [ "$assignee" = "null" ]; then
    assignee_display="Unassigned"
  else
    assignee_display="$assignee"
  fi
  
  if [ -z "$team_id" ]; then
    echo "Failed to fetch issue team information"
    echo "Raw response: $issue_response"
    return 1
  fi
  
  # Display issue details
  echo "----------------------------------------------"
  echo "ISSUE: $issue_id - $issue_title"
  echo "----------------------------------------------"
  echo "Team:      $team_name"
  echo "Status:    $current_state"
  echo "Priority:  $priority_display"
  echo "Due Date:  $due_date_display"
  echo "Assignee:  $assignee_display"
  echo "----------------------------------------------"
  
  # Get workflow states for this specific team
  echo "Fetching workflow states for team..."
  
  states_query="{\"query\":\"query { team(id: \\\"$team_id\\\") { states { nodes { id name type } } } }\"}"
  
  states_response=$(curl \
    --header "Content-Type: application/json" \
    --header "Authorization: $api_key" \
    --silent \
    --data "$states_query" \
    "https://api.linear.app/graphql")
  
  # Create a temporary file for mapping between displayed state names and their IDs
  temp_map_file=$(mktemp)
  
  # Extract states and create a display list and mapping file
  echo "$states_response" | grep -o '"id":"[^"]*","name":"[^"]*","type":"[^"]*"' | 
  while read -r line; do
    state_id=$(echo "$line" | sed -E 's/"id":"([^"]*)","name":"[^"]*","type":"[^"]*"/\1/')
    state_name=$(echo "$line" | sed -E 's/"id":"[^"]*","name":"([^"]*)","type":"[^"]*"/\1/')
    state_type=$(echo "$line" | sed -E 's/"id":"[^"]*","name":"[^"]*","type":"([^"]*)"/\1/')
    
    # Write to mapping file - tab separated to handle spaces in names
    echo -e "${state_name} (${state_type})\t${state_id}" >> "$temp_map_file"
  done
  
  # Check if we got any states
  if [ ! -s "$temp_map_file" ]; then
    echo "Failed to fetch workflow states for team"
    echo "Raw response: $states_response"
    rm "$temp_map_file"
    return 1
  fi
  
  # Use fzf to select a state - display only the state names
  echo "Select a new status for issue $issue_id:"
  selected_display=$(cut -f1 "$temp_map_file" | fzf --height 40% --reverse)
  
  if [ -z "$selected_display" ]; then
    echo "No workflow state selected."
    rm "$temp_map_file"
    return 1
  fi
  
  # Get the state ID from our mapping file
  selected_id=$(grep -F "$selected_display"$'\t' "$temp_map_file" | cut -f2)
  
  # Clean up temp file
  rm "$temp_map_file"
  
  if [ -z "$selected_id" ]; then
    echo "Error: Could not find ID for the selected state."
    return 1
  fi
  
  # Extract readable state name from the selection (remove the type part)
  state_name=$(echo "$selected_display" | sed -E 's/^([^ ]+).*$/\1/')
  
  # Update the issue
  echo "Updating issue $issue_id to state: $state_name (ID: $selected_id)..."
  
  update_query="{\"query\":\"mutation { issueUpdate(id: \\\"$issue_id\\\", input: { stateId: \\\"$selected_id\\\" }) { success } }\"}"
  
  update_response=$(curl \
    --header "Content-Type: application/json" \
    --header "Authorization: $api_key" \
    --silent \
    --data "$update_query" \
    "https://api.linear.app/graphql")
  
  # Check for success with simple grep
  if echo "$update_response" | grep -q '"success":true'; then
    echo "Successfully updated issue $issue_id to status: $state_name"
  else
    echo "Failed to update issue status."
    echo "Response: $update_response"
  fi
}

