#!/usr/bin/env bash

# variables
CONTRACT_DIR="contracts"
DEBUG=0
NAME=$(basename "$0")
NETWORK="regtest"
TRANSFER_NUM=0
WALLET_NUM=0
WALLET_PATH="wallets"
WALLETS=()

# crate variables
DESCRIPTOR_WALLET_FEATURES="--all-features"  # cli,hot are enough but rebuilds each time, see https://github.com/rust-lang/cargo/issues/8703
DESCRIPTOR_WALLET_VER="0.10.2"
RGB_WALLET_FEATURES=""
RGB_WALLET_VER="0.11.0-beta.5"

# closing method / derivation variables
CLOSING_METHODS=("opret1st" "tapret1st")

# rgb-schemata variables
INTERFACE_DIR="./rgb-schemata/interfaces"
SCHEMATA_DIR="./rgb-schemata/schemata"

# indexer variables
ELECTRUM_PORT=50001
ELECTRUM_ENDPOINT="localhost:$ELECTRUM_PORT"
ESPLORA_ENDPOINT="http://localhost:8094/regtest/api"
INDEXER_CLI="--electrum"
INDEXER_ENDPOINT=$ELECTRUM_ENDPOINT
PROFILE="electrum"

# shell colors
C1='\033[0;32m' # green
C2='\033[0;33m' # orange
C3='\033[0;34m' # blue
C4='\033[0;31m' # red
NC='\033[0m'    # No Color

# maps
declare -A CONTRACT_ID_MAP
declare -A CONTRACT_SCHEMA_MAP
declare -A DESC_MAP
declare -A IFACE_MAP
IFACE_MAP["NIA"]="RGB20"
IFACE_MAP["CFA"]="RGB25"
declare -A SCHEMA_MAP
declare -A WLT_CM_MAP
declare -A WLT_ID_MAP


# internal utility functions
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
    # note: calls redirecting stderr to /dev/null will drop xtrace output
    { local trace=0; } 2>/dev/null
    { [ -o xtrace ] && trace=1; } 2>/dev/null
    { [ $DEBUG = 1 ] && set -x; } 2>/dev/null
    if ! "$@"; then
        { set +x; } 2>/dev/null
        _die "command '$*' returned a non-zero exit code (transfer $TRANSFER_NUM)"
    fi
    { [ $trace == 0 ] && set +x; } 2>/dev/null
}

# internal functions
_check_method() {
    local match="$1"
    for m in "${CLOSING_METHODS[@]}"; do
        [ "$m" = "$match" ] && return
    done
    _die "unknown $match closing method"
}

_gen_addr_rgb() {
    local wallet="$1"
    local keychain="$2"
    _log "generating new address for wallet \"$wallet\""
    local wallet_id=${WLT_ID_MAP[$wallet]}
    ADDR="$(_trace "${RGB[@]}" -d "data${wallet_id}" address -w "$wallet" -k "$keychain" 2>/dev/null \
        | awk '/bcrt/ {print $NF}')"
    _log "generated address: $ADDR"
}

_wait_indexers_sync() {
    echo -n "waiting for indexer to have synced"
    local block_count
    block_count=$("${BCLI[@]}" getblockcount)
    if [ "$PROFILE" = "electrum" ]; then
        local electrum_json electrum_res
        # shellcheck disable=2089
        electrum_json="{\"jsonrpc\": \"2.0\", \"method\": \"blockchain.block.header\", \"params\": [$block_count], \"id\": 0}"
        while :; do
            electrum_res="$(echo "$electrum_json" \
                | netcat -w1 localhost $ELECTRUM_PORT \
                | jq '.result')"
            [ -n "$electrum_res" ] && break
            echo -n "."
            sleep 1
        done
    fi
    if [ "$PROFILE" = "esplora" ]; then
        local esplora_height
        while :; do
            esplora_height=$(curl -s $ESPLORA_ENDPOINT/blocks/tip/height)
            [ "$block_count" == "$esplora_height" ] && break
            echo -n "."
            sleep 1
        done
    fi
    echo " done"
}

_gen_blocks() {
    local count="$1"
    _log "mining $count block(s)"
    _trace "${BCLI[@]}" -rpcwallet=miner -generate "$count" >/dev/null
    _wait_indexers_sync
}

_sync_wallet() {
    local wallet="$1"
    _log "syncing wallet $wallet"
    local wallet_id=${WLT_ID_MAP[$wallet]}
    _trace "${RGB[@]}" -d "data${wallet_id}" utxos -w "$wallet" --sync
}

_get_utxo() {
    local wallet="$1"
    local txid="$2"
    _log "extracting vout"
    local wallet_id=${WLT_ID_MAP[$wallet]}
    vout=$(_trace "${RGB[@]}" -d "data${wallet_id}" utxos -w "$wallet" 2>/dev/null \
        | awk "/$txid/ {print \$NF}" | cut -d: -f2)
    [ -n "$vout" ] || _die "couldn't retrieve vout for txid $txid"
    _log "txid $txid, vout: $vout"
}

_gen_utxo() {
    local wallet="$1"
    local keychain="$2"
    if [ -z "$keychain" ]; then
        if [ "${WLT_CM_MAP[$wallet]}" = "opret1st" ]; then
            keychain=9
        else
            keychain=10
        fi
    fi
    _gen_addr_rgb "$wallet" "$keychain"
    _log "sending funds to wallet \"$wallet\" on keychain \"$keychain\""
    txid="$(_trace "${BCLI[@]}" -rpcwallet=miner sendtoaddress "$ADDR" 1)"
    _gen_blocks 1
    _sync_wallet "$wallet"
    _get_utxo "$wallet" "$txid"
}

_list_unspent() {
    local wallet="$1"
    local wallet_id=${WLT_ID_MAP[$wallet]}
    _trace "${RGB[@]}" -d "data${wallet_id}" utxos -w "$wallet"
}

_show_state() {
    local wallet="$1"
    local contract_name="$2"
    local contract_id iface schema wallet_id
    wallet_id=${WLT_ID_MAP[$wallet]}
    contract_id=${CONTRACT_ID_MAP[$contract_name]}
    schema=${CONTRACT_SCHEMA_MAP[$contract_name]}
    iface=${IFACE_MAP[$schema]}
    _trace "${RGB[@]}" -d "data${wallet_id}" \
        state -w "$wallet" "$contract_id" "$iface"
}


# helper functions
check_schemata_version() {
    if ! sha256sum -c --status rgb-schemata.sums; then
        _die "rgb-schemata version mismatch (hint: try \"git submodule update\")"
    fi
}

check_tools() {
    _subtit "checking required tools"
    local required_tools="awk base64 cargo cut docker grep head jq netcat sha256sum"
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
    docker compose --profile '*' down --remove-orphans -v
    rm -rf data{0,1,2,core,index}
}

install_rust_crate() {
    local crate="$1"
    local version="$2"
    local features opts
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

# shellcheck disable=2034
set_aliases() {
    _subtit "setting command aliases"
    BITCOIND_CLI=("docker" "compose" "exec" "-T" "-u" "blits" "bitcoind" "bitcoin-cli" "-regtest")
    BTCHOT=("descriptor-wallet/bin/btc-hot")
    BTCCOLD=("descriptor-wallet/bin/btc-cold")
    ESPLORA_CLI=("docker" "compose" "exec" "-T" "esplora" "cli")
    RGB=("rgb-wallet/bin/rgb" "-n" "$NETWORK" "$INDEXER_CLI" "$INDEXER_ENDPOINT")
    if [ "$PROFILE" = "electrum" ]; then
        BCLI=("${BITCOIND_CLI[@]}")
    else
        BCLI=("${ESPLORA_CLI[@]}")
    fi
}

start_services() {
    _subtit "checking data directories"
    for data_dir in data0 data1 data2; do
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
    docker compose --profile '*' down --remove-orphans -v
    _subtit "checking bound ports"
    if ! which ss >/dev/null; then
        _log "ss not available, skipping bound ports check"
        return
    fi
    # see docker-compose.yml for the exposed ports
    [ "$PROFILE" = "electrum" ] && EXPOSED_PORTS=(50001)
    [ "$PROFILE" = "esplora" ] && EXPOSED_PORTS=(8094)
    for port in "${EXPOSED_PORTS[@]}"; do
        if [ -n "$(ss -HOlnt "sport = :$port")" ];then
            _die "port $port is already bound, services can't be started"
        fi
    done
    _subtit "starting services"
    docker compose --profile $PROFILE up -d
    echo -n "waiting for services to have started..."
    if [ "$PROFILE" = "electrum" ]; then
        # bitcoind
        until docker compose logs bitcoind |grep -q 'Bound to'; do
            sleep 1
        done
    fi
    if [ "$PROFILE" = "esplora" ]; then
        # esplora
        until docker compose logs esplora |grep -q 'waiting for bitcoind sync to finish'; do
            sleep 1
        done
    fi
    echo " done"
}


# main functions
check_balance() {
    local wallet="$1"
    local expected="$2"
    local contract_name="$3"
    _subtit "checking \"$contract_name\" balance for $wallet"
    local contract_id allocations amount wallet_id schema iface
    wallet_id=${WLT_ID_MAP[$wallet]}
    contract_id=${CONTRACT_ID_MAP[$contract_name]}
    schema=${CONTRACT_SCHEMA_MAP[$contract_name]}
    iface=${IFACE_MAP[$schema]}
    schema_id=${SCHEMA_MAP[$schema]}
    mapfile -t outpoints < <(_trace _list_unspent "$wallet" | awk '/:[0-9]+$/ {print $NF}')
    BALANCE=0
    if [ "${#outpoints[@]}" -gt 0 ]; then
        _log "outpoints:"
        for outpoint in "${outpoints[@]}"; do
            echo " - $outpoint"
        done
        mapfile -t allocations < <(_trace "${RGB[@]}" -d "data${wallet_id}" \
            state -w "$wallet" "$contract_id" "$iface" 2>/dev/null \
            | grep 'amount=' | awk -F',' '{print $1" "$2}')
        _log "allocations:"
        for allocation in "${allocations[@]}"; do
            echo " - $allocation"
        done
        for utxo in "${outpoints[@]}"; do
            for allocation in "${allocations[@]}"; do
                amount=$(echo "$allocation" \
                    | awk "/$utxo/ {print \$1}" | awk -F'=' '{print $2}')
                BALANCE=$((BALANCE + amount))
            done
        done
    fi
    if [ "$BALANCE" != "$expected" ]; then
        _die "$(printf '%s' \
            "balance $BALANCE for contract $contract_id ($contract_name) " \
            "differs from the expected $expected (transfer $TRANSFER_NUM)")"
    fi
    _log "$(printf '%s' \
        "balance $BALANCE for contract $contract_id " \
        "($contract_name) matches the expected one")"
}

export_asset() {
    local contract_name="$1"
    local contract_file contract_id wallet wallet_id
    contract_file=${CONTRACT_DIR}/${contract_name}.rgb
    contract_id=${CONTRACT_ID_MAP[$contract_name]}
    wallet="issuer"
    wallet_id=${WLT_ID_MAP[$wallet]}
    _trace "${RGB[@]}" -d "data${wallet_id}" export -w "$wallet" "$contract_id" "$contract_file"
}

get_issue_utxo() {
    local wallet="$1"
    _subtit "creating issuance UTXO for wallet $wallet"
    [ $DEBUG = 1 ] && _log "unspents before issuance" && _list_unspent "$wallet"
    _gen_utxo "$wallet"
    TXID_ISSUE=$txid
    VOUT_ISSUE=$vout
}

import_asset() {
    local contract_name="$1"
    local wallet="$2"
    local contract_file wallet_id
    contract_file=${CONTRACT_DIR}/${contract_name}.rgb
    wallet_id=${WLT_ID_MAP[$wallet]}
    # note: all output to stderr
    _trace "${RGB[@]}" -d "data${wallet_id}" import -w "$wallet" "$contract_file" 2>&1 | grep Contract
}

# requires get_issue_utxo to have been called first
issue_asset() {
    local wallet="$1"
    local contract_name="$2"
    local schema="$3"
    local method="$4"
    _tit "issuing $schema asset \"$contract_name\" ($method)"
    _check_method "$method"
    local contract_base contract_tmpl contract_yaml iface schema_id
    local contract_id issuance wallet_id
    wallet_id=${WLT_ID_MAP[$wallet]}
    contract_base=${CONTRACT_DIR}/${contract_name}
    contract_tmpl=${contract_base}.yaml.template
    contract_yaml=${contract_base}.yaml
    iface=${IFACE_MAP[$schema]}
    schema_id=${SCHEMA_MAP[$schema]}
    sed \
        -e "s/issued_supply/2000/" \
        -e "s/closing_method/$method/" \
        -e "s/txid/$TXID_ISSUE/" \
        -e "s/vout/$VOUT_ISSUE/" \
        "$contract_tmpl" > "$contract_yaml"
    issuance="$(_trace "${RGB[@]}" -d "data${wallet_id}" issue -w "$wallet" "$schema_id" "$contract_yaml" 2>&1)"
    _log "$issuance"
    contract_id="$(echo "$issuance" | grep '^A new contract' | cut -d' ' -f4)"
    CONTRACT_ID_MAP[$contract_name]=$contract_id
    CONTRACT_SCHEMA_MAP[$contract_name]=$schema
    _log "contract ID: $contract_id"
    _log "contract state after issuance"
    _trace "${RGB[@]}" -d "data${wallet_id}" state -w "$wallet" "$contract_id" "$iface"
    [ $DEBUG = 1 ] && _log "unspents after issuance" && _list_unspent "$wallet"
}

prepare_btc_wallet() {
    _subtit "preparing bitcoind wallet"
    _trace "${BCLI[@]}" createwallet miner
    _gen_blocks 103
}

prepare_rgb_wallet() {
    local wallet="$1"
    local method="$2"
    _subtit "preparing $method wallet $wallet ($WALLET_NUM)"
    # closing-method-dependent variables
    _check_method "$method"
    local der_scheme desc_opt descriptor keychain
    if [ "$method" = opret1st ]; then
        der_scheme="bip84"
        desc_opt="--wpkh"
        keychain="<0;1;9>"
    else
        der_scheme="bip86"
        desc_opt="--tapret-key-only"
        keychain="<0;1;9;10>"
    fi
    # BTC setup
    mkdir -p $WALLET_PATH
    rm -rf "$WALLET_PATH/$wallet.{derive,seed}"
    _log "creating wallet $wallet"
    _trace "${BTCHOT[@]}" seed -p '' "$WALLET_PATH/$wallet.seed"
    descriptor="$(_trace "${BTCHOT[@]}" derive \
        -s $der_scheme --testnet --seed-password '' --account-password '' \
        "$WALLET_PATH/$wallet.seed" "$WALLET_PATH/$wallet.derive" \
        | tail -2 | head -1)"
    DESC_MAP[$wallet]="$(echo "$descriptor" \
        | sed -e 's/^.*(//' -e 's/).*$//' -e "s#/\*/#/$keychain/#")"
    [ $DEBUG = 1 ] && echo "descriptor: ${DESC_MAP[$wallet]}"
    WALLETS+=("$wallet")
    WLT_ID_MAP[$wallet]=$WALLET_NUM
    ((WALLET_NUM+=1))
    WLT_CM_MAP[$wallet]=$method
    # RGB setup
    _log "setting up RGB for wallet $wallet"
    wallet_id=${WLT_ID_MAP[$wallet]}
    _trace "${RGB[@]}" -d "data${wallet_id}" create $desc_opt "${DESC_MAP[$wallet]}" "$wallet"
    # NIA
    _trace "${RGB[@]}" -d "data${wallet_id}" import -w "$wallet" $INTERFACE_DIR/RGB20.rgb
    schema_nia="$(_trace "${RGB[@]}" -d "data${wallet_id}" import -w "$wallet" $SCHEMATA_DIR/NonInflatableAssets.rgb 2>&1 | awk '/^Schema/ {print $2}')"
    _trace "${RGB[@]}" -d "data${wallet_id}" import -w "$wallet" $SCHEMATA_DIR/NonInflatableAssets-RGB20.rgb
    # CFA
    _trace "${RGB[@]}" -d "data${wallet_id}" import -w "$wallet" $INTERFACE_DIR/RGB25.rgb
    schema_cfa="$(_trace "${RGB[@]}" -d "data${wallet_id}" import -w "$wallet" $SCHEMATA_DIR/CollectibleFungibleAssets.rgb 2>&1 | awk '/^Schema/ {print $2}')"
    _trace "${RGB[@]}" -d "data${wallet_id}" import -w "$wallet" $SCHEMATA_DIR/CollectibleFungibleAssets-RGB25.rgb
    # first wallet only
    if [ $wallet_id = 0 ]; then
        SCHEMA_MAP["NIA"]="$schema_nia"
        SCHEMA_MAP["CFA"]="$schema_cfa"
        if [ $DEBUG = 1 ]; then
            echo "detected schema IDs:"
            echo "NIA: ${SCHEMA_MAP["NIA"]}"
            echo "CFA: ${SCHEMA_MAP["CFA"]}"
            echo
            echo "schemata:"
            _trace "${RGB[@]}" -d "data${wallet_id}" schemata -w "$wallet"
            echo "interfaces:"
            _trace "${RGB[@]}" -d "data${wallet_id}" interfaces -w "$wallet"
        fi
    fi
}

transfer_asset() {
    transfer_create "$@"    # parameter pass-through
    transfer_complete       # uses global variables set by transfer_create
    # unset global variables set by transfer operations
    unset BALANCE CONSIGNMENT PSBT XFER_CONTRACT_NAME
    unset BLNC_RCPT BLNC_SEND RCPT_WLT SEND_WLT
}

transfer_create() {
    ## params
    local wallets="$1"          # sender>receiver wallet names
    local balances_start="$2"   # expected sender/recipient starting balances
    local send_amt="$3"         # amount to be transferred
    local balances_final="$4"   # expected sender/recipient final balances
    local witness="$5"          # 1 for witness txid, blinded UTXO otherwise
    local reuse_invoice="$6"    # 1 to re-use the previous invoice
    XFER_CONTRACT_NAME="$7"     # contract name
    local method="$8"           # closing method

    ## data variables
    local contract_id rcpt_data rcpt_id send_data send_id
    local blnc_send blnc_rcpt
    local schema iface
    SEND_WLT=$(echo "$wallets" |cut -d/ -f1)
    RCPT_WLT=$(echo "$wallets" |cut -d/ -f2)
    send_id=${WLT_ID_MAP[$SEND_WLT]}
    rcpt_id=${WLT_ID_MAP[$RCPT_WLT]}
    contract_id=${CONTRACT_ID_MAP[$XFER_CONTRACT_NAME]}
    send_data="data${send_id}"
    rcpt_data="data${rcpt_id}"
    blnc_send=$(echo "$balances_start" |cut -d/ -f1)
    blnc_rcpt=$(echo "$balances_start" |cut -d/ -f2)
    schema=${CONTRACT_SCHEMA_MAP[$XFER_CONTRACT_NAME]}
    iface=${IFACE_MAP[$schema]}

    ## starting situation
    _tit "sending $send_amt $XFER_CONTRACT_NAME from $SEND_WLT to $RCPT_WLT ($method)"
    _check_method "$method"
    [ $DEBUG = 1 ] && _log "sender unspents before transfer" && _list_unspent "$SEND_WLT"
    [ $DEBUG = 1 ] && _log "recipient unspents before transfer" && _list_unspent "$RCPT_WLT"
    _subtit "initial balances"
    check_balance "$SEND_WLT" "$blnc_send" "$XFER_CONTRACT_NAME"
    check_balance "$RCPT_WLT" "$blnc_rcpt" "$XFER_CONTRACT_NAME"
    BLNC_SEND=$((blnc_send-send_amt))
    BLNC_RCPT=$((blnc_rcpt+send_amt))
    blnc_send=$(echo "$balances_final" |cut -d/ -f1)
    blnc_rcpt=$(echo "$balances_final" |cut -d/ -f2)
    [ "$BLNC_SEND" = "$blnc_send" ] || \
        _die "expected final sender balance $BLNC_SEND differs from the provided $blnc_send (transfer $TRANSFER_NUM)"
    [ "$BLNC_RCPT" = "$blnc_rcpt" ] || \
        _die "expected final recipient balance $BLNC_RCPT differs from the provided $blnc_rcpt (transfer $TRANSFER_NUM)"

    ## generate invoice
    _subtit "(recipient) preparing invoice"
    local address_mode
    if [ "$reuse_invoice" != 1 ]; then
        if [ "$witness" = 1 ]; then
            address_mode="-a"
        else
            _gen_utxo "$RCPT_WLT"
            address_mode=""
        fi
        # not quoting $address_mode so it doesn't get passed as "" if empty
        # shellcheck disable=2086
        INVOICE="$(_trace "${RGB[@]}" -d "$rcpt_data" invoice \
            $address_mode \
            -w "$RCPT_WLT" "$contract_id" $iface "$send_amt" 2>/dev/null)"
    fi
    _log "invoice: $INVOICE"

    ## RGB tansfer
    _subtit "(sender) preparing RGB transfer"
    CONSIGNMENT="consignment_${TRANSFER_NUM}.rgb"
    PSBT=tx_${TRANSFER_NUM}.psbt
    local sats=(--sats 2000)
    [ -n "$SATS" ] && sats=(--sats "$SATS")
    _trace "${RGB[@]}" -d "$send_data" transfer -w "$SEND_WLT" \
        --method "$method" "${sats[@]}" \
        "$INVOICE" $send_data/$CONSIGNMENT $send_data/$PSBT
    if ! ls "$send_data/$CONSIGNMENT" >/dev/null 2>&1; then
        _die "could not locate consignment file: $send_data/$CONSIGNMENT"
    fi

    ## extract PSBT data
    local decoded_psbt
    decoded_psbt="$(_trace "${BCLI[@]}" decodepsbt "$(base64 -w0 $send_data/$PSBT)")"
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
    _trace "${RGB[@]}" -d "$send_data" inspect \
        "$send_data/$CONSIGNMENT" "$CONSIGNMENT.yaml"
    _log "consignment exported to file: $CONSIGNMENT.yaml"
}

transfer_complete() {
    ## recipient: validate transfer
    _subtit "(recipient) validating consignment"
    local rcpt_data rcpt_id send_data send_id vldt
    send_id=${WLT_ID_MAP[$SEND_WLT]}
    rcpt_id=${WLT_ID_MAP[$RCPT_WLT]}
    send_data="data${send_id}"
    rcpt_data="data${rcpt_id}"
    # note: all output to stderr
    vldt="$(_trace "${RGB[@]}" -d "$rcpt_data" validate \
        "$rcpt_data/$CONSIGNMENT" 2>&1)"
    [ $DEBUG = 1 ] && _log "$vldt"
    if ! echo "$vldt" | grep -q 'The provided consignment is valid'; then
        _die "validation failed (transfer $TRANSFER_NUM)"
    fi

    ## sign + finalize + broadcast PSBT
    _subtit "(sender) signing PSBT"
    local signing tx txid
    signing="$(_trace "${BTCHOT[@]}" sign -p '' \
        $send_data/$PSBT "$WALLET_PATH/$SEND_WLT.derive")"
    if ! echo "$signing" | grep -q 'Done [1-9] signatures'; then
        _die "signing failed (transfer $TRANSFER_NUM)"
    fi
    _subtit "(sender) finalizing PSBT"
    tx="$(_trace "${BTCCOLD[@]}" finalize $send_data/$PSBT)"
    _subtit "(sender) broadcasting tx"
    txid="$(_trace "${BCLI[@]}" sendrawtransaction "$tx")"
    _log "$txid"

    ## mine and sync wallets
    _subtit "confirming transaction"
    _gen_blocks 1
    _subtit "syncing wallets"
    _sync_wallet "$SEND_WLT"
    _sync_wallet "$RCPT_WLT"

    ## accept transfer
    local accept
    _subtit "(recipient) accepting transfer"
    # note: all output to stderr
    accept="$(_trace "${RGB[@]}" -d "data${rcpt_id}" accept -w "$RCPT_WLT" \
        $rcpt_data/$CONSIGNMENT 2>&1)"
    [ $DEBUG = 1 ] && _log "$accept"
    if ! echo "$accept" | grep -q 'Transfer accepted into the stash'; then
        _die "accept failed (transfer $TRANSFER_NUM)"
    fi

    ## ending situation
    [ $DEBUG = 1 ] && _log "sender unspents after transfer" && _list_unspent "$SEND_WLT"
    [ $DEBUG = 1 ] && _log "recipient unspents after transfer" && _list_unspent "$RCPT_WLT"
    [ $DEBUG = 1 ] && _log "sender state after transfer" && _show_state "$SEND_WLT" "$XFER_CONTRACT_NAME"
    [ $DEBUG = 1 ] && _log "recipient state after transfer" && _show_state "$RCPT_WLT" "$XFER_CONTRACT_NAME"
    _subtit "final balances"
    check_balance "$SEND_WLT" "$BLNC_SEND" "$XFER_CONTRACT_NAME"
    check_balance "$RCPT_WLT" "$BLNC_RCPT" "$XFER_CONTRACT_NAME"

    # increment transfer number
    ((TRANSFER_NUM+=1))
}

# cmdline arguments
help() {
    echo "$NAME [-h|--help] [-t|--tapret] [-v|--verbose]"
    echo ""
    echo "options:"
    echo "    -h --help      show this help message"
    echo "    -l --list      list the available scenarios"
    echo "    -s --scenario  run the specified scenario (default: 0)"
    echo "    -v --verbose   enable verbose output"
    echo "       --esplora   use esplora as indexer (default: electrum)"
}

while [ -n "$1" ]; do
    case $1 in
        -h|--help)
            help
            exit 0
            ;;
        -l|--list)
            echo -n "available scenarios: "
            grep '^scenario_[0-9]\+\(\)' "$0" \
                | sed -e 's/^scenario_//' -e 's/() {.*//' \
                | xargs echo
            exit 0
            ;;
        -s|--scenario)
            SCENARIO_NUM="$2"
            SCENARIO="scenario_$SCENARIO_NUM"
            shift
            ;;
        -v|--verbose)
            DEBUG=1
            ;;
        --esplora)
            INDEXER_CLI="--esplora"
            INDEXER_ENDPOINT=$ESPLORA_ENDPOINT
            PROFILE="esplora"
            ;;
        *)
            help
            _die "unsupported argument \"$1\""
            ;;
    esac
    shift
done
[ -z "$SCENARIO" ] && SCENARIO="scenario_0"  # default
# check if the selected scenario is available
if ! grep -q "${SCENARIO}()" "$0"; then
    _die "scenario $SCENARIO_NUM not available"
fi


# initial setup
_tit "setting up"
check_tools
check_schemata_version
set_aliases
trap cleanup EXIT

# install crates
install_rust_crate "descriptor-wallet" "$DESCRIPTOR_WALLET_VER" "$DESCRIPTOR_WALLET_FEATURES" "--debug"
install_rust_crate "rgb-wallet" "$RGB_WALLET_VER" "$RGB_WALLET_FEATURES"

# complete setup
start_services
prepare_btc_wallet


## scenario definitions

# full round of opret transfers
scenario_0() {  # default
    local method="opret1st"
    # wallets
    prepare_rgb_wallet wallet_1 $method
    prepare_rgb_wallet wallet_2 $method
    prepare_rgb_wallet wallet_3 $method
    # asset issuance
    get_issue_utxo wallet_1
    issue_asset wallet_1 usdt NIA $method
    issue_asset wallet_1 collectible CFA $method
    # initial balance checks
    check_balance wallet_1 2000 usdt
    check_balance wallet_1 2000 collectible
    # transfers
    transfer_create wallet_1/wallet_2 2000/0     100 1900/100  0 0 usdt $method         # aborted
    transfer_asset  wallet_1/wallet_2 2000/0     100 1900/100  0 1 usdt $method         # retried
    transfer_asset  wallet_1/wallet_2 2000/0     200 1800/200  0 0 collectible $method  # CFA
    transfer_asset  wallet_1/wallet_2 1900/100   200 1700/300  1 0 usdt $method         # change, witness
    transfer_asset  wallet_2/wallet_3  300/0     150  150/150  0 0 usdt $method         # spend both received allocations
    transfer_asset  wallet_2/wallet_3  200/0     100  100/100  0 0 collectible $method  # CFA, spend received allocations
    transfer_asset  wallet_3/wallet_1  150/1700  100   50/1800 1 0 usdt $method         # close loop, witness
    transfer_asset  wallet_3/wallet_1  100/1800   50   50/1850 1 0 collectible $method  # CFA, close loop, witness
    transfer_asset  wallet_1/wallet_2 1800/150    50 1750/200  0 0 usdt $method         # spend received back
    transfer_asset  wallet_1/wallet_2 1850/100    25 1825/125  0 0 collectible $method  # CFA, spend received back
    # final balance checks
    _tit "checking final balances"
    check_balance wallet_1 1750 usdt
    check_balance wallet_2  200 usdt
    check_balance wallet_3   50 usdt
    check_balance wallet_1 1825 collectible
    check_balance wallet_2  125 collectible
    check_balance wallet_3   50 collectible
}

# full round of tapret transfers
scenario_1() {
    local method="tapret1st"
    # wallets
    prepare_rgb_wallet wallet_1 $method
    prepare_rgb_wallet wallet_2 $method
    prepare_rgb_wallet wallet_3 $method
    # asset issuance
    get_issue_utxo wallet_1
    issue_asset wallet_1 usdt NIA $method
    issue_asset wallet_1 collectible CFA $method
    # initial balance checks
    check_balance wallet_1 2000 usdt
    check_balance wallet_1 2000 collectible
    # transfers
    transfer_create wallet_1/wallet_2 2000/0     100 1900/100  0 0 usdt $method         # aborted
    transfer_asset  wallet_1/wallet_2 2000/0     100 1900/100  0 1 usdt $method         # retried
    transfer_asset  wallet_1/wallet_2 2000/0     200 1800/200  0 0 collectible $method  # CFA
    transfer_asset  wallet_1/wallet_2 1900/100   200 1700/300  1 0 usdt $method         # change, witness
    transfer_asset  wallet_2/wallet_3  300/0     150  150/150  0 0 usdt $method         # spend both received allocations
    transfer_asset  wallet_2/wallet_3  200/0     100  100/100  0 0 collectible $method  # CFA, spend received allocations
    transfer_asset  wallet_3/wallet_1  150/1700  100   50/1800 1 0 usdt $method         # close loop, witness
    transfer_asset  wallet_3/wallet_1  100/1800   50   50/1850 1 0 collectible $method  # CFA, close loop, witness
    transfer_asset  wallet_1/wallet_2 1800/150    50 1750/200  0 0 usdt $method         # spend received back
    transfer_asset  wallet_1/wallet_2 1850/100    25 1825/125  0 0 collectible $method  # CFA, spend received back
    # final balance checks
    _tit "checking final balances"
    check_balance wallet_1 1750 usdt
    check_balance wallet_2  200 usdt
    check_balance wallet_3   50 usdt
    check_balance wallet_1 1825 collectible
    check_balance wallet_2  125 collectible
    check_balance wallet_3   50 collectible
}

# run selected scenario
$SCENARIO

_tit "sandbox run finished"
