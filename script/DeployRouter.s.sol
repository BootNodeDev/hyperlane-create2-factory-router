// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/src/Script.sol";
import { console2 } from "forge-std/src/console2.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import { ICREATE3Factory } from "./utils/ICREATE3Factory.sol";
import { ICreateX } from "./utils/ICreateX.sol";

import { InterchainCreate2FactoryRouter } from "../src/InterchainCreate2FactoryRouter.sol";
import { InterchainCreate2FactoryIsm } from "../src/InterchainCreate2FactoryIsm.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract DeployRouter is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");

        string memory ISM_SALT = vm.envString("ISM_SALT");
        string memory ROUTER_SALT = vm.envString("ROUTER_SALT");
        address mailbox = vm.envAddress("MAILBOX");
        address admin = vm.envAddress("PROXY_ADMIN");
        address owner = vm.envAddress("ROUTER_OWNER");
        address routerImpl = vm.envOr("ROUTER_IMPLEMENTATION", address(0));
        address ism = vm.envOr("ISM", address(0));
        address customHook = vm.envOr("CUSTOM_HOOK", address(0));
        address createX = vm.envAddress("CREATEX_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        if (ism == address(0)) {
            bytes32 ismSalt = keccak256(abi.encodePacked(ISM_SALT, vm.addr(deployerPrivateKey)));
            bytes memory ismCreation = type(InterchainCreate2FactoryIsm).creationCode;
            bytes memory ismBytecode = abi.encodePacked(ismCreation, abi.encode(mailbox));

            ism = ICreateX(createX).deployCreate3(ismSalt, ismBytecode);
        }

        if (routerImpl == address(0)) {
            bytes32 rImplSalt = keccak256(abi.encodePacked(ROUTER_SALT, "IMPLEMENTATION", vm.addr(deployerPrivateKey)));
            bytes memory rImplCreation = type(InterchainCreate2FactoryRouter).creationCode;
            bytes memory rImplBytecode = abi.encodePacked(rImplCreation, abi.encode(mailbox));

            routerImpl = ICreateX(createX).deployCreate3(rImplSalt, rImplBytecode);
        }

        bytes32 routerSalt = keccak256(abi.encodePacked(ROUTER_SALT, vm.addr(deployerPrivateKey)));
        bytes memory routerCreation = type(TransparentUpgradeableProxy).creationCode;
        bytes memory routerBytecode = abi.encodePacked(
            routerCreation,
            abi.encode(
                address(routerImpl),
                admin,
                abi.encodeWithSelector(InterchainCreate2FactoryRouter.initialize.selector, customHook, ism, owner)
            )
        );

        TransparentUpgradeableProxy proxy =
            TransparentUpgradeableProxy(payable(ICreateX(createX).deployCreate3(routerSalt, routerBytecode)));

        vm.stopBroadcast();

        // solhint-disable-next-line no-console
        console2.log("Proxy:", address(proxy));
        console2.log("Implementation:", routerImpl);
        console2.log("ISM:", ism);
    }
}
