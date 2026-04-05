// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/RefundProtocol.sol";
import "../src/MerchantVault.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20Vault is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MerchantVaultTest is Test {
    RefundProtocol public protocol;
    MerchantVault public vault;
    MockERC20Vault public usdc;
    address public arbiter = address(0xA11);
    address public owner = address(0xB22);
    address public stranger = address(0xBAD);
    address public merchant = address(0xC0);
    address public customer = address(0xD0);
    address public refundTo = address(0xE0);

    function setUp() public {
        usdc = new MockERC20Vault("USDC", "USDC");
        protocol = new RefundProtocol(owner, arbiter, address(usdc), "Refund Protocol", "1.0");
        vault = new MerchantVault(owner, address(protocol), address(usdc));
        usdc.mint(address(vault), 10_000 ether);
    }

    function testEscrowToRefundProtocol() public {
        bytes32 h = keccak256(bytes("wc-1"));
        vm.prank(owner);
        vault.escrowToRefundProtocol(merchant, customer, 100 ether, refundTo, h);

        assertEq(usdc.balanceOf(address(protocol)), 100 ether);
        assertEq(usdc.balanceOf(address(vault)), 10_000 ether - 100 ether);
        assertEq(protocol.balances(merchant), 100 ether);
        (address p, uint256 a) = protocol.getInfo(h);
        assertEq(p, customer);
        assertEq(a, 100 ether);
    }

    function testNonOwnerReverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vault.escrowToRefundProtocol(merchant, customer, 1 ether, refundTo, bytes32(0));
    }

    function testConstructorZeroProtocolReverts() public {
        vm.expectRevert(MerchantVault.ZeroAddress.selector);
        new MerchantVault(owner, address(0), address(usdc));
    }
}
