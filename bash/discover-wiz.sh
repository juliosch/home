#!/bin/bash

# Descobridor de Lâmpadas WiZ na rede local
# =========================================

PORT=38899
BROADCAST="255.255.255.255"
DISCOVERY_MESSAGE='{"method":"getPilot","params":{}}'
SCAN_TIMEOUT=3
RESPONSE_TIMEOUT=1
TEMP_DIR=$(mktemp -d)
LOG_FILE="$TEMP_DIR/discovery.log"

# Função para limpar e sair
cleanup() {
    rm -rf "$TEMP_DIR"
    exit "${1:-0}"
}

# Configura captura para interrupção do usuário
trap "cleanup" INT TERM EXIT

# Verifica dependências
check_dependencies() {
    if ! command -v socat &> /dev/null; then
        echo "❌ O programa 'socat' não está instalado."
        echo "   Instale com: sudo apt install socat"
        cleanup 1
    fi
}

# Função para verificar se um IP pertence à nossa máquina
is_local_ip() {
    local ip_to_check=$1
    local local_ips=""

    # Tenta diferentes métodos para obter IPs locais
    if command -v ifconfig &> /dev/null; then
        local_ips=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*')
    elif command -v hostname &> /dev/null; then
        local_ips=$(hostname -I 2>/dev/null)
    elif [ -f /sbin/ip ]; then
        local_ips=$(/sbin/ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1)
    else
        # Fallback: assume apenas localhost
        local_ips="127.0.0.1"
    fi

    for local_ip in $local_ips; do
        if [ "$ip_to_check" = "$local_ip" ]; then
            return 0  # true
        fi
    done

    return 1  # false
}

# Determina a sub-rede local baseada em um IP
get_subnet_from_ip() {
    local ip=$1
    local ip_parts=(${ip//./ })

    # Retorna os 3 primeiros octetos assumindo uma máscara /24 (mais comum)
    echo "${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}."
}

# Obtém o IP local principal
get_local_ip() {
    local ip=""

    # Tenta diferentes métodos para obter o IP principal
    if command -v ifconfig &> /dev/null; then
        # Primeiro tenta interfaces comuns
        for iface in eth0 en0 wlan0; do
            ip=$(ifconfig $iface 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | head -n1)
            if [ -n "$ip" ]; then
                break
            fi
        done

        # Se não encontrou, tenta qualquer interface que não seja loopback
        if [ -z "$ip" ]; then
            ip=$(ifconfig | grep -v 'lo' | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | head -n1)
        fi
    elif command -v hostname &> /dev/null; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    elif [ -f /sbin/ip ]; then
        ip=$(/sbin/ip -o -4 addr show | grep -v 'lo' | awk '{print $4}' | cut -d/ -f1 | head -n1)
    fi

    echo "$ip"
}

# Busca lâmpadas na rede usando métodos diversos
scan_network() {
    echo "🔍 Buscando lâmpadas WiZ na rede local..."

    # Obtém o IP local
    local local_ip=$(get_local_ip)

    if [ -z "$local_ip" ]; then
        echo "⚠️ Não foi possível determinar o IP local."
        echo "   Usando apenas método de broadcast direto..."
        direct_broadcast
        return
    fi

    echo "📡 IP local detectado: $local_ip"

    # Determina a sub-rede
    local subnet=$(get_subnet_from_ip "$local_ip")

    echo "🌐 Sub-rede para varredura: ${subnet}0-255"

    # Inicia com broadcast direto para métodos rápidos
    send_broadcast

    # Depois faz uma varredura IP por IP para garantir cobertura
    echo "🔍 Iniciando varredura detalhada da rede..."

    local found=0
    local checked=0
    local total=254

    for i in $(seq 1 254); do
        local target_ip="${subnet}${i}"

        # Não precisamos verificar nosso próprio IP
        if is_local_ip "$target_ip"; then
            continue
        fi

        # Atualiza o contador e mostra progresso
        checked=$((checked + 1))
        if [ $((checked % 10)) -eq 0 ] || [ "$checked" -eq "$total" ]; then
            echo -ne "🔄 Progresso: $checked/$total IPs verificados (${found} lâmpadas encontradas)\r"
        fi

        # Envia a mensagem de descoberta para este IP específico
        check_ip "$target_ip"
    done

    echo -e "\n✅ Varredura completa!"
}

# Envia broadcast direto para toda a rede
direct_broadcast() {
    echo "📡 Enviando mensagem de broadcast para $BROADCAST:$PORT..."

    # Envia a mensagem de descoberta para o endereço de broadcast
    echo "$DISCOVERY_MESSAGE" | socat - UDP-DATAGRAM:"$BROADCAST":"$PORT",broadcast

    # Aguarda um momento para que as lâmpadas possam responder
    echo "⏳ Aguardando respostas..."
    sleep "$SCAN_TIMEOUT"
}

# Envia mensagem de broadcast para toda a rede
send_broadcast() {
    echo "📡 Enviando mensagem de broadcast para $BROADCAST:$PORT..."

    # Envia a mensagem de descoberta para o endereço de broadcast
    echo "$DISCOVERY_MESSAGE" | socat - UDP-DATAGRAM:"$BROADCAST":"$PORT",broadcast

    # Aguarda um momento para que as lâmpadas possam responder
    echo "⏳ Aguardando respostas iniciais..."
    sleep 2
}

# Verifica se um IP específico é uma lâmpada WiZ
check_ip() {
    local ip=$1

    # Envia mensagem getPilot para o IP específico com timeout
    local response=""
    response=$(echo "$DISCOVERY_MESSAGE" | timeout "$RESPONSE_TIMEOUT" socat - UDP-DATAGRAM:"$ip":"$PORT" 2>/dev/null)

    # Se houver resposta, verificamos se é uma lâmpada WiZ
    if [ -n "$response" ]; then
        echo -e "\n🔆 Lâmpada WiZ encontrada: $ip"
        echo "   Status: $response"

        # Guarda a descoberta no log
        echo "$ip" >> "$LOG_FILE"
        found=$((found + 1))
    fi
}

# Função principal
main() {
    echo "🔎 Iniciando descoberta de lâmpadas WiZ na rede local..."
    echo "======================================================"

    check_dependencies

    # Cria arquivo de log
    touch "$LOG_FILE"

    # Tenta detectar qual comando 'timeout' está disponível
    if ! command -v timeout &> /dev/null; then
        if command -v gtimeout &> /dev/null; then
            # Em macOS com coreutils instalado
            alias timeout='gtimeout'
        else
            # Fallback para sistemas sem comando timeout
            timeout() {
                local timeout_duration=$1
                shift
                "$@" &
                pid=$!
                (
                    sleep "$timeout_duration"
                    kill -9 $pid 2>/dev/null
                ) &
                wait $pid 2>/dev/null
            }
        fi
    fi

    # Executa o scan
    scan_network

    # Mostra resultados
    if [ -s "$LOG_FILE" ]; then
        local count=$(wc -l < "$LOG_FILE")
        echo -e "\n🎉 Lâmpadas WiZ encontradas: $count"

        echo -e "\n💡 Use o controlador com estas lâmpadas:"
        while read -r ip; do
            echo "  ./wiz-control.sh -i $ip -on -b 80"
        done < "$LOG_FILE"
    else
        echo -e "\n⚠️ Nenhuma lâmpada WiZ encontrada."
        echo "Verifique se:"
        echo "  1. As lâmpadas estão conectadas à mesma rede"
        echo "  2. O firewall não está bloqueando tráfego UDP na porta $PORT"
        echo "  3. Você tem permissões para enviar/receber na porta $PORT"
        echo "Tente executar o script como administrador (sudo) se necessário."
    fi

    echo -e "\n✅ Processo de descoberta concluído."
}

# Executa o programa
main "$@"Ω
