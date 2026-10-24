// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {AcontextToken} from "src/AcontextToken.sol";

/// @notice Additional sequence and algebraic properties for the fixed-supply token.
/// forge-config: default.fuzz.runs = 1024
contract AcontextPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    address private constant OTHER_SPENDER = address(0x5EED2);

    AcontextToken private token;

    function setUp() public {
        token = new AcontextToken();
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        AcontextToken created = new AcontextToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(created));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(created.totalSupply(), SUPPLY);
        assertEq(created.balanceOf(address(this)), SUPPLY);
    }

    function test_largestFiniteAllowanceIsNotInfinite() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(SPENDER, approved));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), approved - 1);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY - 1));
        assertEq(token.allowance(address(this), SPENDER), approved - SUPPLY);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteApprovalCanBeReplacedAndRevoked() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);

        assertTrue(token.approve(SPENDER, 2));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), 1);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertTrue(token.approve(SPENDER, 0));

        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.balanceOf(ALICE), 2);
    }

    function test_approvalBeforeFundingCanSpendFutureDeposits() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 10));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10));
        token.transferFrom(ALICE, BOB, 10);
        assertEq(token.allowance(ALICE, SPENDER), 10);

        assertTrue(token.transfer(ALICE, 10));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 10));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 10);
    }

    function test_returningTokensDoesNotRestoreSpentAllowance() public {
        assertTrue(token.transfer(ALICE, 10));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 10));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 10));
        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, 10));

        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_selfTransfersStillCheckBalance() public {
        assertTrue(token.transfer(ALICE, 1));
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1, 2));
        token.transfer(ALICE, 2);

        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 2));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1, 2));
        token.transferFrom(ALICE, ALICE, 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.allowance(ALICE, SPENDER), 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroValueDelegatedTransferRejectsZeroEndpoints() public {
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(ALICE, address(0), 0);

        // A zero amount must not let an invalid owner through. The call may fail
        // during allowance validation before it reaches sender validation.
        vm.prank(SPENDER);
        vm.expectRevert();
        token.transferFrom(address(0), BOB, 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.allowance(address(0), SPENDER), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_failedInfiniteSpendLeavesApprovalUsable() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);

        assertTrue(token.transfer(ALICE, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 1);
    }

    function test_directTransfersDoNotConsumeAnAllowance() public {
        assertTrue(token.approve(ALICE, SUPPLY));
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.allowance(address(this), ALICE), SUPPLY);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.allowance(address(this), ALICE), SUPPLY);

        vm.prank(ALICE);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), ALICE), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function testFuzz_transferRoundTripRestoresBalances(uint256 aliceBalance, uint256 amount) public {
        aliceBalance = bound(aliceBalance, 0, SUPPLY);
        amount = bound(amount, 0, aliceBalance);
        assertTrue(token.transfer(ALICE, aliceBalance));
        assertTrue(token.transfer(BOB, SUPPLY - aliceBalance));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, amount));

        assertEq(token.balanceOf(ALICE), aliceBalance);
        assertEq(token.balanceOf(BOB), SUPPLY - aliceBalance);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splittingTransferHasSameResult(uint256 total, uint256 first) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        AcontextToken singleTransferToken = new AcontextToken();
        assertTrue(singleTransferToken.transfer(ALICE, total));
        assertTrue(token.transfer(ALICE, first));
        assertTrue(token.transfer(ALICE, total - first));

        assertEq(token.balanceOf(ALICE), singleTransferToken.balanceOf(ALICE));
        assertEq(token.balanceOf(address(this)), singleTransferToken.balanceOf(address(this)));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(singleTransferToken.totalSupply(), SUPPLY);
    }

    function testFuzz_replacingApprovalIsIdempotent(uint256 previous, uint256 next) public {
        assertTrue(token.approve(SPENDER, previous));
        assertTrue(token.approve(OTHER_SPENDER, previous));
        assertTrue(token.approve(SPENDER, next));
        assertTrue(token.approve(SPENDER, next));

        assertEq(token.allowance(address(this), SPENDER), next);
        assertEq(token.allowance(address(this), OTHER_SPENDER), previous);
        assertEq(token.allowance(SPENDER, address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_spendersShareBalanceButNotAllowance(uint256 held, uint256 firstSpend) public {
        held = bound(held, 1, SUPPLY);
        firstSpend = bound(firstSpend, 1, held);
        assertTrue(token.transfer(ALICE, held));
        vm.startPrank(ALICE);
        assertTrue(token.approve(SPENDER, held));
        assertTrue(token.approve(OTHER_SPENDER, held));
        vm.stopPrank();

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, firstSpend));
        vm.prank(OTHER_SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held - firstSpend, held)
        );
        token.transferFrom(ALICE, BOB, held);
        assertEq(token.allowance(ALICE, OTHER_SPENDER), held);

        vm.prank(OTHER_SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, held - firstSpend));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), held);
        assertEq(token.allowance(ALICE, SPENDER), held - firstSpend);
        assertEq(token.allowance(ALICE, OTHER_SPENDER), firstSpend);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedZeroReceiverSpendIsAtomic(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.approve(SPENDER, approved));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), amount);

        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedTransfersWithOverlappingRoles(uint8 roles, uint256 amount, bool infinite) public {
        // These four cases deliberately cover all role collisions, including
        // owner == spender == receiver; unconstrained addresses rarely collide.
        uint8 mode = roles % 4;
        address spender = mode < 2 ? ALICE : SPENDER;
        address receiver = mode == 0 || mode == 2 ? ALICE : mode == 1 ? BOB : SPENDER;
        amount = bound(amount, 0, SUPPLY);
        uint256 approved = infinite ? type(uint256).max : amount;
        assertTrue(token.transfer(ALICE, SUPPLY));
        vm.prank(ALICE);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(ALICE, receiver, amount));

        assertEq(token.allowance(ALICE, spender), infinite ? type(uint256).max : 0);
        assertEq(token.balanceOf(ALICE), receiver == ALICE ? SUPPLY : SUPPLY - amount);
        assertEq(token.balanceOf(SPENDER), receiver == SPENDER ? amount : 0);
        assertEq(token.balanceOf(BOB), receiver == BOB ? amount : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
