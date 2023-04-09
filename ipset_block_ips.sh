#!/usr/bin/env bash

## NOME...............: ipset_block_ip.sh
## VERSÃO.............: 1.0.10
## DATA DA CRIAÇÃO....: 01/04/2023
## ESCRITO POR........: Bruno Lima
## E-MAIL.............: bruno@lc.tec.br
## DISTRO.............: Endian Fw 3.3.22
## LICENÇA............: GPLv3
## PROJETO............: https://github.com/bflima
## DESCRIÇÃO..........: Baixar criar e atualizar regras para bloqueio de ips usando o ipset, usando lista com o CIDR do país Brazil 

# Variaveis
LOCAL='/tmp/ipset_log'
REGRA='/tmp/regra_log'
COUNTRY='br'
IPT_BKP='/opt/iptables'
IPT_SAVE='/srv/iptab.save'
IPS_SAVE='/srv/ipset.save'

# Lista
LISTA='whitelist_geo_br'

# Testar se o programa ipset esta instaladado
which ipset || { echo 'programa ipset não instalado, saindo...' ; exit 2 ; }


# FUNÇÕES
MENU()
{
    clear
    echo "
---------------------MENU---------------------

[1] - ATUALIZAR LISTA COM IPS PARA O BRAZIL

[2] - CRIAR REGRAS PARA BLOQUEIO

[3] - LIMPAR REGRAS IPSET

[4] - LIMPAR REGRAS IPTABLES

[5] - SALVAR REGRAS APLICADAS

[9] - SAIR DO PROGRAMA

----------------------------------------------
"
}

ATUALIZAR_LISTA_IPS()
{
    clear
    PATH_GEO_IP="/tmp/geoip"
    
    # Testar se diretorio existe
    [ ! -d "$PATH_GEO_IP" ] && mkdir -p "$PATH_GEO_IP"

    # Acesar diretorio
    cd "$PATH_GEO_IP" || { echo "Erro ao acessar diretorio" ; exit 1 ; }

    # Apagar arquivos antigos de ips
    rm -f "$PATH_GEO_IP"/*.zone*

    # Fazer Download das listas com todos paises
    wget --no-check-certificate https://www.ipdeny.com/ipblocks/data/countries/br.zone -P "$PATH_GEO_IP" || { echo "Erro ao baixar arquivo" ; exit 1 ; }
    
    # Ler somente o primeiro caracter digitado
    read -n 1 -rp 'Deseja continuar S/n: ' ESCOLHA

    ESCOLHA=${ESCOLHA:-s}
    [[ ${ESCOLHA,,} != 's' ]] && { echo 'Programa finalizado' ; exit 2; }

    # Se lista já exisitir a mesma será limpa, senão irá criar uma lista nova
    if [[ $(ipset -L $LISTA -quiet) ]]; then ipset -F $LISTA ; else ipset -N $LISTA hash:net ; fi

    # Adicionar lista de ips com cidr por pais no caso BR
    while read -r IP_GEO_BR ; do ipset add $LISTA "${IP_GEO_BR}" ; done <  "$PATH_GEO_IP"/"$COUNTRY".zone

    # Adicionar rede local para segurança dos acessos, laço for foi usado para garantir mais de um ip cadastrado na interface
    REDE_GREEN=$(ip r | grep br0 | awk '{print $1}')
    for ip in $REDE_GREEN ; do ipset add $LISTA "$ip" ; done

    # Salva arquivo de log
    echo "Sistema atualizado $(date)" >> "$LOCAL"
}

CRIAR_REGRAS_IP()
{
    clear

    # Verificar se o script já foi utilizado.
    [[ -f "$REGRA" ]] && { echo 'regras já foram criadas'  ; exit 2 ;}

    # Verificar se lista foi criada e atualizada, se não tiver sido, será criada
    [[ ! -f "$LOCAL" ]] && ATUALIZAR_LISTA_IPS

    # Informar portas para serem adionadas no bloqueio
    read -rp 'Digite a(s) porta(s) para bloquear separado por virgula EX 22,3389: ' PORTAS

    # Testando valor informado
    [[ -n "$PORTAS" || "${PORTAS//,/}" == ?(-)+([0-9]) ]] || { echo "Erro porta informada com erro ou vazia, saindo..." ; exit 2 ; }

    # Testar se porta é válida
    for porta in ${PORTAS//,/ }
        do 
            [[ $porta -gt 0 && $porta -lt 65535 ]] || { echo "Erro porta informada $porta " ; exit 2 ; }
    done

    # Confirmar escolha
    echo "Portas informadas são: ${PORTAS//,/ }"

    # Ler somente o primeiro caracter digitado
    read -n 1 -rp 'Deseja continuar S/n: ' ESCOLHA

    ESCOLHA=${ESCOLHA:-s}
    [[ ${ESCOLHA,,} != 's' ]] && { echo 'Programa finalizado' ; exit 2; }


    if [[ $(wc -w <<< "${PORTAS//,/ }") -eq 1 ]]
        then  
            # Criar logs
            iptables -I CUSTOMINPUT   -p tcp  --dport "$PORTAS" -m set ! --match-set $LISTA src -j NFLOG --nflog-prefix "${LISTA^^}:DROP: "
            iptables -I CUSTOMFORWARD -p tcp  --dport "$PORTAS" -m set ! --match-set $LISTA src -j NFLOG --nflog-prefix "${LISTA^^}:DROP: "

            # Criar regras iptables
            iptables -A CUSTOMINPUT   -p tcp  --dport "$PORTAS" -m set ! --match-set $LISTA src -j DROP 
            iptables -A CUSTOMFORWARD -p tcp  --dport "$PORTAS" -m set ! --match-set $LISTA src -j DROP

    elif [[ $(wc -w <<< "${PORTAS//,/ }") -gt 1 ]] 
        then
            # Criar logs
            iptables -I CUSTOMINPUT   -p tcp -m multiport --dports "$PORTAS" -m set ! --match-set $LISTA src -j NFLOG --nflog-prefix "${LISTA^^}:DROP: "
            iptables -I CUSTOMFORWARD -p tcp -m multiport --dports "$PORTAS" -m set ! --match-set $LISTA src -j NFLOG --nflog-prefix "${LISTA^^}:DROP: "
            
            # Criar regras iptables
            iptables -A CUSTOMINPUT   -p tcp -m multiport --dports "$PORTAS" -m set ! --match-set $LISTA src -j DROP 
            iptables -A CUSTOMFORWARD -p tcp -m multiport --dports "$PORTAS" -m set ! --match-set $LISTA src -j DROP
    fi

    # Salvar regras
    ipset save $LISTA > $IPS_SAVE
    iptables-save > $IPT_SAVE

    # Salva arquivo de log
    echo "Sistema atualizado $(date)" >> "$REGRA"

}
# Programa principal


MENU

# Ler somente o primeiro caracter digitado
read -n 1 -t 30 -rp 'FAVOR ESCOLHER -> ' MENU || printf 'Tempo limite esgotado\nFavor executar novamente o script\n'

case $MENU in

    1) ATUALIZAR_LISTA_IPS
    ;;

    2) CRIAR_REGRAS_IP
    ;;

    3) printf '\n\nCUIDADO ao limpar as regras do ipset, o acesso via ssh pode ser perdido\n'
       read -n 1 -rp 'Deseja continuar s/N: ' ESCOLHA

       ESCOLHA=${ESCOLHA:-n}

       [[ ${ESCOLHA,,} = 's' ]] && ipset -F "$LISTA"
    ;;

    4) clear
       echo 'Regras em USO:'
       iptables -nvL CUSTOMINPUT
       iptables -nvL CUSTOMFORWARD
       
       read -n 1 -rp 'Deseja continuar s/N: ' ESCOLHA

       ESCOLHA=${ESCOLHA:-n}
       [[ ${ESCOLHA,,} != 's' ]] && { echo 'Saindo...' ; exit 2 ; }

       # Realizando backup das regras atuais
       iptables-save > "$IPT_BKP"

       # Limpar as regras
       iptables -F CUSTOMINPUT
       iptables -F CUSTOMFORWARD
       rm -f "$REGRA" > /dev/null
    ;;

    5) ipset save $LISTA > $IPS_SAVE
       iptables-save > $IPT_SAVE
       
       # Resumo da importação se ips
       TOTAL_IPS=$(ipset list | wc -l)
       echo "Total de ips na lista: $TOTAL_IPS"
    ;;

    9) echo 'Saindo...' && exit 0
    ;;

    *) echo "Opção inválida"

esac