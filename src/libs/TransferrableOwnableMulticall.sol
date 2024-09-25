// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { CallLib } from "@hyperlane-xyz/middleware/libs/Call.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/*
 * @title OwnableMulticall
 * @dev Permits immutable owner address to execute calls with value to other contracts.
 */
contract TransferrableOwnableMulticall is Ownable, Initializable {
    constructor(address _owner) {
        _transferOwnership(_owner);
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        _transferOwnership(_owner);
    }

    function multicall(CallLib.Call[] calldata calls) external onlyOwner returns (bytes[] memory returnData) {
        uint256 i = 0;
        uint256 len = calls.length;
        returnData = new bytes[](len);

        while (i < len) {
            returnData[i] = CallLib.call(calls[i]);
            unchecked {
                ++i;
            }
        }
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable { }
}
