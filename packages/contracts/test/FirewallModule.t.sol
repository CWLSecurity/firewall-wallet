pragma solidity ^0.8.23;

import "forge-std/Test.sol";

// Импортируем сам контракт + ошибки (они на уровне файла)
import {
    FirewallModule,
    Firewall_NotInitialized,
    Firewall_Unauthorized,
    Firewall_RevertedByPolicy,
    Firewall_AllowNotSchedulable,
    Firewall_NotScheduled,
    Firewall_NotUnlocked,
    Firewall_AlreadyExecuted,
    Firewall_ExecutionFailed
} from "../src/FirewallModule.sol";

import {Decision} from "../src/interfaces/IFirewallPolicy.sol";

contract MockRouter {
    Decision public decision;
    uint48 public delaySeconds;

    uint256 public notifyCalls;

    constructor(Decision d, uint48 delay) {
        decision = d;
        delaySeconds = delay;
    }

    function evaluate(
        address,
        address,
        uint256,
        bytes calldata
    ) external view returns (Decision, uint48) {
        return (decision, delaySeconds);
    }

    function notifyExecuted(
        address,
        address,
        uint256,
        bytes calldata
    ) external {
        notifyCalls++;
    }
}

contract MockReceiver {
    address public lastSender;
    uint256 public lastValue;
    bytes public lastData;

    receive() external payable {
        lastSender = msg.sender;
        lastValue = msg.value;
        lastData = "";
    }

    fallback() external payable {
        lastSender = msg.sender;
        lastValue = msg.value;
        lastData = msg.data;
    }
}

contract RevertingReceiver {
    fallback() external payable {
        revert("NOPE");
    }

    receive() external payable {
        revert("NOPE");
    }
}

contract FirewallModuleTest is Test {
    address internal OWNER = address(0xA11CE);
    address internal RECOVERY = address(0xB0B);

    MockReceiver internal receiver;

    function setUp() public {
        receiver = new MockReceiver();
    }

    function _deployAndInit(address router) internal returns (FirewallModule m) {
        m = new FirewallModule();
        vm.prank(OWNER);
        m.init(router, OWNER, RECOVERY);
    }

    // -------------------- init / auth --------------------

    function testInit_secondInit_revertsUnauthorized() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(OWNER);
        vm.expectRevert(Firewall_Unauthorized.selector);
        m.init(address(r), OWNER, RECOVERY);
    }

    function testExecuteNow_onlyOwner_revertsForNonOwner() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(address(0xDEAD));
        vm.expectRevert(Firewall_Unauthorized.selector);
        m.executeNow(address(receiver), 0.1 ether, "");
    }

    function testSchedule_onlyOwner_revertsForNonOwner() public {
        MockRouter r = new MockRouter(Decision.Delay, 5);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(address(0xDEAD));
        vm.expectRevert(Firewall_Unauthorized.selector);
        m.schedule(address(receiver), 0.1 ether, "");
    }

    function testExecuteScheduled_onlyOwner_revertsForNonOwner() public {
        MockRouter r = new MockRouter(Decision.Delay, 5);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(address(0xDEAD));
        vm.expectRevert(Firewall_Unauthorized.selector);
        m.executeScheduled(bytes32(uint256(1)));
    }

    // -------------------- executeNow --------------------

    function testExecuteNow_whenAllow_executesAndNotifies() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.expectCall(
            address(r),
            abi.encodeWithSelector(
                MockRouter.evaluate.selector,
                address(m),
                address(receiver),
                0.2 ether,
                bytes("")
            )
        );

        vm.expectCall(
            address(r),
            abi.encodeWithSelector(
                MockRouter.notifyExecuted.selector,
                address(m),
                address(receiver),
                0.2 ether,
                bytes("")
            )
        );

        vm.prank(OWNER);
        m.executeNow(address(receiver), 0.2 ether, "");

        assertEq(address(receiver).balance, 0.2 ether);
        assertEq(receiver.lastSender(), address(m));
        assertEq(receiver.lastValue(), 0.2 ether);
        assertEq(r.notifyCalls(), 1);
    }

    function testExecuteNow_whenDelay_revertsByPolicy() public {
        MockRouter r = new MockRouter(Decision.Delay, 10);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(OWNER);
        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        m.executeNow(address(receiver), 0.2 ether, "");
    }

    function testExecuteNow_whenRevert_revertsByPolicy() public {
        MockRouter r = new MockRouter(Decision.Revert, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(OWNER);
        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        m.executeNow(address(receiver), 0.2 ether, "");
    }

    function testExecuteNow_whenCallFails_revertsExecutionFailed() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        RevertingReceiver bad = new RevertingReceiver();

        vm.prank(OWNER);
        bytes memory expected = abi.encodeWithSignature("Error(string)", "NOPE");

        vm.expectRevert(abi.encodeWithSelector(Firewall_ExecutionFailed.selector, expected));
        m.executeNow(address(bad), 0.1 ether, "");
    }

    // -------------------- schedule --------------------

    function testSchedule_whenAllow_revertsAllowNotSchedulable() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(OWNER);
        vm.expectRevert(Firewall_AllowNotSchedulable.selector);
        m.schedule(address(receiver), 0.1 ether, "");
    }

    function testSchedule_whenRevert_revertsByPolicy() public {
        MockRouter r = new MockRouter(Decision.Revert, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(OWNER);
        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        m.schedule(address(receiver), 0.1 ether, "");
    }

    function testSchedule_whenDelay_returnsTxId() public {
        MockRouter r = new MockRouter(Decision.Delay, 7);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.3 ether, "");

        assertTrue(txId != bytes32(0));
    }

    // -------------------- executeScheduled --------------------

    function testExecuteScheduled_unknownTx_revertsNotScheduled() public {
        MockRouter r = new MockRouter(Decision.Delay, 5);
        FirewallModule m = _deployAndInit(address(r));

        bytes32 txId = bytes32(uint256(123));

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Firewall_NotScheduled.selector, txId));
        m.executeScheduled(txId);
    }

    function testExecuteScheduled_beforeUnlock_revertsNotUnlocked() public {
        MockRouter r = new MockRouter(Decision.Delay, 10);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.4 ether, "");

        vm.prank(OWNER);
        uint256 expectedUnlock = block.timestamp + 10;

        vm.expectRevert(abi.encodeWithSelector(Firewall_NotUnlocked.selector, txId, expectedUnlock));
        m.executeScheduled(txId);
    }

    function testExecuteScheduled_afterUnlock_executesAndNotifies() public {
        MockRouter r = new MockRouter(Decision.Delay, 10);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.5 ether, "");

        vm.warp(block.timestamp + 10);

        vm.expectCall(
            address(r),
            abi.encodeWithSelector(
                MockRouter.notifyExecuted.selector,
                address(m),
                address(receiver),
                0.5 ether,
                bytes("")
            )
        );

        vm.prank(OWNER);
        m.executeScheduled(txId);

        assertEq(address(receiver).balance, 0.5 ether);
        assertEq(receiver.lastSender(), address(m));
        assertEq(receiver.lastValue(), 0.5 ether);
        assertEq(r.notifyCalls(), 1);
    }

    function testExecuteScheduled_twice_revertsAlreadyExecuted() public {
        MockRouter r = new MockRouter(Decision.Delay, 1);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.2 ether, "");

        vm.warp(block.timestamp + 1);

        vm.prank(OWNER);
        m.executeScheduled(txId);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Firewall_AlreadyExecuted.selector, txId));
        m.executeScheduled(txId);
    }

    function testExecuteScheduled_whenCallFails_revertsExecutionFailed() public {
        MockRouter r = new MockRouter(Decision.Delay, 1);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        RevertingReceiver bad = new RevertingReceiver();

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(bad), 0.1 ether, "");

        vm.warp(block.timestamp + 1);

        vm.prank(OWNER);
        bytes memory expected = abi.encodeWithSignature("Error(string)", "NOPE");

        vm.expectRevert(abi.encodeWithSelector(Firewall_ExecutionFailed.selector, expected));
        m.executeScheduled(txId);
    }
}
