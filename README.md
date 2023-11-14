RGB Sandbox
===

## Introduction
This is an RGB sandbox and demo based on RGB version 0.11 beta 5.

The underlying Bitcoin network is `regtest`.

RGB is operated via the [rgb-wallet] crate. [descriptor-wallet] is used for
walleting.

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
Clone the repository, including (shallow) submodules and change to the
newly-created directory:
```sh
git clone https://github.com/RGB-Tools/rgb-sandbox --recurse-submodules --shallow-submodules
cd rgb-sandbox
```

The automated demo does not require any other setup steps.

The manual version requires handling of data directories and services, see the
[dedicated section](#data-and-service-management) for instructions.

Both versions will leave `descriptor-wallet` and `rgb-wallet` installed, in the
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
bitcoin node and an indexer. These can be used to support testing and
exploring the basic functionality of an RGB ecosystem.

The indexer can either be electrum or esplora. The default for the automated
demo and the one used in the manual demo is electrum.

Check out the manual demo below to get started with example commands. Refer to
each command's help documentation for additional information.

## Automated demo
To check out the automated demo, run:
```sh
bash demo.sh
```

The automated script will install the required rust crates, cleanup and create
empty data directories, start the required services, prepare the wallets,
issue assets, execute a series of asset transfers, then stop the services and
remove the data directories.

For more verbose output during the automated demo, add the `-v` option (`bash
demo.sh -v`), which shows the commands being run and additional
information (including output from additional inspection commands).

To use esplora instead of electrum as indexer, add the `--esplora` option.

The automated demo also supports scenarios that can be selected via the `-s`
option. The default scenario is `0`, which has been described above using the
`opret1st` closing method for all operations, but `1` is also available (`bash
demo.sh -s 1`) to run the same operations using the `tapret1st` closing method.

Multiple scenarios can also be executed in a single run with the `scenarios.sh`
script (`bash scenarios.sh 0 1`). This script will run all the specified
scenarios, save the logs of each scenario in a separate file under the `logs`
directory and give a final report on which scenarios succeeded or failed.

## Manual demo

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
Start the required services in Docker containers:
```sh
# missing docker images will be downloaded
docker compose --profile electrum up -d
```

To get a list of the running services you can run:
```sh
docker compose ps
```

To get their respective logs you can run, for instance:
```sh
docker compose logs bitcoind
```

Once finished, in order to clean up services and data to start the demo
from scratch, run:
```sh
# stop services, remove containers and volumes
docker compose --profile electrum down -v

# remove data directories and generated files
rm -fr data{0,1} wallets consignment.yaml contracts/usdt.yaml
```

To also remove installed crates run:
```sh
rm -r descriptor-wallet rgb-wallet
```

### Premise
The rgb-wallet CLI tool does not handle bitcoin-related functionality, it
performs RGB-specific tasks over data that is provided by an external bitcoin
wallet, such as descriptor-wallet. In particular, in order to demonstrate a
basic workflow with issuance and transfer, from the bitcoin wallets we will
need:
TODO
- an *outpoint_issue* to which the issuer will allocate the new asset
- an *outpoint_receive* where the recipient will receive the asset transfer
- an *addr_change* where the sender will receive the bitcoin and asset change
- a partially signed bitcoin transaction (PSBT) to anchor the transfer

### descriptor-wallet installation
Bitcoin walleting will be handled with descriptor-wallet. We install its CLI to
the `descriptor-wallet` directory inside the project directory:
```sh
cargo install descriptor-wallet --version 0.10.2 --root ./descriptor-wallet --all-features --debug
```

### rgb-wallet installation
RGB functionality will be handled with `rgb-wallet`. We install its CLI to the
`rgb-wallet` directory inside the project directory:
```sh
cargo install rgb-wallet --version 0.11.0-beta.5 --root ./rgb-wallet
```

### Demo
#### Initial setup
We setup aliases to ease CLI calls:
```sh
alias bcli="docker compose exec -u blits bitcoind bitcoin-cli -regtest"
alias btccold="descriptor-wallet/bin/btc-cold"
alias btchot="descriptor-wallet/bin/btc-hot"
alias rgb0="rgb-wallet/bin/rgb -n regtest --electrum localhost:50001 -d data0 -w issuer"
alias rgb1="rgb-wallet/bin/rgb -n regtest --electrum localhost:50001 -d data1 -w rcpt1"
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
INTERFACE_DIR="rgb-schemata/interfaces"
SCHEMATA_DIR="rgb-schemata/schemata"
WALLET_PATH="wallets"
```

We prepare the Bitcoin core wallet:
```sh
# Bitcoin Core wallet
bcli createwallet miner
bcli -generate 103
```

If there are left-over wallets from previous runs, they need to be removed:
```sh
rm -fr $WALLET_PATH
```

We create the directory to hold bitcoin wallet files:
```sh
mkdir $WALLET_PATH
```

We prepare the issuer/sender and receiver bitcoin wallets:
```sh
# issuer/sender wallet
btchot seed -p '' "$WALLET_PATH/0.seed"
# example output:
# Master key:
#   - fingerprint:   44ff6cd2
#   - id:            44ff6cd2846fd0e42cdb532ebc4cb97aed56dd4b
#   - xpub mainnet:  xpub661MyMwAqRbcGLre12hSzG9JkjehrjU6XrpHRqRiLDvd18EHe2krPFhVPgHW3p9GmVPREx3LAieWy9hA118J17faSPsngQK7jmZipDV5ewW
#   - xpub testnet:  tpubD6NzVbkrYhZ4Y93VTDgYCBUg5rkMr7yA5VQanPUrg8gWkQtziFbwXhNKdiNHaK6WZPvKrXZChpUZfLBmPryXtZ7sVzd6MvyMKjA8aAxfsQy

btchot derive -s bip86 --testnet --seed-password '' --account-password '' \
  "$WALLET_PATH/0.seed" "$WALLET_PATH/0.derive"
# example output:
# Account:
#   - fingerprint:   524975d1
#   - id:            524975d17986cb5e8ab5cf86ddec4b146be6611a
#   - derivation:    m=[44ff6cd2]/86'/1'/0'
#   - xpub:          tpubDDA4WpAzm75zi7eKjuWKxUB7b9V16UHqhApMFeFfPxremDC3J1j4XQXXBLJjSQXzv8GhHnDvbTVNU2xPYgynWiTutaKsypezTA2WuNNubAN
# Recommended wallet descriptor:
# tr([44ff6cd2/86h/1h/0h]tpubDDA4WpAzm75zi7eKjuWKxUB7b9V16UHqhApMFeFfPxremDC3J1j4XQXXBLJjSQXzv8GhHnDvbTVNU2xPYgynWiTutaKsypezTA2WuNNubAN/*/*)#97nxrfcc

descriptor_0="tr([44ff6cd2/86h/1h/0h]tpubDDA4...rfcc"

# receiver wallet
btchot seed -p '' "$WALLET_PATH/1.seed"
# example output:
# Master key:
#   - fingerprint:   1eeadfa5
#   - id:            1eeadfa5f084acece58580aa34911d5e529407ee
#   - xpub mainnet:  xpub661MyMwAqRbcFXdrqXuC1q3gSYnV1C9Jx61ByDooJM3PWJYSqbkqHHop8if8VPnXBzSV58kgJUQxXeW1jKGhnG2q5n7TGF9c6H95AESq3gC
#   - xpub testnet:  tpubD6NzVbkrYhZ4XKpiHitHDkP3mft8zaeNVibVKmrweFoHFbD9upbvRjUeNkjv1tjkytyPgiGYqaF1Dpzd8B7wfhV89NrkwmoqgEjUvFCjrbU

btchot derive -s bip86 --testnet --seed-password '' --account-password '' \
  "$WALLET_PATH/1.seed" "$WALLET_PATH/1.derive"
# example output:
# Account:
#   - fingerprint:   9d517038
#   - id:            9d517038d9980a74dd84d0cb0da9bda005d5d0a3
#   - derivation:    m=[1eeadfa5]/86'/1'/0'
#   - xpub:          tpubDCSNRAwWUnx8wnCZEXMjMxG4zb9vQZhKTztmQojovDrqjMayjCMML4PMFkQyr8R66pbSkbNMJfDth1GihcFw1mU1GZf2yyQpqRcuG4Rbo4x
# Recommended wallet descriptor:
# tr([1eeadfa5/86h/1h/0h]tpubDCSNRAwWUnx8wnCZEXMjMxG4zb9vQZhKTztmQojovDrqjMayjCMML4PMFkQyr8R66pbSkbNMJfDth1GihcFw1mU1GZf2yyQpqRcuG4Rbo4x/*/*)#gd44a8uu

descriptor_1="tr([1eeadfa5/86h/1h/0h]tpubDCSN...a8uu"
```

We modify the descriptors to use the rgb-wallet expected syntax:
```sh
descriptor_0="$(echo $descriptor_0 | sed -e 's/^.*(//' -e 's/).*$//' -e 's#/\*/#/<0;1;9>/#')"
descriptor_1="$(echo $descriptor_1 | sed -e 's/^.*(//' -e 's/).*$//' -e 's#/\*/#/<0;1;9>/#')"
```

We setup the RGB wallets:
```sh
# issuer/sender
rgb0 create --wpkh $descriptor_0 issuer
# example output
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Unable to find or parse config file; using config defaults
# Loading descriptor from command-line argument ... success
# Syncing keychain 0 .......... keychain 1 .......... keychain 9 .......... success
# Saving the wallet as 'issuer' ... success

# receiver
rgb1 create --wpkh $descriptor_1 rcpt1
# example output
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Unable to find or parse config file; using config defaults
# Loading descriptor from command-line argument ... success
# Syncing keychain 0 .......... keychain 1 .......... keychain 9 .......... success
# Saving the wallet as 'rcpt1' ... success
```

We import interface and schema into the RGB wallets:
```sh
# issuer/sender
rgb0 import $INTERFACE_DIR/RGB20.rgb
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Unable to find or parse config file; using config defaults
# Loading descriptor from wallet issuer ... success
# Loading stock ... stock file is absent, creating a new one ... success
# Interface urn:lnp-bp:if:FYGtpt-fMCCitCg-Yo4Tru1X-MAaEkcKa-6inHR1Ji-bm8jtv#planet-avalon-diploma with name RGB20 imported to the stash

rgb0 import $SCHEMATA_DIR/NonInflatableAssets.rgb
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet issuer ... success
# Loading stock ... success
# Schema urn:lnp-bp:sc:2wFrMq-DQGYEXLx-YN5TgGiv-M7uxbA56-yqCtf7rd-MNTSvC#carol-politic-lima imported to the stash

rgb0 import $SCHEMATA_DIR/NonInflatableAssets-RGB20.rgb
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet issuer ... success
# Loading stock ... success
# Implementation urn:lnp-bp:im:9oYLiu-zqEukeiP-VDk73EQ2-yhSsyQXS-7tX8AU4J-qnnruH#salute-winter-provide of interface urn:lnp-bp:if:FYGtpt-fMCCitCg-Yo4Tru1X-MAaEkcKa-6inHR1Ji-bm8jtv#planet-avalon-diploma for schema urn:lnp-bp:sc:2wFrMq-DQGYEXLx-YN5TgGiv-M7uxbA56-yqCtf7rd-MNTSvC#carol-politic-lima imported to the stash


# receiver (same output as issuer/sender)
rgb1 import $INTERFACE_DIR/RGB20.rgb
rgb1 import $SCHEMATA_DIR/NonInflatableAssets.rgb
rgb1 import $SCHEMATA_DIR/NonInflatableAssets-RGB20.rgb
```

We retrieve the schema ID and set it as environment variable:
```sh
rgb0 schemata
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet issuer ... success
# Loading stock ... success
# urn:lnp-bp:sc:2wFrMq-DQGYEXLx-YN5TgGiv-M7uxbA56-yqCtf7rd-MNTSvC#carol-politic-lima

schema_id="urn:lnp-bp:sc:2wFrMq-DQG...litic-lima
```

We prepare the required UTXOs:
```sh
# generate addresses
rgb0 address -k 9
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet issuer ... success
#
# Term.   Address
# &9/0    bcrt1qum5l5me9tzfgw2flqvsdevmpk8uye9uh9ju56a

addr_issue="bcrt1qum..."

rgb1 address -k 9
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet rcpt1 ... success
#
# Term.   Address
# &9/0    bcrt1q0g4rh35ql7774da7mcup4p20dmrs429mhzj9rk

addr_receive="bcrt1q0g..."

# fund wallets
bcli -rpcwallet=miner sendtoaddress "$addr_issue" 1
bcli -rpcwallet=miner sendtoaddress "$addr_receive" 1
bcli -rpcwallet=miner -generate 1

# sync wallets and gather outpoints
rgb0 utxos --sync
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet issuer ... success
# Syncing keychain 0 .......... keychain 1 .......... keychain 9 ........... success
#
# Height     Amount, ṩ    Outpoint
# bcrt1qum5l5me9tzfgw2flqvsdevmpk8uye9uh9ju56a    &9/0
# mempool    100000000    ba8ff181e3ecd3800569a99f0807b4f309d71e12ba33dd8be428cf5f235a378c:1
#
# Loading descriptor from wallet issuer ... success
#
# Wallet total balance: 100000000 ṩ

outpoint_issue="ba8...78c:1"

rgb1 utxos --sync
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet rcpt1 ... success
# Syncing keychain 0 .......... keychain 1 .......... keychain 9 ........... success
#
# Height     Amount, ṩ    Outpoint
# bcrt1q0g4rh35ql7774da7mcup4p20dmrs429mhzj9rk    &9/0
# 104        100000000    252e3976b9b467eb232fa88bcbcff6b4a857eb31b2eb039d441d6e4fb5ddee51:1
#
# Loading descriptor from wallet rcpt1 ... success
#
# Wallet total balance: 100000000 ṩ

outpoint_receive="252...e51:1"
```

#### Asset issuance
To issue an asset, we first need to prepare a contract definition file, then
use it to actually carry out the issuance.

To prepare the contract file, we copy the provided template and modify the copy
to set the required data:
- issued supply
- closing method
- issuance txid and vout

We do this with a single command (which reads the template file, modifies the
given properties and writes the result to the contract definition file):
```sh
sed \
  -e "s/issued_supply/1000/" \
  -e "s/closing_method/$CLOSING_METHOD/" \
  -e "s/txid:vout/$outpoint_issue/" \
  contracts/usdt.yaml.template > contracts/usdt.yaml
```

To actually issue the asset, run:
```sh
rgb0 issue "$schema_id" contracts/usdt.yaml
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet issuer ... success
# Loading stock ... success
# A new contract rgb:RAfEnGH-vDNMgWuvU-HQUDo6DXj-NhUx3NFBa-Z7787tJgR-1KtBWp is issued and added to the stash.
# Use `export` command to export the contract.

contract_id="rgb:RAf...BWp"
```

This will create a new genesis that includes the asset metadata and the
allocation of the initial amount to `outpoint_issue`.

You can list known contracts:
```sh
rgb0 contracts
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet issuer ... success
# Loading stock ... success
# rgb:RAfEnGH-vDNMgWuvU-HQUDo6DXj-NhUx3NFBa-Z7787tJgR-1KtBWp
```

You can show the current known state for the contract:
```sh
rgb0 state "$contract_id" "$IFACE"
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet issuer ... success
# Loading stock ... success
# Global:
#   spec := (ticker=("USDT"), name=("USD Tether"), details=~, precision=0)
#   terms := (text=("demo NIA asset"), media=~)
#   issuedSupply := (1000)
#
# Owned:
#   assetOwner:
#     amount=1000, utxo=bc:opret1st:ba8ff181e3ecd3800569a99f0807b4f309d71e12ba33dd8be428cf5f235a378c:1, witness=~ # owned by the wallet
```

#### Transfer

##### Receiver: generate invoice
In order to receive assets, the receiver needs to provide an invoice to the
sender. The receiver generates an invoice providing the amount to be received
(here `100`) and the outpoint where the assets should be allocated:
```sh
rgb1 invoice "$contract_id" "$IFACE" 100
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet rcpt1 ... success
# Loading stock ... success
# rgb:RAfEnGH-vDNMgWuvU-HQUDo6DXj-NhUx3NFBa-Z7787tJgR-1KtBWp/RGB20/100+bcrt:utxob:upycyqp-ckvZmrFE7-ErgXriscJ-QX4MCXQuf-3D5Ef8DdS-smfFTb

invoice="rgb:RAf...BWp/RGB20/100+bcrt:utxob:upy...FTb"
```
Notes:
- this will blind the given outpoint and the invoice will contain a blinded
  UTXO in place of the original outpoint (see the `utxob:` part of the
  invoice)
- it is also possible to provide an address instead of a blinded UTXO and in
  that case the sender will allocate assets to an output of the transaction
  (the sender will need to also send some bitcoins to the provided address)

##### Sender: initiate asset transfer
To send assets, the sender needs to create a PSBT and a consignment, then
modify the PSBT to include a commitment to the consignment. The rgb-wallet
`prepare` command prepares the PSBT and the `consign` command handles
consignment preparation and commitment. The `transfer` command does both.

We create the transfer, providing the receiver's invoice and file names to save
the consignment and the PSBT.
```sh
rgb0 transfer --method $CLOSING_METHOD "$invoice" \
  "data0/$CONSIGNMENT" "data0/$PSBT"
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet issuer ... success
# Loading stock ... success
```

The consignment can be inspected by exporting it to yaml, but since the output
is very long it's best to send the output to a file:
```sh
rgb0 inspect "data0/$CONSIGNMENT" > consignment.yaml
```
To view the result, open the `consignment.yaml` file with a text viewer or
editor.

##### Consignment exchange
For the purpose of this demo, copying the file over to the receiver's data
directory is sufficient:
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
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# The provided consignment is valid
```

At this point the witness transaction not been broadcast yet, as the sender is
waiting for approval from the receiver.

Once validation has passed, the receiver can approve the transfer. For this
demo let's just assume it happened, in a real-world scenario an [RGB proxy]
would be typically used for this as well.

##### Sender: broadcast transaction
With the receiver's approval of the transfer, the transaction can be signed,
finalized and broadcast:
```sh
btchot sign -p '' "data0/$PSBT" "$WALLET_PATH/0.derive"
# example output:
# Signing with [44ff6cd2/86h/1h/0h]tpubDDA4WpAzm75zi7eKjuWKxUB7b9V16UHqhApMFeFfPxremDC3J1j4XQXXBLJjSQXzv8GhHnDvbTVNU2xPYgynWiTutaKsypezTA2WuNNubAN/*/*
#
# Done 1 signatures

btccold finalize "data0/$PSBT"
# example output:
# 020000000001018c375a235fcf28e48bdd33ba121ed709f3b407089fa9690580d3ece381f18fba0100000000000000000270dff505000000001600149ab996b5069011b00ecfa17c3a1a518342a057ba0000000000000000226a20a7e26764375ffda9bad7a8c6986968ae3103a51eb3242be7d8bffb114f74f90f0247304402207fdc3c501f9cf282e7fc27a766054858c4c03de3b3860cfb29b42855e909848202207f693b566ec39ccf4f53ba78d95514edf0562b9ff36941de84ee4bb9467b8fcb01210387aee261073759fc1f27cde0c533204a06063ffe1f5e344c776fff52f5481a2c00000000

tx="020...000"

bcli sendrawtransaction "$tx"
```

##### Transaction confirmation
Now the transaction has been broadcast, let's confirm it:
```sh
bcli -rpcwallet=miner -generate 1
```

In real-world scenarios the parties wait for the transaction to be included in
a block.

##### Wallet synchronization
Once the transaction has been confirmed, wallets need to be updated:
```sh
rgb0 utxos --sync
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet issuer ... success
# Syncing keychain 0 .......... keychain 1 .......... keychain 9 ............ success
#
# Height     Amount, ṩ    Outpoint
# bcrt1qn2ueddgxjqgmqrk0597r5xj3sdp2q4a6zxp4qx    &9/1
# 105         99999600    e7b8deefc83f56e5e60046367a338dd6b687371ace6aa9d1be0a6a22d6228c60:0
#
# Loading descriptor from wallet issuer ... success
#
# Wallet total balance: 99999600 ṩ

rgb1 utxos --sync
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet rcpt1 ... success
# Syncing keychain 0 .......... keychain 1 .......... keychain 9 ........... success
#
# Height     Amount, ṩ    Outpoint
# bcrt1q0g4rh35ql7774da7mcup4p20dmrs429mhzj9rk    &9/0
# 104        100000000    252e3976b9b467eb232fa88bcbcff6b4a857eb31b2eb039d441d6e4fb5ddee51:1
#
# Loading descriptor from wallet rcpt1 ... success
#
# Wallet total balance: 100000000 ṩ
```

##### Receiver: accept transfer
Once the transaction has been confirmed, the receiver can accept the transfer,
which is required to complete the transfer and update the contract state:
```sh
rgb1 accept "data1/$CONSIGNMENT"
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet rcpt1 ... success
# Loading stock ... success
#
# Transfer accepted into the stash
```

Note that accepting a transfer first validates its consignment.

Let's see the updated contract state, from the receiver's point of view:
```sh
rgb1 state "$contract_id" "$IFACE"
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet rcpt1 ... success
# Loading stock ... success
# Global:
#   spec := (ticker=("USDT"), name=("USD Tether"), details=~, precision=0)
#   terms := (text=("demo NIA asset"), media=~)
#   issuedSupply := (1000)
#
# Owned:
#   assetOwner:
#     amount=100, utxo=bc:opret1st:252e3976b9b467eb232fa88bcbcff6b4a857eb31b2eb039d441d6e4fb5ddee51:1, witness=bc:e7b8deefc83f56e5e60046367a338dd6b687371ace6aa9d1be0a6a22d6228c60 # owned by the wallet
```

##### Transfer complete
The sender doesn't need to explicitly accept the transfer, as it's automatically
accepted when creating it.

The contract state reflects the updated situation:
```sh
rgb0 state "$contract_id" "$IFACE"
# example output:
# RGB: command-line wallet for RGB smart contracts
#      by LNP/BP Standards Association
#
# Loading descriptor from wallet issuer ... success
# Loading stock ... success
# Global:
#   spec := (ticker=("USDT"), name=("USD Tether"), details=~, precision=0)
#   terms := (text=("demo NIA asset"), media=~)
#   issuedSupply := (1000)
#
# Owned:
#   assetOwner:
#     amount=900, utxo=bc:opret1st:e7b8deefc83f56e5e60046367a338dd6b687371ace6aa9d1be0a6a22d6228c60:0, witness=bc:e7b8deefc83f56e5e60046367a338dd6b687371ace6aa9d1be0a6a22d6228c60 # owned by the wallet
```
Both the bitcoin and RGB changes have been allocated to an outpout of the
transaction.

Since the `outpoint_receive` was blinded during invoice generation, the payer
has no information on where the asset was allocated by the transfer.

## Acknowledgments
This project was originally based on the rgb-node demo by [St333p] (version
0.1) and [grunch]'s [guide].

[RGB HTTP JSON-RPC]: https://github.com/RGB-Tools/rgb-http-json-rpc
[RGB proxy]: https://github.com/RGB-Tools/rgb-proxy-server
[St333p]: https://github.com/St333p
[cargo]: https://github.com/rust-lang/cargo
[descriptor-wallet]: https://github.com/BP-WG/descriptor-wallet
[docker compose]: https://docs.docker.com/compose/install/
[docker]: https://docs.docker.com/get-docker/
[git]: https://git-scm.com/downloads
[grunch]: https://github.com/grunch
[guide]: https://grunch.dev/blog/rgbnode-tutorial/
[rgb-wallet]: https://github.com/RGB-WG/rgb
