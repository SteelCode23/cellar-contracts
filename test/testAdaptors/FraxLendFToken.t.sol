// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { FTokenAdaptor, IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract FraxLendFTokenAdaptorTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    ERC20Adaptor private erc20Adaptor;
    FTokenAdaptor private fTokenAdaptor;
    CellarInitializableV2_2 private cellar;
    PriceRouter private priceRouter;
    Registry private registry;

    address private immutable strategist = vm.addr(0xBEEF);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 public FRAX = ERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);

    // FraxLend fToken markets.
    address private FXS_FRAX_MARKET = 0xDbe88DBAc39263c47629ebbA02b3eF4cf0752A72;

    // Chainlink PriceFeeds
    address private FRAX_USD_FEED = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;

    uint32 private fraxPosition;
    uint32 private fxsFraxMarketPosition;

    modifier checkBlockNumber() {
        if (block.number < 16869780) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 16869780.");
            return;
        }
        _;
    }

    function setUp() external {
        fTokenAdaptor = new FTokenAdaptor();
        erc20Adaptor = new ERC20Adaptor();

        registry = new Registry(address(this), address(this), address(priceRouter));
        priceRouter = new PriceRouter(registry);
        registry.setAddress(2, address(priceRouter));

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(FRAX_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, FRAX_USD_FEED);
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(fTokenAdaptor));

        fraxPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(FRAX));
        fxsFraxMarketPosition = registry.trustPosition(address(fTokenAdaptor), abi.encode(FXS_FRAX_MARKET));

        cellar = new CellarInitializableV2_2(registry);
        cellar.initialize(
            abi.encode(
                address(this),
                registry,
                FRAX,
                "Fraximal Cellar",
                "oWo",
                fxsFraxMarketPosition,
                abi.encode(0),
                strategist
            )
        );

        cellar.addAdaptorToCatalogue(address(fTokenAdaptor));

        cellar.addPositionToCatalogue(fraxPosition);

        FRAX.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));
    }

    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Only withdraw assets - 1 because p2pSupplyIndex is not updated, so it is possible
        // for totalAssets to equal assets - 1.
        cellar.withdraw(assets - 2, address(this), address(this));
    }

    function testTotalAssets(uint256 assets) external {
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(cellar.totalAssets(), assets, 2, "Total assets should equal assets deposited.");
    }

    function testLendingFrax(uint256 assets) external {
        // Add FRAX position and change holding position to vanilla FRAX.
        cellar.addPosition(0, fraxPosition, abi.encode(0), false);
        cellar.setHoldingPosition(fraxPosition);

        // Have user deposit into cellar.
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to lend FRAX.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Lend FRAX on FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(FXS_FRAX_MARKET, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        IFToken market = IFToken(FXS_FRAX_MARKET);
        uint256 shareBalance = market.balanceOf(address(cellar));
        assertTrue(shareBalance > 0, "Cellar should own shares.");
        assertApproxEqAbs(
            market.toAssetAmount(shareBalance, false),
            assets,
            2,
            "Rebalance should have lent all FRAX on FraxLend."
        );
    }

    function testWithdrawingFrax(uint256 assets) external {
        // Add vanilla FRAX as a position in the cellar.
        cellar.addPosition(0, fraxPosition, abi.encode(0), false);

        // Have user deposit into cellar.
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to withdraw FRAX.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Withdraw FRAX from FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRedeem(FXS_FRAX_MARKET, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            FRAX.balanceOf(address(cellar)),
            assets,
            2,
            "Cellar FRAX should have been withdraw from FraxLend."
        );
    }

    function testRebalancingBetweenMarkets() external {}

    function testUsingMarketNotSetupAsPosition() external {}

    // ========================================= HELPER FUNCTIONS =========================================

    function _createBytesDataToLend(address fToken, uint256 amountToDeposit) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.lendFrax.selector, fToken, amountToDeposit);
    }

    function _createBytesDataToRedeem(address fToken, uint256 amountToRedeem) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.redeemFraxShare.selector, fToken, amountToRedeem);
    }
}
