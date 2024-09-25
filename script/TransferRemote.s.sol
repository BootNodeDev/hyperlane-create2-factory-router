// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/src/Script.sol";
import { console2 } from "forge-std/src/console2.sol";

import { ReceiverHypERC20 } from "./utils/ReceiverHypERC20.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { StandardHookMetadata } from "@hyperlane-xyz/hooks/libs/StandardHookMetadata.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract TransferRemote is Script {
    function run() public {
        uint256 ownerPrivateKey = vm.envUint("ROUTER_OWNER_PK");
        address owner = vm.envAddress("ROUTER_OWNER");

        ReceiverHypERC20 warpRouter = ReceiverHypERC20(address(0x2E41bc75472B261a7b482B9B1FDf694cE369D06f));

        vm.startBroadcast(ownerPrivateKey);

        uint256 _gasPaymentOp = warpRouter.quoteGasPayment(uint32(11_155_420));
        uint256 _gasPaymentArb = warpRouter.quoteGasPayment(uint32(421_614));

        bytes32 messageIdOp = warpRouter.transferRemote{ value: _gasPaymentOp }(
            uint32(11_155_420),
            TypeCasts.addressToBytes32(owner),
            1000,
            StandardHookMetadata.overrideGasLimit(308_139),
            address(0)
        );
        bytes32 messageIdArb = warpRouter.transferRemote{ value: _gasPaymentArb }(
            uint32(421_614),
            TypeCasts.addressToBytes32(owner),
            1000,
            StandardHookMetadata.overrideGasLimit(308_139),
            address(0)
        );

        vm.stopBroadcast();

        console2.log("_gasPaymentOp", _gasPaymentOp);
        console2.log("_gasPaymentArb", _gasPaymentArb);

        console2.logBytes32(messageIdOp);
        console2.logBytes32(messageIdArb);
    }
}
