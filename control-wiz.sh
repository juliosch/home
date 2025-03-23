#!/bin/bash

# Configurações padrão
PORT=38899
VERBOSE=true

# Função para enviar comandos
send_command() {
    local ip=$1
    local command=$2

    if [ "$VERBOSE" = true ]; then
        echo "Enviando para $ip: $command"
    fi

    echo "$command" | socat - UDP-DATAGRAM:$ip:$PORT

    # Pequena pausa para evitar sobrecarregar a rede
    sleep 0.1
}

# Função para processar comandos para uma lâmpada
process_lamp() {
    local ip=$1
    shift

    if [ -z "$ip" ]; then
        echo "❌ Erro: IP não especificado"
        return 1
    fi

    if [ "$VERBOSE" = true ]; then
        echo "🔍 Processando lâmpada: $ip"
    fi

    # Variáveis para construir o comando
    local has_commands=false
    local params="{\"state\":true}"

    # Loop pelos argumentos até encontrar outro -i ou acabarem os argumentos
    while [ $# -gt 0 ]; do
        case "$1" in
            # Se encontrar outro indicador de IP, paramos de processar esta lâmpada
            -i|--ip)
                break
                ;;
            # Comandos de estado
            -on|--on)
                params="{\"state\":true}"
                has_commands=true
                shift
                ;;
            -off|--off)
                params="{\"state\":false}"
                has_commands=true
                shift
                ;;
            # Comando de brilho
            -b|--brightness)
                if [ -z "$2" ] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    echo "❌ Erro: Valor de brilho inválido ou ausente após -b"
                    return 1
                fi

                if [ "$2" -ge 0 ] && [ "$2" -le 100 ]; then
                    # Extrai o estado atual do params para manter
                    local state_part
                    if [[ "$params" == *"\"state\":false"* ]]; then
                        state_part="\"state\":false"
                    else
                        state_part="\"state\":true"
                    fi
                    params="{$state_part,\"dimming\":$2}"
                    has_commands=true
                else
                    echo "❌ Erro: Brilho deve ser entre 0 e 100"
                    return 1
                fi
                shift 2
                ;;
            # Comando de temperatura
            -t|--temp)
                if [ -z "$2" ] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    echo "❌ Erro: Valor de temperatura inválido ou ausente após -t"
                    return 1
                fi

                if [ "$2" -ge 2200 ] && [ "$2" -le 6500 ]; then
                    # Extrai o estado atual do params para manter
                    local state_part
                    if [[ "$params" == *"\"state\":false"* ]]; then
                        state_part="\"state\":false"
                    else
                        state_part="\"state\":true"
                    fi
                    params="{$state_part,\"temp\":$2}"
                    has_commands=true
                else
                    echo "❌ Erro: Temperatura deve ser entre 2200K e 6500K"
                    return 1
                fi
                shift 2
                ;;
            # Comando RGB
            -c|--color)
                if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] ||
                   ! [[ "$2" =~ ^[0-9]+$ ]] || ! [[ "$3" =~ ^[0-9]+$ ]] || ! [[ "$4" =~ ^[0-9]+$ ]]; then
                    echo "❌ Erro: Valores RGB inválidos ou insuficientes após -c"
                    return 1
                fi

                local R=$2
                local G=$3
                local B=$4

                if [ "$R" -ge 0 ] && [ "$R" -le 255 ] &&
                   [ "$G" -ge 0 ] && [ "$G" -le 255 ] &&
                   [ "$B" -ge 0 ] && [ "$B" -le 255 ]; then
                    # Extrai o estado atual do params para manter
                    local state_part
                    if [[ "$params" == *"\"state\":false"* ]]; then
                        state_part="\"state\":false"
                    else
                        state_part="\"state\":true"
                    fi
                    params="{$state_part,\"r\":$R,\"g\":$G,\"b\":$B}"
                    has_commands=true
                else
                    echo "❌ Erro: Valores RGB devem ser entre 0 e 255"
                    return 1
                fi
                shift 4
                ;;
            # Comando de status
            -s|--status)
                send_command "$ip" '{"method":"getPilot","params":{}}'
                shift
                ;;
            # Se encontrar um argumento desconhecido, imprimimos um erro
            *)
                echo "❌ Aviso: Argumento desconhecido ignorado: $1"
                shift
                ;;
        esac
    done

    # Envia comando acumulado, se houver
    if [ "$has_commands" = true ]; then
        local command_json="{\"method\":\"setPilot\",\"params\":$params}"
        send_command "$ip" "$command_json"
    fi

    return 0
}

# Função para mostrar ajuda
show_help() {
    echo "Controlador de Lâmpadas WiZ"
    echo "=========================="
    echo ""
    echo "Uso:"
    echo "  $0 -i IP [comandos] [-i IP2 [comandos2] ...]"
    echo ""
    echo "Opções:"
    echo "  -i, --ip IP          - Especifica o IP da lâmpada"
    echo "  -q, --quiet          - Modo silencioso (sem mensagens de status)"
    echo "  -h, --help           - Exibe esta ajuda"
    echo ""
    echo "Comandos:"
    echo "  -on, --on            - Liga a lâmpada"
    echo "  -off, --off          - Desliga a lâmpada"
    echo "  -b, --brightness N   - Ajusta o brilho (0-100%)"
    echo "  -t, --temp N         - Ajusta a temperatura da cor (2200-6500K)"
    echo "  -c, --color R G B    - Define a cor RGB (0-255)"
    echo "  -s, --status         - Obtém o estado atual da lâmpada"
    echo ""
    echo "Exemplos:"
    echo "  $0 -i 192.168.1.100 -on -b 75                      - Liga e ajusta brilho"
    echo "  $0 -i 192.168.1.100 -c 255 0 0 -i 192.168.1.101 -on - Controla duas lâmpadas"
    echo "  $0 -i 192.168.1.100 -on -t 3000 -b 80              - Múltiplos comandos"
}

# Processamento principal dos argumentos
main() {
    # Verifica se socat está instalado
    if ! command -v socat &> /dev/null; then
        echo "❌ Erro: O programa 'socat' não está instalado."
        echo "Instale-o com seu gerenciador de pacotes (ex: apt install socat)"
        exit 1
    fi

    # Verifica se há argumentos
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    # Processa opções globais e inicia o processamento de lâmpadas
    local current_ip=""
    local args=("$@")
    local i=0

    while [ $i -lt ${#args[@]} ]; do
        local arg="${args[$i]}"

        case "$arg" in
            -q|--quiet)
                VERBOSE=false
                ((i++))
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -i|--ip)
                # Precisamos do próximo argumento como IP
                if [ $((i+1)) -ge ${#args[@]} ]; then
                    echo "❌ Erro: IP não fornecido após -i"
                    exit 1
                fi

                current_ip="${args[$((i+1))]}"
                ((i+=2))

                # Coletamos todos os argumentos até o próximo -i ou fim
                local lamp_args=()
                local j=$i
                while [ $j -lt ${#args[@]} ]; do
                    if [ "${args[$j]}" = "-i" ] || [ "${args[$j]}" = "--ip" ]; then
                        break
                    fi
                    lamp_args+=("${args[$j]}")
                    ((j++))
                done

                # Processamos esta lâmpada
                process_lamp "$current_ip" "${lamp_args[@]}"

                # Avançamos para o próximo conjunto
                i=$j
                ;;
            *)
                echo "❌ Erro: Argumento desconhecido ou IP não especificado: $arg"
                echo "Use -h para ajuda."
                exit 1
                ;;
        esac
    done

    exit 0
}

# Executa o script
main "$@"
