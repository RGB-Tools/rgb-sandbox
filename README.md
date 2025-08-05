RGB Sandbox
===

## Introduction
This is an RGB sandbox and demo based on RGB version 0.11.1 RC 4.

The underlying Bitcoin network is `regtest`.

RGB is operated via the [rgb-cmd] crate. [bp-wallet] is used for
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

Both versions will leave `bp-wallet` and `rgb-cmd` installed, in the
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
option. The default scenario is `0`, which has been described above, using the
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
rm -r bp-wallet rgb-cmd
```

### Premise
The rgb-cmd CLI tool does not handle bitcoin-related functionality, it
performs RGB-specific tasks over data that is provided by an external bitcoin
wallet, such as bp-wallet. In particular, in order to demonstrate a
basic workflow with issuance and transfer, from the bitcoin wallets we will
need:
- an *outpoint_issue* to which the issuer will allocate the new asset
- an *outpoint_receive* where the recipient will receive the asset transfer
- a partially signed bitcoin transaction (PSBT) to anchor the transfer

### bp-wallet installation
Bitcoin walleting will be handled with bp-wallet. We install its CLI to
the `bp-wallet` directory inside the project directory:
```sh
cargo install bp-wallet --version 0.11.1-alpha.2 --root ./bp-wallet --features=cli,hot
```

### rgb-cmd installation
RGB functionality will be handled with `rgb-cmd`. We install its CLI to the
`rgb-cmd` directory inside the project directory:
```sh
cargo install rgb-cmd --version 0.11.1-rc.4 --root ./rgb-cmd
```

### Demo
#### Initial setup
We setup aliases to ease CLI calls:
```sh
alias bcli="docker compose exec -u blits bitcoind bitcoin-cli -regtest"
alias bp="bp-wallet/bin/bp"
alias bphot="bp-wallet/bin/bp-hot"
alias rgb0="rgb-cmd/bin/rgb -n regtest --electrum=localhost:50001 -d data0 -w issuer"
alias rgb1="rgb-cmd/bin/rgb -n regtest --electrum=localhost:50001 -d data1 -w rcpt1"
```

We set some environment variables:
```sh
CLOSING_METHOD="opret1st"
CONSIGNMENT="consignment.rgb"
PSBT="tx.psbt"
SCHEMATA_DIR="rgb-schemas/schemata"
WALLET_PATH="wallets"
KEYCHAIN="<0;1;9>"
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
# seed password definition
export SEED_PASSWORD="seed test password"
# issuer/sender wallet
bphot seed "$WALLET_PATH/0.seed"
# example output:
# Master key:
#  - fingerprint:   598d26fe
#  - mainnet:       yes
#  - id:            598d26fe67440cf07440a2bbad3a1d39190fd6dd
#  - xpub:          xpub661MyMwAqRbcFEYjvY4eJsx912sHuNHZbTK59GQU5rcZiZg3UoMbT4eHMjTYe1gox9ju6qe1p1LMHa2EXYTXjNSLvFn7gTvVJ3zZqEfqnUw

bphot derive -N -s bip86 "$WALLET_PATH/0.seed" "$WALLET_PATH/0.derive"
# example output:
# Account: [598d26fe/86h/1h/0h]tpubDCwKX3ruPTchxDewiTWEHDxp2hdP9n82fbYvn82R14MhwmfyviscYK3xEVDn8rdUNcEKXZT2VFfcAFS2dcVKFJqyvu4TSMyhermxGBy4FLe
#   - fingerprint:   bdaa6934
#   - id:            bdaa693476ca9abada57fa368d1d73a2816bada4
#   - key origin:    [598d26fe/86h/1h/0h]
#   - xpub:          [598d26fe/86h/1h/0h]tpubDCwKX3ruPTchxDewiTWEHDxp2hdP9n82fbYvn82R14MhwmfyviscYK3xEVDn8rdUNcEKXZT2VFfcAFS2dcVKFJqyvu4TSMyhermxGBy4FLe

account_0="[598d26fe/86h/1h/0h]tpubDCwK...4FLe"
descriptor_0="$account_0/$KEYCHAIN/*"

# receiver wallet
bphot seed "$WALLET_PATH/1.seed"
# example output:
# Master key:
#   - fingerprint:   01388e83
#   - mainnet:       yes
#   - id:            01388e838d7078da16c6bac34c7a1cd3ae066a15
#   - xpub:          xpub661MyMwAqRbcFhMyXELbJEQvCWXgKJCcmoUShV6wyzEDdWopG2tmurq1c5tUNGiEiZffNwQF4SKWsTHMXRuUtXfR9iB1BtNh9t9eQtNtRWv

bphot derive -N -s bip86 "$WALLET_PATH/1.seed" "$WALLET_PATH/1.derive"
# example output:
# Account: [01388e83/86h/1h/0h]tpubDCTj4vrvbbGQDxbmUvKvxujkkgZTPQd1WPQSFQziwhHQgABHUnBN1CAB9tXHuSwEteRbwk7Wy4i7J88qCLrDSRY9e3m65J8SckQn2VRgytA
#   - fingerprint:   68401907
#   - id:            68401907032c78e45e4cc5283129e76cd662b75f
#   - key origin:    [01388e83/86h/1h/0h]
#   - xpub:          [01388e83/86h/1h/0h]tpubDCTj4vrvbbGQDxbmUvKvxujkkgZTPQd1WPQSFQziwhHQgABHUnBN1CAB9tXHuSwEteRbwk7Wy4i7J88qCLrDSRY9e3m65J8SckQn2VRgytA

account_1="[01388e83/86h/1h/0h]tpubDCTj...gytA"
descriptor_1="$account_1/$KEYCHAIN/*"
```

We setup the RGB wallets:
```sh
# issuer/sender
rgb0 create --wpkh $descriptor_0 issuer
# example output
# Unable to find or parse config file; using config defaults
# Loading descriptor from command-line argument ... success
# Syncing keychain 0 .......... keychain 1 .......... keychain 9 .......... success
# Saving the wallet as 'issuer' ... success

# receiver
rgb1 create --wpkh $descriptor_1 rcpt1
# example output
# Unable to find or parse config file; using config defaults
# Loading descriptor from command-line argument ... success
# Syncing keychain 0 .......... keychain 1 .......... keychain 9 .......... success
# Saving the wallet as 'rcpt1' ... success
```

We import the NIA schema into the RGB wallets:
```sh
# issuer/sender
rgb0 import $SCHEMATA_DIR/NonInflatableAsset.rgb
# example output:
# Unable to find or parse config file; using config defaults
# Importing kit rgb:kit:qxyONQWD-WY7Sha7-wzsRSMW-MaNI6PI-T74uzx9-sBzUztg:
# - schema NonInflatableAsset RWhwUfTMpuP2Zfx1~j4nswCANGeJrYOqDcKelaMV4zU#remote-digital-pegasus
# - script library alu:q~CZ0ovt-UN9eBlc-VMn86mz-Kfd3ywu-f7~9jTB-k6A8tiY#japan-nylon-center
# - strict types: 35 definitions
# Kit is imported


# receiver (same output as issuer/sender)
rgb1 import $SCHEMATA_DIR/NonInflatableAsset.rgb
```

We retrieve the schema ID and set it as environment variable:
```sh
rgb0 schemata
# example output:
# NonInflatableAsset              rgb:sch:RWhwUfTMpuP2Zfx1~j4nswCANGeJrYOqDcKelaMV4zU#remote-digital-pegasus

schema_id="rgb:sch:RWhwUfTM...igital-pegasus"
```

We prepare the required UTXOs:
```sh
# generate addresses
rgb0 address -k 9
# example output:
# Loading descriptor from wallet issuer ... success
#
# Term.   Address
# &9/0    bcrt1qk2x6fl3ps3qgx4qwsz4vt6ygpn7k9ahspklt49

addr_issue="bcrt1qk2...hspklt49"

rgb1 address -k 9
# example output:
# Loading descriptor from wallet rcpt1 ... success
#
# Term.   Address
# &9/0    bcrt1qml9x37tcdupzk02tvcwe8w8gm3qffg8ydr4zhy

addr_receive="bcrt1qml...8ydr4zhy"

# fund wallets
bcli -rpcwallet=miner sendtoaddress "$addr_issue" 1
bcli -rpcwallet=miner sendtoaddress "$addr_receive" 1
bcli -rpcwallet=miner -generate 1

# sync wallets and gather outpoints
rgb0 utxos --sync
# example output:
# Loading descriptor from wallet issuer ... success
# Syncing keychain 0 .......... keychain 1 .......... keychain 9 ........... success
# Balance of wpkh([598d26fe/86h/1h/0h]tpubDCwKX3ruPTchxDewiTWEHDxp2hdP9n82fbYvn82R14MhwmfyviscYK3xEVDn8rdUNcEKXZT2VFfcAFS2dcVKFJqyvu4TSMyhermxGBy4FLe/<0;1;9>/*)
#
# Height     Amount, ṩ    Outpoint
# bcrt1qk2x6fl3ps3qgx4qwsz4vt6ygpn7k9ahspklt49    &9/0
# 104        100000000    02e107ddf4f42757f44fac43feb007606d8caf40616fa92dba62176995513e88:0
#
# Loading descriptor from wallet issuer ... success
#
# Wallet total balance: 100000000 ṩ

outpoint_issue="02e107dd...95513e88:0"

rgb1 utxos --sync
# example output:
# Loading descriptor from wallet rcpt1 ... success
# Syncing keychain 0 .......... keychain 1 .......... keychain 9 ........... success
# Balance of wpkh([01388e83/86h/1h/0h]tpubDCTj4vrvbbGQDxbmUvKvxujkkgZTPQd1WPQSFQziwhHQgABHUnBN1CAB9tXHuSwEteRbwk7Wy4i7J88qCLrDSRY9e3m65J8SckQn2VRgytA/<0;1;9>/*)
#
# Height     Amount, ṩ    Outpoint
# bcrt1qml9x37tcdupzk02tvcwe8w8gm3qffg8ydr4zhy    &9/0
# 104        100000000    efde6b6e5c0fa2aea3adbac679d859462f7c67c41cf661bd1558f9a4bbf2a43f:1
#
# Loading descriptor from wallet rcpt1 ... success
#
# Wallet total balance: 100000000 ṩ

outpoint_receive="efde6b6e...bbf2a43f:1"
```

#### Asset issuance
To issue an asset, we first need to prepare a contract definition file, then
use it to actually carry out the issuance.

To prepare the contract file, we copy the provided template and modify the copy
to set the required data:
- schema ID
- issued supply
- issuance txid and vout

We do this with a single command (which reads the template file, modifies the
given properties and writes the result to the contract definition file):
```sh
sed \
  -e "s/schema_id/$schema_id/" \
  -e "s/issued_supply/1000/" \
  -e "s/txid:vout/$outpoint_issue/" \
  contracts/usdt.yaml.template > contracts/usdt.yaml
```

To actually issue the asset, run:
```sh
rgb0 issue "ssi:issuer" contracts/usdt.yaml
# example output:
# A new contract rgb:Tk3d0h5w-8v4XYCg-7e~Sc0o-Lu6rp~X-~Jt7VHS-jqgzFD8 is issued and added to the stash.
# Use `export` command to export the contract.

contract_id="rgb:Tk3d0h5w...-jqgzFD8"
```

This will create a new genesis that includes the asset metadata and the
allocation of the initial amount to `outpoint_issue`.

You can list known contracts:
```sh
rgb0 contracts
# example output:
# rgb:Tk3d0h5w-8v4XYCg-7e~Sc0o-Lu6rp~X-~Jt7VHS-jqgzFD8    BitcoinRegtest  2025-07-02      rgb:sch:RWhwUfTMpuP2Zfx1~j4nswCANGeJrYOqDcKelaMV4zU#remote-digital-pegasus
#   Developer: ssi:issuer
```

You can show the current known state for the contract:
```sh
rgb0 state "$contract_id"
# example output:
# Loading descriptor from wallet issuer ... success
#
# Global:
#   spec := ticker "USDT", name "USD Tether", details ~, precision indivisible
#   terms := text "demo NIA asset", media ~
#   issuedSupply := 1000
#
# Owned:
#   State         Seal                                                                            Witness
#   assetOwner:
#          1000   02e107ddf4f42757f44fac43feb007606d8caf40616fa92dba62176995513e88:0      ~
```

#### Transfer

##### Receiver: generate invoice
In order to receive assets, the receiver needs to provide an invoice to the
sender. The receiver generates an invoice providing the amount to be received
(here `100`) and the outpoint where the assets should be allocated:
```sh
rgb1 invoice --amount 100 "$contract_id"
# example output:
# Loading descriptor from wallet rcpt1 ... success
# rgb:Tk3d0h5w-8v4XYCg-7e~Sc0o-Lu6rp~X-~Jt7VHS-jqgzFD8/~/BF/bcrt:utxob:MSLQCKkW-w6caphB-12do1nJ-HNfgxvv-WE3zOOC-s8yZyHq-Ihoa5

invoice="rgb:Tk3d0h5w...Hq-Ihoa5"
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
modify the PSBT to include a commitment to the consignment. The rgb-cmd
`prepare` command prepares the PSBT and the `consign` command handles
consignment preparation and commitment. The `transfer` command does both.

We create the transfer, providing the receiver's invoice and file names to save
the consignment and the PSBT.
```sh
rgb0 transfer "$invoice" "data0/$CONSIGNMENT" "data0/$PSBT"
# example output:
# Loading descriptor from wallet issuer ... success
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
bphot sign -N "data0/$PSBT" "$WALLET_PATH/0.derive"
# example output:
# BP: command-line tool for working with seeds and private keys in bitcoin protocol
#     by LNP/BP Standards Association
#
# Signing data0/tx.psbt with wallets/0.derive
# Signing key: [598d26fe/86h/1h/0h]tpubDCwKX3ruPTchxDewiTWEHDxp2hdP9n82fbYvn82R14MhwmfyviscYK3xEVDn8rdUNcEKXZT2VFfcAFS2dcVKFJqyvu4TSMyhermxGBy4FLe
# Signing using testnet signer
# PSBT version: v0
# Transaction id: c5a04a06e082e2ea22ae5ab7b1c146ee82ab756e5fbe60a0c5a4251b82a92c5a
# Done 1 signatures, saved to data0/tx.psbt
#
#
# cHNidP8BAH0CAAAAAYg+UZVpF2K6LalvYUCvjG1gB7D+Q6xP9Fcn9PTdB+ECAAAAAAAAAAAAAgAAAAAAAAAAImogz9pcM+A+/DJNd4TXOAOTCk8k2dRV4z1mCRY4i+4L6OJw3/UFAAAAABYAFJ3dQn1dUQyfIkEp9pG/+xJUdvb6AAAAAE8BBDWHzwN8I3VZgAAAAPmb8sYvrm7ckf7rog/++BVPu7KCSyWTkiVXqUSucOiNAijskWDISEkTwADMR0akesUHSNePOKbXY8OfEV3deO1zEFmNJv5WAACAAQAAgAAAAIAB+wQAAAAABvwDUkdCAgEAJvwDUkdCAUeo27yG7KjznHNr4YhcdvzHadfKLL4ozzgLH81n86GUnQAATk3d0h5w8v4XYCg7e/Sc0oLu6rp/X/Jt7VHSjqgzFD///////////xAnAAABAE5N3dIecPL+F2AoO3v0nNKC7uq6f1/ybe1R0o6oMxQ/oA8AAAEAoA8BAgAAAAEAAAAs4mNJ6VLepgiEAwAAAAAAAAExItAIqRbDpxqmEHXZ2jWckc1+DG+9YTfM44KzzJnIeghkAAAAAAAAAAAm/ANSR0IETk3d0h5w8v4XYCg7e/Sc0oLu6rp/X/Jt7VHSjqgzFD9ETk3d0h5w8v4XYCg7e/Sc0oLu6rp/X/Jt7VHSjqgzFD+gDwAAR6jbvIbsqPOcc2vhiFx2/Mdp18osvijPOAsfzWfzoZQAAQEfAOH1BQAAAAAWABSyjaT+IYRAg1QOgKrF6IgM/WL28CICAiweuA5hcm7yMvbS7LT9DrsMAJo6tH4q07kGjpTvNz5FSDBFAiEAxTMFTdxhOzac4zRjpx28UzfyryTo9KVvkxsE69gxZiUCIFjdMhTTLF9Jr4L5BI6G9LvMjtXQLOj+/tid4nn9fuNfASIGAiweuA5hcm7yMvbS7LT9DrsMAJo6tH4q07kGjpTvNz5FGFmNJv5WAACAAQAAgAAAAIAJAAAAAAAAAAAm/ANNUEMATk3d0h5w8v4XYCg7e/Sc0oLu6rp/X/Jt7VHSjqgzFD8gP7FNyyOTYGA9IZVyDRiytiLfjOCUUJcn38JP/tUXoD0G/ANNUEMBCMRtbvf4HHkqBvwDTVBDECDP2lwz4D78Mk13hNc4A5MKTyTZ1FXjPWYJFjiL7gvo4gb8A01QQxH9PwEDAAAIAAAAAAMajN4LIVSptPuBTqb4FgNoQBQho7rNXFLe4OTwamTozAADGA+Jgi6goKfygBxnsx7weo/cxluwYLWvwNkrD5KAGfcAAx7IgpVFF+KPwhuLO5tMMsgxckijXCHNeLvzoki5ltIhAAPN6TLyadIEblBqN3QJL1oyqPtD1Xa8zniZaf6oDKTojAADdzHErPhEsMeWMeZpxiov/MQ0HUDOcTQGCqfiH7jV2RwAA+yAxTDLxTXILnW+tMIMrr0bH0PYo/xzNxOHeAacGo4JAU5N3dIecPL+F2AoO3v0nNKC7uq6f1/ybe1R0o6oMxQ/P7FNyyOTYGA9IZVyDRiytiLfjOCUUJcn38JP/tUXoD0AA1IXeT+Z+UCc19qNYTbppSIQtbVFvk4eBdHtY6skiZYdAcRtbvf4HHkqCPwFT1BSRVQBIM/aXDPgPvwyTXeE1zgDkwpPJNnUVeM9ZgkWOIvuC+jiACICA1JKxktU8tYdc/IIpjatg0o51nGZeaeYn96wDfCUA9h/GFmNJv5WAACAAQAAgAAAAIAJAAAAAQAAAAA=

rgb0 finalize -p data0/$PSBT data0/${PSBT%psbt}tx
# example output:
# Reading PSBT from file data0/tx.psbt ... success
# Loading descriptor from wallet issuer ... success
# Finalizing PSBT ... 1 of 1 inputs were finalized, transaction is ready for the extraction
# Saving PSBT to file data0/tx.psbt ... success
# Extracting signed transaction ... success
# Saving transaction to file data0/tx.tx ...success
# Publishing transaction via electrum ... success
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
# Loading descriptor from wallet issuer ... success
# Syncing keychain 0 .......... keychain 1 .......... keychain 9 ............ success
# Balance of wpkh([598d26fe/86h/1h/0h]tpubDCwKX3ruPTchxDewiTWEHDxp2hdP9n82fbYvn82R14MhwmfyviscYK3xEVDn8rdUNcEKXZT2VFfcAFS2dcVKFJqyvu4TSMyhermxGBy4FLe/<0;1;9>/*)
#
# Height     Amount, ṩ    Outpoint
# bcrt1qnhw5yl2a2yxf7gjp98mfr0lmzf28dah6r7gs8a    &9/1
# 105         99999600    c5a04a06e082e2ea22ae5ab7b1c146ee82ab756e5fbe60a0c5a4251b82a92c5a:1
#
# Loading descriptor from wallet issuer ... success
#
# Wallet total balance: 99999600 ṩ

rgb1 utxos --sync
# example output:
# Loading descriptor from wallet rcpt1 ... success
# Syncing keychain 0 .......... keychain 1 .......... keychain 9 ........... success
# Balance of wpkh([01388e83/86h/1h/0h]tpubDCTj4vrvbbGQDxbmUvKvxujkkgZTPQd1WPQSFQziwhHQgABHUnBN1CAB9tXHuSwEteRbwk7Wy4i7J88qCLrDSRY9e3m65J8SckQn2VRgytA/<0;1;9>/*)
#
# Height     Amount, ṩ    Outpoint
# bcrt1qml9x37tcdupzk02tvcwe8w8gm3qffg8ydr4zhy    &9/0
# 104        100000000    efde6b6e5c0fa2aea3adbac679d859462f7c67c41cf661bd1558f9a4bbf2a43f:1
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
# Transfer accepted into the stash
```

Note that accepting a transfer first validates its consignment.

Let's see the updated contract state, from the receiver's point of view:
```sh
rgb1 state "$contract_id"
# example output:
# Loading descriptor from wallet rcpt1 ... success
#
# Global:
#   spec := ticker "USDT", name "USD Tether", details ~, precision indivisible
#   terms := text "demo NIA asset", media ~
#   issuedSupply := 1000
#
# Owned:
#   State         Seal                                                                            Witness
#   assetOwner:
#           100   efde6b6e5c0fa2aea3adbac679d859462f7c67c41cf661bd1558f9a4bbf2a43f:1      c5a04a06e082e2ea22ae5ab7b1c146ee82ab756e5fbe60a0c5a4251b82a92c5a (tentative)
```

##### Transfer complete
The sender doesn't need to explicitly accept the transfer, as it's automatically
accepted when creating it.

The contract state reflects the updated situation:
```sh
rgb0 state "$contract_id"
# example output:
# Loading descriptor from wallet issuer ... success
#
# Global:
#   spec := ticker "USDT", name "USD Tether", details ~, precision indivisible
#   terms := text "demo NIA asset", media ~
#   issuedSupply := 1000
#
# Owned:
#   State         Seal                                                                            Witness
#   assetOwner:
#           900   c5a04a06e082e2ea22ae5ab7b1c146ee82ab756e5fbe60a0c5a4251b82a92c5a:1      c5a04a06e082e2ea22ae5ab7b1c146ee82ab756e5fbe60a0c5a4251b82a92c5a (tentative)
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
[rgb-cmd]: https://github.com/rgb-protocol/rgb-api
