# TeamCraft deployment: `just --list` shows everything. Extra ansible-playbook options go after the
# recipe, e.g. `just install-all --check` or `just setup-all -e teamcraft_version=1.0.0`.

playbook := "ansible-playbook -i inventory/hosts setup.yml"

default:
    @just --list

# Install the Ansible collections the playbook uses
roles:
    ansible-galaxy collection install -r requirements.yml

# Install and start everything that is enabled (fast path for changes and updates)
install-all *args: roles
    {{ playbook }} --tags=install-all,start {{ args }}

# Like install-all, and also remove components you disabled
setup-all *args: roles
    {{ playbook }} --tags=setup-all,start {{ args }}

# Install one component, e.g. `just install-component keycloak` (names: docs/components/)
install-component component *args:
    {{ playbook }} --tags=install-{{ component }},start {{ args }}

# Start (or restart changed) services
start *args:
    {{ playbook }} --tags=start {{ args }}

# Stop all services
stop *args:
    {{ playbook }} --tags=stop {{ args }}

# Check the running instance from here and on the host
self-check *args:
    {{ playbook }} --tags=self-check {{ args }}

# Create or update a user of the bundled Keycloak: just ensure-admin alice 'long password' [owner|admin|member|guest]
ensure-admin username password role="owner" *args:
    {{ playbook }} --tags=ensure-admin -e username={{ quote(username) }} -e password={{ quote(password) }} -e role={{ role }} {{ args }}

# Run the backups now
backup *args:
    {{ playbook }} --tags=backup {{ args }}

# Update the playbook to its latest release (which pins the TeamCraft version), then install it
update:
    git pull --ff-only
    @echo "TeamCraft version: $(sed -n 's/^teamcraft_version: \"\(.*\)\"/\1/p' group_vars/teamcraft_servers.yml) (see CHANGELOG.md before running: just install-all)"

# Lint the playbook (CI runs the same)
lint:
    yamllint --strict .
    ansible-lint --profile production

# Deploy to a throwaway local container and test it end to end (test/dry-run.sh)
dry-run *args:
    test/dry-run.sh {{ args }}
