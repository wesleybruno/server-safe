# Idempotent: skips the install step if docker is already present, but
# always (re)ensures the service is enabled and running.
FAMILY=$(distro_family)

if command -v docker &>/dev/null; then
  echo "==> docker ja instalado, pulando instalacao"
else
  if [[ "$FAMILY" == "debian" ]]; then
    echo "==> instalando docker via repositorio oficial (apt)"
    ensure_installed curl curl
    ensure_installed gpg gnupg

    install -m 0755 -d /etc/apt/keyrings
    . /etc/os-release
    curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    ARCH=$(dpkg --print-architecture)
    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" \
      > /etc/apt/sources.list.d/docker.list

    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      docker-ce docker-ce-cli containerd.io docker-compose-plugin
  else
    echo "==> instalando docker via repositorio oficial (dnf/yum)"
    if command -v dnf &>/dev/null; then
      dnf -y -q install dnf-plugins-core
      dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      dnf install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin
    else
      yum install -y -q yum-utils
      yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      yum install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin
    fi
  fi
fi

echo "==> habilitando servico docker"
systemctl enable --now docker

echo "==> validando"
systemctl is-active --quiet docker || fail "servico docker nao esta ativo"
command -v docker &>/dev/null || fail "binario docker nao encontrado apos instalacao"

DOCKER_VERSION=$(json_escape "$(docker --version 2>/dev/null)")

echo "==> ok"
result "ok" "docker instalado e ativo" "{\"version\":\"$DOCKER_VERSION\"}"
