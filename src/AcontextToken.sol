// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Acontext (ACON)
/// @notice Fixed-supply ERC-20 with 18 decimals and the entire supply minted to its deployer.
/// @dev On the IMD launch, msg.sender is the factory that distributes the supply.
contract AcontextToken is ERC20 {
    /// @notice One billion tokens, expressed in the token's smallest unit.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Acontext", "ACON") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
