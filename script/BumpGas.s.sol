// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/src/Script.sol";
import { console2 } from "forge-std/src/console2.sol";

import { ReceiverHypERC20 } from "./utils/ReceiverHypERC20.sol";
import {TypeCasts} from "@hyperlane-xyz/libs/TypeCasts.sol";
import {StandardHookMetadata} from "@hyperlane-xyz/hooks/libs/StandardHookMetadata.sol";
import {InterchainGasPaymaster} from "@hyperlane-xyz/hooks/igp/InterchainGasPaymaster.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract BumpGas is Script {
    function run() public {
        uint256 ownerPrivateKey = vm.envUint("ROUTER_OWNER_PK");
        address owner = vm.envAddress("ROUTER_OWNER");

        InterchainGasPaymaster igp = InterchainGasPaymaster(address(0x6f2756380FD49228ae25Aa7F2817993cB74Ecc56));

        vm.startBroadcast(ownerPrivateKey);

        igp.payForGas{value: 100000000000000000}(
            bytes32(0x57e309e68fcc141dccd012ab7aa6ca42809229b321ff0b095b2135b0437096c9),
            uint32(11155420),
            uint256(10000000),
            owner
        );

        vm.stopBroadcast();
    }
}
