#!/bin/bash

################################################################################
#                                                                              #
#               SCRIPT DE DIAGNÓSTICO INTELIGENTE (Versão Generalizada)        #
#         - Testa estabilidade da tensão (Teste Fonte), GPS e Conexão de Dados.#
#                                                                              #
################################################################################

# --- Cores e Ícones ---
BOLD='\033[1m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ICON_OK="✅"; ICON_FAIL="❌"

# Configurações Genéricas para Teste
TEMPO_LIMITE_CONEXAO=45
LAT_MIN_TEST=-25.00; LAT_MAX_TEST=-20.00
LON_MIN_TEST=-45.00; LON_MAX_TEST=-40.00

# Garante a limpeza do processo de conexão ao sair
trap "sudo killall wvdial pppd 2>/dev/null; rm -f /tmp/wvdial_log; echo -e '\nScript interrompido.'" EXIT

decodificar_throttled() {
    local throttled_input="$1"; local hex_val=${throttled_input#*=}; local dec_val=$((hex_val))
    local problemas_atuais=""
    if (( (dec_val & 1) != 0 )); then problemas_atuais+="Subtensão; "; fi
    if [ -n "$problemas_atuais" ]; then echo -e "${RED}${BOLD}[ FALHA ATUAL ] ($hex_val) - ${problemas_atuais%??}${NC}";
    elif (( (dec_val & 0x10000) != 0 )); then echo -e "${YELLOW}${BOLD}[ ALERTA HISTÓRICO ] ($hex_val) - Subtensão (Histórico)${NC}";
    else echo -e "${GREEN}${BOLD}[ OK ] ($hex_val) - Tensão estável.${NC}"; fi
}

testar_diagnostico_completo() {
    echo -e "\n${CYAN}${BOLD}--- DIAGNÓSTICO COMPLETO DO SISTEMA ---${NC}"
    local status_tensao="OK"; local status_gps="OK"; local status_conexao="OK"

    # ETAPA 1: TESTE FONTE
    echo -e "\n${CYAN}1. Teste Fonte (Verificando Estabilidade da Tensão)...${NC}"
    local throttled_status=$(vcgencmd get_throttled)
    local explicacao_throttled=$(decodificar_throttled "$throttled_status")
    echo -e "    └─ ${explicacao_throttled}"
    if (( $(echo ${throttled_status#*=} | awk '{print $1}') & 0x7 )); then status_tensao="FALHA"; fi

    # ETAPA 2: VERIFICAÇÃO DE CONEXÃO DE DADOS MÓVEIS (PPP)
    echo -e "\n${CYAN}2. Verificação de Conexão de Dados Móveis (PPP)...${NC}"
    sudo killall wvdial pppd 2>/dev/null; rm -f /tmp/wvdial_log
    
    # ATENÇÃO: 'wvdial config_generica' usa o arquivo /etc/wvdial.conf. 
    # A string 'config_generica' deve ser substituída pela seção correta em um ambiente real.
    sudo wvdial config_generica > /tmp/wvdial_log 2>&1 &
    
    local connected=false
    echo -n "    └─ Aguardando conexão ppp0 por até ${TEMPO_LIMITE_CONEXAO} segundos... "
    for i in $(seq 1 ${TEMPO_LIMITE_CONEXAO}); do if ip a | grep -q "ppp0"; then connected=true; break; fi; sleep 1; echo -n "."; done
    echo ""
    
    if $connected; then
        echo -e "       └─ ${GREEN}${BOLD}[ OK ] - Interface ppp0 criada.${NC}"
        if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then echo -e "             └─ Ping: ${GREEN}${BOLD}[ OK ]${NC}"; else echo -e "             └─ Ping: ${RED}${BOLD}[ FALHA ]${NC}"; status_conexao="FALHA"; fi
    else
        local causa_falha="Conexão não estabelecida no tempo limite"
        if grep -q "NO CARRIER" /tmp/wvdial_log; then causa_falha="NO CARRIER (Verificar Chip SIM/Antena)"; fi
        echo -e "       └─ ${RED}${BOLD}[ FALHA ] - ${causa_falha}${NC}"
        status_conexao="FALHA"
    fi
    sudo killall wvdial pppd 2>/dev/null

    # ETAPA 3: SINAL DE GPS E LOCALIZAÇÃO
    echo -e "\n${CYAN}3. Análise de Sinal GPS e Geolocalização (aguarde 15s)...${NC}"
    if [ ! -e /dev/serial0 ]; then status_gps="FALHA";
    else
        local gps_data=$(timeout 15s cat /dev/serial0 | tr -d '\0'); local all_ok=true
        if ! echo "$gps_data" | grep -q '$'; then status_gps="FALHA";
        else
            local rmc_status=$(echo "$gps_data" | grep "RMC" | tail -n 1 | cut -d',' -f3); local gsa_fix=$(echo "$gps_data" | grep "GSA" | tail -n 1 | cut -d',' -f3)
            local lat=$(echo "$gps_data" | grep "RMC" | tail -n 1 | cut -d',' -f4); local lat_dir=$(echo "$gps_data" | grep "RMC" | tail -n 1 | cut -d',' -f5)
            local lon=$(echo "$gps_data" | grep "RMC" | tail -n 1 | cut -d',' -f6); local lon_dir=$(echo "$gps_data" | grep "RMC" | tail -n 1 | cut -d',' -f7)
            
            if [ "$rmc_status" == "A" ]; then echo -e "    ├─ Sinal RMC: ${GREEN}Ativo${NC}"; else all_ok=false; fi
            if [ -n "$lat" ] && [ -n "$lon" ]; then
                local lat_dec=$(echo "$lat" | awk '{ deg=int($1/100); min_val=($1-(deg*100)); print deg+(min_val/60) }')
                local lon_dec=$(echo "$lon" | awk '{ deg=int($1/100); min_val=($1-(deg*100)); print deg+(min_val/60) }')
                if [ "$lat_dir" == "S" ]; then lat_dec="-${lat_dec}"; fi; if [ "$lon_dir" == "W" ]; then lon_dec="-${lon_dec}"; fi
                local lat_ok=$(echo "$lat_dec >= $LAT_MIN_TEST && $lat_dec <= $LAT_MAX_TEST" | bc -l)
                local lon_ok=$(echo "$lon_dec >= $LON_MIN_TEST && $lon_dec <= $LON_MAX_TEST" | bc -l)
                if [ "$lat_ok" -eq 1 ] && [ "$lon_ok" -eq 1 ]; then echo -e "    └─ Localização: ${GREEN}Dentro da Área de Teste.${NC}";
                else echo -e "    └─ Localização: ${YELLOW}Fora da Área de Teste. Lat ${lat_dec}, Lon ${lon_dec}${NC}";
                fi
            fi
            if ! $all_ok; then status_gps="FALHA"; fi
        fi
    fi

    # RESUMO FINAL
    echo -e "\n--- Resumo ---"
    if [ "$status_tensao" == "FALHA" ] || [ "$status_gps" == "FALHA" ] || [ "$status_conexao" == "FALHA" ]; then echo -e "${RED}DIAGNÓSTICO GERAL: FALHA${NC}"; else echo -e "${GREEN}DIAGNÓSTICO GERAL: SUCESSO${NC}"; fi
    printf "    - %-24s ${BOLD}%s${NC}\n" "Estabilidade da Tensão (Teste Fonte):" "$status_tensao"
    printf "    - %-24s ${BOLD}%s${NC}\n" "Status da Conexão (PPP):" "$status_conexao"
    printf "    - %-24s ${BOLD}%s${NC}\n" "Status do GPS:" "$status_gps"
}
testar_diagnostico_completo