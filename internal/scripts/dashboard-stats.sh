# Read-only, sem mudar nada no sistema. CPU% exige duas amostras de
# /proc/stat com um intervalo entre elas — por isso essa chamada demora uns
# 0.2s, aceitavel pra um poll de dashboard, nao pra algo latency-sensitive.
read -r _ u1 n1 s1 i1 w1 irq1 sirq1 steal1 _ < /proc/stat
sleep 0.2
read -r _ u2 n2 s2 i2 w2 irq2 sirq2 steal2 _ < /proc/stat

idle1=$((i1 + w1)); idle2=$((i2 + w2))
total1=$((u1 + n1 + s1 + i1 + w1 + irq1 + sirq1 + steal1))
total2=$((u2 + n2 + s2 + i2 + w2 + irq2 + sirq2 + steal2))
idle_delta=$((idle2 - idle1))
total_delta=$((total2 - total1))

CPU_PCT="0.0"
if [[ "$total_delta" -gt 0 ]]; then
  CPU_PCT=$(awk -v id="$idle_delta" -v td="$total_delta" 'BEGIN{printf "%.1f", (1-(id/td))*100}')
fi

MEM_TOTAL=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
MEM_AVAIL=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
MEM_PCT="0.0"
if [[ "${MEM_TOTAL:-0}" -gt 0 ]]; then
  MEM_PCT=$(awk -v t="$MEM_TOTAL" -v a="${MEM_AVAIL:-0}" 'BEGIN{printf "%.1f", (1-(a/t))*100}')
fi

DISK_PCT=$(df -P / | awk 'NR==2{gsub("%","",$5); print $5}')
DISK_PCT="${DISK_PCT:-0}.0"

echo "==> cpu ${CPU_PCT}% mem ${MEM_PCT}% disco ${DISK_PCT}%"
result "ok" "estatisticas coletadas" "{\"cpu_percent\":$CPU_PCT,\"mem_percent\":$MEM_PCT,\"disk_percent\":$DISK_PCT}"
