// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {AcontextToken} from "../src/AcontextToken.sol";

/// @dev Test-only stand-in for a contract deploying and distributing the token.
contract TokenFactoryHarness {
    function deploy() external returns (AcontextToken) {
        return new AcontextToken();
    }

    function distribute(AcontextToken token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "distribution failed");
    }
}

/// @dev A plain ERC-20 transfer must succeed without invoking this receiver.
contract RejectingReceiver {
    fallback() external {
        revert("no callbacks accepted");
    }
}

contract AcontextTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    AcontextToken private token;

    function setUp() public {
        token = new AcontextToken();
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "Acontext");
        assertEq(token.symbol(), "ACON");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_constructorEmitsWholeSupplyMint() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), address(this), SUPPLY);
        AcontextToken created = new AcontextToken();
        assertEq(created.balanceOf(address(this)), SUPPLY);
    }

    function test_factoryReceivesSupplyInsteadOfTransactionOrigin() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        vm.prank(ALICE, ALICE);
        AcontextToken created = factory.deploy();
        assertEq(created.balanceOf(address(factory)), SUPPLY);
        assertEq(created.balanceOf(ALICE), 0);
        assertEq(created.balanceOf(address(this)), 0);
        assertEq(created.totalSupply(), SUPPLY);
    }

    function test_launchAllocationsClaimsAndPoolTransfersArriveWhole() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        AcontextToken created = factory.deploy();
        address distributor = address(0xD157);
        address pool = address(0x9001);
        address remainder = address(0x9002);

        factory.distribute(created, distributor, SUPPLY / 10);
        factory.distribute(created, pool, SUPPLY * 8 / 10);
        factory.distribute(created, remainder, SUPPLY / 10);
        assertEq(created.balanceOf(address(factory)), 0);
        assertEq(created.balanceOf(distributor), SUPPLY / 10);
        assertEq(created.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(created.balanceOf(remainder), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(created.transfer(ALICE, SUPPLY / 10));
        assertEq(created.balanceOf(distributor), 0);
        assertEq(created.balanceOf(ALICE), SUPPLY / 10);

        // Exercise the token side of receiving from and paying back to a pool.
        // This is a transfer compatibility test, not a Uniswap swap simulation.
        vm.prank(pool);
        assertTrue(created.transfer(BOB, 5 ether));
        assertEq(created.balanceOf(BOB), 5 ether);
        vm.prank(BOB);
        assertTrue(created.transfer(pool, 5 ether));
        assertEq(created.balanceOf(BOB), 0);
        assertEq(created.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(created.totalSupply(), SUPPLY);
    }

    function test_transferEmitsEventAndReturnsTrue() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 7 ether);
        assertTrue(token.transfer(ALICE, 7 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 7 ether);
        assertEq(token.balanceOf(ALICE), 7 ether);
    }

    function test_transferEntireSupplyThenRejectSecondTransfer() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        token.transfer(BOB, 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferLeavesBalanceUnchanged() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertTrue(token.transfer(address(this), 1));
        assertTrue(token.transfer(address(this), 0));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToContractMakesNoCallback() public {
        RejectingReceiver receiver = new RejectingReceiver();
        assertTrue(token.transfer(address(receiver), 1));
        assertEq(token.balanceOf(address(receiver)), 1);
    }

    function test_transferToZeroRevertsIncludingZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferUint256MaxRevertsWithoutChangingBalances() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_approveEmitsEventWithoutMovingTokens() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), SPENDER, 12 ether);
        assertTrue(token.approve(SPENDER, 12 ether));
        assertEq(token.allowance(address(this), SPENDER), 12 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(SPENDER), 0);
    }

    function test_approveReplacesAndRevokesAllowance() public {
        assertTrue(token.approve(SPENDER, 12 ether));
        assertTrue(token.approve(SPENDER, 4 ether));
        assertEq(token.allowance(address(this), SPENDER), 4 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), SPENDER, 0);
        assertTrue(token.approve(SPENDER, 0));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_approvalBelongsToCallerAndNamedSpenderOnly() public {
        assertTrue(token.approve(SPENDER, 100));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 1));
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.allowance(ALICE, SPENDER), 1);
        assertEq(token.allowance(address(this), BOB), 0);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        token.transferFrom(address(this), BOB, 1);
    }

    function test_approveZeroSpenderRevertsIncludingZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_transferFromEmitsTransferAndConsumesFiniteAllowance() public {
        assertTrue(token.approve(SPENDER, 9 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 4 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 4 ether));
        assertEq(token.allowance(address(this), SPENDER), 5 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);
        assertEq(token.balanceOf(ALICE), 4 ether);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 5 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(BOB), 5 ether);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(this), BOB, 1);
    }

    function test_transferFromPreservesInfiniteAllowance() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertTrue(token.transferFrom(address(this), BOB, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromToSelfSpendsAllowanceButPreservesBalance() public {
        assertTrue(token.approve(SPENDER, 8 ether));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 3 ether));
        assertEq(token.allowance(address(this), SPENDER), 5 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromZeroAmountNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromRequiresApprovalEvenFromHolder() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.allowance(address(this), address(this)), 0);
    }

    function test_transferFromInsufficientBalanceRestoresAllowance() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 100));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 100));
        token.transferFrom(ALICE, BOB, 100);
        assertEq(token.allowance(ALICE, SPENDER), 100);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromInvalidReceiverRestoresAllowance() public {
        assertTrue(token.approve(SPENDER, 100));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_deployerCannotSpendHolderBalanceWithoutApproval() public {
        assertTrue(token.transfer(ALICE, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 100);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }

    function test_noMintBurnAdminOrUpgradeEntrypoints() public {
        assertTrue(token.transfer(ALICE, 100));
        bytes[] memory calls = new bytes[](18);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[5] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1);
        calls[6] = abi.encodeWithSignature("pause()");
        calls[7] = abi.encodeWithSignature("unpause()");
        calls[8] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[9] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[10] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[11] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[12] = abi.encodeWithSignature("setMinter(address)", BOB);
        calls[13] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[14] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[15] = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", BOB, bytes(""));
        calls[16] = abi.encodeWithSignature("owner()");
        calls[17] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded, "deployer reached unsupported entrypoint");
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded, "stranger reached unsupported entrypoint");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(ALICE), 100);
            assertEq(token.balanceOf(BOB), 0);
        }
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }

    function test_rejectsNativeCurrencyAndPayableFunctionCalls() public {
        vm.deal(address(this), 2 ether);
        (bool plainTransfer,) = address(token).call{value: 1 ether}("");
        assertFalse(plainTransfer);
        (bool payableApproval,) = address(token).call{value: 1 ether}(abi.encodeCall(token.approve, (SPENDER, 1)));
        assertFalse(payableApproval);
        assertEq(address(token).balance, 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_runtimeAndCreationCodeFitLaunchLimits() public view {
        assertGt(address(token).code.length, 0);
        assertLe(address(token).code.length, 24_576);
        assertLe(type(AcontextToken).creationCode.length, 49_152);
    }

    function test_runtimeHasNoForbiddenReachableOpcodes() public view {
        bytes memory runtime = address(token).code;
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode == 0x5b) reachable = true;
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            if (reachable) {
                assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff, "forbidden runtime opcode");
            }
            if (
                opcode == 0x00 || opcode == 0x56 || opcode == 0xf3 || opcode == 0xfd || opcode == 0xfe || opcode == 0xff
            ) {
                reachable = false;
            }
        }
    }

    function testFuzz_deploymentMintsOnlyToImmediateCaller(address deployer) public {
        vm.assume(deployer != address(0));
        vm.prank(deployer);
        AcontextToken created = new AcontextToken();
        assertEq(created.totalSupply(), SUPPLY);
        assertEq(created.balanceOf(deployer), SUPPLY);
        assertEq(created.balanceOf(address(0)), 0);
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        if (recipient == address(this)) {
            assertEq(token.balanceOf(address(this)), SUPPLY);
        } else {
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
            assertEq(token.balanceOf(recipient), amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalsNeverMoveBalances(address spender, uint256 amount) public {
        vm.assume(spender != address(0));
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(address(this), spender), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromRespectsBalanceAndAllowance(uint256 balance, uint256 approved, uint256 amount)
        public
    {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, 0, approved < balance ? approved : balance);
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approved));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, amount));
        assertEq(token.balanceOf(ALICE), balance - amount);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.allowance(ALICE, SPENDER), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferMoreThanBalanceReverts(uint256 balance, uint256 amount) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max);
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        token.transfer(BOB, amount);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_insufficientAllowanceReverts(uint256 balance, uint256 approved) public {
        balance = bound(balance, 1, SUPPLY);
        approved = bound(approved, 0, balance - 1);
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approved));
        vm.prank(SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, approved + 1)
        );
        token.transferFrom(ALICE, BOB, approved + 1);
        assertEq(token.allowance(ALICE, SPENDER), approved);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testFuzz_failedTransferFromRestoresAllowance(uint256 balance, uint256 requested) public {
        balance = bound(balance, 0, SUPPLY);
        requested = bound(requested, balance + 1, type(uint256).max);
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, requested));
        vm.prank(SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, requested)
        );
        token.transferFrom(ALICE, BOB, requested);
        assertEq(token.allowance(ALICE, SPENDER), requested);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
