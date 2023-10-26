#!/usr/bin/env bash

# RGB
CLOSING_METHOD="opret1st"
CONTRACT_DIR="contracts"
IFACE="RGB20"
RGB_CONTRACTS_VER="0.10.2"
TRANSFER_NUM=0

# wallet and network
AMT_FEES=1000
AMT_RCPT=5000
BDK_CLI_FEATURES="--features electrum"
RGB_CONTRACTS_FEATURES="--all-features"
BDK_CLI_VER="0.27.1"
CHANGE_INDEX=9
DERIVE_PATH="m/86h/1h/0h"
DESC_TYPE="wpkh"
ELECTRUM="localhost:50001"
NETWORK="regtest"
WALLETS=("issuer" "rcpt1" "rcpt2")

# maps
declare -A CONTRACT_MAP
declare -A DER_XPRV_MAP
declare -A DER_XPUB_MAP
declare -A WLT_ID_MAP
WLT_ID_MAP[${WALLETS[0]}]=0
WLT_ID_MAP[${WALLETS[1]}]=1
WLT_ID_MAP[${WALLETS[2]}]=2

# script
DEBUG=0
NAME=$(basename "$0")

# shell colors
C1='\033[0;32m' # green
C2='\033[0;33m' # orange
C3='\033[0;34m' # blue
C4='\033[0;31m' # red
NC='\033[0m'    # No Color


# utility functions
_die() {
    printf "\n${C4}ERROR: %s${NC}\n" "$@"
    exit 1
}

_log() {
    printf "${C3}%s${NC}\n" "$@"
}

_subtit() {
    printf "${C2} > %s${NC}\n" "$@"
}

_tit() {
    echo
    printf "${C1}==== %-20s ====${NC}\n" "$@"
}

_trace() {
    { local trace=0; } 2>/dev/null
    { [ -o xtrace ] && trace=1; } 2>/dev/null
    { [ $DEBUG = 1 ] && set -x; } 2>/dev/null
    "$@"
    { [ $trace == 0 ] && set +x; } 2>/dev/null
}

# internal functions
_gen_addr_bdk() {
    local wallet="$1"
    _log "generating new address for wallet \"$wallet\""
    local der_xpub=${DER_XPUB_MAP[$wallet]}
    ADDR=$(_trace "$BDKI" -n $NETWORK wallet -w "$wallet" -d "${DESC_TYPE}($der_xpub)" \
        get_new_address | jq -r '.address')
    _log "generated address: $ADDR"
}

_gen_blocks() {
    local count="$1"
    _log "mining $count block(s)"
    _trace "${BCLI[@]}" -rpcwallet=miner -generate "$count" >/dev/null
    sleep 1     # give electrs time to index
}

_gen_utxo() {
    local wallet="$1"
    _gen_addr_bdk "$wallet"
    _log "sending funds to wallet \"$wallet\""
    txid="$(_trace "${BCLI[@]}" -rpcwallet=miner sendtoaddress "$ADDR" 1)"
    _gen_blocks 1
    _sync_wallet "$wallet"
    _get_utxo "$wallet" "$txid"
}

_get_utxo() {
    local wallet="$1"
    local txid="$2"
    _log "extracting vout"
    local der_xpub=${DER_XPUB_MAP[$wallet]}
    local filter=".[] | .outpoint | select(contains(\"$txid\"))"
    vout=$(_trace "$BDKI" -n $NETWORK wallet -w "$wallet" -d "${DESC_TYPE}($der_xpub)" \
        list_unspent | jq -r "$filter" | cut -d: -f2)
    [ -n "$vout" ] || _die "couldn't retrieve vout for txid $txid"
    _log "txid $txid, vout: $vout"
}

_list_unspent() {
    local wallet="$1"
    local der_xpub=${DER_XPUB_MAP[$wallet]}
    _trace "$BDKI" -n $NETWORK wallet -w "$wallet" \
        -d "${DESC_TYPE}($der_xpub)" list_unspent
}

_sync_wallet() {
    local wallet="$1"
    _log "syncing wallet $wallet"
    local der_xpub=${DER_XPUB_MAP[$wallet]}
    _trace "$BDKI" -n $NETWORK wallet -w "$wallet" \
        -d "${DESC_TYPE}($der_xpub)" -s $ELECTRUM sync
}

# main functions
check_balance() {
    local wallet="$1"
    local expected="$2"
    local contract_name="$3"
    _subtit "checking \"$contract_name\" balance for $wallet"
    local contract_id allocations amount id
    id=${WLT_ID_MAP[$wallet]}
    contract_id=${CONTRACT_MAP[$contract_name]}
    mapfile -t outpoints < <(_trace _list_unspent "$wallet" | jq -r '.[] |.outpoint')
    BALANCE=0
    if [ "${#outpoints[@]}" -gt 0 ]; then
        _log "outpoints:"
        # shellcheck disable=2001
        echo -n "    " && echo "${outpoints[*]}" | sed 's/ /\n    /g'
        allocations=$(_trace "${RGB[@]}" -d "data${id}" state "$contract_id" $IFACE \
            | grep 'amount=' | awk -F',' '{print $1" "$2}')
        _log "allocations:"
        echo "$allocations"
        for utxo in "${outpoints[@]}"; do
            amount=$(echo "$allocations" \
                | grep "$utxo" | awk '{print $1}' | awk -F'=' '{print $2}')
            BALANCE=$((BALANCE + amount))
        done
    fi
    if [ "$BALANCE" != "$expected" ]; then
        _die "$(printf '%s' \
            "balance \"$BALANCE\" for contract \"$contract_id\" " \
            "($contract_name) differs from the expected \"$expected\"")"
    fi
    _log "$(printf '%s' \
        "balance \"$BALANCE\" for contract \"$contract_id\" " \
        "($contract_name) matches the expected one")"
}

check_schemata_version() {
    if ! sha256sum -c --status rgb-schemata.sums; then
        _die "rgb-schemata version mismatch (hint: try \"git submodule update\")"
    fi
}

check_tools() {
    _subtit "checking required tools"
    local required_tools="base64 cargo cut docker grep head jq sha256sum"
    for tool in $required_tools; do
        if ! which "$tool" >/dev/null; then
            _die "could not find reruired tool \"$tool\", please install it and try again"
        fi
    done
    if ! docker compose >/dev/null; then
        _die "could not call docker compose (hint: install docker compose plugin)"
    fi
}

cleanup() {
    _subtit "stopping services and cleaning data directories"
    docker compose down
    rm -rf data{0,1,2,core,index}
}

export_asset() {
    local contract_name="$1"
    local contract_file contract_id wlt_data
    contract_file=${CONTRACT_DIR}/${contract_name}.rgb
    contract_id=${CONTRACT_MAP[$contract_name]}
    wlt_data="data${WLT_ID_MAP["issuer"]}"
    _trace "${RGB[@]}" -d $wlt_data export "$contract_id" "$contract_file"
}

get_issue_utxo() {
    _subtit "creating issuance UTXO"
    [ $DEBUG = 1 ] && _log "unspents before issuance" && _list_unspent issuer
    _gen_utxo issuer
    TXID_ISSUE=$txid
    VOUT_ISSUE=$vout
}

import_asset() {
    local contract_name="$1"
    local wallet="$2"
    local contract_file wallet_id
    contract_file=${CONTRACT_DIR}/${contract_name}.rgb
    wallet_id=${WLT_ID_MAP[$wallet]}
    _trace "${RGB[@]}" -d "data${wallet_id}" import "$contract_file"
}

issue_asset() {
    local contract_name="$1"
    _subtit "issuing asset \"$contract_name\""
    local contract_base contract_tmpl contract_yaml
    local contract_id issuance wlt_data
    wlt_data="data${WLT_ID_MAP["issuer"]}"
    contract_base=${CONTRACT_DIR}/${contract_name}
    contract_tmpl=${contract_base}.yaml.template
    contract_yaml=${contract_base}.yaml
    sed \
        -e "s/issued_supply/2000/" \
        -e "s/created_timestamp/$(date +%s)/" \
        -e "s/closing_method/$CLOSING_METHOD/" \
        -e "s/txid/$TXID_ISSUE/" \
        -e "s/vout/$VOUT_ISSUE/" \
        "$contract_tmpl" > "$contract_yaml"
    issuance="$(_trace "${RGB[@]}" -d $wlt_data issue "$SCHEMA" $IFACE "$contract_yaml" 2>&1)"
    echo "issuance: $issuance"
    contract_id="$(echo "$issuance" | grep '^A new contract' | cut -d' ' -f4)"
    CONTRACT_MAP[$contract_name]=$contract_id
    _log "contract ID: $contract_id"
    _log "contract state after issuance"
    _trace "${RGB[@]}" -d $wlt_data state "$contract_id" $IFACE
    [ $DEBUG = 1 ] && _log "unspents after issuance" && _list_unspent issuer
}

install_rust_crate() {
    local crate="$1"
    local version="$2"
    if [ -n "$3" ]; then
        read -r -a features <<< "$3"
    fi
    if [ -n "$4" ]; then
        read -r -a opts <<< "$4"
    fi
    _subtit "installing $crate to ./$crate"
    cargo install "$crate" --version "$version" --locked \
        --root "./$crate" "${features[@]}" "${opts[@]}" \
        || _die "error installing $crate"
}

prepare_wallets() {
    _subtit "preparing wallets"
    local xprv
    _trace "${BCLI[@]}" createwallet miner >/dev/null
    _gen_blocks 103
    for wallet in "${WALLETS[@]}"; do
        _log "generating new descriptors for wallet $wallet"
        rm -rf "$HOME/.bdk-bitcoin/$wallet"
        xprv="$(_trace "$BDKI" key generate | jq -r '.xprv')"
        DER_XPRV_MAP[$wallet]=$(_trace "$BDKI" key derive -p $DERIVE_PATH/$CHANGE_INDEX -x "$xprv" | jq -r '.xprv')
        DER_XPUB_MAP[$wallet]=$(_trace "$BDKI" key derive -p $DERIVE_PATH/$CHANGE_INDEX -x "$xprv" | jq -r '.xpub')
        [ $DEBUG = 1 ] && echo "xprv: $xprv"
        [ $DEBUG = 1 ] && echo "der_xprv: ${DER_XPRV_MAP[$wallet]}"
        [ $DEBUG = 1 ] && echo "der_xpub: ${DER_XPUB_MAP[$wallet]}"
    done
}

# shellcheck disable=2034
set_aliases() {
    _subtit "setting command aliases"
    BCLI=("docker" "compose" "exec" "-T" "-u" "blits" "bitcoind" "bitcoin-cli" "-$NETWORK")
    BDKI="bdk-cli/bin/bdk-cli"
    RGB=("rgb-contracts/bin/rgb" "-n" "$NETWORK")
}

setup_rgb_clients() {
    _subtit "setting up RGB clients"
    local data num schemata_dir
    data="data"
    schemata_dir="./rgb-schemata/schemata"
    for num in 0 1 2; do
        _trace "${RGB[@]}" -d ${data}${num} import $schemata_dir/NonInflatableAssets.rgb
        _trace "${RGB[@]}" -d ${data}${num} import $schemata_dir/NonInflatableAssets-RGB20.rgb
    done
    SCHEMA="$(_trace "${RGB[@]}" -d ${data}${num} schemata | awk '{print $1}')"
    _log "schema: $SCHEMA"
    [ $DEBUG = 1 ] && _trace "${RGB[@]}" -d ${data}${num} interfaces
}

start_services() {
    _subtit "checking data directories"
    for data_dir in data0 data1 data2 datacore dataindex; do
       if [ -d "$data_dir" ]; then
           if [ "$(stat -c %u $data_dir)" = "0" ]; then
               echo "existing data directory \"$data_dir\" found, owned by root"
               echo "please remove it and try again (e.g. 'sudo rm -r $data_dir')"
               _die "cannot continue"
           fi
           echo "existing data directory \"$data_dir\" found, removing"
           rm -r $data_dir
       fi
       mkdir -p "$data_dir"
    done
    _subtit "stopping services"
    docker compose down
    _subtit "checking bound ports"
    if ! which ss >/dev/null; then
        _log "ss not available, skipping bound ports check"
        return
    fi
    # see docker-compose.yml for the exposed ports
    if [ -n "$(ss -HOlnt 'sport = :50001')" ];then
        _die "port 50001 is already bound, electrs service can't start"
    fi
    _subtit "starting services"
    docker compose up -d
}

transfer_asset() {
    transfer_create "$@"    # parameter pass-through
    transfer_complete       # uses global variables set by transfer_create
    # unset global variables set by transfer operations
    unset BALANCE CONSIGNMENT NAME PSBT
    unset BLNC_RCPT BLNC_SEND RCPT_WLT SEND_WLT
}

transfer_create() {
    ## params
    local wallets="$1"          # sender>receiver wallet names
    local input_outpoint="$2"   # input outpoint
    local balances="$3"         # expected sender/recipient starting balances
    local send_amounts="$4"     # asset amount/change for the transfer
    local witness="$5"          # 1 for witness txid, blinded UTXO otherwise
    local reuse_invoice="$6"    # 1 to re-use the previous invoice
    NAME="${7:-"usdt"}"         # optional contract name (default: usdt)
    local input_outpoint_2="$8" # optional second input outpoint

    # increment transfer number
    TRANSFER_NUM=$((TRANSFER_NUM+1))

    ## data variables
    local contract_id rcpt_data rcpt_id send_data send_id
    local blnc_send blnc_rcpt send_amt send_chg
    SEND_WLT=$(echo "$wallets" |cut -d/ -f1)
    RCPT_WLT=$(echo "$wallets" |cut -d/ -f2)
    send_id=${WLT_ID_MAP[$SEND_WLT]}
    rcpt_id=${WLT_ID_MAP[$RCPT_WLT]}
    contract_id=${CONTRACT_MAP[$NAME]}
    send_data="data${send_id}"
    rcpt_data="data${rcpt_id}"
    send_amt=$(echo "$send_amounts" |cut -d/ -f1)
    send_chg=$(echo "$send_amounts" |cut -d/ -f2)
    blnc_send=$(echo "$balances" |cut -d/ -f1)
    blnc_rcpt=$(echo "$balances" |cut -d/ -f2)

    ## starting situation
    _log "spending $send_amt from $input_outpoint ($SEND_WLT) with $send_chg change"
    if [ -n "$input_outpoint_2" ]; then  # handle double input case
        _log "also using $input_outpoint_2 as input"
    fi
    [ $DEBUG = 1 ] && _log "sender unspents before transfer" && _list_unspent "$SEND_WLT"
    [ $DEBUG = 1 ] && _log "recipient unspents before transfer" && _list_unspent "$RCPT_WLT"
    _subtit "initial balances"
    check_balance "$SEND_WLT" "$blnc_send" "$NAME"
    check_balance "$RCPT_WLT" "$blnc_rcpt" "$NAME"
    BLNC_SEND=$((blnc_send-send_amt))
    BLNC_RCPT=$((blnc_rcpt+send_amt))
    [ "$BLNC_SEND" = "$send_chg" ] || \
        _die "expected final sender balance ($BLNC_SEND) differs from the provided one ($send_chg)"

    ## generate invoice
    _subtit "(recipient) preparing invoice for transfer n. $TRANSFER_NUM"
    if [ "$reuse_invoice" != 1 ]; then
        _gen_utxo "$RCPT_WLT"
        TXID_RCPT=$txid
        VOUT_RCPT=$vout
        INVOICE="$(_trace "${RGB[@]}" -d "$rcpt_data" invoice \
            "$contract_id" $IFACE "$send_amt" "$CLOSING_METHOD:$TXID_RCPT:$VOUT_RCPT")"
        # replace invoice blinded UTXO with an address if witness UTXO is selected
        if [ "$witness" = 1 ]; then
            _gen_addr_bdk "$RCPT_WLT"
            ADDR_RCPT=$ADDR
            INVOICE="${INVOICE%+*}"
            INVOICE="${INVOICE}+$ADDR_RCPT"
        fi
    fi
    _log "invoice: $INVOICE"

    ## prepare PSBT
    _subtit "(sender) preparing PSBT"
    declare inputs=()
    local addr_send der_xpub filter opret psbt_to utxos
    # generate new address for sender
    _gen_addr_bdk "$SEND_WLT"
    addr_send=$ADDR
    [ $DEBUG = 1 ] && _list_unspent "$SEND_WLT"
    PSBT=tx_${TRANSFER_NUM}.psbt
    der_xpub=${DER_XPUB_MAP[$SEND_WLT]}
    utxos=("$input_outpoint")
    if [ -n "$input_outpoint_2" ]; then  # handle double input case
        utxos+=("$input_outpoint_2")
    fi
    for utxo in "${utxos[@]}"; do
        inputs+=("--utxos" "$utxo")
    done
    psbt_to=(--send_all --to "$addr_send:0")
    if [ "$witness" = 1 ]; then
        # get unspent amount from input UTXOs + compute change amt
        local amt_change amt_filter amt_input amt_utxo
        amt_input=0
        for utxo in "${utxos[@]}"; do
            amt_filter=".[] |select(.outpoint == \"$utxo\") |.txout |.value"
            amt_utxo=$(_list_unspent "$SEND_WLT" | jq -r "$amt_filter")
            amt_input=$((amt_input+amt_utxo))
        done
        amt_change=$((amt_input-AMT_RCPT-AMT_FEES))
        [ $DEBUG = 1 ] && _log "input amount: $amt_input"
        # set outputs to change with computed amount + rcpt
        psbt_to=(--to "$addr_send:$amt_change" --to "$ADDR_RCPT:$AMT_RCPT")
    fi
    [ "$CLOSING_METHOD" = "opret1st" ] && opret=("--add_string" "opret")
    _trace "$BDKI" -n $NETWORK wallet -w "$SEND_WLT" \
        -d "${DESC_TYPE}($der_xpub)" create_tx \
        -f 5 "${inputs[@]}" "${psbt_to[@]}" "${opret[@]}" \
            | jq -r '.psbt' | base64 -d >"$send_data/$PSBT"
    # set opret/tapret host
    _trace "${RGB[@]}" -d "$send_data" set-host --method $CLOSING_METHOD \
        "$send_data/$PSBT"

    ## RGB tansfer
    _subtit "(sender) preparing RGB transfer"
    CONSIGNMENT="consignment_${TRANSFER_NUM}.rgb"
    _trace "${RGB[@]}" -d "$send_data" transfer --method $CLOSING_METHOD \
        "$send_data/$PSBT" "$INVOICE" "$send_data/$CONSIGNMENT"
    if ! ls "$send_data/$CONSIGNMENT" >/dev/null 2>&1; then
        _die "could not locate consignment file: $send_data/$CONSIGNMENT"
    fi

    ## extract PSBT data
    local decoded_psbt
    decoded_psbt="$(_trace "${BCLI[@]}" decodepsbt "$(base64 -w0 "$send_data/$PSBT")")"
    if [ $DEBUG = 1 ]; then
        _log "showing PSBT including RGB transfer data"
        echo "$decoded_psbt" | jq
    fi
    TXID_CHANGE="$(echo "$decoded_psbt" | jq -r '.tx |.txid')"
    # select vout which is not OP_RETURN (0) nor witness UTXO (AMT_RCPT)
    VOUT_CHANGE="$(echo "$decoded_psbt" | jq -r '.tx |.vout |.[] |select(.value > 0.001) |.n')"
    [ $DEBUG = 1 ] && _log "change outpoint: $TXID_CHANGE:$VOUT_CHANGE"

    ## copy generated consignment to recipient
    _subtit "(sender) copying consignment to recipient data directory"
    _trace cp {"$send_data","$rcpt_data"}/"$CONSIGNMENT"
    # inspect consignment (output to file as it's very big)
    _trace "${RGB[@]}" -d "$rcpt_data" inspect \
        "$send_data/$CONSIGNMENT" > "$CONSIGNMENT.inspect"
    _log "consignment inspect logged to file: $CONSIGNMENT.inspect"
}

transfer_complete() {
    ## recipient: validate transfer
    _subtit "(recipient) validating consignment"
    local rcpt_data rcpt_id send_data send_id vldt
    send_id=${WLT_ID_MAP[$SEND_WLT]}
    rcpt_id=${WLT_ID_MAP[$RCPT_WLT]}
    send_data="data${send_id}"
    rcpt_data="data${rcpt_id}"
    vldt="$(_trace "${RGB[@]}" -d "$rcpt_data" validate \
        "$rcpt_data/$CONSIGNMENT" 2>&1)"
    _log "$vldt"
    if echo "$vldt" | grep -q 'Consignment is NOT valid'; then
        _die "validation failed"
    fi

    ## sign + finalize + broadcast PSBT
    _subtit "(sender) signing and broadcasting tx"
    local der_xprv der_xpub psbt_finalized psbt_signed
    der_xprv=${DER_XPRV_MAP[$SEND_WLT]}
    der_xpub=${DER_XPUB_MAP[$SEND_WLT]}
    psbt_signed=$(_trace "$BDKI" -n $NETWORK wallet -w "$SEND_WLT" \
        -d "${DESC_TYPE}($der_xprv)" sign \
        --psbt "$(base64 -w0 "$send_data/$PSBT")")
    psbt_finalized=$(echo "$psbt_signed" \
        | jq -r 'select(.is_finalized = true) |.psbt')
    [ -n "$psbt_finalized" ] || _die "error signing or finalizing PSBT"
    echo "$psbt_finalized" \
        | base64 -d > "$send_data/finalized-bdk_${TRANSFER_NUM}.psbt"
    _log "signed + finalized PSBT: $psbt_finalized"
    _trace "$BDKI" -n $NETWORK wallet -w "$SEND_WLT" \
        -d "${DESC_TYPE}($der_xpub)" -s $ELECTRUM broadcast \
        --psbt "$psbt_finalized"

    ## mine and sync wallets
    _subtit "confirming transaction"
    _gen_blocks 1
    _subtit "syncing wallets"
    _sync_wallet "$SEND_WLT"
    _sync_wallet "$RCPT_WLT"

    ## accept transfer
    local accept
    _subtit "(recipient) accepting transfer"
    accept="$(_trace "${RGB[@]}" -d "data${rcpt_id}" accept \
        "$rcpt_data/$CONSIGNMENT" 2>&1)"
    _log "$accept"
    if echo "$accept" | grep -q 'Consignment is NOT valid'; then
        _die "validation failed"
    fi

    ## ending situation
    [ $DEBUG = 1 ] && _log "sender unspents after transfer" && _list_unspent "$SEND_WLT"
    [ $DEBUG = 1 ] && _log "recipient unspents after transfer" && _list_unspent "$RCPT_WLT"
    _subtit "final balances"
    check_balance "$SEND_WLT" "$BLNC_SEND" "$NAME"
    check_balance "$RCPT_WLT" "$BLNC_RCPT" "$NAME"
}

help() {
    echo "$NAME [-h|--help] [-t|--tapret] [-v|--verbose]"
    echo ""
    echo "options:"
    echo "    -h --help     show this help message"
    echo "    -t --tapret   user tapret1st closing method"
    echo "    -v --verbose  enable verbose output"
}


# cmdline arguments
while [ -n "$1" ]; do
    case $1 in
        -h|--help)
            help
            exit 0
            ;;
        -t|--tapret)
            _log "tapret support is unavailable at the moment"
            exit 2
            CLOSING_METHOD="tapret1st"
            CHANGE_INDEX=10
            DESC_TYPE="tr"
            ;;
        -v|--verbose)
            DEBUG=1
            ;;
        *)
            help
            _die "unsupported argument \"$1\""
            ;;
    esac
    shift
done

# initial setup
_tit "setting up"
check_tools
check_schemata_version
set_aliases
install_rust_crate "bdk-cli" "$BDK_CLI_VER" "$BDK_CLI_FEATURES" "--debug"
install_rust_crate "rgb-contracts" "$RGB_CONTRACTS_VER" "$RGB_CONTRACTS_FEATURES"
trap cleanup EXIT
start_services
setup_rgb_clients
prepare_wallets

# asset issuance
_tit "issuing assets"
get_issue_utxo
issue_asset "usdt"
issue_asset "other"
_tit "checking asset balances after issuance"
check_balance "issuer" "2000" "usdt"
check_balance "issuer" "2000" "other"

# export/import asset
_tit "exporting asset"
export_asset usdt
_tit "importing asset to recipient 1"
import_asset usdt rcpt1
import_asset usdt rcpt2

# transfer loop:
#   1. issuer -> rcpt 1 (spend issuance)
#     1a. only initiate tranfer, don't complete (aborted transfer)
#     1b. retry transfer (re-using invoice) and complete it
#   2. check asset balances (blank)
#   3. issuer -> rcpt 1 (spend change)
#   4. rcpt 1 -> rcpt 2 (spend both received allocations)
#   5. rcpt 2 -> issuer (close loop)
#   6. issuer -> rcpt 1 (spend received back)
#   7. rcpt 1 -> rcpt 2 (WitnessUtxo)
_tit "creating transfer from issuer to recipient 1 (but not completing it)"
transfer_create issuer/rcpt1 "$TXID_ISSUE:$VOUT_ISSUE" 2000/0 100/1900 0 0
_tit "transferring asset from issuer to recipient 1 (spend issuance)"
transfer_asset issuer/rcpt1 "$TXID_ISSUE:$VOUT_ISSUE" 2000/0 100/1900 0 1
outpoint_1="$TXID_RCPT:$VOUT_RCPT"

_tit "checking issuer asset balances after the 1st transfer (blank transition)"
check_balance "issuer" "1900" "usdt"
check_balance "issuer" "2000" "other"

_tit "transferring asset from issuer to recipient 1 (spend change)"
transfer_asset issuer/rcpt1 "$TXID_CHANGE:$VOUT_CHANGE" 1900/100 200/1700 0 0
outpoint_2="$TXID_RCPT:$VOUT_RCPT"

_tit "transferring asset from recipient 1 to recipient 2 (spend received)"
transfer_asset rcpt1/rcpt2 "$outpoint_1" 300/0 150/150 0 0 usdt "$outpoint_2"

_tit "transferring asset from recipient 2 to issuer"
transfer_asset rcpt2/issuer "$TXID_RCPT:$VOUT_RCPT" 150/1700 100/50 0 0

_tit "transferring asset from issuer to recipient 1 (spend received back)"
transfer_asset issuer/rcpt1 "$TXID_RCPT:$VOUT_RCPT" 1800/150 50/1750 0 0

_tit "transferring asset from recipient 1 to recipient 2 (spend with witness UTXO)"
transfer_asset rcpt1/rcpt2 "$TXID_RCPT:$VOUT_RCPT" 200/50 40/160 1 0

_tit "checking final asset balances"
check_balance "issuer" "1750" "usdt"
check_balance "rcpt1" "160" "usdt"
check_balance "rcpt2" "90" "usdt"
check_balance "issuer" "2000" "other"

_tit "sandbox run finished"
