.PHONY: build deploy generate-abis get-address account chain compile flatten fork format lint test verify
DEPLOY_SCRIPT ?= script/Deploy.s.sol
# setup wallet for anvil
setup-anvil-wallet:
	shx rm ~/.foundry/keystores/scaffold-eth-default 2>/dev/null; 	shx rm -rf broadcast/Deploy.s.sol/31337
	
# Start local chain
chain: setup-anvil-wallet
	anvil
# Start a fork
fork: setup-anvil-wallet
	anvil --fork-url ${FORK_URL} --chain-id 31337
# Deploy the contracts
deploy:
	@if [ ! -f "$(DEPLOY_SCRIPT)" ]; then 		echo "Error: Deploy script '$(DEPLOY_SCRIPT)' not found"; 		exit 1; 	fi
	@if [ "$(RPC_URL)" = "localhost" ]; then 		if [ "$(ETH_KEYSTORE_ACCOUNT)" = "scaffold-eth-default" ]; then 			yes | forge script $(DEPLOY_SCRIPT) --rpc-url localhost --password localhost --broadcast --ffi --non-interactive --with-gas-price 2000000000; 		else 			yes | forge script $(DEPLOY_SCRIPT) --rpc-url localhost --broadcast --ffi --non-interactive --with-gas-price 2000000000; 		fi 	else 		yes | forge script $(DEPLOY_SCRIPT) --rpc-url $(RPC_URL) --broadcast --ffi --non-interactive; 	fi
# Deploy and generate ABIs
deploy-and-generate-abis: deploy generate-abis 
# Generate TypeScript ABIs
generate-abis:
	node scripts-js/generateTsAbis.js
# List account
account:
	@node scripts-js/checkAccountBalance.js
# Get address of a keystore
get-address:
	@cast wallet address --account $(ACCOUNT_NAME)
# Compile contracts
compile:
	forge compile
# Flatten contracts
flatten:
	forge flatten
# Format code
format:
	forge fmt && prettier --write ./scripts-js/**/*.js
# Lint code
lint:
	forge fmt --check && prettier --check ./scripts-js/**/*.js
# Run tests
test:
	forge test
# Verify contracts
verify:
	yes | forge script script/VerifyAll.s.sol --ffi --rpc-url $(RPC_URL)
