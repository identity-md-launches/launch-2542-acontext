# Acontext (ACON)

A fixed-supply ERC-20 for the requested IMD custom-token launch. The deployable contract is
`src/AcontextToken.sol:AcontextToken`. Its argument-free constructor mints the entire supply
to its immediate caller. During the IMD launch, that caller is the launch factory.

## Token rules and interface

| Parameter | Value |
| --- | --- |
| Name | `Acontext` |
| Symbol | `ACON` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in minor units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None |
| Constructor native value | `0` |
| Initial recipient | `msg.sender`, the immediate deployer |
| Admin roles / initialization | None |

The public interface is the standard `name`, `symbol`, `decimals`, `totalSupply`, `balanceOf`,
`allowance`, `transfer`, `approve`, and `transferFrom`, plus the read-only `INITIAL_SUPPLY`
constant. Amounts are always integers in minor units; one ACON is `10^18` units.

The implementation inherits the vendored OpenZeppelin Contracts v5.0.2 ERC-20 unchanged.
There is one `_mint` call, in the constructor. No callable mint, burn, owner, pause,
blocklist, confiscation, fee, rebase, upgrade, or token-recovery function exists. The deployer
gets tokens, not administrative privileges. Transfers have no external callbacks or fees.
Transfers to the zero address revert, including transfers of zero units. Transfers to other
contracts are permitted; recipients must be able to manage tokens they receive.

`transfer` and `transferFrom` return `true` on success and emit `Transfer`. Zero-amount and
self-transfers are supported. Failure reverts with the inherited ERC-6093 custom errors and
rolls back both balances and allowances. Construction emits `Transfer(address(0), deployer,
INITIAL_SUPPLY)`.

`approve` replaces the caller's allowance for one nonzero spender and emits `Approval`.
Approving zero revokes it. Finite allowances decrease on `transferFrom`; `uint256.max`
denotes unlimited approval and stays unchanged. This version does not emit `Approval` when
`transferFrom` spends allowance; indexers should query `allowance`. Even a holder calling
`transferFrom` on its own balance needs an allowance; holders can use `transfer` directly.

Holders are responsible for their approvals and recipients. Unlimited approval permits a
spender to transfer any present or future balance until revoked. To replace an existing
nonzero approval safely, first confirm its revocation to zero, then approve the new amount;
an already authorized spender may spend the old allowance before revocation confirms.
Tokens accidentally sent to this token's own address have no recovery path. Ordinary native
currency sends and calls carrying native value are rejected.

## Reproducible offline build and tests

The root Foundry project pins Solidity `0.8.26`, Cancun EVM, optimization at 200 runs,
`bytecode_hash = "none"`, and disabled CBOR metadata. FFI and filesystem cheatcode access
are disabled. The build requires Foundry and that compiler already installed. All Solidity
dependencies are ordinary local files; no installation, RPC, fork, or network is required.
See [DEPENDENCIES.md](DEPENDENCIES.md) for source versions, archive hashes, and licenses.

```sh
forge build --offline
forge test --offline --fuzz-seed 0x9f4c9f09c252c4d5653a7e2f3ebf441ad6038b812ce8db4992ae817cc15a23ab
forge fmt --check
forge build --offline --sizes
slither . --exclude-informational --exclude-optimization --exclude-low
```

The suite tests construction through an EOA and a factory, metadata, mint and transfer
events, whole-supply transfers, zero/self-transfers, approvals, revocation, finite and
unlimited allowances, invalid receivers, insufficient balances and approvals, atomic
failure, unsupported privileged entrypoints, native-value rejection, and code size/opcodes.
Fuzz tests use 1,024 cases each by default. Three stateful invariants use a four-actor handler
with an independent balance/allowance ledger, 256 runs of 64 calls each, and
`fail_on_revert = true`. Expected invalid calls are asserted inside the handler.
Tests use no environment variables, file reads, live chain state, or execution-order assumptions.

The launch transfer test checks exact 10%/80%/10% distribution, claims, and token movements
to and from a pool address. It does not simulate Uniswap pricing, liquidity, or swaps. The
network's supplied protected integration harness must check the actual factory and PoolManager
flows in its separate admission step.

## Deployment handoff

These are the assignment's launch parameters, not external contracts used by the token:

| Launch parameter | Pinned value |
| --- | --- |
| Chain | Robinhood Chain, `4663` |
| Token contract | `AcontextToken` |
| Token constructor arguments | `[]` |
| Additional application contracts | None |
| Paired currency (IMD, 18 decimals) | `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127` |
| Pool fee | `12500` (1.25%) |
| Tick spacing | `60` |
| Specified `pool.initialPrice` | `79228162514264337593543950336` |
| `economics.poolBps` | `8000` |
| `economics.initialMarketCapWei` | `5000000000000000000000` (5,000 IMD) |
| `economics.remainderTo` | `0xd6302976e590b9b947da8774b7f1246164e0ce98` |

The separate manifest step supplies `kind: "custom_token"`, these parameters, the token's
metadata, and exact minor-unit supply. This implementation intentionally contains no
`launch.json`. The factory receives all one billion tokens, then sends 10% (100 million)
to the launch's MerkleDistributor, allocates 80% (800 million) to the pool, and forwards
the remaining 10% (100 million) to the specified remainder recipient. The constructor
does not split or reserve any supply. The network derives the actual opening pool price
from the market cap, supply, and deployed token ordering.

Only the network's authorized deployer performs `ProjectFactory.launchCustom`, after
review and attestation. It must use the compiled creation code with no appended constructor
arguments, verify chain `4663`, and verify that its factory is the immediate token deployer.
The constructor makes no external calls and requires no pre-existing contracts. The token
contains no chain-dependent, block-number, timestamp, price, or oracle logic.

Reviewable artifacts can be obtained without signing or broadcasting:

```sh
forge inspect src/AcontextToken.sol:AcontextToken abi
forge inspect src/AcontextToken.sol:AcontextToken bytecode
```

Deploying through any other helper would mint to that helper. Direct deployment outside the
network would not perform its distribution or pool setup. No deployment or transaction is
part of this implementation task.

## After launch

No owner setup, operator service, keeper, or configurable external address is needed. The
network deployer is responsible for distribution, pool creation, protected integration
checks, publishing the deployed address, and source verification. Holders manage transfers
and approvals themselves. A separate independent review remains part of the network's
release process; the local tests and [REVIEW.md](REVIEW.md) are implementation checks.
