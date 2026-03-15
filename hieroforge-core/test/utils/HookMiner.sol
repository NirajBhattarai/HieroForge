// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @title HookMiner
/// @notice Off-chain utility to find a CREATE2 salt that produces a hook address
///         with the desired permission flags in its lower 6 bits.
/// @dev Used only in Foundry scripts/tests — not deployed on-chain.
library HookMiner {
    uint160 internal constant ALL_HOOK_MASK = (1 << 6) - 1; // 0x3F

    /// @notice Find a salt such that CREATE2 from `deployer` produces an address
    ///         whose lower 6 bits match `flags`.
    /// @param deployer The CREATE2 deployer (HookDeployer) address
    /// @param flags The desired permission bits (e.g. 0x22 for AFTER_INITIALIZE | AFTER_SWAP)
    /// @param creationCode type(Hook).creationCode
    /// @param constructorArgs abi.encode(arg1, arg2, ...)
    /// @return hookAddress The computed address with matching flags
    /// @return salt The salt that produces the address
    function find(address deployer, uint160 flags, bytes memory creationCode, bytes memory constructorArgs)
        internal
        pure
        returns (address hookAddress, bytes32 salt)
    {
        bytes memory initCode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 initCodeHash = keccak256(initCode);

        for (uint256 i = 0; i < 100_000; i++) {
            salt = bytes32(i);
            hookAddress = computeAddress(deployer, salt, initCodeHash);
            if (uint160(hookAddress) & ALL_HOOK_MASK == flags) {
                return (hookAddress, salt);
            }
        }
        revert("HookMiner: could not find salt within 100k iterations");
    }

    /// @notice Compute the CREATE2 address for a given deployer, salt, and init code hash.
    function computeAddress(address deployer, bytes32 salt, bytes32 initCodeHash) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))));
    }
}
