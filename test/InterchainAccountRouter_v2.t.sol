// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/src/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {StandardHookMetadata} from "@hyperlane-xyz/hooks/libs/StandardHookMetadata.sol";
import {MockMailbox} from "@hyperlane-xyz/mock/MockMailbox.sol";
import {TypeCasts} from "@hyperlane-xyz/libs/TypeCasts.sol";
import {IInterchainSecurityModule} from "@hyperlane-xyz/interfaces/IInterchainSecurityModule.sol";
import {TestInterchainGasPaymaster} from "@hyperlane-xyz/test/TestInterchainGasPaymaster.sol";
import {IPostDispatchHook} from "@hyperlane-xyz/interfaces/hooks/IPostDispatchHook.sol";
import {InterchainAccountIsm} from "@hyperlane-xyz/isms/routing/InterchainAccountIsm.sol";

import {MockHyperlaneEnvironment} from "./utils/MockHyperlaneEnvironment.sol";
import {CallLib, OwnableMulticall, InterchainAccountRouter_v2} from "../src/InterchainAccountRouter_v2.sol";

contract Callable {
    mapping(address => bytes32) public data;

    function set(bytes32 _data) external {
        data[msg.sender] = _data;
    }
}

contract FailingIsm is IInterchainSecurityModule {
    string public failureMessage;
    uint8 public moduleType;

    constructor(string memory _failureMessage) {
        failureMessage = _failureMessage;
    }

    function verify(
        bytes calldata,
        bytes calldata
    ) external view returns (bool) {
        revert(failureMessage);
    }
}

contract InterchainAccountRouterTestBase is Test {
    using TypeCasts for address;

    event InterchainAccountCreated(
        uint32 indexed origin,
        bytes32 indexed owner,
        address ism,
        address account
    );

    MockHyperlaneEnvironment internal environment;

    uint32 internal origin = 1;
    uint32 internal destination = 2;
    uint32 internal destination2 = 3;

    TestInterchainGasPaymaster internal igp;
    InterchainAccountIsm internal icaIsm;
    InterchainAccountRouter_v2 internal originIcaRouter;
    InterchainAccountRouter_v2 internal destinationIcaRouter;
    InterchainAccountRouter_v2 internal destination2IcaRouter;
    bytes32 internal ismOverride;
    bytes32 internal routerOverride;
    bytes32 internal ism2Override;
    bytes32 internal router2Override;
    uint256 gasPaymentQuote;
    uint256 internal constant GAS_LIMIT_OVERRIDE = 60000;

    OwnableMulticall internal ica;
    OwnableMulticall internal ica2;

    Callable internal target;

    function deployProxiedIcaRouter(
        MockMailbox _mailbox,
        IPostDispatchHook _customHook,
        IInterchainSecurityModule _ism,
        address _owner
    ) public returns (InterchainAccountRouter_v2) {
        InterchainAccountRouter_v2 implementation = new InterchainAccountRouter_v2(
            address(_mailbox)
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(1), // no proxy owner necessary for testing
            abi.encodeWithSelector(
                InterchainAccountRouter_v2.initialize.selector,
                address(_customHook),
                address(_ism),
                _owner
            )
        );

        return InterchainAccountRouter_v2(address(proxy));
    }

    function setUp() public virtual {
        uint32[] memory destinations = new uint32[](2);
        destinations[0] = destination;
        destinations[1] = destination2;

        environment = new MockHyperlaneEnvironment(origin, destinations);

        igp = new TestInterchainGasPaymaster();
        gasPaymentQuote = igp.quoteGasPayment(
            destination,
            igp.getDefaultGasUsage()
        );

        icaIsm = new InterchainAccountIsm(
            address(environment.mailboxes(destination))
        );

        address owner = address(this);
        originIcaRouter = deployProxiedIcaRouter(
            environment.mailboxes(origin),
            environment.igps(destination),
            icaIsm,
            owner
        );
        destinationIcaRouter = deployProxiedIcaRouter(
            environment.mailboxes(destination),
            environment.igps(destination),
            icaIsm,
            owner
        );
        destination2IcaRouter = deployProxiedIcaRouter(
            environment.mailboxes(destination2),
            environment.igps(destination2),
            icaIsm,
            owner
        );

        environment.mailboxes(origin).setDefaultHook(address(igp));

        routerOverride = TypeCasts.addressToBytes32(
            address(destinationIcaRouter)
        );
        ismOverride = TypeCasts.addressToBytes32(
            address(environment.isms(destination))
        );

        router2Override = TypeCasts.addressToBytes32(
            address(destination2IcaRouter)
        );
        ism2Override = TypeCasts.addressToBytes32(
            address(environment.isms(destination2))
        );

        ica = destinationIcaRouter.getLocalInterchainAccount(
            origin,
            address(this),
            address(originIcaRouter),
            address(environment.isms(destination))
        );

        ica2 = destination2IcaRouter.getLocalInterchainAccount(
            origin,
            address(this),
            address(originIcaRouter),
            address(environment.isms(destination2))
        );

        target = new Callable();
    }

    receive() external payable {}
}

contract InterchainAccountRouterTest is InterchainAccountRouterTestBase {
    using TypeCasts for address;

    function testFuzz_constructor(address _localOwner) public {
        OwnableMulticall _account = destinationIcaRouter
            .getDeployedInterchainAccount(
                origin,
                _localOwner,
                address(originIcaRouter),
                address(environment.isms(destination))
            );
        assertEq(_account.owner(), address(destinationIcaRouter));
    }

    function testFuzz_getRemoteInterchainAccount(
        address _localOwner,
        address _ism
    ) public {
        address _account = originIcaRouter.getRemoteInterchainAccount(
            address(_localOwner),
            address(destinationIcaRouter),
            _ism
        );
        originIcaRouter.enrollRemoteRouterAndIsm(
            destination,
            routerOverride,
            TypeCasts.addressToBytes32(_ism)
        );
        assertEq(
            originIcaRouter.getRemoteInterchainAccount(
                destination,
                address(_localOwner)
            ),
            _account
        );
    }

    function testFuzz_enrollRemoteRouters(
        uint8 count,
        uint32 domain,
        bytes32 router
    ) public {
        vm.assume(count > 0 && count < uint256(router) && count < domain);

        // arrange
        // count - # of domains and routers
        uint32[] memory domains = new uint32[](count);
        bytes32[] memory routers = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            domains[i] = domain - uint32(i);
            routers[i] = bytes32(uint256(router) - i);
        }

        // act
        originIcaRouter.enrollRemoteRouters(domains, routers);

        // assert
        uint32[] memory actualDomains = originIcaRouter.domains();
        assertEq(actualDomains.length, domains.length);
        assertEq(abi.encode(originIcaRouter.domains()), abi.encode(domains));

        for (uint256 i = 0; i < count; i++) {
            bytes32 actualRouter = originIcaRouter.routers(domains[i]);
            bytes32 actualIsm = originIcaRouter.isms(domains[i]);

            assertEq(actualRouter, routers[i]);
            assertEq(actualIsm, bytes32(0));
            assertEq(actualDomains[i], domains[i]);
        }
    }

    function testFuzz_enrollRemoteRouterAndIsm(
        bytes32 router,
        bytes32 ism
    ) public {
        vm.assume(router != bytes32(0));

        // arrange pre-condition
        bytes32 actualRouter = originIcaRouter.routers(destination);
        bytes32 actualIsm = originIcaRouter.isms(destination);
        assertEq(actualRouter, bytes32(0));
        assertEq(actualIsm, bytes32(0));

        // act
        originIcaRouter.enrollRemoteRouterAndIsm(destination, router, ism);

        // assert
        actualRouter = originIcaRouter.routers(destination);
        actualIsm = originIcaRouter.isms(destination);
        assertEq(actualRouter, router);
        assertEq(actualIsm, ism);
    }

    function testFuzz_enrollRemoteRouterAndIsms(
        uint32[] calldata destinations,
        bytes32[] calldata routers,
        bytes32[] calldata isms
    ) public {
        // check reverts
        if (
            destinations.length != routers.length ||
            destinations.length != isms.length
        ) {
            vm.expectRevert(bytes("length mismatch"));
            originIcaRouter.enrollRemoteRouterAndIsms(
                destinations,
                routers,
                isms
            );
            return;
        }

        // act
        originIcaRouter.enrollRemoteRouterAndIsms(destinations, routers, isms);

        // assert
        for (uint256 i = 0; i < destinations.length; i++) {
            bytes32 actualRouter = originIcaRouter.routers(destinations[i]);
            bytes32 actualIsm = originIcaRouter.isms(destinations[i]);
            assertEq(actualRouter, routers[i]);
            assertEq(actualIsm, isms[i]);
        }
    }

    function testFuzz_enrollRemoteRouterAndIsmImmutable(
        bytes32 routerA,
        bytes32 ismA,
        bytes32 routerB,
        bytes32 ismB
    ) public {
        vm.assume(routerA != bytes32(0) && routerB != bytes32(0));

        // act
        originIcaRouter.enrollRemoteRouterAndIsm(destination, routerA, ismA);

        // assert
        vm.expectRevert(
            bytes("router and ISM defaults are immutable once set")
        );
        originIcaRouter.enrollRemoteRouterAndIsm(destination, routerB, ismB);
    }

    function testFuzz_enrollRemoteRouterAndIsmNonOwner(
        address newOwner,
        bytes32 router,
        bytes32 ism
    ) public {
        vm.assume(
            newOwner != address(0) && newOwner != originIcaRouter.owner()
        );

        // act
        originIcaRouter.transferOwnership(newOwner);

        // assert
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        originIcaRouter.enrollRemoteRouterAndIsm(destination, router, ism);
    }

    function getCalls(
        bytes32 data
    ) private view returns (CallLib.Call[] memory) {
        vm.assume(data != bytes32(0));

        CallLib.Call memory call = CallLib.Call(
            TypeCasts.addressToBytes32(address(target)),
            0,
            abi.encodeCall(target.set, (data))
        );
        CallLib.Call[] memory calls = new CallLib.Call[](1);
        calls[0] = call;
        return calls;
    }

    function assertRemoteCallReceived(bytes32 data) private {
        assertEq(target.data(address(this)), bytes32(0));
        vm.expectEmit(true, true, false, true, address(destinationIcaRouter));
        emit InterchainAccountCreated(
            origin,
            address(this).addressToBytes32(),
            TypeCasts.bytes32ToAddress(ismOverride),
            address(ica)
        );
        environment.processNextPendingMessage(destination);
        assertEq(target.data(address(ica)), data);
    }

    function assertRemotesCallReceived(bytes32 data) private {
        assertEq(target.data(address(this)), bytes32(0));
        vm.expectEmit(true, true, false, true, address(destinationIcaRouter));
        emit InterchainAccountCreated(
            origin,
            address(this).addressToBytes32(),
            TypeCasts.bytes32ToAddress(ismOverride),
            address(ica)
        );
        environment.processNextPendingMessage(destination);
        assertEq(target.data(address(ica)), data);

        vm.expectEmit(true, true, false, true, address(destination2IcaRouter));
        emit InterchainAccountCreated(
            origin,
            address(this).addressToBytes32(),
            TypeCasts.bytes32ToAddress(ism2Override),
            address(ica2)
        );
        environment.processNextPendingMessage(destination2);
        assertEq(target.data(address(ica2)), data);
    }

    function assertIgpPayment(
        uint256 balanceBefore,
        uint256 balanceAfter,
        uint256 gasLimit
    ) private {
        uint256 expectedGasPayment = gasLimit * igp.gasPrice();
        assertEq(balanceBefore - balanceAfter, expectedGasPayment);
        assertEq(address(igp).balance, expectedGasPayment);
    }

    function testFuzz_getDeployedInterchainAccount_checkAccountOwners(
        address owner
    ) public {
        // act
        ica = destinationIcaRouter.getDeployedInterchainAccount(
            origin,
            owner,
            address(originIcaRouter),
            address(environment.isms(destination))
        );

        (uint32 domain, bytes32 ownerBytes) = destinationIcaRouter
            .accountOwners(address(ica));
        // assert
        assertEq(domain, origin);
        assertEq(ownerBytes, owner.addressToBytes32());
    }

    function test_quoteGasPayment() public {
        // arrange
        originIcaRouter.enrollRemoteRouterAndIsm(
            destination,
            routerOverride,
            ismOverride
        );

        // assert
        assertEq(originIcaRouter.quoteGasPayment(destination), gasPaymentQuote);
    }

    function test_quoteGasPayment_gasLimitOverride() public {
        // arrange
        originIcaRouter.enrollRemoteRouterAndIsm(
            destination,
            routerOverride,
            ismOverride
        );

        // assert
        assertEq(
            originIcaRouter.quoteGasPayment(
                destination,
                "",
                GAS_LIMIT_OVERRIDE
            ),
            igp.quoteGasPayment(destination, GAS_LIMIT_OVERRIDE)
        );
    }

    function testFuzz_singleCallRemoteWithDefault(bytes32 data) public {
        // arrange
        originIcaRouter.enrollRemoteRouterAndIsm(
            destination,
            routerOverride,
            ismOverride
        );
        uint256 balanceBefore = address(this).balance;

        // act
        CallLib.Call[] memory calls = getCalls(data);
        originIcaRouter.callRemote{value: gasPaymentQuote}(
            destination,
            TypeCasts.bytes32ToAddress(calls[0].to),
            calls[0].value,
            calls[0].data
        );

        // assert
        uint256 balanceAfter = address(this).balance;
        assertRemoteCallReceived(data);
        assertIgpPayment(balanceBefore, balanceAfter, igp.getDefaultGasUsage());
    }

    function testFuzz_callRemoteWithDefault(bytes32 data) public {
        // arrange
        originIcaRouter.enrollRemoteRouterAndIsm(
            destination,
            routerOverride,
            ismOverride
        );
        uint256 balanceBefore = address(this).balance;

        // act
        originIcaRouter.callRemote{value: gasPaymentQuote}(
            destination,
            getCalls(data)
        );

        // assert
        uint256 balanceAfter = address(this).balance;
        assertRemoteCallReceived(data);
        assertIgpPayment(balanceBefore, balanceAfter, igp.getDefaultGasUsage());
    }

    function testFuzz_callRemotesWithDefault(bytes32 data) public {
        // arrange
        originIcaRouter.enrollRemoteRouterAndIsm(
            destination,
            routerOverride,
            ismOverride
        );
        originIcaRouter.enrollRemoteRouterAndIsm(
            destination2,
            router2Override,
            ism2Override
        );
        uint256 balanceBefore = address(this).balance;

        InterchainAccountRouter_v2.RemoteCall[] memory remoteCalls = new InterchainAccountRouter_v2.RemoteCall[](2);
        remoteCalls[0] = InterchainAccountRouter_v2.RemoteCall(
            destination,
            getCalls(data),
            bytes(""),
            gasPaymentQuote
        );

        remoteCalls[1] = InterchainAccountRouter_v2.RemoteCall(
            destination2,
            getCalls(data),
            bytes(""),
            gasPaymentQuote
        );

        // act
        originIcaRouter.callRemotes{value: gasPaymentQuote*2}(remoteCalls);

        // assert
        uint256 balanceAfter = address(this).balance;
        assertRemotesCallReceived(data);
        assertIgpPayment(balanceBefore, balanceAfter, igp.getDefaultGasUsage()*2);
    }

    function testFuzz_overrideAndCallRemote(bytes32 data) public {
        // arrange
        originIcaRouter.enrollRemoteRouterAndIsm(
            destination,
            routerOverride,
            ismOverride
        );
        uint256 balanceBefore = address(this).balance;

        // act
        originIcaRouter.callRemote{value: gasPaymentQuote}(
            destination,
            getCalls(data)
        );

        // assert
        uint256 balanceAfter = address(this).balance;
        assertRemoteCallReceived(data);
        assertIgpPayment(balanceBefore, balanceAfter, igp.getDefaultGasUsage());
    }

    function testFuzz_callRemoteWithoutDefaults_revert_noRouter(
        bytes32 data
    ) public {
        // assert error
        CallLib.Call[] memory calls = getCalls(data);
        vm.expectRevert(bytes("no router specified for destination"));
        originIcaRouter.callRemote(destination, calls);
    }

    function testFuzz_customMetadata_forIgp(
        uint64 gasLimit,
        uint64 overpayment,
        bytes32 data
    ) public {
        // arrange
        bytes memory metadata = StandardHookMetadata.formatMetadata(
            0,
            gasLimit,
            address(this),
            ""
        );
        originIcaRouter.enrollRemoteRouterAndIsm(
            destination,
            routerOverride,
            ismOverride
        );
        uint256 balanceBefore = address(this).balance;

        // act
        originIcaRouter.callRemote{
            value: gasLimit * igp.gasPrice() + overpayment
        }(destination, getCalls(data), metadata);

        // assert
        uint256 balanceAfter = address(this).balance;
        assertRemoteCallReceived(data);
        assertIgpPayment(balanceBefore, balanceAfter, gasLimit);
    }

    function testFuzz_customMetadata_reverts_underpayment(
        uint64 gasLimit,
        uint64 payment,
        bytes32 data
    ) public {
        CallLib.Call[] memory calls = getCalls(data);
        vm.assume(payment < gasLimit * igp.gasPrice());
        // arrange
        bytes memory metadata = StandardHookMetadata.formatMetadata(
            0,
            gasLimit,
            address(this),
            ""
        );
        originIcaRouter.enrollRemoteRouterAndIsm(
            destination,
            routerOverride,
            ismOverride
        );

        // act
        vm.expectRevert("IGP: insufficient interchain gas payment");
        originIcaRouter.callRemote{value: payment}(
            destination,
            calls,
            metadata
        );
    }

    function testFuzz_callRemoteWithOverrides_default(bytes32 data) public {
        // arrange
        uint256 balanceBefore = address(this).balance;

        // act
        originIcaRouter.callRemoteWithOverrides{value: gasPaymentQuote}(
            destination,
            routerOverride,
            ismOverride,
            getCalls(data)
        );

        // assert
        uint256 balanceAfter = address(this).balance;
        assertRemoteCallReceived(data);
        assertIgpPayment(balanceBefore, balanceAfter, igp.getDefaultGasUsage());
    }

    function testFuzz_callRemoteWithOverrides_metadata(
        uint64 gasLimit,
        bytes32 data
    ) public {
        // arrange
        bytes memory metadata = StandardHookMetadata.formatMetadata(
            0,
            gasLimit,
            address(this),
            ""
        );
        uint256 balanceBefore = address(this).balance;

        // act
        originIcaRouter.callRemoteWithOverrides{
            value: gasLimit * igp.gasPrice()
        }(destination, routerOverride, ismOverride, getCalls(data), metadata);

        // assert
        uint256 balanceAfter = address(this).balance;
        assertRemoteCallReceived(data);
        assertIgpPayment(balanceBefore, balanceAfter, gasLimit);
    }

    function testFuzz_callRemoteWithFailingIsmOverride(bytes32 data) public {
        // arrange
        string memory failureMessage = "failing ism";
        bytes32 failingIsm = TypeCasts.addressToBytes32(
            address(new FailingIsm(failureMessage))
        );

        // act
        originIcaRouter.callRemoteWithOverrides{value: gasPaymentQuote}(
            destination,
            routerOverride,
            failingIsm,
            getCalls(data),
            ""
        );

        // assert
        vm.expectRevert(bytes(failureMessage));
        environment.processNextPendingMessage(destination);
    }

    function testFuzz_callRemoteWithFailingDefaultIsm(bytes32 data) public {
        // arrange
        string memory failureMessage = "failing ism";
        FailingIsm failingIsm = new FailingIsm(failureMessage);

        // act
        environment.mailboxes(destination).setDefaultIsm(address(failingIsm));
        originIcaRouter.callRemoteWithOverrides{value: gasPaymentQuote}(
            destination,
            routerOverride,
            bytes32(0),
            getCalls(data),
            ""
        );

        // assert
        vm.expectRevert(bytes(failureMessage));
        environment.processNextPendingMessage(destination);
    }

    function testFuzz_getLocalInterchainAccount(bytes32 data) public {
        // check
        OwnableMulticall destinationIca = destinationIcaRouter
            .getLocalInterchainAccount(
                origin,
                address(this),
                address(originIcaRouter),
                address(environment.isms(destination))
            );
        assertEq(
            address(destinationIca),
            address(
                destinationIcaRouter.getLocalInterchainAccount(
                    origin,
                    TypeCasts.addressToBytes32(address(this)),
                    TypeCasts.addressToBytes32(address(originIcaRouter)),
                    address(environment.isms(destination))
                )
            )
        );
        assertEq(address(destinationIca).code.length, 0);

        // act
        originIcaRouter.callRemoteWithOverrides{value: gasPaymentQuote}(
            destination,
            routerOverride,
            ismOverride,
            getCalls(data),
            ""
        );

        // recheck
        assertRemoteCallReceived(data);
        assert(address(destinationIca).code.length != 0);
    }

    function testFuzz_receiveValue(uint256 value) public {
        vm.assume(value > 1 && value <= address(this).balance);
        // receive value before deployed
        assert(address(ica).code.length == 0);
        bool success;
        (success, ) = address(ica).call{value: value / 2}("");
        require(success, "transfer before deploy failed");

        // receive value after deployed
        destinationIcaRouter.getDeployedInterchainAccount(
            origin,
            address(this),
            address(originIcaRouter),
            address(environment.isms(destination))
        );
        assert(address(ica).code.length > 0);

        (success, ) = address(ica).call{value: value / 2}("");
        require(success, "transfer after deploy failed");
    }

    function receiveValue(uint256 value) external payable {
        assertEq(value, msg.value);
    }

    function testFuzz_sendValue(uint256 value) public {
        vm.assume(
            value > 0 && value <= address(this).balance - gasPaymentQuote
        );
        payable(address(ica)).transfer(value);

        bytes memory data = abi.encodeCall(this.receiveValue, (value));
        CallLib.Call memory call = CallLib.build(address(this), value, data);
        CallLib.Call[] memory calls = new CallLib.Call[](1);
        calls[0] = call;

        originIcaRouter.callRemoteWithOverrides{value: gasPaymentQuote}(
            destination,
            routerOverride,
            ismOverride,
            calls,
            ""
        );
        vm.expectCall(address(this), value, data);
        environment.processNextPendingMessage(destination);
    }
}
