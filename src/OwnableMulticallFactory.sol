// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {MinimalProxy} from "@hyperlane-xyz/libs/MinimalProxy.sol";
import {CallLib} from "@hyperlane-xyz/middleware/libs/Call.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {TransferrableOwnableMulticall} from "./libs/TransferrableOwnableMulticall.sol";


contract OwnableMulticallFactory {
    address public immutable implementation;
    bytes32 public immutable bytecodeHash;

    event MulticallCreated(
        address indexed owner,
        address indexed multicall
    );

    constructor() {
        implementation = address(new TransferrableOwnableMulticall(address(this)));
        // cannot be stored immutably because it is dynamically sized
        bytes memory _bytecode = MinimalProxy.bytecode(implementation);
        bytecodeHash = keccak256(_bytecode);
    }

    function deployAndCall(CallLib.Call[] calldata _calls) external payable returns (address payable _multicall, bytes[] memory returnData) {
        bool _deployed = false;
        bytes32 _salt = _getSalt(msg.sender);

        _multicall = _getMulticallAddress(_salt);

        if (!Address.isContract(_multicall)) {
            bytes memory _bytecode = MinimalProxy.bytecode(implementation);
            _multicall = payable(Create2.deploy(0, _salt, _bytecode));

            Address.sendValue(_multicall, msg.value);

            TransferrableOwnableMulticall(_multicall).initialize(address(this));
            _deployed = true;

            emit MulticallCreated(msg.sender, _multicall);
        }

        if (_calls.length > 0) {
            returnData = TransferrableOwnableMulticall(_multicall).multicall(_calls);
        }

        if (_deployed) {
            TransferrableOwnableMulticall(_multicall).transferOwnership(msg.sender);
        }
    }

    function getMulticallAddress(
        address _owner
    ) public view returns (address) {
        return
            _getMulticallAddress(_getSalt(_owner));
    }

    function _getSalt(address _owner) private view returns  (bytes32) {
        return keccak256(abi.encodePacked(address(this), _owner));
    }

    function _getMulticallAddress(
        bytes32 _salt
    ) private view returns (address payable) {
        return payable(Create2.computeAddress(_salt, bytecodeHash));
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
