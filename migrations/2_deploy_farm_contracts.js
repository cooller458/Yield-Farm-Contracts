const { BigNumber } = require("@ethersproject/bignumber");
const { getNetworkConfig } = require('../deploy-config')
const MasterBalance = artifacts.require("MasterBalance");
const SupportBalance = artifacts.require("SupportBalance");
const BalanceToken = artifacts.require("BalanceToken");
const BalanceSplitBar = artifacts.require("BalanceSplitBar");
const MultiCall = artifacts.require("MultiCall");
const Timelock = artifacts.require("Timelock");

const logTx = (tx) => {
    console.dir(tx, { depth: 3 });
}

// let block = await web3.eth.getBlock("latest")
module.exports = async function (deployer, network, accounts) {
    const { adminAddress, feeAccount, STARTING_BLOCK, TOKENS_PER_BLOCK, TIMELOCK_DELAY_SECS, INITIAL_MINT } = getNetworkConfig(network, accounts);
    const BLOCKS_PER_HOUR = (3600 / 3) // 3sec Block Time
    const REWARDS_START = String(STARTING_BLOCK + (BLOCKS_PER_HOUR * 6))


    let BalanceTokenInstance;
    let BalanceSplitBarInstance;
    let MasterBalanceInstance;

    /**
     * Deploy BalanceToken
     */
    deployer.deploy(BalanceToken).then((instance) => {
        BalanceTokenInstance = instance;
        /**
         * Mint intial tokens for liquidity pool
         */
        return BalanceTokenInstance.mint(BigNumber.from(INITIAL_MINT).mul(BigNumber.from(String(10 ** 18))));
    }).then((tx) => {
        logTx(tx);
        /**
         * Deploy BalanceSplitBar
         */
        return deployer.deploy(BalanceSplitBar, BalanceToken.address)
    }).then((instance) => {
        BalanceSplitBarInstance = instance;
        /**
         * Deploy MasterBalance
         */
        return deployer.deploy(MasterBalance,
            BalanceToken.address,                                         // _balance
            BalanceSplitBar.address,                                      // _balanceSplit
            feeAccount,                                                   // _devaddr
            BigNumber.from(TOKENS_PER_BLOCK).mul(BigNumber.from(String(10 ** 18))),  // _balancePerBlock
            REWARDS_START,                                                // _startBlock
            4                                                            // _multiplier
        )
    }).then((instance) => {
        MasterBalanceInstance = instance;
        /**
         * TransferOwnership of balance to MasterBalance
         */
        return BalanceTokenInstance.transferOwnership(MasterBalance.address);
    }).then((tx) => {
        logTx(tx);
        /**
         * TransferOwnership of balanceSPLIT to MasterBalance
         */
        return BalanceSplitBarInstance.transferOwnership(MasterBalance.address);
    }).then((tx) => {
        logTx(tx);
        /**
         * Deploy SupportBalance
         */
        return deployer.deploy(SupportBalance,
            BalanceSplitBar.address,                  //_balanceSplit
            BigNumber.from(TOKENS_PER_BLOCK).mul(BigNumber.from(String(10 ** 18))),                                      // _rewardPerBlock
            REWARDS_START,                            // _startBlock
            STARTING_BLOCK + (BLOCKS_PER_HOUR * 24 * 365),  // _endBlock
        )
    }).then(() => {
        /**
         * Deploy MultiCall
         */
        return deployer.deploy(MultiCall);
    }).then(() => {
        /**
         * Deploy Timelock
         */
        return deployer.deploy(Timelock, adminAddress, TIMELOCK_DELAY_SECS);
    }).then(() => {
        console.log('Rewards Start at block: ', REWARDS_START)
        console.table({
            MasterBalance: MasterBalance.address,
            SupportBalance: SupportBalance.address,
            BalanceToken: BalanceToken.address,
            BalanceSplitBar: BalanceSplitBar.address,
            MultiCall: MultiCall.address,
            Timelock: Timelock.address
        })
    });
};
