// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {TestBase} from "forge-std/Base.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";

import {DeployScroll} from "../../../scripts/deterministic/DeployScroll.s.sol";
import {DeterministicDeployment} from "../../../scripts/deterministic/DeterministicDeployment.sol";

// DeployScrollTest tests the deterministic addresses generated by the DeployScroll script.
// This test allows us to detect changes to the deterministic deployment addresses.
contract DeployScrollTest is TestBase, StdAssertions, DeployScroll {
    function setUp() public {
        // use a specific deployment salt
        DEPLOYMENT_SALT = "test-123";

        // skip reading config from file, work with default (empty) values
        DeterministicDeployment.initialize(ScriptMode.EmptyConfig);

        // need to set this to a non-zero address
        L1_PLONK_VERIFIER_ADDR = address(1);
    }

    function testDefaultAddresses() public {
        predictAllContracts();
        checkCommonAddresses();

        assertEq(0xc42A1Bf23C85B87f0630a4aBD179900c96BC2929, L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR);
        assertEq(0x904699c3146cE384a5B47Ebf7Ddf8c592E203F2C, L1_ETH_GATEWAY_PROXY_ADDR);
        assertEq(0x5e27Eea664f5aB1849025195DF2b7e619f904358, L1_WETH_GATEWAY_PROXY_ADDR);
        assertEq(0x0000000000000000000000000000000000000000, L1_GAS_TOKEN_ADDR);
        assertEq(0x0000000000000000000000000000000000000000, L1_GAS_TOKEN_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x0000000000000000000000000000000000000000, L1_GAS_TOKEN_GATEWAY_PROXY_ADDR);
        assertEq(0x0000000000000000000000000000000000000000, L1_WRAPPED_TOKEN_GATEWAY_ADDR);
        assertEq(0x6D7Aff5a2D9bF44cE086199FEF11BD865E089f9d, L2_WETH_GATEWAY_PROXY_ADDR);
        assertEq(0xd7aDC5e99A29f9f76E3F638Fd6a1C5e9692C2d69, L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR);
        assertEq(0x19f984928A8c1c08e7411c29D3ed07694C8905Cb, L1_ETH_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0xFdDfA03a778fE77DDf0E1E479DEdCD1Aea37E808, L1_WETH_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x3DAD8B5526C420Ae43bf1a7125643ea217A220A1, L2_ETH_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0xded0C0D084A9eb3bA7E86dC1C0826A13055F9d7d, L2_WETH_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x9Fea3cb89B6E60b49048b7D66F66c8cD18f28d11, L2_TX_FEE_VAULT_ADDR);
    }

    function testMockFinalizeAddresses() public {
        TEST_ENV_MOCK_FINALIZE_ENABLED = true;

        predictAllContracts();
        checkCommonAddresses();

        assertEq(0xf3f7244F57171A29ed963F8BA1ec48C361BAac67, L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR);
        assertEq(0x904699c3146cE384a5B47Ebf7Ddf8c592E203F2C, L1_ETH_GATEWAY_PROXY_ADDR);
        assertEq(0x5e27Eea664f5aB1849025195DF2b7e619f904358, L1_WETH_GATEWAY_PROXY_ADDR);
        assertEq(0x0000000000000000000000000000000000000000, L1_GAS_TOKEN_ADDR);
        assertEq(0x0000000000000000000000000000000000000000, L1_GAS_TOKEN_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x0000000000000000000000000000000000000000, L1_GAS_TOKEN_GATEWAY_PROXY_ADDR);
        assertEq(0x0000000000000000000000000000000000000000, L1_WRAPPED_TOKEN_GATEWAY_ADDR);
        assertEq(0x6D7Aff5a2D9bF44cE086199FEF11BD865E089f9d, L2_WETH_GATEWAY_PROXY_ADDR);
        assertEq(0xd7aDC5e99A29f9f76E3F638Fd6a1C5e9692C2d69, L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR);
        assertEq(0x19f984928A8c1c08e7411c29D3ed07694C8905Cb, L1_ETH_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0xFdDfA03a778fE77DDf0E1E479DEdCD1Aea37E808, L1_WETH_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x3DAD8B5526C420Ae43bf1a7125643ea217A220A1, L2_ETH_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0xded0C0D084A9eb3bA7E86dC1C0826A13055F9d7d, L2_WETH_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x9Fea3cb89B6E60b49048b7D66F66c8cD18f28d11, L2_TX_FEE_VAULT_ADDR);
    }

    function testAltGasTokenAddresses() public {
        ALTERNATIVE_GAS_TOKEN_ENABLED = true;

        predictAllContracts();
        checkCommonAddresses();

        assertEq(0xc42A1Bf23C85B87f0630a4aBD179900c96BC2929, L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR);
        assertEq(0x0000000000000000000000000000000000000000, L1_ETH_GATEWAY_PROXY_ADDR);
        assertEq(0x0000000000000000000000000000000000000000, L1_WETH_GATEWAY_PROXY_ADDR);
        assertEq(0xd7919F1390711D610961cb27D2BE0BD2Ec1E5704, L1_GAS_TOKEN_ADDR);
        assertEq(0xfFfbB2b3Df00048D4fE12f342D425C98ca709450, L1_GAS_TOKEN_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x4F5264c7a2A14B4D68C40369255A8f07D91D8a68, L1_GAS_TOKEN_GATEWAY_PROXY_ADDR);
        assertEq(0x78664dbFB260D8053f49F1241ffCe06B0C3a533e, L1_WRAPPED_TOKEN_GATEWAY_ADDR);
        assertEq(0x0000000000000000000000000000000000000000, L2_WETH_GATEWAY_PROXY_ADDR);
        assertEq(0xEf4d0C615D480d20475d50A5127e74C9B704E563, L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR);
        assertEq(0x0000000000000000000000000000000000000000, L1_ETH_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x0000000000000000000000000000000000000000, L1_WETH_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0xFA99FF03e6Dd89e12aaF70DA363D02B5Ab5c2d8F, L2_ETH_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x0000000000000000000000000000000000000000, L2_WETH_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x747d2EB150F88EBA24Dc99841baA19E56e2BF901, L2_TX_FEE_VAULT_ADDR);
    }

    function checkCommonAddresses() internal view {
        assertEq(0x157A45eF5dFAb2C26b8905077c08A9F2018f48FD, L1_WETH_ADDR);
        assertEq(0x4Bd916ecac9c5DBd6f15208c8632802Fd2c49e82, L1_PROXY_ADMIN_ADDR);
        assertEq(0x28b7e53497D08F70476001cc41C719e68425D161, L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR);
        assertEq(0x602EEf44E8898cC7Cd2e1f54B01E77B4Ca855b8C, L1_WHITELIST_ADDR);
        assertEq(0x7C68fab1e8c32A321069866b6F1D4403F05C5f44, L1_SCROLL_CHAIN_PROXY_ADDR);
        assertEq(0xC97658507021A2EB494298CAA815B83BC3DE935b, L1_SCROLL_MESSENGER_PROXY_ADDR);
        assertEq(0x02476A470215Bd2F268179492431230C5Dc607C8, L1_ENFORCED_TX_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0xcCBBecF7B9D6e1CD2dF1aEFab510c0697d04AC1f, L1_ENFORCED_TX_GATEWAY_PROXY_ADDR);
        assertEq(0xC74599653677A4795d79CBd6D4a5AE2D4615384D, L1_ZKEVM_VERIFIER_V2_ADDR);
        assertEq(0x4aAD8eF23d69f5b6Ca8bD58A0789950084116baF, L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR);
        assertEq(0x650522433606B6f232cA0C8d0D5245b6571c180a, L1_MESSAGE_QUEUE_IMPLEMENTATION_ADDR);
        assertEq(0x09a4C2780ECBfF76a58957b93ea66D9727eF6A4C, L1_MESSAGE_QUEUE_PROXY_ADDR);
        assertEq(0xd18137D9b43061477C3DA4453E2F3D1B03453efc, L1_GATEWAY_ROUTER_IMPLEMENTATION_ADDR);
        assertEq(0xdE659359688d66932d951A75C31c106D3105a55E, L1_GATEWAY_ROUTER_PROXY_ADDR);
        assertEq(0xeF4e9d1C5CFd6A007D3353E1A7Beed94b645709E, L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR);
        assertEq(0xEf32c7F1326e781b0f04C54883Eedb0d6a9A2646, L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR);
        assertEq(0x0c65C12Ac7490627A84D8A55a08FE0da7C6Ec850, L1_ERC721_GATEWAY_PROXY_ADDR);
        assertEq(0x610b392EBBdA6cf34140ffFD8522D0A01cF4d8A6, L1_ERC1155_GATEWAY_PROXY_ADDR);
        assertEq(0xDEa0476e9F32C3218ADF8823eba61995D5f5558B, L2_MESSAGE_QUEUE_ADDR);
        assertEq(0x70E868415c7532E436d67b7aE417Bd1551142A9d, L1_GAS_PRICE_ORACLE_ADDR);
        assertEq(0xaFbB29CC183006748fBF1d6a50426699801B3f6e, L2_WHITELIST_ADDR);
        assertEq(0x26fE70D2D9aA9f3DF3031A8a36bd7585b56f3e1c, L2_WETH_ADDR);
        assertEq(0x639F9169025652D95b5c30080ee65177ff539e2d, L2_PROXY_ADMIN_ADDR);
        assertEq(0x1454F7362F8b982177b74CAc02F0428ef6044d27, L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR);
        assertEq(0xEE6FE96bA71AdCB8AE724032F7a9DB8A3e7f87E7, L2_SCROLL_MESSENGER_PROXY_ADDR);
        assertEq(0xD855e6939648a2625DDfBE97070Ec7C48FC5F68c, L2_ETH_GATEWAY_PROXY_ADDR);
        assertEq(0xA0E064607751ef6BfC0d1257438aD021962cD641, L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR);
        assertEq(0x96ae0854179483429E89F7507642Aa83B28ebB9e, L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR);
        assertEq(0xc1DC112B26e925Ce0f797Ea6e3438871dc7Be72D, L2_ERC721_GATEWAY_PROXY_ADDR);
        assertEq(0x2B04b351d5BD976A739DE30190bE5fEEf3145C27, L2_ERC1155_GATEWAY_PROXY_ADDR);
        assertEq(0x923e805f714b2cE849DB9D7E76C9C3ddCa907102, L2_SCROLL_STANDARD_ERC20_ADDR);
        assertEq(0x00C080bc75e59b1e56331a5D15FC1aB50766B4D2, L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR);
        assertEq(0x8b284df9bDfC51029323788111ABCf26a2EDcA2C, L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x7d1802E55Bb5563aFAf7Dd196E85Bd5af297EFd9, L1_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x8EC6F24852F44f4d329aC981cAD28c06C99aFCF3, L1_ERC721_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x6a7d33D8eD31dDf30eB9cb0f6DBFF7e18A129959, L1_ERC1155_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x89fE9D485E04097E8eAf2bb3Ed9d61F506c71d1B, L2_SCROLL_MESSENGER_IMPLEMENTATION_ADDR);
        assertEq(0xb2367f9a1F5F190788676743176F2b572F285c91, L2_GATEWAY_ROUTER_IMPLEMENTATION_ADDR);
        assertEq(0x63d77812d2b762F329DB713c0030AC85A388B7f2, L2_GATEWAY_ROUTER_PROXY_ADDR);
        assertEq(0xDbe21F0Cf7c8F4F912cD29f9932311C49975a0b7, L2_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x59afd1A478Cc0336EE8e97d10b6f59E64089eB4D, L2_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x82206B0f4c561e7E4780E824833217D1b371D4a9, L2_ERC721_GATEWAY_IMPLEMENTATION_ADDR);
        assertEq(0x505cf5aEC35CED635Bf24eE5F15B7634D15A2a67, L2_ERC1155_GATEWAY_IMPLEMENTATION_ADDR);
    }
}
