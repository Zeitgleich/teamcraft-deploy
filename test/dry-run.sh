#!/usr/bin/env bash
# Dry run of the playbook: deploys to a throwaway local target and checks the result. The target is
# a systemd container (Debian trixie, test/target.Containerfile) on its own dual-stack Docker network;
# the playbook reaches it over SSH like a VPS. Everything is bundled (Keycloak, Garage), TLS comes
# from Caddy's internal CA, secrets are generated on the target.
#
#   test/dry-run.sh up        network, registry, target
#   test/dry-run.sh images    build server + SFU images from $TEAMCRAFT_REPO, push to the test registry
#   test/dry-run.sh deploy    just setup-all (twice: the second run must change nothing), test users
#   test/dry-run.sh verify    just self-check, health over IPv4 + IPv6, ports, SFU over QUIC, backups,
#                             messages between two users (TeamCraft's end-to-end harness)
#   test/dry-run.sh down      remove everything again
#   test/dry-run.sh all       up, images, deploy, verify (leaves the target running)
#
# Needs: docker (the target runs privileged, for nested rootless podman), podman (image builds),
# ansible-playbook, just, ssh, curl (HTTP/3 checks only with a curl built with HTTP/3), python3, and
# a TeamCraft checkout in $TEAMCRAFT_REPO (default ../teamcraft) with a Rust toolchain for the e2e test.
# DRY_RUN_BRANDS=1 adds two brands (test/inventory/brands.yml) and checks that each host name gets its
# own brand; it needs a TeamCraft that knows [[brands]].
# DRY_RUN_ANSIBLE_ARGS adds options to every playbook run, e.g. "-e teamcraft_debug=true -vv" to see
# the output of tasks that hide it because they handle secrets (test secrets only, here).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
teamcraft_repo="${TEAMCRAFT_REPO:-$repo/../teamcraft}"
state="${DRY_RUN_DIR:-$HOME/.cache/teamcraft-dry-run}"

network=tc-dryrun
subnet4=172.31.250.0/24
subnet6=fd00:7c:fa::/64
gateway4=172.31.250.1
registry_ip=172.31.250.5
target_ip4=172.31.250.10
target_ip6=fd00:7c:fa::10
target=tc-dryrun-target
registry=tc-dryrun-registry
domain=chat.172-31-250-10.sslip.io
sfu_domain=sfu.chat.172-31-250-10.sslip.io
id_domain=id.chat.172-31-250-10.sslip.io
s3_domain=s3.chat.172-31-250-10.sslip.io
# Test users: the password convention of TeamCraft's dev/dev-token.py.
users=(alice:owner carol:member)

step() { printf '\n==> %s\n' "$*"; }

wait_until() { # description, timeout seconds, command...
  local what="$1" timeout="$2"; shift 2
  local deadline=$((SECONDS + timeout))
  until "$@" >/dev/null 2>&1; do
    if [ "$SECONDS" -ge "$deadline" ]; then echo "timed out waiting for $what" >&2; return 1; fi
    sleep 2
  done
}

playbook() {
  # shellcheck disable=SC2086 # DRY_RUN_* options are split into words on purpose
  ANSIBLE_CONFIG="$repo/ansible.cfg" ANSIBLE_ROLES_PATH="$repo/roles" ansible-playbook \
    -i "$here/inventory/hosts" "$repo/setup.yml" --private-key "$state/id_ed25519" \
    -e "teamcraft_server_image=$(cat "$state/teamcraft-server.ref")" \
    -e "teamcraft_sfu_image=$(cat "$state/teamcraft-sfu.ref")" \
    ${DRY_RUN_BRANDS:+-e @$here/inventory/brands.yml} ${DRY_RUN_ANSIBLE_ARGS:-} "$@"
}

up() {
  mkdir -p "$state"
  chmod 700 "$state"
  step "Network $network ($subnet4, $subnet6)"
  docker network inspect "$network" >/dev/null 2>&1 \
    || docker network create --ipv6 --subnet "$subnet4" --gateway "$gateway4" --subnet "$subnet6" "$network"

  step "Registry"
  docker container inspect "$registry" >/dev/null 2>&1 \
    || docker run -d --name "$registry" --network "$network" --ip "$registry_ip" docker.io/library/registry:3

  step "Target"
  docker build -q -t teamcraft-dry-run-target:local -f "$here/target.Containerfile" "$here"
  if ! docker container inspect "$target" >/dev/null 2>&1; then
    # /home on a volume: the services' podman storage needs a real filesystem, not overlayfs.
    docker run -d --name "$target" --hostname dry-run-target --privileged --cgroupns=private \
      --network "$network" --ip "$target_ip4" --ip6 "$target_ip6" \
      --tmpfs /run --tmpfs /run/lock -v tc-dryrun-home:/home \
      teamcraft-dry-run-target:local
  fi
  wait_until "the target's systemd" 60 docker exec "$target" systemctl is-system-running --wait

  # Docker's embedded DNS (127.0.0.11) works through NAT rules in the container's netns, which the
  # playbook's firewall replaces (flush ruleset), as it would on a VPS. Use a plain resolver instead.
  docker exec "$target" sh -c "printf 'nameserver ${DRY_RUN_DNS:-9.9.9.9}\n' > /etc/resolv.conf"

  step "SSH key"
  [ -f "$state/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C teamcraft-dry-run -f "$state/id_ed25519"
  docker exec -i "$target" sh -c 'cat > /home/deploy/.ssh/authorized_keys && chown -R deploy:deploy /home/deploy/.ssh && chmod 600 /home/deploy/.ssh/authorized_keys' < "$state/id_ed25519.pub"

  step "Test registry is trusted inside the target (plain HTTP)"
  docker exec "$target" sh -c "mkdir -p /etc/containers/registries.conf.d && printf '[[registry]]\nlocation = \"$registry_ip:5000\"\ninsecure = true\n' > /etc/containers/registries.conf.d/50-dry-run.conf"
}

images() {
  step "Images from $teamcraft_repo ($(git -C "$teamcraft_repo" rev-parse --short HEAD))"
  local name
  for name in teamcraft-server teamcraft-sfu; do
    podman build --format docker -f "$teamcraft_repo/containers/$name.Containerfile" -t "localhost/$name:dry-run" "$teamcraft_repo"
    podman push --tls-verify=false --digestfile "$state/$name.digest" \
      "localhost/$name:dry-run" "docker://$registry_ip:5000/zeitgleich/$name:dry-run"
    # Pinned by digest, as a release is.
    echo "$registry_ip:5000/zeitgleich/$name@$(cat "$state/$name.digest")" > "$state/$name.ref"
    cat "$state/$name.ref"
  done
}

deploy() {
  step "Playbook: setup-all, start"
  playbook --tags=setup-all,start
  step "Playbook again (idempotence: nothing may change)"
  playbook --tags=setup-all,start | tee "$state/second-run.log"
  if ! grep -Eq 'changed=0 +unreachable=0 +failed=0' "$state/second-run.log"; then
    echo "the second run changed something" >&2
    return 1
  fi
  step "Test users (ensure-admin)"
  local pair
  for pair in "${users[@]}"; do
    playbook --tags=ensure-admin -e "username=${pair%%:*}" -e "password=${pair%%:*}-dev-pass" -e "role=${pair#*:}"
  done
}

verify() {
  local ca="$state/caddy-root.crt"
  docker exec "$target" cat /home/tc-proxy/caddy-data/caddy/pki/authorities/local/root.crt > "$ca"
  local failed=0
  check() { # description, command...
    local what="$1"; shift
    if "$@" >/dev/null 2>&1; then echo "ok    $what"; else echo "FAIL  $what"; failed=1; fi
  }
  # QUIC checks need a curl built with HTTP/3 (Fedora's is; Ubuntu's isn't): skipped, not failed.
  check_http3() { # description, command...
    if curl -V | grep -q HTTP3; then check "$@"; else echo "skip  $1 (curl without HTTP/3)"; fi
  }
  step "just self-check"
  check "self-check" playbook --tags=self-check
  step "Checks"
  local ip
  for ip in "$target_ip4" "[$target_ip6]"; do
    local bare="${ip//[\[\]]/}"
    local resolve="$domain:443:$bare"
    check "readyz over $ip" curl -fsS --cacert "$ca" --resolve "$resolve" "https://$domain/readyz"
    check "internal API refused over $ip" sh -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --cacert '$ca' --resolve '$resolve' -X POST https://$domain/api/internal/v1/calls/participants/joined)\" = 404 ]"
    check "Keycloak realm over $ip" curl -fsS --cacert "$ca" --resolve "$id_domain:443:$bare" "https://$id_domain/realms/teamcraft/.well-known/openid-configuration"
    check "Keycloak admin console not public over $ip" sh -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --cacert '$ca' --resolve '$id_domain:443:$bare' https://$id_domain/admin/master/console/)\" = 404 ]"
    check "S3 CORS preflight over $ip" sh -c "curl -sS -o /dev/null -D - -X OPTIONS -H 'Origin: https://$domain' --cacert '$ca' --resolve '$s3_domain:443:$bare' https://$s3_domain/teamcraft/x | grep -qi 'access-control-allow-origin: https://$domain'"
    check_http3 "HTTP/3 to Caddy over $ip" curl -fsS --http3-only --cacert "$ca" --resolve "$resolve" "https://$domain/healthz"
    # The QUIC handshake with a verified certificate proves UDP 4433 reachable and the exported
    # certificate in use; the SFU then closes the plain HTTP/3 request (it only speaks WebTransport).
    check_http3 "SFU QUIC + TLS over $ip" sh -c "curl -v -m 10 --http3-only --cacert '$ca' --resolve '$sfu_domain:4433:$bare' https://$sfu_domain:4433/ 2>&1 | grep -q 'SSL certificate verified'"
  done
  # shellcheck disable=SC2016 # expands inside the target, not here
  check "SFU restarts for a renewed certificate" docker exec "$target" sh -c '
    uid=$(id -u tc-sfu); run() { XDG_RUNTIME_DIR=/run/user/$uid runuser -u tc-sfu -- "$@"; }
    before=$(run systemctl --user show -p ExecMainPID --value teamcraft-sfu.service)
    touch /srv/teamcraft/certs/sfu.crt; sleep 5
    after=$(run systemctl --user show -p ExecMainPID --value teamcraft-sfu.service)
    [ "$before" != "$after" ] && run systemctl --user is-active teamcraft-sfu.service'
  local port
  for port in 5432 8080 8081 8180 9180 3900 3901 3903; do
    check "port $port not reachable from outside" sh -c "! timeout 3 bash -c \"exec 3<>/dev/tcp/$target_ip4/$port\" 2>/dev/null"
  done
  check "firewall drops other ports" sh -c "! curl -s -m 3 http://$target_ip4:9999/"
  if [ -n "${DRY_RUN_BRANDS:-}" ]; then
    step "Brands"
    local brand_b=chat-b.172-31-250-10.sslip.io
    check "default host serves Brand A" sh -c "curl -fsS --cacert '$ca' --resolve '$domain:443:$target_ip4' https://$domain/api/v1/brand | grep -q '\"display_name\": *\"Brand A\"'"
    check "brand host serves Brand B (IPv4)" sh -c "curl -fsS --cacert '$ca' --resolve '$brand_b:443:$target_ip4' https://$brand_b/api/v1/brand | grep -q '\"display_name\": *\"Brand B\"'"
    check "brand host serves Brand B (IPv6)" sh -c "curl -fsS --cacert '$ca' --resolve '$brand_b:443:$target_ip6' https://$brand_b/api/v1/brand | grep -q '\"display_name\": *\"Brand B\"'"
    check "brand logo served" sh -c "curl -fsS --cacert '$ca' --resolve '$brand_b:443:$target_ip4' https://$brand_b/api/v1/brand/assets/logo | grep -q 7a3cd0"
    check "brand host readyz" curl -fsS --cacert "$ca" --resolve "$brand_b:443:$target_ip4" "https://$brand_b/readyz"
    # shellcheck disable=SC2016 # expands inside the target, not here
    check "Keycloak allows sign-in on the brand host" docker exec "$target" sh -c '
      uid=$(id -u tc-keycloak); kc() { XDG_RUNTIME_DIR=/run/user/$uid runuser -u tc-keycloak -- podman exec teamcraft-keycloak /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/kcadm-check.config; }
      kc config credentials --server http://127.0.0.1:8180 --realm master --user admin --password "$(cat /srv/teamcraft/secrets/keycloak_admin_password)" >/dev/null &&
      kc get clients -r teamcraft -q clientId=teamcraft -q exact=true | grep -q "https://chat-b.172-31-250-10.sslip.io/\*" &&
      kc get clients -r teamcraft -q clientId=teamcraft -q exact=true | grep -q "\"name\" : \"organization\""'
  fi
  step "Backups"
  check "backup now" playbook --tags=backup
  check "database dumps exist" docker exec "$target" sh -c 'ls /srv/teamcraft/backups/postgres/teamcraft-*.dump /srv/teamcraft/backups/postgres/keycloak-*.dump'
  # shellcheck disable=SC2016 # expands inside the target, not here
  check "dumps copied off-site" docker exec "$target" sh -c '
    uid=$(id -u tc-garage)
    XDG_RUNTIME_DIR=/run/user/$uid runuser -u tc-garage -- podman exec teamcraft-garage /garage bucket info teamcraft-backups \
      | grep -Eq "Objects: *[1-9]"'
  step "Stop and start"
  check "stop" playbook --tags=stop
  check "server stopped" sh -c "! curl -fsS -m 5 --cacert '$ca' --resolve '$domain:443:$target_ip4' https://$domain/readyz"
  check "start" playbook --tags=start
  wait_until "the server after start" 120 curl -fsS --cacert "$ca" --resolve "$domain:443:$target_ip4" "https://$domain/readyz" || failed=1
  step "Messages between two users (TeamCraft e2e harness)"
  if (cd "$teamcraft_repo" && SSL_CERT_FILE="$ca" DEV_TOKEN_ISSUER="https://$id_domain/realms/teamcraft" \
      E2E_DEPLOYED_URL="https://$domain" SQLX_OFFLINE=true \
      cargo test -q -p teamcraft-e2e --features e2e --test suite -- --exact deployed::a_deployed_instance_is_healthy_and_delivers_messages --nocapture); then
    echo "ok    e2e: login and encrypted messages both ways"
  else
    echo "FAIL  e2e: login and encrypted messages both ways"; failed=1
  fi
  return "$failed"
}

down() {
  step "Removing target, registry, network"
  docker rm -f "$target" "$registry" >/dev/null 2>&1 || true
  docker volume rm tc-dryrun-home >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  podman rmi localhost/teamcraft-server:dry-run localhost/teamcraft-sfu:dry-run >/dev/null 2>&1 || true
  rm -rf "$state"
}

case "${1:-}" in
  up) up ;;
  images) images ;;
  deploy) deploy ;;
  verify) verify ;;
  down) down ;;
  all) up; images; deploy; verify ;;
  *) sed -n '2,19p' "$0"; exit 2 ;;
esac
