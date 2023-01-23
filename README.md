RGB Sandbox
===

## Introduction
This is an RGB sandbox and demo based on RGB version 0.8.x.
It is based on the previous rgb-node 0.4.x demo and the original rgb-node demo
by [St333p] (version 0.1) and [grunch]'s [guide].

Please note that later RGB versions will contain braking changes so might be
incompatible with this demo.

It runs in Docker using Rust 1.66 on Debian bullseye. The underlying Bitcoin
network is `regtest`.

The used RGB components are:
- [rgb-cli]
- [rgb-node]
- [rgb-std]
- [rgb20]
- [store_daemon]

[BDK] is used for walleting.

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
Clone the repository:
```sh
git clone https://github.com/RGB-Tools/rgb-sandbox
```

The default setup assumes the user and group IDs are `1000`. If that's not the
case, the `MYUID` and `MYGID` environment variables  in the
`docker-compose.yml` file need to be updated accordingly.

The automated demo does not require any other setup steps.

The manual version requires handling of data directories and services, see the
[dedicated section](#data-and-service-management) for instructions.

### Requirements
- [git]
- [docker]
- [docker-compose]

## Sandbox exploration
The services started with docker compose simulate a small network with a
bitcoin node, an explorer and three RGB nodes. These can be used to test and
explore the basic functionality of an RGB ecosystem.

Check out the manual demo below to get started with example commands. Refer to
each command's help documentation for additional information.

## Automated demo
To check out the automated demo, run:
```sh
bash demo.sh
```

The automated script will install `bdk-cli`, create empty service data
directories, start the required services, create Bitcoin wallets, generate
UTXOs, issue an asset, transfer some of it from the issuer to a first recipient
(twice, the second time spending sender's change), then transfer from the first
recipient to a second one and, finally, transfer all the assets received by the
second recipient back to the issuer.
On exit, the script will stop the services and remove the data directories.

For more verbose output during the automated demo, add the `-v` option (`bash
demo.sh -v`), which shows the commands being run on nodes and output from
additional commands.

The script by default uses "OP_RETURN" as closing method and "wpkh"
descriptors. "Tapret" closing method and taproot descriptors can be selected
passing the `tapret1st` and `tr` arguments:
```sh
bash demo.sh "tapret1st" "tr"
```

## Manual demo recording
Following the manual demo and rxecuting all the required steps is a rather long
and error-prone process.

To ease the task of following the steps, a recording of the manual demo
execution is available:
[![demo](https://asciinema.org/a/553660.svg)](https://asciinema.org/a/553660?autoplay=1)

## Manual demo
The manual demo shows how to issue an asset and transfer some tokens to a
recipient.

At the beginning of the demo, some shell command aliases and common variables
need to be set, then a series of steps are briefly described and illustrated
with example shell commands.

During each step, commands either use literal values, ones that the user needs
to fill in or variables. Some variables will be the ones set at the beginning
of the demo (uppercase), others need to be set based on the output of the
commands as they are run (lowercase).

Values that need to be filled in with command output follow the command that
produces it and the example value is truncated (ends with `...`), meaning the
instruction should not be copied verbatim and the value should instead be
replaced with the actual output received while following the demo.

### Data and service management
Create data directories and start the required services in Docker containers:
```sh
# create service data directories
mkdir data{0,1,2,core,index}

# run containers (first time takes a while to download/build docker images...)
docker-compose up -d
```

To get a list of the running services you can run:
```sh
docker-compose ps
```

To get their respective logs you can run, for instance:
```sh
docker-compose logs rgb-node-0
```

Once finished and in order to clean up containers and data to start the demo
from scratch, run:
```sh
docker-compose down               # stop and remove running containers
rm -fr data{0,1,2,core,index}     # remove service data directories
```

### Premise
RGB-node does not handle wallet-related functionality, it just performs
RGB-specific tasks over data that will be provided by an external wallet, such
as BDK. In particular, in order to demonstrate a basic workflow with issuance
and transfer, we will need:
- an *outpoint_issue* to which `rgb-node-0` will allocate the new asset
  issuance
- an *outpoint_change* on which `rgb-node-0` will send the asset change
- an *outpoint_receive* on which `rgb-node-1` will receive the asset transfer
- a partially signed bitcoin transaction (PSBT) where a commitment to the
  transfer will be anchored

### bdk-cli installation
RGB wallets will be handled with BDK. We install its CLI to the `bdk-cli`
directory inside the demo's directory:
```sh
cargo install bdk-cli --version "0.6.0" --root "./bdk-cli" --features electrum
```

### Demo
We setup aliases to ease calls to command-line interfaces:
```sh
alias bcli='docker-compose exec -u blits bitcoind bitcoin-cli -regtest'
alias bdk='bdk-cli/bin/bdk-cli'
alias rgb0-rgb20='docker-compose exec -u rgb rgb-node-0 rgb20 -n regtest'
alias rgb0-cli='docker-compose exec -u rgb rgb-node-0 rgb-cli -n regtest'
alias rgb1-cli='docker-compose exec -u rgb rgb-node-1 rgb-cli -n regtest'
alias rgb0-std='docker-compose exec -u rgb rgb-node-0 rgb'
alias rgb1-std='docker-compose exec -u rgb rgb-node-1 rgb'
```

We set some environment variables:
```sh
CLOSING_METHOD="opret1st"
DERIVE_PATH="m/86'/1'/0'/0"
DESC_TYPE="wpkh"
ELECTRUM="localhost:50001"
ELECTRUM_DOCKER="electrs:50001"
CONSIGNMENT="consignment.rgbc"
PSBT="tx.psbt"
TRANSITION="transition.rgbt"
```
Note: to use "tapret" instead of "OP_RETURN", set `CLOSING_METHOD` to `tapret1st`
and `DESC_TYPE` to `tr`.

We prepare the wallets using Bitcoin Core and BDK:
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
#   "fingerprint": "afa06284",
#   "mnemonic": "craft kick idle universe diary vehicle poverty gospel yard process cannon old glide good immune anchor measure clerk spare access teach glad turkey loud",
#   "xprv": "tprv8ZgxMBicQKsPf432U5UZM5BoUsRzMXd6NG2gNnmWvkVK17a5s8BNbgD5Hi9ReiRfz7Zy6qdtZr99SHnXtAJKpr9ZY2HxiL5H2Ayz4b7J7zw"
# }
xprv_0="tprv8Zgx..."

bdk key derive -p $DERIVE_PATH -x "$xprv_0"
# example output:
# {
#   "xprv": "[afa06284/86'/1'/0'/0]tprv8iDEmpUvczBeUoSf51E7EU6DS4oyWsYogoh7gncmdbk6MYcHT36cSSTs8KfoJSckFfrThWAK7cPYETDRh2JN2DZHdZdPQgjxEFdjHo4a8SP/*",
#   "xpub": "[afa06284/86'/1'/0'/0]tpubDEuGvEXAmMsKNGUSxethdskL16KugCjiG7HtyJf53sYVC2s45RvCcw5jJUoa5pRwCET4WjRUCp5gXog9Nsiis8xRQBQ5XFS1RUzGRY26WLc/*"
# }
xprv_der_0="[afa06284/86'/1'/0'/0]tprv8iDE...",
xpub_der_0="[afa06284/86'/1'/0'/0]tpubDEuG..."

# receiver BDK wallet
bdk key generate
# example output:
# {
#   "fingerprint": "9a7b1bf5",
#   "mnemonic": "dad must child immense minor oyster slam usage marine stable fancy infant frame violin coach boat raven quit goose sure sunset ranch today regret",
#   "xprv": "tprv8ZgxMBicQKsPfMrcJc4pkx4wzobd2YJd7q1rYeeMnBJqM3REDbSvj683nAFTQqwQZKSeT6fwuU6ke7bg6hTjCusjdms4S8wojbCWuKKccfF"
# }
xprv_1="tprv8Zgx..."

bdk key derive -p $DERIVE_PATH -x "$xprv_1"
# example output:
# {
#   "xprv": "[9a7b1bf5/86'/1'/0'/0]tprv8iChT3XXpryQSXMEdTHyVkjerUVDsJ43ovDDRVmHgiiZEiqBMqWLegjDqGxoDrHE1CuNTsMBygMF1P6yubifzUx9sFNAWdKAoDxY8eE6Q4Q/*",
#   "xpub": "[9a7b1bf5/86'/1'/0'/0]tpubDEtjbTZmyEf5KzP2X6xZuAPmRW1A2dExPDozi1ob6zWx5D5wzEKvqBM61PEfVDqZsNPxveUQe5pozi5qV2kgapDfJqrpKdrK9BQoUTW2poB/*"
# }
xprv_der_1="[9a7b1bf5/86'/1'/0'/0]tprv8iChT3XX...",
xpub_der_1="[9a7b1bf5/86'/1'/0'/0]tpubDEtjbTZm..."

# fund RGB wallets
bdk -n regtest wallet -w issuer -d "$DESC_TYPE($xpub_der_0)" get_new_address
# example output:
# {
#   "address": "bcrt1qsylsdz0kqqnac7ev5s26s5hlg7ws8hhlm4227q"
# }
addr_issue="bcrt1qsy..."

bdk -n regtest wallet -w issuer -d "$DESC_TYPE($xpub_der_0)" get_new_address
# example output:
# {
#   "address": "bcrt1qu0lcz4qttluznfhrt89agwq7zy46ge0kyr38u8"
# }
addr_change="bcrt1qu0..."

bdk -n regtest wallet -w receiver -d "$DESC_TYPE($xpub_der_1)" get_new_address
# example output:
# {
#   "address": "bcrt1qzf7396x7q4kfh496y0jemh5m32qqefv3h3j6al"
# }
addr_receive="bcrt1qzf..."

bcli -rpcwallet=miner sendtoaddress $addr_issue 2
bcli -rpcwallet=miner sendtoaddress $addr_change 2
bcli -rpcwallet=miner sendtoaddress $addr_receive 2
bcli -rpcwallet=miner -generate 1

# sync wallets
bdk -n regtest wallet -w issuer -d "$DESC_TYPE($xpub_der_0)" -s $ELECTRUM sync
bdk -n regtest wallet -w receiver -d "$DESC_TYPE($xpub_der_1)" -s $ELECTRUM sync

# list wallet unspents to gather the outpoints
bdk -n regtest wallet -w issuer -d "$DESC_TYPE($xpub_der_0)" list_unspent
# example output:
# [
#   {
#     "is_spent": false,
#     "keychain": "External",
#     "outpoint": "bf08fd8fd48aa7e1f53185124e0d2f0082c057c6c638f03bea92527e5be3e8cd:1",
#     "txout": {
#       "script_pubkey": "0014813f0689f60027dc7b2ca415a852ff479d03deff",
#       "value": 200000000
#     }
#   },
#   {
#     "is_spent": false,
#     "keychain": "External",
#     "outpoint": "d67e0e08728603e2d8ad077bb1f14b28316e2f6597c277962d2813327a95ed2f:1",
#     "txout": {
#       "script_pubkey": "0014e3ff81540b5ff829a6e359cbd4381e112ba465f6",
#       "value": 200000000
#     }
#   }
# ]

bdk -n regtest wallet -w receiver -d "$DESC_TYPE($xpub_der_1)" list_unspent
# example output:
# [
#   {
#     "is_spent": false,
#     "keychain": "External",
#     "outpoint": "b2dc02697554c9db147895b41f5e55e07730b8211c2147d35f1152a38582807d:0",
#     "txout": {
#       "script_pubkey": "0014127d12e8de056c9bd4ba23e59dde9b8a800ca591",
#       "value": 200000000
#     }
#   }
# ]
```

From the above we get the following outpoints:
```sh
outpoint_issue="bf08fd8f..."
outpoint_change="d67e0e08..."
outpoint_receive="b2dc0269..."
```

#### Asset issuance
To issue an asset, run:
```sh
rgb0-rgb20 issue -m $CLOSING_METHOD USDT "USD Tether" 1000@$outpoint_issue
# example output:
# Contract ID: rgb1znn5xh7g33u4cseg27uz5mzma58rr98tlpfxp75l0e783my8hx0qcx0jsj
#
# Contract YAML:
# ---
# schema_id: rgbsh18kp34t5nn5zu4hz6g7lqjdjskw8aaf84ecdntrtrdvzs7gn3rnzskscfq8
# chain:
#   regtest: 0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206
# metadata:
#   0:
#     - AsciiString: USDT
#   1:
#     - AsciiString: USD Tether
#   3:
#     - U8: 8
#   4:
#     - I64: 1673358389
#   160:
#     - U64: 1000
# owned_rights:
#   161:
#     value:
#       - revealed:
#           seal:
#             method: OpretFirst
#             txid: bf08fd8fd48aa7e1f53185124e0d2f0082c057c6c638f03bea92527e5be3e8cd
#             vout: 1
#             blinding: 15804704581054809064
#           state:
#             value: 1000
#             blinding: "0000000000000000000000000000000000000000000000000000000000000001"
# public_rights: []
#
# Contract JSON:
# {"schema_id":"rgbsh18kp34t5nn5zu4hz6g7lqjdjskw8aaf84ecdntrtrdvzs7gn3rnzskscfq8","chain":{"regtest":"0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206"},"metadata":{"0":[{"AsciiString":"USDT"}],"1":[{"AsciiString":"USD Tether"}],"3":[{"U8":8}],"4":[{"I64":1673358389}],"160":[{"U64":1000}]},"owned_rights":{"161":{"value":[{"revealed":{"seal":{"method":"OpretFirst","txid":"bf08fd8fd48aa7e1f53185124e0d2f0082c057c6c638f03bea92527e5be3e8cd","vout":1,"blinding":15804704581054809064},"state":{"value":1000,"blinding":"0000000000000000000000000000000000000000000000000000000000000001"}}}]}},"public_rights":[]}
#
# Contract source:
# rgbc1qxz4yjeg03g33llwadhlu84erc4eg62kk2g5fukcypmgs2epc2vfs6xyr3jjtyvjj2ctpgtx2r983rnycky9pz54z4ft9xfgkxvgmc36muul0r55htnhvlh80dl7wl8hqltykpqm6sxfrkn7k7rcsgyqpndtpwut8fx9zqzsa42twct562tcqg9p9nfemc4ryrkjpmxj3j04ysg6qc9r2jf7pflt44cpq2v2dvx6ucnnr9qel23ryvqdgrtl6rxhnyz4wrzrtega0u2y8776y2ser60zml02vfdqzl92mxrelw3wlhvuntczhveudzwq45qu8dave2cvx09m43pfqe0wr92s85vng7h63zk36y4ywdz7v4nvy29sz8lrmrgqjwklemq0j782wmwd9u5e0a7d24rl7zm27anpu43r6l5ln57wtcjazvvswynvqghuwduz4y7ju2dzadunm0947kjztxnn23td08vej97pswf00jwecsvpsar4zwtewlyy7eh68zsg53ea8vlpx8rskr536d9qv54xjhrcx35ra3jkac4y5scrgmc8a8mldw8pxxp9fvrvfn4h9j4uetg9qhapuxj9uc63k34ja5hrrfzq4qgddxfe9hmharzf5wr098xpnswfctn8c9t7dgv6nxmm9elzk0pldu7paquusn4wfzwuer3a44xdejnjmpp0pz0ead9x9c6dexweze9l3tt7qvka6hgx
contract_id="rgb1znn5..."
contract_source="rgbc1qxz..."
```
This will create a new genesis that includes asset metadata and the allocation
of the initial amount to the `outpoint_issue`.

Register the newly created contract with rgb-node:
```sh
rgb0-cli contract register $contract_source
```

You can list known fungible assets:
```sh
rgb0-cli contract list
```

You can show the current known state for the contract:
```sh
rgb0-cli contract state $contract_id
# example output:
# Querying state of rgb1znn5xh7g33u4cseg27uz5mzma58rr98tlpfxp75l0e783my8hx0qcx0jsj...
# schema_id: rgbsh18kp34t5nn5zu4hz6g7lqjdjskw8aaf84ecdntrtrdvzs7gn3rnzskscfq8
# root_schema_id: null
# contract_id: rgb1znn5xh7g33u4cseg27uz5mzma58rr98tlpfxp75l0e783my8hx0qcx0jsj
# metadata:
#   9eb987ec787c7e9ffa6052f8eb94310eed5b6c2ab85728435c798cc85f43e714:
#     0:
#     - USDT
#     1:
#     - USD Tether
#     3:
#     - '8'
#     4:
#     - '1673358389'
#     160:
#     - '1000'
# owned_rights: []
# owned_values:
# - 1000#0000000000000000000000000000000000000000000000000000000000000001@bf08fd8fd48aa7e1f53185124e0d2f0082c057c6c638f03bea92527e5be3e8cd:1
# owned_data: []
# owned_attachments: []
```

#### Transfer

#### Receiver: generate blinded UTXO
In order to receive some assets, `rgb-node-1` needs to provide `rgb-node-0`
with a `blinded_utxo`. To do so we blind the `outpoint_receive`:
```sh
rgb1-std blind -m $CLOSING_METHOD $outpoint_receive
# example output:
# txob10xwkaqrqsyn7gv6guz8myfxzlh9dha6f6yfgjdf0nwaspvrk9ghss5npr8
# Blinding factor: 571637893965646
blinded_utxo="txob10xw..."
blinding_factor="57163789..."
```
This also gives us the `blinding_factor` that will be needed later on, in order
to accept the transfer related to this outpoint.

#### Sender: initiate asset transfer
To send some assets to a `blinded_utxo`, `rgb-node-0` needs to create a
consignment and commit to it into a bitcoin transaction. So we will need a
partially signed bitcoin transaction that we will modify to include the
commitment.

Generate a new address for the bitcoin (non-asset) portion of the transaction:
```sh
bdk -n regtest wallet -w issuer -d "$DESC_TYPE($xpub_der_0)" get_new_address
# example output:
# {
#   "address": "tb1q53xthr0wc7x6s8kemzzdwl0stk66tkdrdld8ac"
# }
addr_change="tb1q53xt..."
```

Create the initial PSBT, specifying the `outpoint_issue` as input and the
freshly generated `addr_change` address as output, then write it to a file and
make it available to `rgb-node-0`:
```sh
bdk -n regtest wallet -w issuer -d "$DESC_TYPE($xpub_der_0)" create_tx \
  --enable_rbf --send_all -f 5 --utxos $outpoint_issue --to $addr_change:0
# example output:
# {
#   "details": {
#     "confirmation_time": null,
#     "fee": 550,
#     "received": 199999450,
#     "sent": 200000000,
#     "transaction": null,
#     "txid": "f947289e0736a6938d87428d30c81a00a661d83e5155a25d999585e2728097a4"
#   },
#   "psbt": "cHNidP8BAFIBAAAAAc3o41t+UpLqO/A4xsZXwIIALw1OEoUx9eGnitSP/Qi/AQAAAAD9////Adq/6wsAAAAAFgAUpEy7je7Hjage2diE133wXbWl2aNpAAAAAAEA3gIAAAAAAQGidTUaFjDK9wgFBj6zYZm7t5Jdlakw3EnmU0eNsTDLPgAAAAAA/v///wL8JBoeAQAAABYAFOoMGDGc+P0anr4szrq8JS95HFe7AMLrCwAAAAAWABSBPwaJ9gAn3HsspBWoUv9HnQPe/wJHMEQCIADfi5GJ321H2aY7AOndk4QWzmvxO5ZFjih2wISMWTYUAiAIerdX0VIDXKQvUZS9DdTREn+XIl3hV96FbCw3C3nFEgEhA2Vm3vOJZoCxv0hEJi+8FFSGUL3eIaqo+kIvT6niczrRZwAAAAEBHwDC6wsAAAAAFgAUgT8GifYAJ9x7LKQVqFL/R50D3v8iBgOSTtLuaFetpfJt6+GgeoBPKk+KNXqeCKbi7Eb+X7dwTRivoGKEVgAAgAEAAIAAAACAAAAAAAEAAAAAIgICfHFDbv+YAW1oNvNJlqB54CrDEa6rFwrKOr1irWg+eS4Yr6BihFYAAIABAACAAAAAgAAAAAADAAAAAA=="
# }
echo "cHNidP8B..." | base64 -d > tx.psbt

cp $PSBT data0/
```

Initiate the transfer by creating the consignment and state transition files
(required data: contract ID, outpoint to be spent and for the change, blinded
UTXO, names for consignment and transition files, send and change amounts and
closing method):
```sh
# build the draft consignment for the transfer
rgb0-cli transfer compose $contract_id $outpoint_issue $CONSIGNMENT
# example output:
# Composing consignment for state transfer for contract rgb1znn5xh7g33u4cseg27uz5mzma58rr98tlpfxp75l0e783my8hx0qcx0jsj...
# Task forwarded to bucket daemon
# Saving consignment to consignment_compose.rgbc
# Success

# validate the generated consignment
rgb0-std consignment validate $CONSIGNMENT $ELECTRUM_DOCKER
# example output:
# unresolved_txids: []
# unmined_endpoint_txids: []
# failures: []
# warnings: []
# info: []

# inspect the generated consignment (debug output)
rgb0-std consignment inspect -f debug $CONSIGNMENT

# prepare the state transition for the transfer
rgb0-rgb20 transfer --utxo $outpoint_issue \
  --change 900@$CLOSING_METHOD:$outpoint_change \
  $CONSIGNMENT 100@$blinded_utxo $TRANSITION
# example output:
# ---
# transition_type: 0
# metadata: {}
# parent_owned_rights:
#   9eb987ec787c7e9ffa6052f8eb94310eed5b6c2ab85728435c798cc85f43e714:
#     161:
#       - 0
# owned_rights:
#   161:
#     value:
#       - revealed:
#           seal:
#             method: OpretFirst
#             txid: d67e0e08728603e2d8ad077bb1f14b28316e2f6597c277962d2813327a95ed2f
#             vout: 1
#             blinding: 1888680781681793083
#           state:
#             value: 900
#             blinding: 7262cf789dbf09dd40f8f5571b106fbdaab825a3e45b043d9e8340cb8179008b
#       - confidential_seal:
#           seal: txob10xwkaqrqsyn7gv6guz8myfxzlh9dha6f6yfgjdf0nwaspvrk9ghss5npr8
#           state:
#             value: 100
#             blinding: 8d9d30876240f622bf070aa8e4ef90410ff6b742caed9bfe214f1dc14ebd40b7
# parent_public_rights: {}
# public_rights: []
#
# Success
```

Embed contract information into the PSBT:
```sh
rgb0-cli contract embed $contract_id $PSBT
# example output:
# Embedding rgb1znn5xh7g33u4cseg27uz5mzma58rr98tlpfxp75l0e783my8hx0qcx0jsj into PSBT...
# Task forwarded to bucket daemon
```

Add state transition information to the PSBT:
```sh
rgb0-cli transfer combine $contract_id $TRANSITION $PSBT $outpoint_issue
# example output:
# Preparing PSBT for the state transfer...
# Task forwarded to bucket daemon
```

Finalize RGB bundle information in the PSBT:
```sh
rgb0-std psbt bundle -m $CLOSING_METHOD $PSBT
# example output:
# Total 1 bundles converted

# analyze the resulting (final) PSBT
rgb0-std psbt analyze $PSBT
```

Finalize the consignment:
```sh
rgb0-cli transfer finalize \
    --endseal $blinded_utxo $PSBT $CONSIGNMENT
# example output:
# Finalizing state transfer...
# Task forwarded to bucket daemon
```

#### Consignment exchange
For the purpose of this demo, copying the file over to the receiving node's
data directory is sufficient:
```sh
cp data{0,1}/$CONSIGNMENT
```

In real-world scenarios, consignments are exchanged either via [Storm] or [RGB
HTTP JSON-RPC] (e.g. using an [RGB proxy])

#### Receiver: validate transfer
Before a transfer can be accepted, it needs to be validated:
```sh
rgb1-std consignment validate $CONSIGNMENT $ELECTRUM_DOCKER
# example output:
# unresolved_txids: []
# unmined_endpoint_txids:
# - 001216558680ea34af86cf7f50631ccfde05c0f3eb0007af442849f736a3aa3e
# failures: []
# warnings:
# - !EndpointTransactionMissed 001216558680ea34af86cf7f50631ccfde05c0f3eb0007af442849f736a3aa3e
# info: []
```

The transfer is valid if no `failures` are reported. It is normal at this stage
for a transaction to show up in the `unresolved_txids` list, as that's the
transaction that has not yet been broadcast, as the sender is waiting for
approval from the recipient.

At this point the recipient approves the transfer (for the demo let's just
assume it happened, in a real-world scenario an [RGB proxy] can be used).

#### Sender: sign and broadcast transaction
With rhe receiver's approval of the transfer, the transaction can be signed and
broadcast:
```sh
bdk -n regtest wallet -w issuer -d "$DESC_TYPE($xprv_der_0)" \
    sign --psbt $(base64 -w0 data0/$PSBT)
# example output:
# {
#   "is_finalized": true,
#   "psbt": "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"
# }
psbt_signed="cHNidP8B..."

bdk -n regtest wallet -w issuer -d "$DESC_TYPE($xpub_der_0)" -s $ELECTRUM \
    broadcast --psbt "$psbt_signed"
# example output:
# {
#   "txid": "001216558680ea34af86cf7f50631ccfde05c0f3eb0007af442849f736a3aa3e"
# }

# confirm the transaction
bcli -rpcwallet=miner -generate 1
```

#### Receiver: consume transfer
Once the transaction has been confirmed it's time to accept the incoming
transfer.

Let's first validate the transfer again and confirm the transaction ID doesn't
show up as unmined anymore:
```sh
rgb1-std consignment validate $CONSIGNMENT $ELECTRUM_DOCKER
# example output:
# unresolved_txids: []
# unmined_endpoint_txids: []
# failures: []
# warnings: []
# info: []
```

To complete the transfer and see the new allocation in the contract state, the
receiver needs to consume the consignment, using the `outpoint_receive` and the
corresponding `blinding_factor` generated during UTXO blinding:
```sh
rgb1-cli transfer consume $CONSIGNMENT \
    --reveal "$CLOSING_METHOD@$outpoint_receive#$blinding_factor"
# example output:
# Verifying and consuming state transfer...
# A new bucket daemon instance is started
# Success: contract is valid and imported

rgb1-cli contract state $contract_id
# example output:
# Querying state of rgb1znn5xh7g33u4cseg27uz5mzma58rr98tlpfxp75l0e783my8hx0qcx0jsj...
# ...
# owned_rights: []
# owned_values:
# - 900#7262cf789dbf09dd40f8f5571b106fbdaab825a3e45b043d9e8340cb8179008b@d67e0e08728603e2d8ad077bb1f14b28316e2f6597c277962d2813327a95ed2f:1
# - 100#8d9d30876240f622bf070aa8e4ef90410ff6b742caed9bfe214f1dc14ebd40b7@b2dc02697554c9db147895b41f5e55e07730b8211c2147d35f1152a38582807d:0
# owned_data: []
# owned_attachments: []
```

##### Sender: consume transfer
The contract state (`rgb0-cli contract state $contract_id`) on the sender side
still shows the issuance allocation. To have the RGB node see the new change
allocation the transfer needs to be consumed:
```sh
rgb0-cli contract state $contract_id
# example output:
# Querying state of rgb1znn5xh7g33u4cseg27uz5mzma58rr98tlpfxp75l0e783my8hx0qcx0jsj...
# ...
# owned_rights: []
# owned_values:
# - 1000#0000000000000000000000000000000000000000000000000000000000000001@bf08fd8fd48aa7e1f53185124e0d2f0082c057c6c638f03bea92527e5be3e8cd:1
# owned_data: []
# owned_attachments: []

rgb0-cli transfer consume $CONSIGNMENT
# example output:
# Verifying and consuming state transfer...
# Task forwarded to bucket daemon
# Success: contract is valid and imported

rgb0-cli contract state $contract_id
# example output:
# Querying state of rgb1znn5xh7g33u4cseg27uz5mzma58rr98tlpfxp75l0e783my8hx0qcx0jsj...
# ...
# owned_rights: []
# owned_values:
# - 900#7262cf789dbf09dd40f8f5571b106fbdaab825a3e45b043d9e8340cb8179008b@d67e0e08728603e2d8ad077bb1f14b28316e2f6597c277962d2813327a95ed2f:1
# owned_data: []
# owned_attachments: []
```

Since the `outpoint_receive` was blinded during the transfer, the payer has
no information on where the asset was allocated after the transfer, so the
receiver's allocation is not visible in the contract state on the sender side.

[BDK]: https://github.com/bitcoindevkit/bdk-cli
[RGB HTTP JSON-RPC]: https://github.com/RGB-Tools/rgb-http-json-rpc
[RGB proxy]: https://github.com/grunch/rgb-proxy-server
[St333p]: https://github.com/St333p
[Storm]: https://github.com/Storm-WG/storm-spec
[docker-compose]: https://docs.docker.com/compose/install/
[docker]: https://docs.docker.com/get-docker/
[git]: https://git-scm.com/downloads
[grunch]: https://github.com/grunch
[guide]: https://grunch.dev/blog/rgbnode-tutorial/
[rgb-cli]: https://github.com/RGB-WG/rgb-node/tree/v0.8/cli
[rgb-node]: https://github.com/RGB-WG/rgb-node
[rgb-std]: https://github.com/RGB-WG/rgb-std
[rgb20]: https://github.com/RGB-WG/rust-rgb20
[store_daemon]: https://github.com/Storm-WG/storm-stored
