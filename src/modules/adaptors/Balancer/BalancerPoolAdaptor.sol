// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {BaseAdaptor, ERC20, SafeTransferLib, Cellar, SwapRouter, Registry} from "src/modules/adaptors/BaseAdaptor.sol";
import {IBalancerQueries} from "src/interfaces/external/Balancer/IBalancerQueries.sol";
import {IVault} from "src/interfaces/external/Balancer/IVault.sol";
import {IBalancerRelayer} from "src/interfaces/external/Balancer/solidity-utils/IBalancerRelayer.sol";
import {IStakingLiquidityGauge} from "src/interfaces/external/Balancer/IStakingLiquidityGauge.sol";
import {IBalancerRelayer} from "src/interfaces/external/Balancer/IBalancerRelayer.sol";
import {ILiquidityGaugeFactory} from "src/interfaces/external/Balancer/ILiquidityGaugeFactory.sol";
import {ILiquidityGaugev3Custom} from "src/interfaces/external/Balancer/ILiquidityGaugev3Custom.sol";

/**
 * @title Balancer Pool Adaptor
 * @notice Allows Cellars to interact with Weighted, Stable, and Linear Balancer Pools (BPs).
 * @author 0xEinCodes and CrispyMangoes
 * TODO: This contract is still a WIP, Still need to go through TODOs and resolve relevant github issues
 * TODO: Add event emissions where necessary
 */
contract BalancerPoolAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(ERC20 _bpt)
    // Where:
    // `_bpt` is the Balancer pool token of the Balancer LP market this adaptor is working with
    // `_poolId` is the pool identifier used within the Balancer vault system
    // `_request`is a struct of data used to agnostically joinPools of various types. See https://docs.balancer.fi/reference/joins-and-exits/pool-joins.html#api && https://docs.balancer.fi/reference/joins-and-exits/pool-exits.html for joins and exits.
    // strategist must specify details in `_request`. See 1-pager made to assist constructing queries.
    // ex.)
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // n/a
    // =================================

    // NOTE: JoinPoolRequest is what strategists will need to provide
    // When providing your assets, you must ensure that the tokens are sorted numerically by token address. It's also important to note that the values in maxAmountsIn correspond to the same index value in assets, so these arrays must be made in parallel after sorting.
    // NOTE: different JoinKinds for different pool types: to start, we'll focus on WeightedPools & StablePools. The idea: Strategists pass in the JoinKinds within their calls, so they need to know what type of pool they are joining. Alt: we could query to see what kind of pool it is, but strategist still needs to specify the type of tx this is.

    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    /**
     * @notice The Balancer Vault contract on Ethereum Mainnet.
     * @return address adhereing to IVault
     */
    function vault() internal pure returns (IVault) {
        return IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    }

    // /**
    //  * @notice the BalancerQueries address on all networks
    //  * @return address adhering to IBalancerQueries
    //  */
    // function balancerQueries() internal pure returns (IBalancerQueries) {
    //     return 0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5;
    // }

    function relayer() internal pure returns (IBalancerRelayer relayer) {
        return IBalancerRelayer(0xfeA793Aa415061C483D2390414275AD314B3F621);
    }

    function gaugeFactory() internal pure returns (ILiquidityGaugeFactory gaugeFactory) {
        return ILiquidityGaugeFactory(0x4E7bBd911cf1EFa442BC1b2e9Ea01ffE785412EC);
    }

    //==================== TODO: Adaptor Data Specification ====================
    // See Related Open Issues on this for BalancerPoolAdaptor.sol
    //================= Configuration Data Specification =================
    // NOT USED
    //====================================================================

    /**
     * @notice bptOut lower than desired
     */
    error BalancerPoolAdaptor__BPTOutTooLow();

    /**
     * @notice no claimable reward tokens
     */
    error BalancerPoolAdaptor__ZeroClaimableRewards();

    /**
     * @notice max slippage exceeded
     */
    error BalancerPoolAdaptor__MaxSlippageExceeded();

    /**
     * @notice bpt amount to unstake/withdraw requested exceeds amount actuall staked/deposited in liquidity gauge
     */
    error BalancerPoolAdaptor__NotEnoughToWithdraw();

    /**
     * @notice bpt amount to unstake/withdraw requested exceeds amount actuall staked/deposited in liquidity gauge
     */
    error BalancerPoolAdaptor__NotEnoughToDeposit();

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this identifier is needed during Cellar Delegate Call Operations, so getting the address of the adaptor is more difficult.
     * @return encoded adaptor identifier
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Balancer Pool Adaptor V 1.0"));
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice User deposits are NOT allowed into this position.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice This position is a liquidity provision (credit) position, and user withdraws are not allowed so this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the cellars balance of the positions debtToken.
     * TODO: make sure it is checking balanceOf && staked tokens
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        // TODO: decode adaptorData for poolGauge address
        address bpt = abi.decode(adaptorData, (address));

        ILiquidityGauge poolGauge = gaugeFactory().getPoolGauge(bpt);

        uint256 stakedBPT = poolGauge.balanceOf(address(this));
        return ERC20(token).balanceOf(msg.sender) + stakedBPT;
    }

    /**
     * @notice Returns the positions underlying assets.
     * @param adaptorData specified bpt of interest
     * @return constituent assets making up the respective bpt
     * NOTE: From looking through the Registry, when setting up an adaptorPosition, we will need to make sure that pricing for all assets involved is set up.
     * TODO: Resolve the longer comments in this function within draft PR #112
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IERC20 bpt = IERC20(abi.decode(adaptorData, (address))); // TODO: not sure if bpts have special ERC20 like cERC20 for compound

        return ERC20(bpt); // TODO: confirm if this should be all underlying assets or just the bpt.
            // TODO: I think we actually use vault.getPoolTokens(bytes32 poolId) to get the addresses of constituent tokens involved.
            // TODO: Trickier situations where we want to enter boosted pools, or other pools w/ nested pools, are resolved by using the relayer() w/ multicall and calldata. So in the registry, we'd register the position where we state the boosted pool address, and the PriceRouter would have to know how to break it into constituent parts... vault.getPoolTokens() gives linear pool tokens I think, not all the underlying tokens. If that's the case, then we need to go deeper into the constituent tokens to get the base tokens, or use a CSP-specific extension for the priceRouter.

        // _accounting() is called via totalAssets() during rebalance calls and whatnot on the cellar.

        // TODO: Hmm, this raises the question of how bpts are being priced. CSPs consist of linear pool tokens, which have underlying tokens themselves. So will we need an extension to calculate the constituents of a CSP? I guess we'd pass in the 1st layer constituents (linear pool tokens) of a CSP to the priceRouter and go from there?
    }

    /**
     * @notice When positions are added to the Registry, this function can be used in order to figure out
     *         what assets this adaptor needs to price, and confirm pricing is properly setup.
     * @dev COMP is used when claiming COMP and swapping.
     */
    function assetsUsed(bytes memory adaptorData) public view override returns (ERC20[] memory assets) {
        assets = new ERC20[](2);
        assets[0] = assetOf(adaptorData);
        assets[1] = COMP();
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     * @return whether adaptor returns debt or not
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice call `BalancerRelayer` on mainnet to carry out txs that can incl. joins, exits, and swaps
     * @param tokensIn specific tokens being input for tx
     * @param amountsIn amount of assets input for tx
     * @param bptOut acceptable amount of assets resulting from tx (due to slippage, etc.)
     * @param callData encoded specific txs to be used in `relayer.multicall()`
     * NOTE: The difference btw what Balancer outlines to do and what we want to do is that we want the txs to be carried out by the vault. Whereas we could just end up connecting to the relayer and have it carry out multi-txs which would be bad cause we need to confirm each step of the multi-call.
     * TODO: rename params and possibly include others for `exit()` function. ex.) bptOut needs to be renamed to be agnostic.
     * TODO: see issue for strategist callData
     * TODO: see discussion in draft PR #112 about `approve()` details
     */
    function useRelayer(ERC20[] memory tokensIn, uint256[] memory amountsIn, ERC20 bptOut, bytes[] memory callData)
        public
    {
        for (uint256 i; i < tokensIn.length; ++i) {
            tokensIn[i].approve(vault(), amountsIn[i]);
        } // TODO: this may be obsolete based on approval steps necessary for relayer functionality (see TODO below)

        uint256 startingBpt = BPTout.balanceOf(address(this));

        // TODO: implement proper way of giving Relayer approval; Relayer.setRelayerApproval() or Relayer.approveVault().

        relayer().multicall(callData);

        uint256 endingBpt = BPTout.balanceOf(address(this));

        uint256 amountBptOut = endingBpt - startingBpt;

        uint256 amountBptIn = priceRouter.getValues(tokensIn, amountsIn, bptOut);

        // check value in vs value out
        if (amountBptOut < amountBptIn.mulDivDown(slippage(), 1e4)) revert("Slippage");

        // revoke token in approval
        for (uint256 i; i < tokensIn.length; ++i) {
            _revokeExternalApproval(tokensIn[i], relayer());
        }

        // TODO: see if special revocation is required or necessary with bespoke Relayer approval sequences
    }

    /**
     * @notice deposit (stake) BPTs into respective pool gauge
     * @param _bpt address of BPTs to deposit
     * @param _amountIn number of BPTs to deposit
     * @param _claim_rewards whether or not to claim pending rewards too (true == claim)
     * @dev Interface custom as Balancer/Curve do not provide for liquidityGauges.
     * TODO: Finalize interface details when beginning to do unit testing
     */
    function depositBPT(address _bpt, uint256 _amountIn, bool _claim_rewards) external {
        IERC20 bpt = IERC20(_bpt);
        uint256 amountIn = _maxAvailable(address(bpt), _amountIn);

        ILiquidityGaugev3Custom poolGauge = gaugeFactory().getPoolGauge(_bpt);
        uint256 amountStakedBefore = poolGauge.balanceOf(address(this));

        bpt.approve(_poolGauge, amountIn);
        poolGauge.deposit(amountIn, address(this), _claim_rewards); // address(this) is cellar address bc delegateCall
        uint256 actualAmountStaked = poolGauge.balanceOf(address(this)) - amountStakedBefore;

        _revokeExternalApproval(address(bpt), _poolGauge);
    }

    /**
     * @notice withdraw (unstake) BPT from respective pool gauge
     * @param _bpt address of BPTs to withdraw
     * @param _amountOut number of BPTs to withdraw
     * @param _claim_rewards whether or not to claim pending rewards too (true == claim)
     * @dev Interface custom as Balancer/Curve do not provide for liquidityGauges.
     */
    function withdrawBPT(address _bpt, uint256 _amountOut, bool _claim_rewards) external {

        ILiquidityGaugev3Custom poolGauge = gaugeFactory().getPoolGauge(_bpt);
        uint256 amountOut = _maxAvailable(ERC20(address(poolGauge)), _amountOut); // get the total amount of bpt staked by the cellar essentially (bc it's represented by the amount of gauge tokens the Cellar has)

        IERC20 bpt = IERC20(_bpt);
        uint256 unstakedBPTBefore = bpt.balanceOf(address(this));

        bpt.approve(_poolGauge, amountOut);
        poolGauge.withdraw(amountOut, _claim_rewards); // msg.sender should be cellar address bc delegateCall. TODO: see issue # <> and confirm address.

        uint256 actualWithdrawn = bpt.balanceOf(address(this)) - unstakedBPTBefore;

        _revokeExternalApproval(bpt, _poolGauge);
    }

    /**
     * @notice claim rewards ($BAL and/or other tokens) from LP position
     * @notice Have the strategist provide the address for the pool gauge
     * @dev rewards are only accrue for staked positions
     * @param _bpt associated BPTs for respective reward gauge
     * @param _rewardToken address of reward token, if not $BAL, that strategist is claiming
     * TODO: make all verbose text here into github issues or remove them after discussion w/ Crispy
     * TODO: add checks throughout function
     */
    function claimRewards(address _bpt, address _rewardToken) public {
        ILiquidityGaugev3Custom poolGauge = gaugeFactory().getPoolGauge(bpt);

        // TODO: checks - though, I'm not sure we need these. If cellar calls `claim_rewards()` and there's no rewards for them then... there are no explicit reverts in the codebase but I assume it reverts. Need to test it though: https://github.com/balancer/balancer-v2-monorepo/blob/master/pkg/liquidity-mining/contracts/gauges/ethereum/LiquidityGaugeV5.vy#L440-L450:~:text=if%20total_claimable%20%3E%200%3A

        // TODO: include `claimable_rewards` in next BalancerAdaptor (other tokens on mainnet) that will be used for non-mainnet chains.
        if (poolGauge.claimable_reward(address(this), rewardToken) && poolGauge.claimable_tokens(address(this)) == 0) {
            revert BalancerPoolAdaptor__ZeroClaimableRewards();
        }

        poolGauge.claim_rewards(address(this), address(0));
    }
}
