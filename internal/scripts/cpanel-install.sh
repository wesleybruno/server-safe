# cPanel/WHM: so suporta AlmaLinux/CloudLinux/RHEL, exige licenca paga, e
# assume controle total da maquina (proprio firewall/servicos) — bem
# diferente dos outros extras, por isso o gate de distro explicito abaixo.
# Instalador oficial roda como root via este painel local-only — mesmo trust
# boundary do admin rodando na mao.
FAMILY=$(distro_family)
[[ "$FAMILY" == "rhel" ]] || fail "cPanel/WHM so suporta AlmaLinux/CloudLinux/RHEL — esta maquina e da familia $FAMILY"

[[ -x /usr/local/cpanel/cpanel ]] && fail "cpanel ja esta instalado"

echo "==> baixando instalador oficial da cpanel (demora 1-2h, exige licenca)"
ensure_installed curl curl
cd /home
curl -o latest -L https://securedownloads.cpanel.net/latest
sh latest

echo "==> validando"
[[ -x /usr/local/cpanel/cpanel ]] || fail "instalacao do cpanel nao confirmada"

IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo "==> ok"
result "ok" "cpanel instalado" "{\"url\":\"https://${IP:-SEU_IP}:2087\"}"
