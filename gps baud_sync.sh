#!/bin/bash

################################################################################
#                                                                              #
#                        GPS BAUD RATE DETECTOR v1.0                             #
#             Testa uma lista de baud rates para encontrar a correta           #
#                 e exibir os dados do GPS sem erros.                          #
#                                                                              #
################################################################################

# --- Configurações ---
SERIAL_PORT="/dev/serial0"
# Lista de baud rates a serem testados.
BAUDRATES=(9600 4800 19200 38400 57600 115200)

# --- Cores e Ícones ---
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
ICON_OK="✅"
ICON_FAIL="❌"

# --- Início do Script ---
clear
echo -e "${CYAN}${BOLD}--- Scanner de Baud Rate para GPS na porta ${SERIAL_PORT} ---${NC}"
echo "Testando as seguintes velocidades: ${BAUDRATES[*]}"
echo "------------------------------------------------------------"

FOUND_BAUD=0

# Loop para testar cada baud rate da lista
for BAUD in "${BAUDRATES[@]}"; do
    echo -en ">> Testando ${YELLOW}${BAUD}${NC} baud... "
    
    # Configura a porta serial do Pi para a velocidade atual do loop
    # Usamos stdbuf para desativar o buffer de saída e obter resposta imediata
    stdbuf -o0 sudo stty -F ${SERIAL_PORT} ${BAUD}
    
    # Tenta ler a porta por 2 segundos e procura por uma sentença NMEA válida
    # Se encontrar, a comunicação está correta nesta velocidade.
    if timeout 2s cat ${SERIAL_PORT} | grep -q -m 1 -E '\$GP(GGA|RMC|GSA|GSV)'; then
        echo -e "${GREEN}${BOLD}SUCESSO! ${ICON_OK}${NC}"
        FOUND_BAUD=${BAUD}
        break # Sai do loop pois já encontrou a velocidade correta
    else
        echo -e "${RED}Sem dados válidos. ${ICON_FAIL}${NC}"
    fi
done

echo "------------------------------------------------------------"

# Verifica se um baud rate foi encontrado
if [ ${FOUND_BAUD} -ne 0 ]; then
    echo -e "${GREEN}Baud rate correto encontrado: ${BOLD}${FOUND_BAUD}${NC}"
    echo "A porta serial ${SERIAL_PORT} está agora configurada para esta velocidade."
    echo -e "Visualizando dados ao vivo (Pressione Ctrl+C para sair):"
    
    # Configura a porta mais uma vez para garantir e exibe os dados
    sudo stty -F ${SERIAL_PORT} ${FOUND_BAUD}
    cat ${SERIAL_PORT}
else
    echo -e "${RED}${BOLD}NENHUM BAUD RATE FUNCIONAL ENCONTRADO.${NC}"
    echo "Verifique os seguintes pontos:"
    echo "  1. O módulo GPS está ligado e conectado corretamente (TX no RX do Pi, RX no TX do Pi)?"
    echo "  2. A porta serial está habilitada no seu Raspberry Pi? (Use 'sudo raspi-config')"
    echo "  3. O módulo GPS pode estar com defeito ou usar um baud rate não padrão."
fi

echo ""