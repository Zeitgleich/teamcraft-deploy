#!/usr/bin/env bash
# Dry run of the push gateway behind a web server the host already runs: an Ubuntu 24.04 systemd
# container (test/target.Containerfile) with Apache on 80/443 and a fake Plesk marker, like a Plesk
# server without nginx. The playbook installs the gateway without its Caddy; Apache gets the generated
# "Additional directives for HTTPS" inside its virtual host, as Plesk includes them.
#
#   test/gateway-dry-run.sh up        network, registry, target with Apache and a test CA certificate
#   test/gateway-dry-run.sh image     build the gateway image from $GATEWAY_REPO, push it to the registry
#   test/gateway-dry-run.sh deploy    preflight refusals, setup-all (twice: idempotence), Apache directives
#   test/gateway-dry-run.sh verify    self-check, the API through Apache over IPv4 + IPv6, what stays private
#   test/gateway-dry-run.sh down      remove everything again
#   test/gateway-dry-run.sh all       up, image, deploy, verify (leaves the target running)
#
# Needs: docker (privileged target, nested rootless podman), podman, ansible-playbook, ssh, curl, openssl
# and a teamcraft-push-gateway checkout in $GATEWAY_REPO (default ../teamcraft-push-gateway).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
gateway_repo="${GATEWAY_REPO:-$repo/../teamcraft-push-gateway}"
state="${DRY_RUN_DIR:-$HOME/.cache/teamcraft-gateway-dry-run}"

network=tc-gwdryrun
subnet4=172.31.251.0/24
subnet6=fd00:7c:fb::/64
gateway4=172.31.251.1
registry_ip=172.31.251.5
target_ip4=172.31.251.10
target_ip6=fd00:7c:fb::10
target=tc-gwdryrun-target
registry=tc-gwdryrun-registry
host=push-gw.172-31-251-10.sslip.io

step() { printf '\n==> %s\n' "$*"; }

playbook() {
  ANSIBLE_CONFIG="$repo/ansible.cfg" ANSIBLE_ROLES_PATH="$repo/roles" ansible-playbook \
    -i "$here/gateway-inventory/hosts" "$repo/setup.yml" --private-key "$state/id_ed25519" \
    -e "push_gateway_image=$(cat "$state/gateway.ref")" -e "@$state/credentials.yml" "$@"
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
  step "Target (Ubuntu 24.04)"
  docker build -q -t teamcraft-gateway-dry-run-target:local --build-arg BASE_IMAGE=docker.io/library/ubuntu:24.04 \
    -f "$here/target.Containerfile" "$here"
  if ! docker container inspect "$target" >/dev/null 2>&1; then
    docker run -d --name "$target" --hostname gateway-dry-run --privileged --cgroupns=private \
      --network "$network" --ip "$target_ip4" --ip6 "$target_ip6" \
      --tmpfs /run --tmpfs /run/lock -v tc-gwdryrun-home:/home \
      teamcraft-gateway-dry-run-target:local
  fi
  local i
  for i in $(seq 30); do
    docker exec "$target" systemctl is-system-running --wait >/dev/null 2>&1 && break
    [ "$i" = 30 ] && { echo "the target's systemd did not come up" >&2; return 1; }
    sleep 2
  done
  docker exec "$target" sh -c "printf 'nameserver ${DRY_RUN_DNS:-9.9.9.9}\n' > /etc/resolv.conf"
  [ -f "$state/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C teamcraft-gateway-dry-run -f "$state/id_ed25519"
  docker exec -i "$target" sh -c 'cat > /home/deploy/.ssh/authorized_keys && chown -R deploy:deploy /home/deploy/.ssh && chmod 600 /home/deploy/.ssh/authorized_keys' < "$state/id_ed25519.pub"
  docker exec "$target" sh -c "mkdir -p /etc/containers/registries.conf.d && printf '[[registry]]\nlocation = \"$registry_ip:5000\"\ninsecure = true\n' > /etc/containers/registries.conf.d/50-dry-run.conf"

  step "Test CA, certificate, throwaway credentials"
  if [ ! -f "$state/test-ca.crt" ]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj "/CN=Gateway dry run CA" \
      -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
      -keyout "$state/test-ca.key" -out "$state/test-ca.crt" 2>/dev/null
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj "/CN=$host" \
      -addext "subjectAltName=DNS:$host" -addext "basicConstraints=critical,CA:FALSE" \
      -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=serverAuth" \
      -CA "$state/test-ca.crt" -CAkey "$state/test-ca.key" -keyout "$state/web.key" -out "$state/web.crt" 2>/dev/null
    # An APNs key has this form (a P-256 key in PKCS#8); nothing is ever sent with it.
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$state/apns.p8"
    python3 -c 'import json,sys; print("push_gateway_apns_key: " + json.dumps(open(sys.argv[1]).read()))' "$state/apns.p8" > "$state/credentials.yml"
  fi

  step "Apache on 80/443 and a Plesk marker, as on the real host"
  docker exec "$target" sh -c 'command -v apache2 >/dev/null || (apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apache2 >/dev/null)'
  docker exec "$target" sh -c 'mkdir -p /etc/ssl/gateway-test /usr/local/psa && echo "18.0.81 Ubuntu 24.04 (fake for the dry run)" > /usr/local/psa/version'
  docker exec -i "$target" sh -c 'cat > /etc/ssl/gateway-test/cert.pem' < "$state/web.crt"
  docker exec -i "$target" sh -c 'cat > /etc/ssl/gateway-test/key.pem && chmod 600 /etc/ssl/gateway-test/key.pem' < "$state/web.key"
  # The vhost as Plesk would have it, the additional directives included from where the playbook writes them.
  docker exec -i "$target" sh -c 'cat > /etc/apache2/sites-available/push-gw.conf' <<EOF
<VirtualHost *:443>
    ServerName $host
    SSLEngine on
    SSLCertificateFile /etc/ssl/gateway-test/cert.pem
    SSLCertificateKeyFile /etc/ssl/gateway-test/key.pem
    IncludeOptional /srv/teamcraft/reverse-proxy/push-gateway/plesk-apache-https.conf
</VirtualHost>
EOF
  docker exec "$target" sh -c 'a2enmod -q ssl proxy proxy_http headers >/dev/null && a2ensite -q push-gw >/dev/null && apache2ctl configtest && systemctl restart apache2'
}

image() {
  step "Gateway image from $gateway_repo ($(git -C "$gateway_repo" rev-parse --short HEAD))"
  podman build --format docker -f "$gateway_repo/containers/teamcraft-push-gateway.Containerfile" \
    -t localhost/teamcraft-push-gateway:dry-run "$gateway_repo"
  podman push --tls-verify=false --digestfile "$state/gateway.digest" localhost/teamcraft-push-gateway:dry-run \
    "docker://$registry_ip:5000/zeitgleich/teamcraft-push-gateway:dry-run"
  echo "$registry_ip:5000/zeitgleich/teamcraft-push-gateway@$(cat "$state/gateway.digest")" > "$state/gateway.ref"
}

deploy() {
  # Podman 4.9 can't run its services where the host has a cgroup v1 hierarchy next to v2 (the
  # playbook's preflight says so); a container target inherits the host's.
  if grep -qv '^0::' /proc/self/cgroup; then
    echo "this machine mounts a cgroup v1 hierarchy ($(grep -v '^0::' /proc/self/cgroup | tr '\n' ' ')): Podman 4.9 in the target can't run services; use a VM or another machine" >&2
    return 1
  fi
  step "Preflight refuses the bundled Caddy next to Apache"
  if playbook --tags=install-push-gateway -e '{"push_gateway_caddy_enabled": true, "push_gateway_admin_email": "ops@example.com"}' \
      > "$state/preflight-caddy.log" 2>&1; then
    echo "the preflight check let Caddy in next to Apache" >&2; return 1
  fi
  grep -q 'Ports 80/443 belong to another web server' "$state/preflight-caddy.log"
  step "Preflight refuses the playbook's firewall on Plesk"
  if playbook --tags=install-push-gateway -e '{"base_firewall_enabled": true}' > "$state/preflight-firewall.log" 2>&1; then
    echo "the preflight check let the firewall replace Plesk's" >&2; return 1
  fi
  grep -q 'This host runs Plesk' "$state/preflight-firewall.log"
  step "Playbook: setup-all, start"
  playbook --tags=setup-all,start
  step "Apache with the generated directives"
  docker exec "$target" sh -c 'apache2ctl configtest && systemctl reload apache2'
  step "Playbook again (idempotence: nothing may change)"
  playbook --tags=setup-all,start | tee "$state/second-run.log"
  grep -Eq 'changed=0 +unreachable=0 +failed=0' "$state/second-run.log" || { echo "the second run changed something" >&2; return 1; }
}

verify() {
  local ca="$state/test-ca.crt" failed=0
  check() {
    local what="$1"; shift
    if "$@" >/dev/null 2>&1; then echo "ok    $what"; else echo "FAIL  $what"; failed=1; fi
  }
  step "just self-check"
  check "self-check" playbook --tags=self-check
  step "Checks"
  local ip
  for ip in "$target_ip4" "$target_ip6"; do
    local resolve="$host:443:$ip"
    check "info through Apache over $ip" sh -c "curl -fsS --cacert '$ca' --resolve '$resolve' https://$host/v1/info | grep -q apns"
    check "healthz not public over $ip" sh -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --cacert '$ca' --resolve '$resolve' https://$host/healthz)\" = 404 ]"
    check "metrics not public over $ip" sh -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --cacert '$ca' --resolve '$resolve' https://$host/metrics)\" = 404 ]"
  done
  local port
  for port in 8090 8091; do
    check "port $port not reachable from outside" sh -c "! timeout 3 bash -c \"exec 3<>/dev/tcp/$target_ip4/$port\" 2>/dev/null"
  done
  check "no Caddy, no tc-gwproxy service" docker exec "$target" sh -c '! ss -Htlnp | grep -q caddy'
  check "Apache still owns 80/443" docker exec "$target" sh -c 'ss -Htlnp "( sport = :443 )" | grep -q apache2 && ss -Htlnp "( sport = :80 )" | grep -q apache2'
  # shellcheck disable=SC2016 # expands inside the target, not here
  check "unprivileged users can't bind web ports" docker exec "$target" sh -c '[ "$(sysctl -n net.ipv4.ip_unprivileged_port_start)" = 1024 ]'
  # shellcheck disable=SC2016 # expands inside the target, not here
  check "firewall left alone" docker exec "$target" sh -c '! [ -e /etc/nftables.conf ] && ! nft list ruleset 2>/dev/null | grep -q "table inet filter"'
  check "client address from X-Forwarded-For (gateway config)" docker exec "$target" grep -q 'client_ip_header = "x-forwarded-for"' /home/tc-gateway/config/gateway.toml
  check "podman from Ubuntu's archive" docker exec "$target" sh -c 'podman --version && dpkg -s podman | grep -q "^Version: 4\."'
  step "Stop and start"
  check "stop" playbook --tags=stop
  check "gateway stopped (Apache answers 503)" sh -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --cacert '$ca' --resolve '$host:443:$target_ip4' https://$host/v1/info)\" = 503 ]"
  check "start" playbook --tags=start
  check "gateway back" sh -c "for i in \$(seq 30); do curl -fsS --cacert '$ca' --resolve '$host:443:$target_ip4' https://$host/v1/info && exit 0; sleep 2; done; exit 1"
  return "$failed"
}

down() {
  step "Removing target, registry, network"
  docker rm -f "$target" "$registry" >/dev/null 2>&1 || true
  docker volume rm tc-gwdryrun-home >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  podman rmi localhost/teamcraft-push-gateway:dry-run >/dev/null 2>&1 || true
  rm -rf "$state"
}

case "${1:-}" in
  up) up ;;
  image) image ;;
  deploy) deploy ;;
  verify) verify ;;
  down) down ;;
  all) up; image; deploy; verify ;;
  *) sed -n '2,15p' "$0"; exit 2 ;;
esac
