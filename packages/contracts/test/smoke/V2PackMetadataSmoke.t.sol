// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SmokeBase} from "./SmokeBase.t.sol";

contract V2PackMetadataSmoke is SmokeBase {
    function setUp() public {
        _deployV2WithRealBasePacks();
    }

    function test_CanonicalPacks_AreEnumerableAndReconstructable() public view {
        assertEq(registry.packCount(), 5);
        assertEq(registry.packIdAt(0), BASE_PACK_CONSERVATIVE);
        assertEq(registry.packIdAt(1), BASE_PACK_DEFI);
        assertEq(registry.packIdAt(2), ADDON_PACK_APPROVAL_HARDENING);
        assertEq(registry.packIdAt(3), ADDON_PACK_NEW_RECEIVER_24H);
        assertEq(registry.packIdAt(4), ADDON_PACK_LARGE_TRANSFER_24H);

        uint256[] memory ids = registry.packIds();
        assertEq(ids.length, 5);
        assertEq(ids[0], BASE_PACK_CONSERVATIVE);
        assertEq(ids[1], BASE_PACK_DEFI);
        assertEq(ids[2], ADDON_PACK_APPROVAL_HARDENING);
        assertEq(ids[3], ADDON_PACK_NEW_RECEIVER_24H);
        assertEq(ids[4], ADDON_PACK_LARGE_TRANSFER_24H);

        (
            bool conservativeActive,
            uint8 conservativeType,
            bytes32 conservativeMetadata,
            string memory conservativeSlug,
            uint16 conservativeVersion,
            uint256 conservativePolicyCount
        ) = registry.getPackMeta(BASE_PACK_CONSERVATIVE);
        assertTrue(conservativeActive);
        assertEq(conservativeType, registry.PACK_TYPE_BASE());
        assertEq(conservativeMetadata, keccak256("base-conservative"));
        assertEq(conservativeSlug, "base-conservative");
        assertEq(conservativeVersion, PACK_VERSION_V1);
        assertEq(conservativePolicyCount, 3);

        address[] memory conservativePolicies = registry.getPackPolicies(BASE_PACK_CONSERVATIVE);
        assertEq(conservativePolicies.length, 3);
        assertEq(conservativePolicies[0], address(conservativeApprove));
        assertEq(conservativePolicies[1], address(conservativeLargeTransfer));
        assertEq(conservativePolicies[2], address(conservativeNewReceiver));

        (
            bool defiActive,
            uint8 defiType,
            bytes32 defiMetadata,
            string memory defiSlug,
            uint16 defiVersion,
            uint256 defiPolicyCount
        ) = registry.getPackMeta(BASE_PACK_DEFI);
        assertTrue(defiActive);
        assertEq(defiType, registry.PACK_TYPE_BASE());
        assertEq(defiMetadata, keccak256("base-defi"));
        assertEq(defiSlug, "base-defi");
        assertEq(defiVersion, PACK_VERSION_V1);
        assertEq(defiPolicyCount, 5);

        address[] memory defiPolicies = registry.getPackPolicies(BASE_PACK_DEFI);
        assertEq(defiPolicies.length, 5);
        assertEq(defiPolicies[0], address(defiApprove));
        assertEq(defiPolicies[1], address(defiApprovalToNewSpender));
        assertEq(defiPolicies[2], address(defiErc20FirstRecipient));
        assertEq(defiPolicies[3], address(defiLargeTransfer));
        assertEq(defiPolicies[4], address(defiNewReceiver));

        (
            bool addonActive,
            uint8 addonType,
            bytes32 addonMetadata,
            string memory addonSlug,
            uint16 addonVersion,
            uint256 addonPolicyCount
        ) = registry.getPackMeta(ADDON_PACK_APPROVAL_HARDENING);
        assertTrue(addonActive);
        assertEq(addonType, registry.PACK_TYPE_ADDON());
        assertEq(addonMetadata, keccak256("addon-approval-hardening"));
        assertEq(addonSlug, "addon-approval-hardening");
        assertEq(addonVersion, PACK_VERSION_V1);
        assertEq(addonPolicyCount, 1);

        address[] memory approvalHardeningPolicies = registry.getPackPolicies(ADDON_PACK_APPROVAL_HARDENING);
        assertEq(approvalHardeningPolicies.length, 1);
        assertEq(approvalHardeningPolicies[0], address(addonApprovalHardening));

        (
            bool newReceiverActive,
            uint8 newReceiverType,
            bytes32 newReceiverMetadata,
            string memory newReceiverSlug,
            uint16 newReceiverVersion,
            uint256 newReceiverPolicyCount
        ) = registry.getPackMeta(ADDON_PACK_NEW_RECEIVER_24H);
        assertTrue(newReceiverActive);
        assertEq(newReceiverType, registry.PACK_TYPE_ADDON());
        assertEq(newReceiverMetadata, keccak256("addon-new-receiver-24h-delay"));
        assertEq(newReceiverSlug, "addon-new-receiver-24h-delay");
        assertEq(newReceiverVersion, PACK_VERSION_V1);
        assertEq(newReceiverPolicyCount, 1);

        address[] memory newReceiverPolicies = registry.getPackPolicies(ADDON_PACK_NEW_RECEIVER_24H);
        assertEq(newReceiverPolicies.length, 1);
        assertEq(newReceiverPolicies[0], address(addonNewReceiver));

        (
            bool largeTransferActive,
            uint8 largeTransferType,
            bytes32 largeTransferMetadata,
            string memory largeTransferSlug,
            uint16 largeTransferVersion,
            uint256 largeTransferPolicyCount
        ) = registry.getPackMeta(ADDON_PACK_LARGE_TRANSFER_24H);
        assertTrue(largeTransferActive);
        assertEq(largeTransferType, registry.PACK_TYPE_ADDON());
        assertEq(largeTransferMetadata, keccak256("addon-large-transfer-24h-delay"));
        assertEq(largeTransferSlug, "addon-large-transfer-24h-delay");
        assertEq(largeTransferVersion, PACK_VERSION_V1);
        assertEq(largeTransferPolicyCount, 1);

        address[] memory largeTransferPolicies = registry.getPackPolicies(ADDON_PACK_LARGE_TRANSFER_24H);
        assertEq(largeTransferPolicies.length, 1);
        assertEq(largeTransferPolicies[0], address(addonLargeTransfer));
    }
}
