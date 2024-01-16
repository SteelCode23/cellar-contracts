// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IComet } from "src/interfaces/external/Compound/IComet.sol";
import { SupplyAdaptor } from "src/modules/adaptors/Compound/V3/SupplyAdaptor.sol";
import { CollateralAdaptor } from "src/modules/adaptors/Compound/V3/CollateralAdaptor.sol";
import { BorrowAdaptor } from "src/modules/adaptors/Compound/V3/BorrowAdaptor.sol";
import { RewardsAdaptor } from "src/modules/adaptors/Compound/V3/RewardsAdaptor.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract CellarCompoundTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    Cellar private cellar;
    SupplyAdaptor private supplyAdaptor;
    CollateralAdaptor private collateralAdaptor;
    BorrowAdaptor private borrowAdaptor;
    RewardsAdaptor private rewardsAdaptor;
    WstEthExtension private wstethExtension;

    IComet private usdcComet = IComet(cUSDCV3);
    IComet private wethComet = IComet(cWETHV3);

    uint32 private usdcPosition = 1;
    uint32 private wethPosition = 2;
    uint32 private wbtcPosition = 3;
    uint32 private compPosition = 4;
    uint32 private uniPosition = 5;
    uint32 private linkPosition = 6;
    uint32 private wstEthPosition = 7;
    uint32 private cbEthPosition = 8;
    uint32 private rEthPosition = 9;

    // cUSDCV3 Comet
    uint32 private wethCompoundV3CollateralPosition = 101;
    uint32 private wbtcCompoundV3CollateralPosition = 102;
    uint32 private compCompoundV3CollateralPosition = 103;
    uint32 private uniCompoundV3CollateralPosition = 104;
    uint32 private linkCompoundV3CollateralPosition = 105;
    uint32 private usdcCompoundV3SupplyPosition = 106;
    uint32 private usdcCompoundV3DebtPosition = 107;

    // cWETHV3 Comet
    uint32 private wstEthCompoundV3CollateralPosition = 201;
    uint32 private cbEthCompoundV3CollateralPosition = 202;
    uint32 private rEthCompoundV3CollateralPosition = 203;
    uint32 private wethCompoundV3SupplyPosition = 204;
    uint32 private wethCompoundV3DebtPosition = 205;

    uint256 initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        supplyAdaptor = new SupplyAdaptor();
        collateralAdaptor = new CollateralAdaptor(1.05e18, 16);
        borrowAdaptor = new BorrowAdaptor(1.05e18, 16);
        rewardsAdaptor = new RewardsAdaptor(cometRewards);
        wstethExtension = new WstEthExtension(priceRouter);

        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(COMP_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, COMP_USD_FEED);
        priceRouter.addAsset(COMP, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(LINK_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, LINK_USD_FEED);
        priceRouter.addAsset(LINK, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, STETH_USD_FEED);
        priceRouter.addAsset(STETH, settings, abi.encode(stor), price);

        uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
        price = price.mulDivDown(wstethToStethConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));
        priceRouter.addAsset(WSTETH, settings, abi.encode(0), price);

        stor.inETH = true;
        price = uint256(IChainlinkAggregator(UNI_ETH_FEED).latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC);
        price = price.changeDecimals(6, 8);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, UNI_ETH_FEED);
        priceRouter.addAsset(UNI, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(CBETH_ETH_FEED).latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC);
        price = price.changeDecimals(6, 8);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, CBETH_ETH_FEED);
        priceRouter.addAsset(cbETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC);
        price = price.changeDecimals(6, 8);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
        priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

        // Setup Cellar:
        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(supplyAdaptor));
        registry.trustAdaptor(address(collateralAdaptor));
        registry.trustAdaptor(address(borrowAdaptor));
        registry.trustAdaptor(address(rewardsAdaptor));

        // Add ERC20 positions.
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(wbtcPosition, address(erc20Adaptor), abi.encode(WBTC));
        registry.trustPosition(compPosition, address(erc20Adaptor), abi.encode(COMP));
        registry.trustPosition(uniPosition, address(erc20Adaptor), abi.encode(UNI));
        registry.trustPosition(linkPosition, address(erc20Adaptor), abi.encode(LINK));
        registry.trustPosition(wstEthPosition, address(erc20Adaptor), abi.encode(WSTETH));
        registry.trustPosition(cbEthPosition, address(erc20Adaptor), abi.encode(cbETH));
        registry.trustPosition(rEthPosition, address(erc20Adaptor), abi.encode(rETH));

        // Add Compound V3 Supply position.
        registry.trustPosition(usdcCompoundV3SupplyPosition, address(supplyAdaptor), abi.encode(cUSDCV3));
        registry.trustPosition(wethCompoundV3SupplyPosition, address(supplyAdaptor), abi.encode(cWETHV3));

        // Add Compounds V3 Collateral positions.
        registry.trustPosition(wethCompoundV3CollateralPosition, address(collateralAdaptor), abi.encode(cUSDCV3, WETH));
        registry.trustPosition(wbtcCompoundV3CollateralPosition, address(collateralAdaptor), abi.encode(cUSDCV3, WBTC));
        registry.trustPosition(compCompoundV3CollateralPosition, address(collateralAdaptor), abi.encode(cUSDCV3, COMP));
        registry.trustPosition(uniCompoundV3CollateralPosition, address(collateralAdaptor), abi.encode(cUSDCV3, UNI));
        registry.trustPosition(linkCompoundV3CollateralPosition, address(collateralAdaptor), abi.encode(cUSDCV3, LINK));
        registry.trustPosition(
            wstEthCompoundV3CollateralPosition,
            address(collateralAdaptor),
            abi.encode(cWETHV3, WSTETH)
        );
        registry.trustPosition(
            cbEthCompoundV3CollateralPosition,
            address(collateralAdaptor),
            abi.encode(cWETHV3, cbETH)
        );
        registry.trustPosition(rEthCompoundV3CollateralPosition, address(collateralAdaptor), abi.encode(cWETHV3, rETH));

        // Add Compound V3 Debt position.
        registry.trustPosition(usdcCompoundV3DebtPosition, address(borrowAdaptor), abi.encode(cUSDCV3));
        registry.trustPosition(wethCompoundV3DebtPosition, address(borrowAdaptor), abi.encode(cWETHV3));

        string memory cellarName = "Compound Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(true), initialDeposit, platformCut);

        cellar.addAdaptorToCatalogue(address(supplyAdaptor));
        cellar.addAdaptorToCatalogue(address(collateralAdaptor));
        cellar.addAdaptorToCatalogue(address(borrowAdaptor));
        cellar.addAdaptorToCatalogue(address(rewardsAdaptor));

        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(wbtcPosition);
        cellar.addPositionToCatalogue(compPosition);
        cellar.addPositionToCatalogue(uniPosition);
        cellar.addPositionToCatalogue(linkPosition);
        cellar.addPositionToCatalogue(wstEthPosition);
        cellar.addPositionToCatalogue(cbEthPosition);
        cellar.addPositionToCatalogue(rEthPosition);
        cellar.addPositionToCatalogue(wethCompoundV3CollateralPosition);
        cellar.addPositionToCatalogue(wbtcCompoundV3CollateralPosition);
        cellar.addPositionToCatalogue(compCompoundV3CollateralPosition);
        cellar.addPositionToCatalogue(uniCompoundV3CollateralPosition);
        cellar.addPositionToCatalogue(linkCompoundV3CollateralPosition);
        cellar.addPositionToCatalogue(wstEthCompoundV3CollateralPosition);
        cellar.addPositionToCatalogue(cbEthCompoundV3CollateralPosition);
        cellar.addPositionToCatalogue(rEthCompoundV3CollateralPosition);
        cellar.addPositionToCatalogue(usdcCompoundV3SupplyPosition);
        cellar.addPositionToCatalogue(usdcCompoundV3DebtPosition);
        cellar.addPositionToCatalogue(wethCompoundV3SupplyPosition);
        cellar.addPositionToCatalogue(wethCompoundV3DebtPosition);

        USDC.safeApprove(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
    }

    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);

        // Add cUSDCV3 Supply position, and set as holding position.
        cellar.addPosition(0, usdcCompoundV3SupplyPosition, abi.encode(true), false);
        cellar.setHoldingPosition(usdcCompoundV3SupplyPosition);

        // Deposit into Cellar.
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            usdcComet.balanceOf(address(cellar)),
            assets,
            2,
            "Assets should have been deposited into Compound."
        );
    }

    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);

        // Add cUSDCV3 Supply position, and set as holding position.
        cellar.addPosition(0, usdcCompoundV3SupplyPosition, abi.encode(true), false);
        cellar.setHoldingPosition(usdcCompoundV3SupplyPosition);

        // Deposit into Cellar.
        cellar.deposit(assets, address(this));

        // Withdraw from Cellar.
        uint256 amountToWithdraw = cellar.maxWithdraw(address(this));
        cellar.withdraw(amountToWithdraw, address(this), address(this));

        assertApproxEqAbs(USDC.balanceOf(address(this)), assets, 1, "Amount withdrawn should equal assets.");
    }

    function testHappyPathUSDCComet(uint256 assets) external {
        // Use 200 for min assets because the minimum borrow is 100 USDC.
        assets = bound(assets, 200e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);

        // Deposit into Cellar.
        cellar.deposit(assets, address(this));

        // Add required positions.
        cellar.addPosition(0, wethPosition, abi.encode(true), false);
        cellar.addPosition(0, wethCompoundV3CollateralPosition, abi.encode(0), false);
        cellar.addPosition(0, usdcCompoundV3DebtPosition, abi.encode(0), true);

        // Simulate a swap by minting Cellar ERC20s.
        uint256 assetsInWeth = priceRouter.getValue(USDC, assets, WETH);
        deal(address(USDC), address(cellar), initialAssets);
        deal(address(WETH), address(cellar), assetsInWeth);

        // Add collateral and borrow assets.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToSupplyCollateralToCompoundV3(usdcComet, WETH, assetsInWeth);
            data[0] = Cellar.AdaptorCall({ adaptor: address(collateralAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrowBaseFromCompoundV3(usdcComet, assets / 2);
            data[1] = Cellar.AdaptorCall({ adaptor: address(borrowAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 expectedUsdcBalance = initialAssets + assets / 2;
        assertApproxEqAbs(
            USDC.balanceOf(address(cellar)),
            expectedUsdcBalance,
            1,
            "USDC Balance of cellar should equal initialAssets + assets / 2."
        );

        IComet.AssetInfo memory info = usdcComet.getAssetInfo(2);
        uint256 expectedHealthFactor = 2 * info.liquidateCollateralFactor; // HF = assets*LCF / (assets/2) -> HF = 2 * LCF
        uint256 actualHealthFactor = borrowAdaptor.getAccountHealthFactor(usdcComet, address(cellar));
        assertApproxEqRel(actualHealthFactor, expectedHealthFactor, 1e12, "Health Factor should equal expected.");

        // Repay debt, and withdraw collateral.
        data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRepayBaseToCompoundV3(usdcComet, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(borrowAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawCollateralFromCompoundV3(usdcComet, WETH, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(collateralAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 expectedWethBalance = assetsInWeth;
        assertApproxEqAbs(
            WETH.balanceOf(address(cellar)),
            expectedWethBalance,
            1,
            "WETH Balance of cellar should equal assetsInWeth."
        );
    }

    function testHappyPathWETHComet(uint256 assets) external {
        // Compute min assets.
        uint256 minAssets = priceRouter.getValue(WETH, 3 * 0.1e18, USDC);
        assets = bound(assets, minAssets, 1_000_000e6);
        deal(address(USDC), address(this), assets);

        // Deposit into Cellar.
        cellar.deposit(assets, address(this));

        // Add required positions.
        cellar.addPosition(0, wethPosition, abi.encode(true), false);
        cellar.addPosition(0, wstEthCompoundV3CollateralPosition, abi.encode(0), false);
        cellar.addPosition(0, wethCompoundV3DebtPosition, abi.encode(0), true);

        // Simulate a swap by minting Cellar ERC20s.
        uint256 assetsInWsteth = priceRouter.getValue(USDC, assets, WSTETH);
        deal(address(USDC), address(cellar), initialAssets);
        deal(address(WSTETH), address(cellar), assetsInWsteth);

        uint256 assetsToBorrow = priceRouter.getValue(USDC, assets / 2, WETH);

        // Add collateral and borrow assets.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToSupplyCollateralToCompoundV3(wethComet, WSTETH, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(collateralAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrowBaseFromCompoundV3(wethComet, assetsToBorrow);
            data[1] = Cellar.AdaptorCall({ adaptor: address(borrowAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 expectedWethBalance = assetsToBorrow;
        assertApproxEqAbs(
            WETH.balanceOf(address(cellar)),
            expectedWethBalance,
            1,
            "WETH Balance of cellar should equal assetsToBorrow."
        );

        IComet.AssetInfo memory info = wethComet.getAssetInfo(1);
        uint256 expectedHealthFactor = 2 * info.liquidateCollateralFactor; // HF = assets*LCF / (assets/2) -> HF = 2 * LCF
        uint256 actualHealthFactor = borrowAdaptor.getAccountHealthFactor(wethComet, address(cellar));
        // We expect this HF check to need a larger range because we are using very different chainlink pricefeeds when calcualting the borrow amount.
        assertApproxEqRel(actualHealthFactor, expectedHealthFactor, 0.005e18, "Health Factor should equal expected.");

        // Give the cellar some extra WETH dust so it can repay all debt.
        deal(address(WETH), address(cellar), WETH.balanceOf(address(cellar)) + 1);

        // Repay debt, and withdraw collateral.
        data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRepayBaseToCompoundV3(wethComet, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(borrowAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawCollateralFromCompoundV3(wethComet, WSTETH, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(collateralAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 borrowBalance = wethComet.borrowBalanceOf(address(cellar));
        console.log("Borrow Balance", borrowBalance);

        uint256 expectedWstethBalance = assetsInWsteth;
        assertApproxEqAbs(
            WSTETH.balanceOf(address(cellar)),
            expectedWstethBalance,
            1,
            "WSTETH Balance of cellar should equal assetsInWsteth."
        );
    }

    function testMultipleCollateralPositions(uint256 assets) external {
        assets = bound(assets, 100e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);

        // Deposit into Cellar.
        cellar.deposit(assets, address(this));

        uint256 startingTotalAssets = cellar.totalAssets();

        // Add required positions.
        cellar.addPosition(0, wethPosition, abi.encode(true), false);
        cellar.addPosition(0, wbtcPosition, abi.encode(true), false);
        cellar.addPosition(0, compPosition, abi.encode(true), false);
        cellar.addPosition(0, uniPosition, abi.encode(true), false);
        cellar.addPosition(0, linkPosition, abi.encode(true), false);
        cellar.addPosition(0, wethCompoundV3CollateralPosition, abi.encode(0), false);
        cellar.addPosition(0, wbtcCompoundV3CollateralPosition, abi.encode(0), false);
        cellar.addPosition(0, compCompoundV3CollateralPosition, abi.encode(0), false);
        cellar.addPosition(0, uniCompoundV3CollateralPosition, abi.encode(0), false);
        cellar.addPosition(0, linkCompoundV3CollateralPosition, abi.encode(0), false);

        // Simulate a swap by minting Cellar ERC20s.
        deal(address(USDC), address(cellar), initialAssets);
        deal(address(WETH), address(cellar), priceRouter.getValue(USDC, assets / 5, WETH));
        deal(address(WBTC), address(cellar), priceRouter.getValue(USDC, assets / 5, WBTC));
        deal(address(COMP), address(cellar), priceRouter.getValue(USDC, assets / 5, COMP));
        deal(address(UNI), address(cellar), priceRouter.getValue(USDC, assets / 5, UNI));
        deal(address(LINK), address(cellar), priceRouter.getValue(USDC, assets / 5, LINK));

        assertApproxEqRel(cellar.totalAssets(), startingTotalAssets, 1e12, "Cellar Total Assets should be unchanged.");

        // Rebalance Cellar so that is supplied collateral in all available positions.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](5);
            adaptorCalls[0] = _createBytesDataToSupplyCollateralToCompoundV3(usdcComet, WETH, type(uint256).max);
            adaptorCalls[1] = _createBytesDataToSupplyCollateralToCompoundV3(usdcComet, WBTC, type(uint256).max);
            adaptorCalls[2] = _createBytesDataToSupplyCollateralToCompoundV3(usdcComet, COMP, type(uint256).max);
            adaptorCalls[3] = _createBytesDataToSupplyCollateralToCompoundV3(usdcComet, UNI, type(uint256).max);
            adaptorCalls[4] = _createBytesDataToSupplyCollateralToCompoundV3(usdcComet, LINK, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(collateralAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        assertApproxEqRel(cellar.totalAssets(), startingTotalAssets, 1e12, "Cellar Total Assets should be unchanged.");
    }

    function testHealthFactorWithMultipleCollateralPositions(uint256 assets, uint8 borrowDenominator) external {
        borrowDenominator = uint8(bound(borrowDenominator, 2, 10));
        assets = bound(assets, 10_00e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);

        // Deposit into Cellar.
        cellar.deposit(assets, address(this));

        uint256 startingTotalAssets = cellar.totalAssets();

        // Add required positions.
        cellar.addPosition(0, wethPosition, abi.encode(true), false);
        cellar.addPosition(0, wbtcPosition, abi.encode(true), false);
        cellar.addPosition(0, compPosition, abi.encode(true), false);
        cellar.addPosition(0, uniPosition, abi.encode(true), false);
        cellar.addPosition(0, linkPosition, abi.encode(true), false);
        cellar.addPosition(0, wethCompoundV3CollateralPosition, abi.encode(0), false);
        cellar.addPosition(0, wbtcCompoundV3CollateralPosition, abi.encode(0), false);
        cellar.addPosition(0, compCompoundV3CollateralPosition, abi.encode(0), false);
        cellar.addPosition(0, uniCompoundV3CollateralPosition, abi.encode(0), false);
        cellar.addPosition(0, linkCompoundV3CollateralPosition, abi.encode(0), false);
        cellar.addPosition(0, usdcCompoundV3DebtPosition, abi.encode(0), true);

        // Simulate a swap by minting Cellar ERC20s.
        uint256 valueForEachCollateral = assets / 5;
        deal(address(USDC), address(cellar), initialAssets);
        deal(address(WETH), address(cellar), priceRouter.getValue(USDC, valueForEachCollateral, WETH));
        deal(address(WBTC), address(cellar), priceRouter.getValue(USDC, valueForEachCollateral, WBTC));
        deal(address(COMP), address(cellar), priceRouter.getValue(USDC, valueForEachCollateral, COMP));
        deal(address(UNI), address(cellar), priceRouter.getValue(USDC, valueForEachCollateral, UNI));
        deal(address(LINK), address(cellar), priceRouter.getValue(USDC, valueForEachCollateral, LINK));

        assertApproxEqRel(cellar.totalAssets(), startingTotalAssets, 1e12, "Cellar Total Assets should be unchanged.");

        uint256 assetsToBorrow = assets / borrowDenominator;

        // Rebalance Cellar so that is supplied collateral in all available positions.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](5);
            adaptorCalls[0] = _createBytesDataToSupplyCollateralToCompoundV3(usdcComet, WETH, type(uint256).max);
            adaptorCalls[1] = _createBytesDataToSupplyCollateralToCompoundV3(usdcComet, WBTC, type(uint256).max);
            adaptorCalls[2] = _createBytesDataToSupplyCollateralToCompoundV3(usdcComet, COMP, type(uint256).max);
            adaptorCalls[3] = _createBytesDataToSupplyCollateralToCompoundV3(usdcComet, UNI, type(uint256).max);
            adaptorCalls[4] = _createBytesDataToSupplyCollateralToCompoundV3(usdcComet, LINK, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(collateralAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrowBaseFromCompoundV3(usdcComet, assetsToBorrow);
            data[1] = Cellar.AdaptorCall({ adaptor: address(borrowAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 expectedHealthFactor = 0;
        for (uint8 i = 0; i < 5; ++i) {
            IComet.AssetInfo memory info = usdcComet.getAssetInfo(i);
            expectedHealthFactor += valueForEachCollateral.mulDivDown(info.liquidateCollateralFactor, 1e18);
        }
        expectedHealthFactor = expectedHealthFactor.mulDivDown(1e18, assetsToBorrow);
        uint256 actualHealthFactor = borrowAdaptor.getAccountHealthFactor(usdcComet, address(cellar));

        // Note we are within 10 bps of precision with our HF calcualtions, which is perfectly fine for 2 reasons
        // 1) We are not using compounds pricing when determining how much collateral valueForEachCollateral is.
        // 2) We enforce a minimum health factor of 1.05e18, so even if we were off by 1%, our worst case Health Factor would be 1.0395.
        assertApproxEqRel(actualHealthFactor, expectedHealthFactor, 0.001e18, "Health Factor should equal expected.");
        assertApproxEqRel(cellar.totalAssets(), startingTotalAssets, 1e12, "Cellar Total Assets should be unchanged.");
    }

    function testClaimingRewards() external {
        uint256 assets = 1_000_000e6;
        deal(address(USDC), address(this), assets);

        // Add cUSDCV3 Supply position, and set as holding position.
        cellar.addPosition(0, usdcCompoundV3SupplyPosition, abi.encode(true), false);
        cellar.setHoldingPosition(usdcCompoundV3SupplyPosition);

        // Deposit into Cellar.
        cellar.deposit(assets, address(this));

        skip(1 days / 6);

        // Claim rewards.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToClaimRewardsFromCompoundV3(usdcComet);
            data[0] = Cellar.AdaptorCall({ adaptor: address(rewardsAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        // Note we do not check that the cellar received COMP rewards bc at the time of this fork, no COMP rewards are flowing for suppling assets
        // if you change the fork block number to a more recent block number, then you can check that COMP rewards accrue, but the multi collateral tests will fail
        // because their supply caps are already filled.

        // If strategist tries to pass in a malicious comet address, rebalance reverts.
        address maliciousComet = vm.addr(5);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToClaimRewardsFromCompoundV3(IComet(maliciousComet));
            data[0] = Cellar.AdaptorCall({ adaptor: address(rewardsAdaptor), callData: adaptorCalls });
        }
        vm.expectRevert();
        cellar.callOnAdaptor(data);
    }
    // TODO test checking a strategist trying to use untrusted input args.
    // TODO create a new adaptor, set max number of assets to be at current comets asset count, then add one mor, and make sure we can unwind from the position.
}
