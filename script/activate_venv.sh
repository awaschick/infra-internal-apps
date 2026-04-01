is_venv_active() {
    if [ -n "$VIRTUAL_ENV" ]; then
        return 0  # True, a virtual environment is active
    else
        return 1  # False, no virtual environment is active
    fi
}

# Example usage
if is_venv_active; then
    echo "Virtual environment is active: $VIRTUAL_ENV"
else
    echo "No virtual environment is active
fi