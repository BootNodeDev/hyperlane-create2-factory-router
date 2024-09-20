// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/src/Script.sol";
import { console2 } from "forge-std/src/console2.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ICreateX } from "./utils/ICreateX.sol";
import { ReceiverHypERC20 } from "./utils/ReceiverHypERC20.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract DeployHypERC20Imple is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        address mailbox = vm.envAddress("MAILBOX");
        address createX = vm.envAddress("CREATEX_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        bytes32 routerSalt = keccak256(abi.encodePacked("HypERC20-Impl-0.0.2", vm.addr(deployerPrivateKey)));
        bytes memory rImplCreation = type(ReceiverHypERC20).creationCode;
        bytes memory rImplBytecode = abi.encodePacked(rImplCreation, abi.encode(18, mailbox));

        address routerImpl = ICreateX(createX).deployCreate3(routerSalt, rImplBytecode);

        // address routerImpl = address(new ReceiverHypERC20{salt: routerSalt}(18, mailbox));

        vm.stopBroadcast();

        // solhint-disable-next-line no-console
        console2.log("Implementation:", routerImpl);
    }
}
