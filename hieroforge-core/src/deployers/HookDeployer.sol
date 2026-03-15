// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @title HookDeployer
/// @notice Factory contract that deploys hook contracts via CREATE2 to achieve
///         deterministic addresses with specific lower-bit patterns (required for hook permissions).
contract HookDeployer {
    event Deployed(address indexed deployed, bytes32 salt);

    error DeploymentFailed();

    /// @notice Deploy a contract using CREATE2 with the given salt and creation code.
    /// @param salt The salt for CREATE2 address derivation
    /// @param creationCode The full creation bytecode (type(X).creationCode ++ abi.encode(args))
    /// @return deployed The address of the deployed contract
    function deploy(bytes32 salt, bytes memory creationCode) external returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(creationCode, 0x20), mload(creationCode), salt)
        }
        if (deployed == address(0)) revert DeploymentFailed();
        emit Deployed(deployed, salt);
    }
}
