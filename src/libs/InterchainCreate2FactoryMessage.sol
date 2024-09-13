// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ============ External Imports ============
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

/**
 * Format of message:
 * [   0:    32] sender
 * [  32:    64] ISM
 * [  64:    96] salt
 * [  96:  ????] bytecode
 * [  ????:????] initCode
 */
library InterchainCreate2FactoryMessage {
    using TypeCasts for bytes32;

    /**
     * @notice Returns formatted (packed) InterchainCreate2FactoryMessage
     * @dev This function should only be used in memory message construction.
     * @param _sender The sender of the message
     * @param _salt The address of the remote ISM
     * @param _ism The address of the remote ISM
     * @param _bytecode The bytecode
     * @param _initCode The initCode
     * @return Formatted message body
     */
    function encode(
        address _sender,
        bytes32 _ism,
        bytes32 _salt,
        bytes memory _bytecode,
        bytes memory _initCode
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(TypeCasts.addressToBytes32(_sender), _ism, _salt, _bytecode, _initCode);
    }

    /**
     * @notice Parses and returns the calls from the provided message
     * @param _message The interchain account message
     * @return The array of calls
     */
    function decode(bytes calldata _message)
        internal
        pure
        returns (bytes32, bytes32, bytes32, bytes memory, bytes memory)
    {
        return abi.decode(_message, (bytes32, bytes32, bytes32, bytes, bytes));
    }

    /**
     * @notice Parses and returns the ISM address from the provided message
     * @param _message The interchain account message
     * @return The ISM encoded in the message
     */
    function ism(bytes calldata _message) internal pure returns (address) {
        return address(bytes20(_message[44:64]));
    }
}
