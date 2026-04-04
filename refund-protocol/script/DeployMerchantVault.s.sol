// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MerchantVault} from "../src/MerchantVault.sol";

/// @notice Deploy MerchantVault. Required: PRIVATE_KEY, VAULT_OWNER, REFUND_PROTOCOL_ADDRESS, USDC_ADDRESS.
contract DeployMerchantVault is Script {
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
        address vaultOwner = vm.envAddress("VAULT_OWNER");
        address protocol = vm.envAddress("REFUND_PROTOCOL_ADDRESS");
        address usdc = vm.envAddress("USDC_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);
        MerchantVault vault = new MerchantVault(vaultOwner, protocol, usdc);
        vm.stopBroadcast();

        console2.log("chainId", block.chainid);
        console2.log("MerchantVault", address(vault));
    }
}
