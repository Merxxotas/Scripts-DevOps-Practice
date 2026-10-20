#!/usr/bin/env bash
#
# GitHub Actions CI/CD Setup Script
# 
# This script helps you set up GitHub Actions workflows for your project.
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not a git repository. Please run this script from your project root."
        exit 1
    fi
}

# Function to copy workflow files
copy_workflows() {
    local target_dir="${1:-.}"
    
    print_info "Copying GitHub Actions workflow files..."
    
    # Create .github/workflows directory if it doesn't exist
    mkdir -p "$target_dir/.github/workflows"
    
    # Copy workflow files
    cp "$SCRIPT_DIR/.github/workflows/"*.yml "$target_dir/.github/workflows/"
    
    print_success "Workflow files copied to $target_dir/.github/workflows/"
}

# Function to display next steps
show_next_steps() {
    echo ""
    echo "========================================="
    echo "  Setup Complete! Next Steps:"
    echo "========================================="
    echo ""
    echo "1. Commit the workflow files:"
    echo "   git add .github/workflows/"
    echo "   git commit -m 'Add GitHub Actions CI/CD pipeline'"
    echo ""
    echo "2. Push to GitHub:"
    echo "   git push origin main"
    echo ""
    echo "3. Configure secrets (optional, for Docker Hub):"
    echo "   Go to: https://github.com/YOUR_USERNAME/YOUR_REPO/settings/secrets/actions"
    echo "   Add: DOCKER_USERNAME and DOCKER_PASSWORD"
    echo ""
    echo "4. View your workflows:"
    echo "   https://github.com/YOUR_USERNAME/YOUR_REPO/actions"
    echo ""
    echo "5. Read the full documentation:"
    echo "   cat GitHub-Actions-CI-CD/README.md"
    echo ""
}

# Main function
main() {
    echo "========================================="
    echo "  GitHub Actions CI/CD Setup"
    echo "========================================="
    echo ""
    
    # Check if we're in a git repo
    check_git_repo
    
    # Check if this is the project root (has Stage2-Python-Unified or similar)
    if [[ ! -d "Stage2-Python-Unified" && ! -d "Stage3-Containerization" ]]; then
        print_warning "Could not find Stage2-Python-Unified or Stage3-Containerization directories."
        print_warning "Make sure you're running this from the project root."
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Ask for target directory
    echo ""
    read -p "Enter target directory (default: current directory): " target_dir
    target_dir="${target_dir:-.}"
    
    # Copy workflows
    copy_workflows "$target_dir"
    
    # Show next steps
    show_next_steps
    
    print_success "Setup complete!"
}

# Run main function
main "$@"
