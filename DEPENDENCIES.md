# Vendored dependencies

All imported Solidity sources and their transitive imports are stored as ordinary files under `lib/`. No install step, submodule, remote import, or network access is needed for builds and tests.

## OpenZeppelin/openzeppelin-contracts v5.0.2

- Source archive: https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2
- Archive SHA-256: `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`
- Included files: 6 (import closure and licenses).
- Upstream Solidity source is unmodified.

## foundry-rs/forge-std v1.9.7

- Source archive: https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
- Archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`
- Included files: 21 (import closure and licenses).
- Upstream Solidity source is unmodified.

OpenZeppelin supplies the ERC-20 implementation (MIT). Forge Standard Library supplies test assertions, cheatcode interfaces, and invariant targeting (MIT OR Apache-2.0). Only AcontextToken and its OpenZeppelin imports are production dependencies.
