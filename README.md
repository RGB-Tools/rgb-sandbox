RGB Sandbox
===

## Introduction
This is an RGB sandbox and demo based on RGB version 0.10.
It is based on the original rgb-node demo by [St333p] (version 0.1), [grunch]'s
[guide] and previous rgb-node sandbox versions.

The underlying Bitcoin network is `regtest`.

RGB is operated via the [rgb-contracts] crate. [BDK] is used for walleting.

This sandbox can help explore RGB features in a self-contained environment
or can be used as a demo of the main RGB functionalities for fungible assets.

Two versions of the demo are available:
- an automated one
- a manual one

The automated version is meant to provide a quick and easy way to see an RGB
token be created and transferred. The manual version is meant to provide a
hands-on experience with an RGB token and gives step-by-step instructions on
how to operate all the required components.

Commands are to be executed in a bash shell. Example output is provided to
allow following the links between the steps. Actual output when executing the
procedure will be different each time.

## Setup
Clone the repository, including (shallow) submodules:
```sh
git clone https://github.com/RGB-Tools/rgb-sandbox --recurse-submodules --shallow-submodules
```

The default setup assumes the user and group IDs are `1000`. If that's not the
case, the `MYUID` and `MYGID` environment variables  in the
`docker-compose.yml` file need to be updated accordingly.

The automated demo does not require any other setup steps.

The manual version requires handling of data directories and services, see the
[dedicated section](#data-and-service-management) for instructions.

Both versions will leave `bdk-cli` and `rgb-contracts` installed, in the
respective directories under the project root. These directories can be safely
removed to start from scratch, doing so will just require the rust crates to be
re-installed on the next run.

### Requirements
- [git]
- [cargo]
- [docker]
- [docker compose]
- sqlite3 development library (e.g. `libsqlite3-dev` on Debian-like systems)

## Sandbox exploration
The services started with docker compose simulate a small network with a
bitcoin node and an explorer. These can be used to support testing and
exploring the basic functionality of an RGB ecosystem.

Check out the manual demo below to get started with example commands. Refer to
each command's help documentation for additional information.

## Automated demo
To check out the automated demo, run:
```sh
bash demo.sh
```

The automated script will install the required rust crates, create empty
service data directories, start the required services, prepare the wallets,
issue assets, execute a series of asset transfers, then stop the services and
remove the data directories.

For more verbose output during the automated demo, add the `-v` option (`bash
demo.sh -v`), which shows the commands being run and additional
information (including output from additional inspection commands).

## Manual demo recording

Following the manual demo and executing all the required steps is a rather long
and error-prone process.

To ease the task of following the steps, a recording of the manual demo
execution is available:
[![demo](https://asciinema.org/a/603883.svg)](https://asciinema.org/a/603883?autoplay=1)

## Manual demo

Note: this has not yet been updated to the 0.10 version.

The manual demo shows how to issue an asset and transfer some to a recipient.

At the beginning of the demo, some shell command aliases and common variables
need to be set, then a series of steps are briefly described and illustrated
with example shell commands.

During each step, commands either use literal values, ones that the user needs
to fill in, or variables. Some variables (uppercase) are the ones set at the
beginning of the demo, others (lowercase) need to be set based on the output of
the commands as they are run.

Values that need to be filled in with command output follow the command
invocation that produces the required output and the example value is
ellipsized (`...`), meaning the instruction should not be copied verbatim and
the value should instead be replaced with the actual output received while
following the steps.

### Data and service management
Create data directories and start the required services in Docker containers:
```sh
# create data directories
mkdir data{0,1,core,index}

# start services (first time docker images need to be downloaded...)
docker compose up -d
```

To get a list of the running services you can run:
```sh
docker compose ps
```

To get their respective logs you can run, for instance:
```sh
docker compose logs bitcoind
```

Once finished and in order to clean up containers and data to start the demo
from scratch, run:
```sh
# stop services and remove containers
docker compose down

# remove data directories
rm -fr data{0,1,core,index}
```

### Premise
The rgb-contracts CLI tool does not handle wallet-related functionality, it
performs RGB-specific tasks over data that is provided by an external wallet,
such as BDK. In particular, in order to demonstrate a basic workflow with
issuance and transfer, from the bitcoin wallets we will need:
- an *outpoint_issue* to which the issuer will allocate the new asset
- an *outpoint_receive* where the recipient will receive the asset transfer
- an *addr_change* where the sender will receive the bitcoin and asset change
- a partially signed bitcoin transaction (PSBT) to anchor the transfer

### bdk-cli installation
Wallets will be handled with BDK. We install its CLI to the `bdk-cli` directory
inside the project directory:
```sh
cargo install bdk-cli --version "0.27.1" --root "./bdk-cli" --features electrum --locked
```

### rgb-contracts installation
RGB functionality will be handled with `rgb-contracts`. We install its CLI to
the `rgb-contracts` directory inside the project directory:
```sh
cargo install rgb-contracts --version "0.10.0-rc.5" --root "./rgb-contracts" --all-features --locked
```

### Demo
#### Initial setup
We setup aliases to ease CLI calls:
```sh
alias bcli="docker compose exec -u blits bitcoind bitcoin-cli -regtest"
alias bdk="bdk-cli/bin/bdk-cli"
alias rgb0="rgb-contracts/bin/rgb -n regtest -d data0"
alias rgb1="rgb-contracts/bin/rgb -n regtest -d data1"
```

We set some environment variables:
```sh
CLOSING_METHOD="opret1st"
DERIVE_PATH="m/86'/1'/0'/9"
DESC_TYPE="wpkh"
ELECTRUM="localhost:50001"
ELECTRUM_DOCKER="electrs:50001"
CONSIGNMENT="consignment.rgb"
PSBT="tx.psbt"
IFACE="RGB20"
```

We prepare the Bitcoin wallets using Bitcoin Core and BDK:
```sh
# Bitcoin Core wallet
bcli createwallet miner
bcli -generate 103

# if there are any bdk wallets from previous runs, they need to be removed
rm -fr ~/.bdk-bitcoin/{issuer,receiver}

# issuer/sender BDK wallet
bdk key generate
# example output:
# {
#   "fingerprint": "a83fc09c",
#   "mnemonic": "frozen nest frown retire wolf clinic tent know culture mad season whip impulse adjust hand change stomach meat wreck brick foam broken start reform",
#   "xprv": "tprv8ZgxMBicQKsPey8NKMEpFemmWPMtYb4znAKtWVKr48Q1uDvemxT3RRW5m6NpToMoiVYSwVS16xKkeMueVhxnUsE7X7TpgzzxLSg7jBS1ma2"
# }

xprv_0="tprv8Zgx..."

bdk key derive -p "$DERIVE_PATH" -x "$xprv_0"
# example output:
# {
#   "xprv": "[a83fc09c/86'/1'/0'/9]tprv8iqTQS7ksLhSaJNCfach4uTD6NJtoypuYnSEM5no1Km6YkCt8ciaYxtNL8pR68KU8a7GDSMhRTsrjaH7QR5bsx2e4287tjBa7SdFGyStGPR/*",
#   "xpub": "[a83fc09c/86'/1'/0'/9]tpubDFXVYrA11iP7TmPzZEHHUK7KfPppyK1p8631dbq6RbZVPETem1YAjTWEWK6xkwQpJpcvcX6vGZ8xoK6yLE7CcRnm4514mhHGfJ1UNLHVxXG/*"
# }

xprv_der_0="[a83fc09c/86'/1'/0'/9]tprv8iqT..."
xpub_der_0="[a83fc09c/86'/1'/0'/9]tpubDFXV..."

# receiver BDK wallet
bdk key generate
# example output:
# {
#   "fingerprint": "2976d70f",
#   "mnemonic": "kick detail chronic crime unusual nut legal viable limb elegant always tent envelope betray comfort human famous boat garment shallow hunt brass mind bomb",
#   "xprv": "tprv8ZgxMBicQKsPdorFhbmRFNu9tWMy2xxLLRYvxE5bpSvhymTpUmHdgaZiXN3ndATpSRTyyaxpnve3xYwhdoUhW1DwCW85MW9KwuJzV2xX6gV"
# }

xprv_1="tprv8Zgx..."

bdk key derive -p "$DERIVE_PATH" -x "$xprv_1"
# example output:
# {
#   "xprv": "[2976d70f/86'/1'/0'/9]tprv8j496FRBryAmENLx7h66pKcgtet1o7fJN5yv4jVvZ8cpcDVTWajqqmyNFmrv9buLR7UkhqFKuvshcZQxdzfCgN1Qg1m5UcHLA5PRumTBvv7/*",
#   "xpub": "[2976d70f/86'/1'/0'/9]tpubDFkBEfTS1LrS7qNk1LkhDjGoTgPwxSrCwPahMFYDyQRDShkE8yZS2GbERvepZ9mNAK5R4ejNmDoFFv1EHZ8QgJwqkXFmn6C1spUa6VUwr1x/*"
# }

xprv_der_1="[2976d70f/86'/1'/0'/9]tprv8j49..."
xpub_der_1="[2976d70f/86'/1'/0'/9]tpubDFkB..."

# generate addresses
bdk -n regtest wallet -w issuer -d "$DESC_TYPE($xpub_der_0)" get_new_address
# example output:
# {
#   "address": "bcrt1q67z8nmswgvs38n64yl80plsejcs6vt867c2y22"
# }

addr_issue="bcrt1q67..."

bdk -n regtest wallet -w issuer -d "$DESC_TYPE($xpub_der_0)" get_new_address
# example output:
# {
#   "address": "bcrt1qr36fkwcvaqkg4v5e2hdh9x4vrxhqysf6wk4hcn"
# }

addr_change="bcrt1qr3..."

bdk -n regtest wallet -w receiver -d "$DESC_TYPE($xpub_der_1)" get_new_address
# example output:
# {
#   "address": "bcrt1q87w6s0anaugzksgmq9adwcgw9wyt6ekj7u8qc6"
# }

addr_receive="bcrt1q87..."

# fund wallets
bcli -rpcwallet=miner sendtoaddress "$addr_issue" 1
bcli -rpcwallet=miner sendtoaddress "$addr_receive" 1
bcli -rpcwallet=miner -generate 1

# sync wallets
bdk -n regtest wallet -w issuer -d "$DESC_TYPE($xpub_der_0)" -s "$ELECTRUM" sync
bdk -n regtest wallet -w receiver -d "$DESC_TYPE($xpub_der_1)" -s "$ELECTRUM" sync

# list wallet unspents and gather the outpoints
bdk -n regtest wallet -w issuer -d "$DESC_TYPE($xpub_der_0)" list_unspent
# example output:
# [
#   {
#     "is_spent": false,
#     "keychain": "External",
#     "outpoint": "6f6343401fc57c3f6a30043c61023e62311ee2b5d321823843af9cbcbfb2ac7e:1",
#     "txout": {
#       "script_pubkey": "0014d78479ee0e432113cf5527cef0fe199621a62cfa",
#       "value": 100000000
#     }
#   }
# ]

outpoint_issue="6f6...c7e:1"

bdk -n regtest wallet -w receiver -d "$DESC_TYPE($xpub_der_1)" list_unspent
# example output:
# [
#   {
#     "is_spent": false,
#     "keychain": "External",
#     "outpoint": "bbc274a1f145552a6f22cab912c9b1903fb30333128b3b0f22212f2aa87772e2:0",
#     "txout": {
#       "script_pubkey": "00143f9da83fb3ef102b411b017ad7610e2b88bd66d2",
#       "value": 100000000
#     }
#   }
# ]

outpoint_receive="bbc...2e2:0"
```

We setup the RGB clients, importing schema and interface implementation:
```sh
# 1st client
rgb0 import rgb-schemata/schemata/NonInflatableAssets.rgb
# example output:
# Stock file not found, creating default stock
# Wallet file not found, creating new wallet list
# Schema urn:lnp-bp:sc:BEiLYE-am9WhTW1-oK8cpvw4-FEMtzMrf-mKocuGZn-qWK6YF#ginger-parking-nirvana imported to the stash

rgb0 import rgb-schemata/schemata/NonInflatableAssets-RGB20.rgb
# example output:
# Implementation urn:lnp-bp:im:9EUGHC-wpuiyrQE-NdPBVyiv-VX4sVRBs-9yKfteug-HtqnGb#titanic-easy-citizen of interface urn:lnp-bp:if:48hc4i-m9JRcYQA-uUSzwFCK-VNEa9eZf-nhepU8QJ-pqosXS#laptop-domingo-cool for schema urn:lnp-bp:sc:BEiLYE-am9WhTW1-oK8cpvw4-FEMtzMrf-mKocuGZn-qWK6YF#ginger-parking-nirvana imported to the stash

# 2nd client (same output as 1st client)
rgb1 import rgb-schemata/schemata/NonInflatableAssets.rgb
rgb1 import rgb-schemata/schemata/NonInflatableAssets-RGB20.rgb
```

We retrieve the schema ID and set it as environment variable:
```sh
rgb0 schemata
# example output:
# urn:lnp-bp:sc:BEiLYE-am9WhTW1-oK8cpvw4-FEMtzMrf-mKocuGZn-qWK6YF#ginger-parking-nirvana RGB20

schema="urn:lnp-bp:sc:BEiLYE-am...ing-nirvana"
```

#### Asset issuance
To issue an asset, we first need to prepare a contract definition file, then
use it to actually carry out the issuance.

To prepare the contract file, we copy the provided template and modify the copy
to set the required data:
- issued supply
- created timestamp
- closing method
- issuance txid and vout

We do this with a single command (which reads the template file, modifies the
given properties and writes the result to the contract definition file):
```sh
sed \
  -e "s/issued_supply/1000/" \
  -e "s/created_timestamp/$(date +%s)/" \
  -e "s/closing_method/$CLOSING_METHOD/" \
  -e "s/txid:vout/$outpoint_issue/" \
  contracts/usdt.yaml.template > contracts/usdt.yaml
```

To actually issue the asset, run:
```sh
rgb0 issue "$schema" "$IFACE" contracts/usdt.yaml
# example output:
# A new contract rgb:2Q7p6zS-JUCTP8pMJ-7fk8QBjYp-ngvHnJiuw-9jh8PPuvy-scKUUkd is issued and added to the stash.
# Use `export` command to export the contract.

contract_id="rgb:2Q7...Ukd"
```
This will create a new genesis that includes the asset metadata and the
allocation of the initial amount to `outpoint_issue`.

You can list known contracts:
```sh
rgb0 contracts
# example output:
# rgb:2Q7p6zS-JUCTP8pMJ-7fk8QBjYp-ngvHnJiuw-9jh8PPuvy-scKUUkd
```

You can show the current known state for the contract:
```sh
rgb0 state "$contract_id" "$IFACE"
# example output:
# Global:
#   spec := (naming=(ticker=("USDT"), name=("USD Tether"), details=~), precision=0)
#   data := (terms=("demo RGB20 asset"), media=~)
#   issuedSupply := (1000)
#   created := (1691496693)
#
# Owned:
#   assetOwner:
#     amount=1000, utxo=6f6343401fc57c3f6a30043c61023e62311ee2b5d321823843af9cbcbfb2ac7e:1, witness=~ # owner unknown
```

#### Transfer

##### Receiver: generate invoice
In order to receive assets, the receiver needs to provide an invoice to the
sender. The receiver generates an invoice providing the amount to be received
(here `100`) and the outpoint where the assets should be allocated:
```sh
rgb1 invoice "$contract_id" "$IFACE" 100 "$CLOSING_METHOD:$outpoint_receive"
# example output:
# rgb:2Q7p6zS-JUCTP8pMJ-7fk8QBjYp-ngvHnJiuw-9jh8PPuvy-scKUUkd/RGB20/100+utxob:ZCTkvDN-mrwDXLSkx-1PKfHuaGH-R7cLf79Rg-YfSUGYn6i-YAS4Ts

invoice="rgb:2Q7...Ukd/RGB20/100+utxob:ZCT...4Ts"
```
Note: this will blind the given outpoint and the invoice will contain a blinded
UTXO in place of the original outpoint (see the `utxob:` part of the invoice).

##### Sender: initiate asset transfer
To send assets, the sender needs to create a consignment and commit to it into
a bitcoin transaction. We need to create a PSBT and then modify it to include
the commitment.

We create the PSBT, using `outpoint_issue` as input and `addr_change` for the
change (RGB and BTC):
```sh
bdk -n regtest wallet -w issuer -d "$DESC_TYPE($xpub_der_0)" create_tx \
  -f 5 --send_all --utxos "$outpoint_issue" --to "$addr_change:0" \
  --add_string opret
# example output:
# {
#   "details": {
#     "confirmation_time": null,
#     "fee": 630,
#     "received": 99999370,
#     "sent": 100000000,
#     "transaction": null,
#     "txid": "26a1250ec087138e663cb7be52e13b18758e0257d9aba79d3f6eb0b0516763dd"
#   },
#   "psbt": "cHNidP8BAGIBAAAAAX6ssr+8nK9DOIIh07XiHjFiPgJhPAQwaj98xR9AQ2NvAQAAAAD+////Aore9QUAAAAAFgAUHHSbOwzoLIqymVXbcpqsGa4CQToAAAAAAAAAAAdqBW9wcmV0aAAAAAABAN4CAAAAAAEB9PcBuZVCyKTgMO50SVrsjfqdlVTABBB3cMtZaGXMN2MAAAAAAP3///8C/AUQJAEAAAAWABRhzatgiLp38YKt+2na/iB6/Y2MnADh9QUAAAAAFgAU14R57g5DIRPPVSfO8P4ZliGmLPoCRzBEAiAdCmZ/hSk/rZr+G+SGo/Lx8O8ZpAjIihTYcF983h796wIgHnKVCPwfmTIn+EPl8pDXbzHRTVnAn5jBRDCaMYS1SeMBIQPkcWZ9eqvZKlG1QK4t4vplBvahq6fHGp/lezPo9+pznWcAAAABAR8A4fUFAAAAABYAFNeEee4OQyETz1UnzvD+GZYhpiz6IgYClNhrjr91okI1jPK4r97icFId4fmZHKPciyYh7UBuX+MYqD/AnFYAAIABAACAAAAAgAkAAAAAAAAAACICAquWbk66NttJRZuWBIjM4NIbB1bT0/pH5VKyViGyey5TGKg/wJxWAACAAQAAgAAAAIAJAAAAAQAAAAAA"
# }

echo "cHN...AAA" | base64 -d > "data0/$PSBT"
```

We then modify the PSBT to set the commitment host:
```sh
rgb0 set-host --method "$CLOSING_METHOD" "data0/$PSBT"
# PSBT file 'data0/tx.psbt' is updated with opret1st host now set.
```

We create the transfer, providing the PSBT and the invoice. This generates the
consignment:
```sh
rgb0 transfer --method "$CLOSING_METHOD" "data0/$PSBT" "$invoice" "data0/$CONSIGNMENT"
# example output:
# Transfer is created and saved into 'data0/consignment.rgb'.
# PSBT file 'data0/tx.psbt' is updated with all required commitments and ready to be signed.
# Stash data are updated.
```

The consignment can be inspected, but since the output is very long it's best
to send the output to a file:
```sh
rgb0 inspect "data0/$CONSIGNMENT" > consignment.inspect
```
To view the result, open the `consignment.inspect` file with a text editor.

##### Consignment exchange
For the purpose of this demo, copying the file over to the receiving node's
data directory is sufficient:
```sh
cp data{0,1}/"$CONSIGNMENT"
```

In real-world scenarios, consignments are exchanged either via [RGB HTTP
JSON-RPC] (e.g. using an [RGB proxy]) or other consignment exchange services.

##### Receiver: validate transfer
Before a transfer can be safely accepted, it needs to be validated:
```sh
rgb1 validate "data1/$CONSIGNMENT"
# example output:
# Consignment has non-mined terminal(s)
# Non-mined terminals:
# - f17d544c0ac161f758d379c4366e6ede8f394da9633671908738b415ae5c8fb4
# Validation warnings:
# - terminal witness transaction f17d544c0ac161f758d379c4366e6ede8f394da9633671908738b415ae5c8fb4 is not yet mined.
```

At this point it's normal that validation reports a warning about the witness
transaction not been mined, as the sender has not broadcast it yet. The sender
is waiting for approval from the receiver.

Once validation has passed, the receiver can approve the transfer. For this
demo let's just assume it happened, in a real-world scenario an [RGB proxy]
would be typically used for this as well.

##### Sender: sign and broadcast transaction
With the receiver's approval of the transfer, the transaction can be signed and
broadcast:
```sh
bdk -n regtest wallet -w issuer -d "$DESC_TYPE($xprv_der_0)" \
  sign --psbt $(cat data0/$PSBT | base64 | tr -d '\r\n')
# example output:
# {
#   "is_finalized": true,
#   "psbt": "cHNidP8BAH0BAAAAAX6ssr+8nK9DOIIh07XiHjFiPgJhPAQwaj98xR9AQ2NvAQAAAAD+////Aore9QUAAAAAFgAUHHSbOwzoLIqymVXbcpqsGa4CQToAAAAAAAAAACJqILJNu5OPAn29xMK30LPyEYF8BQzo4m4kMqdwQOf+vFMvaAAAACb8A1JHQgGzGylFw6I59wDVj85LlfJSDWRSj1ETsk8raL8NsrHYvNYAALgv5W39fUCA+5Wg2rcfqnBDyRzss7SzfYf8Km8dWDCRECcAAAABuC/lbf19QID7laDatx+qcEPJHOyztLN9h/wqbx1YMJGgDwAAAAGgDwECAAMAAAAAAAAPvcNrn//UdwiEAwAAAAAAAB1R+iZ9g65EZQH+yo6U6Rd5BR49w6kNrogl9GhgX2lPAkkbzeRxlHm2NcOArOXeqIFc56HypcJNjYqcpHODx2ySCGQAAAAAAAAAU/umctyJSLYssZtL73I+o2LndtWGDjf0niWCCTgYfVgAAAEA3gIAAAAAAQH09wG5lULIpOAw7nRJWuyN+p2VVMAEEHdwy1loZcw3YwAAAAAA/f///wL8BRAkAQAAABYAFGHNq2CIunfxgq37adr+IHr9jYycAOH1BQAAAAAWABTXhHnuDkMhE89VJ87w/hmWIaYs+gJHMEQCIB0KZn+FKT+tmv4b5Iaj8vHw7xmkCMiKFNhwX3zeHv3rAiAecpUI/B+ZMif4Q+XykNdvMdFNWcCfmMFEMJoxhLVJ4wEhA+RxZn16q9kqUbVAri3i+mUG9qGrp8can+V7M+j36nOdZwAAAAEBHwDh9QUAAAAAFgAU14R57g5DIRPPVSfO8P4ZliGmLPoiBgKU2GuOv3WiQjWM8riv3uJwUh3h+Zkco9yLJiHtQG5f4xioP8CcVgAAgAEAAIAAAACACQAAAAAAAAABBwABCGsCRzBEAiAJopaRrp3rkRwyFThM4feKs1/LrqP3oLj/4mxEWEX8NgIgWTtPIDgl2pOHAQHcW8Y8L3+kwPYbUfe5IHgE7Q49dpwBIQKU2GuOv3WiQjWM8riv3uJwUh3h+Zkco9yLJiHtQG5f4yb8A1JHQgO4L+Vt/X1AgPuVoNq3H6pwQ8kc7LO0s32H/CpvHVgwkSCzGylFw6I59wDVj85LlfJSDWRSj1ETsk8raL8NsrHYvAAiAgKrlm5OujbbSUWblgSIzODSGwdW09P6R+VSslYhsnsuUxioP8CcVgAAgAEAAIAAAACACQAAAAEAAAAAKfwGTE5QQlA0ALgv5W39fUCA+5Wg2rcfqnBDyRzss7SzfYf8Km8dWDCRIAjJeTBvKvCk+LhBj7FQmWMaz10SJxpnP3PjjR0/gGtNCfwGTE5QQlA0AQhTJmpjuc0zTwj8BU9QUkVUAAAI/AVPUFJFVAEgsk27k48Cfb3EwrfQs/IRgXwFDOjibiQyp3BA5/68Uy8A"
# }

psbt_signed="cHN...y8A"

bdk -n regtest wallet -w issuer -d "$DESC_TYPE($xpub_der_0)" -s "$ELECTRUM" \
    broadcast --psbt "$psbt_signed"
# example output:
# {
#   "txid": "f17d544c0ac161f758d379c4366e6ede8f394da9633671908738b415ae5c8fb4"
# }
```

##### Transaction confirmation
Now the transaction has been broadcast, let's confirm it:
```sh
bcli -rpcwallet=miner -generate 1
```
In real-world scenarios the parties wait for the transaction to be included in
a block.

##### Receiver: accept transfer
Once the transaction has been confirmed, the receiver can accept the transfer,
which is required to complete the transfer and update the contract state:
```sh
rgb1 accept "data1/$CONSIGNMENT"
# example output:
# Consignment is valid
#
# Transfer accepted into the stash
```
Note that accepting a transfer first validates its consignment.

Let's see the updated contract state, from the receiver's point of view:
```sh
rgb1 state "$contract_id" "$IFACE"
# example output:
# Global:
#   spec := (naming=(ticker=("USDT"), name=("USD Tether"), details=~), precision=0)
#   data := (terms=("demo RGB20 asset"), media=~)
#   issuedSupply := (1000)
#   created := (1691496693)
#
# Owned:
#   assetOwner:
#     amount=900, utxo=f17d544c0ac161f758d379c4366e6ede8f394da9633671908738b415ae5c8fb4:0, witness=f17d544c0ac161f758d379c4366e6ede8f394da9633671908738b415ae5c8fb4 # owner unknown
#     amount=100, utxo=bbc274a1f145552a6f22cab912c9b1903fb30333128b3b0f22212f2aa87772e2:0, witness=f17d544c0ac161f758d379c4366e6ede8f394da9633671908738b415ae5c8fb4 # owner unknown
#     amount=1000, utxo=6f6343401fc57c3f6a30043c61023e62311ee2b5d321823843af9cbcbfb2ac7e:1, witness=~ # owner unknown
```
The allocations for the original issuance and the transfer can be seen. The
receiver can recognize its allocation from the `utxo`, which corresponds to the
`outpoint_receive` provided to generate the invoice.

##### Sender: accept transfer
The sender doesn't need to explicitly accept the transfer, as it's automatically
accepted when creating it.

The contract state already reflects the updated situation:
```sh
rgb0 state "$contract_id" "$IFACE"
# example output:
# Global:
#   spec := (naming=(ticker=("USDT"), name=("USD Tether"), details=~), precision=0)
#   data := (terms=("demo RGB20 asset"), media=~)
#   issuedSupply := (1000)
#   created := (1691496693)
#
# Owned:
#   assetOwner:
#     amount=900, utxo=f17d544c0ac161f758d379c4366e6ede8f394da9633671908738b415ae5c8fb4:0, witness=f17d544c0ac161f758d379c4366e6ede8f394da9633671908738b415ae5c8fb4 # owner unknown
#     amount=1000, utxo=6f6343401fc57c3f6a30043c61023e62311ee2b5d321823843af9cbcbfb2ac7e:1, witness=~ # owner unknown
```

Since the `outpoint_receive` was blinded during invoice generation, the payer
has no information on where the asset was allocated by the transfer, so the
receiver's allocation is not visible in the contract state on the sender's
side.


[BDK]: https://github.com/bitcoindevkit/bdk-cli
[RGB HTTP JSON-RPC]: https://github.com/RGB-Tools/rgb-http-json-rpc
[RGB proxy]: https://github.com/RGB-Tools/rgb-proxy-server
[St333p]: https://github.com/St333p
[cargo]: https://github.com/rust-lang/cargo
[docker compose]: https://docs.docker.com/compose/install/
[docker]: https://docs.docker.com/get-docker/
[git]: https://git-scm.com/downloads
[grunch]: https://github.com/grunch
[guide]: https://grunch.dev/blog/rgbnode-tutorial/
[rgb-contracts]: https://github.com/RGB-WG/rgb
