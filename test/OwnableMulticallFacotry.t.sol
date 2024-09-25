// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { Test } from "forge-std/src/Test.sol";
import { CallLib, OwnableMulticallFactory } from "../src/OwnableMulticallFactory.sol";
import { TransferrableOwnableMulticall } from "../src/libs/TransferrableOwnableMulticall.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

contract Callable {
    mapping(address => bytes32) public data;

    function set(bytes32 _data) external returns (bytes32) {
        data[msg.sender] = _data;
        return _data;
    }
}

contract OwnableMulticallFactoryTest is Test {
    OwnableMulticallFactory internal factory;
    Callable internal target;

    address kakaroto = makeAddr("kakaroto");

    event MulticallCreated(address indexed owner, address indexed multicall);

    function setUp() public virtual {
        factory = new OwnableMulticallFactory();
        target = new Callable();
    }

    function getCalls(bytes32 data) private view returns (CallLib.Call[] memory) {
        vm.assume(data != bytes32(0));

        CallLib.Call memory call =
            CallLib.Call(TypeCasts.addressToBytes32(address(target)), 0, abi.encodeCall(target.set, (data)));
        CallLib.Call[] memory calls = new CallLib.Call[](1);
        calls[0] = call;
        return calls;
    }

    function asserteCallReceived(bytes32 data, address multicall) private view {
        assertEq(target.data(address(this)), bytes32(0));
        assertEq(target.data(multicall), data);
    }

    function testFuzz_deployAndCall(bytes32 data) public {
        // arrange
        CallLib.Call[] memory calls = getCalls(data);
        address expectedMulticall = factory.getMulticallAddress(kakaroto);

        // act
        vm.prank(kakaroto);
        vm.expectEmit(true, true, false, true, address(factory));
        emit MulticallCreated(kakaroto, expectedMulticall);
        (address payable multicall, bytes[] memory returnData) = factory.deployAndCall(calls);

        // assert
        assertEq(multicall, expectedMulticall);
        asserteCallReceived(data, multicall);
        assertEq(TransferrableOwnableMulticall(multicall).owner(), kakaroto);
        assertEq(returnData.length, 1);
        assertEq(abi.decode(returnData[0], (bytes32)), data);
    }
}
