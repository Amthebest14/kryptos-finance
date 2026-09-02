// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {LiquidationHandler} from "../src/LiquidationHandler.sol";
import {VaultManager} from "../src/VaultManager.sol";

/// @notice Standalone redeploy for LiquidationHandler.sol — reused across
/// multiple fixes without changing this script's own logic (it always
/// deploys whatever the current source is): gap #8's real debt repayment /
/// real collateral payout, and gap #5's abandoned-position backstop
/// (proposeAbandonedClose / finalizeWithProof / finalizeByTimeout). No
/// changes needed to VaultManager, PositionRegistry, or any proof-verifying
/// contract for either — this deploys just the one contract and re-points
/// VaultManager.liquidationHandler at it — vault.setLiquidationHandler is a
/// plain owner-callable function, no full system redeploy required.
contract RedeployLiquidationHandler is Script {
    address constant REGISTRY = 0x9101dD31C3C2f4097149A9D6C44B7C14445e4A0a;
    address constant VAULT = 0xf236E7177CB4684cCbfEfB9b5369853094116985;
    address constant TRANSITION_REVEAL_ADAPTER = 0xbaC53287eCf23ac461742B2BC08AC5754664b14d;

    function run() external {
        vm.startBroadcast();

        LiquidationHandler handler = new LiquidationHandler(REGISTRY, VAULT, TRANSITION_REVEAL_ADAPTER);
        VaultManager(VAULT).setLiquidationHandler(address(handler));

        vm.stopBroadcast();

        console.log("LiquidationHandler:", address(handler));
        console.log("VaultManager.liquidationHandler() is now:", address(handler));
    }
}
