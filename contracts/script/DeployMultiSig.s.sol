// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SimpleMultiSig} from "../src/SimpleMultiSig.sol";
import {PriceOracle} from "../src/PriceOracle.sol";

/// @notice Deploys SimpleMultiSig and transfers PriceOracle's ownership to
/// it. Deployed 1-of-1 (deployer as sole owner) — honestly, this is not yet
/// a real security improvement, since one person controls the only key
/// either way. What changes is the infrastructure: adding real independent
/// co-owners later is one `propose`/`approve` cycle away, not a PriceOracle
/// redeploy. Standalone script, doesn't touch the main Deploy.s.sol flow.
contract DeployMultiSig is Script {
    address constant PRICE_ORACLE = 0xD746bD3B09ce0D4Ba708BA85479471A93792b1E5;

    function run() external {
        vm.startBroadcast();

        address[] memory owners = new address[](1);
        owners[0] = msg.sender;
        SimpleMultiSig multisig = new SimpleMultiSig(owners, 1);

        PriceOracle(PRICE_ORACLE).setOwner(address(multisig));

        vm.stopBroadcast();

        console.log("SimpleMultiSig:", address(multisig));
        console.log("PriceOracle.owner() is now:", address(multisig));
    }
}
