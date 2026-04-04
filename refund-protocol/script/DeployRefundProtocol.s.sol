// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {RefundProtocol} from "../src/RefundProtocol.sol";

/// @notice Deploy `RefundProtocol` on any chain. Set env the same way for Base Sepolia, Arc testnet, or Base mainnet.
/// @dev Required: `PRIVATE_KEY`, `ARBITER_ADDRESS`, `USDC_ADDRESS` (the canonical USDC / fiat token on that chain).
contract DeployRefundProtocol is Script {
    /// @dev Accepts `PRIVATE_KEY` with or without `0x` (Forge's `envUint` requires the prefix for hex).
    function _envPrivateKey() internal view returns (uint256) {
        string memory raw = vm.envString("PRIVATE_KEY");
        bytes memory b = bytes(raw);
        if (b.length >= 2 && b[0] == 0x30 && (b[1] == 0x78 || b[1] == 0x58)) {
            return vm.parseUint(raw);
        }
        return vm.parseUint(string.concat("0x", raw));
    }

    function run() external {
        uint256 deployerPrivateKey = _envPrivateKey();
        address arbiter = vm.envAddress("ARBITER_ADDRESS");
        address usdc = vm.envAddress("USDC_ADDRESS");
        string memory eip712Name = vm.envOr("EIP712_NAME", string("Refund Protocol"));
        string memory eip712Version = vm.envOr("EIP712_VERSION", string("1.0"));

        vm.startBroadcast(deployerPrivateKey);
        RefundProtocol protocol = new RefundProtocol(arbiter, usdc, eip712Name, eip712Version);
        vm.stopBroadcast();

        console2.log("chainId", block.chainid);
        console2.log("RefundProtocol", address(protocol));
    }
}
