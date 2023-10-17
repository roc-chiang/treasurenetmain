#!/bin/bash
set -eux
# your gaiad binary name
BIN=treasurenetd

CHAIN_ID="treasurenet_5005-1"
KEYALGO="secp256k1"
LOGLEVEL="info"
# to trace evm
TRACE="--trace"

NODES=$1

#ALLOCATION="10000000000stake,10000000000footoken,10000000000footoken2,10000000000ibc/nometadatatoken"
ALLOCATION="100000000000000000000000000aunit,10000000000stake,10000000000footoken,10000000000footoken2,10000000000ibc/nometadatatoken"

# first we start a genesis.json with validator 1
# validator 1 will also collect the gentx's once gnerated
STARTING_VALIDATOR=1
STARTING_VALIDATOR_HOME="--home /root/validator$STARTING_VALIDATOR"
# todo add git hash to chain name
$BIN init $STARTING_VALIDATOR_HOME --chain-id=$CHAIN_ID validator1

# Change parameter token denominations to aunit
cat $HOME/validator$STARTING_VALIDATOR/config/genesis.json | jq '.app_state["staking"]["params"]["bond_denom"]="aunit"' > $HOME/validator$STARTING_VALIDATOR/config/tmp_genesis.json && mv $HOME/validator$STARTING_VALIDATOR/config/tmp_genesis.json $HOME/validator$STARTING_VALIDATOR/config/genesis.json
cat $HOME/validator$STARTING_VALIDATOR/config/genesis.json | jq '.app_state["crisis"]["constant_fee"]["denom"]="aunit"' > $HOME/validator$STARTING_VALIDATOR/config/tmp_genesis.json && mv $HOME/validator$STARTING_VALIDATOR/config/tmp_genesis.json $HOME/validator$STARTING_VALIDATOR/config/genesis.json
cat $HOME/validator$STARTING_VALIDATOR/config/genesis.json | jq '.app_state["gov"]["deposit_params"]["min_deposit"][0]["denom"]="aunit"' > $HOME/validator$STARTING_VALIDATOR/config/tmp_genesis.json && mv $HOME/validator$STARTING_VALIDATOR/config/tmp_genesis.json $HOME/validator$STARTING_VALIDATOR/config/genesis.json
cat $HOME/validator$STARTING_VALIDATOR/config/genesis.json | jq '.app_state["mint"]["params"]["mint_denom"]="aunit"' > $HOME/validator$STARTING_VALIDATOR/config/tmp_genesis.json && mv $HOME/validator$STARTING_VALIDATOR/config/tmp_genesis.json $HOME/validator$STARTING_VALIDATOR/config/genesis.json

# increase block time (?)
cat $HOME/validator$STARTING_VALIDATOR/config/genesis.json | jq '.consensus_params["block"]["time_iota_ms"]="1000"' > $HOME/validator$STARTING_VALIDATOR/config/tmp_genesis.json && mv $HOME/validator$STARTING_VALIDATOR/config/tmp_genesis.json $HOME/validator$STARTING_VALIDATOR/config/genesis.json

# Set gas limit in genesis
cat $HOME/validator$STARTING_VALIDATOR/config/genesis.json | jq '.consensus_params["block"]["max_gas"]="10000000"' > $HOME/validator$STARTING_VALIDATOR/config/tmp_genesis.json && mv $HOME/validator$STARTING_VALIDATOR/config/tmp_genesis.json $HOME/validator$STARTING_VALIDATOR/config/genesis.json

# disable produce empty block
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' 's/create_empty_blocks = true/create_empty_blocks = false/g' $HOME/validator$STARTING_VALIDATOR/config/config.toml
  else
    sed -i 's/create_empty_blocks = true/create_empty_blocks = false/g' $HOME/validator$STARTING_VALIDATOR/config/config.toml
fi

## Modify generated genesis.json to our liking by editing fields using jq
## we could keep a hardcoded genesis file around but that would prevent us from
## testing the generated one with the default values provided by the module.

# add in denom metadata for both native tokens
jq '.app_state.bank.denom_metadata += [{"name": "Foo Token", "symbol": "FOO", "base": "footoken", display: "mfootoken", "description": "A non-staking test token", "denom_units": [{"denom": "footoken", "exponent": 0}, {"denom": "mfootoken", "exponent": 6}]},{"name": "Stake Token", "symbol": "STEAK", "base": "aunit", display: "unit", "description": "A staking test token", "denom_units": [{"denom": "aunit", "exponent": 0}, {"denom": "unit", "exponent": 18}]}]' /root/validator$STARTING_VALIDATOR/config/genesis.json > /footoken2-genesis.json
jq '.app_state.bank.denom_metadata += [{"name": "Foo Token2", "symbol": "F20", "base": "footoken2", display: "mfootoken2", "description": "A second non-staking test token", "denom_units": [{"denom": "footoken2", "exponent": 0}, {"denom": "mfootoken2", "exponent": 6}]}]' /footoken2-genesis.json > /bech32ibc-genesis.json

# Set the chain's native bech32 prefix
jq '.app_state.bech32ibc.nativeHRP = "treasurenet"' /bech32ibc-genesis.json > /gov-genesis.json

# a 60 second voting period to allow us to pass governance proposals in the tests
jq '.app_state.gov.voting_params.voting_period = "120s"' /gov-genesis.json > /community-pool-genesis.json

# Add some funds to the community pool to test Airdrops, note that the gravity address here is the first 20 bytes
# of the sha256 hash of 'distribution' to create the address of the module
# jq '.app_state.distribution.fee_pool.community_pool = [{"denom": "stake", "amount": "1000000000000000000000000.0"}]' /community-pool-genesis.json > /community-pool2-genesis.json
# jq '.app_state.auth.accounts += [{"@type": "/cosmos.auth.v1beta1.ModuleAccount", "base_account": { "account_number": "0", "address": "gravity1jv65s3grqf6v6jl3dp4t6c9t9rk99cd8r0kyvh","pub_key": null,"sequence": "0"},"name": "distribution","permissions": ["basic"]}]' /community-pool2-genesis.json > /community-pool3-genesis.json
# jq '.app_state.bank.balances += [{"address": "gravity1jv65s3grqf6v6jl3dp4t6c9t9rk99cd8r0kyvh", "coins": [{"amount": "1000000000000000000000000", "denom": "stake"}]}]' /community-pool3-genesis.json > /edited-genesis.json

mv /community-pool-genesis.json /genesis.json

# Sets up an arbitrary number of validators on a single machine by manipulating
# the --home parameter on gaiad
for i in $(seq 1 $NODES);
do
GAIA_HOME="--home /root/validator$i"
GENTX_HOME="--home-client /root/validator$i"
ARGS="$GAIA_HOME --keyring-backend test"

# Generate a validator key, orchestrator key, and eth key for each validator
$BIN keys add $ARGS validator$i 2>> /validator$i-phrases
$BIN keys add $ARGS orchestrator$i 2>> /orchestrator$i-phrases
$BIN eth_keys add >> /validator$i-eth-keys

VALIDATOR_KEY=$($BIN keys show validator$i -a $ARGS)
ORCHESTRATOR_KEY=$($BIN keys show orchestrator$i -a $ARGS)
# move the genesis in
mkdir -p /root/validator$i/config/
mv /genesis.json /root/validator$i/config/genesis.json
$BIN add-genesis-account $ARGS $VALIDATOR_KEY $ALLOCATION
$BIN add-genesis-account $ARGS $ORCHESTRATOR_KEY $ALLOCATION
# move the genesis back out
mv /root/validator$i/config/genesis.json /genesis.json
done


for i in $(seq 1 $NODES);
do
cp /genesis.json /root/validator$i/config/genesis.json
GAIA_HOME="--home /validator$i"
ARGS="$GAIA_HOME --keyring-backend test"
ORCHESTRATOR_KEY=$($BIN keys show orchestrator$i -a $ARGS)
ETHEREUM_KEY=$(grep address /validator-eth-keys | sed -n "$i"p | sed 's/.*://')
# the /8 containing 7.7.7.7 is assigned to the DOD and never routable on the public internet
# we're using it in private to prevent gaia from blacklisting it as unroutable
# and allow local pex
$BIN gentx $ARGS $GAIA_HOME --moniker validator$i --chain-id=$CHAIN_ID --ip 7.7.7.$i validator$i 500000000stake $ETHEREUM_KEY $ORCHESTRATOR_KEY
# obviously we don't need to copy validator1's gentx to itself
if [ $i -gt 1 ]; then
cp /validator$i/config/gentx/* /validator1/config/gentx/
fi
done


$BIN collect-gentxs $STARTING_VALIDATOR_HOME
GENTXS=$(ls /validator1/config/gentx | wc -l)
cp /validator1/config/genesis.json /genesis.json
echo "Collected $GENTXS gentx"

# put the now final genesis.json into the correct folders
for i in $(seq 1 $NODES);
do
cp /genesis.json /validator$i/config/genesis.json
done