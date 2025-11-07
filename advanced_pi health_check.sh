#!/bin/bash
# Script de Diagnóstico Avançado: Checa saúde da CPU, memória, disco, interfaces e velocidade de rede.

export LC_ALL=C; export LANG=C; export LC_NUMERIC=C

BOLD='\033[1m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
FALHAS=()

diagnostico_sistema() {
    echo -e "\n${CYAN}1. Análise de Energia e Temperatura:${NC}"
    local throttled_status=$(vcgencmd get_throttled)
    if [ "$throttled_status" != "throttled=0x0" ]; then FALHAS+=("Energia: Histórico de subtensão detectado ($throttled_status)"); fi
    printf "    - %-25s ${GREEN}[ OK ]${NC}\n" "Status da Alimentação:"
    
    local temp=$(vcgencmd measure_temp | grep -oE '[0-9]+\.[0-9]+')
    if (( $(echo "$temp > 80.0" | bc -l) )); then FALHAS+=("Temperatura: CRÍTICA (${temp}°C)"); fi
    printf "    - %-25s ${GREEN}[ OK ] - (${temp}°C)${NC}\n" "Temperatura da CPU:"

    echo -e "\n${CYAN}2. Desempenho de CPU e Memória:${NC}"
    local cpu_stats=($(grep '^cpu ' /proc/stat | awk '{print $2, $3, $4, $5}')); local cpu_total=$((cpu_user + cpu_nice + cpu_system + cpu_idle));
    local cpu_usage=$(printf "%.0f" "$(echo "100 * ($cpu_total - $cpu_idle) / $cpu_total" | bc -l)")
    printf "    - %-25s ${BOLD}%s%%${NC}\n" "Uso da CPU:" "$cpu_usage"
    local mem_info=$(free -h | grep "Mem:"); local mem_used=$(echo $mem_info | awk '{print $3}'); local mem_total=$(echo $mem_info | awk '{print $2}')
    printf "    - %-25s ${BOLD}%s / %s${NC}\n" "Uso de Memória (RAM):" "$mem_used" "$mem_total"

    echo -e "\n${CYAN}3. Saúde do Armazenamento:${NC}"
    local disk_info=$(df -h / | tail -n 1); local disk_percent=$(echo $disk_info | awk '{print $5}')
    printf "    - %-25s ${BOLD}%s${NC}\n" "Espaço em Disco Usado:" "$disk_percent"
    local mmc_errors=$(sudo dmesg | grep -i "error.*mmc")
    if [ -n "$mmc_errors" ]; then FALHAS+=("Armazenamento: Erros de baixo nível (mmc) no Cartão SD"); fi
    printf "    - %-25s ${GREEN}[ OK ] - Sem erros mmc.${NC}\n" "Erros de Baixo Nível:"
}

teste_interfaces() {
    echo -e "\n${CYAN}4. Teste de Interfaces e Comunicações:${NC}"
    printf "    - %-25s" "Saúde do Wi-Fi:"
    if ! ip link show wlan0 &> /dev/null; then FALHAS+=("Wi-Fi: Interface wlan0 não encontrada"); else echo -e "${GREEN}[ OK ] - Funcional.${NC}"; fi
    
    printf "    - %-25s" "Rede Ethernet (Cabo):"
    if ! ip link show eth0 &> /dev/null; then echo -e "${YELLOW}[ N/A ]${NC}";
    elif cat /sys/class/net/eth0/carrier 2>/dev/null | grep -q "1"; then echo -e "${GREEN}[ OK ] - Link ativo.${NC}";
    else FALHAS+=("Ethernet: Cabo desconectado ou sem link"); echo -e "${YELLOW}[ ALERTA ]${NC}"; fi
    
    printf "    - %-25s" "Bluetooth:"
    if ! command -v hciconfig &> /dev/null; then FALHAS+=("Bluetooth: 'hciconfig' não instalado"); else echo -e "${GREEN}[ OK ] - Módulo ativo.${NC}"; fi
}

teste_conectividade_internet() {
    echo -e "\n${CYAN}5. Teste de Conectividade Básica:${NC}"
    local ip_ativo=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -vE "^127\.|^169\.254\.")
    if [ -z "$ip_ativo" ]; then FALHAS+=("Internet: Nenhuma conexão de rede ativa"); return; fi

    if timeout 5 curl -s --max-time 5 -o /dev/null http://google.com 2>/dev/null; then
        printf "    - %-25s ${GREEN}[ OK ] - Conectado à Internet${NC}\n" "Status da Conexão:"
    else
        FALHAS+=("Internet: Sem conectividade (HTTP falhou)"); printf "    - %-25s ${RED}[ FALHA ]${NC}\n" "Status da Conexão:"
        return
    fi
    
    # TESTE DE VELOCIDADE
    echo -e "\n    ${CYAN}Teste de Velocidade (speedtest-cli):${NC}"
    if command -v speedtest-cli &> /dev/null; then
        local speedtest_output=$(LC_ALL=C speedtest-cli --simple 2>/dev/null)
        if [ $? -eq 0 ]; then
            local download_mbps=$(echo "$speedtest_output" | grep "Download:" | awk '{print $2}')
            local upload_mbps=$(echo "$speedtest_output" | grep "Upload:" | awk '{print $2}')
            printf "    - %-25s ${GREEN}${BOLD}%s Mbps${NC}\n" "Velocidade de Download:" "$download_mbps"
            printf "    - %-25s ${GREEN}${BOLD}%s Mbps${NC}\n" "Velocidade de Upload:" "$upload_mbps"
        else
            printf "    - %-25s ${RED}Falha ao executar speedtest-cli.${NC}\n" "Velocidade:"
            FALHAS+=("Internet: speedtest-cli falhou na execução.")
        fi
    else
        printf "    - %-25s ${YELLOW}speedtest-cli não encontrado (Instale para medir).${NC}\n" "Velocidade:"
    fi
}

mostrar_resumo_final() {
    echo -e "\n${CYAN}6. Resumo Final de Falhas:${NC}"
    if [ ${#FALHAS[@]} -eq 0 ]; then echo -e "    ${GREEN}[ SUCESSO ] - Nenhum problema crítico detectado.${NC}";
    else
        echo -e "    ${RED}Os seguintes problemas foram encontrados:${NC}"
        for item in "${FALHAS[@]}"; do echo -e "    	 	- ${YELLOW}$item${NC}"; done
    fi
}

clear
diagnostico_sistema; teste_interfaces; teste_conectividade_internet; mostrar_resumo_final
echo -e "\n${CYAN}Diagnóstico Concluído.${NC}\n"