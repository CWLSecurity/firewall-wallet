// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {PolicyRouter} from "../../src/PolicyRouter.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {MockPolicy} from "../mocks/MockPolicies.sol";

contract PolicyRouterTest is Test {
    function test_Constructor_RevertsOnZeroPolicies() public {
        address[] memory _policies = new address[](0);

        vm.expectRevert();
        new PolicyRouter(_policies);
    }

    function test_PolicyCount() public {
        MockPolicy p1 = new MockPolicy(Decision.Allow, 0);
        MockPolicy p2 = new MockPolicy(Decision.Delay, 10);
        MockPolicy p3 = new MockPolicy(Decision.Revert, 0);

       address[] memory _policies = new address[](3);
        _policies[0] = address(p1);
        _policies[1] = address(p2);
        _policies[2] = address(p3);

        PolicyRouter r = new PolicyRouter(_policies);
        assertEq(r.policyCount(), 3);
    }

    function test_Evaluate_PrioritizesRevert() public {
        MockPolicy allowP = new MockPolicy(Decision.Allow, 0);
        MockPolicy delayP = new MockPolicy(Decision.Delay, 100);
        MockPolicy revertP = new MockPolicy(Decision.Revert, 0);

        address[] memory _policies = new address[](3);
        _policies[0] = address(allowP);
        _policies[1] = address(delayP);
        _policies[2] = address(revertP);

        PolicyRouter r = new PolicyRouter(_policies);

        (Decision d, uint48 delay) = r.evaluate(address(0xCAFE), address(this), 0, "");

        assertEq(uint256(d), uint256(Decision.Revert));
        assertEq(uint256(delay), 0);
    }

    function test_Evaluate_ReturnsDelayWhenNoRevert() public {
        MockPolicy allowP1 = new MockPolicy(Decision.Allow, 0);
        MockPolicy delayP = new MockPolicy(Decision.Delay, 123);
        MockPolicy allowP2 = new MockPolicy(Decision.Allow, 0);

        address[] memory _policies = new address[](3);
        _policies[0] = address(allowP1);
        _policies[1] = address(delayP);
        _policies[2] = address(allowP2);

        PolicyRouter r = new PolicyRouter(_policies);

        (Decision d, uint48 delay) = r.evaluate(address(0xCAFE), address(this), 0, "");

        assertEq(uint256(d), uint256(Decision.Delay));
        assertEq(uint256(delay), 123);
    }

    function test_Evaluate_AllAllow() public {
        MockPolicy p1 = new MockPolicy(Decision.Allow, 0);
        MockPolicy p2 = new MockPolicy(Decision.Allow, 0);

        address[] memory _policies = new address[](2);
        _policies[0] = address(p1);
        _policies[1] = address(p2);

        PolicyRouter r = new PolicyRouter(_policies);

        (Decision d, uint48 delay) = r.evaluate(address(0xCAFE), address(this), 0, "");

        assertEq(uint256(d), uint256(Decision.Allow));
        assertEq(uint256(delay), 0);
    }
}
