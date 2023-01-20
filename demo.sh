#!/usr/bin/env bash

# closing method: Tapret (tapret1st) or OP_RETURN (opret1st)
CLOSING_METHOD="opret1st"

# wallet and network
DERIVE_PATH="m/86'/1'/0'/0"
DESC_TYPE="wpkh"
ELECTRUM="localhost:50001"
ELECTRUM_DOCKER="electrs:50001"
NETWORK=regtest

# output
DEBUG=0
INSPECT=0

# shell colors
C1='\033[0;32m' # green
C2='\033[0;33m' # orange
C3='\033[0;34m' # blue
NC='\033[0m'    # No Color

_die() {
    echo >&2 "$@"
    exit 1
}

_tit() {
    echo
    printf "${C1}==== %-20s ====${NC}\n" "$@"
}

_subtit() {
    printf "${C2} > %s${NC}\n" "$@"
}

_log() {
    printf "${C3}%s${NC}\n" "$@"
}

_trace() {
    { local trace=0; } 2>/dev/null
    { [ -o xtrace ] && trace=1; } 2>/dev/null
    { [ "$DEBUG" != 0 ] && set -x; } 2>/dev/null
    "$@"
    { [ "$trace" == 0 ] && set +x; } 2>/dev/null
}

_wait_user() {
    if [ "$INSPECT" != 0 ]; then
        read -r -p "press any key to continue" -N 1 _
    fi
}

# shellcheck disable=2034
set_cmd_aliases() {
    BCLI=("docker-compose" "exec" "-T" "-u" "blits" "bitcoind" "bitcoin-cli" "-$NETWORK")
    BDKI="bdk-cli/bin/bdk-cli"
    CLI0=("docker-compose" "exec" "-T" "-u" "rgb" "rgb-node-0" "rgb-cli" "-n" "$NETWORK")
    CLI1=("docker-compose" "exec" "-T" "-u" "rgb" "rgb-node-1" "rgb-cli" "-n" "$NETWORK")
    CLI2=("docker-compose" "exec" "-T" "-u" "rgb" "rgb-node-2" "rgb-cli" "-n" "$NETWORK")
    R200=("docker-compose" "exec" "-T" "-u" "rgb" "rgb-node-0" "rgb20" "-n" "$NETWORK")
    R201=("docker-compose" "exec" "-T" "-u" "rgb" "rgb-node-1" "rgb20" "-n" "$NETWORK")
    R202=("docker-compose" "exec" "-T" "-u" "rgb" "rgb-node-2" "rgb20" "-n" "$NETWORK")
    STD0=("docker-compose" "exec" "-T" "-u" "rgb" "rgb-node-0" "rgb")
    STD1=("docker-compose" "exec" "-T" "-u" "rgb" "rgb-node-1" "rgb")
    STD2=("docker-compose" "exec" "-T" "-u" "rgb" "rgb-node-2" "rgb")
}

check_dirs() {
    for data_dir in data0 data1 data2 datacore dataindex; do
       if [ -d "$data_dir" ]; then
           if [ "$(stat -c %u $data_dir)" = "0" ]; then
               echo "existing data directory \"$data_dir\" found, owned by root"
               echo "please remove it and try again (e.g. 'sudo rm -r $data_dir')"
               _die "cannot continue"
           fi
           echo "exisrting data directory \"$data_dir\" found, removing"
           rm -r $data_dir
       fi
       mkdir -p "$data_dir"
    done
}

install_bdk_cli() {
    local bdk_cli_path="bdk-cli"
    if [ -d "${bdk_cli_path}" ] && [ -x "${BDKI}" ]; then
        if [ "$(${BDKI} -V)" = "bdk-cli 0.6.0" ]; then
            _log "bdk-cli already installed"
            return
        fi
    fi
    _log "installing bdk-cli to ${bdk_cli_path}"
    cargo install bdk-cli --version "0.6.0" --root "./bdk-cli" --features electrum
}

cleanup() {
    docker-compose down
    rm -rf data{0,1,2,core,index}
}

start_services() {
    docker-compose down
    docker-compose up -d
}

prepare_wallets() {
    _trace "${BCLI[@]}" createwallet miner >/dev/null
    for wallet in 'issuer' 'rcpt1' 'rcpt2'; do
        _log "generating new descriptors for wallet $wallet"
        rm -rf ~/.bdk-bitcoin/$wallet
        local xprv
        local der_xprv
        local der_xpub
        xprv="$(_trace $BDKI key generate | jq -r '.xprv')"
        der_xprv=$(_trace $BDKI key derive -p $DERIVE_PATH -x "$xprv" | jq -r '.xprv')
        der_xpub=$(_trace $BDKI key derive -p $DERIVE_PATH -x "$xprv" | jq -r '.xpub')
        printf -v "xprv_$wallet" '%s' "$xprv"
        printf -v "der_xprv_$wallet" '%s' "$der_xprv"
        printf -v "der_xpub_$wallet" '%s' "$der_xpub"
        local xprv_var="xprv_$wallet"
        local der_xprv_var="der_xprv_$wallet"
        local der_xpub_var="der_xpub_$wallet"
        _log "xprv: ${!xprv_var}"
        _log "der_xprv: ${!der_xprv_var}"
        _log "der_xpub: ${!der_xpub_var}"
    done
}

gen_blocks() {
    local count="$1"
    _log "mining $count block(s)"
    _trace "${BCLI[@]}" -rpcwallet=miner -generate "$count" >/dev/null
    sleep 1     # give electrs time to index
}

gen_addr_bdk() {
    local wallet="$1"
    _log "generating new address for wallet \"$wallet\""
    local der_xpub_var="der_xpub_$wallet"
    addr=$(_trace $BDKI -n $NETWORK wallet -w "$wallet" -d "${DESC_TYPE}(${!der_xpub_var})" \
        get_new_address | jq -r '.address')
    _log "generated address: $addr"
}

sync_wallet() {
    local wallet="$1"
    _log "syncing wallet $wallet"
    local der_xpub_var="der_xpub_$wallet"
    _trace $BDKI -n $NETWORK wallet -w "$wallet" -d "${DESC_TYPE}(${!der_xpub_var})" -s $ELECTRUM sync
}

get_utxo() {
    local wallet="$1"
    local txid="$2"
    _log "extracting vout"
    local der_xpub_var="der_xpub_$wallet"
    local filter=".[] | .outpoint | select(contains(\"$txid\"))"
    vout=$(_trace $BDKI -n $NETWORK wallet -w "$wallet" -d "${DESC_TYPE}(${!der_xpub_var})" \
        list_unspent | jq -r "$filter" | cut -d: -f2)
    [ -n "$vout" ] || _die "couldn't retrieve vout for txid $txid"
    _log "txid $txid, vout: $vout"
}

gen_utxo() {
    local wallet="$1"
    local mode="bdk"
    [ "$wallet" = "miner" ] && mode="core"
    # generate an address
    gen_addr_$mode "$wallet"
    # send and mine
    _log "sending funds to wallet \"$wallet\""
    txid="$(_trace "${BCLI[@]}" -rpcwallet=miner sendtoaddress "$addr" 1)"
    gen_blocks 1
    sync_wallet "$wallet"
    get_utxo "$wallet" "$txid"
}

list_unspent() {
    local wallet="$1"
    local der_xpub_var="der_xpub_$wallet"
    _trace $BDKI -n $NETWORK wallet -w "$wallet" \
        -d "${DESC_TYPE}(${!der_xpub_var})" list_unspent
}

issue_asset() {
    _log "unspents before issuance" && list_unspent issuer
    gen_utxo issuer
    txid_issue=$txid
    vout_issue=$vout
    gen_utxo issuer
    txid_issue_2=$txid
    vout_issue_2=$vout
    _subtit 'issuing asset'
    local c_id c_src contract_source
    while read -r line; do
        c_id=$(echo "$line" | grep '^Contract ID:' | cut -d' ' -f3)
        c_src=$(echo "$line" | grep '^rgbc1')
        [ -n "$c_id" ] && contract_id="$c_id"
        [ -n "$c_src" ] && contract_source="$c_src"
    done < <(_trace "${R200[@]}" issue -m $CLOSING_METHOD USDT "USD Tether" \
        "1000@$txid_issue:$vout_issue" "1000@$txid_issue_2:$vout_issue_2" 2>&1)
    _subtit 'registering contract'
    _trace "${CLI0[@]}" contract register "$contract_source"
    _log "contract list after issuance"
    _trace "${CLI0[@]}" contract list
    _log "contract state after issuance"
    _trace "${CLI0[@]}" contract state "$contract_id"
    _log "unspents after issuance" && list_unspent issuer
    _wait_user
}

export_asset() {
    exp_asset="$(_trace "${CLI0[@]}" contract consignment "$contract_id" \
        | tail -1)"
    _log "exported asset: $exp_asset"
}

import_asset() {
    local cli_alias="$1[@]"
    local cli=("${!cli_alias}")
    _trace "${cli[@]}" contract register "$exp_asset"
}

get_balance() {
    local wallet="$1"
    local cli_alias="$2[@]"
    local cli=("${!cli_alias}")
    mapfile -t outpoints < <(_trace list_unspent "$wallet" | jq -r '.[] |.outpoint')
    balance=0
    if [ "${#outpoints[@]}" -gt 0 ]; then
        _log "outpoints: ${outpoints[*]}"
        local allocations amount
        allocations=$(_trace "${cli[@]}" contract state "$contract_id" \
            | grep '^- ' | cut -d' ' -f2)
        _log "wallet $wallet allocations: $allocations"
        for utxo in "${outpoints[@]}"; do
            amount=$(echo "$allocations" \
                | grep "$utxo" | cut -d'#' -f1)
            balance=$((balance + amount))
        done
    else
        balance="N/A"
    fi
}

transfer_asset() {
    ## params
    local send_wlt="$1"         # sender wallet name
    local rcpt_wlt="$2"         # recipient wallet name
    local send_id="$3"          # sender id (for CLIs and data dir)
    local rcpt_id="$4"          # recipient id (for CLIs and data dir)
    local txid_send="$5"        # sender txid
    local vout_send="$6"        # sender vout
    local num="$7"              # transfer number
    local amt_send="$8"         # asset amount to send
    local amt_change="$9"       # asset amount to get back as change
    local txid_send_2="${10}"   # sender txid n. 2
    local vout_send_2="${11}"   # sender vout n. 2

    ## derive cli + data variables for sender and recipient
    local temp_var
    local rcpt_cli rcpt_std rcpt_data
    local send_cli send_r20 send_std send_data
    temp_var="CLI${send_id}[@]" && send_cli=("${!temp_var}")
    temp_var="CLI${rcpt_id}[@]" && rcpt_cli=("${!temp_var}")
    temp_var="R20${send_id}[@]" && send_r20=("${!temp_var}")
    temp_var="STD${send_id}[@]" && send_std=("${!temp_var}")
    temp_var="STD${rcpt_id}[@]" && rcpt_std=("${!temp_var}")
    send_data="data${send_id}"
    rcpt_data="data${rcpt_id}"

    ## starting situation
    _log "spending $amt_send from $txid_send:$vout_send ($send_wlt) with $amt_change change"
    if [ -n "$txid_send_2" ] && [ -n "$vout_send_2" ]; then  # handle double input case
        _log "also using $txid_send_2:$vout_send_2 as input"
    fi
    _log "sender unspents before transfer" && list_unspent "$send_wlt"
    _log "receiver unspents before transfer" && list_unspent "$rcpt_wlt"
    _subtit "initial balances"
    get_balance "$send_wlt" "CLI${send_id}"
    _log "sender balance: $balance"
    get_balance "$rcpt_wlt" "CLI${rcpt_id}"
    _log "receiver balance: $balance"
    _wait_user
    ## generate utxo to receive assets
    gen_utxo "$rcpt_wlt"
    txid_rcpt=$txid
    vout_rcpt=$vout

    ## blind receiving utxo
    _subtit "blinding UTXO for transfer n. $num"
    local blinding blind_utxo blind_factor
    blinding="$(_trace "${rcpt_std[@]}" blind -m $CLOSING_METHOD \
        "$txid_rcpt:$vout_rcpt")"
    blind_utxo=$(echo "$blinding" | head -1)
    blind_factor=$(echo "$blinding" | tail -1 | cut -d' ' -f3)
    _log "blinded utxo: $blind_utxo"
    _log "blinding factor: $blind_factor"

    ## generate addresses for transfer asset change and tx btc output
    if [ "$amt_change" -gt 0 ]; then
        gen_utxo "$send_wlt"
        txid_change=$txid
        vout_change=$vout
        [ "$DEBUG" != 0 ] && _log "change outpoint $txid_change:$vout_change"
    else
        unset txid_change
        unset vout_change
        [ "$DEBUG" != 0 ] && _log \
            "change amount is 0, skipping change outpoint creation"
    fi
    gen_addr_bdk "$send_wlt"
    local addr_send=$addr

    ## prepare psbt
    _subtit "creating PSBT"
    [ "$DEBUG" != 0 ] && list_unspent "$send_wlt"
    local filter=".[] |select(.outpoint|contains(\"$txid_send\")) |.txout |.amount"
    local amnt amnt_2
    amnt="$(list_unspent "$send_wlt" | jq -r "$filter")"
    if [ -n "$txid_send_2" ] && [ -n "$vout_send_2" ]; then  # handle double input case
        filter=".[] |select(.outpoint|contains(\"$txid_send_2\")) |.txout |.amount"
        amnt_2="$(list_unspent "$send_wlt" | jq -r "$filter")"
        amnt=$((amnt + amnt_2))
    fi
    local psbt=tx_${num}.psbt
    local psbt_embed=embed_${num}.psbt
    local der_xpub_var="der_xpub_$send_wlt"
    local utxos=("$txid_send:$vout_send")
    if [ -n "$txid_send_2" ] && [ -n "$vout_send_2" ]; then  # handle double input case
        utxos+=("$txid_send_2:$vout_send_2")
    fi
    declare inputs=()
    for utxo in "${utxos[@]}"; do
        inputs+=("--utxos" "$utxo")
    done
    _trace $BDKI -n $NETWORK wallet -w "$send_wlt" \
        -d "${DESC_TYPE}(${!der_xpub_var})" create_tx --enable_rbf --send_all \
        -f 5 "${inputs[@]}" --to "$addr_send:0" \
            | jq -r '.psbt' | base64 -d >"$send_data/$psbt"
    if [ "$DEBUG" != 0 ]; then
        _log "showing decoded psbt"
        _trace "${BCLI[@]}" decodepsbt "$(base64 -w0 "$send_data/$psbt")" | jq
    fi
    sleep 1

    ## initiate transfer
    _subtit "initiating transfer"
    local cons_comp=consignment_compose_${num}.rgbc
    local input_comp="$txid_send:$vout_send"
    local input_tran=("-u" "$txid_send:$vout_send")
    local transition=transition_${num}.rgbt
    local change
    if [ "$amt_change" -gt 0 ]; then
        change=("-c" "$amt_change@$CLOSING_METHOD:$txid_change:$vout_change")
    else
        change=()
    fi
    if [ -n "$txid_send_2" ] && [ -n "$vout_send_2" ]; then  # handle double input case
        input_comp_2="$txid_send_2:$vout_send_2"
        input_tran+=("-u" "$txid_send_2:$vout_send_2")
    fi
    _log "composing transfer"
    _trace "${send_cli[@]}" transfer compose \
        "$contract_id" "$input_comp" "$input_comp_2" "$cons_comp"
    _log "validating consignment"
    _trace "${send_std[@]}" consignment validate "$cons_comp" $ELECTRUM_DOCKER
    if [ "$DEBUG" != 0 ]; then
        _log "inspecting consignment"
        _trace "${send_std[@]}" consignment inspect -f debug "$cons_comp"
    fi
    _log "transferring asset"
    _trace "${send_r20[@]}" transfer "${input_tran[@]}" "${change[@]}" \
        "$cons_comp" "$amt_send@$blind_utxo" "$transition"
    _wait_user

    ## embed contract into psbt
    _subtit "finalizing psbt"
    _log "embedding contract into psbt"
    _trace "${send_cli[@]}" contract embed "$contract_id" "$psbt" \
        -o "$psbt_embed"
    if [ "$DEBUG" != 0 ]; then
        _log "showing decoded psbt with embedded contract"
        _trace "${BCLI[@]}" decodepsbt \
            "$(base64 -w0 "$send_data/$psbt_embed")" | jq
    fi
    local tries=0
    while [ ! -f "$send_data/$psbt_embed" ]; do
        tries=$((tries + 1))
        [ $tries -gt 5 ] && _die \
            " max retries reached waiting for psbt to appear"
        sleep 1
    done
    _wait_user

    ## add state transition info to psbt
    _log "adding state transition information to psbt"
    local psbt_combine="combine_${num}.psbt"
    local psbt_bundle="bundle_${num}.psbt"
    _trace "${send_cli[@]}" transfer combine -o "$psbt_combine" \
        "$contract_id" "$transition" "$psbt_embed" "${utxos[@]}"

    ## finalize RGB bundle in psbt
    _log "finalizing RGB bundle in psbt"
    _trace "${send_std[@]}" psbt bundle -m $CLOSING_METHOD \
        "$psbt_combine" "$psbt_bundle"
    _log "analyzing bundled psbt"
    _trace "${send_std[@]}" psbt analyze "$psbt_bundle"

    ## finalize consignment
    _subtit "finalizing consignment"
    local cons_final="consignment_final_${num}.rgbc"
    _trace "${send_cli[@]}" transfer finalize \
        --endseal "$blind_utxo" "$psbt_bundle" "$cons_comp" "$cons_final"
    _wait_user

    ## copy generated data to recipient
    _trace cp {"$send_data","$rcpt_data"}/"$cons_final"

    ## recipient: validate transfer
    _subtit "validating consignment"
    local vldt
    vldt=$(_trace "${rcpt_std[@]}" consignment validate \
        "$cons_final" $ELECTRUM_DOCKER)
    _log "$vldt"
    if ! echo "$vldt" | grep -q 'failures: \[\]'; then
        _die "validation error (failure)"
    fi

    ## sign + broadcast psbt
    _subtit "signing and broadcasting tx"
    local der_xprv_var="der_xprv_$send_wlt"
    local psbt_finalized psbt_signed
    local reveal="$CLOSING_METHOD@$txid_rcpt:$vout_rcpt#$blind_factor"
    psbt_signed=$(_trace $BDKI -n $NETWORK wallet -w "$send_wlt" \
        -d "${DESC_TYPE}(${!der_xprv_var})" sign \
        --psbt "$(base64 -w0 "$send_data/$psbt_bundle")")
    psbt_finalized=$(echo "$psbt_signed" \
        | jq -r 'select(.is_finalized = true) |.psbt')
    [ -n "$psbt_finalized" ] || _die "error signing and finalizing PSBT"
    echo "$psbt_finalized" \
        | base64 -d > "data${send_id}/finalized-bdk_${num}.psbt"
    _log "signed PSBT: $psbt_finalized"
    _trace $BDKI -n $NETWORK wallet -w "$send_wlt" \
        -d "${DESC_TYPE}(${!der_xpub_var})" -s $ELECTRUM broadcast \
        --psbt "$psbt_finalized"
    gen_blocks 1
    _wait_user

    ## recipient: consume transfer
    _subtit "consuming transfer (recipient)"
    local accept
    accept=$(_trace "${rcpt_cli[@]}" transfer consume "$cons_final" \
        --reveal "$reveal")
    _log "$accept"

    ## sender: consume transfer
    _subtit "consuming transfer (sender)"
    accept=$(_trace "${send_cli[@]}" transfer consume "$cons_final")
    _log "$accept"

    ## ending situation
    _log "sender unspents after transfer" && list_unspent "$send_wlt"
    _log "receiver unspents after transfer" && list_unspent "$rcpt_wlt"
    _subtit "final balances"
    get_balance "$send_wlt" "CLI${send_id}"
    _log "sender balance: $balance"
    get_balance "$rcpt_wlt" "CLI${rcpt_id}"
    _log "receiver balance: $balance"
    _wait_user
}

# cmdline arguments
while [ -n "$1" ]; do
    case $1 in
        tapret1st)
            _log "setting tapret close method"
            CLOSING_METHOD="tapret1st"
            ;;
        opret1st)
            _log "setting opret close method"
            CLOSING_METHOD="opret1st"
            ;;
        wpkh)
            _log "setting wpkh descriptor type"
            DESC_TYPE="wpkh"
            ;;
        tr)
            _log "setting tr descriptor type"
            DESC_TYPE="tr"
            ;;
        "-i")
            _log "enabling pauses for output user inspection"
            INSPECT=1
            ;;
        "-v")
            _log "enabling debug output"
            DEBUG=1
            ;;
        *)
            _die "unsupported argument \"$1\""
            ;;
    esac
    shift
done

# initial setup
set_cmd_aliases
_tit "installing bdk-cli"
install_bdk_cli
trap cleanup EXIT
_tit "starting services"
check_dirs
start_services

# wallet setup
_tit "preparing wallets"
prepare_wallets
gen_blocks 103

# asset issuance
_tit "issuing \"USDT\" asset"
issue_asset
export_asset

# import asset for recipient 1
import_asset "CLI1"

# asset transfer no. 1
_tit "transferring asset from issuer to recipient 1"
transfer_asset issuer rcpt1 0 1 "$txid_issue" "$vout_issue" 1 100 1900 "$txid_issue_2" "$vout_issue_2"

# change spending test
_tit "transferring asset from issuer to recipient 1 - 2nd time (spending change)"
transfer_asset issuer rcpt1 0 1 "$txid_change" "$vout_change" 1 200 1700

# asset transfer no. 2
_tit "transferring asset from recipient 1 to recipient 2"
transfer_asset rcpt1 rcpt2 1 2 "$txid_rcpt" "$vout_rcpt" 2 42 158

# asset transfer no. 3 (transfer 100%, no change)
_tit "transferring asset from recipient 2 to issuer"
transfer_asset rcpt2 issuer 2 0 "$txid_rcpt" "$vout_rcpt" 3 42 0
