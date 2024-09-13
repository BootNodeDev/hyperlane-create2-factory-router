// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

contract TestDeployContract {
    uint256 public counter;

    event Incremented(uint256 value);

    function increment() public {
        counter++;
        emit Incremented(counter);
    }
}
