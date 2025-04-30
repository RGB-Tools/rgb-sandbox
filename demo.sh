#!/usr/bin/env bash

# variables
CONTRACT_DIR="contracts"
DEBUG=0
RECOMPILE=0
NAME=$(basename "$0")
NETWORK="regtest"
TRACE_OUT="trace.out"
TRANSFER_NUM=0
WALLET_NUM=0
WALLET_PATH="wallets"
WALLETS=()
SATS=800 # TODO: This is required only for witness-out transfers. We need to account for it
FEE=260
export SEED_PASSWORD="seed test password"

# crate variables
BP_WALLET_FEATURES="--features=cli,hot"
BP_WALLET_VER="0.12.0-beta.5"
RGB_WALLET_FEATURES=""
RGB_WALLET_VER="0.12.0-beta.5"

# RGB wallet types
WALLET_TYPES=("wpkh" "tapret-key-only")

# indexer variables
ELECTRUM_PORT=50001
ELECTRUM_ENDPOINT="localhost:$ELECTRUM_PORT"
ESPLORA_ENDPOINT="http://localhost:8094/regtest/api"
INDEXER_OPT="--electrum"
INDEXER_ENDPOINT=$ELECTRUM_ENDPOINT
INDEXER_CLI="$INDEXER_OPT=$INDEXER_ENDPOINT"
PROFILE="electrum"

# shell colors
C1='\033[0;32m' # green
C2='\033[0;33m' # orange
C3='\033[0;34m' # blue
C4='\033[0;31m' # red
NC='\033[0m'    # No Color

# maps
declare -A CONTRACT_ID_MAP
declare -A CONTRACT_NAME_MAP
declare -A DESC_MAP
declare -A WLT_ID_MAP

CONTRACT_NAME_MAP["usdt"]=USDT
CONTRACT_NAME_MAP["collectible"]=OtherToken

# copy stderr to fd 4
exec 4>&2

# internal utility functions
_die() {
    # always output to stderr (copied to fd 4)
    printf "\n${C4}ERROR: %s${NC}\n" "$@" >&4
    exit 1
}

_log() {
    printf "${C3}%s${NC}\n" "$@"
}

_subtit() {
    printf "${C2}-- %s${NC}\n" "$@"
}

_tit() {
    S="$*"              # string
    B=50                # buffer
    P=$(((B-${#S})/2))  # padding
    [ $P -lt 0 ] && P=0
    printf "\n${C1}==== %${P}s%s%${P}s ====${NC}\n" "" "$S" ""
}

_trace() {
    # notes:
    # - calls redirecting stderr to /dev/null will drop xtrace output
    # - don't use inside subshells like () $() or pipes, lest _die not working
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
_check_wallet_type() {
    local match="$1"
    for m in "${WALLET_TYPES[@]}"; do
        [ "$m" = "$match" ] && return
    done
    _die "unknown $match wallet type"
}

_gen_addr_rgb() {
    local wallet="$1"
    _subtit "generating new funding address for $wallet"
    local wallet_id=${WLT_ID_MAP[$wallet]}
    _trace "${RGB[@]}" -d "data${wallet_id}" fund "$wallet" >$TRACE_OUT 2>/dev/null
    ADDR="$(awk '/bcrt/ {print $NF}' $TRACE_OUT)"
    _log "generated funding address: $ADDR"
}

_wait_indexers_sync() {
    echo -n "Waiting for the indexer to sync ... "
    local block_count
    block_count=$("${BCLI[@]}" getblockcount)
    if [ "$PROFILE" = "electrum" ]; then
        local electrum_json electrum_res
        # shellcheck disable=2089
        electrum_json="{\"jsonrpc\": \"2.0\", \"wallet_type\": \"blockchain.block.header\", \"params\": [$block_count], \"id\": 0}"
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
    _subtit "mining $count block(s)"
    _trace "${BCLI[@]}" -rpcwallet=miner -generate "$count" >/dev/null
    _wait_indexers_sync
}

_sync_wallet() {
    local wallet="$1"
    _subtit "syncing $wallet"
    local wallet_id=${WLT_ID_MAP[$wallet]}
    _trace "${RGB[@]}" -d "data${wallet_id}" sync "$INDEXER_CLI" "$wallet"
}

_get_utxo() {
    local wallet="$1"
    local txid="$2"
    _subtit "extracting vout for $wallet (txid: $txid)"
    local wallet_id=${WLT_ID_MAP[$wallet]}
    _trace "${RGB[@]}" -d "data${wallet_id}" seals -w "$wallet" >$TRACE_OUT 2>/dev/null
    vout=$(awk "/$txid/ {print \$NF}" $TRACE_OUT | cut -d: -f2)
    [ -n "$vout" ] || _die "couldn't retrieve vout for txid $txid"
    _log "txid $txid, vout: $vout"
}

_gen_utxo() {
    local wallet="$1"
    _gen_addr_rgb "$wallet"
    _subtit "sending funds to $wallet"
    _trace "${BCLI[@]}" -rpcwallet=miner sendtoaddress "$ADDR" 1 >$TRACE_OUT
    txid="$(cat $TRACE_OUT)"
    _gen_blocks 1
    _sync_wallet "$wallet"
    _get_utxo "$wallet" "$txid"
}

_list_unspent() {
    local wallet="$1"
    local wallet_id=${WLT_ID_MAP[$wallet]}
    _trace "${RGB[@]}" -d "data${wallet_id}" seals -w "$wallet"
}

_show_state() {
    local wallet="$1"
    local contract_name="$2"
    local sync="$3"
    local contract_id wallet_id
    wallet_id=${WLT_ID_MAP[$wallet]}
    contract_id=${CONTRACT_ID_MAP[$contract_name]}
    if [ "$sync" = 1 ]; then
        sync=("--sync")
    else
        sync=()
    fi
    _trace "${RGB[@]}" -d "data${wallet_id}" \
        state -w "$wallet" -goa "${sync[@]}" "$contract_id"
}


# helper functions
check_tools() {
    _subtit "checking required tools"
    local required_tools="awk base64 cargo cut docker grep head jq netcat sha256sum tr"
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
    if [ -z "$SKIP_INIT" ] && [ -z "$SKIP_STOP" ]; then
        _subtit "stopping services and cleaning data directories"
        stop_services
        rm -rf data{0,1,2,core,index}
    else
        _subtit "skipping services stop"
    fi
}

install_rust_crate() {
    local crate="$1"
    local version="$2"
    local features opts
    local debug=""
    local force=""
    if [ -n "$3" ]; then
        read -r -a features <<< "$3"
    fi
    if [ -n "$4" ]; then
        read -r -a opts <<< "$4"
    fi
    if [ $DEBUG = 1 ]; then
      debug=("--profile" "dev")
    else
      debug=("--profile" "test")
    fi
    if [ $RECOMPILE = 1 ]; then
      force="--force"
    fi
    _subtit "installing $crate to ./$crate"
    cargo install "$crate" --version "$version" --locked "${debug[@]}" $force \
        --root "./$crate" "${features[@]}" "${opts[@]}" \
        || _die "error installing $crate"
}

# shellcheck disable=2034
set_aliases() {
    _subtit "setting command aliases"
    BITCOIND_CLI=("docker" "compose" "exec" "-T" "-u" "blits" "bitcoind" "bitcoin-cli" "-regtest")
    BPHOT=("bp-wallet/bin/bp-hot")
    BP=("bp-wallet/bin/bp")
    ESPLORA_CLI=("docker" "compose" "exec" "-T" "esplora" "cli")
    RGB=("rgb-wallet/bin/rgb" "-n" "$NETWORK") # TODO: We had to get rid of "$INDEXER_CLI")
    if [ "$PROFILE" = "electrum" ]; then
        BCLI=("${BITCOIND_CLI[@]}")
    else
        BCLI=("${ESPLORA_CLI[@]}")
    fi
}

stop_services() {
    _subtit "stopping services"
    # cleanly stop esplora
    if $COMPOSE ps |grep -q esplora; then
        for SRV in socat electrs; do
            $COMPOSE exec esplora bash -c "sv -w 60 force-stop /etc/service/$SRV"
        done

    fi
    # bring all services down
    docker compose --profile '*' down --remove-orphans -v
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
    stop_services
    _subtit "checking bound ports"
    # see docker-compose.yml for the exposed ports
    [ "$PROFILE" = "electrum" ] && EXPOSED_PORTS=(50001)
    [ "$PROFILE" = "esplora" ] && EXPOSED_PORTS=(8094)
    for port in "${EXPOSED_PORTS[@]}"; do
        if netcat -z localhost "$port"; then
            _die "port $port is already bound, services can't be started"
        fi
    done
    _subtit "cleaning service data dirs"
    for d in datacore dataelectrs; do
        if [ -d "$d" ]; then
            rm -r $d
            mkdir -p $d
        fi
    done
    if [ -d "dataesplora" ]; then
        docker compose run --rm esplora bash -c "rm -rf /data/.bitcoin.conf /data/*"
    fi
    _subtit "starting services"
    docker compose --profile $PROFILE up -d || _die "could not start services"
    echo -n "waiting for services to have started..."
    if [ "$PROFILE" = "electrum" ]; then
        # bitcoind
        until docker compose logs bitcoind |grep -q 'Bound to'; do
            sleep 1
        done
    fi
    if [ "$PROFILE" = "esplora" ]; then
        # esplora
        until docker compose logs esplora |grep -q 'Bootstrapped 100%'; do
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
    local subtit="${4:-0}"
    if [ "$subtit" = 0 ]; then
        _tit "checking $contract_name balance for $wallet"
    elif [ "$subtit" = 1 ]; then
        _subtit "checking $contract_name balance for $wallet"
    fi
    local contract_id allocations amount wallet_id
    wallet_id=${WLT_ID_MAP[$wallet]}
    contract_id=${CONTRACT_ID_MAP[$contract_name]}
    mapfile -t outpoints < <(_list_unspent "$wallet" | awk '/:[0-9]+$/ {print $NF}')
    BALANCE=0
    if [ "${#outpoints[@]}" -gt 0 ]; then
        _log "outpoints:"
        for outpoint in "${outpoints[@]}"; do
            echo " - $outpoint"
        done
        mapfile -t allocations < <("${RGB[@]}" -d "data${wallet_id}" \
            state -w "$wallet" -o "$contract_id" 2>/dev/null \
            | grep '^[[:space:]]' | awk '{print $3" "$5}')
        _log "allocations:"
        for allocation in "${allocations[@]}"; do
            echo " - $allocation"
        done
        for utxo in "${outpoints[@]}"; do
            for allocation in "${allocations[@]}"; do
                amount=$(echo "$allocation" \
                    | awk "/$utxo/ {print \$1}")
                BALANCE=$((BALANCE + amount))
            done
        done
    fi
    if [ "$BALANCE" != "$expected" ]; then
        _die "$(printf '%s' \
            "$wallet balance $BALANCE for $contract_id ($contract_name) " \
            "differs from the expected $expected (transfer $TRANSFER_NUM)")"
    fi
    _log "$(printf '%s' \
        "balance $BALANCE for contract $contract_id " \
        "($contract_name) matches the expected one")"
}

export_contract() {
    local contract_name="$1"
    local wallet="$2"
    _tit "exporting $contract_name contract from $wallet"
    local contract_file contract_id wallet_id
    contract_id=${CONTRACT_ID_MAP[$contract_name]}
    wallet_id=${WLT_ID_MAP[$wallet]}
    rm -rf ${CONTRACT_DIR}/"${CONTRACT_NAME_MAP[$contract_name]}".*.contract
    cp -r data"${wallet_id}"/bitcoin.testnet/"${CONTRACT_NAME_MAP[$contract_name]}".*.contract "${CONTRACT_DIR}/"
    #_trace "${RGB[@]}" -d "data${wallet_id}" export -w "$wallet" "$contract_id" "$contract_file"
}

get_issue_utxo() {
    local wallet="$1"
    _tit "creating issuance UTXO for wallet $wallet"
    [ $DEBUG = 1 ] && _subtit "unspents before issuance" && _list_unspent "$wallet"
    _gen_utxo "$wallet"
    TXID_ISSUE=$txid
    VOUT_ISSUE=$vout
}

import_contract() {
    local contract_name="$1"
    local wallet="$2"
    _tit "importing $contract_name contract into $wallet"
    local wallet_id
    wallet_id=${WLT_ID_MAP[$wallet]}
    rm -rf data"${wallet_id}"/bitcoin.testnet/"${CONTRACT_NAME_MAP[$contract_name]}".*.contract
    cp -r $CONTRACT_DIR/"${CONTRACT_NAME_MAP[$contract_name]}".*.contract "data${wallet_id}/bitcoin.testnet/"
    # note: all output to stderr
    #_trace "${RGB[@]}" -d "data${wallet_id}" import -w "$wallet" "$contract_file" 2>&1 | grep Contract
}

# requires get_issue_utxo to have been called first
issue_contract() {
    local wallet="$1"
    local contract_name="$2"
    _tit "issuing contract $contract_name"
    local contract_base contract_tmpl contract_yaml
    local contract_id issuance wallet_id
    wallet_id=${WLT_ID_MAP[$wallet]}
    contract_base=${CONTRACT_DIR}/${contract_name}
    contract_tmpl=${contract_base}.yaml.template
    contract_yaml=${contract_base}.yaml
    sed \
        -e "s/issued_supply/2000/" \
        -e "s/txid/$TXID_ISSUE/" \
        -e "s/vout/$VOUT_ISSUE/" \
        "$contract_tmpl" > "$contract_yaml"
    _subtit "issuing"
    _trace "${RGB[@]}" -d "data${wallet_id}" import issuers/*
    _trace "${RGB[@]}" -d "data${wallet_id}" issue -w "$wallet" "$contract_yaml" \
        >$TRACE_OUT 2>&1
    issuance="$(cat $TRACE_OUT)"
    echo "$issuance"
    contract_id="$(echo "$issuance" | grep '^A new contract' | cut -d' ' -f7)"
    CONTRACT_ID_MAP[$contract_name]=$contract_id
    _subtit "contract state after issuance"
    _trace "${RGB[@]}" -d "data${wallet_id}" state -go -w "$wallet"
    [ $DEBUG = 1 ] && _subtit "unspents after issuance" && _list_unspent "$wallet"
}

prepare_btc_wallet() {
    _subtit "preparing bitcoind wallet"
    _trace "${BCLI[@]}" createwallet miner
    _gen_blocks 103
}

prepare_rgb_wallet() {
    local wallet="$1"
    local wallet_type="$2"
    _tit "preparing $wallet_type wallet $wallet"
    # wallet type-dependent variables
    _check_wallet_type "$wallet_type"
    local der_scheme
    if [ "$wallet_type" = wpkh ]; then
        der_scheme="bip84"
    else
        der_scheme="bip86"
    fi
    # BTC setup
    mkdir -p $WALLET_PATH
    rm -rf "$WALLET_PATH/$wallet.{derive,seed}"
    _subtit "creating bitcoin wallet $wallet"
    _trace "${BPHOT[@]}" seed "$WALLET_PATH/$wallet.seed"
    _trace "${BPHOT[@]}" derive -N -s $der_scheme \
        "$WALLET_PATH/$wallet.seed" "$WALLET_PATH/$wallet.derive" >$TRACE_OUT
    account="$(cat $TRACE_OUT | awk '/Account/ {print $NF}')"
    DESC_MAP[$wallet]="$account/<0;1>/*"
    [ $DEBUG = 1 ] && echo "descriptor: ${DESC_MAP[$wallet]}"
    WALLETS+=("$wallet")
    WLT_ID_MAP[$wallet]=$WALLET_NUM
    ((WALLET_NUM+=1))
    # RGB setup
    _subtit "creating RGB wallet $wallet"
    wallet_id=${WLT_ID_MAP[$wallet]}
    _trace "${RGB[@]}" -d "data${wallet_id}" init -q
    _trace "${RGB[@]}" -d "data${wallet_id}" create --"$wallet_type" "$wallet" "${DESC_MAP[$wallet]}"
}

sign_and_broadcast() {
    local send_data="$1"
    local wallet="$2"
    _subtit "(sender) signing PSBT"
    _trace "${BPHOT[@]}" sign -N "$send_data/$PSBT" \
        "$WALLET_PATH/$SEND_WLT.derive" >$TRACE_OUT 2>&1
    if ! grep -q 'Done [1-9] signatures' $TRACE_OUT; then
        _die "signing failed (transfer $TRANSFER_NUM)"
    fi
    _subtit "(sender) finalizing and broadcasting the PSBT"
    local broadcast="-b"
    [ "$NO_BROADCAST" = 1 ] && broadcast=""
    _trace "${RGB[@]}" finalize $broadcast "$INDEXER_CLI" -n $NETWORK -d "$send_data" \
        -w "$wallet" "$send_data/$PSBT" "$send_data/${PSBT%psbt}tx"
}

transfer_assets() {
    transfer_create "$@"    # parameter pass-through
    transfer_complete       # uses global variables set by transfer_create
    # unset global variables set by transfer operations
    unset BALANCE CONSIGNMENT PSBT XFER_CONTRACT_NAME
    unset BLNC_RCPT BLNC_SEND RCPT_WLT SEND_WLT
}

transfer_aborted() {
    transfer_create "$@"    # parameter pass-through
    _subtit "(sender) aborting transfer"
    _sync_wallet "$SEND_WLT"
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

    ## data variables
    local contract_id rcpt_data rcpt_id send_data send_id
    local blnc_send blnc_rcpt
    SEND_WLT=$(echo "$wallets" |cut -d/ -f1)
    RCPT_WLT=$(echo "$wallets" |cut -d/ -f2)
    send_id=${WLT_ID_MAP[$SEND_WLT]}
    rcpt_id=${WLT_ID_MAP[$RCPT_WLT]}
    contract_id=${CONTRACT_ID_MAP[$XFER_CONTRACT_NAME]}
    send_data="data${send_id}"
    rcpt_data="data${rcpt_id}"
    blnc_send=$(echo "$balances_start" |cut -d/ -f1)
    blnc_rcpt=$(echo "$balances_start" |cut -d/ -f2)

    ## starting situation
    _tit "sending $send_amt $XFER_CONTRACT_NAME from $SEND_WLT to $RCPT_WLT"
    [ $DEBUG = 1 ] && _subtit "sender unspents before transfer" && _list_unspent "$SEND_WLT"
    [ $DEBUG = 1 ] && _subtit "recipient unspents before transfer" && _list_unspent "$RCPT_WLT"
    [ $DEBUG = 1 ] && _subtit "sender state before transfer" && _show_state "$SEND_WLT" "$XFER_CONTRACT_NAME" 0
    [ $DEBUG = 1 ] && _subtit "recipient state before transfer" && _show_state "$RCPT_WLT" "$XFER_CONTRACT_NAME" 0
    _subtit "initial balances"
    [ "$SKIP_INITIAL_SEND_CHECK_BALANCE" != 1 ] && check_balance "$SEND_WLT" "$blnc_send" "$XFER_CONTRACT_NAME" 1
    [ "$SKIP_INITIAL_RCPT_CHECK_BALANCE" != 1 ] && check_balance "$RCPT_WLT" "$blnc_rcpt" "$XFER_CONTRACT_NAME" 1
    BLNC_SEND=$((blnc_send-send_amt))
    BLNC_RCPT=$((blnc_rcpt+send_amt))
    [ -n "$CUSTOM_BLNC_RCPT" ] && BLNC_RCPT=$CUSTOM_BLNC_RCPT
    blnc_send=$(echo "$balances_final" |cut -d/ -f1)
    blnc_rcpt=$(echo "$balances_final" |cut -d/ -f2)
    [ "$BLNC_SEND" = "$blnc_send" ] || \
        _die "expected final sender balance $BLNC_SEND differs from the provided $blnc_send (transfer $TRANSFER_NUM)"
    [ "$BLNC_RCPT" = "$blnc_rcpt" ] || \
        _die "expected final recipient balance $BLNC_RCPT differs from the provided $blnc_rcpt (transfer $TRANSFER_NUM)"

    ## generate invoice
    local address_mode
    if [ "$reuse_invoice" != 1 ]; then
        _subtit "(recipient) preparing invoice"
        if [ "$witness" = 1 ]; then
            address_mode="--wout"
        else
            [ "$NO_GEN_UTXO" != 1 ] && _gen_utxo "$RCPT_WLT"
            address_mode=""
        fi
        _trace "${RGB[@]}" -d "$rcpt_data" invoice $address_mode \
            -w "$RCPT_WLT" "$contract_id" "$send_amt" >$TRACE_OUT
        INVOICE="$(cat $TRACE_OUT)"
    else
        _subtit "(recipient) re-using invoice"
    fi
    _log "invoice: $INVOICE"

    ## RGB transfer
    _subtit "(sender) preparing RGB transfer"
    CONSIGNMENT="consignment_${TRANSFER_NUM}.rgb"
    PSBT=tx_${TRANSFER_NUM}.psbt
    local sats=()
    local fee=()
    [ -n "$SATS" ] && sats=(--sats "$SATS")
    [ -n "$FEE" ] && fee=(--fee "$FEE")
    _trace "${RGB[@]}" -d "$send_data" pay -w "$SEND_WLT" \
        "${sats[@]}" "${fee[@]}" --force \
        "$INVOICE" "$send_data/$CONSIGNMENT" "$send_data/$PSBT"
    if ! ls "$send_data/$CONSIGNMENT" >/dev/null 2>&1; then
        _die "could not locate consignment file: $send_data/$CONSIGNMENT"
    fi

    ## extract PSBT data
    local decoded_psbt
    _trace "${BCLI[@]}" decodepsbt "$(base64_file_nowrap "$send_data/$PSBT")" >$TRACE_OUT
    decoded_psbt="$(cat $TRACE_OUT)"
    if [ $DEBUG = 1 ]; then
        _subtit "decoded PSBT with RGB transfer data"
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
    # TODO: Re-enable with `rgbx` tool
    # _trace "${RGB[@]}" -d "$send_data" inspect \
    #     "$send_data/$CONSIGNMENT" "$CONSIGNMENT.yaml"
    # _log "consignment exported to file: $CONSIGNMENT.yaml"

    [ $DEBUG = 1 ] && _subtit "tentative sender state" && _show_state "$SEND_WLT" "$XFER_CONTRACT_NAME" 0
}

transfer_complete() {
    # TODO: We skip validation for now and process directly to `accept`, since v0.12 doesn't support
    #       (yet?) separate validation procedure
    ## recipient: validate transfer
    _subtit "(recipient) validating & accepting consignment"
    local rcpt_data rcpt_id send_data send_id vldt
    send_id=${WLT_ID_MAP[$SEND_WLT]}
    rcpt_id=${WLT_ID_MAP[$RCPT_WLT]}
    send_data="data${send_id}"
    rcpt_data="data${rcpt_id}"
    # note: all output to stderr
    _trace "${RGB[@]}" -d "data${rcpt_id}" accept -w "$RCPT_WLT" \
        "$rcpt_data/$CONSIGNMENT" >$TRACE_OUT 2>&1
    vldt="$(cat $TRACE_OUT)"
    [ $DEBUG = 1 ] && echo "$vldt"
    if echo "$vldt" | grep -q 'invalid'; then
        _die "validation failed (transfer $TRANSFER_NUM)"
    fi

    ## sign + finalize + broadcast PSBT
    sign_and_broadcast "$send_data" "$SEND_WLT"

    ## mine and sync wallets
    _subtit "confirming transaction"
    [ "$NO_MINE" = 1 ] || _gen_blocks 1
    _subtit "syncing wallets"
    _sync_wallet "$SEND_WLT"
    _sync_wallet "$RCPT_WLT"

    ## ending situation
    [ $DEBUG = 1 ] && _subtit "sender state after transfer" && _show_state "$SEND_WLT" "$XFER_CONTRACT_NAME" 0
    [ $DEBUG = 1 ] && _subtit "recipient state after transfer" && _show_state "$RCPT_WLT" "$XFER_CONTRACT_NAME" 0
    _subtit "final balances"
    check_balance "$RCPT_WLT" "$BLNC_RCPT" "$XFER_CONTRACT_NAME" 1
    check_balance "$SEND_WLT" "$BLNC_SEND" "$XFER_CONTRACT_NAME" 1

    # increment transfer number
    ((TRANSFER_NUM+=1))
}

base64_file_nowrap() {
    # This function encodes the specified file to base64 format without wrapping lines.
    # By default, Linux systems wrap base64 output every 76 columns. We use 'tr -d' to remove whitespaces.
    # Note that the option '-w0' for 'base64' doesn't work on Mac OS X due to different flags.
    # Arguments:
    #   $1: File path to be encoded
    cat "$1" | base64 | tr -d '\r\n'
}


# cmdline arguments
help() {
    echo "$NAME [-h|--help] [-l|--list] [-s|--scenario <scenario>] [-v|--verbose] [--esplora]"
    echo ""
    echo "options:"
    echo "    -h --help      show this help message"
    echo "    -l --list      list the available scenarios"
    echo "    -s --scenario  run the specified scenario (default: 0)"
    echo "    -v --verbose   enable verbose output"
    echo "    -r --recompile force complete recompile"
    echo "       --esplora   use esplora as indexer (default: electrum)"
    echo "    -u --skip-stop skip stopping docker containers after the completion"
    echo "       --stop      stop docker containers (if running)"
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
        --stop)
            stop_services
            exit 0
            ;;
        -v|--verbose)
            DEBUG=1
            export RUST_BACKTRACE=1
            ;;
        -r|--recompile)
            RECOMPILE=1
            ;;
        -u|--skip-stop)
            SKIP_STOP=1
            ;;
        --esplora)
            INDEXER_OPT="--esplora"
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
set_aliases
trap cleanup EXIT

# install crates
install_rust_crate "bp-wallet" "$BP_WALLET_VER" "$BP_WALLET_FEATURES" "--git https://github.com/BP-WG/bp-wallet --branch v0.12" # commit 0d439062
install_rust_crate "rgb-wallet" "$RGB_WALLET_VER" "$RGB_WALLET_FEATURES" "--git https://github.com/RGB-WG/rgb --branch v0.12" # commit 9ffff7fb

mkdir "$CONTRACT_DIR"

# complete setup
if [ -z "$SKIP_INIT" ]; then
    start_services
    prepare_btc_wallet
else
    _subtit "skipping services start"
fi


# scenario definitions

## full round of opret transfers
scenario_0() {  # default
    local wallet_type="wpkh"
    # wallets
    prepare_rgb_wallet wallet_0 $wallet_type
    prepare_rgb_wallet wallet_1 $wallet_type
    prepare_rgb_wallet wallet_2 $wallet_type
    # contract issuance
    get_issue_utxo wallet_0
    issue_contract wallet_0 usdt NIA
    issue_contract wallet_0 collectible CFA
    # export/import contracts
    export_contract usdt wallet_0
    import_contract usdt wallet_1
    import_contract usdt wallet_2
    export_contract collectible wallet_0
    import_contract collectible wallet_1
    import_contract collectible wallet_2
    # initial balance checks
    check_balance wallet_0 2000 usdt
    check_balance wallet_0 2000 collectible
    # transfers
    transfer_aborted wallet_0/wallet_1 2000/0     100 1900/100  0 0 usdt         # aborted
    transfer_assets wallet_0/wallet_1 2000/0     100 1900/100  0 1 usdt         # retried
    transfer_assets wallet_0/wallet_1 2000/0     200 1800/200  0 0 collectible  # CFA
    transfer_assets wallet_0/wallet_1 1900/100   200 1700/300  1 0 usdt         # change, witness
    transfer_assets wallet_1/wallet_2  300/0     250   50/250  0 0 usdt         # spend both received allocations
    transfer_assets wallet_1/wallet_2  200/0     100  100/100  0 0 collectible  # CFA, spend received allocations
    transfer_assets wallet_2/wallet_0  250/1700  100  150/1800 1 0 usdt         # close loop, witness
    transfer_assets wallet_2/wallet_0  100/1800   50   50/1850 1 0 collectible  # CFA, close loop, witness
    transfer_assets wallet_0/wallet_1 1800/50     50 1750/100  0 0 usdt         # spend received back
    transfer_assets wallet_0/wallet_1 1850/100    25 1825/125  0 0 collectible  # CFA, spend received back
    transfer_assets wallet_1/wallet_2  100/150   100    0/250  0 0 usdt         # spend all (no change)
    transfer_assets wallet_2/wallet_0  250/1750  250    0/2000 1 0 usdt         # spend all (witness)
    # final balance checks
    _tit "checking final balances"
    check_balance wallet_0 2000 usdt
    check_balance wallet_1    0 usdt
    check_balance wallet_2    0 usdt
    check_balance wallet_0 1825 collectible
    check_balance wallet_1  125 collectible
    check_balance wallet_2   50 collectible
}

## full round of tapret transfers
scenario_1() {
    local wallet_type="tapret-key-only"
    # wallets
    prepare_rgb_wallet wallet_0 $wallet_type
    prepare_rgb_wallet wallet_1 $wallet_type
    prepare_rgb_wallet wallet_2 $wallet_type
    # contract issuance
    get_issue_utxo wallet_0
    issue_contract wallet_0 usdt NIA
    issue_contract wallet_0 collectible CFA
    # export/import contracts
    export_contract usdt wallet_0
    import_contract usdt wallet_1
    import_contract usdt wallet_2
    export_contract collectible wallet_0
    import_contract collectible wallet_1
    import_contract collectible wallet_2
    # initial balance checks
    check_balance wallet_0 2000 usdt
    check_balance wallet_0 2000 collectible
    # transfers
    transfer_aborted wallet_0/wallet_1 2000/0     100 1900/100  0 0 usdt         # aborted
    transfer_assets wallet_0/wallet_1 2000/0     100 1900/100  0 1 usdt         # retried
    transfer_assets wallet_0/wallet_1 2000/0     200 1800/200  0 0 collectible  # CFA
    transfer_assets wallet_0/wallet_1 1900/100   200 1700/300  1 0 usdt         # change, witness
    transfer_assets wallet_1/wallet_2  300/0     250   50/250  0 0 usdt         # spend both received allocations
    transfer_assets wallet_1/wallet_2  200/0     100  100/100  0 0 collectible  # CFA, spend received allocations
    transfer_assets wallet_2/wallet_0  250/1700  100  150/1800 1 0 usdt         # close loop, witness
    transfer_assets wallet_2/wallet_0  100/1800   50   50/1850 1 0 collectible  # CFA, close loop, witness
    transfer_assets wallet_0/wallet_1 1800/50     50 1750/100  0 0 usdt         # spend received back
    transfer_assets wallet_0/wallet_1 1850/100    25 1825/125  0 0 collectible  # CFA, spend received back
    transfer_assets wallet_1/wallet_2  100/150   100    0/250  0 0 usdt         # spend all (no change)
    transfer_assets wallet_2/wallet_0  250/1750  250    0/2000 1 0 usdt         # spend all (witness)
    # final balance checks
    _tit "checking final balances"
    check_balance wallet_0 2000 usdt
    check_balance wallet_1    0 usdt
    check_balance wallet_2    0 usdt
    check_balance wallet_0 1825 collectible
    check_balance wallet_1  125 collectible
    check_balance wallet_2   50 collectible
}

## full round of opret transfers (no aborted/retried)
scenario_10() {
    local wallet_type="wpkh"
    # wallets
    prepare_rgb_wallet wallet_0 $wallet_type
    prepare_rgb_wallet wallet_1 $wallet_type
    prepare_rgb_wallet wallet_2 $wallet_type
    # contract issuance
    get_issue_utxo wallet_0
    issue_contract wallet_0 usdt NIA
    issue_contract wallet_0 collectible CFA
    # export/import contracts
    export_contract usdt wallet_0
    import_contract usdt wallet_1
    import_contract usdt wallet_2
    export_contract collectible wallet_0
    import_contract collectible wallet_1
    import_contract collectible wallet_2
    # initial balance checks
    check_balance wallet_0 2000 usdt
    check_balance wallet_0 2000 collectible
    # transfers
    transfer_assets wallet_0/wallet_1 2000/0     100 1900/100  0 0 usdt         # spend issuance
    transfer_assets wallet_0/wallet_1 2000/0     200 1800/200  0 0 collectible  # CFA
    transfer_assets wallet_0/wallet_1 1900/100   200 1700/300  1 0 usdt         # change, witness
    transfer_assets wallet_1/wallet_2  300/0     250   50/250  0 0 usdt         # spend both received allocations
    transfer_assets wallet_1/wallet_2  200/0     100  100/100  0 0 collectible  # CFA, spend received allocations
    transfer_assets wallet_2/wallet_0  250/1700  100  150/1800 1 0 usdt         # close loop, witness
    transfer_assets wallet_2/wallet_0  100/1800   50   50/1850 1 0 collectible  # CFA, close loop, witness
    transfer_assets wallet_0/wallet_1 1800/50     50 1750/100  0 0 usdt         # spend received back
    transfer_assets wallet_0/wallet_1 1850/100    25 1825/125  0 0 collectible  # CFA, spend received back
    transfer_assets wallet_1/wallet_2  100/150   100    0/250  0 0 usdt         # spend all (no change)
    transfer_assets wallet_2/wallet_0  250/1750  250    0/2000 1 0 usdt         # spend all (witness)
    # final balance checks
    _tit "checking final balances"
    check_balance wallet_0 2000 usdt
    check_balance wallet_1    0 usdt
    check_balance wallet_2    0 usdt
    check_balance wallet_0 1825 collectible
    check_balance wallet_1  125 collectible
    check_balance wallet_2   50 collectible
}

## full round of tapret transfers (no aborted/retried)
scenario_11() {
    local wallet_type="tapret-key-only"
    # wallets
    prepare_rgb_wallet wallet_0 $wallet_type
    prepare_rgb_wallet wallet_1 $wallet_type
    prepare_rgb_wallet wallet_2 $wallet_type
    # contract issuance
    get_issue_utxo wallet_0
    issue_contract wallet_0 usdt NIA
    issue_contract wallet_0 collectible CFA
    # export/import contracts
    export_contract usdt wallet_0
    import_contract usdt wallet_1
    import_contract usdt wallet_2
    export_contract collectible wallet_0
    import_contract collectible wallet_1
    import_contract collectible wallet_2
    # initial balance checks
    check_balance wallet_0 2000 usdt
    check_balance wallet_0 2000 collectible
    # transfers
    transfer_assets wallet_0/wallet_1 2000/0     100 1900/100  0 0 usdt         # spend issuance
    transfer_assets wallet_0/wallet_1 2000/0     200 1800/200  0 0 collectible  # CFA
    transfer_assets wallet_0/wallet_1 1900/100   200 1700/300  1 0 usdt         # change, witness
    transfer_assets wallet_1/wallet_2  300/0     250   50/250  0 0 usdt         # spend both received allocations
    transfer_assets wallet_1/wallet_2  200/0     100  100/100  0 0 collectible  # CFA, spend received allocations
    transfer_assets wallet_2/wallet_0  250/1700  100  150/1800 1 0 usdt         # close loop, witness
    transfer_assets wallet_2/wallet_0  100/1800   50   50/1850 1 0 collectible  # CFA, close loop, witness
    transfer_assets wallet_0/wallet_1 1800/50     50 1750/100  0 0 usdt         # spend received back
    transfer_assets wallet_0/wallet_1 1850/100    25 1825/125  0 0 collectible  # CFA, spend received back
    transfer_assets wallet_1/wallet_2  100/150   100    0/250  0 0 usdt         # spend all (no change)
    transfer_assets wallet_2/wallet_0  250/1750  250    0/2000 1 0 usdt         # spend all (witness)
    # final balance checks
    _tit "checking final balances"
    check_balance wallet_0 2000 usdt
    check_balance wallet_1    0 usdt
    check_balance wallet_2    0 usdt
    check_balance wallet_0 1825 collectible
    check_balance wallet_1  125 collectible
    check_balance wallet_2   50 collectible
}

# run selected scenario
$SCENARIO

_tit "sandbox run finished"
