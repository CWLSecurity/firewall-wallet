// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {LargeTransferDelayPolicy} from "../../src/policies/LargeTransferDelayPolicy.sol";
import {ApprovalToNewSpenderDelayPolicy} from "../../src/policies/ApprovalToNewSpenderDelayPolicy.sol";
import {NewReceiverDelayPolicy} from "../../src/policies/NewReceiverDelayPolicy.sol";
import {NewEOAReceiverDelayPolicy} from "../../src/policies/NewEOAReceiverDelayPolicy.sol";
import {MockReceiver} from "../../src/mocks/MockReceiver.sol";

contract MockVaultWithRouterMatrix {
    address public immutable router;

    constructor(address router_) {
        router = router_;
    }
}

contract V2PolicyUserScenarioMatrixTest is Test {
    uint256 internal constant CONSERVATIVE_THRESHOLD = 0.05 ether;
    uint48 internal constant CONSERVATIVE_DELAY = 1 hours;

    uint48 internal constant APPROVAL_DELAY = 30 minutes;
    uint48 internal constant RECEIVER_DELAY = 1 hours;
    uint48 internal constant EOA_DELAY = 30 minutes;

    address internal constant ROUTER = address(0xAA11AA11);
    address internal constant TOKEN = address(0x1000);
    address internal constant EOA_SPENDER = address(0xBEEF);

    LargeTransferDelayPolicy internal conservativeLarge;
    ApprovalToNewSpenderDelayPolicy internal approvalPolicy;
    NewReceiverDelayPolicy internal newReceiverPolicy;
    NewEOAReceiverDelayPolicy internal newEoaPolicy;
    MockVaultWithRouterMatrix internal vault;
    MockReceiver internal contractSpender;
    MockReceiver internal contractTarget;

    function setUp() public {
        conservativeLarge = new LargeTransferDelayPolicy(CONSERVATIVE_THRESHOLD, CONSERVATIVE_THRESHOLD, CONSERVATIVE_DELAY);
        approvalPolicy = new ApprovalToNewSpenderDelayPolicy(APPROVAL_DELAY);
        newReceiverPolicy = new NewReceiverDelayPolicy(RECEIVER_DELAY);
        newEoaPolicy = new NewEOAReceiverDelayPolicy(EOA_DELAY);

        vault = new MockVaultWithRouterMatrix(ROUTER);
        contractSpender = new MockReceiver();
        contractTarget = new MockReceiver();
    }

    function _assertLargeEth(uint256 value, Decision expectedDecision, uint48 expectedDelay) internal view {
        (Decision decision, uint48 delayOut) = conservativeLarge.evaluate(address(vault), address(0xCAFE), value, "");
        assertEq(uint256(decision), uint256(expectedDecision), "unexpected decision for ETH transfer");
        assertEq(delayOut, expectedDelay, "unexpected delay for ETH transfer");
    }

    function _assertLargeErc20(uint256 amount, Decision expectedDecision, uint48 expectedDelay) internal view {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", address(0xCAFE), amount);
        (Decision decision, uint48 delayOut) = conservativeLarge.evaluate(address(vault), TOKEN, 0, data);
        assertEq(uint256(decision), uint256(expectedDecision), "unexpected decision for ERC20 transfer");
        assertEq(delayOut, expectedDelay, "unexpected delay for ERC20 transfer");
    }

    function _assertApprovalEoaRevert(uint256 amount) internal view {
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", EOA_SPENDER, amount);
        (Decision decision, uint48 delayOut) = approvalPolicy.evaluate(address(vault), TOKEN, 0, data);
        assertEq(uint256(decision), uint256(Decision.Revert), "EOA non-zero approval must revert");
        assertEq(delayOut, 0, "revert path delay must be zero");
    }

    function _assertApprovalContractDelayThenAllow(uint256 amount) internal {
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(contractSpender), amount);

        (Decision firstDecision, uint48 firstDelay) = approvalPolicy.evaluate(address(vault), TOKEN, 0, data);
        assertEq(uint256(firstDecision), uint256(Decision.Delay), "first contract approval should delay");
        assertEq(firstDelay, APPROVAL_DELAY, "unexpected approval delay");

        vm.prank(ROUTER);
        approvalPolicy.onExecuted(address(vault), TOKEN, 0, data);

        (Decision secondDecision, uint48 secondDelay) = approvalPolicy.evaluate(address(vault), TOKEN, 0, data);
        assertEq(uint256(secondDecision), uint256(Decision.Allow), "known contract approval should allow");
        assertEq(secondDelay, 0, "allow path delay must be zero");
    }

    function _assertNewReceiverDelayThenAllow(address receiver) internal {
        (Decision firstDecision, uint48 firstDelay) = newReceiverPolicy.evaluate(address(vault), receiver, 0, "");
        assertEq(uint256(firstDecision), uint256(Decision.Delay), "new receiver must delay");
        assertEq(firstDelay, RECEIVER_DELAY, "unexpected new receiver delay");

        vm.prank(ROUTER);
        newReceiverPolicy.onExecuted(address(vault), receiver, 0, "");

        (Decision secondDecision, uint48 secondDelay) = newReceiverPolicy.evaluate(address(vault), receiver, 0, "");
        assertEq(uint256(secondDecision), uint256(Decision.Allow), "known receiver must allow");
        assertEq(secondDelay, 0, "allow path delay must be zero");
    }

    function _assertUnknownSelectorDelayThenAllow(bytes4 selector) internal {
        bytes memory data = abi.encodeWithSelector(selector, uint256(1));

        (Decision firstDecision, uint48 firstDelay) = newEoaPolicy.evaluate(address(vault), address(contractTarget), 0, data);
        assertEq(uint256(firstDecision), uint256(Decision.Delay), "first selector on contract target must delay");
        assertEq(firstDelay, EOA_DELAY, "unexpected selector delay");

        vm.prank(ROUTER);
        newEoaPolicy.onExecuted(address(vault), address(contractTarget), 0, data);

        (Decision secondDecision, uint48 secondDelay) = newEoaPolicy.evaluate(address(vault), address(contractTarget), 0, data);
        assertEq(uint256(secondDecision), uint256(Decision.Allow), "known selector on contract target must allow");
        assertEq(secondDelay, 0, "allow path delay must be zero");
    }

    function test_UserScenario_001_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 1, Decision.Allow, 0);
    }

    function test_UserScenario_002_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 2, Decision.Allow, 0);
    }

    function test_UserScenario_003_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 3, Decision.Allow, 0);
    }

    function test_UserScenario_004_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 4, Decision.Allow, 0);
    }

    function test_UserScenario_005_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 5, Decision.Allow, 0);
    }

    function test_UserScenario_006_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 6, Decision.Allow, 0);
    }

    function test_UserScenario_007_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 7, Decision.Allow, 0);
    }

    function test_UserScenario_008_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 8, Decision.Allow, 0);
    }

    function test_UserScenario_009_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 9, Decision.Allow, 0);
    }

    function test_UserScenario_010_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 10, Decision.Allow, 0);
    }

    function test_UserScenario_011_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 11, Decision.Allow, 0);
    }

    function test_UserScenario_012_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 12, Decision.Allow, 0);
    }

    function test_UserScenario_013_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 13, Decision.Allow, 0);
    }

    function test_UserScenario_014_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 14, Decision.Allow, 0);
    }

    function test_UserScenario_015_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 15, Decision.Allow, 0);
    }

    function test_UserScenario_016_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 16, Decision.Allow, 0);
    }

    function test_UserScenario_017_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 17, Decision.Allow, 0);
    }

    function test_UserScenario_018_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 18, Decision.Allow, 0);
    }

    function test_UserScenario_019_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 19, Decision.Allow, 0);
    }

    function test_UserScenario_020_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 20, Decision.Allow, 0);
    }

    function test_UserScenario_021_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 21, Decision.Allow, 0);
    }

    function test_UserScenario_022_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 22, Decision.Allow, 0);
    }

    function test_UserScenario_023_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 23, Decision.Allow, 0);
    }

    function test_UserScenario_024_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 24, Decision.Allow, 0);
    }

    function test_UserScenario_025_ConservativeEthBelowThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD - 25, Decision.Allow, 0);
    }

    function test_UserScenario_026_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 0, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_027_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 1, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_028_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 2, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_029_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 3, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_030_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 4, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_031_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 5, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_032_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 6, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_033_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 7, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_034_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 8, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_035_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 9, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_036_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 10, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_037_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 11, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_038_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 12, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_039_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 13, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_040_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 14, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_041_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 15, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_042_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 16, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_043_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 17, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_044_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 18, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_045_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 19, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_046_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 20, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_047_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 21, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_048_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 22, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_049_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 23, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_050_ConservativeEthAtOrAboveThreshold() public view {
        _assertLargeEth(CONSERVATIVE_THRESHOLD + 24, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_051_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 1, Decision.Allow, 0);
    }

    function test_UserScenario_052_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 2, Decision.Allow, 0);
    }

    function test_UserScenario_053_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 3, Decision.Allow, 0);
    }

    function test_UserScenario_054_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 4, Decision.Allow, 0);
    }

    function test_UserScenario_055_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 5, Decision.Allow, 0);
    }

    function test_UserScenario_056_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 6, Decision.Allow, 0);
    }

    function test_UserScenario_057_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 7, Decision.Allow, 0);
    }

    function test_UserScenario_058_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 8, Decision.Allow, 0);
    }

    function test_UserScenario_059_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 9, Decision.Allow, 0);
    }

    function test_UserScenario_060_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 10, Decision.Allow, 0);
    }

    function test_UserScenario_061_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 11, Decision.Allow, 0);
    }

    function test_UserScenario_062_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 12, Decision.Allow, 0);
    }

    function test_UserScenario_063_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 13, Decision.Allow, 0);
    }

    function test_UserScenario_064_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 14, Decision.Allow, 0);
    }

    function test_UserScenario_065_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 15, Decision.Allow, 0);
    }

    function test_UserScenario_066_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 16, Decision.Allow, 0);
    }

    function test_UserScenario_067_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 17, Decision.Allow, 0);
    }

    function test_UserScenario_068_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 18, Decision.Allow, 0);
    }

    function test_UserScenario_069_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 19, Decision.Allow, 0);
    }

    function test_UserScenario_070_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 20, Decision.Allow, 0);
    }

    function test_UserScenario_071_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 21, Decision.Allow, 0);
    }

    function test_UserScenario_072_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 22, Decision.Allow, 0);
    }

    function test_UserScenario_073_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 23, Decision.Allow, 0);
    }

    function test_UserScenario_074_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 24, Decision.Allow, 0);
    }

    function test_UserScenario_075_ConservativeErc20BelowThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD - 25, Decision.Allow, 0);
    }

    function test_UserScenario_076_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 0, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_077_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 1, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_078_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 2, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_079_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 3, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_080_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 4, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_081_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 5, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_082_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 6, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_083_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 7, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_084_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 8, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_085_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 9, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_086_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 10, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_087_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 11, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_088_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 12, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_089_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 13, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_090_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 14, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_091_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 15, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_092_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 16, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_093_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 17, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_094_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 18, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_095_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 19, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_096_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 20, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_097_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 21, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_098_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 22, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_099_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 23, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_100_ConservativeErc20AtOrAboveThreshold() public view {
        _assertLargeErc20(CONSERVATIVE_THRESHOLD + 24, Decision.Delay, CONSERVATIVE_DELAY);
    }

    function test_UserScenario_101_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(1);
    }

    function test_UserScenario_102_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(2);
    }

    function test_UserScenario_103_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(3);
    }

    function test_UserScenario_104_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(4);
    }

    function test_UserScenario_105_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(5);
    }

    function test_UserScenario_106_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(6);
    }

    function test_UserScenario_107_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(7);
    }

    function test_UserScenario_108_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(8);
    }

    function test_UserScenario_109_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(9);
    }

    function test_UserScenario_110_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(10);
    }

    function test_UserScenario_111_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(11);
    }

    function test_UserScenario_112_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(12);
    }

    function test_UserScenario_113_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(13);
    }

    function test_UserScenario_114_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(14);
    }

    function test_UserScenario_115_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(15);
    }

    function test_UserScenario_116_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(16);
    }

    function test_UserScenario_117_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(17);
    }

    function test_UserScenario_118_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(18);
    }

    function test_UserScenario_119_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(19);
    }

    function test_UserScenario_120_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(20);
    }

    function test_UserScenario_121_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(21);
    }

    function test_UserScenario_122_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(22);
    }

    function test_UserScenario_123_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(23);
    }

    function test_UserScenario_124_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(24);
    }

    function test_UserScenario_125_ApprovalEoaNonZeroReverts() public view {
        _assertApprovalEoaRevert(25);
    }

    function test_UserScenario_126_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(1);
    }

    function test_UserScenario_127_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(2);
    }

    function test_UserScenario_128_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(3);
    }

    function test_UserScenario_129_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(4);
    }

    function test_UserScenario_130_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(5);
    }

    function test_UserScenario_131_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(6);
    }

    function test_UserScenario_132_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(7);
    }

    function test_UserScenario_133_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(8);
    }

    function test_UserScenario_134_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(9);
    }

    function test_UserScenario_135_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(10);
    }

    function test_UserScenario_136_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(11);
    }

    function test_UserScenario_137_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(12);
    }

    function test_UserScenario_138_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(13);
    }

    function test_UserScenario_139_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(14);
    }

    function test_UserScenario_140_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(15);
    }

    function test_UserScenario_141_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(16);
    }

    function test_UserScenario_142_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(17);
    }

    function test_UserScenario_143_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(18);
    }

    function test_UserScenario_144_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(19);
    }

    function test_UserScenario_145_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(20);
    }

    function test_UserScenario_146_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(21);
    }

    function test_UserScenario_147_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(22);
    }

    function test_UserScenario_148_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(23);
    }

    function test_UserScenario_149_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(24);
    }

    function test_UserScenario_150_ApprovalContractDelaysThenAllows() public {
        _assertApprovalContractDelayThenAllow(25);
    }

    function test_UserScenario_151_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28673));
    }

    function test_UserScenario_152_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28674));
    }

    function test_UserScenario_153_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28675));
    }

    function test_UserScenario_154_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28676));
    }

    function test_UserScenario_155_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28677));
    }

    function test_UserScenario_156_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28678));
    }

    function test_UserScenario_157_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28679));
    }

    function test_UserScenario_158_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28680));
    }

    function test_UserScenario_159_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28681));
    }

    function test_UserScenario_160_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28682));
    }

    function test_UserScenario_161_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28683));
    }

    function test_UserScenario_162_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28684));
    }

    function test_UserScenario_163_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28685));
    }

    function test_UserScenario_164_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28686));
    }

    function test_UserScenario_165_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28687));
    }

    function test_UserScenario_166_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28688));
    }

    function test_UserScenario_167_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28689));
    }

    function test_UserScenario_168_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28690));
    }

    function test_UserScenario_169_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28691));
    }

    function test_UserScenario_170_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28692));
    }

    function test_UserScenario_171_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28693));
    }

    function test_UserScenario_172_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28694));
    }

    function test_UserScenario_173_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28695));
    }

    function test_UserScenario_174_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28696));
    }

    function test_UserScenario_175_NewReceiverDelaysThenAllows() public {
        _assertNewReceiverDelayThenAllow(address(28697));
    }

    function test_UserScenario_176_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000001));
    }

    function test_UserScenario_177_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000002));
    }

    function test_UserScenario_178_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000003));
    }

    function test_UserScenario_179_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000004));
    }

    function test_UserScenario_180_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000005));
    }

    function test_UserScenario_181_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000006));
    }

    function test_UserScenario_182_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000007));
    }

    function test_UserScenario_183_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000008));
    }

    function test_UserScenario_184_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000009));
    }

    function test_UserScenario_185_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f00000a));
    }

    function test_UserScenario_186_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f00000b));
    }

    function test_UserScenario_187_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f00000c));
    }

    function test_UserScenario_188_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f00000d));
    }

    function test_UserScenario_189_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f00000e));
    }

    function test_UserScenario_190_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f00000f));
    }

    function test_UserScenario_191_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000010));
    }

    function test_UserScenario_192_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000011));
    }

    function test_UserScenario_193_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000012));
    }

    function test_UserScenario_194_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000013));
    }

    function test_UserScenario_195_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000014));
    }

    function test_UserScenario_196_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000015));
    }

    function test_UserScenario_197_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000016));
    }

    function test_UserScenario_198_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000017));
    }

    function test_UserScenario_199_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000018));
    }

    function test_UserScenario_200_UnknownContractSelectorDelaysThenAllows() public {
        _assertUnknownSelectorDelayThenAllow(bytes4(0x7f000019));
    }
}
