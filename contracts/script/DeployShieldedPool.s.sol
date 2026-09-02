// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ShieldedPool} from "../src/ShieldedPool.sol";
import {Groth16Verifier as ShieldedSpendVerifier} from "../src/ShieldedSpendVerifier.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// @notice Standalone testnet deployment for the gap #2 shielded-pool
/// proof-of-concept — deliberately separate from Deploy.s.sol. This is not
/// wired into the live lending system; see ShieldedPool.sol's own top
/// comment for exactly what this does and doesn't demonstrate.
contract DeployShieldedPool is Script {
    function run() external {
        vm.startBroadcast();

        bytes memory poseidonBytecode = vm.parseBytes(vm.readFile("script/artifacts/PoseidonT3.bytecode.txt"));
        address poseidonT3;
        assembly {
            poseidonT3 := create(0, add(poseidonBytecode, 0x20), mload(poseidonBytecode))
        }
        require(poseidonT3 != address(0), "PoseidonT3 deploy failed");

        ShieldedSpendVerifier verifier = new ShieldedSpendVerifier();
        MockERC20 token = new MockERC20("Shielded Test Token", "STT", 100 ether);
        ShieldedPool pool = new ShieldedPool(address(token), poseidonT3, address(verifier));

        token.mint(msg.sender, 1_000_000);

        vm.stopBroadcast();

        console.log("PoseidonT3:            ", poseidonT3);
        console.log("ShieldedSpendVerifier: ", address(verifier));
        console.log("Shielded Test Token:   ", address(token));
        console.log("ShieldedPool:          ", address(pool));
    }
}
