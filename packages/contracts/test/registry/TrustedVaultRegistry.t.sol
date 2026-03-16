// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {
    TrustedVaultRegistry,
    TrustedVaultRegistry_Unauthorized
} from "../../src/TrustedVaultRegistry.sol";

contract TrustedVaultRegistryTest is Test {
    TrustedVaultRegistry internal registry;
    address internal registrar = address(0xA11CE);
    address internal vault = address(0xBEEF);

    function setUp() public {
        registry = new TrustedVaultRegistry(address(this));
    }

    function test_OwnerCanSetRegistrarAndRegistrarCanMarkVault() public {
        registry.setRegistrar(registrar, true);
        assertTrue(registry.isRegistrar(registrar));

        vm.prank(registrar);
        registry.setRecognizedVault(vault, true);
        assertTrue(registry.isRecognizedVault(vault));

        vm.prank(registrar);
        registry.setRecognizedVault(vault, false);
        assertFalse(registry.isRecognizedVault(vault));
    }

    function test_NonRegistrarCannotMark() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(TrustedVaultRegistry_Unauthorized.selector);
        registry.setRecognizedVault(vault, true);
    }

    function test_NonOwnerCannotSetRegistrar() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(TrustedVaultRegistry_Unauthorized.selector);
        registry.setRegistrar(registrar, true);
    }
}
