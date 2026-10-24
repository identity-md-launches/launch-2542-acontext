// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {AcontextToken} from "../src/AcontextToken.sol";

/// @dev Closed actor set with an independent ledger for all balances and allowances.
///      Inputs are bounded using the model, never the token's possibly incorrect state.
contract AcontextHandler is Test {
    AcontextToken private immutable token;
    address[4] public actors = [address(0x1001), address(0x1002), address(0x1003), address(0x1004)];
    mapping(address => uint256) public modelBalance;
    mapping(address => mapping(address => uint256)) public modelAllowance;

    constructor(AcontextToken token_) {
        token = token_;
        modelBalance[actors[0]] = 1_000_000_000_000_000_000_000_000_000;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        amount = bound(amount, 0, modelBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        modelBalance[from] -= amount;
        modelBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        modelAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % 4];
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 approved = modelAllowance[from][spender];
        uint256 held = modelBalance[from];
        amount = bound(amount, 0, approved < held ? approved : held);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        modelBalance[from] -= amount;
        modelBalance[to] += amount;
        if (approved != type(uint256).max) modelAllowance[from][spender] -= amount;
    }

    function attemptOverdraw(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 held = modelBalance[from];
        amount = bound(amount, held + 1, type(uint256).max);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        token.transfer(to, amount);
    }

    function attemptUnauthorizedSpend(uint256 fromSeed, uint256 spenderSeed) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 approved = modelAllowance[from][spender];
        if (approved == type(uint256).max) return;
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        token.transferFrom(from, spender, approved + 1);
    }

    function attemptZeroReceiver(uint256 fromSeed) external {
        address from = actors[fromSeed % 4];
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }
}

contract AcontextInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    AcontextToken private token;
    AcontextHandler private handler;

    function setUp() public {
        token = new AcontextToken();
        handler = new AcontextHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.attemptOverdraw.selector;
        selectors[4] = handler.attemptUnauthorizedSpend.selector;
        selectors[5] = handler.attemptZeroReceiver.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyIsFixedAndEveryTokenIsAccountedFor() public view {
        uint256 total;
        for (uint256 i; i < 4; ++i) {
            total += token.balanceOf(handler.actors(i));
        }
        assertEq(total, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_balancesMatchIndependentLedger() public view {
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.modelBalance(actor));
        }
    }

    function invariant_allowancesMatchIndependentLedger() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.modelAllowance(owner, spender));
            }
        }
    }
}
