// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {StandardHookMetadata} from "@hyperlane-xyz/hooks/libs/StandardHookMetadata.sol";
import {MockMailbox} from "@hyperlane-xyz/mock/MockMailbox.sol";
import {MockHyperlaneEnvironment} from "@hyperlane-xyz/mock/MockHyperlaneEnvironment.sol";
import {TypeCasts} from "@hyperlane-xyz/libs/TypeCasts.sol";
import {IInterchainSecurityModule} from "@hyperlane-xyz/interfaces/IInterchainSecurityModule.sol";
import {TestInterchainGasPaymaster} from "@hyperlane-xyz/test/TestInterchainGasPaymaster.sol";
import {IPostDispatchHook} from "@hyperlane-xyz/interfaces/hooks/IPostDispatchHook.sol";
import {TestIsm} from "@hyperlane-xyz/test/TestIsm.sol";

import {InterchainCreate2FactoryRouter} from "src/InterchainCreate2FactoryRouter.sol";
import {InterchainCreate2FactoryIsm} from "src/InterchainCreate2FactoryIsm.sol";
import { InterchainCreate2FactoryMessage } from "src/libs/InterchainCreate2FactoryMessage.sol";

contract SomeContract {
    uint256 public counter;

    event SomeEvent(uint256 counter);
    function someFunction() external {
        counter++;
        emit SomeEvent(counter);
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

contract InterchainCreate2FactoryRouterBase is Test {
    using TypeCasts for address;

    event Deployed(bytes32 indexed bytecodeHash, bytes32 indexed salt, address indexed deployedAddress);
    event SomeEvent(uint256 counter);

    MockHyperlaneEnvironment internal environment;

    uint32 internal origin = 1;
    uint32 internal destination = 2;

    TestInterchainGasPaymaster internal igp;
    InterchainCreate2FactoryIsm internal ism;
    InterchainCreate2FactoryRouter internal originRouter;
    InterchainCreate2FactoryRouter internal destinationRouter;

    TestIsm internal testIsm;
    bytes32 internal testIsmB32;
    bytes32 internal originRouterB32;
    bytes32 internal destinationRouterB32;

    uint256 gasPaymentQuote;
    uint256 internal constant GAS_LIMIT_OVERRIDE = 60000;

    address internal admin = makeAddr("admin");
    address internal owner = makeAddr("owner");
    // address internal sender = makeAddr("sender");

    function deployProxiedRouter(
        MockMailbox _mailbox,
        IPostDispatchHook _customHook,
        IInterchainSecurityModule _ism,
        address _owner
    ) public returns (InterchainCreate2FactoryRouter) {
        InterchainCreate2FactoryRouter implementation = new InterchainCreate2FactoryRouter(
            address(_mailbox)
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin,
            abi.encodeWithSelector(
                InterchainCreate2FactoryRouter.initialize.selector,
                address(_customHook),
                address(_ism),
                _owner
            )
        );

        return InterchainCreate2FactoryRouter(address(proxy));
    }

    function setUp() public virtual {
        environment = new MockHyperlaneEnvironment(origin, destination);

        igp = new TestInterchainGasPaymaster();
        gasPaymentQuote = igp.quoteGasPayment(
            destination,
            igp.getDefaultGasUsage()
        );

        ism = new InterchainCreate2FactoryIsm(
            address(environment.mailboxes(destination))
        );

        testIsm = new TestIsm();

        originRouter = deployProxiedRouter(
            environment.mailboxes(origin),
            environment.igps(destination),
            ism,
            owner
        );
        destinationRouter = deployProxiedRouter(
            environment.mailboxes(destination),
            environment.igps(destination),
            ism,
            owner
        );

        environment.mailboxes(origin).setDefaultHook(address(igp));

        originRouterB32 = TypeCasts.addressToBytes32(address(originRouter));
        destinationRouterB32 = TypeCasts.addressToBytes32(address(destinationRouter));
        testIsmB32 = TypeCasts.addressToBytes32(address(testIsm));
    }

    receive() external payable {}
}

contract InterchainCreate2FactoryRouterTest is InterchainCreate2FactoryRouterBase {
    using TypeCasts for address;

    modifier enrollRouters() {
        vm.startPrank(owner);
        originRouter.enrollRemoteRouter(
            destination,
            destinationRouterB32
        );

        destinationRouter.enrollRemoteRouter(
            origin,
            originRouterB32
        );

        vm.stopPrank();
        _;
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
        vm.prank(owner);
        originRouter.enrollRemoteRouters(domains, routers);

        // assert
        uint32[] memory actualDomains = originRouter.domains();
        assertEq(actualDomains.length, domains.length);
        assertEq(abi.encode(originRouter.domains()), abi.encode(domains));

        for (uint256 i = 0; i < count; i++) {
            bytes32 actualRouter = originRouter.routers(domains[i]);

            assertEq(actualRouter, routers[i]);
            assertEq(actualDomains[i], domains[i]);
        }
    }

    function test_quoteGasPayment() public enrollRouters {
        // arrange
        bytes memory messageBody = InterchainCreate2FactoryMessage.encode(
            address(1),
            TypeCasts.addressToBytes32(address(0)),
            "",
            new bytes(0),
            new bytes(0)
        );

        // assert
        assertEq(originRouter.quoteGasPayment(destination, messageBody, new bytes(0)), gasPaymentQuote);
    }

    function test_quoteGasPayment_gasLimitOverride() public enrollRouters {
        // arrange
        bytes memory messageBody = InterchainCreate2FactoryMessage.encode(
            address(1),
            TypeCasts.addressToBytes32(address(0)),
            "",
            new bytes(0),
            new bytes(0)
        );

        bytes memory hookMetadata = StandardHookMetadata.overrideGasLimit(GAS_LIMIT_OVERRIDE);

        // assert
        assertEq(
            originRouter.quoteGasPayment(destination, messageBody, hookMetadata),
            igp.quoteGasPayment(destination, GAS_LIMIT_OVERRIDE)
        );
    }

    function assertContractDeployed(address _sender, bytes32 _salt, bytes memory _bytecode, address _ism) private {
        address expectedAddress = destinationRouter.deployedAddress(_sender, _salt, _bytecode);

        assertFalse(Address.isContract(expectedAddress));

        vm.expectCall(address(_ism), abi.encodeWithSelector(TestIsm.verify.selector));

        vm.expectEmit(true, true, true, true, address(destinationRouter));
        emit Deployed(keccak256(_bytecode), keccak256(abi.encode(_sender, _salt)), expectedAddress);
        environment.processNextPendingMessage();

        assertTrue(Address.isContract(expectedAddress));

        uint256 counterBefore = SomeContract(expectedAddress).counter();

        vm.expectEmit(true, true, true, true, expectedAddress);
        emit SomeEvent(counterBefore+1);
        SomeContract(expectedAddress).someFunction();
    }

    function assertContractDeployedAndInit(address _sender, bytes32 _salt, bytes memory _bytecode, address _ism) private {
        address expectedAddress = destinationRouter.deployedAddress(_sender, _salt, _bytecode);

        assertFalse(Address.isContract(expectedAddress));

        vm.expectCall(address(_ism), abi.encodeWithSelector(TestIsm.verify.selector));

        vm.expectEmit(true, true, true, true, address(destinationRouter));
        emit Deployed(keccak256(_bytecode), keccak256(abi.encode(_sender, _salt)), expectedAddress);

        vm.expectEmit(true, true, true, true, expectedAddress);
        emit SomeEvent(1);

        environment.processNextPendingMessage();

        assertTrue(Address.isContract(expectedAddress));

        uint256 counterBefore = SomeContract(expectedAddress).counter();

        vm.expectEmit(true, true, true, true, expectedAddress);
        emit SomeEvent(counterBefore+1);
        SomeContract(expectedAddress).someFunction();
    }

    function assertIgpPayment(
        uint256 balanceBefore,
        uint256 balanceAfter,
        uint256 gasLimit
    ) private view {
        uint256 expectedGasPayment = gasLimit * igp.gasPrice();
        assertEq(balanceBefore - balanceAfter, expectedGasPayment);
        assertEq(address(igp).balance, expectedGasPayment);
    }

    function assumeSender(address _sender) internal view{
        vm.assume(_sender != address(0) && _sender != admin && !Address.isContract(_sender));
        assumeNotPrecompile(_sender);
    }

    function testFuzz_deployContract_no_router_enrolled(address sender, bytes32 salt) public {
        assumeSender(sender);

        // arrange
        vm.deal(sender, gasPaymentQuote);

        // act
        bytes memory bytecode = type(SomeContract).creationCode;
        vm.prank(sender);
        vm.expectRevert("No router enrolled for domain: 2");
        originRouter.deployContract{value: gasPaymentQuote}(
            destination,
            "",
            salt,
            bytecode
        );
    }

    function testFuzz_deployContract_defaultISM(address sender, bytes32 salt) public enrollRouters {
        assumeSender(sender);

        // arrange
        vm.deal(sender, gasPaymentQuote);

        uint256 balanceBefore = address(sender).balance;

        // act
        bytes memory bytecode = type(SomeContract).creationCode;
        vm.prank(sender);
        originRouter.deployContract{value: gasPaymentQuote}(
            destination,
            "",
            salt,
            bytecode
        );

        // assert
        uint256 balanceAfter = address(sender).balance;
        address _ism = address(environment.mailboxes(destination).defaultIsm());
        assertContractDeployed(sender, salt, type(SomeContract).creationCode, _ism);
        assertIgpPayment(balanceBefore, balanceAfter, igp.getDefaultGasUsage());
    }

    function testFuzz_deployContractAndInit_defaultISM(address sender, bytes32 salt) public enrollRouters {
        assumeSender(sender);

        // arrange
        vm.deal(sender, gasPaymentQuote);

        uint256 balanceBefore = address(sender).balance;

        // act
        bytes memory bytecode = type(SomeContract).creationCode;
        bytes memory initCode = abi.encodeWithSelector(SomeContract.someFunction.selector);

        vm.prank(sender);
        originRouter.deployContractAndInit{value: gasPaymentQuote}(
            destination,
            "",
            salt,
            bytecode,
            initCode
        );

        // assert
        uint256 balanceAfter = address(sender).balance;
        address _ism = address(environment.mailboxes(destination).defaultIsm());
        assertContractDeployedAndInit(sender, salt, type(SomeContract).creationCode, _ism);
        assertIgpPayment(balanceBefore, balanceAfter, igp.getDefaultGasUsage());
    }

    function testFuzz_deployContract_defaultISM_customMetadata_forIgp(address sender, bytes32 salt, uint64 gasLimit, uint64 overpayment) public enrollRouters {
        assumeSender(sender);

        // arrange
        uint256 payment = gasLimit * igp.gasPrice() + overpayment;
        vm.deal(sender, payment);

        bytes memory metadata = StandardHookMetadata.formatMetadata(
            0,
            gasLimit,
            sender,
            ""
        );

        uint256 balanceBefore = address(sender).balance;

        // act
        bytes memory bytecode = type(SomeContract).creationCode;
        vm.prank(sender);
        originRouter.deployContract{value: payment}(
            destination,
            "",
            salt,
            bytecode,
            metadata
        );

        // assert
        uint256 balanceAfter = address(sender).balance;
        address _ism = address(environment.mailboxes(destination).defaultIsm());
        assertContractDeployed(sender, salt, type(SomeContract).creationCode, _ism);
        assertIgpPayment(balanceBefore, balanceAfter, gasLimit);
    }

    function testFuzz_deployContractAndInit_defaultISM_customMetadata_forIgp(address sender, bytes32 salt, uint64 gasLimit, uint64 overpayment) public enrollRouters {
        assumeSender(sender);

        // arrange
        uint256 payment = gasLimit * igp.gasPrice() + overpayment;
        vm.deal(sender, payment);

        bytes memory metadata = StandardHookMetadata.formatMetadata(
            0,
            gasLimit,
            sender,
            ""
        );

        uint256 balanceBefore = address(sender).balance;

        // act
        bytes memory bytecode = type(SomeContract).creationCode;
        bytes memory initCode = abi.encodeWithSelector(SomeContract.someFunction.selector);

        vm.prank(sender);
        originRouter.deployContractAndInit{value: payment}(
            destination,
            "",
            salt,
            bytecode,
            initCode,
            metadata
        );

        // assert
        uint256 balanceAfter = address(sender).balance;
        address _ism = address(environment.mailboxes(destination).defaultIsm());
        assertContractDeployedAndInit(sender, salt, type(SomeContract).creationCode, _ism);
        assertIgpPayment(balanceBefore, balanceAfter, gasLimit);
    }

    function testFuzz_deployContract_defaultISM_reverts_underpayment(address sender, bytes32 salt, uint64 gasLimit, uint64 payment) public enrollRouters {
        assumeSender(sender);
        vm.assume(payment < gasLimit * igp.gasPrice());

        // arrange
        vm.deal(sender, payment);

        bytes memory metadata = StandardHookMetadata.formatMetadata(
            0,
            gasLimit,
            sender,
            ""
        );

        // act
        bytes memory bytecode = type(SomeContract).creationCode;
        vm.prank(sender);
        vm.expectRevert("IGP: insufficient interchain gas payment");
        originRouter.deployContract{value: payment}(
            destination,
            "",
            salt,
            bytecode,
            metadata
        );
    }

    function testFuzz_deployContractAndInit_defaultISM_reverts_underpayment(address sender, bytes32 salt, uint64 gasLimit, uint64 payment) public enrollRouters {
        assumeSender(sender);
        vm.assume(payment < gasLimit * igp.gasPrice());

        // arrange
        vm.deal(sender, payment);

        bytes memory metadata = StandardHookMetadata.formatMetadata(
            0,
            gasLimit,
            sender,
            ""
        );

        // act
        bytes memory bytecode = type(SomeContract).creationCode;
        bytes memory initCode = abi.encodeWithSelector(SomeContract.someFunction.selector);

        vm.prank(sender);
        vm.expectRevert("IGP: insufficient interchain gas payment");
        originRouter.deployContractAndInit{value: payment}(
            destination,
            "",
            salt,
            bytecode,
            initCode,
            metadata
        );
    }

    function testFuzz_deployContract_paramISM(address sender, bytes32 salt) public enrollRouters {
        assumeSender(sender);

        // arrange
        vm.deal(sender, gasPaymentQuote);

        uint256 balanceBefore = address(sender).balance;

        // act
        bytes memory bytecode = type(SomeContract).creationCode;
        vm.prank(sender);
        originRouter.deployContract{value: gasPaymentQuote}(
            destination,
            testIsmB32,
            salt,
            bytecode
        );

        // assert
        uint256 balanceAfter = address(sender).balance;
        assertContractDeployed(sender, salt, type(SomeContract).creationCode, address(testIsm));
        assertIgpPayment(balanceBefore, balanceAfter, igp.getDefaultGasUsage());
    }

    function testFuzz_deployContractAndInit_paramISM(address sender, bytes32 salt) public enrollRouters {
        assumeSender(sender);

        // arrange
        vm.deal(sender, gasPaymentQuote);

        uint256 balanceBefore = address(sender).balance;

        // act
        bytes memory bytecode = type(SomeContract).creationCode;
        bytes memory initCode = abi.encodeWithSelector(SomeContract.someFunction.selector);

        vm.prank(sender);
        originRouter.deployContractAndInit{value: gasPaymentQuote}(
            destination,
            testIsmB32,
            salt,
            bytecode,
            initCode
        );

        // assert
        uint256 balanceAfter = address(sender).balance;
        assertContractDeployedAndInit(sender, salt, type(SomeContract).creationCode, address(testIsm));
        assertIgpPayment(balanceBefore, balanceAfter, igp.getDefaultGasUsage());
    }

    function testFuzz_deployContract_paramISM_customMetadata_forIgp(address sender, bytes32 salt, uint64 gasLimit, uint64 overpayment) public enrollRouters {
        assumeSender(sender);

        // arrange
        uint256 payment = gasLimit * igp.gasPrice() + overpayment;
        vm.deal(sender, payment);

        bytes memory metadata = StandardHookMetadata.formatMetadata(
            0,
            gasLimit,
            sender,
            ""
        );

        uint256 balanceBefore = address(sender).balance;

        // act
        bytes memory bytecode = type(SomeContract).creationCode;
        vm.prank(sender);
        originRouter.deployContract{value: payment}(
            destination,
            testIsmB32,
            salt,
            bytecode,
            metadata
        );

        // assert
        uint256 balanceAfter = address(sender).balance;
        assertContractDeployed(sender, salt, type(SomeContract).creationCode, address(testIsm));
        assertIgpPayment(balanceBefore, balanceAfter, gasLimit);
    }

    function testFuzz_deployContractAndInit_paramISM_customMetadata_forIgp(address sender, bytes32 salt, uint64 gasLimit, uint64 overpayment) public enrollRouters {
        assumeSender(sender);

        // arrange
        uint256 payment = gasLimit * igp.gasPrice() + overpayment;
        vm.deal(sender, payment);

        bytes memory metadata = StandardHookMetadata.formatMetadata(
            0,
            gasLimit,
            sender,
            ""
        );

        uint256 balanceBefore = address(sender).balance;

        // act
        bytes memory bytecode = type(SomeContract).creationCode;
        bytes memory initCode = abi.encodeWithSelector(SomeContract.someFunction.selector);

        vm.prank(sender);
        originRouter.deployContractAndInit{value: payment}(
            destination,
            testIsmB32,
            salt,
            bytecode,
            initCode,
            metadata
        );

        // assert
        uint256 balanceAfter = address(sender).balance;
        assertContractDeployedAndInit(sender, salt, type(SomeContract).creationCode, address(testIsm));
        assertIgpPayment(balanceBefore, balanceAfter, gasLimit);
    }

    function testFuzz_deployContract_WithFailingIsm(address sender, bytes32 salt) public enrollRouters {
        assumeSender(sender);

        // arrange
        string memory failureMessage = "failing ism";
        bytes32 failingIsm = TypeCasts.addressToBytes32(
            address(new FailingIsm(failureMessage))
        );

         // arrange
        vm.deal(sender, gasPaymentQuote);

        // act
        bytes memory bytecode = type(SomeContract).creationCode;
        vm.prank(sender);
        originRouter.deployContract{value: gasPaymentQuote}(
            destination,
            failingIsm,
            salt,
            bytecode
        );

        // assert
        vm.expectRevert(bytes(failureMessage));
        environment.processNextPendingMessage();
    }

    function testFuzz_deployContractAndInit_WithFailingIsm(address sender, bytes32 salt) public enrollRouters {
        assumeSender(sender);

        // arrange
        string memory failureMessage = "failing ism";
        bytes32 failingIsm = TypeCasts.addressToBytes32(
            address(new FailingIsm(failureMessage))
        );

         // arrange
        vm.deal(sender, gasPaymentQuote);

        // act
        bytes memory bytecode = type(SomeContract).creationCode;
        bytes memory initCode = abi.encodeWithSelector(SomeContract.someFunction.selector);

        vm.prank(sender);
        originRouter.deployContractAndInit{value: gasPaymentQuote}(
            destination,
            failingIsm,
            salt,
            bytecode,
            initCode
        );

        // assert
        vm.expectRevert(bytes(failureMessage));
        environment.processNextPendingMessage();
    }

}
